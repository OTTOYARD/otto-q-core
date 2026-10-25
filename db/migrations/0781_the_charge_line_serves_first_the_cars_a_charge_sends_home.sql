-- migration-version: APPLIED-NO-LEDGER-ROW
-- migration-name:    the_charge_line_serves_first_the_cars_a_charge_sends_home
--
-- 0781  **The charge line serves first the cars a charge sends home, among each owner's own cars only: a car whose turn
--       in the bays is hours away yields its place to its own owner's cars whose charge is their way out, never to another
--       owner's, until that turn comes within its charge and a margin. A car that has waited 90 minutes is still served
--       first, and an immediate dispatch before every car.** (G501)
--       Chase, 2026-10-24: "Make sure we're not missing any edge in our intelligence ... Study all layers and study what
--       the ideal outcome is for optimal, autonomous, fleet, orchestration, and logistics. Go find an edge and build."
--       And on whose car goes first: "all fleet owners will want their vehicle arriving to take precedence over any other
--       vehicle (unless it is a homogeneous fleet from an OEM or owner/management perspective ... Remember, we don't own
--       our own vehicles, we manage for others- and ideally multiple OEM's at the same depot eventually. So always base
--       decisions off of that framing." So no owner's car waits for another owner's car because of this order: each
--       owner keeps the places its cars hold in the line without it, and only its own cars trade those places, for its
--       own uptime.
--       Rule 9 allows queueing and names better ordering of who is served next as the answer to site pressure. Nothing
--       here shortens a charge, skips or defers a service, or lets a car leave sooner than its needs allow: the cars that
--       yield are cars the service bays hold in the depot anyway, and each is charged before its turn in the bays comes.
--
-- ══ §1 WHY, MEASURED (read-only; db/checks/0471 and scripts/replay_charge_line.py reproduce every figure) ═══════════════
--
--   At the 30-post depot the wall is the two service bays (db/checks/0470 §1: about 124 bay-hours owed against 18 of
--   bay on a busy day). On the three busy days it has run (3389e651, 67290d0a, 78c0624c; sim 8 AM to 5 PM CT), the cars
--   that owed service-bay work (mechanical PM, calibration, repair) took 60-66% of the posts' charge-minutes, and 19 to
--   21 of the 120 to 128 such visits reached a service bay by the day's end. The cars that owed no service bay, whose
--   charge is their way out, waited a mean 23-57 minutes for a post. The kernel's line (0642: a car past 90 minutes
--   first, then the response ratio in minutes of charge) has no term for what a car does after its charge.
--   Replayed on each day's own arrivals, charge minutes and charger repairs, on 30 posts (a rehearsal, not the twin:
--   §5), with the bay line read as this file reads it (first come, work the depot took away first). Extracted on
--   2026-10-24 between 12:40 and 12:53 PM CT (17:40:55 and 17:53:58 UTC, the clock read either side) and replayed
--   offline by 1:11 PM CT; within each owner, on the engine's owners (read at 5:35 PM CT, 22:35:00 UTC), by 5:36 PM CT
--   (22:36:24 UTC):
--
--     day        order                       exit-bound cars:     bay-held cars:    bay seats reached     minutes past
--                                            wait / time in the   wait for a post   before the car was    the 30-minute
--                                            depot, minutes       (mean)            charged (minutes)     queue wait, all
--     78c0624c   today (floor 90, minutes)      28.9 / 7,536          65.0            5 (192)                6,255
--                this file (each owner's own)   23.1 / 6,884          70.2            5 (202)                6,461
--                across owners (not built)      18.4 / 6,345          78.8            5 (225)                7,143
--     67290d0a   today                          18.6 / 6,813          30.9            3 (46)                 1,836
--                this file                      11.5 / 5,922          39.2            3 (47)                 2,340
--                across owners                  10.4 / 5,786          40.0            4 (47)                 2,392
--     3389e651   today                          19.1 / 5,779          65.9            2 (149)                5,817
--                this file                       7.1 / 4,827          72.4            3 (158)                5,874
--                across owners                   4.8 / 4,651          73.6            2 (147)                5,929
--
--   (a) The cars a charge sends home spend 652 to 952 fewer minutes in the depot a day, 9-17%: 11 to 16 car-hours back
--       on the road, from the same posts and the same charges. Every owner's do, on every day: Tesla's 140-272 minutes,
--       Waymo's 197-696, Zoox's 55-230. Reordering across owners would add 136-539 more, all of it by putting one
--       owner's cars ahead of another's: not built.
--   (b) The bays are fed as before: the count of first service seats a car reached before its charge was done moves by
--       one at most. The bay line read here is an estimate (§2 (b)); the floor and decide section (4b) stand behind it.
--   (c) What it costs, stated rather than left to be found: the bay-held cars wait 5 to 8 minutes longer for a post
--       (3 to 9 by owner), and the minutes past the owners' 30-minute queue wait rise 1-27% in all, on each owner's own
--       cars, traded for its own uptime. Their exit does not move: they wait for the bays either way.
--   (d) Owners are the engine's, vehicles.fleet_operator_id: Waymo Nashville 46, Tesla Robotaxi TN 36 and Zoox
--       Southeast 34 of the depot's 116 cars, car for car the classes of the 2026-08-23 telemetry export.
--   (e) The margin matters little: at 60 the exit-bound cars' minutes read 6,862, 5,969 and 4,827, within 50 of 30's.
--       30 is the default.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Two dials, a person's (rule 10): charge_order_exit_first (0..1, default 0) and charge_order_exit_margin_min
--       (0..240, default 30).
--   (b) public.ottoq_bay_line(run, depot, clock), read-only: each car at the depot that owes bay work on its open visit
--       in this run and is not in that lane's bay now, per lane (the service bays; the wash bays with the detail work
--       they share), in the line's order (work the depot started and took away first, as 0003 has it, then the visit's
--       arrival, then the car); its open minutes there; the minutes of work ahead of it (the cars before it, and what is
--       left of each car in one of the lane's bays now, by its active booking); the lane's bays; and eta_min, its turn:
--       the work ahead over the bays. An estimate: decide section (4b) also ranks by urgency and deploy time, a car
--       waits for its charge before a bay, and the cars still to come home are not in it. It is also the first piece of
--       the agent's constraint board (G503).
--   (c) public.ottoq_charge_order_keys gains three columns, all NULL with the dial at 0, where it returns 0642's keys
--       exactly: exit_key, 1 for a car whose turn in the bays (bay_eta_min: the latest of its lanes) is its minutes of
--       charge and the margin or more away, 0 for every other car the clock times; bay_eta_min; and exit_rank, each car's
--       place in the line: the kernel's order without the key (immediate dispatch, the floor, minutes, 0545's ratio,
--       battery, car), with each owner's cars below the floor and not immediate reordered among the places that owner's
--       cars hold, its cars whose charge is their exit first, each group in that order. An owner is
--       vehicles.fleet_operator_id. Its columns change, so it is dropped and created, with the same grants.
--   (d) ottoq_decide_tick, OTTO-Q's seat: the cursor sorts by exit_rank after an agent's live order and before the
--       floor (the rank holds the floor and minutes already), reads it in the same statement as the other keys, and
--       records exit_key, bay_eta_min and exit_rank on the seat's 'charge_order' when the rank is set. Immediate dispatch,
--       an agent's live order, the baseline seats and the floor are untouched.
--   (e) The same rank in the same place in ottoq_charge_queue_kernel_order (the agent's board and the check's line),
--       ottoq_depot_queue (the cockpits) and ottoq_run_learning (the board's queue read).
--   (f) The check. ottoq_charge_line_state carries, with the dial at 1, each waiting car's turn in the bays (`bx`), the
--       owner of each of the depot's cars (`owners`), and `exit_first` and `exit_margin_min`; ottoq_charge_line_schedule
--       ranks its line as the keys do at each minute t of a future: the order without the key, then each owner's cars
--       below the floor reordered among that owner's places, a car yielding while bx - t - om >= the margin. A car coming
--       home, and a car a charger's fault at the order puts back in line, carry no bx and never yield. A state without
--       the key simulates by the statement before 0781, kept verbatim.
--   (g) The agent's board: 'kernel_order' says exit_first, that a car yields only to its own operator's cars, and the
--       margin; each car in the line the bays will hold carries bays_in_min and yields, as the kernel orders it.
--   Not changed: how full a car charges, when it may leave, which charger kind it wants, any service, the departure test
--   (rule 9), the floor, the agent's order and the check's comparison.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, no run running. P1 0642 applied; the eight bodies are the ones this file was written against
--   (md5); nothing it creates exists. Pre-images under '0781_pre'. Each anchor matches once. V1 each patched body is its
--   pre-image with its anchors replaced; the keys are stored as written; their grants are the pre-image's. V2 at the
--   defaults, on the latest twin-depot run at its last clock, the kernel's order, the cockpits' charge queue, the
--   learning's queue read, the check's state, its expected future and the board read value for value as before. V3 in a
--   sub-block that rolls back, with the dial at 1 on that run: every timed car carries an exit key and every car in the
--   line a rank; each owner's cars hold the same places as without the dial; within an owner, below the floor, no car
--   that yields is ahead of one that does not; the state carries exit_first and the margin, and the expected future
--   runs on it. Executed in full, the future's seats against the kernel's order included, by
--   tests/test_charge_order_exit_first_sql.py on the miniature depot carried through 0642 (whose charge-line bodies are
--   the live ones, md5 asserted) and the live decide tick (tests/fixtures/exit_first_decide_live.sql).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: at the default every key reads as before and every decision row
--   is byte for byte (the record's new fields are written only when the key is set). Rule 12 has the switch go on at
--   depot scope under the deciding person's name, with one demo run to show it working.
--
-- ══ §5 WHAT THE REHEARSAL IS AND IS NOT ═══════════════════════════════════════════════════════════════════════════════
--
--   A replay of each day's visits on its posts, minute by minute: arrivals at the visit's arrival, each charge its real
--   minutes, a post down from its faulted charge to its next charge. It does not replay the bays (each car's first
--   service seat is the day's own), the agent's orders, the gate, or the ticks; the replayed "today" waits less than the
--   day did (exit-bound 28.9 against 30.2 on 78c0624c, and 19.1 against 57.4 on 3389e651). Three worlds of one seed:
--   single readings, not ranges. What the twin shows is the demo run that switches it on.
--
-- ROLLBACK: DROP FUNCTION public.ottoq_charge_order_keys(uuid, uuid, timestamptz), then EXECUTE every `definition` in
--   ottoq_schema_snapshots WHERE label = '0781_pre' AND object_kind = 'function' (the keys' first) and re-grant the keys
--   as 0642 left them (EXECUTE to PUBLIC, anon, authenticated, service_role); DROP FUNCTION
--   public.ottoq_bay_line(uuid, uuid, timestamptz); DELETE FROM public.ottoq_policy_param_catalog WHERE param_key IN
--   ('charge_order_exit_first', 'charge_order_exit_margin_min') (and their policy rows); DELETE FROM
--   public.ottoq_cert_lineage WHERE name = '0781_the_charge_line_serves_first_the_cars_a_charge_sends_home'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight, no run running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0781 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0781 P0: a run is running; its decide tick and the readers would change mid-run. Apply between runs';
  END IF;
END $inflight$;

-- ── P1: 0642 is applied; every body is the one this file was written against; nothing it creates exists ──
DO $premises$
DECLARE r record;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0781_the_charge_line_serves_first_the_cars_a_charge_sends_home') THEN
    RAISE EXCEPTION '0781 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0642_the_kernel_serves_a_long_wait_first_and_times_its_line_in_minutes') THEN
    RAISE EXCEPTION '0781 P1: 0642 is not applied; apply it first';
  END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_charge_order_keys(uuid,uuid,timestamp with time zone)', '877318ab6ad7f7cf193ddd3e17938a1d', 'the keys (0642)'),
      ('public.ottoq_charge_queue_kernel_order(uuid,uuid,timestamp with time zone)', '100476a9bfa33e48b7495f6921979301', 'the kernel''s own order'),
      ('public.ottoq_depot_queue(uuid,uuid)', 'c84852a2e3f385d12b8ce4a77ada094a', 'the cockpits'' queue'),
      ('public.ottoq_run_learning(uuid,integer,boolean)', '3f4aa75740ef67f9e0c9ea6079ac58e0', 'the learning read'),
      ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 'c05f29bc7da1068acf1dfc1bad362ba5', 'the check''s state'),
      ('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', '0c4c8d2c5ecdcb84fd97d78dfa4c85a5', 'the check''s simulator'),
      ('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', '03cbb1a2e3b75a82874de01f7cf635ba', 'the agent''s board'),
      ('public.ottoq_decide_tick(uuid)', '2b3d0cbf5cdb13ca24f0de788073dc46', 'the decide tick')) AS t(fn, want, what)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.fn)) IS DISTINCT FROM r.want THEN
      RAISE EXCEPTION '0781 P1: % (%) is not the body this file patches (md5 %)', r.what, r.fn, left(r.want, 8);
    END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_bay_line(uuid,uuid,timestamp with time zone)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                 WHERE param_key IN ('charge_order_exit_first', 'charge_order_exit_margin_min')) THEN
    RAISE EXCEPTION '0781 P1: the bay line or a dial already exists';
  END IF;
