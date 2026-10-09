-- migration-version: 20261009123213
-- migration-name:    the_kernel_serves_a_long_wait_first_and_times_its_line_in_minutes
--
-- 0642  **The kernel serves a car that has waited 90 minutes first, and orders the rest by minutes of charge.** (G384)
--       Under congestion the kernel's own charge order, ranked by minutes waited over battery points owed, let low
--       batteries wait for hours behind top-offs. On b2efcc07 the 13 boot cars under 45% waited a mean 98 minutes from
--       the gate to a charger (the longest 203, three never seated) against every owner's 30-minute contract queue wait
--       (db/checks/0424 §4); on 64251eb8, at sim 14:05, nine cars at 12-42% that had waited 65 minutes stood 13th to
--       21st in a line of 32, behind top-offs at 70-88% that had waited 38-56. The 90-minute floor that exists held only
--       while an agent's order stood, and 127 of b2efcc07's 136 orders were the kernel's own. Rule 9 allows queueing and
--       names better ordering of who is served next as the answer to site pressure. This is that ordering, measured in
--       the check's own replay before it was built.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-09 6:20-6:50 AM CT) ═════════════════════════════════════════════════════════════
--
--   The check's replay: each of b2efcc07's 87 graded orders whose window ran to its end, replayed in what really
--   happened after it (arrivals, cars that appeared, charge times, charges under way, faults, and the calendar's holds as
--   they stood), with the kernel's own order and with each variant; each car's wait in the window to its first charger
--   (a car not seated waits at least to the window's end), 6,404 car-windows. The minutes a car is ordered by are the
--   ones the check expected at the order, never the charge time that really happened.
--
--                                    mean wait  p90 wait  under 45%  80% and up  on time (of 962 due)  late, min  past 30, min
--     the kernel today (points)          70.1     141.8      135.9       43.8          12              127,913     285,432
--     floor 90, points behind it         70.0     137.4      131.2       45.6          13              128,828     284,845
--     floor 60, longest wait first       70.4     136.7      116.1       54.2          16              118,418     286,683
--     first come, first served           70.9     136.7      106.9       67.5           7              126,290     288,726
--     minutes of charge                  69.7     138.4      127.2       47.4          40              131,625     283,840
--     minutes, a fixed-power estimate    70.1     136.9      134.2       49.2          10              132,085     285,338
--     floor 90 first, then minutes       70.0     136.9      116.7       53.2          41              123,119     284,521
--
--   (a) Minutes, not points. Among cars due out (immediate dispatch, first in every variant), the kernel today gives a
--       fast charger to whichever has waited longest per point owed; ordered by minutes of charge, it goes first to the
--       cars that can still be ready by their due time: 41 of 962 due cars on time against 12. Order 471 shows it: two
--       cars at 44% that charge in 27-29 minutes made their due on a fast charger, where the kernel had put cars at 49%
--       that charge in 93-102 minutes, late by about an hour either way. A fixed-power estimate of the minutes does not
--       do it (10 on time): the gain is the charge clock's knowledge of each make and model.
--   (b) The floor, longest wait first. Minutes alone still leave low batteries behind (127 minutes against 136); the
--       floor takes them to 117, top-offs wait 9 minutes longer (53 against 44), and lateness falls 3.7%. The mean wait,
--       the 90th percentile and the minutes past the contract wait barely move: no ordering creates chargers, and on a
--       busy day the depot has fewer than its line needs (rule 9: a capacity finding, never a lever on a vehicle).
--   (c) One run's replay, in overlapping windows, so single readings, not ranges. 64251eb8's orders are the second world
--       (§5).
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Two dials, a person's (rule 10): charge_wait_floor_min (90; 0 is no floor) and charge_order_minutes (1; 0 is
--       0545's ratio in points).
--   (b) public.ottoq_contract_queue_wait_min(car, clock): the queue wait the car's owner agreed (max_queue_wait_minutes in
--       the contract in force), as the agent's board reads it; NULL with no contract.
--   (c) public.ottoq_charge_order_minutes(run, depot, clock): each waiting car's minutes to its target on the depot's
--       charge clock with this run's own charges, the shorter of the kinds it can use, timed exactly as the check's state
--       times it.
--   (d) public.ottoq_charge_order_keys(run, depot, clock): the two keys, floor_key (the wait, at or past the floor) and
--       minutes_key ((minutes waited + minutes of charge) / minutes of charge). A car the clock cannot time (no battery
--       size) carries no minutes_key and sorts after the cars that do, until the floor takes it: the floor is what
--       guarantees no car waits behind the line indefinitely, whatever the clock knows.
--   (e) ottoq_decide_tick, OTTO-Q's seat: the charge cursor reads the keys once per tick and sorts by them after
--       immediate dispatch and an agent's live order (the pin, then the agent's ranking), before 0545's ratio in points,
--       which now breaks only their ties. Each seat made records the keys it was made by (context 'charge_order'). A
--       failure reading them leaves the order before 0642. Baseline seats are untouched.
--   (f) The same keys, in the same place, in ottoq_charge_queue_kernel_order (the agent's board and the check's line),
--       ottoq_depot_queue (the cockpits) and ottoq_run_learning (the board's queue read).
--   (g) The check. The state carries each car's ordering minutes (om) and contract wait (mw), and the run's two dials;
--       the simulator orders the line as the cursor does, by om (never a sampled future's draw; scaled with what a car
--       owes when that changes), and reports breach_sum and breach_n (minutes past each car's contract wait at its first
--       seat; with an outflow, breach2_sum over the next visits too). The comparison weighs that after lateness and
--       before minutes in the depot (by 'contract_wait'), so an agent's order can win by keeping more cars inside their
--       owners' queue waits. A state without the dials simulates and compares exactly as before.
--   (h) The agent's board says how the kernel orders ('kernel_order': floor_min, by).
--   Nothing here changes how full a car charges, when it may leave, or which charger kind it wants (rule 9).
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, no run running. P1 0641 applied; the eight bodies are the ones this file was written against
--   (md5); nothing it creates exists. V1 the cursor reads the keys and sorts by them before 0545's ratio. V2 on the
--   latest 8 stored states, without the dials, the simulator (the expected future with no order, a sampled one with the
--   agent's) and the comparison are 0641's, key for key. V3 the keys execute on the twin depot, the state carries the
--   dials at their defaults, and a stored state given the keys reports breach. Executed in full by
--   tests/test_charge_order_floor_sql.py on the miniature depot.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert TRUE and forces_dial_restart TRUE: at the defaults every run's seating order changes, as 0545, 0546
--   and 0551 did. And one property moves, stated rather than left to be found: the kernel's seating now reads the
--   depot's charge clock, which the nightly job refits (11:22 UTC) and this run's own charges adjust. A determinism pair
--   is unaffected (both arms read one fit in one transaction), but a seed replayed on another day can seat differently
--   once the fit has moved. That is the clock learning, as rule 10 intends (production updates its estimates overnight,
--   never its rules); a cross-day digest of a run (G140) has to key on the clock's fit as well as the engine.
--
-- ══ §5 THE SECOND WORLD ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   64251eb8, the armed run on b2efcc07's seed this morning (6:05-7:20 AM CT, the same stack, a different world after
--   its first tick), stopped at sim 17:00 and graded: its 63 full-window orders replayed the same way, 4,518 car-windows.
--
--                                    mean wait  p90 wait  under 45%  80% and up  on time (of 720 due)  late, min  past 30, min
--     the kernel today (points)          66.4     127.2      129.1       41.3          25               80,397     180,666
--     floor 60, longest wait first       66.3     125.0      116.0       52.3          25               81,637     180,467
--     minutes of charge                  65.8     127.4      124.4       43.2          33               77,351     178,868
--     floor 90 first, then minutes       66.1     126.4      120.2       47.7          33               78,737     180,207
--
--   The same direction on every variant, smaller: minutes give the on-time and lateness gains (25 -> 33 due cars on
--   time), the floor buys low batteries a shorter wait (129 -> 120) at the top-offs' cost (41 -> 48). In this world
--   minutes alone come out ahead of this file on everything but the low batteries; the floor stays because a windowed
--   replay cannot see the tail it exists for: by minutes alone a car whose charge takes 110 minutes gains priority
--   eleven times slower than one whose charge takes 10, so under a steady stream of short charges it can still wait
--   indefinitely, and the floor is what bounds that. Its value (90) is a person's dial, and the research wing's designed
--   pairs in the twin are where it gets tuned (rule 10).
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0642_pre' AND object_kind = 'function';
--   DROP FUNCTION public.ottoq_charge_order_keys(uuid, uuid, timestamptz),
--   public.ottoq_charge_order_minutes(uuid, uuid, timestamptz), public.ottoq_contract_queue_wait_min(uuid, timestamptz);
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key IN ('charge_wait_floor_min', 'charge_order_minutes');
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0642_the_kernel_serves_a_long_wait_first_and_times_its_line_in_minutes'.

BEGIN;

-- ── P0: nothing in flight, no run running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0642 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0642 P0: a run is running; its decide tick would change order mid-run. Apply between runs';
  END IF;
END $inflight$;

-- ── P1: 0641 is applied; every body is the one this file was written against; nothing it creates exists ──
DO $premises$
DECLARE r record;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0642_the_kernel_serves_a_long_wait_first_and_times_its_line_in_minutes') THEN
    RAISE EXCEPTION '0642 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0641_the_agent_sees_the_kernels_own_plan') THEN
    RAISE EXCEPTION '0642 P1: 0641 is not applied; apply it first';
  END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_decide_tick(uuid)', 'f1473f41f43a796fef80707a80288cea', 'the decide tick (0614)'),
      ('public.ottoq_charge_queue_kernel_order(uuid,uuid,timestamp with time zone)', '7582ced28b18b05068f5279966d82020', 'the kernel''s own order (0614)'),
      ('public.ottoq_depot_queue(uuid,uuid)', '223855b9da1b01f260c4e4eeb473f45a', 'the cockpits'' queue (0614)'),
      ('public.ottoq_run_learning(uuid,integer,boolean)', 'c98ab6513765bbbc51703731e08ab613', 'the board''s queue read (0614)'),
      ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', '46f238684d97df4cb4f858538f239ee6', 'the check''s state (0639)'),
      ('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 'cdb81756e077abaa7e95370526e26a51', 'the check''s simulator (0639)'),
      ('public.ottoq_charge_line_compare(jsonb,jsonb)', '5054e2dc5502d5b2c44ef241c314ad7e', 'the check''s comparison (0623)'),
      ('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', 'c3e0920924b6afc43da75821fbfe2867', 'the agent''s board (0641)')
    ) AS x(sig, md5, what)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0642 P1: % is not the body this file was written against (md5 %); read it again', r.what, left(r.md5, 8);
    END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_contract_queue_wait_min(uuid,timestamptz)') IS NOT NULL
     OR to_regprocedure('public.ottoq_charge_order_minutes(uuid,uuid,timestamptz)') IS NOT NULL
     OR to_regprocedure('public.ottoq_charge_order_keys(uuid,uuid,timestamptz)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                 WHERE param_key IN ('charge_order_minutes', 'charge_wait_floor_min')) THEN
    RAISE EXCEPTION '0642 P1: something this file creates already exists';
  END IF;
END $premises$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0642_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_decide_tick(uuid)'::regprocedure,
                 'public.ottoq_charge_queue_kernel_order(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_depot_queue(uuid,uuid)'::regprocedure,
                 'public.ottoq_run_learning(uuid,integer,boolean)'::regprocedure,
                 'public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure,
                 'public.ottoq_charge_line_compare(jsonb,jsonb)'::regprocedure,
                 'public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure);

-- what V2 compares against: the check's simulator and comparison as they stand, on the latest 8 stored states
CREATE TEMP TABLE _0642_pre ON COMMIT DROP AS
SELECT s.order_id, x.r0, x.r1, public.ottoq_charge_line_compare(x.r0, x.r1) AS cmp
  FROM (SELECT * FROM public.ottoq_charge_order_snapshots WHERE depot_id = '11111111-1111-1111-1111-111111111111'
         ORDER BY order_id DESC LIMIT 8) s
  CROSS JOIN LATERAL (SELECT public.ottoq_charge_line_schedule(s.state, NULL, 0, s.seed, true) AS r0,
                             public.ottoq_charge_line_schedule(s.state, s.agent_order, 3, s.seed, true) AS r1) x;

-- ══ (a) the two dials, a person's (rule 10) ══════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, agent_writable, affects, description)
VALUES
 ('charge_wait_floor_min', 0, 480, 90, false,
  'ottoq_decide_tick (charge cursor, seat 0); ottoq_charge_order_keys; ottoq_charge_line_state',
  '0642 (G384): a car that has waited this many minutes for a charger goes ahead of every car that has not, the longest '
  'wait first, in the kernel''s own order (after immediate dispatch and an agent''s live order). 0 = no floor. A '
  'person''s dial, never the agent''s (rule 10).'),
 ('charge_order_minutes', 0, 1, 1, false,
  'ottoq_decide_tick (charge cursor, seat 0); ottoq_charge_order_keys; ottoq_charge_line_state',
  '0642 (G384): 1 orders the kernel''s charge line by the response ratio in minutes of charge, (minutes waited + minutes '
  'the charge takes on the charge clock) / minutes the charge takes; 0 by 0545''s ratio in battery points. A person''s '
  'dial, never the agent''s (rule 10).');


-- ══ (b) a car's contract wait ════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_contract_queue_wait_min(p_vehicle_id uuid, p_clock timestamptz)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  -- 0642: the longest the car's owner has agreed it waits in the charge queue (ottoq_fleet_operator_slas,
  -- max_queue_wait_minutes): the contract in force at p_clock, its latest version, as the agent's board reads it.
  -- NULL when the car's operator has no contract in force or it names no limit: such a car is held to no contract wait.
  SELECT s.max_queue_wait_minutes::numeric
    FROM vehicles v
    JOIN ottoq_fleet_operator_slas s ON s.fleet_operator_id = v.fleet_operator_id
   WHERE v.id = p_vehicle_id AND s.status = 'active'
     AND s.effective_from <= p_clock AND (s.effective_until IS NULL OR s.effective_until > p_clock)
   ORDER BY s.version DESC
   LIMIT 1
$fn$;

-- ══ (c) the minutes the kernel orders a car by ═══════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_order_minutes(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz)
RETURNS TABLE(vehicle_id uuid, md numeric, ml numeric, dok boolean, lok boolean, minutes numeric)
LANGUAGE plpgsql
STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0642 (G384): how long each car waiting for a charger at the depot takes to charge to its target, timed exactly as the
   check's state times it (ottoq_charge_line_state): the depot's charge clock (ottoq_charge_clock_model) with this run's
   own charges up to p_clock, on the depot's fastest charger of each kind, from the car's battery now to rule 9's one
   target (ottoq_effective_target_soc_at). `minutes` is the shorter of the two kinds the car can use (both when it can
   use neither), at least one minute. The kernel orders its charge line by it; the check's state carries the same
   number per car (om), so the futures order the line as the kernel does. Read-only. */
DECLARE
  v_ct jsonb := public.ottoq_charge_clock_model(p_depot_id);
  v_ev jsonb; v_kw_d numeric; v_kw_l numeric;
BEGIN
  IF v_ct IS NULL THEN
    RETURN;
  END IF;
  v_ev := public.ottoq_charge_clock_run_evidence(v_ct, p_sim_run_id, p_clock);
  SELECT max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'dcfc'),
         max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'l2')
    INTO v_kw_d, v_kw_l
    FROM stalls s WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc', 'l2');
  RETURN QUERY
  SELECT x.id, x.md, x.ml, x.dok, x.lok,
         GREATEST(CASE WHEN x.dok AND x.lok THEN LEAST(x.md, x.ml)
                       WHEN x.dok THEN x.md
                       WHEN x.lok THEN x.ml
                       ELSE LEAST(x.md, x.ml) END, 1)
    FROM (SELECT v.id,
                 (public.ottoq_charge_clock(v_ct, 'dcfc', wh.who, v.battery_capacity_kwh, v.current_soc, tg.t, v_kw_d,
                                            v.inlet_max_kw, v_ev -> 'dcfc') ->> 'm')::numeric AS md,
                 (public.ottoq_charge_clock(v_ct, 'l2', wh.who, v.battery_capacity_kwh, v.current_soc, tg.t, v_kw_l,
                                            v.inlet_max_kw, v_ev -> 'l2') ->> 'm')::numeric AS ml,
                 public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'dcfc') AS dok,
                 public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2') AS lok
            FROM vehicles v
            CROSS JOIN LATERAL (SELECT public.ottoq_effective_target_soc_at(v.id, p_clock) AS t) tg
            CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who) wh
           WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
             AND v.current_state::text IN ('arrived_at_gate', 'staged_awaiting_service')) x
   WHERE x.md IS NOT NULL AND x.ml IS NOT NULL;
