-- migration-version: 20261009104632
-- migration-name:    the_agent_sees_the_kernels_own_plan
--
-- 0641  **The agent sees the kernel's own plan, car by car.**
--       The agent's order is taken only when it beats the kernel's own order in the check's futures. The agent never saw
--       that order's future: its board's last projection carries the two sides' totals and nothing per car. So it could
--       not see which cars the kernel's plan makes late or leaves low on an L2, which are the moves its prompt asks it to
--       make (due_rescue_fast, low_battery_on_l2). It had to guess where the plan was wrong.
--
-- ══ §1 WHY (measured 2026-10-09 10:05 UTC, 5:05 AM CT, on live, read-only) ════════════════════════════════════════════════
--
--   On b2efcc07's 136 orders, the check's expected future of the kernel's order from the state it stored at each order
--   (ottoq_charge_line_schedule, scenario 0, as it stood before 0639): a mean 0.76 cars per order with a due time, 0.75
--   of them planned late, by a mean 115.5 minutes, on 54 of the 136 orders; and 4.47 cars per order under 45% put on an
--   L2, of 42.3 in the line. The agent's order matched the kernel's 127 times in 136 (db/checks/0423).
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   ottoq_agent_charge_queue_board: each car's 'plan' (start_min, kind, ready_min, late_min), each arriving car's
--   plan_start_min and plan_kind, and 'kernel_plan' (cars, arriving, unseated, late, late_min, low_on_l2): what the
--   kernel's own order does from now in the check's expected future, from the check's own state and simulator
--   (ottoq_charge_line_state, ottoq_charge_line_schedule with no order, scenario 0), so the agent reads the plan the
--   check will compare its order against. Nothing else on the board moves. The agent's prompt (agent v27) says what
--   they mean and that an order wins only where it changes the plan for the better.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, no run running. P1 0640 is applied and the board is the body it left (f6079cdd). V1 the board
--   at the latest order of the latest run with 20 stored orders carries the plan, and each car's plan is the
--   simulator's seat for it. V2 without the plan's fields, the board is 0640's, key for key, on the latest 8 stored
--   orders. Executed by tests/test_agent_holds_sql.py on the miniature depot.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE, as 0640: the board is read by the agent alone.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0641_pre' AND object_kind = 'function';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0641_the_agent_sees_the_kernels_own_plan'.

BEGIN;

-- ── P0: nothing in flight, no run running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0641 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0641 P0: a run is running; its agent reads the board this changes. Apply between runs';
  END IF;
END $inflight$;

-- ── P1: 0640 is applied; the board is the body it left ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0640_the_agent_sees_the_chargers_the_calendar_holds') THEN
    RAISE EXCEPTION '0641 P1: 0640 is not applied; apply it first';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'))
     IS DISTINCT FROM 'f6079cdd3692f9f5c3a12298d1663583' THEN
    RAISE EXCEPTION '0641 P1: ottoq_agent_charge_queue_board is not the body 0640 left (md5 f6079cdd); read it again';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0641_the_agent_sees_the_kernels_own_plan') THEN
    RAISE EXCEPTION '0641 P1: already applied';
  END IF;
END $premises$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0641_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure;

-- what V2 compares against: the board as it stood, at the latest 8 stored orders
CREATE TEMP TABLE _0641_pre ON COMMIT DROP AS
SELECT s.order_id, public.ottoq_agent_charge_queue_board(s.sim_run_id, s.depot_id, s.sim_clock) AS board
  FROM (SELECT * FROM public.ottoq_charge_order_snapshots WHERE depot_id = '11111111-1111-1111-1111-111111111111'
         ORDER BY order_id DESC LIMIT 8) s;