END $premises$;

-- ── the pre-images, the keys' grants with them ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0781_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_charge_order_keys(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_charge_queue_kernel_order(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_depot_queue(uuid,uuid)'::regprocedure,
                 'public.ottoq_run_learning(uuid,integer,boolean)'::regprocedure,
                 'public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure,
                 'public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_decide_tick(uuid)'::regprocedure);

CREATE TEMP TABLE _0781_acl ON COMMIT DROP AS
SELECT r.rolname, has_function_privilege(r.oid, 'public.ottoq_charge_order_keys(uuid,uuid,timestamp with time zone)',
                                         'EXECUTE') AS can
  FROM pg_roles r WHERE r.rolname IN ('anon', 'authenticated', 'service_role');

-- ── V2's before: the readers at the defaults, on the latest twin-depot run at its last clock ──
CREATE TEMP TABLE _0781_before ON COMMIT DROP AS
WITH r AS (
  SELECT sim_run_id, depot_id, sim_clock_current AS clock FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND sim_clock_current IS NOT NULL
   ORDER BY started_at DESC NULLS LAST LIMIT 1)
SELECT r.sim_run_id, r.depot_id, r.clock,
       (SELECT COALESCE(jsonb_agg(jsonb_build_array(k.vehicle_id, k.kernel_pos) ORDER BY k.kernel_pos), '[]'::jsonb)
          FROM public.ottoq_charge_queue_kernel_order(r.sim_run_id, r.depot_id, r.clock) k) AS kernel,
       (SELECT COALESCE(jsonb_agg(jsonb_build_array(q.vehicle_id, q.queue_position) ORDER BY q.queue_position), '[]'::jsonb)
          FROM public.ottoq_depot_queue(r.depot_id, r.sim_run_id) q WHERE q.queue_kind = 'charge') AS cockpit,
       public.ottoq_run_learning(r.sim_run_id, 20, true) #> '{queue}' AS learning,
       public.ottoq_charge_line_state(r.sim_run_id, r.depot_id, r.clock) AS state,
       public.ottoq_agent_charge_queue_board(r.sim_run_id, r.depot_id, r.clock) AS board
  FROM r;