END $fn$;

-- ══ (d) the kernel's two keys ════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_order_keys(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz)
RETURNS TABLE(vehicle_id uuid, wait_min numeric, minutes numeric, floor_key numeric, minutes_key numeric)
LANGUAGE plpgsql
STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0642 (G384): the two keys OTTO-Q's seat orders its charge line by after immediate dispatch and the agent's keys, and
   before 0545's ratio in points, for each car waiting for a charger at the depot. floor_key: a car that has waited
   charge_wait_floor_min (90) or longer goes ahead of every car that has not, the longest wait first (NULL below the
   floor, and for every car with the floor at 0). minutes_key: then the highest response ratio in minutes, (minutes
   waited + minutes its charge takes) / minutes its charge takes (ottoq_charge_order_minutes), with charge_order_minutes
   at 1 (NULL at 0, and for a car the clock cannot time, which then sorts by 0545's ratio). The wait is the cursor's own
   (ottoq_charge_wait_min). ottoq_decide_tick's cursor, ottoq_charge_queue_kernel_order, ottoq_depot_queue and
   ottoq_run_learning all read the keys here; the check's state carries the same dials (ottoq_charge_line_state). */
DECLARE
  v_mon boolean := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_order_minutes', 1), 1) >= 1;
  v_fl numeric := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_wait_floor_min', 90), 90), 0);
BEGIN
  IF NOT v_mon AND v_fl = 0 THEN
    RETURN;                                    -- both keys off: no car carries one, and every key sorts nothing
  END IF;
  RETURN QUERY
  WITH m AS (
    SELECT o.vehicle_id, o.minutes FROM public.ottoq_charge_order_minutes(p_sim_run_id, p_depot_id, p_clock) o WHERE v_mon
  )
  SELECT v.id, w.wait_min, m.minutes,
         CASE WHEN v_fl > 0 AND w.wait_min >= v_fl THEN w.wait_min END,
         CASE WHEN v_mon AND m.minutes IS NOT NULL THEN (w.wait_min + m.minutes) / m.minutes END
    FROM vehicles v
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_wait_min(v.config, v.last_state_change, p_clock, p_sim_run_id)::numeric AS wait_min) w
    LEFT JOIN m ON m.vehicle_id = v.id
   WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
     AND v.current_state::text IN ('arrived_at_gate', 'staged_awaiting_service');
