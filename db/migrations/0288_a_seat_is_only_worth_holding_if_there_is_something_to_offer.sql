-- migration-version: PENDING
-- migration-name:    0288_a_seat_is_only_worth_holding_if_there_is_something_to_offer
--
-- 0288  A SEAT IS ONLY WORTH HOLDING IF THERE IS SOMETHING TO OFFER
--
-- ############################################################################
-- HELD. DRAFTED, DRY-RUN, AND DELIBERATELY NOT APPLIED. See db/checks/0223.
--
-- This file was written believing saturation explained every unanswered seat.
-- The second post-fix run was then checked and it does not: of the twenty
-- unanswered seats across both runs, 7 are saturation and 13 are CADENCE --
-- the proposer never fired inside the seat's one tick at all. On run 36e5cc68
-- the separation is perfect: every seat armed at a tick the loop fired on was
-- answered (15 of 15, including one where a single charge stall was free), and
-- every seat armed at a tick it did not fire on went unanswered (12 of 12).
--
-- Three reasons this is not applied tonight:
--   1. Its justification shrank from "all twenty" to "seven of twenty".
--   2. Fixing cadence moves where seats are armed and whether they are
--      answered, so this guard's value can only be sized honestly afterwards.
--      Tuning against a number that is about to move is how a change gets
--      credited with someone else's improvement.
--   3. It edits the DECIDE PATH, the one place where "small, safe and probably
--      fine" is not a good enough reason to ship.
--
-- Everything below is kept as drafted, measurements intact, so it can be
-- re-argued rather than re-derived once G58 (cadence) is closed.
-- ############################################################################
--
-- 0219 filed G54 as "the hold has no liveness check" and proposed asking
-- whether a proposer is alive. 0221 showed the proposer was very much alive and
-- the two halves simply disagreed about "already placed"; 0287 fixed that and
-- 0222 measured the answer rate move off zero for the first time.
--
-- 0222 also named what the fix did NOT touch, and this file is that:
--
--   run 1bd41105, every seat it armed, against the charge stalls busy at the
--   same tick (from ottoq_proposer_fire_log, same run, same tick):
--
--     arm tick  seats  charge stalls busy  answered?
--            2      1              40 / 40  no
--            4      6              40 / 40  no
--           16      2          (no fire)    YES
--           18      2               7 / 40  YES
--
--   All SEVEN unanswered seats were armed into a depot where not one of the
--   forty charge stalls was free. Both answered ticks had capacity. With zero
--   free charge points there is no proposal ANY proposer could make, so the
--   seat costs the vehicle a decide tick of latency and can buy nothing.
--
-- That is the liveness check 0219 reached for, with the predicate it should
-- have had: not "is a proposer alive" but "is there anything to propose".
--
-- ---------------------------------------------------------------------------
-- THE PREDICATE, AND WHY IT IS DELIBERATELY WEAKER THAN `offerable`
--
-- The frame's `offerable` (0265/L-61) is the strict test: unoccupied, unexpired
-- reservation, a charger that exists, station_state Available, and a heartbeat
-- fresher than 90 seconds. It would be the tighter guard. IT MUST NOT BE USED
-- HERE, and the reason is the defect class this repo keeps re-finding:
--
--   ottoq_cuopt_first_refusal_arm is in the DECIDE PATH. Putting a heartbeat
--   freshness test inside the decide path would make the kernel's assignment
--   behaviour depend on OCPP heartbeat timing -- a new input to a path that is
--   certified byte-identical. That is G15's defect (the L1 shield reading the
--   wall clock) with a different clock.
--
-- So the guard uses only the PHYSICAL, run-scoped, sim-clock-resolved half:
--
--     a charge stall with no vehicle on it and no live reservation
--
-- which is a NECESSARY condition for any proposal to be enactable, reads only
-- `stalls`, and compares against v_sim -- the same clock this function already
-- uses for its own reservation test three lines below. A stall that is free but
-- whose charger is faulted still passes, so the guard fires strictly less often
-- than the strict test would: it only ever refuses to arm when the situation is
-- unambiguous.
--
-- FAIL-OPEN, like every other branch of this machinery. Refusing to arm means
-- the vehicle is NOT held, so the greedy cursor serves it this tick instead of
-- next. The change can only ever make a vehicle's assignment earlier.
--
-- ---------------------------------------------------------------------------
-- forces_recert = false, AND THE ARGUMENT IS ONE ROW
--
-- ottoq_cuopt_first_refusal_arm's FIRST gate is
--
--     v_cap := GREATEST(0, ottoq_policy_get(p_sim_run_id,
--                          'cuopt_first_refusal_max_defers', 1)::int);
--     IF v_cap = 0 THEN RETURN 0; END IF;
--
-- and 0152 set the GLOBAL row for that key to 0 (measured: 1 global row at 0,
-- 632 run rows at 0, 7 run rows at 1 -- the seven armed proposer runs). A
-- certification arm writes no run row, so it resolves to the global 0 and
-- returns before reaching anything this file adds. P1 pins that row. The guard
-- is inserted AFTER the cap check, never before it, and A3 pins that ordering
-- in the source.
--
-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0288 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0288 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0288 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0288 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