-- ── (a) the dials ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('charge_order_exit_first',
        '0781 (G501): 1 = after the floor (charge_wait_floor_min), the kernel''s charge line serves a car whose charge is its '
        'exit before one whose turn in the bays (ottoq_bay_line) is its charge and charge_order_exit_margin_min or more '
        'away; that car rejoins the front once its turn comes within its charge and the margin. The cursor, the kernel''s '
        'order, the cockpits'' queue, the board and the check''s futures all order by it. 0 = 0642''s order. Nothing '
        'shortens a charge or a service (rule 9). A person''s dial, never the agent''s (rule 10).',
        0, 0, 1, 'public.ottoq_charge_order_keys, public.ottoq_decide_tick, public.ottoq_charge_line_schedule', false),
       ('charge_order_exit_margin_min',
        '0781 (G501): with charge_order_exit_first at 1, how many minutes ahead of its turn in the bays a car''s charge '
        'must still be able to end for the car to yield the line; within it the car is ordered as a car whose charge is '
        'its exit. A person''s dial, never the agent''s (rule 10).',
        30, 0, 240, 'public.ottoq_charge_order_keys, public.ottoq_charge_line_schedule', false);

-- ── (b) the bay line ──
CREATE FUNCTION public.ottoq_bay_line(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS TABLE(vehicle_id uuid, lane text, pos integer, open_min numeric, ahead_min numeric, bays integer,
               eta_min numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  /* 0781 (G501): the depot's bay lines as the engine can read them now. Per lane (the service bays; the wash bays with
     the detail work they share), each car at the depot that owes bay work on its open visit in this run and is not in
     that lane's bay now: its place in the line (work the depot started and took away first, as 0003 has it, then the
     visit's arrival, then the car), its open minutes there (its atoms' est_min), the minutes of work ahead of it (the
     cars before it, and what is left of each car in one of the lane's bays now, by its active booking, in sim time),
     the lane's bays (its stalls not in maintenance or closed), and eta_min, its turn: the work ahead over the bays.
     An estimate, read-only: decide section (4b) also ranks by urgency and deploy time, a car still owing a charge
     waits for it before a bay, and the cars still to come home are not in it. */
  WITH owed AS (
    SELECT vn.vehicle_id,
           CASE WHEN a.value ->> 'requires_bay' = 'service_bay' THEN 'service_bay' ELSE 'wash_bay' END AS lane,
           GREATEST(COALESCE((a.value ->> 'est_min')::numeric, 0), 0) AS est,
           (a.value ? 'reopened_at' OR a.value ? 'cut_short_at') AS resumed,
           COALESCE(vn.arrived_at, vn.created_at) AS arrived,
           v.current_state::text AS state
      FROM ottoq_visit_needs vn
      JOIN vehicles v ON v.id = vn.vehicle_id
      CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(vn.atoms) = 'array' THEN vn.atoms
                                                   ELSE '[]'::jsonb END) a
     WHERE vn.sim_run_id = p_sim_run_id AND vn.status IN ('open', 'in_progress')
       AND v.home_depot_id = p_depot_id AND v.category = 'autonomous'
       AND a.value ->> 'requires_bay' IN ('service_bay', 'wash_bay', 'detail')
       AND COALESCE(a.value ->> 'status', 'pending') NOT IN ('done', 'cancelled', 'skipped', 'in_progress')
  ), cars AS (
    SELECT o.vehicle_id, o.lane, sum(o.est) AS open_min, bool_or(o.resumed) AS resumed, min(o.arrived) AS arrived
      FROM owed o
     WHERE NOT (o.lane = 'service_bay' AND o.state = 'in_service_bay')
       AND NOT (o.lane = 'wash_bay' AND o.state IN ('in_wash_bay', 'in_detail_bay'))
     GROUP BY o.vehicle_id, o.lane
  ), cap AS (
    SELECT l.lane,
           GREATEST((SELECT count(*) FROM stalls s
                      WHERE s.depot_id = p_depot_id AND s.stall_type::text = l.lane
                        AND COALESCE(s.status::text, '') NOT IN ('maintenance', 'closed')), 1)::int AS bays,
           COALESCE((SELECT sum(GREATEST(extract(epoch FROM (upper(b.during) - p_clock)) / 60.0, 0))
                       FROM ottoq_stall_bookings b JOIN stalls s ON s.id = b.stall_id
                      WHERE b.sim_run_id = p_sim_run_id AND s.depot_id = p_depot_id AND s.stall_type::text = l.lane
                        AND b.state = 'active' AND b.during @> p_clock), 0)::numeric AS busy_min
      FROM (VALUES ('service_bay'), ('wash_bay')) AS l(lane)
  )
  SELECT c.vehicle_id, c.lane, (row_number() OVER w)::int,
         round(c.open_min, 2),
         round(cap.busy_min + COALESCE(sum(c.open_min) OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0), 2),
         cap.bays,
         round((cap.busy_min + COALESCE(sum(c.open_min) OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0))
               / cap.bays, 2)
    FROM cars c JOIN cap ON cap.lane = c.lane
  WINDOW w AS (PARTITION BY c.lane ORDER BY c.resumed DESC, c.arrived ASC NULLS LAST, c.vehicle_id)
$function$;
GRANT EXECUTE ON FUNCTION public.ottoq_bay_line(uuid, uuid, timestamp with time zone)
  TO anon, authenticated, service_role;   -- as the keys that call it: invoker's rights, so a caller reads what its policies let it

-- ── (c) the keys, with the exit key and each owner's places ──
DROP FUNCTION public.ottoq_charge_order_keys(uuid, uuid, timestamp with time zone);
CREATE FUNCTION public.ottoq_charge_order_keys(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS TABLE(vehicle_id uuid, wait_min numeric, minutes numeric, floor_key numeric, minutes_key numeric,
               exit_key integer, bay_eta_min numeric, exit_rank integer)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0642 (G384): the two keys OTTO-Q's seat orders its charge line by after immediate dispatch and the agent's keys, and
   before 0545's ratio in points, for each car waiting for a charger at the depot. floor_key: a car that has waited
   charge_wait_floor_min (90) or longer goes ahead of every car that has not, the longest wait first (NULL below the
   floor, and for every car with the floor at 0). minutes_key: then the highest response ratio in minutes, (minutes
   waited + minutes its charge takes) / minutes its charge takes (ottoq_charge_order_minutes), with charge_order_minutes
   at 1 (NULL at 0, and for a car the clock cannot time, which then sorts by 0545's ratio). The wait is the cursor's own
   (ottoq_charge_wait_min). ottoq_decide_tick's cursor, ottoq_charge_queue_kernel_order, ottoq_depot_queue and
   ottoq_run_learning all read the keys here; the check's state carries the same dials (ottoq_charge_line_state).
   0781 (G501): with charge_order_exit_first at 1, three more. exit_key: 1 for a car whose turn in the bays (bay_eta_min:
   ottoq_bay_line's eta_min, the latest of the lanes it owes work in) is its minutes of charge and
   charge_order_exit_margin_min (30) or more away, 0 for every other car the clock times. exit_rank: each car's place in
   the line, which the readers sort by ahead of the floor: the kernel's order without the key (immediate dispatch, the
   floor, minutes, 0545's ratio, battery, car), with each owner's cars below the floor and not immediate reordered among
   the places that owner's cars hold, its cars whose exit_key is 0 first, each group in that order. A car yields only to
   its own owner's cars, and no owner's car is put behind another owner's car by it: we manage cars for their owners,
   and every owner wants its own car first (Chase, 2026-10-24). An owner is vehicles.fleet_operator_id; the cars of no
   operator share one owner's places. All three NULL with the dial at 0, where this returns 0642's keys exactly; a car
   the clock cannot time carries no exit_key, and a car not in the kernel's line carries no rank. */
DECLARE
  v_mon boolean := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_order_minutes', 1), 1) >= 1;
  v_fl numeric := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_wait_floor_min', 90), 90), 0);
  v_xon boolean := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_order_exit_first', 0), 0) >= 1;       -- 0781
  v_xm numeric := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_order_exit_margin_min', 30), 30), 0);
BEGIN
  IF NOT v_xon THEN
    IF NOT v_mon AND v_fl = 0 THEN
      RETURN;                                  -- both keys off: no car carries one, and every key sorts nothing
    END IF;
    RETURN QUERY
    WITH m AS (
      SELECT o.vehicle_id, o.minutes FROM public.ottoq_charge_order_minutes(p_sim_run_id, p_depot_id, p_clock) o WHERE v_mon
    )
    SELECT v.id, w.wait_min, m.minutes,
           CASE WHEN v_fl > 0 AND w.wait_min >= v_fl THEN w.wait_min END,
           CASE WHEN v_mon AND m.minutes IS NOT NULL THEN (w.wait_min + m.minutes) / m.minutes END,
           NULL::integer, NULL::numeric, NULL::integer
      FROM vehicles v
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_wait_min(v.config, v.last_state_change, p_clock, p_sim_run_id)::numeric AS wait_min) w
      LEFT JOIN m ON m.vehicle_id = v.id
     WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
       AND v.current_state::text IN ('arrived_at_gate', 'staged_awaiting_service');
    RETURN;
  END IF;
  -- 0781: the exit key reads every waiting car's minutes, whatever charge_order_minutes says; the rank reads the line
  -- as ottoq_charge_queue_kernel_order holds it (not faulted, below its visit target less one) and orders it as that
  -- does before the key
  RETURN QUERY
  WITH m AS (
    SELECT o.vehicle_id, o.minutes FROM public.ottoq_charge_order_minutes(p_sim_run_id, p_depot_id, p_clock) o
  ), b AS (
    SELECT l.vehicle_id, max(l.eta_min) AS eta
      FROM public.ottoq_bay_line(p_sim_run_id, p_depot_id, p_clock) l GROUP BY l.vehicle_id
  ), k AS (
    SELECT v.id, v.fleet_operator_id AS op, v.current_soc AS soc, w.wait_min, m.minutes,
           CASE WHEN v_fl > 0 AND w.wait_min >= v_fl THEN w.wait_min END AS floor_key,
           CASE WHEN v_mon AND m.minutes IS NOT NULL THEN (w.wait_min + m.minutes) / m.minutes END AS minutes_key,
           CASE WHEN m.minutes IS NULL THEN NULL WHEN b.eta - m.minutes >= v_xm THEN 1 ELSE 0 END AS exit_key,
           CASE WHEN m.minutes IS NOT NULL THEN b.eta END AS bay_eta_min,
           vn.immediate, vn.visit_target,
           GREATEST(public.ottoq_effective_target_soc_at(v.id, p_clock) - v.current_soc, 1) AS gap,
           public.ottoq_vehicle_fault_open(v.config) AS fault_open
      FROM vehicles v
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_wait_min(v.config, v.last_state_change, p_clock, p_sim_run_id)::numeric AS wait_min) w
      LEFT JOIN m ON m.vehicle_id = v.id
      LEFT JOIN b ON b.vehicle_id = v.id
      CROSS JOIN LATERAL (
        SELECT COALESCE((SELECT x.urgency = 'immediate_dispatch' FROM ottoq_visit_needs x
                          WHERE x.vehicle_id = v.id AND x.status IN ('open', 'in_progress')
                            AND COALESCE(x.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                              = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                          ORDER BY x.created_at DESC, x.visit_key DESC LIMIT 1), false) AS immediate,
               COALESCE((SELECT x.target_soc FROM ottoq_visit_needs x
                          WHERE x.vehicle_id = v.id AND x.status IN ('open', 'in_progress')
                            AND COALESCE(x.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                              = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                          ORDER BY x.created_at DESC, x.visit_key DESC LIMIT 1), public.ottoq_default_target_soc()) AS visit_target) vn
     WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
       AND v.current_state::text IN ('arrived_at_gate', 'staged_awaiting_service')
  ), r AS (
    SELECT k.id, k.op, k.exit_key, (NOT k.immediate AND k.floor_key IS NULL) AS xch,
           row_number() OVER (ORDER BY k.immediate DESC, k.floor_key DESC NULLS LAST, k.minutes_key DESC NULLS LAST,
                                       (k.wait_min + k.gap) / k.gap DESC NULLS LAST, k.soc ASC, k.id) AS r0
      FROM k WHERE NOT k.fault_open AND k.soc < k.visit_target - 1
  ), e AS (
    SELECT r.id,
           (CASE WHEN r.xch
                 THEN (array_agg(r.r0) OVER (PARTITION BY r.xch, r.op ORDER BY r.r0
                                             ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING))
                        [row_number() OVER (PARTITION BY r.xch, r.op ORDER BY COALESCE(r.exit_key, 0), r.r0)]
                 ELSE r.r0 END)::int AS exit_rank
      FROM r
  )
  SELECT k.id, k.wait_min, k.minutes, k.floor_key, k.minutes_key, k.exit_key, k.bay_eta_min, e.exit_rank
    FROM k LEFT JOIN e ON e.id = k.id;
END $function$;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_order_keys(uuid, uuid, timestamp with time zone)
  TO anon, authenticated, service_role;   -- as 0642 left it (V1 compares)

-- ── (d)-(g): the anchored replacements ──
CREATE TEMP TABLE _0781_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0781_patch VALUES
  -- d1: the decide tick reads each car's place in the line, its exit key and its turn in the bays with the other keys
  (1, 'public.ottoq_decide_tick(uuid)'::regprocedure,
   $o1$      SELECT COALESCE(jsonb_object_agg(k.vehicle_id::text, jsonb_build_array(k.floor_key, k.minutes_key)), '{}'::jsonb)
        INTO v_ok
        FROM public.ottoq_charge_order_keys(p_sim_run_id, v_depot, v_clock) k
       WHERE k.floor_key IS NOT NULL OR k.minutes_key IS NOT NULL;
$o1$,
   $n1$      /* 0781 (G501): and, with charge_order_exit_first at 1, each car's exit key, its turn in the bays and its place in
         the line with its owner's exchange made: {car: [floor_key, minutes_key, exit_key, bay_eta_min, exit_rank]}. At
         0 every rank is NULL and each car carries 0642's two keys, as before. */
      SELECT COALESCE(jsonb_object_agg(k.vehicle_id::text,
               CASE WHEN k.exit_rank IS NULL THEN jsonb_build_array(k.floor_key, k.minutes_key)
                    ELSE jsonb_build_array(k.floor_key, k.minutes_key, k.exit_key, k.bay_eta_min, k.exit_rank) END),
               '{}'::jsonb)
        INTO v_ok
        FROM public.ottoq_charge_order_keys(p_sim_run_id, v_depot, v_clock) k
       WHERE k.floor_key IS NOT NULL OR k.minutes_key IS NOT NULL OR k.exit_rank IS NOT NULL;
$n1$),
  -- d2: the cursor sorts by the place after the agent's keys and before the floor
  (2, 'public.ottoq_decide_tick(uuid)'::regprocedure,
   $o2$              (v_ok -> v.id::text ->> 0)::numeric DESC NULLS LAST,
              (v_ok -> v.id::text ->> 1)::numeric DESC NULLS LAST,
$o2$,
   $n2$              /* 0781 (G501): with charge_order_exit_first at 1, each car's place in the kernel's line
                 (ottoq_charge_order_keys' exit_rank): the order below, with each owner's cars below the floor and not
                 immediate reordered among the places that owner's cars hold, its cars whose charge is their exit first.
                 The floor and minutes after it then sort nothing. NULL for every car at 0: 0642's order. */
              (v_ok -> v.id::text ->> 4)::numeric ASC NULLS LAST,
              (v_ok -> v.id::text ->> 0)::numeric DESC NULLS LAST,
              (v_ok -> v.id::text ->> 1)::numeric DESC NULLS LAST,
$n2$),
  -- d3: the seat records them when the place is set
  (3, 'public.ottoq_decide_tick(uuid)'::regprocedure,
   $o3$      v_ctx := v_ctx || jsonb_build_object('charge_order', jsonb_build_object(
                 'floor_key', v_ok -> v_req.vehicle_id::text -> 0, 'minutes_key', v_ok -> v_req.vehicle_id::text -> 1));
    END IF;
$o3$,
   $n3$      v_ctx := v_ctx || jsonb_build_object('charge_order', jsonb_build_object(
                 'floor_key', v_ok -> v_req.vehicle_id::text -> 0, 'minutes_key', v_ok -> v_req.vehicle_id::text -> 1));
    END IF;
    IF v_ok -> v_req.vehicle_id::text ->> 4 IS NOT NULL THEN   /* 0781 (G501): its exit key, its turn in the bays, its place */
      v_ctx := jsonb_set(v_ctx, '{charge_order}', (v_ctx -> 'charge_order')
                 || jsonb_build_object('exit_key', v_ok -> v_req.vehicle_id::text -> 2,
                                       'bay_eta_min', v_ok -> v_req.vehicle_id::text -> 3,
                                       'exit_rank', v_ok -> v_req.vehicle_id::text -> 4));
    END IF;
$n3$),
  -- e1: the kernel's own order
  (4, 'public.ottoq_charge_queue_kernel_order(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o4$                                            ok.floor_key DESC NULLS LAST, ok.minutes_key DESC NULLS LAST,   -- 0642
$o4$,
   $n4$                                            ok.exit_rank ASC NULLS LAST,                                    -- 0781 (G501)
                                            ok.floor_key DESC NULLS LAST, ok.minutes_key DESC NULLS LAST,   -- 0642
$n4$),
  -- e2: the cockpits' queue
  (5, 'public.ottoq_depot_queue(uuid,uuid)'::regprocedure,
   $o5$                                        (SELECT k.floor_key FROM ok k WHERE k.vehicle_id = c.id) DESC NULLS LAST,     -- 0642
$o5$,
   $n5$                                        (SELECT k.exit_rank FROM ok k WHERE k.vehicle_id = c.id) ASC NULLS LAST,      -- 0781 (G501)
                                        (SELECT k.floor_key FROM ok k WHERE k.vehicle_id = c.id) DESC NULLS LAST,     -- 0642
$n5$),
  -- e3: the learning's queue read
  (6, 'public.ottoq_run_learning(uuid,integer,boolean)'::regprocedure,
   $o6$                      (SELECT k.floor_key FROM ok k WHERE k.vehicle_id = q.id) DESC NULLS LAST,     -- 0642
$o6$,
   $n6$                      (SELECT k.exit_rank FROM ok k WHERE k.vehicle_id = q.id) ASC NULLS LAST,      -- 0781 (G501)
                      (SELECT k.floor_key FROM ok k WHERE k.vehicle_id = q.id) DESC NULLS LAST,     -- 0642
$n6$),
  -- f1: the state's dials
  (7, 'public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o7$  v_fm jsonb; v_r0 timestamptz;                                                                     -- 0635
$o7$,
   $n7$  v_fm jsonb; v_r0 timestamptz;                                                                     -- 0635
  -- 0781 (G501): the exit key, as this run's dials stand, and each waiting car's turn in the bays
  v_xon boolean := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_order_exit_first', 0), 0) >= 1;
  v_xm numeric := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_order_exit_margin_min', 30), 30), 0);
  v_bx jsonb := '{}'::jsonb;
$n7$),
  -- f2: the cars' turns in the bays, read once
  (8, 'public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o8$  v_ev := public.ottoq_charge_clock_run_evidence(v_ct, p_sim_run_id, p_clock);
$o8$,
   $n8$  v_ev := public.ottoq_charge_clock_run_evidence(v_ct, p_sim_run_id, p_clock);
  IF v_xon THEN                                                                                     -- 0781
    SELECT COALESCE(jsonb_object_agg(z.vehicle_id::text, z.eta), '{}'::jsonb) INTO v_bx
      FROM (SELECT l.vehicle_id, max(l.eta_min) AS eta
              FROM public.ottoq_bay_line(p_sim_run_id, p_depot_id, p_clock) l GROUP BY l.vehicle_id) z;
  END IF;
$n8$),
  -- f3: each waiting car carries its turn in the bays
  (9, 'public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o9$           || CASE WHEN x.mw IS NOT NULL THEN jsonb_build_object('mw', x.mw) ELSE '{}'::jsonb END                       -- 0642
$o9$,
   $n9$           || CASE WHEN x.mw IS NOT NULL THEN jsonb_build_object('mw', x.mw) ELSE '{}'::jsonb END                       -- 0642
           || CASE WHEN x.bx IS NOT NULL THEN jsonb_build_object('bx', x.bx) ELSE '{}'::jsonb END                       -- 0781
$n9$),
  (10, 'public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o10$                 public.ottoq_contract_queue_wait_min(v.id, p_clock) AS mw,                                     -- 0642
$o10$,
   $n10$                 public.ottoq_contract_queue_wait_min(v.id, p_clock) AS mw,                                     -- 0642
                 (v_bx ->> v.id::text)::numeric AS bx,                                                           -- 0781
$n10$),
  -- f4: the state says the kernel orders by it, and whose each car is
  (11, 'public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o11$    'floor_min', GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_wait_floor_min', 90), 90), 0));
$o11$,
   $n11$    'floor_min', GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_wait_floor_min', 90), 90), 0));
  IF v_xon THEN                                                                                     -- 0781 (G501)
    -- the exit key, its margin, and each of the depot's cars' owner (vehicles.fleet_operator_id; JSON null for a car of
    -- none): the futures exchange places only among one owner's cars, as the keys do
    v_state := v_state || jsonb_build_object('exit_first', true, 'exit_margin_min', v_xm, 'owners',
                 (SELECT COALESCE(jsonb_object_agg(ov.id::text, ov.fleet_operator_id), '{}'::jsonb)
                    FROM vehicles ov WHERE ov.home_depot_id = p_depot_id AND ov.category = 'autonomous'));
  END IF;
$n11$),
  -- f5: the simulator's exit key, margin and owners
  (12, 'public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure,
   $o12$  c_om float8[] := '{}'; c_mw float8[] := '{}';
$o12$,
   $n12$  c_om float8[] := '{}'; c_mw float8[] := '{}';
  -- 0781 (G501): the kernel's exit key (exit_first, exit_margin_min: ottoq_charge_line_state), each car's owner (owners)
  -- and each waiting car's turn in the bays, in minutes from the order (bx); a car coming home, or put back in line by a
  -- charger that faults at the order, carries no bx and never yields
  v_xon boolean := COALESCE((p_state ->> 'exit_first')::boolean, false);
  v_xm float8 := GREATEST(COALESCE((p_state ->> 'exit_margin_min')::float8, 30), 0);
  v_own jsonb := COALESCE(p_state -> 'owners', '{}'::jsonb);
  c_bx float8[] := '{}';
$n12$),
  (13, 'public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure,
   $o13$      c_om[n] := (e ->> 'om')::float8; c_mw[n] := (e ->> 'mw')::float8;                          -- 0642
$o13$,
   $n13$      c_om[n] := (e ->> 'om')::float8; c_mw[n] := (e ->> 'mw')::float8;                          -- 0642
      c_bx[n] := (e ->> 'bx')::float8;                                                             -- 0781
$n13$),
  -- f6: the line at t, ordered as the cursor orders it, with each owner's exchange
  (14, 'public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure,
   $o14$    -- the cars waiting at t, in the cursor's order at t
    SELECT array_agg(u.i ORDER BY
             u.imm DESC,
             CASE WHEN v_live THEN u.w >= v_pin END DESC NULLS LAST,
             CASE WHEN v_live AND NOT (u.w >= v_pin) THEN
                    CASE WHEN u.rk IS NULL THEN 500
                         ELSE u.rk + CASE WHEN v_mode = 'dcfc' AND u.ok = 'l2' THEN 1000
                                          WHEN v_mode = 'l2' AND u.ok = 'dcfc' THEN 1000 ELSE 0 END END END ASC NULLS LAST,
             -- 0642: the kernel's own keys after the agent's: the longest wait past the floor first, then the response
             -- ratio in minutes of charge (NULL for every car in a state without them: 0641's order, key for key)
             CASE WHEN v_floor > 0 AND u.w >= v_floor THEN u.w END DESC NULLS LAST,
             CASE WHEN v_omon THEN (u.w + u.om) / u.om END DESC NULLS LAST,
             (u.w + u.g) / u.g DESC, u.soc ASC, u.idr ASC)
      INTO v_order
      FROM (SELECT z3.i, c_imm[z3.i] AS imm,
                   CASE WHEN c_inb[z3.i] THEN t - c_av[z3.i] ELSE c_w0[z3.i] + t END AS w,
                   c_g[z3.i] AS g, c_soc[z3.i] AS soc, c_idr[z3.i] AS idr, c_rank[z3.i] AS rk, c_okind[z3.i] AS ok,
                   GREATEST(COALESCE(c_om[z3.i], CASE WHEN c_dok[z3.i] AND NOT c_lok[z3.i] THEN c_md[z3.i]
                                                      WHEN c_lok[z3.i] AND NOT c_dok[z3.i] THEN c_ml[z3.i]
                                                      ELSE LEAST(c_md[z3.i], c_ml[z3.i]) END), 1) AS om      -- 0642
              FROM generate_subscripts(c_ready, 1) AS z3(i)
             WHERE z3.i <= n AND c_ready[z3.i] IS NULL AND c_gate[z3.i] <= t
               AND c_vk[z3.i] < 2 AND NOT c_void[z3.i]) u;
$o14$,
   $n14$    -- the cars waiting at t, in the cursor's order at t
    IF v_xon THEN
      -- 0781 (G501): the kernel's own order at t without the exit key (r0), and each car's place in it with its owner's
      -- exchange made (xr): each owner's cars below the floor and not immediate reordered among the places that
      -- owner's cars hold, its cars whose charge is their exit first (xk 0: no turn in the bays, or one its charge and
      -- the margin do not reach by t), each group in r0. Sorted after the agent's keys, as the cursor sorts exit_rank.
      SELECT array_agg(u.i ORDER BY
               u.imm DESC,
               CASE WHEN v_live THEN u.w >= v_pin END DESC NULLS LAST,
               CASE WHEN v_live AND NOT (u.w >= v_pin) THEN
                      CASE WHEN u.rk IS NULL THEN 500
                           ELSE u.rk + CASE WHEN v_mode = 'dcfc' AND u.ok = 'l2' THEN 1000
                                            WHEN v_mode = 'l2' AND u.ok = 'dcfc' THEN 1000 ELSE 0 END END END ASC NULLS LAST,
               u.xr ASC)
        INTO v_order
        FROM (SELECT y.i, y.imm, y.w, y.rk, y.ok,
                     CASE WHEN y.xch
                          THEN (array_agg(y.r0) OVER (PARTITION BY y.xch, y.op ORDER BY y.r0
                                                      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING))
                                 [row_number() OVER (PARTITION BY y.xch, y.op ORDER BY y.xk, y.r0)]
                          ELSE y.r0 END AS xr
                FROM (SELECT x.*,
                             row_number() OVER (ORDER BY x.imm DESC,
                                                         CASE WHEN v_floor > 0 AND x.w >= v_floor THEN x.w END DESC NULLS LAST,
                                                         CASE WHEN v_omon THEN (x.w + x.om) / x.om END DESC NULLS LAST,
                                                         (x.w + x.g) / x.g DESC, x.soc ASC, x.idr ASC) AS r0,
                             (NOT x.imm AND NOT (v_floor > 0 AND x.w >= v_floor)) AS xch,
                             CASE WHEN x.bx IS NOT NULL AND x.bx - t - x.om >= v_xm THEN 1 ELSE 0 END AS xk
                        FROM (SELECT z3.i, c_imm[z3.i] AS imm,
                                     CASE WHEN c_inb[z3.i] THEN t - c_av[z3.i] ELSE c_w0[z3.i] + t END AS w,
                                     c_g[z3.i] AS g, c_soc[z3.i] AS soc, c_idr[z3.i] AS idr, c_rank[z3.i] AS rk,
                                     c_okind[z3.i] AS ok, v_own ->> c_id[z3.i] AS op, c_bx[z3.i] AS bx,
                                     GREATEST(COALESCE(c_om[z3.i], CASE WHEN c_dok[z3.i] AND NOT c_lok[z3.i] THEN c_md[z3.i]
                                                                        WHEN c_lok[z3.i] AND NOT c_dok[z3.i] THEN c_ml[z3.i]
                                                                        ELSE LEAST(c_md[z3.i], c_ml[z3.i]) END), 1) AS om
                                FROM generate_subscripts(c_ready, 1) AS z3(i)
                               WHERE z3.i <= n AND c_ready[z3.i] IS NULL AND c_gate[z3.i] <= t
                                 AND c_vk[z3.i] < 2 AND NOT c_void[z3.i]) x) y) u;
    ELSE
      -- without the key, the statement before 0781, key for key
      SELECT array_agg(u.i ORDER BY
               u.imm DESC,
               CASE WHEN v_live THEN u.w >= v_pin END DESC NULLS LAST,
               CASE WHEN v_live AND NOT (u.w >= v_pin) THEN
                      CASE WHEN u.rk IS NULL THEN 500
                           ELSE u.rk + CASE WHEN v_mode = 'dcfc' AND u.ok = 'l2' THEN 1000
                                            WHEN v_mode = 'l2' AND u.ok = 'dcfc' THEN 1000 ELSE 0 END END END ASC NULLS LAST,
               -- 0642: the kernel's own keys after the agent's: the longest wait past the floor first, then the response
               -- ratio in minutes of charge (NULL for every car in a state without them: 0641's order, key for key)
               CASE WHEN v_floor > 0 AND u.w >= v_floor THEN u.w END DESC NULLS LAST,
               CASE WHEN v_omon THEN (u.w + u.om) / u.om END DESC NULLS LAST,
               (u.w + u.g) / u.g DESC, u.soc ASC, u.idr ASC)
        INTO v_order
        FROM (SELECT z3.i, c_imm[z3.i] AS imm,
                     CASE WHEN c_inb[z3.i] THEN t - c_av[z3.i] ELSE c_w0[z3.i] + t END AS w,
                     c_g[z3.i] AS g, c_soc[z3.i] AS soc, c_idr[z3.i] AS idr, c_rank[z3.i] AS rk, c_okind[z3.i] AS ok,
                     GREATEST(COALESCE(c_om[z3.i], CASE WHEN c_dok[z3.i] AND NOT c_lok[z3.i] THEN c_md[z3.i]
                                                        WHEN c_lok[z3.i] AND NOT c_dok[z3.i] THEN c_ml[z3.i]
                                                        ELSE LEAST(c_md[z3.i], c_ml[z3.i]) END), 1) AS om      -- 0642
                FROM generate_subscripts(c_ready, 1) AS z3(i)
               WHERE z3.i <= n AND c_ready[z3.i] IS NULL AND c_gate[z3.i] <= t
                 AND c_vk[z3.i] < 2 AND NOT c_void[z3.i]) u;
    END IF;
$n14$),
  -- g1: the board says how the kernel orders
  (15, 'public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o15$      'by', CASE WHEN COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_order_minutes', 1), 1) >= 1
                 THEN 'charge_minutes' ELSE 'points' END),
