-- migration-version: 20261018111537
-- migration-name:    the_bay_line_serves_the_car_that_rejoins_service_soonest
--
-- 0747  **The bay line serves first the car that will be back in service soonest. An urgent repair is fitted in around
--       the others, unless it is a safety emergency or has waited too long.** (G461)
--       Chase, 2026-10-17 evening CT: an urgent issue (an urgent flat tire, an urgent battery check) means the car is
--       brought back to the depot and looked at immediately. In the depot it is fitted in around the cars that can rejoin
--       the robotaxi earning state right away, and does not supersede a car in for a standard or timely service. Rule 9
--       stands: queueing is allowed, sacrificing a car's needs is not, and an emergency (a vehicle taken offline or routed
--       at once to a service stall) is the one exception. Research wing, rule 10: a dial, measured in the twin, then a
--       certified change.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-17 between 7:10 and 7:37 PM CT; db/checks/0452 queries (3)-(5)) ═════════════
--
--   The recall side already does what Chase asks: both recall implementations (public.ottoq_recall_naive_threshold_v1,
--   public.ottoq_recall_interval_scheduled_v1) send a car home at once, not deferrable, for a safety-critical fault
--   (rung 1, lead 0 ticks), a major fault (rung 2, lead 1), a low battery and a rider-flagged cleaning.
--   The depot side does the opposite. Decide section (4b) seats the wash, detail and service bays in this order:
--   urgency first (critical > overdue > due > due_soon > ok), then resumed work, then minutes to the car's deploy
--   time, then open must-do minutes, then the car's id. Its urgency is the card's overall_urgency, the most urgent of
--   all the car's needs, so a car with any critical need goes ahead of a car one short service from earning: it was
--   critical on 2,090 of the 3,875 bay decisions of the 5 busy days and 264 of the 1,149 of the 6 normal days. The last
--   two keys carry little:
--     - minutes_to_deploy comes from the car's drawn next_deploy_at; on the busy days 2,638 of the 3,875 cars were
--       already past it (median -431 minutes) and 901 had none;
--     - open_must_do_min (public.ottoq_vehicle_needs_card) sums open visits only (status 'open', not 'in_progress'),
--       with no run scope and no test of whether an atom is done. It read 0 on 3,554 of the 3,875 busy-day decisions and
--       1,146 of the 1,149 normal-day ones, so the shortest-job term the comment promises does not run.
--   Measured on those runs, the service bays are the contended line (2 bays). On the 5 busy days decide (4b) passed
--   over mechanical_pm 1,411 times, fault_repair 826, sensor_calibration 378 (noop_no_candidate), and on the 6 normal
--   days 30, 67 and 18.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Dials, neither agent-writable: bay_order_uptime_first (0..1, default 0) and bay_wait_floor_min (30..480,
--       default 90, the charge line's floor from 0642).
--   (b) public.ottoq_bay_uptime_order_key(run, car, need, is_resume, clock): NULL below 1, else an ascending key:
--         1. a safety emergency first: the bay need is a fault repair, and the car's drawn fault is severity 1 (the
--            card's critical grade) or its open repair is for one of the twin's two hazard classes, an HV battery
--            thermal event or a charge-system fault (rule 9's exception: routed at once). The other in-depot faults,
--            a sensor suite or compute fault and the immobilizing drive or steering and brake faults, are urgent but
--            not hazards: the car is home, offline and parked, and is fitted in like any repair;
--         2. then any car that has waited the floor or longer since it last changed state, the longest wait first
--            (no car starves, the urgent repair included);
--         3. then work the depot already started and took away (resumed bay work, the 0003 key);
--         4. then cars with no open fault repair before cars with one: an urgent repair is fitted in around the cars
--            that rejoin service after this bay;
--         5. then the least must-do work left on the car's own visit in this run, counting the work that holds a space
--            (charge, wash, detail, service bay; not the cabin and digital work done in place). That is the car back in
--            service soonest, the shortest-job rule.
--       Ties fall through to today's keys, unchanged.
--   (c) Decide section (4b): the key is computed once per candidate, put first in both of its orders (the seat rank and
--       the cursor), and recorded on the decision's context as uptime_key only when it is set. At 0 the key is NULL for
--       every car, NULLs tie, and the order and the decision rows are byte-identical to today's.
--   (d) Cells: robowash_normal_2026_10_18 gains cell 4, robotic lanes with the dial (its contrast is cell 3, robotic
--       lanes alone; its declared control is cell 1). A new sweep uptimefirst_busy_2026_10_18 holds the busy day, where
--       the service bays are contended: robotic lanes alone, then with the dial. Same seed, priority 14.
--   Not changed: what a car needs, the recall, which bay a need goes to, how long anything takes, the departure test
--   (rule 9: no car leaves with a needed service open), the charge line, and the true emergency path of the exception
--   handler.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the decide is the body 0746 left (prosrc md5 b90378b7); the tables the key reads exist; no
--   dial, function or sweep of this file exists; 0746's sweep holds its three cells and no fourth. P2 not already
--   applied. Pre-image to ottoq_schema_snapshots as '0747_pre'. Each anchor matches once. V1 the body less its
--   insertions is its pre-image. V2 at the dial's default the key is NULL. V3 the dials are catalogued as declared and
--   the cells are as declared. The key is executed by tests/test_bay_uptime_order_sql.py.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. At the dial's default the key is NULL for every candidate, so
--   both orders are today's (V1), and the decision's context carries no new field. No certification arm, canon cell or
--   dial experiment sets the dial.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0747_pre'; DROP FUNCTION
--   public.ottoq_bay_uptime_order_key(uuid, uuid, text, boolean, timestamptz); if no arm has run, DELETE the sweep
--   uptimefirst_busy_2026_10_18 and its cells, cell 4 of robowash_normal_2026_10_18, and the two dials' catalog rows;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0747_the_bay_line_serves_the_car_that_rejoins_service_soonest'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0747 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the body 0746 left, the tables the key reads, 0746's sweep, nothing of this file ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_decide_tick(uuid)'))
     IS DISTINCT FROM 'b90378b7b46b7adcfa4ef938a791d395' THEN
    RAISE EXCEPTION '0747 P1: public.ottoq_decide_tick is not the body 0746 left (md5 b90378b7)';
  END IF;
  IF to_regclass('public.vehicle_need_profile') IS NULL OR to_regclass('public.ottoq_visit_needs') IS NULL
     OR to_regclass('public.service_cadence_policy') IS NULL
     OR to_regprocedure('public.ottoq_policy_get(uuid,text,numeric)') IS NULL THEN
    RAISE EXCEPTION '0747 P1: a table or function the key reads is missing';
  END IF;
  IF to_regprocedure('public.ottoq_bay_uptime_order_key(uuid,uuid,text,boolean,timestamp with time zone)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                 WHERE param_key IN ('bay_order_uptime_first', 'bay_wait_floor_min'))
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'uptimefirst_busy_2026_10_18') THEN
    RAISE EXCEPTION '0747 P1: the function, a dial or the sweep of this file already exists';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'robowash_normal_2026_10_18') <> 3
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                     WHERE s.sweep_code = 'robowash_normal_2026_10_18' AND c.cell_code = 'dcfc40.otto_q.wash_robotic'
                       AND c.fixed_params = '{"deploy_peak_fraction": 0.90, "wash_lane_physics": 2}'::jsonb) THEN
    RAISE EXCEPTION '0747 P1: 0746''s sweep robowash_normal_2026_10_18 is not its three cells as written';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0747_the_bay_line_serves_the_car_that_rejoins_service_soonest') THEN
    RAISE EXCEPTION '0747 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0747_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_decide_tick(uuid)'::regprocedure;

