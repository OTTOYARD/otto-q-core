-- migration-version: PENDING
-- migration-name:    0835_a_bay_held_for_a_car_on_its_way_in_is_not_idle_with_a_car_ready
--
-- 0835  **A bay held for a car on its way in is not "idle with a car ready" on the agent's board.** (G541, second half)
--
-- ══ §1 WHY (read 2026-11-14 on runs 14d6eda7, c8913ea2 and 1902d13b, busy_day, the twin depot, all after 0829) ═════════
--
--   The agent's board (0783, public.ottoq_depot_constraint) counts a bay busy by the cars whose STATE is in that bay,
--   and a car ready for a bay as any car in the bay's line that owes no charge. Read from the stored boards
--   (ottoq_agent_pass_evidence.board_text) against the calendar (ottoq_stall_bookings, sim time):
--     consulted boards on the three runs                                   81
--     wash bays read "idle with a car ready"                               16
--     of those, a wash booking already on the calendar began within
--       1.1 minutes of the board's clock                                    9   (within 10 minutes: 13)
--   So on most of those boards the idle bay was already a car's: the calendar had seated it and the car was on its way
--   in. The agent wrote a directive about an idle wash bay each time (G541). Three boards remain (the next wash began
--   11.2, 16.8 and 23.0 minutes later); they are left to read as they are.
--   Also read: the wash bays' busy count was under the calendar's on 5 of the 81 boards (a booking running, the car's
--   state not yet in the bay).
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_depot_constraint, the bays only (the posts' row, the lines, the wall and the lesson are untouched):
--     busy_now             the larger of the cars in the bay by state (as before) and the bays a car stands in or a
--                          held or active booking covers now, never more than the bays up. It can only rise.
--     held_for_car_due     NEW: bays not busy on which a held or active booking begins within 10 minutes.
--     idle_now             bays up less busy, as before.
--     idle_with_car_ready  the bays neither busy nor held, against the ready cars; and a ready car is now one that owes
--                          no charge, is not the car a bay is held for, and is not in another bay, in an emergency
--                          state or out of service. It can only fall.
--   Read-only, for the board. No engine function reads this function to seat, order or hold a car.
--   No dial: it corrects a count. The board carries `constraint` only with grounding and agent_constraint_board on.
--
-- ══ §3 RULES 9, 10, 14 ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   No car's charge, target, service or place in any line changes. The agent gains no lever.
--
-- ══ §4 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight and no run running. P2 once. P1 the definition is the one read on live (pg_get_functiondef
--   md5 273f2bde…) and 0783 is classified. The pre-image to ottoq_schema_snapshots as '0835_pre'. Each anchor matches
--   once. V1 ACL, security, volatility, settings and owner unchanged. V2 on the 20 latest runs this database holds
--   (one call costs about half a second on live, read 2026-11-14, and an older run's cars are no longer in its
--   states), each at its own clock: the answer less the four bay counts is the pre-image's; no bay's busy_now fell; no bay's
--   idle_with_car_ready rose; busy + held never exceeds the bays up. V3 the body is the one the tests ran (md5).
--   tests/test_depot_constraint_held_bay_sql.py runs this file on the scratch PostgreSQL over 0783's own harness.
--
-- ══ §5 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE: the function is read only by the agent's board, behind agent_board_grounding_enabled and
--   agent_constraint_board, both 0 at the defaults a certification arm runs at. forces_dial_restart FALSE: no dial.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0835_pre'; DELETE FROM
--   public.ottoq_cert_lineage WHERE name = '0835_a_bay_held_for_a_car_on_its_way_in_is_not_idle_with_a_car_ready'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight, and no run running ──
DO $p0$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0835 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0835 P0: a run is running; its agent reads this board. Apply between runs';
  END IF;
END $p0$;

-- ── P2: once (asked first: after an apply the definition is no longer the one P1 names) ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0835_a_bay_held_for_a_car_on_its_way_in_is_not_idle_with_a_car_ready') THEN
    RAISE EXCEPTION '0835 P2: already applied';
  END IF;
END $once$;

-- ── P1: the definition this file was written against ──
DO $p1$
BEGIN
  IF to_regprocedure('public.ottoq_depot_constraint(uuid,uuid,timestamp with time zone)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                     WHERE name = '0783_the_agents_board_says_where_the_depots_wall_is') THEN
    RAISE EXCEPTION '0835 P1: 0783 is not applied; apply in order';
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_depot_constraint(uuid,uuid,timestamp with time zone)'::regprocedure))
       IS DISTINCT FROM '273f2bde577d05fd7cea4da77d92faf9' THEN
    RAISE EXCEPTION '0835 P1: public.ottoq_depot_constraint is not the definition this file was written against';
  END IF;
END $p1$;

-- ── the pre-image, the attributes V1 holds the function to, and the pre-image as a callable for V2 ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0835_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_depot_constraint(uuid,uuid,timestamp with time zone)'::regprocedure;

CREATE TEMP TABLE _0835_attrs ON COMMIT DROP AS
SELECT p.proacl::text AS acl, p.prosecdef, p.provolatile, p.proconfig::text AS config, p.proowner
  FROM pg_proc p WHERE p.oid = 'public.ottoq_depot_constraint(uuid,uuid,timestamp with time zone)'::regprocedure;

DO $pre$
DECLARE v_def text := pg_get_functiondef('public.ottoq_depot_constraint(uuid,uuid,timestamp with time zone)'::regprocedure);
BEGIN
  IF position('FUNCTION public.ottoq_depot_constraint(' IN v_def) = 0 THEN
    RAISE EXCEPTION '0835: the definition does not name the function as expected';
  END IF;
  EXECUTE replace(v_def, 'FUNCTION public.ottoq_depot_constraint(', 'FUNCTION pg_temp._0835_pre(');
END $pre$;

-- ── the five substitutions, each matched once, read with bare newlines whatever line endings the paste carried ──
DO $patch$
DECLARE
  v_def text := replace(pg_get_functiondef('public.ottoq_depot_constraint(uuid,uuid,timestamp with time zone)'::regprocedure), E'\r', '');
  v_old text; v_new text; i int;
  v_olds text[] := ARRAY[
$a1$  ), lanes AS (
    SELECT l.lane,
$a1$,
$a2$           (SELECT count(*) FROM vehicles v WHERE v.home_depot_id = p_depot_id
               AND v.current_state::text = ANY (CASE l.lane WHEN 'service_bay' THEN ARRAY['in_service_bay']
                                                            ELSE ARRAY['in_wash_bay', 'in_detail_bay'] END))::int AS busy,
$a2$,
$a3$    SELECT l.lane, l.up, l.busy, l.prog, count(f.vehicle_id)::int AS q, COALESCE(sum(f.owe_min), 0) AS qmin,
           (count(f.vehicle_id) FILTER (WHERE NOT ottoq.ottoq_vehicle_owes_charge_now(f.vehicle_id, p_clock)))::int AS ready
      FROM lanes l LEFT JOIN fin f ON f.res = l.lane
     GROUP BY l.lane, l.up, l.busy, l.prog
$a3$,
$a4$                   'resource', x.lane, 'units_up', x.up, 'busy_now', x.busy, 'idle_now', GREATEST(x.up - x.busy, 0),
                   'idle_with_car_ready', LEAST(GREATEST(x.up - x.busy, 0), x.ready),
$a4$,
$a5$ and the cars still to come home are in no line. */
$a5$];
  v_news text[] := ARRAY[
$b1$  ), bs AS (
    --: 0835 (G541): each bay up, whether it is taken now (a car stands in it, or a held or active booking covers
    --: the clock), and the car a held or active booking brings to it within 10 minutes.
    SELECT s.id, s.stall_type::text AS lane,
           (s.current_vehicle_id IS NOT NULL
            OR EXISTS (SELECT 1 FROM ottoq_stall_bookings b
                        WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                          AND b.state IN ('held', 'active') AND b.during @> p_clock)) AS taken,
           (SELECT b.vehicle_id FROM ottoq_stall_bookings b
             WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id AND b.state IN ('held', 'active')
               AND lower(b.during) > p_clock AND lower(b.during) <= p_clock + interval '10 minutes'
             ORDER BY lower(b.during), b.vehicle_id LIMIT 1) AS due_car
      FROM stalls s
     WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('service_bay', 'wash_bay')
       AND COALESCE(s.status::text, '') NOT IN ('maintenance', 'closed')
  ), lanes AS (
    SELECT l.lane,
           (SELECT count(*) FROM bs WHERE bs.lane = l.lane AND bs.taken)::int AS taken,              --: 0835
           (SELECT count(*) FROM bs WHERE bs.lane = l.lane AND NOT bs.taken AND bs.due_car IS NOT NULL)::int AS held,
$b1$,
$b2$           (SELECT count(*) FROM vehicles v WHERE v.home_depot_id = p_depot_id
               AND v.current_state::text = ANY (CASE l.lane WHEN 'service_bay' THEN ARRAY['in_service_bay']
                                                            ELSE ARRAY['in_wash_bay', 'in_detail_bay'] END))::int AS in_bay,
$b2$,
$b3$    --: 0835: busy is the larger of the cars in the bay by state and the bays taken, never more than the bays up; a
    --: bay held for a car due is not more than what is left; a ready car owes no charge, is not the car a bay is
    --: held for, and is not in another bay, in an emergency state or out of service.
    SELECT l.lane, l.up, LEAST(l.up, GREATEST(l.in_bay, l.taken))::int AS busy,
           LEAST(l.held, GREATEST(l.up - GREATEST(l.in_bay, l.taken), 0))::int AS held,
           l.prog, count(f.vehicle_id)::int AS q, COALESCE(sum(f.owe_min), 0) AS qmin,
           (count(f.vehicle_id) FILTER (
              WHERE NOT ottoq.ottoq_vehicle_owes_charge_now(f.vehicle_id, p_clock)
                AND NOT EXISTS (SELECT 1 FROM bs WHERE bs.lane = l.lane AND bs.due_car = f.vehicle_id)
                AND NOT EXISTS (SELECT 1 FROM vehicles rv
                                 WHERE rv.id = f.vehicle_id
                                   AND rv.current_state::text IN ('in_service_bay', 'in_wash_bay', 'in_detail_bay',
                                                                  'emergency_staged', 'tow_requested',
                                                                  'out_of_service'))))::int AS ready
      FROM lanes l LEFT JOIN fin f ON f.res = l.lane
     GROUP BY l.lane, l.up, l.in_bay, l.taken, l.held, l.prog
$b3$,
$b4$                   'resource', x.lane, 'units_up', x.up, 'busy_now', x.busy, 'idle_now', GREATEST(x.up - x.busy, 0),
                   'held_for_car_due', x.held,                                                          --: 0835
                   'idle_with_car_ready', LEAST(GREATEST(x.up - x.busy - x.held, 0), x.ready),
$b4$,
$b5$ and the cars still to come home are in no line.
   0835 (G541): a bay is busy when a car stands in it or a held or active booking covers the clock, as well as by the
   cars' states; held_for_car_due counts the bays not busy that a booked car reaches within 10 minutes; and
   idle_with_car_ready counts neither, nor a ready car that is that car, is in another bay or is out of service. */
$b5$];
BEGIN
  FOR i IN 1..5 LOOP
    v_old := replace(v_olds[i], E'\r', ''); v_new := replace(v_news[i], E'\r', '');
    IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
      RAISE EXCEPTION '0835: anchor % does not match exactly once', i;
    END IF;
    v_def := replace(v_def, v_old, v_new);
  END LOOP;
  EXECUTE v_def;
END $patch$;

-- ── V1: nothing about the function but its body moved ──
DO $v1$
BEGIN
  IF EXISTS (SELECT 1 FROM _0835_attrs a, pg_proc p
              WHERE p.oid = 'public.ottoq_depot_constraint(uuid,uuid,timestamp with time zone)'::regprocedure
                AND (p.proacl::text, p.prosecdef, p.provolatile, p.proconfig::text, p.proowner)
                    IS DISTINCT FROM (a.acl, a.prosecdef, a.provolatile, a.config, a.proowner)) THEN
    RAISE EXCEPTION '0835 V1 FAILED: the function''s ACL, security, volatility, settings or owner moved';
  END IF;
END $v1$;

-- ── V2: on the 20 latest runs here, each at its own clock ──
DO $v2$
DECLARE r record; n jsonb; o jsonb; e jsonb; oe jsonb; v_runs int := 0; v_busy_up int := 0; v_ready_down int := 0;
  v_strip text[] := ARRAY['busy_now', 'idle_now', 'held_for_car_due', 'idle_with_car_ready'];
BEGIN
  FOR r IN SELECT s.sim_run_id, s.depot_id, s.sim_clock_current AS c FROM public.ottoq_sim_runs s
            WHERE s.depot_id IS NOT NULL AND s.sim_clock_current IS NOT NULL
            ORDER BY s.started_at DESC NULLS LAST, s.sim_run_id LIMIT 20 LOOP
    n := public.ottoq_depot_constraint(r.sim_run_id, r.depot_id, r.c);
    o := pg_temp._0835_pre(r.sim_run_id, r.depot_id, r.c);
    IF (n - 'resources') IS DISTINCT FROM (o - 'resources')
       OR jsonb_array_length(n -> 'resources') IS DISTINCT FROM jsonb_array_length(o -> 'resources') THEN
      RAISE EXCEPTION '0835 V2 FAILED: run % moved outside its resources', r.sim_run_id;
    END IF;
    FOR e IN SELECT x FROM jsonb_array_elements(n -> 'resources') x LOOP
      SELECT x INTO oe FROM jsonb_array_elements(o -> 'resources') x WHERE x ->> 'resource' = e ->> 'resource';
      IF e ->> 'resource' = 'posts' THEN
        IF e IS DISTINCT FROM oe THEN RAISE EXCEPTION '0835 V2 FAILED: run % posts moved', r.sim_run_id; END IF;
        CONTINUE;
      END IF;
      IF (e - v_strip) IS DISTINCT FROM (oe - v_strip) THEN
        RAISE EXCEPTION '0835 V2 FAILED: run % % moved outside its four counts', r.sim_run_id, e ->> 'resource';
      END IF;
      IF (e ->> 'busy_now')::int < (oe ->> 'busy_now')::int
         OR (e ->> 'idle_with_car_ready')::int > (oe ->> 'idle_with_car_ready')::int
         OR (e ->> 'busy_now')::int + (e ->> 'held_for_car_due')::int > (e ->> 'units_up')::int
         OR (e ->> 'idle_now')::int <> GREATEST((e ->> 'units_up')::int - (e ->> 'busy_now')::int, 0) THEN
        RAISE EXCEPTION '0835 V2 FAILED: run % %: busy fell, ready rose, or the counts exceed the bays (% against %)',
                        r.sim_run_id, e ->> 'resource', e, oe;
      END IF;
      v_busy_up := v_busy_up + ((e ->> 'busy_now')::int - (oe ->> 'busy_now')::int);
      v_ready_down := v_ready_down + ((oe ->> 'idle_with_car_ready')::int - (e ->> 'idle_with_car_ready')::int);
    END LOOP;
    v_runs := v_runs + 1;
  END LOOP;
  RAISE NOTICE '0835 V2 PASSED: % run(s); bays busy +%, idle with a car ready -%', v_runs, v_busy_up, v_ready_down;
END $v2$;

-- ── V3: the body is the one the scratch PostgreSQL ran ──
DO $v3$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_depot_constraint(uuid,uuid,timestamp with time zone)'::regprocedure)
       IS DISTINCT FROM '91ed02bdd251adb2c05c840d14616a2c' THEN
    RAISE EXCEPTION '0835 V3 FAILED: the body is not the one the tests ran (%)', (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_depot_constraint(uuid,uuid,timestamp with time zone)'::regprocedure);
  END IF;
END $v3$;

-- pg_temp._0835_pre is the session's own and goes with it: no statement here drops anything.

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0835_a_bay_held_for_a_car_on_its_way_in_is_not_idle_with_a_car_ready', false, false,
        'G541, second half. public.ottoq_depot_constraint, the bays only: busy_now is the larger of the cars in the bay '
        'by state and the bays a car stands in or a held or active booking covers now; held_for_car_due (new) counts the '
        'bays not busy on which a booking begins within 10 minutes; idle_with_car_ready counts neither, nor a ready car '
        'that is the car a bay is held for, is in another bay, is in an emergency state or is out of service. Read only '
        'by the agent''s board behind agent_board_grounding_enabled and agent_constraint_board, both 0 at the defaults, '
        'so no certification arm moves; no dial is added.',
        now());

COMMIT;