$o15$,
   $n15$      'by', CASE WHEN COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_order_minutes', 1), 1) >= 1
                 THEN 'charge_minutes' ELSE 'points' END)
      -- 0781 (G501): and, with the exit key on, below the floor each operator's cars whose charge is their exit go
      -- before that operator's cars whose turn in the bays is their charge and exit_margin_min or more away, in the
      -- places that operator's cars hold: a car yields only to its own operator's cars
      || CASE WHEN COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_order_exit_first', 0), 0) >= 1
              THEN jsonb_build_object('exit_first', true, 'exit_yields_to', 'own_operator', 'exit_margin_min',
                     GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_order_exit_margin_min', 30), 30), 0))
              ELSE '{}'::jsonb END,
$n15$),
  -- g2: each car the bays will hold says when its turn comes and whether it yields its place
  (16, 'public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o16$                        FROM pl WHERE pl.id = v.id::text)) AS j
$o16$,
   $n16$                        FROM pl WHERE pl.id = v.id::text))
             -- 0781 (G501): with the exit key on, the minutes until this car's turn in the bays (the state's bx), and
             -- whether the kernel has it yield its place to its own operator's cars a charge sends home (below the
             -- floor, not an immediate dispatch, and its turn its charge and the margin or more away)
             || COALESCE((SELECT jsonb_build_object(
                                   'bays_in_min', round((c.value ->> 'bx')::numeric, 0),
                                   'yields', NOT COALESCE((c.value ->> 'imm')::boolean, false)
                                             AND NOT (COALESCE((ps.s ->> 'floor_min')::numeric, 0) > 0
                                                      AND (c.value ->> 'w')::numeric >= (ps.s ->> 'floor_min')::numeric)
                                             AND (c.value ->> 'bx')::numeric - (c.value ->> 'om')::numeric
                                                 >= COALESCE((ps.s ->> 'exit_margin_min')::numeric, 30))
                            FROM ps, jsonb_array_elements(COALESCE(ps.s -> 'cars', '[]'::jsonb)) c
                           WHERE c.value ->> 'id' = v.id::text AND c.value ? 'bx' LIMIT 1), '{}'::jsonb) AS j