-- ── (a) the dials ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('bay_order_uptime_first',
        '0747 (G461): 1 = decide section (4b) seats the wash, detail and service bays uptime first: a safety emergency '
        '(a severity-1 fault, or an HV battery thermal event or charge-system fault) first, then any car that has waited bay_wait_floor_min or longer (the longest first), then '
        'resumed work, then cars with no open fault repair before cars with one, then the least must-do work left on the '
        'car''s visit; ties fall to the order before 0747. 0 = urgency first, as before 0747. Research days only until '
        'certified.',
        0, 0, 1, 'public.ottoq_bay_uptime_order_key, public.ottoq_decide_tick (4b)', false),
       ('bay_wait_floor_min',
        '0747: under bay_order_uptime_first, a car that has waited this many minutes since it last changed state goes '
        'ahead of every car that has not, the longest wait first, so a repair fitted in around others never starves. 90 '
        'is the charge line''s floor (0642).',
        90, 30, 480, 'public.ottoq_bay_uptime_order_key', false);

-- ── (b) the key ──
CREATE FUNCTION public.ottoq_bay_uptime_order_key(p_sim_run_id uuid, p_vehicle_id uuid, p_svc text,
                                                  p_is_resume boolean, p_clock timestamptz)
RETURNS numeric[]
LANGUAGE plpgsql
STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
-- 0747 (G461): the uptime-first key of one bay candidate, ascending, or NULL with bay_order_uptime_first off. Chase,
-- 2026-10-17: an urgent issue brings a car home at once (the recall already does) and is fitted in around the cars that
-- rejoin service soonest; it does not supersede a car in for standard or timely service. Rule 9's emergency goes first,
-- and a car past the wait floor goes next, so no car's needs are sacrificed to the order.
DECLARE
  v_floor numeric; v_wait numeric; v_sev int; v_fault boolean; v_hazard boolean; v_rem numeric;