END $fn$;

-- ══ (e)-(h) the anchored patches: each anchor once, each body stored as patched ════════════════════════════════════════
CREATE TEMP TABLE _0642_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0642_patch VALUES
('public.ottoq_decide_tick(uuid)', 1,
$o642$  v_ao_kpos jsonb := '{}'::jsonb; v_ao_order_id bigint; v_ao_wait numeric;                                       /* 0614 */
$o642$,
$n642$  v_ao_kpos jsonb := '{}'::jsonb; v_ao_order_id bigint; v_ao_wait numeric;                                       /* 0614 */
  v_ok jsonb := '{}'::jsonb;                                                                                     /* 0642 */
$n642$),
('public.ottoq_decide_tick(uuid)', 2,
$o642$  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id, v.config AS ao_config, v.last_state_change AS ao_lsc
$o642$,
$n642$  /* 0642 (G384): OTTO-Q's seat's own two keys after the agent's, read once per tick (ottoq_charge_order_keys):
     {car: [floor_key, minutes_key]}. Every other seat, the dials at 0, and a failure here leave it empty, and the
     cursor's ORDER BY is the one before 0642, key for key. */
  IF v_seat = 0 THEN
    BEGIN
      SELECT COALESCE(jsonb_object_agg(k.vehicle_id::text, jsonb_build_array(k.floor_key, k.minutes_key)), '{}'::jsonb)
        INTO v_ok
        FROM public.ottoq_charge_order_keys(p_sim_run_id, v_depot, v_clock) k
       WHERE k.floor_key IS NOT NULL OR k.minutes_key IS NOT NULL;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0642 charge order keys: % %', SQLSTATE, SQLERRM;
      v_ok := '{}'::jsonb;
    END;
  END IF;

  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id, v.config AS ao_config, v.last_state_change AS ao_lsc
$n642$),
('public.ottoq_decide_tick(uuid)', 3,
$o642$              CASE WHEN v_seat = 2 THEN v.current_soc END ASC,
$o642$,
$n642$              CASE WHEN v_seat = 2 THEN v.current_soc END ASC,
              /* 0642 (G384): OTTO-Q's seat, after the agent's keys: a car that has waited charge_wait_floor_min (90)
                 or longer goes ahead of every car that has not, the longest wait first; then the highest response
                 ratio in minutes of charge, (minutes waited + minutes its charge takes) / minutes its charge takes.
                 Both NULL for every car on a baseline seat or with the dials at 0, and 0545's ratio below orders the
                 line as before; below the floor 0545's ratio breaks only the minutes' ties. */
              (v_ok -> v.id::text ->> 0)::numeric DESC NULLS LAST,
              (v_ok -> v.id::text ->> 1)::numeric DESC NULLS LAST,
$n642$),
('public.ottoq_decide_tick(uuid)', 4,
$o642$    IF v_ao_on THEN  /* 0614: the order this seat is made under, for the stall pick and for the record */
$o642$,
$n642$    IF v_ok ? v_req.vehicle_id::text THEN  /* 0642: the keys this car was served by, for the record */
      v_ctx := v_ctx || jsonb_build_object('charge_order', jsonb_build_object(
                 'floor_key', v_ok -> v_req.vehicle_id::text -> 0, 'minutes_key', v_ok -> v_req.vehicle_id::text -> 1));
    END IF;
    IF v_ao_on THEN  /* 0614: the order this seat is made under, for the stall pick and for the record */
$n642$),
('public.ottoq_charge_queue_kernel_order(uuid,uuid,timestamp with time zone)', 1,
$o642$  -- charging-staff limit, which hold a car back from a tick without moving its place.
$o642$,
$n642$  -- charging-staff limit, which hold a car back from a tick without moving its place.
  -- 0642 (G384): and the cursor's two keys after immediate dispatch (ottoq_charge_order_keys): the longest wait past
  -- the floor first, then the response ratio in minutes of charge; 0545's ratio in points breaks their ties.
$n642$),
('public.ottoq_charge_queue_kernel_order(uuid,uuid,timestamp with time zone)', 2,
$o642$  SELECT q.id, (row_number() OVER (ORDER BY q.immediate DESC, (q.wait_min + q.gap) / q.gap DESC NULLS LAST,
                                            q.current_soc ASC, q.id))::int,
$o642$,
$n642$  SELECT q.id, (row_number() OVER (ORDER BY q.immediate DESC,
                                            ok.floor_key DESC NULLS LAST, ok.minutes_key DESC NULLS LAST,   -- 0642
                                            (q.wait_min + q.gap) / q.gap DESC NULLS LAST,
                                            q.current_soc ASC, q.id))::int,
$n642$),
('public.ottoq_charge_queue_kernel_order(uuid,uuid,timestamp with time zone)', 3,
$o642$    FROM q
   WHERE q.current_soc < q.visit_target - 1
$o642$,
$n642$    FROM q
    LEFT JOIN public.ottoq_charge_order_keys(p_sim_run_id, p_depot_id, p_clock) ok ON ok.vehicle_id = q.id   -- 0642
   WHERE q.current_soc < q.visit_target - 1
$n642$),
('public.ottoq_depot_queue(uuid,uuid)', 1,
$o642$      FROM z),
  -- sect.3 STALL ASSIGNMENT -- mirrored:$o642$,
