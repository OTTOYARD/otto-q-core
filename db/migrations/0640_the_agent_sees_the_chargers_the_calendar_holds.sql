-- migration-version: PENDING
-- migration-name:    the_agent_sees_the_chargers_the_calendar_holds
--
-- 0640  **The agent sees the chargers the depot's calendar holds for named cars.**
--       0639 taught the kernel's check that a charger the calendar holds for a named car goes to no other car inside its
--       window. The agent that proposes the order still could not see one: its board lists the chargers free, down and
--       freeing soonest, and nothing booked ahead. So it ranked cars onto chargers the kernel was always going to give to
--       someone else, and ranked cars that already had a charger waiting for them.
--
-- ══ §1 WHY (measured 2026-10-09 10:15 UTC, 5:15 AM CT, on live, read-only) ════════════════════════════════════════════════
--
--   On b2efcc07's 136 orders, with the calendar read as it stood at each order (0639's ottoq_charge_line_holds): a mean
--   21.4 charge bookings held for named cars starting within the hour (max 32), 15.9 of them within 15 minutes; a mean
--   10.0 of the line's 42.3 cars had a charger held for them; and 215 of the 1,331 cars the agent named in its orders
--   (16%) already had one. The board carried none of it.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   ottoq_agent_charge_queue_board: 'chargers.held' lists the chargers the calendar holds for a named car within the
--   next hour, soonest first (kind, stall, car, from_min, until_min; at most 12), and each car's 'held' names the
--   charger held for it (kind, stall, from_min, until_min), both from ottoq_charge_line_holds: the check's own reading,
--   so the agent and the check see one calendar. Nothing else on the board moves. The agent's prompt (agent v27,
--   edge-functions/_shared/agent_charge_order.ts) says what the two fields mean.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, no run running (the board is read by the agent of a running run). P1 0639 is applied and the
--   board is the body 0637 left (2fa4de1c). V1 the board at the latest order of the latest run with 20 stored orders
--   lists the chargers the calendar held then within the hour, and each car its own. V2 without the two fields, the
--   board is 0639's, key for key, on the latest 8 stored orders. Executed by tests/test_agent_holds_sql.py on the
--   miniature depot.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE, as 0637: the board is read by the agent alone; no kernel decision,
--   seat, dial or certification arm reads it.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0640_pre' AND object_kind = 'function';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0640_the_agent_sees_the_chargers_the_calendar_holds'.

BEGIN;

-- ── P0: nothing in flight, no run running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0640 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0640 P0: a run is running; its agent reads the board this changes. Apply between runs';
  END IF;
END $inflight$;