-- ══ the anchored patches: each anchor once, the stored definition after ═══════════════════════════════════════════════════
CREATE TEMP TABLE _0641_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0641_patch VALUES
('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', 1,
$old$  -- hold covers the moment the kernel gives that charger to no other car, whatever an order says.
$old$,
$new$  -- hold covers the moment the kernel gives that charger to no other car, whatever an order says.
  -- 0641: each car's 'plan', each arriving car's plan_start_min and plan_kind, and 'kernel_plan' are what the
  -- kernel's own order does from now in the check's expected future (ottoq_charge_line_schedule on
  -- ottoq_charge_line_state, scenario 0): when each car starts, on which kind, when it is ready and how late; and how
  -- many cars the plan makes late, puts under 45% on an L2, or cannot seat within the horizon.
$new$),
('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', 2,
$old$  ), k AS (
$old$,
$new$  ), ps AS (                                                                                        -- 0641
    SELECT public.ottoq_charge_line_state(p_sim_run_id, p_depot_id, p_clock) AS s
  ), pl AS (
    SELECT y.value ->> 'id' AS id, (y.value ->> 's0')::numeric AS s0, y.value ->> 'k0' AS k0,
           (y.value ->> 'r')::numeric AS r, COALESCE((y.value ->> 'inb')::boolean, false) AS inb,
           (SELECT (c.value ->> 'due')::numeric FROM jsonb_array_elements(COALESCE(ps.s -> 'cars', '[]'::jsonb)) c
             WHERE c.value ->> 'id' = y.value ->> 'id' LIMIT 1) AS due,
           (SELECT (c.value ->> 'soc')::numeric
              FROM jsonb_array_elements(COALESCE(ps.s -> 'cars', '[]'::jsonb) || COALESCE(ps.s -> 'inbound', '[]'::jsonb)) c
             WHERE c.value ->> 'id' = y.value ->> 'id' LIMIT 1) AS soc
      FROM ps
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(public.ottoq_charge_line_schedule(
                           ps.s, NULL, 0, COALESCE(p_sim_run_id::text, 'board'), true) -> 'seats', '[]'::jsonb)) y
  ), k AS (
$new$),
('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', 3,
$old$             'kernel_pos', k.kernel_pos) AS j
$old$,
$new$             'kernel_pos', k.kernel_pos,
             -- 0641: what the kernel's own order does with this car from now, in the check's expected future
             'plan', (SELECT jsonb_build_object('start_min', round(pl.s0, 0), 'kind', pl.k0, 'ready_min', round(pl.r, 0),
                                                'late_min', CASE WHEN pl.due IS NOT NULL AND pl.r IS NOT NULL
                                                                 THEN GREATEST(round(pl.r - pl.due, 0), 0) END)
                        FROM pl WHERE pl.id = v.id::text)) AS j
$new$),
('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', 4,
$old$    'arriving', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', x.name, 'eta_min', round(x.eta_min, 0),
                                                              'soc', round(x.soc_at_arrival, 0), 'source', x.source)
$old$,
$new$    'arriving', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', x.name, 'eta_min', round(x.eta_min, 0),
                                                              'soc', round(x.soc_at_arrival, 0), 'source', x.source,
                                                              -- 0641: when and on which kind the kernel's order seats it
                                                              'plan_start_min', (SELECT round(pl.s0, 0) FROM pl
                                                                                  WHERE pl.id = x.vehicle_id::text),
                                                              'plan_kind', (SELECT pl.k0 FROM pl WHERE pl.id = x.vehicle_id::text))
$new$),
('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', 5,
$old$    'cars', COALESCE((SELECT jsonb_agg(cars.j ORDER BY cars.kernel_pos) FROM cars), '[]'::jsonb),
$old$,
$new$    'cars', COALESCE((SELECT jsonb_agg(cars.j ORDER BY cars.kernel_pos) FROM cars), '[]'::jsonb),
    -- 0641: what the kernel's own order does with the whole line from now, in the check's expected future
    'kernel_plan', (SELECT jsonb_build_object(
                      'cars', count(*) FILTER (WHERE NOT pl.inb), 'arriving', count(*) FILTER (WHERE pl.inb),
                      'unseated', count(*) FILTER (WHERE pl.s0 IS NULL),
                      'late', count(*) FILTER (WHERE pl.due IS NOT NULL AND pl.r > pl.due),
                      'late_min', round(COALESCE(sum(pl.r - pl.due) FILTER (WHERE pl.due IS NOT NULL AND pl.r > pl.due), 0), 0),
                      'low_on_l2', count(*) FILTER (WHERE pl.k0 = 'l2' AND pl.soc < 45))
                      FROM pl),
$new$);

DO $patch$
DECLARE f record; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0641_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0641_patch WHERE fn = f.fn ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0641 %: anchor % matches % times, not 1', f.fn, p.seq, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(f.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0641 %: not stored as patched', f.fn;
    END IF;
  END LOOP;
END $patch$;

-- ══ V1: the board carries the kernel's plan, each car's its own seat ═══════════════════════════════════════════════════
DO $v1$
DECLARE
  c_twin constant uuid := '11111111-1111-1111-1111-111111111111';
  s record; v_b jsonb; v_seats jsonb; v_bad int; v_t timestamptz;