$n642$      FROM z),
  -- 0642 (G384): OTTO-Q's seat's two keys after the agent's, as the cursor reads them (ottoq_charge_order_keys)
  ok AS (
    SELECT k.* FROM public.ottoq_charge_order_keys(p_sim_run_id, p_depot_id, (SELECT clock FROM z)) k
     WHERE (SELECT seat FROM z) = 0),
  -- sect.3 STALL ASSIGNMENT -- mirrored:$n642$),
('public.ottoq_depot_queue(uuid,uuid)', 2,
$o642$                                        CASE WHEN (SELECT seat FROM z) = 2 THEN c.current_soc END ASC,
$o642$,
$n642$                                        CASE WHEN (SELECT seat FROM z) = 2 THEN c.current_soc END ASC,
                                        (SELECT k.floor_key FROM ok k WHERE k.vehicle_id = c.id) DESC NULLS LAST,     -- 0642
                                        (SELECT k.minutes_key FROM ok k WHERE k.vehicle_id = c.id) DESC NULLS LAST,   -- 0642
$n642$),
('public.ottoq_run_learning(uuid,integer,boolean)', 1,
$o642$  ), o AS (
    SELECT q.*, row_number() OVER (
$o642$,
$n642$  ), ok AS (                                                                                     -- 0642
    SELECT k.* FROM public.ottoq_charge_order_keys(p_sim_run_id, v_depot, v_clock) k WHERE v_seat = 0
  ), o AS (
    SELECT q.*, row_number() OVER (
$n642$),
('public.ottoq_run_learning(uuid,integer,boolean)', 2,
$o642$                      CASE WHEN v_seat = 2 THEN q.current_soc END ASC,
$o642$,
$n642$                      CASE WHEN v_seat = 2 THEN q.current_soc END ASC,
                      (SELECT k.floor_key FROM ok k WHERE k.vehicle_id = q.id) DESC NULLS LAST,     -- 0642
                      (SELECT k.minutes_key FROM ok k WHERE k.vehicle_id = q.id) DESC NULLS LAST,   -- 0642
$n642$),
('public.ottoq_run_learning(uuid,integer,boolean)', 3,
$o642$               'then the agent''s ranking (the kind free now first), then the kernel''s ratio.',
$o642$,
$n642$               'then the agent''s ranking (the kind free now first), then the kernel''s ratio. 0642: on OTTO-Q''s seat '
               'the kernel''s own keys come before its ratio in points: a car that has waited charge_wait_floor_min (90) '
               'or longer first, the longest wait first, then (minutes waited + minutes of charge) / minutes of charge.',
$n642$),
('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 1,
$o642$   exactly. */
DECLARE$o642$,
$n642$   exactly.
   0642: each car in the line and each car coming home carries `om`, the minutes the kernel orders it by (the shorter
   of its two clock times on the kinds it can use, ottoq_charge_order_minutes' number) and `mw`, its contract's queue
   wait when it has one (ottoq_contract_queue_wait_min); and the state carries the kernel's order keys as the run's
   dials stand (`order_minutes`, `floor_min`), so the futures order the line as the kernel does. */
DECLARE$n642$),
('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 2,
$o642$           'sd', (x.cd ->> 'sd')::numeric, 'sl', (x.cl ->> 'sd')::numeric, 'cls', x.who ->> 'cls', 'lv', x.cd ->> 'lvl')
           ORDER BY x.kernel_pos), '[]'::jsonb)$o642$,
$n642$           'sd', (x.cd ->> 'sd')::numeric, 'sl', (x.cl ->> 'sd')::numeric, 'cls', x.who ->> 'cls', 'lv', x.cd ->> 'lvl')
           || jsonb_build_object('om', GREATEST(CASE WHEN x.dok AND x.lok THEN LEAST((x.cd ->> 'm')::numeric, (x.cl ->> 'm')::numeric)
                                                     WHEN x.dok THEN (x.cd ->> 'm')::numeric
                                                     WHEN x.lok THEN (x.cl ->> 'm')::numeric
                                                     ELSE LEAST((x.cd ->> 'm')::numeric, (x.cl ->> 'm')::numeric) END, 1))   -- 0642
           || CASE WHEN x.mw IS NOT NULL THEN jsonb_build_object('mw', x.mw) ELSE '{}'::jsonb END                       -- 0642
           ORDER BY x.kernel_pos), '[]'::jsonb)$n642$),