-- ── P1: 0639 is applied; the board is the body 0637 left ──
DO $premises$
BEGIN
  IF to_regprocedure('public.ottoq_charge_line_holds(uuid,timestamp with time zone,numeric)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                     WHERE name = '0639_the_futures_hold_a_charger_for_the_car_the_calendar_names') THEN
    RAISE EXCEPTION '0640 P1: 0639 is not applied; apply it first';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'))
     IS DISTINCT FROM '2fa4de1c1326f3f91cbe674da44a48d2' THEN
    RAISE EXCEPTION '0640 P1: ottoq_agent_charge_queue_board is not the body 0637 left (md5 2fa4de1c); read it again';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0640_the_agent_sees_the_chargers_the_calendar_holds') THEN
    RAISE EXCEPTION '0640 P1: already applied';
  END IF;
END $premises$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0640_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure;

-- what V2 compares against: the board as it stood, at the latest 8 stored orders
CREATE TEMP TABLE _0640_pre ON COMMIT DROP AS
SELECT s.order_id, public.ottoq_agent_charge_queue_board(s.sim_run_id, s.depot_id, s.sim_clock) AS board
  FROM (SELECT * FROM public.ottoq_charge_order_snapshots WHERE depot_id = '11111111-1111-1111-1111-111111111111'
         ORDER BY order_id DESC LIMIT 8) s;

-- ══ the anchored patches: each anchor once, the stored definition after ═══════════════════════════════════════════════════
CREATE TEMP TABLE _0640_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0640_patch VALUES
('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', 1,
$old$  -- which clock this is and how each class charges against the depot's typical car.
$old$,
$new$  -- which clock this is and how each class charges against the depot's typical car.
  -- 0640: 'chargers.held' lists the chargers the depot's calendar holds for a named car within the next hour
  -- (ottoq_charge_line_holds, the check's own reading), and each car's 'held' names the charger held for it: while a
  -- hold covers the moment the kernel gives that charger to no other car, whatever an order says.
$new$),
('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', 2,
$old$  WITH k AS (
$old$,
$new$  WITH hl AS (                                                                                      -- 0640
    SELECT (x.value ->> 'c')::uuid AS stall_id, (x.value ->> 'v')::uuid AS vehicle_id, (x.value ->> 'a')::numeric AS a,
           (x.value ->> 'b')::numeric AS b
      FROM jsonb_array_elements(public.ottoq_charge_line_holds(p_sim_run_id, p_clock, 60)) x
  ), k AS (
$new$),
('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', 3,
$old$             'holds_charger', k.holds_charger,
$old$,
$new$             'holds_charger', k.holds_charger,
             -- 0640: the charger the calendar holds for this car, if any: the kernel seats it there when it opens
             'held', (SELECT jsonb_build_object('kind', hs.stall_type::text, 'stall', COALESCE(hs.display_name, hs.stall_code),
                                                'from_min', round(h.a, 0), 'until_min', round(h.b, 0))
                        FROM hl h JOIN stalls hs ON hs.id = h.stall_id
                       WHERE h.vehicle_id = v.id ORDER BY h.a, hs.stall_code LIMIT 1),
$new$),
('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', 4,
$old$                                     FROM (SELECT * FROM soon ORDER BY soon.in_min NULLS LAST, soon.name LIMIT 8) x),
                                  '[]'::jsonb)),
$old$,
$new$                                     FROM (SELECT * FROM soon ORDER BY soon.in_min NULLS LAST, soon.name LIMIT 8) x),
                                  '[]'::jsonb),
      -- 0640: the chargers the depot's calendar holds for a named car within the next hour, soonest first
      'held', COALESCE((SELECT jsonb_agg(jsonb_build_object('kind', x.kind, 'stall', x.name, 'car', x.car,
                                                            'from_min', x.a, 'until_min', x.b) ORDER BY x.a, x.name)
                          FROM (SELECT hs.stall_type::text AS kind, COALESCE(hs.display_name, hs.stall_code) AS name,
                                       COALESCE(hv.display_name, hv.id::text) AS car, round(h.a, 0) AS a, round(h.b, 0) AS b
                                  FROM hl h JOIN stalls hs ON hs.id = h.stall_id JOIN vehicles hv ON hv.id = h.vehicle_id
                                 WHERE hs.depot_id = p_depot_id
                                 ORDER BY h.a, hs.stall_code LIMIT 12) x), '[]'::jsonb)),
$new$);

DO $patch$
DECLARE f record; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0640_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0640_patch WHERE fn = f.fn ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0640 %: anchor % matches % times, not 1', f.fn, p.seq, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(f.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0640 %: not stored as patched', f.fn;
    END IF;
  END LOOP;
END $patch$;

-- ══ V1: the board lists the chargers the calendar held, and each car its own ════════════════════════════════════════════
DO $v1$
DECLARE
  c_twin constant uuid := '11111111-1111-1111-1111-111111111111';
  s record; v_b jsonb; v_h jsonb; v_n int; v_first jsonb; v_cars int; v_mine int;