-- P0. THE ARM IS THE ONE THIS FILE WAS WRITTEN AGAINST ----------------------
DO $p0$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cuopt_first_refusal_arm';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0288 P0: public.ottoq_cuopt_first_refusal_arm does not exist';
  END IF;
  IF position('''cuopt_first_refusal_max_defers'', 1)::int' in v_src) = 0
     OR position('IF v_cap = 0 THEN RETURN 0; END IF;' in v_src) = 0 THEN
    RAISE EXCEPTION '0288 P0: the cap gate changed shape; the forces_recert=false '
                    'argument depends on it returning before anything else runs';
  END IF;
  IF position('v.current_state = ''arrived_at_gate''' in v_src) = 0
     OR position('s.stall_type::text IN (''dcfc'',''l2'')' in v_src) = 0 THEN
    RAISE EXCEPTION '0288 P0: the Zone guard or the charge-type literal changed; '
                    'this file was written against both';
  END IF;
  IF position('ottoq_depot_has_free_charge_point' in v_src) > 0 THEN
    RAISE EXCEPTION '0288 P0: the guard is already present; this file has run';
  END IF;
  RAISE NOTICE '0288 P0: arm is unmodified, cap gate first, guard not yet present';
END $p0$;

-- P1. THE forces_recert=false ARGUMENT, AS ONE MEASURED ROW -----------------
DO $p1$
DECLARE v_global numeric; v_n int;
BEGIN
  SELECT param_value INTO v_global FROM public.ottoq_policy_params
   WHERE param_key = 'cuopt_first_refusal_max_defers' AND scope_type = 'global';
  IF v_global IS NULL THEN
    RAISE EXCEPTION '0288 P1: there is no GLOBAL cuopt_first_refusal_max_defers row, '
                    'so a certification arm would fall through to the caller default '
                    'of 1 and REACH the code this file changes';
  END IF;
  IF v_global <> 0 THEN
    RAISE EXCEPTION '0288 P1: the global cuopt_first_refusal_max_defers is %, not 0; '
                    'a certification arm would arm seats and this file DOES force '
                    'recert', v_global;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key = 'cuopt_first_refusal_max_defers' AND scope_type = 'run'
     AND param_value >= 1;
  RAISE NOTICE '0288 P1: global tier is 0; % run row(s) opt in explicitly', v_n;
END $p1$;

-- P2. THE DEPOT CAN ACTUALLY BE SATURATED ----------------------------------
-- If a depot has no charge stalls at all the guard would refuse every arm
-- forever, which is not a fix, it is an off switch. Assert the flagship has
-- charge stalls to be free.
DO $p2$
DECLARE v_chg int;
BEGIN
  SELECT count(*) INTO v_chg FROM public.stalls
   WHERE depot_id = '11111111-1111-1111-1111-111111111111'
     AND stall_type::text IN ('dcfc','l2');
  IF v_chg = 0 THEN
    RAISE EXCEPTION '0288 P2: the flagship depot has no charge stalls; the guard '
                    'would refuse every arm unconditionally';
  END IF;
  RAISE NOTICE '0288 P2: % charge stalls at the flagship depot', v_chg;