BEGIN
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_order_uptime_first', 0), 0) < 1 THEN
    RETURN NULL;
  END IF;
  v_floor := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_wait_floor_min', 90), 90);
  SELECT GREATEST(0, EXTRACT(EPOCH FROM (p_clock - v.last_state_change)) / 60.0) INTO v_wait
    FROM public.vehicles v WHERE v.id = p_vehicle_id;
  SELECT p.worst_fault_severity INTO v_sev FROM public.vehicle_need_profile p WHERE p.vehicle_id = p_vehicle_id;
  -- the car's own visit in this run: must-do work not yet done, counting only the work that holds a space
  SELECT bool_or(a ->> 'svc' = 'fault_repair'),
         -- the twin's hazard classes (twin.ottoq_sim_vehicle_exception_handler: immobilizing and service-incompatible)
         bool_or(a ->> 'svc' = 'fault_repair' AND a ->> 'fault_class' IN ('hv_battery_thermal', 'charge_system_fault')),
         COALESCE(sum(COALESCE(CASE WHEN (a ->> 'est_min') ~ '^[0-9]+(\.[0-9]+)?$' THEN (a ->> 'est_min')::numeric END,
                               cp.est_min_default, 0)), 0)
    INTO v_fault, v_hazard, v_rem
    FROM public.ottoq_visit_needs n
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(n.atoms, '[]'::jsonb)) a
    JOIN public.service_cadence_policy cp ON cp.svc = a ->> 'svc' AND cp.is_active
                                         AND cp.lane IN ('anchor', 'wash_bay', 'detail', 'service_bay')
   WHERE n.vehicle_id = p_vehicle_id AND n.sim_run_id = p_sim_run_id AND n.status IN ('open', 'in_progress')
     AND COALESCE((a ->> 'must_do')::boolean, false)
     AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled', 'skipped');
  RETURN ARRAY[
    CASE WHEN p_svc = 'fault_repair' AND (COALESCE(v_sev, 99) = 1 OR COALESCE(v_hazard, false))
         THEN 0 ELSE 1 END,                                                             -- 1. a safety emergency
    CASE WHEN COALESCE(v_wait, 0) >= v_floor THEN 0 ELSE 1 END,                         -- 2. past the wait floor,
    CASE WHEN COALESCE(v_wait, 0) >= v_floor THEN -round(v_wait, 3) ELSE 0 END,         --    the longest wait first
    CASE WHEN COALESCE(p_is_resume, false) THEN 0 ELSE 1 END,                           -- 3. work already started
    CASE WHEN COALESCE(v_fault, false) THEN 1 ELSE 0 END,                               -- 4. a repair fits in around
    round(COALESCE(v_rem, 0), 3)                                                        -- 5. soonest back in service
  ]::numeric[];