$n16$);

DO $patch$
DECLARE f regprocedure; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0781_patch LOOP
    v_def := pg_get_functiondef(f);
    FOR p IN SELECT * FROM _0781_patch WHERE fn = f ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0781: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(f) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0781: % is not stored as patched', f;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each patched body is its pre-image with its anchors replaced; the keys as written, with their grants ──
DO $v1$
DECLARE r record; p record; v_body text; v_n int := 0;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_charge_queue_kernel_order(uuid,uuid,timestamp with time zone)', '100476a9bfa33e48b7495f6921979301'),
      ('public.ottoq_depot_queue(uuid,uuid)', 'c84852a2e3f385d12b8ce4a77ada094a'),
      ('public.ottoq_run_learning(uuid,integer,boolean)', '3f4aa75740ef67f9e0c9ea6079ac58e0'),
      ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 'c05f29bc7da1068acf1dfc1bad362ba5'),
      ('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', '0c4c8d2c5ecdcb84fd97d78dfa4c85a5'),
      ('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', '03cbb1a2e3b75a82874de01f7cf635ba'),
      ('public.ottoq_decide_tick(uuid)', '2b3d0cbf5cdb13ca24f0de788073dc46')) AS t(fn, pre)
  LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = to_regprocedure(r.fn);
    FOR p IN SELECT * FROM _0781_patch WHERE fn = to_regprocedure(r.fn) ORDER BY seq DESC LOOP
      IF strpos(v_body, p.c_new) = 0 THEN
        RAISE EXCEPTION '0781 V1: % does not carry replacement %', r.fn, p.seq;
      END IF;
      v_body := replace(v_body, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_body) IS DISTINCT FROM r.pre THEN
      RAISE EXCEPTION '0781 V1: % less its replacements is not its pre-image (md5 %)', r.fn, md5(v_body);
    END IF;
    v_n := v_n + 1;
  END LOOP;
  IF EXISTS (SELECT 1 FROM _0781_acl a JOIN pg_roles g ON g.rolname = a.rolname
              WHERE has_function_privilege(g.oid, 'public.ottoq_charge_order_keys(uuid,uuid,timestamp with time zone)',
                                           'EXECUTE') IS DISTINCT FROM a.can) THEN
    RAISE EXCEPTION '0781 V1: the keys'' grants are not the ones 0642 left';
  END IF;
  RAISE NOTICE '0781 V1: % bodies are their pre-images with their anchors replaced; the keys carry 0642''s grants', v_n;
