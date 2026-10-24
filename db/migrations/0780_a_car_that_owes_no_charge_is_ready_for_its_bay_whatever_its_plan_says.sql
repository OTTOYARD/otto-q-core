-- migration-version: 20261024163830
-- migration-name:    a_car_that_owes_no_charge_is_ready_for_its_bay_whatever_its_plan_says
--
-- 0780  **A car that owes no charge is ready for its bay, whatever its plan says.** (G500; db/checks/0470 §2)
--       The bay calendar asks one question before it seats a car ahead of its slot or keeps its slot: is the car still
--       charging? It answers by reading the car's itinerary: any charge leg planned, active or in progress, not closed,
--       with a planned end still ahead (ottoq.ottoq_vehicle_bay_ready; the reconcile's BLOCKER 1, its verbatim twin). At
--       the twin depot as built since 0763 (30 robotic fast chargers, no standard charger) the itinerary still plans a
--       standard charge by its fixed rule (G459), the car charges on a fast charger under another leg, reaches 100% and
--       the standard leg stays planned, re-timed forward by the flow contract. So a car at 100%, parked and waiting for
--       its service bay, reads as charging for the rest of the day, and the calendar starves the depot's wall.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-24 11:07 AM-1:05 PM CT; run 78c0624c; db/checks/0470 §2, queries (4)-(9)) ══════
--
--   Run 78c0624c-ff52-4594-8e54-9da254d4d867, busy_day at the twin depot (rule 8), 13:00-22:00:44 sim, the 30-post depot.
--   Its two service bays are the depot's wall: 159 service-bay jobs owed (112 preventive maintenance, 41 calibrations,
--   5 repairs, 1 cosmetic), about 124 bay-hours of work against 18 bay-hours of bay, and 23 jobs done.
--   (a) The service bays stood empty 151.7 bay-minutes of 1,081 (14.0%) by the calendar's own seats. In 97.3 of them a
--       car was refused the bay that tick for want of a free one (reason no_free_space), across eight gaps: 16.6 minutes
--       (23 refused ticks), 24.4 (41), 7.5 (15), 1.5 (2), 13.9 (26), 6.0 (12), 2.6 (5) and 24.8 (41). Three gaps, 53.7
--       minutes, had no candidate at all (the boot hour and 15:00-15:14), which is 0470 §4's question, not this file's;
--       the last 0.7 were handovers under a minute.
--   (b) Each of those eight gaps ended at, or was cut by, a forward hold (booked_by otto_q, made 4-5 hours earlier)
--       starting 3-60 minutes into the gap. Six of its seven cars were read: every one at 100%, parked and waiting for
--       its service, in staging (staged_awaiting_service) or charge_complete_holding, its charge closed hours before
--       (05b0de6f at 14:31, 1b9b6ea1 at 15:08, b97789b5 at 15:30), each carrying a standard charge leg planned ahead
--       (charge_l2, 165-445 minutes long, starting 21:55). The seventh's hold (616a06de) was ended by the run's stop.
--       The ready car could not be seated early (ottoq_activate_due_bay_reservations seats ahead of the window only a car
--       ottoq_vehicle_bay_ready calls ready); its own request for the bay was refused (its window overlapped its own
--       hold; 05b0de6f asked 92 times); no other car could take the bay (its window overlapped the hold); and the yield
--       (0553) could not move the hold, because a car that could come now never yields.
--   (c) Three minutes before each hold began, the reconcile read the leg as a charge (BLOCKER 1) and released the hold
--       replanned_no_window with blocked_by 'charging' and an ETA of 21:23 to 05:03 the next morning. Of the run's 12
--       reconcile actions blocked by 'charging', 12 were on a car that was not charging and whose last charge had
--       closed at 99-100%: 10 service holds released, 2 holds moved. Of the six gap holds released this way, five cars
--       never got a service bay in the run (the sixth, 5cee8fb3, was seated by the reactive path the tick its hold went);
--       05b0de6f parked from 14:31 to the run's end at 22:00 with its preventive maintenance owed.
--   The car's energy says what the plan cannot: G244's one charge rule, a car owes a charge when its battery is below
--   its one target (ottoq_effective_target_soc_at, 100 unless its owner set less) less one, and the departure test reads
--   the same rule. A charge leg for a car that owes no charge is a plan nothing will run.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Dial bay_ready_reads_energy (0..1, default 0; not agent-writable).
--   (b) ottoq.ottoq_vehicle_owes_charge_now(car, clock): true when the car is on a charger now (charging_dcfc,
--       charging_l2: rule 9, a charge is never stopped short), when its battery is below its one target less one, or
--       when either is unknown; false otherwise. Read-only; never raises (an error reads true, the old answer).
--   (c) ottoq.ottoq_vehicle_bay_ready, one anchored insertion that acts only at 1: a charge leg still planned blocks the
--       car's bay only while the car owes a charge by (b).
--   (d) ottoq.ottoq_reconcile_bay_reservations, three anchored insertions that act only at 1: BLOCKER 1 likewise. A
--       charge the car owes, or one under way, blocks exactly as before, and 0744's charge past its plan is untouched.
--   With both, a ready car's early activation seats it the tick its bay frees (0015's vehicle-first pre-emption already
--   stands the reconcile down for it), and the reconcile stops releasing the holds of cars that owe nothing.
--   Not changed: how full a car charges, which services it needs, when it may leave (rule 9; the departure test reads
--   the car's battery, not its plan); the itinerary and its legs; the activation, the yield, the walk, the bay line.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the two bodies are the ones this file patches (prosrc md5 f52356da, 75485e67); the dial and
--   the helper are absent. P2 not already applied. Pre-images to ottoq_schema_snapshots as '0780_pre'. Each anchor
--   matches once. V1 each body less its insertions is its pre-image. V2 the helper agrees with G244's rule, car for car,
--   across the twin depot's fleet. V3 the dial is catalogued 0..1 default 0 and not agent-writable, and the helper is
--   executable by postgres and service_role only. Executed in full by tests/test_bay_ready_reads_energy_sql.py on the
--   live bodies (md5 asserted).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. At the dial's default both bodies compute what they computed
--   before (V1), and no certification arm, canon cell or dial experiment sets the dial. Rule 12: switched on at the twin
--   depot after the apply, as its own statement, under the deciding person's name; no sweep, no pair.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0780_pre';
--   DROP FUNCTION ottoq.ottoq_vehicle_owes_charge_now(uuid, timestamp with time zone);
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_ready_reads_energy' (and its policy rows);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0780_a_car_that_owes_no_charge_is_ready_for_its_bay_whatever_its_plan_says'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0780 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies read, nothing of this file ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('ottoq.ottoq_vehicle_bay_ready(uuid,uuid,timestamp with time zone)'))
     IS DISTINCT FROM 'f52356da4a33742998c3fc69695e7bb9' THEN
    RAISE EXCEPTION '0780 P1: ottoq.ottoq_vehicle_bay_ready is not the body this file patches (md5 f52356da)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)'))
     IS DISTINCT FROM '75485e67a20dbb022fe23f817743d213' THEN
    RAISE EXCEPTION '0780 P1: ottoq.ottoq_reconcile_bay_reservations is not the body this file patches (md5 75485e67)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_ready_reads_energy')
     OR to_regprocedure('ottoq.ottoq_vehicle_owes_charge_now(uuid,timestamp with time zone)') IS NOT NULL THEN
    RAISE EXCEPTION '0780 P1: the dial or the helper already exists';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0780_a_car_that_owes_no_charge_is_ready_for_its_bay_whatever_its_plan_says') THEN
    RAISE EXCEPTION '0780 P2: already applied';
  END IF;