END
$fn$;
REVOKE ALL ON FUNCTION public.ottoq_bay_uptime_order_key(uuid, uuid, text, boolean, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_bay_uptime_order_key(uuid, uuid, text, boolean, timestamptz) TO service_role;

-- ── (c) decide section (4b) ──
CREATE TEMP TABLE _0747_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0747_patch VALUES
  -- 1: the key, once per candidate
  (1, $o1$                 pk.eff_rank, v.fleet_operator_id
            FROM pick pk$o1$,
   $n1$                 pk.eff_rank, v.fleet_operator_id,
                 -- 0747 (G461): the uptime-first key, NULL with bay_order_uptime_first off (then NULLs tie, and the
                 -- order below is the order before 0747)
                 public.ottoq_bay_uptime_order_key(p_sim_run_id, pk.vehicle_id, pk.svc, pk.is_resume, v_clock) AS upf_key
            FROM pick pk$n1$),
  -- 2: first in the seat rank
  (2, $o2$row_number() OVER (ORDER BY rk.eff_rank DESC,$o2$,
   $n2$row_number() OVER (ORDER BY rk.upf_key ASC NULLS LAST,   -- 0747
                                             rk.eff_rank DESC,$n2$),
  -- 3: first in the cursor
  (3, $o3$          FROM ranked rk
         ORDER BY rk.eff_rank DESC,$o3$,
   $n3$          FROM ranked rk
         ORDER BY rk.upf_key ASC NULLS LAST,   -- 0747
                  rk.eff_rank DESC,$n3$),
  -- 4: on the decision's context, only when it is set
  (4, $o4$                      'requires_charging','false','service', v_need.purpose);$o4$,
   $n4$                      'requires_charging','false','service', v_need.purpose)
                 || CASE WHEN v_need.upf_key IS NULL THEN '{}'::jsonb
                         ELSE jsonb_build_object('uptime_key', to_jsonb(v_need.upf_key)) END;   -- 0747$n4$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  FOR p IN SELECT * FROM _0747_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0747: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0747: the decide is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the patched body less its insertions is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc WHERE oid = 'public.ottoq_decide_tick(uuid)'::regprocedure;
  FOR p IN SELECT * FROM _0747_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'b90378b7b46b7adcfa4ef938a791d395' THEN
    RAISE EXCEPTION '0747 V1: the decide less its insertions is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: at the dial's default the key is NULL ──
DO $v2$
BEGIN
  IF public.ottoq_bay_uptime_order_key('00000000-0000-0000-0000-00000000747a', '00000000-0000-0000-0000-00000000747b',
                                       'fault_repair', false, now()) IS NOT NULL THEN
    RAISE EXCEPTION '0747 V2: at the default the key is set';
  END IF;
END $v2$;

-- ── (d) the cells ──
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params, control_cell_code)
SELECT s.sweep_id, 'dcfc40.otto_q.wash_robotic.uptime_first', 4, 'otto_q', 'dcfc40',
       '{"deploy_peak_fraction": 0.90, "wash_lane_physics": 2, "bay_order_uptime_first": 1}'::jsonb, 'dcfc40.otto_q'
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'robowash_normal_2026_10_18';
INSERT INTO public.ottoq_throughput_sweeps (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick,
                                            seeds, replicates, priority, arm_budget_s, status, notes)
VALUES ('uptimefirst_busy_2026_10_18',
        'The bay line uptime first on the busy day, on forty robotic posts and robotic wash lanes',
        '11111111-1111-1111-1111-111111111111', 'busy_day', '2026-09-01 11:00:00+00', 144, 5,
        ARRAY[686364201590009433]::bigint[], 0, 14, 5400, 'active',
        '0747 (G461). Cell 1 is dcfc40_power_busy_2026_10_17''s first cell (dcfc40.otto_q) with robotic wash lanes '
        '(wash_lane_physics 2); cell 2 adds bay_order_uptime_first. value_2026_09_30''s first seed.');
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc40.otto_q.wash_robotic', 1, 'otto_q', 'dcfc40',
       '{"deploy_peak_fraction": 0.90, "wash_lane_physics": 2}'::jsonb
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'uptimefirst_busy_2026_10_18';
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params, control_cell_code)
SELECT s.sweep_id, 'dcfc40.otto_q.wash_robotic.uptime_first', 2, 'otto_q', 'dcfc40',
       '{"deploy_peak_fraction": 0.90, "wash_lane_physics": 2, "bay_order_uptime_first": 1}'::jsonb,
       'dcfc40.otto_q.wash_robotic'
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'uptimefirst_busy_2026_10_18';