END $p2$;

-- ---------------------------------------------------------------------------
-- THE PREDICATE, IN ONE PLACE
CREATE OR REPLACE FUNCTION public.ottoq_depot_has_free_charge_point(
  p_depot_id uuid, p_at timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  --: 0288. Is there a charge point at this depot that nothing is standing on
  --: and nothing holds a live reservation for? A NECESSARY condition for any
  --: proposal to be enactable, and therefore for a first-refusal seat to be
  --: worth holding.
  --:
  --: DELIBERATELY NOT the frame's `offerable`, which also requires a healthy
  --: charger and a heartbeat under 90 seconds old. This function is called from
  --: the DECIDE PATH, and a heartbeat freshness test there would make kernel
  --: assignment depend on OCPP timing -- G15's defect with a different clock.
  --: Weaker means it says "yes" more often, which means it changes behaviour
  --: less often, which is the safe direction for a guard that suppresses a hold.
  --:
  --: p_at is the caller's clock and MUST be the sim clock inside a twin run.
  --:
  --: ONE ASYMMETRY, CHOSEN RATHER THAN INHERITED. A reservation with a NULL
  --: expires_at is read three different ways in this database already:
  --:   ottoq_cuopt_first_refusal_arm  COALESCE(expires_at, v_sim) >= v_sim  -> LIVE
  --:   frame `reservation_live`       COALESCE(expires_at,'infinity') > clk -> LIVE
  --:   frame `offerable`              COALESCE(expires_at,'-infinity')<= clk-> FREE
  --: This function follows `offerable` and calls a NULL expiry FREE. Not because
  --: that reading is more correct -- the three disagree and that is its own
  --: finding -- but because it is the direction that makes this guard say YES
  --: more often, so it suppresses fewer holds and changes less behaviour. A
  --: guard should round toward doing nothing.
  SELECT EXISTS (
    SELECT 1 FROM stalls s
     WHERE s.depot_id = p_depot_id
       AND s.stall_type::text IN ('dcfc','l2')
       AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL
            OR COALESCE(s.reservation_expires_at, '-infinity'::timestamptz) <= p_at));
$function$;

COMMENT ON FUNCTION public.ottoq_depot_has_free_charge_point(uuid, timestamptz) IS
'0288: true iff some dcfc/l2 stall at this depot is unoccupied and unreserved at
p_at. The necessary condition for a first-refusal seat to be worth holding.
Deliberately weaker than the frame''s `offerable`: no charger health, no
heartbeat window, because this is called from the decide path and a heartbeat
test there would be G15 with a different clock.';