END $once$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0780_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('ottoq.ottoq_vehicle_bay_ready(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure);

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('bay_ready_reads_energy',
        '0780 (G500): 1 = a charge leg the itinerary still carries says a car is not ready for its bay only while the car '
        'owes a charge (below its one target less one, G244) or is on a charger now, in ottoq_vehicle_bay_ready and the '
        'reconcile''s BLOCKER 1; a car that owes nothing is seated the tick its bay frees and keeps its hold. 0 = any '
        'planned charge leg blocks, as before 0780.',
        0, 0, 1, 'ottoq.ottoq_vehicle_bay_ready, ottoq.ottoq_reconcile_bay_reservations', false);

-- ── (b) the helper ──
CREATE FUNCTION ottoq.ottoq_vehicle_owes_charge_now(p_vehicle_id uuid, p_clock timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
-- 0780 (G500): does the car owe a charge right now? True when it is on a charger (rule 9: a charge is never stopped
-- short), when its battery is below its one target less one (G244's one rule, the departure test's), or when either is
-- unknown. An error reads true, which is the answer before 0780: a plan's charge leg blocks.
DECLARE v RECORD;
BEGIN
  IF p_vehicle_id IS NULL OR p_clock IS NULL THEN RETURN true; END IF;
  SELECT current_state::text AS state, current_soc INTO v FROM public.vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND OR v.current_soc IS NULL THEN RETURN true; END IF;
  IF v.state IN ('charging_dcfc', 'charging_l2') THEN RETURN true; END IF;
  RETURN COALESCE(v.current_soc < public.ottoq_effective_target_soc_at(p_vehicle_id, p_clock) - 1, true);
EXCEPTION WHEN OTHERS THEN
  RETURN true;
END
$function$;
REVOKE ALL ON FUNCTION ottoq.ottoq_vehicle_owes_charge_now(uuid, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION ottoq.ottoq_vehicle_owes_charge_now(uuid, timestamp with time zone) TO service_role;

-- ── (c) and (d): the anchored insertions ──
CREATE TEMP TABLE _0780_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0780_patch VALUES
  -- c1: ottoq_vehicle_bay_ready reads the car's energy before it answers
  (1, 'ottoq.ottoq_vehicle_bay_ready(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o1$  RETURN v_charge_end IS NULL;
$o1$,
   $n1$  -- 0780 (G500): with bay_ready_reads_energy on, a charge leg the plan still carries blocks the car's bay only while
  -- the car owes a charge or is on a charger now. At a depot whose itinerary plans a charge the depot cannot give (G459),
  -- that leg outlives the car's real charge and is re-timed forward all day.
  IF v_charge_end IS NOT NULL
     AND COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_ready_reads_energy', 0), 0) >= 1
     AND NOT ottoq.ottoq_vehicle_owes_charge_now(p_vehicle_id, p_clock) THEN
    v_charge_end := NULL;
  END IF;
  RETURN v_charge_end IS NULL;
$n1$),
  -- d1: the reconcile's variable
  (2, 'ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o2$  v_follow boolean;   -- 0744 (G458)
$o2$,
   $n2$  v_follow boolean;   -- 0744 (G458)
  v_energy boolean;   -- 0780 (G500)
$n2$),
  -- d2: the dial, read once per call
  (3, 'ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o3$  v_follow := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_hold_follows_charge', 0), 0) >= 1;
$o3$,
   $n3$  v_follow := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_hold_follows_charge', 0), 0) >= 1;
  -- 0780 (G500): with bay_ready_reads_energy on, BLOCKER 1 reads a planned charge leg only for a car that owes a charge.
  v_energy := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_ready_reads_energy', 0), 0) >= 1;
$n3$),
  -- d3: BLOCKER 1 reads the car's energy before it blocks
  (4, 'ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o4$    IF v_try IS NOT NULL THEN v_block_at := v_try; v_blk := 'charging'; END IF;
$o4$,
   $n4$    -- 0780 (G500): a charge leg for a car that owes no charge and is not on a charger is a plan nothing will run.
    IF v_try IS NOT NULL AND v_energy AND NOT ottoq.ottoq_vehicle_owes_charge_now(v_b.vehicle_id, p_clock) THEN
      v_try := NULL;
    END IF;
    IF v_try IS NOT NULL THEN v_block_at := v_try; v_blk := 'charging'; END IF;
$n4$);

DO $patch$
DECLARE f regprocedure; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0780_patch LOOP
    v_def := pg_get_functiondef(f);
    FOR p IN SELECT * FROM _0780_patch WHERE fn = f ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0780: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(f) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0780: % is not stored as patched', f;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each patched body less its insertions is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'ottoq.ottoq_vehicle_bay_ready(uuid,uuid,timestamp with time zone)'::regprocedure;
  FOR p IN SELECT * FROM _0780_patch WHERE seq = 1 LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'f52356da4a33742998c3fc69695e7bb9' THEN
    RAISE EXCEPTION '0780 V1: ottoq_vehicle_bay_ready less its insertion is not its pre-image (md5 %)', md5(v_body);
  END IF;
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'ottoq.ottoq_reconcile_bay_reservations(uuid,uuid,timestamp with time zone)'::regprocedure;
  FOR p IN SELECT * FROM _0780_patch WHERE seq BETWEEN 2 AND 4 ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM '75485e67a20dbb022fe23f817743d213' THEN
    RAISE EXCEPTION '0780 V1: the reconcile less its insertions is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: the helper agrees with G244's rule, car for car, across the twin depot's fleet ──
DO $v2$
DECLARE v_n int; v_bad int;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE ottoq.ottoq_vehicle_owes_charge_now(v.id, now())
                                IS DISTINCT FROM (v.current_soc IS NULL
                                                  OR v.current_state::text IN ('charging_dcfc', 'charging_l2')
                                                  OR v.current_soc < public.ottoq_effective_target_soc_at(v.id, now()) - 1))
    INTO v_n, v_bad
    FROM public.vehicles v
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous';
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0780 V2: the helper disagrees with G244''s rule on % of % cars', v_bad, v_n;
  END IF;
  RAISE NOTICE '0780 V2: the helper agrees with G244''s rule on % of % cars at the twin depot', v_n - v_bad, v_n;