END $v1$;

-- ── V2: at the defaults the readers read as before, value for value ──
DO $v2$
DECLARE b record; v_k jsonb; v_q jsonb; v_l jsonb; v_s jsonb; v_bd jsonb;
BEGIN
  SELECT * INTO b FROM _0781_before;
  IF NOT FOUND THEN
    RAISE NOTICE '0781 V2: no twin-depot run to read; the tests execute it';
    RETURN;
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_array(k.vehicle_id, k.kernel_pos) ORDER BY k.kernel_pos), '[]'::jsonb) INTO v_k
    FROM public.ottoq_charge_queue_kernel_order(b.sim_run_id, b.depot_id, b.clock) k;
  SELECT COALESCE(jsonb_agg(jsonb_build_array(q.vehicle_id, q.queue_position) ORDER BY q.queue_position), '[]'::jsonb)
    INTO v_q FROM public.ottoq_depot_queue(b.depot_id, b.sim_run_id) q WHERE q.queue_kind = 'charge';
  v_l := public.ottoq_run_learning(b.sim_run_id, 20, true) #> '{queue}';
  v_s := public.ottoq_charge_line_state(b.sim_run_id, b.depot_id, b.clock);
  v_bd := public.ottoq_agent_charge_queue_board(b.sim_run_id, b.depot_id, b.clock);
  IF v_k IS DISTINCT FROM b.kernel OR v_q IS DISTINCT FROM b.cockpit OR v_l IS DISTINCT FROM b.learning
     OR v_s IS DISTINCT FROM b.state OR v_bd IS DISTINCT FROM b.board THEN
    RAISE EXCEPTION '0781 V2: at the defaults a reader moved on run % at %: kernel %, cockpit %, learning %, state %, board %',
      b.sim_run_id, b.clock, v_k = b.kernel, v_q = b.cockpit, v_l IS NOT DISTINCT FROM b.learning, v_s = b.state,
      v_bd = b.board;
  END IF;
  RAISE NOTICE '0781 V2: at the defaults, run % at %: the kernel''s order (% cars), the cockpits'' queue, the learning read, the state and the board read as before',
    left(b.sim_run_id::text, 8), b.clock, jsonb_array_length(v_k);