-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_cuopt_first_refusal_arm(p_sim_run_id uuid, p_tick bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_depot uuid; v_sim timestamptz; v_cap int; v_ids uuid[]; v_n int := 0;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;

  -- STARVATION BOUND + OFF SWITCH, both policy-tunable per run.
  v_cap := GREATEST(0, ottoq_policy_get(p_sim_run_id, 'cuopt_first_refusal_max_defers', 1)::int);
  IF v_cap = 0 THEN RETURN 0; END IF;

  SELECT depot_id, COALESCE(sim_clock_current, now()) INTO v_depot, v_sim
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;

  -- 0288: A SEAT IS ONLY WORTH HOLDING IF THERE IS SOMETHING TO OFFER.
  -- Measured on run 1bd41105: all seven seats that went unanswered were armed
  -- into a depot with 0 of 40 charge stalls free, and both ticks that produced
  -- an answer had capacity. With no free charge point there is no proposal any
  -- proposer could make, so the hold costs the vehicle a decide tick and buys
  -- nothing. Fails OPEN: not arming means greedy serves the vehicle THIS tick
  -- instead of next, so this branch can only ever make an assignment earlier.
  IF NOT public.ottoq_depot_has_free_charge_point(v_depot, v_sim) THEN
    RETURN 0;
  END IF;

  SELECT COALESCE(array_agg(v.id), ARRAY[]::uuid[]) INTO v_ids
    FROM vehicles v
   WHERE v.home_depot_id = v_depot
     AND v.category = 'autonomous'
     -- Zone A/outside-the-walls only. Mirrors ottoq_cuopt_defer_arm's own guard.
     AND v.current_state = 'arrived_at_gate'
     AND v.current_stall_id IS NULL
     AND v.current_soc < 85
     -- greedy has already reserved a charge stall for it => nothing left to optimise
     AND NOT EXISTS (SELECT 1 FROM stalls s
                      WHERE s.reserved_by = v.id
                        AND s.stall_type::text IN ('dcfc','l2')
                        AND COALESCE(s.reservation_expires_at, v_sim) >= v_sim)
     -- THE BOUND: never hold a vehicle that is already armed/spent, and never
     -- more than v_cap times in the whole run.
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_cuopt_deferrals d
                      WHERE d.sim_run_id = p_sim_run_id AND d.vehicle_id = v.id
                        AND (d.state <> 'clear' OR d.defer_count >= v_cap))
     -- cuOpt has already answered for this vehicle => let the cursor enact it now
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_external_proposals p
                      WHERE p.sim_run_id     = p_sim_run_id
                        AND p.action_context = 'stall_assignment'
                        AND p.entity_type    = 'vehicle'
                        AND p.entity_id      = v.id
                        AND p.status         = 'pending'
                        -- 0259: any source that declares holds_tick counts as an answer.
                        AND p.source IN (SELECT pp.source FROM public.ottoq_proposer_precedence pp
                                          WHERE pp.holds_tick));

  IF v_ids IS NULL OR array_length(v_ids,1) IS NULL THEN RETURN 0; END IF;

  v_n := public.ottoq_cuopt_defer_arm(p_sim_run_id, p_tick, v_ids, NULL);

  BEGIN
    PERFORM public.cuopt_log_gate(
      p_sim_run_id, 'first_refusal_arm', array_length(v_ids,1),
      jsonb_build_object('armed', v_n, 'offered', array_length(v_ids,1),
                         'tick', p_tick, 'max_defers', v_cap),
      clock_timestamp(), 'p7_first_refusal');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN v_n;
EXCEPTION WHEN OTHERS THEN
  -- Fail OPEN: a ledger hiccup must never change how the engine assigns.
  RAISE WARNING 'ottoq_cuopt_first_refusal_arm: % (run=%, tick=%)', SQLERRM, p_sim_run_id, p_tick;
  RETURN 0;
END;
$function$;

-- ---------------------------------------------------------------------------
-- A1. THE PREDICATE CAN SAY YES.
DO $a1$
DECLARE v_free int; v_yes boolean;
BEGIN
  SELECT count(*) INTO v_free FROM public.stalls s
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
     AND s.stall_type::text IN ('dcfc','l2')
     AND s.current_vehicle_id IS NULL
     AND (s.reserved_by IS NULL
          OR COALESCE(s.reservation_expires_at, '-infinity'::timestamptz) <= now());
  v_yes := public.ottoq_depot_has_free_charge_point(
             '11111111-1111-1111-1111-111111111111'::uuid, now());
  IF v_yes <> (v_free > 0) THEN
    RAISE EXCEPTION 'A1 FAILED: the helper says % while % charge stalls are free',
                    v_yes, v_free;
  END IF;
  IF NOT v_yes THEN
    RAISE EXCEPTION 'A1 FAILED: every charge stall at the flagship depot is busy '
                    'right now, so this assertion cannot show the predicate saying '
                    'YES. Re-apply when the depot is quiesced.';
  END IF;
  RAISE NOTICE 'A1 OK: helper agrees with a direct count (% free)', v_free;