-- ── V3: the dials and the cells ──
DO $v3$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog
       WHERE NOT COALESCE(agent_writable, false)
         AND ((param_key, default_value, min_value, max_value) IN (('bay_order_uptime_first', 0, 0, 1),
                                                                   ('bay_wait_floor_min', 90, 30, 480)))) <> 2 THEN
    RAISE EXCEPTION '0747 V3: the dials are not catalogued as declared';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'robowash_normal_2026_10_18') <> 4
     OR (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
          WHERE s.sweep_code = 'uptimefirst_busy_2026_10_18') <> 2
     OR (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
          WHERE s.sweep_code IN ('robowash_normal_2026_10_18', 'uptimefirst_busy_2026_10_18')
            AND c.fixed_params ->> 'bay_order_uptime_first' = '1'
            AND c.fixed_params - 'bay_order_uptime_first' = '{"deploy_peak_fraction": 0.90, "wash_lane_physics": 2}'::jsonb) <> 2
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps s JOIN public.ottoq_throughput_sweeps sp
                      ON sp.sweep_code = 'dcfc40_power_busy_2026_10_17'
                     WHERE s.sweep_code = 'uptimefirst_busy_2026_10_18'
                       AND (s.scenario, s.sim_start, s.ticks, s.sim_min_per_tick, s.seeds[1])
                         = (sp.scenario, sp.sim_start, sp.ticks, sp.sim_min_per_tick, sp.seeds[1])) THEN
    RAISE EXCEPTION '0747 V3: the cells are not as declared';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0747_the_bay_line_serves_the_car_that_rejoins_service_soonest', false, false,
        'Dials bay_order_uptime_first (default 0) and bay_wait_floor_min. New public.ottoq_bay_uptime_order_key (NULL at 0), '
        'put first in decide section (4b)''s two orders and recorded on the decision''s context only when set. V1: the body '
        'less its insertions is its pre-image; at 0 the key is NULL for every car, so the order and the decision rows are '
        'today''s. Cells: robowash_normal_2026_10_18 cell 4 and uptimefirst_busy_2026_10_18 (two cells), priority 14. No '
        'certification arm, canon cell or dial experiment sets the dial.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-18 11:15:37 UTC (6:15 AM CT), ledger version 20261018111537 ══════════════════════════════════════
--
--   Through apply_migration after 0746 (its P1 read 0746's decide, b90378b7), with nothing in flight (no run live and
--   nothing in flight, read before and after; the file's own P0 at the apply). The text sent, BEGIN through COMMIT and
--   one newline, is 15,279 characters, md5 48e802dd10e2b46693afa04c6f941ebd, equal to the ledger's statements[1] read
--   back; its executable part is 15,263 characters, md5 298b933759473f804779b3ea0c0e5a54, equal to this file's.
--   public.ottoq_decide_tick is now md5 fc843b9e0d50ec33325ef32ac296759a and public.ottoq_bay_uptime_order_key
--   8d395ffe7d79d5d4149f08755dff4078 (prosrc), the bodies the dry run and the key's hazard-class probe of 2026-10-17
--   evening left. robowash_normal_2026_10_18 now has its four cells and uptimefirst_busy_2026_10_18 its two, priority
--   14.
--
--   End to end on live, rolled back by its own raise at 11:47:26 UTC (6:47 AM CT): a probe run at the twin depot; three
--   staged cars at 100% with every other need fresh, one needing mechanical_pm (24 minutes, the needs card's urgency
--   critical), one fault_repair (101 minutes, severity 2, overdue) and one fault_repair whose atom carries fault_class
--   hv_battery_thermal (severity 2, overdue). Section (4b)'s patched cursor, taken from the decide's prosrc between 'FOR
--   v_need IN' and the first newline-LOOP with the run, depot and clock substituted: at bay_order_uptime_first 0 the
--   order was the PM car, the repair, the thermal car, every upf_key NULL (urgency first); at 1 the thermal car first
--   [0,1,0,1,1,101], the PM car second [1,1,0,1,0,24] and the severity-2 repair third [1,1,0,1,1,101].
