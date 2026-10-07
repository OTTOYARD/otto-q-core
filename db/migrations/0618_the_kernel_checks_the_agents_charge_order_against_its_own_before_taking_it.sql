-- migration-version: PENDING
-- migration-name:    the_kernel_checks_the_agents_charge_order_against_its_own_before_taking_it
--
-- 0618  **The kernel checks the agent's charge order against its own before it takes it.** When the agent sends an
--       order, its door (`ottoq_agent_charge_order_record`) now projects the charge line twice from the same moment,
--       once in the kernel's own order and once in the agent's, and takes the agent's only when the projection says it
--       is no worse: at least as many cars ready by their due time and the whole line ready no later, or more cars
--       ready by their due time for at most 10% more total time. Otherwise the order is recorded as `refused`, with
--       both projections and the reason, and the kernel's order stands. The charge cursor reads only accepted orders
--       (0614's `ottoq_agent_charge_order_live`), so a refused order never seats a car.
--
-- ══ §1 WHY (db/checks/0415, run 0bbdcc07 against 81787ef9, same scenario and seed, both cut at sim 15:11:06) ══════════
--
--   0614 took the agent's order whole: after immediate dispatch and the 90-minute pin, the agent's rank decided who took
--   the next free charger. Measured on the first run under an order, against the same seed without one, over the same
--   2.19 sim-hours: uptime 33.2% against 40.6%, 61 departures against 71, 39.4% of cars with a due time ready by it
--   against 45.2%, 46 cars still waiting for a charger at the end against 36. Energy to the cars was the same (1,681 kWh
--   against 1,673) and each kind of charger charged each band of battery at the same rate, so the depot did the same
--   work for fewer cars. The decision ledger shows why. The agent ranked low batteries first and named them for a fast
--   charger; on a tick when only an L2 was free, 0614's key still put them ahead of every car it had not named, so six
--   cars at 13% to 44% took an L2 for 2 to 3.5 hours each (0617 fixed that key), while seven cars at 86% to 93%, which
--   the kernel had plugged in within 35 minutes, waited 137 to 188 minutes. Nothing in 0614 compared the agent's order
--   with the kernel's before acting on it. CLAUDE.md: "agents propose, solver disposes"; "assignment plus
--   verification, always". This is the verification.
--
-- ══ §2 WHAT ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq_charge_line_projection(run, depot, clock, order)`: a deterministic list schedule of the charge line from
--       `clock`. The line is `ottoq_charge_queue_kernel_order` (less a car that holds a reserved charger, which is
--       already assigned). Chargers are the depot's dcfc and L2 stalls that are free now (the board's own test) or
--       charging a car (free when that car reaches its target); faulted ones and ones held for something else are left
--       out. Each car's minutes on each kind are `ottoq_charge_minutes_estimate` on the depot's fastest charger of the
--       kind, to rule 9's one target, as the agent's board shows them. Whenever chargers are free, the unseated cars
--       are taken in the cursor's own order (immediate dispatch, then, under an order, the cars waited past the pin,
--       then `ottoq_agent_charge_order_key` with the kinds free at that moment, then the kernel's order), and each takes
--       a free charger of the kind it wants (the stall pick's rule: the order's kind, except for an immediate
--       dispatch; else dcfc below 45% or for an immediate dispatch, l2 otherwise), or the other kind it can plug into
--       when that is all that is free. A car charges to its full target on whichever charger it takes; nothing in the
--       projection, or anywhere in this file, shortens a charge (rule 9). It reports, from `clock`: the cars, the cars
--       ready by their due time, the minutes to ready summed over the line, the summed lateness, and the last start.
--       A car not plugged in within 480 minutes counts at 480 plus its fastest charge.
--   (b) `ottoq_charge_order_verdict(kernel, agent)`: pure. Fewer cars ready by their due time: refused. More: taken if
--       the line's total minutes to ready is at most 10% more, else refused. Equal: taken if the total is no more than
--       the kernel's (half a minute of rounding), else refused.
--   (c) The door runs both projections when the order names at least one car, records the verdict in the new
--       `projection` column, and sets status `refused` when the verdict refuses; a projection that fails refuses too
--       (`projection_failed`), so an unchecked order is never taken. The receipt carries the verdict.
--   (d) `ottoq_agent_charge_order_usage` counts `orders_refused`, and each order in `by_order` carries its `verdict`.
--   (e) The agent's board (`ottoq_agent_charge_queue_board`) shows `last_order.projection`, so the agent reads why its
--       last order was refused, and by how much.
--
--   The tick path is untouched: the cursor, the key, the stall pick and the live read are the ones 0614 and 0617 left.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the door, the usage read and the board are 0614/0616's bodies, the key is 0617's, the
--   kernel's order and the minutes estimate are 0614's (md5 of each source); the status check is 0614's; no lineage row.
--   V1: the verdict's truth table. V2: on a running twin run, the kernel's projection is computed twice and agrees with
--   itself, and the verdict of the kernel against itself is taken. tests/test_agent_charge_order_sql.py executes the
--   projection, the verdict, the door, the usage read and the board on stubs: an order that sends low batteries to the
--   only free L2s ahead of short charges is refused; one that gets a car to its due time on a fast charger is taken;
--   the kernel's own order is taken; a refused order changes nothing in the line.
--
-- ══ §4 RECERT ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   FALSE/FALSE. Only the door, the usage read and the board change, and the door records an order only when
--   agent_charge_order = 1, which only an operator_demo run arms (0615); no certification, sweep or dial pair runs one.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0618_pre';
--   DROP FUNCTION public.ottoq_charge_order_verdict(jsonb, jsonb);
--   DROP FUNCTION public.ottoq_charge_line_projection(uuid, uuid, timestamptz, jsonb);
--   (the `projection` column and the wider status check may stay: nothing else reads them);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0618_the_kernel_checks_the_agents_charge_order_against_its_own_before_taking_it'.

BEGIN;

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0618 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)', '37b845872bf4998e34260c5ed22d2eb3', 'the door (0614)'),
      ('public.ottoq_agent_charge_order_usage(uuid,integer)',                  '3b18ab05670fc2dc83cfb811e8279158', 'the usage read (0616)'),
      ('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', '8713a5caa9260046fdae66ca64935b0f', 'the board (0614)'),
      ('public.ottoq_agent_charge_order_key(jsonb,uuid,text)',                 'fd6ac38a8af8f5198f622782b616b506', 'the key (0617)'),
      ('public.ottoq_charge_queue_kernel_order(uuid,uuid,timestamp with time zone)', '7582ced28b18b05068f5279966d82020', 'the kernel''s order (0614)'),
      ('public.ottoq_charge_minutes_estimate(numeric,numeric,numeric,numeric,numeric)', '21f22ff887d40b57a3039f5d65e978af', 'the minutes estimate (0614)'))
    AS x(sig, md5, what)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = r.sig::regprocedure) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0618 P1: % is not the body this file was written against (md5 %); read it again', r.what, left(r.md5, 8);
    END IF;
  END LOOP;
  IF (SELECT pg_get_constraintdef(c.oid) FROM pg_constraint c
       WHERE c.conrelid = 'public.ottoq_agent_charge_orders'::regclass AND c.conname = 'ottoq_agent_charge_orders_status_check')
     IS DISTINCT FROM 'CHECK ((status = ANY (ARRAY[''accepted''::text, ''partial''::text, ''rejected''::text])))' THEN
    RAISE EXCEPTION '0618 P1: the orders ledger''s status check is not 0614''s';
  END IF;
  IF to_regprocedure('public.ottoq_charge_line_projection(uuid,uuid,timestamp with time zone,jsonb)') IS NOT NULL
     OR to_regprocedure('public.ottoq_charge_order_verdict(jsonb,jsonb)') IS NOT NULL THEN
    RAISE EXCEPTION '0618 P1: the projection or the verdict already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0618_the_kernel_checks_the_agents_charge_order_against_its_own_before_taking_it') THEN
    RAISE EXCEPTION '0618 P1: already applied';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0618_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)'::regprocedure,
                 'public.ottoq_agent_charge_order_usage(uuid,integer)'::regprocedure,
                 'public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure);

-- ══ (c, the ledger) a refused order is recorded, with the projection that refused it ═════════════════════════════════
--: The append-only trigger guards UPDATE and DELETE; adding a column and widening a check are neither.
ALTER TABLE public.ottoq_agent_charge_orders
  DROP CONSTRAINT ottoq_agent_charge_orders_status_check,
  ADD CONSTRAINT ottoq_agent_charge_orders_status_check CHECK (status IN ('accepted', 'partial', 'rejected', 'refused')),
  ADD COLUMN projection jsonb;

COMMENT ON COLUMN public.ottoq_agent_charge_orders.projection IS
'0618: the kernel''s check on this order: {take, reason, kernel, agent}, each side the charge line projected from the order''s moment (ottoq_charge_line_projection) in the kernel''s own order and in the agent''s. status = refused when take is false. NULL on orders recorded before 0618, and on an order that named no car.';

-- ══ (a) the projection ═════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_line_projection(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz, p_order jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0618: the charge line projected from p_clock as a deterministic list schedule, in the kernel's own order when p_order
   is NULL or '{}', or in the order the cursor keeps under the live order p_order ({vehicle_id: {rank, kind}}, the shape
   ottoq_agent_charge_order_live returns). Read-only. Every car charges to its full target on whichever charger it takes
   (rule 9): the projection orders the line and never shortens a charge. A projection, not a forecast: no car arrives,
   no charger faults and no order expires inside it, and both sides of a comparison see the same line and chargers. */
DECLARE
  c_horizon constant numeric := 480;
  v_on   boolean := (p_order IS NOT NULL AND jsonb_typeof(p_order) = 'object' AND p_order <> '{}'::jsonb);
  v_pin  numeric;
  v_kw_d numeric; v_kw_l numeric;
  c_id uuid[]; c_kpos int[]; c_imm boolean[]; c_pin boolean[]; c_md numeric[]; c_ml numeric[]; c_due numeric[];
  c_want text[]; c_dok boolean[]; c_lok boolean[];
  c_start numeric[]; c_ready numeric[]; c_kind text[];
  s_kind text[]; s_free numeric[];
  n int; m int; i int; j int; best int; t numeric; v_next numeric; v_mode text; v_seated int := 0; v_any boolean;
  v_dur numeric;
  v_out jsonb;
BEGIN
  v_pin := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_pin_wait_min', 90), 90);
  SELECT max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'dcfc'),
         max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'l2')
    INTO v_kw_d, v_kw_l
    FROM stalls s WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc', 'l2');

  -- the line, in the kernel's order; a car holding a reserved charger is already assigned to it
  SELECT array_agg(x.id ORDER BY x.kernel_pos), array_agg(x.kernel_pos ORDER BY x.kernel_pos),
         array_agg(x.immediate ORDER BY x.kernel_pos), array_agg(x.pinned ORDER BY x.kernel_pos),
         array_agg(x.md ORDER BY x.kernel_pos), array_agg(x.ml ORDER BY x.kernel_pos),
         array_agg(x.due ORDER BY x.kernel_pos), array_agg(x.want ORDER BY x.kernel_pos),
         array_agg(x.dok ORDER BY x.kernel_pos), array_agg(x.lok ORDER BY x.kernel_pos)
    INTO c_id, c_kpos, c_imm, c_pin, c_md, c_ml, c_due, c_want, c_dok, c_lok
    FROM (
      SELECT k.vehicle_id AS id, k.kernel_pos, k.immediate,
             (v_on AND k.wait_min >= v_pin) AS pinned,
             public.ottoq_charge_minutes_estimate(v.battery_capacity_kwh, k.soc,
               public.ottoq_effective_target_soc_at(v.id, p_clock), v_kw_d, v.inlet_max_kw) AS md,
             public.ottoq_charge_minutes_estimate(v.battery_capacity_kwh, k.soc,
               public.ottoq_effective_target_soc_at(v.id, p_clock), v_kw_l, v.inlet_max_kw) AS ml,
             extract(epoch FROM (vn.dispatch_due_at - p_clock)) / 60.0 AS due,
             CASE WHEN v_on AND NOT k.immediate AND (p_order -> k.vehicle_id::text ->> 'kind') IN ('dcfc', 'l2')
                  THEN p_order -> k.vehicle_id::text ->> 'kind'
                  WHEN k.soc < 45 OR k.immediate THEN 'dcfc' ELSE 'l2' END AS want,
             public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'dcfc') AS dok,
             public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2') AS lok
        FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, p_depot_id, p_clock) k
        JOIN vehicles v ON v.id = k.vehicle_id
        LEFT JOIN LATERAL (SELECT vn.dispatch_due_at FROM ottoq_visit_needs vn
                            WHERE vn.vehicle_id = v.id AND vn.status IN ('open', 'in_progress')
                              AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                                = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                            ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) vn ON true
       WHERE NOT k.holds_charger) x
   WHERE x.md IS NOT NULL AND x.ml IS NOT NULL;

  -- the chargers: free now by the board's own test, or charging a car and free when that car is full
  SELECT array_agg(y.kind ORDER BY y.kind, y.free_at, y.id), array_agg(y.free_at ORDER BY y.kind, y.free_at, y.id)
    INTO s_kind, s_free
    FROM (
      SELECT s.id, s.stall_type::text AS kind,
             CASE WHEN s.current_vehicle_id IS NULL THEN 0::numeric
                  ELSE public.ottoq_charge_minutes_estimate(cv.battery_capacity_kwh, cv.current_soc,
                         public.ottoq_effective_target_soc_at(cv.id, p_clock), s.connector_max_kw, cv.inlet_max_kw) END AS free_at
        FROM stalls s
        JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
        LEFT JOIN vehicles cv ON cv.id = s.current_vehicle_id
       WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc', 'l2')
         AND c.station_state IS DISTINCT FROM 'Faulted'
         AND (   (s.current_vehicle_id IS NULL
                  AND NOT (s.reserved_by IS NOT NULL AND COALESCE(s.reservation_expires_at, 'infinity'::timestamptz) > p_clock)
                  AND c.station_state = 'Available' AND c.last_heartbeat_at >= p_clock - interval '90 seconds'
                  AND NOT EXISTS (SELECT 1 FROM ottoq_stall_bookings b
                                   WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                                     AND b.state IN ('held', 'active', 'done', 'interrupted') AND b.during @> p_clock))
              OR cv.current_state::text IN ('charging_dcfc', 'charging_l2'))) y
   WHERE y.free_at IS NOT NULL;

  n := COALESCE(array_length(c_id, 1), 0);
  m := COALESCE(array_length(s_kind, 1), 0);
  c_start := array_fill(NULL::numeric, ARRAY[GREATEST(n, 1)]);
  c_ready := array_fill(NULL::numeric, ARRAY[GREATEST(n, 1)]);
  c_kind  := array_fill(NULL::text, ARRAY[GREATEST(n, 1)]);

  WHILE v_seated < n AND m > 0 LOOP
    SELECT min(f) INTO t FROM unnest(s_free) f;
    EXIT WHEN t IS NULL OR t > c_horizon;
    -- the kinds free at t, as the cursor reads them once per tick
    SELECT CASE WHEN bool_or(z.k = 'dcfc') AND bool_or(z.k = 'l2') THEN 'both'
                WHEN bool_or(z.k = 'dcfc') THEN 'dcfc' ELSE 'l2' END
      INTO v_mode FROM unnest(s_kind, s_free) AS z(k, f) WHERE z.f <= t;
    v_any := false;
    FOR i IN SELECT z.i FROM generate_subscripts(c_id, 1) AS z(i)
              WHERE c_ready[z.i] IS NULL
              ORDER BY c_imm[z.i] DESC,
                       CASE WHEN v_on THEN c_pin[z.i] END DESC NULLS LAST,
                       CASE WHEN v_on AND NOT c_pin[z.i]
                            THEN public.ottoq_agent_charge_order_key(p_order, c_id[z.i], v_mode) END ASC NULLS LAST,
                       c_kpos[z.i]
    LOOP
      EXIT WHEN (SELECT min(f) FROM unnest(s_free) f) > t;
      best := NULL;
      FOR j IN 1..m LOOP
        CONTINUE WHEN s_free[j] > t;
        CONTINUE WHEN (s_kind[j] = 'dcfc' AND NOT c_dok[i]) OR (s_kind[j] = 'l2' AND NOT c_lok[i]);
        IF best IS NULL OR (s_kind[j] = c_want[i] AND s_kind[best] <> c_want[i]) THEN best := j; END IF;
      END LOOP;
      CONTINUE WHEN best IS NULL;
      v_dur := CASE WHEN s_kind[best] = 'dcfc' THEN c_md[i] ELSE c_ml[i] END;
      c_start[i] := t; c_ready[i] := t + v_dur; c_kind[i] := s_kind[best];
      s_free[best] := t + GREATEST(v_dur, 0.01);
      v_seated := v_seated + 1; v_any := true;
    END LOOP;
    IF NOT v_any THEN
      -- no car left in the line can use a charger free at t: those chargers wait for the next one to free
      SELECT min(f) INTO v_next FROM unnest(s_free) f WHERE f > t;
      EXIT WHEN v_next IS NULL;
      FOR j IN 1..m LOOP
        IF s_free[j] <= t THEN s_free[j] := v_next; END IF;
      END LOOP;
    END IF;
  END LOOP;

  SELECT jsonb_build_object(
           'cars', n, 'chargers', m, 'seated', count(*) FILTER (WHERE c_ready[z.i] IS NOT NULL),
           'with_due', count(*) FILTER (WHERE c_due[z.i] IS NOT NULL),
           'on_time', count(*) FILTER (WHERE c_due[z.i] IS NOT NULL AND c_ready[z.i] IS NOT NULL AND c_ready[z.i] <= c_due[z.i]),
           'ready_sum_min', round(COALESCE(sum(COALESCE(c_ready[z.i], c_horizon + LEAST(c_md[z.i], c_ml[z.i]))), 0), 1),
           'mean_ready_min', round(avg(COALESCE(c_ready[z.i], c_horizon + LEAST(c_md[z.i], c_ml[z.i]))), 1),
           'late_sum_min', round(COALESCE(sum(GREATEST(COALESCE(c_ready[z.i], c_horizon + LEAST(c_md[z.i], c_ml[z.i]))
                                                       - c_due[z.i], 0)) FILTER (WHERE c_due[z.i] IS NOT NULL), 0), 1),
           'last_start_min', round(max(c_start[z.i]), 1),
           'on_dcfc', count(*) FILTER (WHERE c_kind[z.i] = 'dcfc'),
           'on_l2', count(*) FILTER (WHERE c_kind[z.i] = 'l2'),
           'horizon_min', c_horizon)
    INTO v_out
    FROM generate_subscripts(c_id, 1) AS z(i);
  RETURN COALESCE(v_out, jsonb_build_object('cars', 0, 'chargers', m, 'seated', 0, 'with_due', 0, 'on_time', 0,
                                            'ready_sum_min', 0, 'mean_ready_min', NULL, 'late_sum_min', 0,
                                            'last_start_min', NULL, 'on_dcfc', 0, 'on_l2', 0, 'horizon_min', c_horizon));
END $fn$;

COMMENT ON FUNCTION public.ottoq_charge_line_projection(uuid, uuid, timestamptz, jsonb) IS
'0618: the charge line projected from a moment as a deterministic list schedule, in the kernel''s order (order NULL or ''{}'') or in the order the cursor keeps under a live agent order. Reports cars ready by their due time, the line''s summed minutes to ready, summed lateness and the last start. Every car charges to its full target (rule 9). Read-only; the agent''s door compares the two sides with ottoq_charge_order_verdict.';

-- ══ (b) the verdict ════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_order_verdict(p_kernel jsonb, p_agent jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $fn$
  -- 0618: does the kernel take the agent's order? Cars ready by their due time first (the owner's requirement), then the
  -- line's summed minutes to ready (every minute a car waits or charges is a minute off the road). Fewer cars ready by
  -- their due time: refused. More: taken unless the line takes more than 10% longer in total. As many: taken when the
  -- line is ready no later in total (half a minute of rounding). A side with no projection: refused.
  SELECT jsonb_build_object('take', x.take, 'reason', x.reason,
           'kernel', jsonb_build_object('on_time', p_kernel -> 'on_time', 'with_due', p_kernel -> 'with_due',
                                        'mean_ready_min', p_kernel -> 'mean_ready_min', 'ready_sum_min', p_kernel -> 'ready_sum_min',
                                        'late_sum_min', p_kernel -> 'late_sum_min', 'cars', p_kernel -> 'cars'),
           'agent', jsonb_build_object('on_time', p_agent -> 'on_time', 'with_due', p_agent -> 'with_due',
                                       'mean_ready_min', p_agent -> 'mean_ready_min', 'ready_sum_min', p_agent -> 'ready_sum_min',
                                       'late_sum_min', p_agent -> 'late_sum_min', 'cars', p_agent -> 'cars'))
    FROM (SELECT
            CASE WHEN ko IS NULL OR ao IS NULL OR kr IS NULL OR ar IS NULL THEN false
                 WHEN ao < ko THEN false
                 WHEN ao > ko THEN ar <= 1.10 * kr
                 ELSE ar <= kr + 0.5 END AS take,
            CASE WHEN ko IS NULL OR ao IS NULL OR kr IS NULL OR ar IS NULL THEN 'no_projection'
                 WHEN ao < ko THEN 'fewer_cars_ready_by_due'
                 WHEN ao > ko AND ar <= 1.10 * kr THEN 'more_cars_ready_by_due'
                 WHEN ao > ko THEN 'more_cars_ready_by_due_but_line_much_later'
                 WHEN ar < kr - 0.5 THEN 'line_ready_sooner'
                 WHEN ar <= kr + 0.5 THEN 'no_worse'
                 ELSE 'line_ready_later' END AS reason
            FROM (SELECT (p_kernel ->> 'on_time')::int AS ko, (p_agent ->> 'on_time')::int AS ao,
                         (p_kernel ->> 'ready_sum_min')::numeric AS kr, (p_agent ->> 'ready_sum_min')::numeric AS ar) s) x
$fn$;

-- ══ (c) the door ═══════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_agent_charge_order_record(p_sim_run_id uuid, p_board_tick bigint, p_chain_id text,
                                                                  p_model text, p_order jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_run record; v_q jsonb := '{}'::jsonb; v_cars jsonb := '[]'::jsonb; v_dropped jsonb := '[]'::jsonb;
  v_seen text[] := ARRAY[]::text[]; v_rank int := 0; v_n int := 0; e jsonb; v_id uuid; v_kind text; v_info jsonb;
  v_status text; v_order_id bigint; v_why text;
  v_map jsonb; v_verdict jsonb;   -- 0618
BEGIN
  SELECT r.sim_run_id, r.depot_id, r.tick_count, r.sim_clock_current, r.status INTO v_run
    FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_run.sim_run_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'run_not_found'); END IF;
  IF v_run.status IS DISTINCT FROM 'running' THEN
    RETURN jsonb_build_object('ok', false, 'skipped', 'run_not_running');
  END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order', 0), 0) < 1 THEN
    RETURN jsonb_build_object('ok', false, 'skipped', 'agent_charge_order is 0 for this run');
  END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_seat', 0), 0) <> 0 THEN
    RETURN jsonb_build_object('ok', false, 'skipped', 'a baseline seat owns this run');
  END IF;

  -- the line as the kernel holds it now: an order is accepted only for cars in it
  SELECT COALESCE(jsonb_object_agg(k.vehicle_id::text, jsonb_build_object(
           'kernel_pos', k.kernel_pos, 'wait_min', round(k.wait_min, 1), 'soc', round(k.soc, 1),
           'name', COALESCE(v.display_name, k.vehicle_id::text))), '{}'::jsonb)
    INTO v_q
    FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current) k
    JOIN vehicles v ON v.id = k.vehicle_id;

  v_why := left(btrim(COALESCE(p_order ->> 'why', '')), 400);
  IF jsonb_typeof(p_order -> 'cars') IS DISTINCT FROM 'array' THEN
    v_dropped := jsonb_build_array(jsonb_build_object('reason', 'no cars array'));
  ELSE
    FOR e IN SELECT x.value FROM jsonb_array_elements(p_order -> 'cars') WITH ORDINALITY x(value, i) ORDER BY x.i LIMIT 40
    LOOP
      v_n := v_n + 1;
      v_id := NULL;
      IF jsonb_typeof(e) = 'object' AND (e ->> 'vehicle_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        v_id := (e ->> 'vehicle_id')::uuid;
      END IF;
      IF v_id IS NULL THEN
        v_dropped := v_dropped || jsonb_build_object('vehicle_id', left(COALESCE(e ->> 'vehicle_id', e::text), 60), 'reason', 'not_a_vehicle_id');
        CONTINUE;
      END IF;
      IF v_id::text = ANY (v_seen) THEN
        v_dropped := v_dropped || jsonb_build_object('vehicle_id', v_id, 'reason', 'duplicate');
        CONTINUE;
      END IF;
      v_seen := v_seen || v_id::text;
      v_info := v_q -> v_id::text;
      IF v_info IS NULL THEN
        v_dropped := v_dropped || jsonb_build_object('vehicle_id', v_id, 'reason', 'not_waiting_for_a_charger');
        CONTINUE;
      END IF;
      v_kind := lower(COALESCE(e ->> 'kind', 'either'));
      IF v_kind NOT IN ('dcfc', 'l2', 'either') THEN v_kind := 'either'; END IF;
      -- a kind the car cannot plug into here is the kernel's to pick, not a reason to drop the car
      IF v_kind <> 'either' AND NOT public.ottoq_charge_kind_compatible(v_id, v_run.depot_id, v_kind) THEN
        v_kind := 'either';
      END IF;
      v_rank := v_rank + 1;
      v_cars := v_cars || jsonb_build_object(
        'vehicle_id', v_id, 'rank', v_rank, 'kind', v_kind, 'why', left(btrim(COALESCE(e ->> 'why', '')), 200),
        'name', v_info -> 'name', 'soc', v_info -> 'soc', 'wait_min', v_info -> 'wait_min',
        'kernel_pos', v_info -> 'kernel_pos');
    END LOOP;
  END IF;

  v_status := CASE WHEN v_rank = 0 THEN 'rejected' WHEN v_rank < v_n THEN 'partial' ELSE 'accepted' END;

  /* 0618: THE KERNEL'S CHECK. The line projected from now in the kernel's own order and in the order the cursor would
     keep under this one; the order is taken only when ottoq_charge_order_verdict says it is no worse. A projection
     that fails refuses: an order the kernel could not check is never taken. */
  IF v_rank > 0 THEN
    BEGIN
      SELECT jsonb_object_agg(c ->> 'vehicle_id', jsonb_build_object('rank', c -> 'rank', 'kind', c ->> 'kind'))
        INTO v_map FROM jsonb_array_elements(v_cars) c;
      v_verdict := public.ottoq_charge_order_verdict(
        public.ottoq_charge_line_projection(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current, '{}'::jsonb),
        public.ottoq_charge_line_projection(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current, v_map));
    EXCEPTION WHEN OTHERS THEN
      v_verdict := jsonb_build_object('take', false, 'reason', 'projection_failed', 'error', left(SQLERRM, 200));
    END;
    IF NOT COALESCE((v_verdict ->> 'take')::boolean, false) THEN
      v_status := 'refused';
    END IF;
  END IF;

  INSERT INTO ottoq_agent_charge_orders
    (sim_run_id, depot_id, board_tick, recorded_tick, sim_clock, chain_id, model, status, n_offered, n_accepted,
     cars, dropped, why, projection)
  VALUES (p_sim_run_id, v_run.depot_id, p_board_tick, COALESCE(v_run.tick_count, 0), v_run.sim_clock_current,
          left(p_chain_id, 80), left(p_model, 120), v_status, v_n, v_rank, v_cars, v_dropped, NULLIF(v_why, ''),
          v_verdict)
  RETURNING order_id INTO v_order_id;

  RETURN jsonb_build_object(
    'ok', true, 'order_id', v_order_id, 'status', v_status, 'offered', v_n, 'accepted', v_rank,
    'dropped', v_dropped, 'queue', (SELECT count(*) FROM jsonb_object_keys(v_q)),
    'recorded_tick', COALESCE(v_run.tick_count, 0),
    'ttl_ticks', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15),
    'pin_wait_min', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_pin_wait_min', 90), 90),
    'projection', v_verdict);
EXCEPTION WHEN OTHERS THEN
  -- the agent's pass reads this receipt; a fault here must say so and never take the pass down
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_agent_charge_order_record(uuid, bigint, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_charge_order_record(uuid, bigint, text, text, jsonb) TO service_role;

-- ══ (d) what the orders did, and how many the kernel refused ══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_agent_charge_order_usage(p_sim_run_id uuid, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0614: what the agent's charge orders did on one run, read-only. A seat is a stall_assignment the decide path
  -- enacted while an order was live (its context_frame carries agent_charge_order). by_rank = the agent's order seated
  -- it (not pinned); pinned = the fairness floor seated it ahead of the order; unranked = the order did not name it;
  -- moved_ahead = seated by rank while the kernel's own order had it behind as many cars as were seated that tick;
  -- kind_followed = it took the kind the order named.
  WITH o AS (
    SELECT x.order_id, x.chain_id, x.recorded_tick, x.status, x.n_offered, x.n_accepted, x.projection
      FROM ottoq_agent_charge_orders x WHERE x.sim_run_id = p_sim_run_id
  ), s AS (
    SELECT d.tick_seq,
           CASE WHEN (d.context_frame -> 'agent_charge_order' ->> 'order_id') ~ '^[0-9]+$'
                THEN (d.context_frame -> 'agent_charge_order' ->> 'order_id')::bigint END AS order_id,
           COALESCE((d.context_frame -> 'agent_charge_order' ->> 'pinned')::boolean, false) AS pinned,
           d.context_frame -> 'agent_charge_order' ->> 'kind' AS kind,
           (d.context_frame -> 'agent_charge_order' ->> 'rank') AS rank,
           CASE WHEN (d.context_frame -> 'agent_charge_order' ->> 'kernel_pos') ~ '^[0-9]+$'
                THEN (d.context_frame -> 'agent_charge_order' ->> 'kernel_pos')::int END AS kernel_pos,
           COALESCE(d.enacted_action ->> 'stall_type', d.proposed_action ->> 'stall_type') AS took,
           count(*) OVER (PARTITION BY d.tick_seq) AS seats_in_tick
      FROM ottoq_decisions d
     WHERE d.sim_run_id = p_sim_run_id AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
       AND d.context_frame ? 'agent_charge_order'
  ), t AS (
    SELECT s.*, (NOT s.pinned AND s.rank IS NOT NULL) AS by_rank FROM s
  )
  SELECT jsonb_build_object(
    'orders', (SELECT count(*) FROM o),
    'orders_accepted', (SELECT count(*) FROM o WHERE o.status IN ('accepted', 'partial')),
    -- 0618: the orders the kernel's own projection said were worse than its order, and so never steered a seat
    'orders_refused', (SELECT count(*) FROM o WHERE o.status = 'refused'),
    'cars_ranked', (SELECT COALESCE(sum(o.n_accepted), 0) FROM o WHERE o.status IN ('accepted', 'partial')),
    'seats_under_order', (SELECT count(*) FROM t),
    'seats_by_rank', (SELECT count(*) FROM t WHERE t.by_rank),
    -- 0616: the orders that seated at least one car by their rank: the agent passes the twin draws green
    'orders_seating', (SELECT count(DISTINCT t.order_id) FROM t WHERE t.by_rank),
    'seats_pinned', (SELECT count(*) FROM t WHERE t.pinned),
    'seats_unranked', (SELECT count(*) FROM t WHERE NOT t.pinned AND t.rank IS NULL),
    'moved_ahead', (SELECT count(*) FROM t WHERE t.by_rank AND t.kernel_pos > t.seats_in_tick),
    'kind_named', (SELECT count(*) FROM t WHERE t.kind IN ('dcfc', 'l2')),
    'kind_followed', (SELECT count(*) FROM t WHERE t.kind IN ('dcfc', 'l2') AND t.took = t.kind),
    'by_order', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'order_id', o.order_id, 'chain_id', o.chain_id, 'recorded_tick', o.recorded_tick, 'status', o.status,
               'offered', o.n_offered, 'accepted', o.n_accepted,
               'verdict', o.projection ->> 'reason',
               'seats', (SELECT count(*) FROM t WHERE t.order_id = o.order_id),
               'seats_by_rank', (SELECT count(*) FROM t WHERE t.order_id = o.order_id AND t.by_rank),
               'moved_ahead', (SELECT count(*) FROM t WHERE t.order_id = o.order_id AND t.by_rank
                                                       AND t.kernel_pos > t.seats_in_tick))
             ORDER BY o.order_id DESC)
        FROM (SELECT * FROM o ORDER BY o.order_id DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 200))) o), '[]'::jsonb))
$function$;

-- ══ (e) the agent reads why ════════════════════════════════════════════════════════════════════════════════════════════
DO $board$
DECLARE v_def text; n int; c_old text; c_new text;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure);
  c_old := $old$'accepted', x.n_accepted, 'dropped', x.dropped,$old$;
  c_new := $new$'accepted', x.n_accepted, 'dropped', x.dropped, 'projection', x.projection,$new$;
  n := (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old);
  IF n <> 1 THEN RAISE EXCEPTION '0618 board: the anchor matches % times, not 1', n; END IF;
  EXECUTE replace(v_def, c_old, c_new);
END $board$;

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v1$
DECLARE k jsonb := '{"on_time": 3, "ready_sum_min": 1000}'::jsonb;
BEGIN
  IF (public.ottoq_charge_order_verdict(k, '{"on_time": 2, "ready_sum_min": 500}') ->> 'reason') IS DISTINCT FROM 'fewer_cars_ready_by_due'
     OR (public.ottoq_charge_order_verdict(k, '{"on_time": 2, "ready_sum_min": 500}') ->> 'take')::boolean
     OR (public.ottoq_charge_order_verdict(k, '{"on_time": 4, "ready_sum_min": 1100}') ->> 'reason') IS DISTINCT FROM 'more_cars_ready_by_due'
     OR NOT (public.ottoq_charge_order_verdict(k, '{"on_time": 4, "ready_sum_min": 1100}') ->> 'take')::boolean
     OR (public.ottoq_charge_order_verdict(k, '{"on_time": 4, "ready_sum_min": 1101}') ->> 'reason') IS DISTINCT FROM 'more_cars_ready_by_due_but_line_much_later'
     OR (public.ottoq_charge_order_verdict(k, '{"on_time": 4, "ready_sum_min": 1101}') ->> 'take')::boolean
     OR (public.ottoq_charge_order_verdict(k, '{"on_time": 3, "ready_sum_min": 990}') ->> 'reason') IS DISTINCT FROM 'line_ready_sooner'
     OR (public.ottoq_charge_order_verdict(k, '{"on_time": 3, "ready_sum_min": 1000.4}') ->> 'reason') IS DISTINCT FROM 'no_worse'
     OR NOT (public.ottoq_charge_order_verdict(k, '{"on_time": 3, "ready_sum_min": 1000.4}') ->> 'take')::boolean
     OR (public.ottoq_charge_order_verdict(k, '{"on_time": 3, "ready_sum_min": 1001}') ->> 'reason') IS DISTINCT FROM 'line_ready_later'
     OR (public.ottoq_charge_order_verdict(k, '{"on_time": 3, "ready_sum_min": 1001}') ->> 'take')::boolean
     OR (public.ottoq_charge_order_verdict(k, NULL) ->> 'reason') IS DISTINCT FROM 'no_projection'
     OR (public.ottoq_charge_order_verdict(k, NULL) ->> 'take')::boolean THEN
    RAISE EXCEPTION '0618 V1: the verdict''s truth table is wrong';
  END IF;
END $v1$;

DO $v2$
DECLARE r record; a jsonb; b jsonb; v jsonb;
BEGIN
  SELECT s.sim_run_id, s.depot_id, s.sim_clock_current INTO r
    FROM public.ottoq_sim_runs s
   WHERE s.status = 'running' AND s.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY s.started_at DESC LIMIT 1;
  IF r.sim_run_id IS NULL THEN
    RAISE NOTICE '0618 V2: no twin run is running; the projection is executed by the tests on stubs';
    RETURN;
  END IF;
  a := public.ottoq_charge_line_projection(r.sim_run_id, r.depot_id, r.sim_clock_current, '{}'::jsonb);
  b := public.ottoq_charge_line_projection(r.sim_run_id, r.depot_id, r.sim_clock_current, NULL);
  IF a IS DISTINCT FROM b THEN
    RAISE EXCEPTION '0618 V2: the kernel''s projection does not agree with itself: % / %', a, b;
  END IF;
  v := public.ottoq_charge_order_verdict(a, a);
  IF NOT (v ->> 'take')::boolean OR v ->> 'reason' <> 'no_worse' THEN
    RAISE EXCEPTION '0618 V2: the kernel''s order against itself is not taken: %', v;
  END IF;
  RAISE NOTICE '0618 V2 on run %: %', r.sim_run_id, a;
END $v2$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0618_the_kernel_checks_the_agents_charge_order_against_its_own_before_taking_it', false, false,
  'The agent''s charge-order door projects the line in the kernel''s order and the agent''s and refuses an order the '
  'projection says is worse (status refused, projection recorded); the usage read counts refusals and the board shows '
  'why. FALSE/FALSE: the tick path is untouched and orders exist only on operator_demo runs (0615).',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