END $a1$;

-- A2. THE PREDICATE CAN SAY NO. A control, so A1 is not the only answer it
--     knows. A depot with no stalls at all has no free charge point.
DO $a2$
BEGIN
  IF public.ottoq_depot_has_free_charge_point(
       '00000000-0000-0000-0000-0000028800aa'::uuid, now()) THEN
    RAISE EXCEPTION 'A2 FAILED: a depot that does not exist reports a free charge '
                    'point; the predicate cannot say no and A1 proved nothing';
  END IF;
  RAISE NOTICE 'A2 OK: the predicate says no when there is nothing to offer';
END $a2$;

-- A3. THE GUARD IS IN THE ARM, AND IT IS AFTER THE CAP GATE.
DO $a3$
DECLARE v_src text; v_cap_pos int; v_guard_pos int;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cuopt_first_refusal_arm';
  v_cap_pos   := position('IF v_cap = 0 THEN RETURN 0; END IF;' in v_src);
  v_guard_pos := position('ottoq_depot_has_free_charge_point' in v_src);
  IF v_guard_pos = 0 THEN
    RAISE EXCEPTION 'A3 FAILED: the guard is not in the arm';
  END IF;
  IF v_cap_pos = 0 OR v_cap_pos > v_guard_pos THEN
    RAISE EXCEPTION 'A3 FAILED: the cap gate no longer precedes the guard; a '
                    'certification arm would reach the new code and this file '
                    'would force recert';
  END IF;
  RAISE NOTICE 'A3 OK: guard present, and the cap gate still returns first';
END $a3$;

-- A4. THE ARM STILL REFUSES WHAT IT ALWAYS REFUSED.
DO $a4$
BEGIN
  IF public.ottoq_cuopt_first_refusal_arm(NULL, 1) <> 0 THEN
    RAISE EXCEPTION 'A4 FAILED: a NULL run should arm nothing';
  END IF;
  IF public.ottoq_cuopt_first_refusal_arm(
       '00000000-0000-0000-0000-0000028800bb'::uuid, 1) <> 0 THEN
    RAISE EXCEPTION 'A4 FAILED: a run that does not exist should arm nothing';
  END IF;
  RAISE NOTICE 'A4 OK: the pre-existing refusals are unchanged';
END $a4$;

-- A5. NOTHING WAS ARMED BY THIS FILE.
DO $a5$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_cuopt_deferrals
   WHERE sim_run_id IN ('00000000-0000-0000-0000-0000028800aa'::uuid,
                        '00000000-0000-0000-0000-0000028800bb'::uuid);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A5 FAILED: % deferral row(s) exist for this file''s scratch ids', v_n;
  END IF;
  RAISE NOTICE 'A5 OK: no deferral rows written';
END $a5$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0288_a_seat_is_only_worth_holding_if_there_is_something_to_offer', false,
 'ottoq_cuopt_first_refusal_arm gains one guard: do not arm a first-refusal seat when the depot has no free charge point. New helper public.ottoq_depot_has_free_charge_point(depot, at) holds the predicate in one place. Evidence db/checks/0222: on run 1bd41105 all seven seats that went unanswered were armed at ticks where 40 of 40 charge stalls were busy, and both ticks that produced an answer had capacity. This is the liveness check 0219 wanted with the right predicate -- not "is a proposer alive" but "is there anything to propose". The predicate is DELIBERATELY weaker than the frame''s offerable: no charger health and no heartbeat window, because this runs in the decide path and a heartbeat test there would be G15 (the shield reading a wall clock) with a different clock; weaker means it fires less often, which is the safe direction for a guard that suppresses a hold. Fails OPEN in every case: not arming means greedy serves the vehicle this tick instead of next, so the change can only make an assignment earlier. forces_recert=false because the cap gate returns first: the GLOBAL cuopt_first_refusal_max_defers row is 0 (0152), a certification arm writes no run row, so it returns before reaching the guard -- P1 pins the row and A3 pins the ordering in the source.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