('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 3,
$o642$                 public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2') AS lok,
                 public.ottoq_charge_clock(v_ct, 'dcfc', wh.who, v.battery_capacity_kwh, k.soc, tg.t, v_kw_d, v.inlet_max_kw,$o642$,
$n642$                 public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2') AS lok,
                 public.ottoq_contract_queue_wait_min(v.id, p_clock) AS mw,                                     -- 0642
                 public.ottoq_charge_clock(v_ct, 'dcfc', wh.who, v.battery_capacity_kwh, k.soc, tg.t, v_kw_d, v.inlet_max_kw,$n642$),
('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 4,
$o642$           'sd', (ck.cd ->> 'sd')::numeric, 'sl', (ck.cl ->> 'sd')::numeric, 'cls', wh.who ->> 'cls', 'lv', ck.cd ->> 'lvl')
           || CASE WHEN th.r IS NOT NULL$o642$,
$n642$           'sd', (ck.cd ->> 'sd')::numeric, 'sl', (ck.cl ->> 'sd')::numeric, 'cls', wh.who ->> 'cls', 'lv', ck.cd ->> 'lvl')
           || jsonb_build_object('om', GREATEST(CASE WHEN kc.dok AND kc.lok THEN LEAST((ck.cd ->> 'm')::numeric, (ck.cl ->> 'm')::numeric)
                                                     WHEN kc.dok THEN (ck.cd ->> 'm')::numeric
                                                     WHEN kc.lok THEN (ck.cl ->> 'm')::numeric
                                                     ELSE LEAST((ck.cd ->> 'm')::numeric, (ck.cl ->> 'm')::numeric) END, 1))   -- 0642
           || CASE WHEN kc.mw IS NOT NULL THEN jsonb_build_object('mw', kc.mw) ELSE '{}'::jsonb END                       -- 0642
           || CASE WHEN th.r IS NOT NULL$n642$),