END $v2$;

-- ── V3: with the dial at 1, in a sub-block that rolls back ──
DO $v3$
DECLARE b record; v_msg text := NULL; v_timed int; v_keyed int; v_bad int; v_ones int; v_ops int; v_bx int;
        v_state jsonb;
BEGIN
  SELECT * INTO b FROM _0781_before;
  IF NOT FOUND THEN
    RAISE NOTICE '0781 V3: no twin-depot run to read; the tests execute it';
    RETURN;
  END IF;
  BEGIN
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value)
    VALUES ('run', b.sim_run_id, 'charge_order_exit_first', 1);
    CREATE TEMP TABLE _0781_v3k ON COMMIT DROP AS
    SELECT k.*, v.fleet_operator_id AS op
      FROM public.ottoq_charge_order_keys(b.sim_run_id, b.depot_id, b.clock) k JOIN vehicles v ON v.id = k.vehicle_id;
    CREATE TEMP TABLE _0781_v3o ON COMMIT DROP AS
    SELECT o.vehicle_id, o.kernel_pos AS pos, o.immediate, w.pos AS pos0
      FROM public.ottoq_charge_queue_kernel_order(b.sim_run_id, b.depot_id, b.clock) o
      LEFT JOIN (SELECT (e ->> 0)::uuid AS vehicle_id, (e ->> 1)::int AS pos
                   FROM jsonb_array_elements(b.kernel) e) w ON w.vehicle_id = o.vehicle_id;
    SELECT count(*) FILTER (WHERE k.minutes IS NOT NULL), count(*) FILTER (WHERE k.exit_key IS NOT NULL),
           count(*) FILTER (WHERE (k.minutes IS NOT NULL) <> (k.exit_key IS NOT NULL)),
           count(*) FILTER (WHERE k.exit_key = 1), count(DISTINCT k.op)
      INTO v_timed, v_keyed, v_bad, v_ones, v_ops
      FROM _0781_v3k k;
    IF v_bad > 0 THEN
      v_msg := format('%s timed cars without an exit key, or keyed cars the clock cannot time', v_bad);
    END IF;
    -- the kernel's order is the rank, and holds the cars it held without the dial
    IF v_msg IS NULL AND (EXISTS (SELECT 1 FROM _0781_v3o o LEFT JOIN _0781_v3k k ON k.vehicle_id = o.vehicle_id
                                   WHERE k.exit_rank IS DISTINCT FROM o.pos OR o.pos0 IS NULL)
                          OR (SELECT count(*) FROM _0781_v3o) <> jsonb_array_length(b.kernel)) THEN
      v_msg := 'the kernel''s order is not each car''s exit_rank, or holds other cars than it did without the dial';
    END IF;
    -- each owner's cars hold the places they held without the dial; immediate dispatch and the floor do not move
    IF v_msg IS NULL AND EXISTS (
         SELECT 1 FROM (SELECT k.op, array_agg(o.pos ORDER BY o.pos) AS now_, array_agg(o.pos0 ORDER BY o.pos0) AS was
                          FROM _0781_v3o o JOIN _0781_v3k k ON k.vehicle_id = o.vehicle_id
                         GROUP BY k.op) z
          WHERE z.now_ IS DISTINCT FROM z.was) THEN
      v_msg := 'an owner''s cars hold other places than they held without the dial';
    END IF;
    IF v_msg IS NULL AND EXISTS (SELECT 1 FROM _0781_v3o o JOIN _0781_v3k k ON k.vehicle_id = o.vehicle_id
                                  WHERE (o.immediate OR k.floor_key IS NOT NULL) AND o.pos <> o.pos0) THEN
      v_msg := 'an immediate dispatch or a car past the floor moved';
    END IF;
    -- within an owner, below the floor, no car that yields ahead of one that does not
    IF v_msg IS NULL AND EXISTS (
         SELECT 1 FROM _0781_v3o a JOIN _0781_v3k ka ON ka.vehicle_id = a.vehicle_id
           JOIN _0781_v3o c ON c.pos > a.pos JOIN _0781_v3k kc ON kc.vehicle_id = c.vehicle_id
          WHERE ka.op IS NOT DISTINCT FROM kc.op AND NOT a.immediate AND NOT c.immediate
            AND ka.floor_key IS NULL AND kc.floor_key IS NULL
            AND ka.exit_key = 1 AND COALESCE(kc.exit_key, 0) = 0) THEN
      v_msg := 'within an owner the kernel''s order puts a car the bays will hold before a car whose charge is its exit';
    END IF;
    v_state := public.ottoq_charge_line_state(b.sim_run_id, b.depot_id, b.clock);
    SELECT count(*) INTO v_bx FROM jsonb_array_elements(COALESCE(v_state -> 'cars', '[]'::jsonb)) c WHERE c.value ? 'bx';
    IF v_msg IS NULL AND (v_state ->> 'exit_first' IS DISTINCT FROM 'true' OR (v_state ->> 'exit_margin_min')::numeric <> 30
                          OR (SELECT count(*) FROM jsonb_object_keys(COALESCE(v_state -> 'owners', '{}'::jsonb)))
                             <> (SELECT count(*) FROM vehicles v WHERE v.home_depot_id = b.depot_id
                                                                   AND v.category = 'autonomous')) THEN
      v_msg := 'the state does not carry the exit key at its defaults and every car''s owner';
    END IF;
    -- and the expected future runs on it (its seats against the kernel's order are the tests')
    IF v_msg IS NULL AND public.ottoq_charge_line_schedule(v_state, NULL, 0, 'v3', true) -> 'seats' IS NULL THEN
      v_msg := 'the expected future does not run on the state with the exit key';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0781', MESSAGE = 'v3 done';
  EXCEPTION WHEN SQLSTATE 'P0781' THEN
    NULL;   -- the dial row, the two scratch tables and anything read under them roll back here
  END;
  IF v_msg IS NOT NULL THEN
    RAISE EXCEPTION '0781 V3: %', v_msg;
  END IF;
  RAISE NOTICE '0781 V3: with the dial at 1 on run %: % of % waiting cars timed, all keyed; % yield, each only to its own owner''s cars; every owner''s cars hold the places they held (% owners); the state carries the key and % turns in the bays',
    left(b.sim_run_id::text, 8), v_keyed, v_timed, v_ones, v_ops, v_bx;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0781_the_charge_line_serves_first_the_cars_a_charge_sends_home', false, false,
        'Dials charge_order_exit_first (default 0) and charge_order_exit_margin_min (30); new public.ottoq_bay_line; '
        'public.ottoq_charge_order_keys gains exit_key, bay_eta_min and exit_rank (NULL at the default): each car''s '
        'place, each owner''s cars below the floor reordered among that owner''s own places, its cars whose charge is '
        'their exit first. The rank leads the kernel''s keys in the decide tick''s cursor, the kernel''s order, the '
        'cockpits'' queue and the learning read; the check''s simulator exchanges the same way at each minute; the state''s '
        'bx and owners and the board''s fields only at 1 (V1: each body is its pre-image with its anchors replaced; V2: '
        'at the defaults every reader reads as before; V3: every owner''s cars hold their places). No certification arm, '
        'canon cell or dial experiment sets the dial.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-25 17:01:29 UTC (12:01 PM CT), no ledger row ═══════════════════════════════════════════════════
--
--   Chase ran this file in the Supabase dashboard's SQL editor as the first of four in one paste made by
--   scripts/editor_paste.py from the files at 7989077 (this file md5 54fb818c, its part of the paste 116507fc; the
--   paste aa85088d, 137,973 bytes), each file its own transaction once its text's md5 had been checked. The header's
--   version and this footer are the only text added since. Its checks passed inside its transaction; its lineage row
--   (FALSE/FALSE) and its '0781_pre' snapshots carry 17:01:29.826201 UTC (the paste's transactions share its start
--   time, as one editor message). Read back at 17:02:57 UTC (12:02 PM CT): the keys at md5 65c8d535, the kernel's order
--   at 3b03ee4d, the cockpits' queue at 5a66257a, the learning read at bf94627a and the bay line at 7c989348 (the
--   state, simulator, board and decide tick carry 0782's and 0784's changes on top of this file's), each the md5
--   the tests produced on a scratch database from the same paste; `charge_order_exit_first` 1 at the twin depot by
--   Chase (the margin at its default 30). No run was live; not yet seen in a demo run.