END $v2$;

-- ── V3: the dial and the helper's grants ──
DO $v3$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'bay_ready_reads_energy' AND default_value = 0 AND min_value = 0 AND max_value = 1
                    AND NOT COALESCE(agent_writable, false)) THEN
    RAISE EXCEPTION '0780 V3: the dial is not catalogued 0..1, default 0, not agent-writable';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles r
              WHERE r.rolname IN ('anon', 'authenticated')
                AND has_function_privilege(r.oid, 'ottoq.ottoq_vehicle_owes_charge_now(uuid,timestamp with time zone)',
                                           'EXECUTE')) THEN
    RAISE EXCEPTION '0780 V3: a signed-in or anonymous caller can execute the helper';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0780_a_car_that_owes_no_charge_is_ready_for_its_bay_whatever_its_plan_says', false, false,
        'Dial bay_ready_reads_energy (default 0); helper ottoq.ottoq_vehicle_owes_charge_now; one anchored insertion in '
        'ottoq.ottoq_vehicle_bay_ready and three in ottoq.ottoq_reconcile_bay_reservations, acting only at 1: a planned '
        'charge leg blocks a car''s bay only while the car owes a charge or is on a charger (V1: each body less its '
        'insertions is its pre-image). No certification arm, canon cell or dial experiment sets the dial.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-24 16:38:30 UTC (11:38 AM CT), ledger version 20261024163830 ══════════════════════════════════════