('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 5,
$o642$    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(v_ct, 'dcfc', wh.who, v.battery_capacity_kwh, i.soc_at_arrival, tg.t,$o642$,
$n642$    CROSS JOIN LATERAL (SELECT public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'dcfc') AS dok,          -- 0642
                               public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2') AS lok,
                               public.ottoq_contract_queue_wait_min(v.id, p_clock) AS mw) kc
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(v_ct, 'dcfc', wh.who, v.battery_capacity_kwh, i.soc_at_arrival, tg.t,$n642$),
('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 6,
$o642$    'cars', v_cars, 'inbound', v_inb, 'chargers', v_ch);$o642$,
$n642$    'cars', v_cars, 'inbound', v_inb, 'chargers', v_ch,
    -- 0642: the kernel's own order keys, as this run's dials stand (ottoq_charge_order_keys)
    'order_minutes', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_order_minutes', 1), 1) >= 1,
    'floor_min', GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_wait_floor_min', 90), 90), 0));$n642$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 1,
$o642$   again. Totals add holds and holds_unmodelled. Without the list, 0638's result, key for key. */
DECLARE$o642$,
$n642$   again. Totals add holds and holds_unmodelled. Without the list, 0638's result, key for key.
   0642: with the kernel's order keys in the state (order_minutes, floor_min: ottoq_charge_line_state), the line is
   ordered as the kernel's cursor orders it (ottoq_charge_order_keys): after the agent's keys, a car that has waited the
   floor or longer first, the longest wait first, then the response ratio in minutes of charge, by each car's `om` (the
   minutes the kernel orders it by: never a sampled future's draw; scaled with what it owes when that changes); and the
   result adds breach_sum and breach_n (each car's minutes past its contract's queue wait `mw` at its first seat, or at
   the horizon if it gets none; a car with no contract wait is held to none), and with an outflow breach2_sum over the
   next visits too. Without the keys, 0641's result, key for key. */
DECLARE$n642$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 2,
$o642$  nh int := 0; h_un int := 0; s_h0 int[]; s_h1 int[]; v_held boolean; v_hb float8;
$o642$,
$n642$  nh int := 0; h_un int := 0; s_h0 int[]; s_h1 int[]; v_held boolean; v_hb float8;
  -- 0642: the kernel's order keys, and each car's ordering minutes and contract wait
  v_keys boolean := (p_state ? 'order_minutes');
  v_omon boolean := COALESCE((p_state ->> 'order_minutes')::boolean, false);
  v_floor float8 := GREATEST(COALESCE((p_state ->> 'floor_min')::float8, 0), 0);
  c_om float8[] := '{}'; c_mw float8[] := '{}';
$n642$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 3,
$o642$      c_md[n] := (e ->> 'md')::float8;
      c_ml[n] := (e ->> 'ml')::float8;
      c_inb[n] := v_inbound;$o642$,
$n642$      c_md[n] := (e ->> 'md')::float8;
      c_ml[n] := (e ->> 'ml')::float8;
      c_om[n] := (e ->> 'om')::float8; c_mw[n] := (e ->> 'mw')::float8;                          -- 0642
      c_inb[n] := v_inbound;$n642$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 4,
$o642$              c_md[n] := c_md[n] * v_owe / c_g[n];
              c_ml[n] := c_ml[n] * v_owe / c_g[n];$o642$,
$n642$              c_md[n] := c_md[n] * v_owe / c_g[n];
              c_ml[n] := c_ml[n] * v_owe / c_g[n];
              c_om[n] := c_om[n] * v_owe / c_g[n];                                                  -- 0642$n642$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 5,
$o642$          c_md[n] := s_free[m] - v_tf; c_ml[n] := s_free[m] - v_tf;$o642$,
$n642$          c_md[n] := s_free[m] - v_tf; c_ml[n] := s_free[m] - v_tf;
          c_om[n] := GREATEST(s_free[m] - v_tf, 1); c_mw[n] := NULL;                                -- 0642: what is left$n642$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 6,
$o642$      c_md[n] := v_rr[4]; c_ml[n] := v_rr[5]; c_av[n] := v_rr[2]; c_gate[n] := v_rr[2];$o642$,
$n642$      c_md[n] := v_rr[4]; c_ml[n] := v_rr[5]; c_av[n] := v_rr[2]; c_gate[n] := v_rr[2];
      -- 0642: the minutes the kernel orders the return by: the clock's from its reserve in proportion to what it owes
      -- (ottoq_charge_line_return_draw's own scaling, without a sampled future's draw); its first visit's contract wait
      c_om[n] := GREATEST(CASE WHEN COALESCE((v_r ->> 'tg')::float8, 100) - (v_r ->> 'rs')::float8 > 0.5
                               THEN GREATEST(COALESCE((v_r ->> 'tg')::float8, 100) - v_rr[3], 0)
                                    / (COALESCE((v_r ->> 'tg')::float8, 100) - (v_r ->> 'rs')::float8) ELSE 0 END
                          * CASE WHEN c_dok[n] AND c_lok[n] THEN LEAST((v_r ->> 'rmd')::float8, (v_r ->> 'rml')::float8)
                                 WHEN c_dok[n] THEN (v_r ->> 'rmd')::float8
                                 WHEN c_lok[n] THEN (v_r ->> 'rml')::float8
                                 ELSE LEAST((v_r ->> 'rmd')::float8, (v_r ->> 'rml')::float8) END, 1);
      c_mw[n] := c_mw[array_position(c_id, p_car[pi])];$n642$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 7,
$o642$          c_md[i] := c_md[i] * v_frac;
          c_ml[i] := c_ml[i] * v_frac;$o642$,
$n642$          c_md[i] := c_md[i] * v_frac;
          c_ml[i] := c_ml[i] * v_frac;
          c_om[i] := c_om[i] * v_frac;                                                                -- 0642$n642$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 8,
$o642$                                          WHEN v_mode = 'l2' AND u.ok = 'dcfc' THEN 1000 ELSE 0 END END END ASC NULLS LAST,
             (u.w + u.g) / u.g DESC, u.soc ASC, u.idr ASC)$o642$,
$n642$                                          WHEN v_mode = 'l2' AND u.ok = 'dcfc' THEN 1000 ELSE 0 END END END ASC NULLS LAST,
             -- 0642: the kernel's own keys after the agent's: the longest wait past the floor first, then the response
             -- ratio in minutes of charge (NULL for every car in a state without them: 0641's order, key for key)
             CASE WHEN v_floor > 0 AND u.w >= v_floor THEN u.w END DESC NULLS LAST,
             CASE WHEN v_omon THEN (u.w + u.om) / u.om END DESC NULLS LAST,
             (u.w + u.g) / u.g DESC, u.soc ASC, u.idr ASC)$n642$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 9,
$o642$                   c_g[z3.i] AS g, c_soc[z3.i] AS soc, c_idr[z3.i] AS idr, c_rank[z3.i] AS rk, c_okind[z3.i] AS ok
$o642$,
$n642$                   c_g[z3.i] AS g, c_soc[z3.i] AS soc, c_idr[z3.i] AS idr, c_rank[z3.i] AS rk, c_okind[z3.i] AS ok,
                   GREATEST(COALESCE(c_om[z3.i], CASE WHEN c_dok[z3.i] AND NOT c_lok[z3.i] THEN c_md[z3.i]
                                                      WHEN c_lok[z3.i] AND NOT c_dok[z3.i] THEN c_ml[z3.i]
                                                      ELSE LEAST(c_md[z3.i], c_ml[z3.i]) END), 1) AS om      -- 0642
$n642$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 10,
$o642$  IF f_on THEN                                                                                     -- 0635
    v_out := v_out || jsonb_build_object('faults_drawn', f_n, 'requeued', f_rq);
  END IF;$o642$,