BEGIN
  SELECT sn.order_id, sn.sim_run_id, sn.sim_clock INTO s FROM public.ottoq_charge_order_snapshots sn
   WHERE sn.depot_id = c_twin
   ORDER BY (SELECT count(*) FROM public.ottoq_charge_order_snapshots x WHERE x.sim_run_id = sn.sim_run_id) >= 20 DESC,
            sn.order_id DESC
   LIMIT 1;
  IF s.order_id IS NULL THEN
    RAISE NOTICE '0641 V1: no stored order; the board is executed by the tests';
    RETURN;
  END IF;
  v_t := clock_timestamp();
  v_b := public.ottoq_agent_charge_queue_board(s.sim_run_id, c_twin, s.sim_clock);
  IF jsonb_typeof(v_b -> 'kernel_plan') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION '0641 V1: the board at order % carries no kernel_plan', s.order_id;
  END IF;
  v_seats := public.ottoq_charge_line_schedule(public.ottoq_charge_line_state(s.sim_run_id, c_twin, s.sim_clock), NULL, 0,
                                               s.sim_run_id::text, true) -> 'seats';
  SELECT count(*) INTO v_bad
    FROM jsonb_array_elements(COALESCE(v_b -> 'cars', '[]'::jsonb)) c
    LEFT JOIN LATERAL (SELECT y.value FROM jsonb_array_elements(COALESCE(v_seats, '[]'::jsonb)) y
                        WHERE y.value ->> 'id' = c.value ->> 'vehicle_id' LIMIT 1) z ON true
   WHERE (c.value #>> '{plan,start_min}')::numeric IS DISTINCT FROM round((z.value ->> 's0')::numeric, 0)
      OR (c.value #>> '{plan,kind}') IS DISTINCT FROM (z.value ->> 'k0');
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0641 V1: % cars on the board at order % carry a plan that is not the simulator''s seat', v_bad, s.order_id;
  END IF;
  RAISE NOTICE '0641 V1: the board at order % (run %, sim %, % s) carries the kernel''s plan for % cars in the line and % coming home: % late by % minutes, % under 45%% on an L2, % not seated within the horizon',
    s.order_id, left(s.sim_run_id::text, 8), to_char(s.sim_clock, 'HH24:MI'),
    round(extract(epoch FROM clock_timestamp() - v_t)::numeric, 2),
    v_b #>> '{kernel_plan,cars}', v_b #>> '{kernel_plan,arriving}', v_b #>> '{kernel_plan,late}',
    v_b #>> '{kernel_plan,late_min}', v_b #>> '{kernel_plan,low_on_l2}', v_b #>> '{kernel_plan,unseated}';
END $v1$;

-- ══ V2: without the plan's fields, the board is 0640's, key for key ═════════════════════════════════════════════════════
DO $v2$
DECLARE v_n int; v_diff int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE (x.board - 'kernel_plan')
                                            || jsonb_build_object(
                                                 'cars', COALESCE((SELECT jsonb_agg(c.value - 'plan' ORDER BY c.o)
                                                                     FROM jsonb_array_elements(x.board -> 'cars')
                                                                          WITH ORDINALITY c(value, o)), '[]'::jsonb),
                                                 'arriving', COALESCE((SELECT jsonb_agg(a.value - 'plan_start_min' - 'plan_kind' ORDER BY a.o)
                                                                         FROM jsonb_array_elements(x.board -> 'arriving')
                                                                              WITH ORDINALITY a(value, o)), '[]'::jsonb))
                                          IS DISTINCT FROM p.board)
    INTO v_n, v_diff
    FROM _0641_pre p
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = p.order_id
    CROSS JOIN LATERAL (SELECT public.ottoq_agent_charge_queue_board(s.sim_run_id, s.depot_id, s.sim_clock) AS board) x;
  IF v_diff > 0 THEN
    RAISE EXCEPTION '0641 V2: % of % boards changed beyond the plan''s fields', v_diff, v_n;
  END IF;
  RAISE NOTICE '0641 V2: % boards at stored orders unchanged beyond the plan''s fields', v_n;
END $v2$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0641_the_agent_sees_the_kernels_own_plan', false, false,
  'The agent''s board carries what the kernel''s own order does from now in the check''s expected future (each car''s '
  'plan, each arriving car''s seat, kernel_plan''s counts), from the check''s own state and simulator, so the agent reads '
  'the plan its order is compared against. FALSE/FALSE as 0640: the board is read by the agent alone.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