--
--   Through apply_migration with nothing in flight (P0 read 0 and no run live or paused at 16:37:42 UTC, and the file's
--   own P0 at the apply). The text sent, BEGIN through COMMIT and one newline, is 10,821 characters, md5
--   4814865012d3337cdda9813e2c466dbf, equal to the ledger's statements[1] read back. Read back from the live catalog
--   (md5 of prosrc): ottoq.ottoq_vehicle_bay_ready 3e22ca9a550c0fa0573bb138d56936ce, ottoq.ottoq_reconcile_bay_reservations
--   2df40fc616882808b4a9b0d1952ff99b, ottoq.ottoq_vehicle_owes_charge_now 2fc1c5b5ac8f19096bb82dd7ad7a5ecb: the bodies
--   tests/test_bay_ready_reads_energy_sql.py leaves on the scratch PostgreSQL, byte for byte. Two pre-images under
--   '0780_pre'; the lineage row false/false. The header's §1 figures were corrected after the apply (eight gaps, not
--   seven; six of seven held cars read; five of six never seated); the executable part is unchanged (md5 as above).
--
--   NOT YET SWITCHED ON. A rolled-back end-to-end probe on live (a full car with a leftover charge leg, read ready at the
--   dial's 0 and 1) was sent through execute_sql at 16:39 UTC; the connector held it for a confirmation that cannot be
--   answered from a cloud session and it timed out after 60 s without running. The switch at the twin depot
--   (ottoq_policy_set('depot', twin depot, 'bay_ready_reads_energy', 1, ...)) waits on the same connector.