$n642$  IF f_on THEN                                                                                     -- 0635
    v_out := v_out || jsonb_build_object('faults_drawn', f_n, 'requeued', f_rq);
  END IF;
  IF v_keys THEN                                                                                   -- 0642
    -- each car's minutes past its contract's queue wait at its first seat (its wait before the order, and since, to its
    -- first charger; to the horizon if it gets none): the cars here now and coming home, then their next visits
    SELECT v_out || jsonb_build_object(
             'breach_sum', round(COALESCE(sum(GREATEST(c_w0[z.i] + COALESCE(c_s0[z.i], v_hor) - c_av[z.i] - c_mw[z.i], 0))
                                          FILTER (WHERE c_mw[z.i] IS NOT NULL), 0)::numeric, 2),
             'breach_n', count(*) FILTER (WHERE c_mw[z.i] IS NOT NULL
                                            AND c_w0[z.i] + COALESCE(c_s0[z.i], v_hor) - c_av[z.i] > c_mw[z.i]))
      INTO v_out
      FROM generate_subscripts(c_ready, 1) AS z(i)
     WHERE z.i <= n0;
    IF o_on THEN
      SELECT v_out || jsonb_build_object(
               'breach2_sum', round((v_out ->> 'breach_sum')::numeric
                                    + COALESCE(sum(GREATEST(COALESCE(c_s0[z.i], v_hor) - c_av[z.i] - c_mw[z.i], 0))
                                               FILTER (WHERE c_mw[z.i] IS NOT NULL AND NOT c_void[z.i] AND c_vk[z.i] = 1), 0)::numeric, 2))
        INTO v_out
        FROM generate_series(n0 + 1, GREATEST(n, n0)) AS z(i)
       WHERE z.i > n0 AND c_vk[z.i] > 0;
    END IF;
  END IF;$n642$),
('public.ottoq_charge_line_compare(jsonb,jsonb)', 1,
$o642$  -- and d_out (minutes out at work inside the window) beside it. Without it, 0620's comparison exactly.
$o642$,
$n642$  -- and d_out (minutes out at work inside the window) beside it. Without it, 0620's comparison exactly.
  -- 0642 (G384): after lateness and before the minutes in the depot, the owner's contract (rule 9): the summed minutes
  -- cars wait past their contract's queue wait (breach2_sum over both visits when both sides carry it, else
  -- breach_sum; a minute of rounding), d_breach beside. Without breach_sum on both sides, 0623's comparison exactly.
$n642$),
('public.ottoq_charge_line_compare(jsonb,jsonb)', 2,
$o642$  SELECT jsonb_build_object('cmp', x.cmp, 'by', x.by, 'd_on_time', x.dot, 'd_late', x.dl, 'd_flow', x.df)
         || CASE WHEN x.two THEN jsonb_build_object('d_flow1', x.df1, 'd_out', x.dout) ELSE '{}'::jsonb END$o642$,
$n642$  SELECT jsonb_build_object('cmp', x.cmp, 'by', x.by, 'd_on_time', x.dot, 'd_late', x.dl, 'd_flow', x.df)
         || CASE WHEN x.two THEN jsonb_build_object('d_flow1', x.df1, 'd_out', x.dout) ELSE '{}'::jsonb END
         || CASE WHEN x.b1 THEN jsonb_build_object('d_breach', x.db) ELSE '{}'::jsonb END              -- 0642$n642$),
('public.ottoq_charge_line_compare(jsonb,jsonb)', 3,
$o642$                      WHEN s.al < s.kl - 0.5 THEN 1 WHEN s.al > s.kl + 0.5 THEN -1
                      WHEN s.af < s.kf - 1.0 THEN 1 WHEN s.af > s.kf + 1.0 THEN -1 ELSE 0 END AS cmp,
                 CASE WHEN s.ao <> s.ko THEN 'on_time' WHEN abs(s.al - s.kl) > 0.5 THEN 'lateness'
                      WHEN abs(s.af - s.kf) > 1.0 THEN 'flow' ELSE 'tie' END AS by,$o642$,
$n642$                      WHEN s.al < s.kl - 0.5 THEN 1 WHEN s.al > s.kl + 0.5 THEN -1
                      WHEN s.ab < s.kb - 1.0 THEN 1 WHEN s.ab > s.kb + 1.0 THEN -1                               -- 0642
                      WHEN s.af < s.kf - 1.0 THEN 1 WHEN s.af > s.kf + 1.0 THEN -1 ELSE 0 END AS cmp,
                 CASE WHEN s.ao <> s.ko THEN 'on_time' WHEN abs(s.al - s.kl) > 0.5 THEN 'lateness'
                      WHEN abs(s.ab - s.kb) > 1.0 THEN 'contract_wait'                                           -- 0642
                      WHEN abs(s.af - s.kf) > 1.0 THEN 'flow' ELSE 'tie' END AS by,
                 s.b1, round(s.ab - s.kb, 2) AS db,$n642$),
('public.ottoq_charge_line_compare(jsonb,jsonb)', 4,
$o642$                         y.two,
$o642$,
$n642$                         y.two, y.b1,
                         CASE WHEN y.b2 THEN (p_kernel ->> 'breach2_sum')::numeric
                              WHEN y.b1 THEN (p_kernel ->> 'breach_sum')::numeric ELSE 0 END AS kb,             -- 0642
                         CASE WHEN y.b2 THEN (p_agent ->> 'breach2_sum')::numeric
                              WHEN y.b1 THEN (p_agent ->> 'breach_sum')::numeric ELSE 0 END AS ab,
$n642$),
('public.ottoq_charge_line_compare(jsonb,jsonb)', 5,
$o642$                    FROM (SELECT (jsonb_typeof(p_kernel -> 'flow2_sum') = 'number'
                                  AND jsonb_typeof(p_agent -> 'flow2_sum') = 'number') AS two) y) s) x$o642$,
$n642$                    FROM (SELECT (jsonb_typeof(p_kernel -> 'flow2_sum') = 'number'
                                  AND jsonb_typeof(p_agent -> 'flow2_sum') = 'number') AS two,
                                 COALESCE(jsonb_typeof(p_kernel -> 'breach_sum') = 'number'
                                          AND jsonb_typeof(p_agent -> 'breach_sum') = 'number', false) AS b1,     -- 0642
                                 COALESCE(jsonb_typeof(p_kernel -> 'breach2_sum') = 'number'
                                          AND jsonb_typeof(p_agent -> 'breach2_sum') = 'number', false) AS b2) y) s) x$n642$),
('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', 1,
$o642$    'ttl_ticks', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15),
$o642$,
$n642$    'ttl_ticks', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15),
    -- 0642 (G384): how the kernel orders its own line after immediate dispatch: a car that has waited floor_min or
    -- longer first, the longest wait first; then by minutes of charge (by = 'charge_minutes') or points ('points')
    'kernel_order', jsonb_build_object(
      'floor_min', GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_wait_floor_min', 90), 90), 0),
      'by', CASE WHEN COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_order_minutes', 1), 1) >= 1
                 THEN 'charge_minutes' ELSE 'points' END),