BEGIN
  SELECT sn.order_id, sn.sim_run_id, sn.sim_clock INTO s FROM public.ottoq_charge_order_snapshots sn
   WHERE sn.depot_id = c_twin
   ORDER BY (SELECT count(*) FROM public.ottoq_charge_order_snapshots x WHERE x.sim_run_id = sn.sim_run_id) >= 20 DESC,
            sn.order_id DESC
   LIMIT 1;
  IF s.order_id IS NULL THEN
    RAISE NOTICE '0640 V1: no stored order; the board is executed by the tests';
    RETURN;
  END IF;
  v_b := public.ottoq_agent_charge_queue_board(s.sim_run_id, c_twin, s.sim_clock);
  v_h := public.ottoq_charge_line_holds(s.sim_run_id, s.sim_clock, 60);
  SELECT count(*) INTO v_n FROM jsonb_array_elements(v_h) x JOIN public.stalls st ON st.id = (x.value ->> 'c')::uuid
   WHERE st.depot_id = c_twin;
  IF jsonb_typeof(v_b #> '{chargers,held}') IS DISTINCT FROM 'array'
     OR jsonb_array_length(v_b #> '{chargers,held}') <> LEAST(v_n, 12) THEN
    RAISE EXCEPTION '0640 V1: the board at order % lists % held chargers; the calendar held % within the hour', s.order_id,
      jsonb_array_length(COALESCE(v_b #> '{chargers,held}', '[]'::jsonb)), v_n;
  END IF;
  -- every car on the board with a hold names the first of its own
  SELECT count(*), count(*) FILTER (WHERE (c.value -> 'held') IS NOT NULL AND c.value -> 'held' <> 'null'::jsonb)
    INTO v_cars, v_mine
    FROM jsonb_array_elements(COALESCE(v_b -> 'cars', '[]'::jsonb)) c;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v_b -> 'cars', '[]'::jsonb)) c
              WHERE (EXISTS (SELECT 1 FROM jsonb_array_elements(v_h) x WHERE x.value ->> 'v' = c.value ->> 'vehicle_id'))
                    IS DISTINCT FROM (c.value -> 'held' IS NOT NULL AND c.value -> 'held' <> 'null'::jsonb)) THEN
    RAISE EXCEPTION '0640 V1: a car on the board at order % does not carry the hold the calendar held for it', s.order_id;
  END IF;
  v_first := v_b #> '{chargers,held,0}';
  RAISE NOTICE '0640 V1: the board at order % (run %, sim %) lists % of the % chargers the calendar held then for a named car within the hour%; % of its % cars carry a hold of their own',
    s.order_id, left(s.sim_run_id::text, 8), to_char(s.sim_clock, 'HH24:MI'),
    jsonb_array_length(v_b #> '{chargers,held}'), v_n,
    CASE WHEN v_first IS NOT NULL THEN format(' (the first an %s from minute %s to %s)', v_first ->> 'kind',
                                              v_first ->> 'from_min', COALESCE(v_first ->> 'until_min', 'open')) ELSE '' END,
    v_mine, v_cars;
END $v1$;

-- ══ V2: without the two fields, the board is 0639's, key for key ═════════════════════════════════════════════════════════
DO $v2$
DECLARE v_n int; v_diff int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE (x.board #- '{chargers,held}')
                                            || jsonb_build_object('cars', COALESCE((SELECT jsonb_agg(c.value - 'held' ORDER BY c.o)
                                                                                      FROM jsonb_array_elements(x.board -> 'cars')
                                                                                           WITH ORDINALITY c(value, o)), '[]'::jsonb))
                                          IS DISTINCT FROM p.board)
    INTO v_n, v_diff
    FROM _0640_pre p
    JOIN public.ottoq_charge_order_snapshots s ON s.order_id = p.order_id
    CROSS JOIN LATERAL (SELECT public.ottoq_agent_charge_queue_board(s.sim_run_id, s.depot_id, s.sim_clock) AS board) x;
  IF v_diff > 0 THEN
    RAISE EXCEPTION '0640 V2: % of % boards changed beyond the two fields', v_diff, v_n;
  END IF;
  RAISE NOTICE '0640 V2: % boards at stored orders unchanged beyond the two fields', v_n;
END $v2$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0640_the_agent_sees_the_chargers_the_calendar_holds', false, false,
  'The agent''s board lists the chargers the depot''s calendar holds for a named car within the hour, and each car the '
  'charger held for it, from ottoq_charge_line_holds (0639), so the agent and the kernel''s check read one calendar. '
  'FALSE/FALSE as 0637: the board is read by the agent alone; no kernel decision, seat, dial or certification arm reads it.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