$n642$);

DO $patch$
DECLARE f record; q record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0642_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR q IN SELECT * FROM _0642_patch WHERE fn = f.fn ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, q.c_old, ''))) / length(q.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0642 %: anchor % matches % times, not 1', f.fn, q.seq, n;
      END IF;
      v_def := replace(v_def, q.c_old, q.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(f.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0642 %: not stored as patched', f.fn;
    END IF;
  END LOOP;
END $patch$;


-- ══ V1: each body stored as patched, and the cursor reads the keys ═══════════════════════════════════════════════════════
DO $v1$
DECLARE v_src text;
BEGIN
  v_src := regexp_replace(regexp_replace((SELECT prosrc FROM pg_proc WHERE oid = 'public.ottoq_decide_tick(uuid)'::regprocedure),
                                         '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
  IF strpos(v_src, 'public.ottoq_charge_order_keys(p_sim_run_id, v_depot, v_clock)') = 0
     OR strpos(v_src, '(v_ok -> v.id::text ->> 0)::numeric DESC NULLS LAST') = 0
     OR strpos(v_src, '(v_ok -> v.id::text ->> 1)::numeric DESC NULLS LAST') = 0 THEN
    RAISE EXCEPTION '0642 V1: the decide tick does not read the keys';
  END IF;
  IF strpos(v_src, '(v_ok -> v.id::text ->> 1)::numeric DESC NULLS LAST')
     > strpos(v_src, 'GREATEST(public.ottoq_effective_target_soc_at(v.id, v_clock) - v.current_soc, 1))') THEN
    RAISE EXCEPTION '0642 V1: the keys do not sort before 0545''s ratio';
  END IF;
  RAISE NOTICE '0642 V1: eight bodies stored as patched; the cursor reads ottoq_charge_order_keys once per tick and sorts by the floor, then minutes, before 0545''s ratio';
END $v1$;

-- ══ V2: without the keys in the state, the simulator and the comparison are 0641's, key for key ════════════════════════
DO $v2$
DECLARE v_n int; v_diff int; v_cmp int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE x.r0 IS DISTINCT FROM p.r0 OR x.r1 IS DISTINCT FROM p.r1),
         count(*) FILTER (WHERE public.ottoq_charge_line_compare(x.r0, x.r1) IS DISTINCT FROM p.cmp)
    INTO v_n, v_diff, v_cmp
    FROM _0642_pre p
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = p.order_id
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_line_schedule(s.state, NULL, 0, s.seed, true) AS r0,
                               public.ottoq_charge_line_schedule(s.state, s.agent_order, 3, s.seed, true) AS r1) x;
  IF v_diff > 0 OR v_cmp > 0 THEN
    RAISE EXCEPTION '0642 V2: % of % stored states simulate differently (% compare differently) without the keys', v_diff, v_n, v_cmp;
  END IF;
  RAISE NOTICE '0642 V2: % stored states (the expected future with no order, a sampled future with the agent''s) simulate and compare as before, key for key', v_n;
END $v2$;

-- ══ V3: with the keys, the state and the simulator carry them; the keys execute on the twin depot ════════════════════════
DO $v3$
DECLARE
  c_twin constant uuid := '11111111-1111-1111-1111-111111111111';
  s record; v_st jsonb; v_r jsonb; v_k int; v_t timestamptz;
BEGIN
  SELECT sn.order_id, sn.sim_run_id, sn.sim_clock, sn.state, sn.seed INTO s FROM public.ottoq_charge_order_snapshots sn
   WHERE sn.depot_id = c_twin ORDER BY sn.order_id DESC LIMIT 1;
  IF s.order_id IS NULL THEN
    RAISE NOTICE '0642 V3: no stored order; the keys are executed by the tests';
    RETURN;
  END IF;
  v_t := clock_timestamp();
  SELECT count(*) INTO v_k FROM public.ottoq_charge_order_keys(s.sim_run_id, c_twin, s.sim_clock);
  v_st := public.ottoq_charge_line_state(s.sim_run_id, c_twin, s.sim_clock);
  IF (v_st ->> 'order_minutes') IS DISTINCT FROM 'true' OR (v_st ->> 'floor_min')::numeric IS DISTINCT FROM 90 THEN
    RAISE EXCEPTION '0642 V3: the state does not carry the kernel''s keys at their defaults: % %', v_st -> 'order_minutes', v_st -> 'floor_min';
  END IF;
  -- the stored state at that order, given the keys and each car's ordering minutes from its own clock times
  v_r := public.ottoq_charge_line_schedule(
           s.state || jsonb_build_object('order_minutes', true, 'floor_min', 90,
             'cars', COALESCE((SELECT jsonb_agg(c.value || jsonb_build_object('om', GREATEST(LEAST((c.value ->> 'md')::numeric,
                                                                                                  (c.value ->> 'ml')::numeric), 1),
                                                                         'mw', 30) ORDER BY c.o)
                                 FROM jsonb_array_elements(s.state -> 'cars') WITH ORDINALITY c(value, o)), '[]'::jsonb)),
           NULL, 0, s.seed, true);
  IF jsonb_typeof(v_r -> 'breach_sum') IS DISTINCT FROM 'number' OR jsonb_typeof(v_r -> 'breach_n') IS DISTINCT FROM 'number' THEN
    RAISE EXCEPTION '0642 V3: the simulator with the keys reports no breach: %', v_r - 'seats' - 'return_seats';
  END IF;
  RAISE NOTICE '0642 V3: the keys execute on the twin depot (% cars waiting now); the state carries order_minutes and floor_min 90; order % replayed with the keys: % cars past their contract wait by % minutes in all (% s)',
    v_k, s.order_id, v_r ->> 'breach_n', v_r ->> 'breach_sum', round(extract(epoch FROM clock_timestamp() - v_t)::numeric, 2);
END $v3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0642_the_kernel_serves_a_long_wait_first_and_times_its_line_in_minutes', true, true,
  'The kernel''s own charge order (OTTO-Q''s seat) puts a car that has waited charge_wait_floor_min (90) first, the '
  'longest wait first, then orders by the response ratio in minutes of charge on the depot''s charge clock '
  '(charge_order_minutes), before 0545''s ratio in points (G384). Mirrored in the kernel''s order, the cockpits'' queue, '
  'the board and the check''s state and simulator; the check compares contract-wait breach after lateness. TRUE/TRUE: '
  'every run''s seating order changes at the defaults, as 0545, 0546 and 0551 did.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
