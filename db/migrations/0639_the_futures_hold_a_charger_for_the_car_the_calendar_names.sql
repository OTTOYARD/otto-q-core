-- migration-version: PENDING
-- migration-name:    the_futures_hold_a_charger_for_the_car_the_calendar_names
--
-- 0639  **The futures hold a charger for the car the depot's calendar names.**
--       The kernel's check on an agent's charge order rolls the charge line forward and seats the next car on each
--       charger the moment it frees. The kernel does not: its calendar books chargers ahead for named cars (an L2 seat
--       plan books up to four hours ahead; the planners book on arrival), and its assignment gate refuses a charger held
--       for another car to everyone else (ottoq.ottoq_validate_assignment: a live booking by another vehicle covering the
--       moment). The state carried no calendar, so the futures gave held chargers to the wrong cars, and every forecast
--       and every grade inherited the error (G380).
--
-- ══ §1 WHY (measured 2026-10-09 08:55-09:17 UTC, 3:55-4:17 AM CT, on live, read-only) ══════════════════════════════════════
--
--   (a) The check's own replay, given everything that really happened (arrivals, appeared cars, charge times, charges
--       under way, faults), still placed a car's plug-in a mean 12.19 minutes from when it really plugged in on
--       b2efcc07's 87 full-window orders (2,093 compared; 451 plug-ins missed, 576 invented). The error lives with the
--       cars already at the depot at the order: 16.69 minutes (bias -9.41: placed early), against 6.99 for cars that came
--       home inside the window. A third of the compared plug-ins went to the other kind of charger.
--   (b) Not bays (no bay booking between an order and the car's plug-in), not a charger's turnover (a charger is reused a
--       median 0.81 minutes after a fast charge ends, 0.35 after an L2), not the wait bank (it resets off site). The
--       calendar: at sim 13:01 the L2 seat plan booked twelve L2 windows starting 14:01-14:10 for named cars; returning
--       cars got L2 windows booked from 15 minutes ahead; 46 L2 bookings were superseded (booked a mean 75.7 minutes
--       ahead, up to 249) and 31 released (a mean 207 ahead). Car b696f1b8 (86%, staged) was evaluated 30 times between
--       13:21 and 14:28 and refused a charger every time ('no compatible available stall') while 36 charges started,
--       20 of them returning cars seated within two minutes of arriving; the replay had it plugged in 52 minutes earlier.
--   (c) Rehearsed: the same 87 replays with each order's held bookings rebuilt from the calendar's own sim-clock columns
--       (2,393 holds, 1,913 on cars the futures model, 463 on cars they do not), the simulator giving a held charger only
--       to its car: mean miss 12.19 -> 7.34 minutes; cars at the depot 16.69 -> 8.35 (bias -9.41 -> -6.70); cars coming
--       home 6.99 -> 5.95; missed 451 -> 247, invented 576 -> 403; summed miss on the pairs both compared 25,343 -> 16,728.
--       What is left is bays, the stall pick beyond the kind of charger, and the next order taking over.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_charge_line_holds(run, clock, horizon): the charge bookings the run's calendar held at `clock` (its
--       own sim clock) for a named car: each a charger (c), its car (v), and its window in minutes from `clock` (a, from
--       0; b, NULL when open-ended), for a window reaching past `clock` and starting inside the horizon. Held at `clock`:
--       booked by then (booked_at_sim), not yet released by then (released_at, on the sim clock), and not yet a charge under
--       way. Read from the calendar's own sim-clock columns, so a past moment reads as it stood.
--   (b) ottoq_charge_line_state: with the run's new dial agent_charge_order_holds at 1 (its default), the state carries
--       `holds`, (a) at the order. The chargers list and the line are untouched. At 0, 0638's state exactly.
--   (c) ottoq_charge_line_schedule: with `holds`, a charger held for another car is not free to a car inside its window;
--       the car it is held for takes it as any free charger; a car's holds end when it is seated anywhere (the kernel
--       supersedes them); a hold for a car the futures do not model is left out and counted (holds_unmodelled); a hold's
--       end is a moment the line is read again. Totals add holds and holds_unmodelled. Without `holds`, 0638's result,
--       key for key. Every future and both sides of a comparison read the same holds.
--   (d) ottoq_arbiter_self_assessment_v3: the simulator area no longer lists holds among what it does not model, and
--       says how many of the graded orders were made before it did; ottoq_arbiter_self_assessment, whose numbers v3
--       reads, no longer lists them in its own area either.
--   The realizer is untouched: it carries the state's holds into the hindsight replay as they stood at the order.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, no run running. P1 0638 is applied, the four bodies are the ones 0637 left (state 76674570,
--   simulator 43aeb832, self-review 3137c23d, its numbers' reader 0a061641), and the objects are new. V1 the simulator by meaning on a two-car line. V2 without `holds`, the
--   simulator is 0638's, key for key, on the latest stored states (both sides, futures 0 and 3). V3 the state at the
--   latest order of the latest run with 20 stored orders carries the calendar's holds as they stood then. V4 the replay
--   with and without the calendar's holds on the latest 40 graded full-window orders of the latest run with 20, rebuilt
--   by (a) at each order's clock. Executed by tests/test_agent_holds_sql.py on the miniature depot.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE, as 0619-0638: the state and the simulator are read by the check on
--   an agent's charge order, its futures and the grader; no kernel decision, seat or certification arm reads them. The
--   dial is a person's (agent_charge_order_holds, 1; 0 is 0638's check exactly), never the agent's (rule 10).
--
-- ROLLBACK: set agent_charge_order_holds to 0 on the runs that should not see it (0638's state, exactly), or EXECUTE each
--   `definition` in ottoq_schema_snapshots WHERE label = '0639_pre' AND object_kind = 'function'; then DROP FUNCTION
--   public.ottoq_charge_line_holds(uuid, timestamptz, numeric); DELETE FROM public.ottoq_policy_param_catalog WHERE
--   param_key = 'agent_charge_order_holds'; DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0639_the_futures_hold_a_charger_for_the_car_the_calendar_names'.

BEGIN;

-- ── P0: nothing in flight, no run running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0639 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0639 P0: a run is running; its check reads the state and the simulator this changes. Apply between runs';
  END IF;
END $inflight$;

-- ── P1: the bodies are the ones 0637 left; the objects are new ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)',                  '7667457088d0fcdc9aef7ae14811b6f1'),
    ('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)',                  '43aeb8327b239d1ddc7332c947f55907'),
    ('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)',       '3137c23df9e90c7380e642b75ca87134'),
    ('public.ottoq_arbiter_self_assessment(uuid,timestamp with time zone)',                  '0a0616418c2fe288ac1b20e92cf7c602'))
    AS t(sig, src_md5)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)) IS DISTINCT FROM r.src_md5 THEN
      RAISE EXCEPTION '0639 P1: % is not the body measured (md5 %); read it again', r.sig, left(r.src_md5, 8);
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0638_the_self_review_remembers_what_it_found') THEN
    RAISE EXCEPTION '0639 P1: 0638 is not applied; apply 0630-0638 first';
  END IF;
  IF to_regprocedure('public.ottoq_charge_line_holds(uuid,timestamp with time zone,numeric)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_holds')
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0639_the_futures_hold_a_charger_for_the_car_the_calendar_names') THEN
    RAISE EXCEPTION '0639 P1: already applied';
  END IF;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0639_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure,
                 'public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)'::regprocedure,
                 'public.ottoq_arbiter_self_assessment(uuid,timestamp with time zone)'::regprocedure);

-- what V2 compares against: the simulator as it stood, on the latest stored states, both sides, futures 0 and 3
CREATE TEMP TABLE _0639_pre ON COMMIT DROP AS
SELECT s.order_id, x.k, x.side,
       public.ottoq_charge_line_schedule(s.state, CASE WHEN x.side = 'agent' THEN s.agent_order END, x.k, s.seed, true) AS out
  FROM (SELECT * FROM public.ottoq_charge_order_snapshots WHERE depot_id = '11111111-1111-1111-1111-111111111111'
         ORDER BY order_id DESC LIMIT 8) s
  CROSS JOIN (VALUES (0, 'kernel'), (0, 'agent'), (3, 'kernel'), (3, 'agent')) x(k, side);

-- ══ the dial ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, agent_writable, affects, description)
VALUES ('agent_charge_order_holds', 0, 1, 1, false,
  'ottoq_charge_line_state, ottoq_charge_line_schedule (0639 the calendar''s holds)',
  '0639: whether the kernel''s check on an agent''s charge order reads the charge bookings the depot''s calendar holds for '
  'named cars (ottoq_charge_line_holds) and gives a held charger to no other car inside its window, as the kernel''s '
  'assignment gate does. 1 reads them; 0 is 0638''s check exactly. A person''s dial, never the agent''s (rule 10).');

-- ══ (a) the holds ═════════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_line_holds(p_sim_run_id uuid, p_clock timestamptz, p_horizon_min numeric DEFAULT 480)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0639: the charge bookings the run's calendar held at p_clock (its own sim clock) for a named car: each a charger (c),
  -- its car (v), and its window in minutes from p_clock (a, from 0; b, NULL when open-ended), for a window reaching past
  -- p_clock and starting inside the horizon. Held at p_clock: booked by then, not yet released by then, and not yet a
  -- charge under way. Read from the calendar's own sim-clock columns (booked_at_sim, released_at), so a past moment
  -- reads as it stood.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'c', b.stall_id, 'v', b.vehicle_id,
           'a', round(GREATEST(extract(epoch FROM (lower(b.during) - p_clock)) / 60.0, 0)::numeric, 2),
           'b', CASE WHEN upper_inf(b.during) THEN NULL
                     ELSE round((extract(epoch FROM (upper(b.during) - p_clock)) / 60.0)::numeric, 2) END)
         ORDER BY lower(b.during), b.stall_id, b.vehicle_id, b.booking_id), '[]'::jsonb)
    FROM public.ottoq_stall_bookings b
   WHERE b.sim_run_id = p_sim_run_id AND b.purpose IN ('charge_l2', 'charge_dcfc')
     AND COALESCE(b.booked_at_sim, '-infinity'::timestamptz) <= p_clock
     AND COALESCE(b.released_at, 'infinity'::timestamptz) > p_clock
     AND COALESCE(upper(b.during), 'infinity'::timestamptz) > p_clock
     AND lower(b.during) < p_clock + make_interval(secs => (COALESCE(p_horizon_min, 480) * 60)::double precision)
     AND (b.state IN ('held', 'superseded', 'released') OR lower(b.during) > p_clock)
$fn$;
COMMENT ON FUNCTION public.ottoq_charge_line_holds(uuid, timestamptz, numeric) IS
'0639. The charge bookings a run''s calendar held at p_clock (its own sim clock) for a named car, as the kernel''s check reads them: [{c: charger (stall id), v: car, a: from (minutes from p_clock, 0 at the earliest), b: until (NULL when open-ended)}], for a window reaching past p_clock and starting within the horizon. Held at p_clock: booked by then (booked_at_sim), not released by then (released_at, sim clock), not yet a charge under way. The state carries it (agent_charge_order_holds); the simulator gives a held charger to no other car inside its window, as ottoq.ottoq_validate_assignment refuses it. Read-only.';
GRANT EXECUTE ON FUNCTION public.ottoq_charge_line_holds(uuid, timestamptz, numeric) TO authenticated, service_role;

-- ══ (b) (c) (d) the anchored patches: each anchor once, the stored definition after ══════════════════════════════════════
CREATE TEMP TABLE _0639_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;

INSERT INTO _0639_patch VALUES
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 1,
$old$Without the block, 0634's result, key for
   key. */$old$,
$new$Without the block, 0634's result, key for
   key.
   0639: with a `holds` list (ottoq_charge_line_state, the run's agent_charge_order_holds dial at 1), a charger the
   depot's calendar holds for a named car (c, the car v, from a to b minutes) is not free to any other car inside its
   window, as the kernel's assignment gate refuses it (ottoq.ottoq_validate_assignment); the car it is held for takes
   it as any free charger. A car's holds end when it is seated anywhere (the kernel supersedes them), a hold for a car
   the futures do not model is left out and counted (holds_unmodelled), and a hold's end is a moment the line is read
   again. Totals add holds and holds_unmodelled. Without the list, 0638's result, key for key. */$new$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 2,
$old$  s_n int[] := '{}'; v_tf float8; v_rp float8;
$old$,
$new$  s_n int[] := '{}'; v_tf float8; v_rp float8;
  -- 0639: the chargers the calendar holds for a named car
  h_j int[] := '{}'; h_v text[] := '{}'; h_a float8[] := '{}'; h_b float8[] := '{}'; h_off boolean[] := '{}';
  nh int := 0; h_un int := 0; s_h0 int[]; s_h1 int[]; v_held boolean; v_hb float8;
$new$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 3,
$old$  -- 0623: the cars charged and still parked leave from now, on what is left of their dwell
$old$,
$new$  -- 0639: the chargers the depot's calendar holds for a named car (the state's `holds`, ottoq_charge_line_state): from
  -- a to b minutes no other car takes one, as the kernel's assignment gate refuses it (ottoq.ottoq_validate_assignment);
  -- a hold for a car the futures do not model is left out and counted, and a car's holds end when it is seated
  IF jsonb_typeof(p_state -> 'holds') = 'array' AND m > 0 THEN
    FOR e IN SELECT x.value FROM jsonb_array_elements(p_state -> 'holds') WITH ORDINALITY x(value, o) ORDER BY x.o LOOP
      j := array_position(s_id, e ->> 'c');
      CONTINUE WHEN j IS NULL OR (e ->> 'v') IS NULL;
      IF array_position(c_id, e ->> 'v') IS NULL THEN h_un := h_un + 1; CONTINUE; END IF;
      nh := nh + 1; h_j[nh] := j; h_v[nh] := e ->> 'v';
      h_a[nh] := GREATEST(COALESCE((e ->> 'a')::float8, 0), 0);
      h_b[nh] := GREATEST(COALESCE((e ->> 'b')::float8, v_hor + 1), h_a[nh]);
    END LOOP;
    IF nh > 0 THEN
      -- indexed by charger: each charger's holds are h_j's run s_h0 .. s_h1
      SELECT array_agg(u.j ORDER BY u.j, u.k), array_agg(u.v ORDER BY u.j, u.k), array_agg(u.a ORDER BY u.j, u.k),
             array_agg(u.b ORDER BY u.j, u.k)
        INTO h_j, h_v, h_a, h_b
        FROM unnest(h_j, h_v, h_a, h_b) WITH ORDINALITY AS u(j, v, a, b, k);
      h_off := array_fill(false, ARRAY[nh]);
      s_h0 := array_fill(1, ARRAY[m]); s_h1 := array_fill(0, ARRAY[m]);
      FOR q IN 1 .. nh LOOP
        IF s_h1[h_j[q]] < s_h0[h_j[q]] THEN s_h0[h_j[q]] := q; END IF;
        s_h1[h_j[q]] := q;
      END LOOP;
    END IF;
  END IF;

  -- 0623: the cars charged and still parked leave from now, on what is left of their dwell
$new$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 4,
$old$        CONTINUE WHEN s_free[j] > t;
$old$,
$new$        CONTINUE WHEN s_free[j] > t;
        IF nh > 0 AND s_h1[j] >= s_h0[j] THEN                                                    -- 0639
          v_held := false;
          FOR q IN s_h0[j] .. s_h1[j] LOOP
            IF NOT h_off[q] AND h_a[q] <= t AND t < h_b[q] AND h_v[q] <> c_id[i] THEN v_held := true; EXIT; END IF;
          END LOOP;
          CONTINUE WHEN v_held;
        END IF;
$new$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 5,
$old$      c_start[i] := t; c_ready[i] := t + v_dur; c_kind[i] := s_k[best];
$old$,
$new$      c_start[i] := t; c_ready[i] := t + v_dur; c_kind[i] := s_k[best];
      IF nh > 0 THEN                                                                             -- 0639: its holds end
        FOR q IN 1 .. nh LOOP
          IF h_v[q] = c_id[i] THEN h_off[q] := true; END IF;
        END LOOP;
      END IF;
$new$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 6,
$old$      t_next := LEAST(t_c, t_a, v_dn);
$old$,
$new$      v_hb := NULL;                                                                              -- 0639: a hold ending
      IF nh > 0 THEN
        SELECT min(u.b) INTO v_hb FROM unnest(h_b, h_off) AS u(b, off) WHERE NOT u.off AND u.b > t;
      END IF;
      t_next := LEAST(t_c, t_a, v_dn, v_hb);
$new$),
('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 7,
$old$    v_out := v_out || jsonb_build_object('faults_drawn', f_n, 'requeued', f_rq);
  END IF;
$old$,
$new$    v_out := v_out || jsonb_build_object('faults_drawn', f_n, 'requeued', f_rq);
  END IF;
  IF jsonb_typeof(p_state -> 'holds') = 'array' THEN                                               -- 0639
    v_out := v_out || jsonb_build_object('holds', nh, 'holds_unmodelled', h_un);
  END IF;
$new$),
('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 8,
$old$0634's state exactly. */$old$,
$new$0634's state exactly.
   0639: with the run's agent_charge_order_holds dial at 1 (its default), the state carries `holds`: the charge bookings
   the depot's calendar held at p_clock for a named car (ottoq_charge_line_holds), which the simulator gives to no
   other car inside their windows. The chargers list and the line are untouched. With the dial at 0, 0638's state
   exactly. */$new$),
('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 9,
$old$  RETURN v_state;
$old$,
$new$  -- 0639: the chargers the depot's calendar holds for a named car, unless a person has turned it off for this run
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_holds', 1), 1) >= 1 THEN
    v_state := v_state || jsonb_build_object('holds', public.ottoq_charge_line_holds(p_sim_run_id, p_clock, c_horizon));
  END IF;
  RETURN v_state;
$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 10,
$old$ it invented. It does not model bays, holds, the stall pick beyond the kind of charger, or the next '
                 || 'order taking over, and no forecast can remove that error.',$old$,
$new$ it invented. It does not model bays, the stall pick beyond the kind of charger, or the next order '
                 || 'taking over'
                 -- 0639: holds are modelled now; an order whose state carried none was made before they were
                 || COALESCE((SELECT CASE WHEN count(*) > 0
                                          THEN '; and ' || count(*) || ' of the orders graded here were made before it held a '
                                               || 'charger for the car the depot''s calendar names' END
                                FROM public.ottoq_charge_order_grades h0
                                JOIN public.ottoq_charge_order_snapshots s0 ON s0.order_id = h0.order_id
                               WHERE h0.depot_id IS NOT DISTINCT FROM p_depot_id AND h0.graded_at >= p_since
                                 AND NOT (s0.state ? 'holds')), '')
                 || ', and no forecast can remove that error.',$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 11,
$old$'action', 'Measure which of the four costs the most, then model that one in the check''s simulator.',$old$,
$new$'action', 'Measure which of the three costs the most, then model that one in the check''s simulator.',$new$),
('public.ottoq_arbiter_self_assessment(uuid,timestamp with time zone)', 12,
$old$It does not model bays, holds, the stall pick beyond the kind, '$old$,
$new$It does not model bays, the stall pick beyond the kind, '$new$);

DO $patch$
DECLARE f record; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0639_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0639_patch WHERE fn = f.fn ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0639 %: anchor % matches % times, not 1', f.fn, p.seq, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(to_regprocedure(f.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0639 %: not stored as patched', f.fn;
    END IF;
  END LOOP;
END $patch$;

-- ══ V1: the simulator by meaning, on a line of two cars and one L2 ═══════════════════════════════════════════════════════
--   a waits longer (ratio 2, a 20-minute charge), b less (ratio 1, a 60-minute charge); one L2 free at 0
DO $v1$
DECLARE
  c_line constant jsonb := jsonb_build_object('ttl_min', 0, 'pin_min', 90, 'horizon_min', 480, 'inbound', '[]'::jsonb,
    'chargers', jsonb_build_array(jsonb_build_object('id', 'l', 'k', 'l2', 'free', 0)),
    'cars', jsonb_build_array(
      jsonb_build_object('id', 'a', 'w', 40, 'g', 40, 'imm', false, 'soc', 60, 'md', 20, 'ml', 20, 'sd', 0, 'sl', 0),
      jsonb_build_object('id', 'b', 'w', 0, 'g', 40, 'imm', false, 'soc', 60, 'md', 60, 'ml', 60, 'sd', 0, 'sl', 0)));
  -- b's battery is low (it wants a fast charger) and it waits longest; a fast charger and an L2 free at 0
  c_two constant jsonb := jsonb_build_object('ttl_min', 0, 'pin_min', 90, 'horizon_min', 480, 'inbound', '[]'::jsonb,
    'chargers', jsonb_build_array(jsonb_build_object('id', 'f', 'k', 'dcfc', 'free', 0),
                                  jsonb_build_object('id', 'l', 'k', 'l2', 'free', 0)),
    'cars', jsonb_build_array(
      jsonb_build_object('id', 'b', 'w', 40, 'g', 40, 'imm', false, 'soc', 30, 'md', 20, 'ml', 60, 'sd', 0, 'sl', 0),
      jsonb_build_object('id', 'a', 'w', 0, 'g', 40, 'imm', false, 'soc', 60, 'md', 30, 'ml', 20, 'sd', 0, 'sl', 0)));
  -- c cannot use an L2; the one L2 is held for it until minute 30
  c_none constant jsonb := jsonb_build_object('ttl_min', 0, 'pin_min', 90, 'horizon_min', 480, 'inbound', '[]'::jsonb,
    'chargers', jsonb_build_array(jsonb_build_object('id', 'l', 'k', 'l2', 'free', 0)),
    'cars', jsonb_build_array(
      jsonb_build_object('id', 'a', 'w', 40, 'g', 40, 'imm', false, 'soc', 60, 'md', 20, 'ml', 20, 'sd', 0, 'sl', 0),
      jsonb_build_object('id', 'c', 'w', 0, 'g', 40, 'imm', false, 'soc', 60, 'md', 30, 'ml', 30, 'sd', 0, 'sl', 0,
                         'lok', false)));
  v0 jsonb; v jsonb; s jsonb; v_bad text := '';
BEGIN
  v0 := public.ottoq_charge_line_schedule(c_line, NULL, 0, 'v1', true);
  s := (SELECT jsonb_object_agg(y.value ->> 'id', (y.value ->> 's0')::numeric) FROM jsonb_array_elements(v0 -> 'seats') y);
  IF s <> '{"a": 0, "b": 20}'::jsonb OR v0 ? 'holds' THEN v_bad := v_bad || ' no holds: ' || s::text; END IF;
  -- a hold for b covering the moment: b takes the L2, a waits for b's charge
  v := public.ottoq_charge_line_schedule(c_line || '{"holds": [{"c": "l", "v": "b", "a": 0, "b": 100}]}'::jsonb, NULL, 0, 'v1', true);
  s := (SELECT jsonb_object_agg(y.value ->> 'id', (y.value ->> 's0')::numeric) FROM jsonb_array_elements(v -> 'seats') y);
  IF s <> '{"a": 60, "b": 0}'::jsonb OR (v ->> 'holds')::int <> 1 OR (v ->> 'holds_unmodelled')::int <> 0 THEN
    v_bad := v_bad || ' held from 0: ' || s::text;
  END IF;
  -- a hold for b from minute 5: at 0 it covers nothing, so a takes the L2; b takes it when a's charge ends
  v := public.ottoq_charge_line_schedule(c_line || '{"holds": [{"c": "l", "v": "b", "a": 5, "b": 100}]}'::jsonb, NULL, 0, 'v1', true);
  s := (SELECT jsonb_object_agg(y.value ->> 'id', (y.value ->> 's0')::numeric) FROM jsonb_array_elements(v -> 'seats') y);
  IF s <> '{"a": 0, "b": 20}'::jsonb THEN v_bad := v_bad || ' held from 5: ' || s::text; END IF;
  -- a hold for a car the futures do not model: left out and counted
  v := public.ottoq_charge_line_schedule(c_line || '{"holds": [{"c": "l", "v": "z", "a": 0, "b": 100}]}'::jsonb, NULL, 0, 'v1', true);
  IF v - 'holds' - 'holds_unmodelled' IS DISTINCT FROM v0 OR (v ->> 'holds')::int <> 0 OR (v ->> 'holds_unmodelled')::int <> 1 THEN
    v_bad := v_bad || ' unmodelled: ' || (v - 'seats')::text;
  END IF;
  -- a car takes its own
  v := public.ottoq_charge_line_schedule(c_line || '{"holds": [{"c": "l", "v": "a", "a": 0, "b": 100}]}'::jsonb, NULL, 0, 'v1', true);
  IF v - 'holds' - 'holds_unmodelled' IS DISTINCT FROM v0 OR (v ->> 'holds')::int <> 1 THEN
    v_bad := v_bad || ' its own: ' || (v - 'seats')::text;
  END IF;
  -- an empty list: the line without one, plus its counts
  v := public.ottoq_charge_line_schedule(c_line || '{"holds": []}'::jsonb, NULL, 0, 'v1', true);
  IF v IS DISTINCT FROM v0 || '{"holds": 0, "holds_unmodelled": 0}'::jsonb THEN v_bad := v_bad || ' empty: ' || (v - 'seats')::text; END IF;
  -- b is seated on the fast charger at 0, so its hold on the L2 ends with it and a takes the L2 at 0 (not the fast
  -- charger at 20)
  v := public.ottoq_charge_line_schedule(c_two || '{"holds": [{"c": "l", "v": "b", "a": 0, "b": 100}]}'::jsonb, NULL, 0, 'v1', true);
  s := (SELECT jsonb_object_agg(y.value ->> 'id', jsonb_build_array((y.value ->> 's0')::numeric, y.value ->> 'k0'))
          FROM jsonb_array_elements(v -> 'seats') y);
  IF s <> '{"a": [0, "l2"], "b": [0, "dcfc"]}'::jsonb THEN v_bad := v_bad || ' seated elsewhere: ' || s::text; END IF;
  -- the L2 is held for c, which cannot use it: a takes it when the hold ends, a moment the line is read again
  v := public.ottoq_charge_line_schedule(c_none || '{"holds": [{"c": "l", "v": "c", "a": 0, "b": 30}]}'::jsonb, NULL, 0, 'v1', true);
  s := (SELECT jsonb_object_agg(y.value ->> 'id', (y.value ->> 's0')::numeric) FROM jsonb_array_elements(v -> 'seats') y);
  IF s <> '{"a": 30, "c": null}'::jsonb THEN v_bad := v_bad || ' hold end: ' || s::text; END IF;
  IF v_bad <> '' THEN
    RAISE EXCEPTION '0639 V1: the simulator does not read holds as meant:%', v_bad;
  END IF;
  IF strpos(pg_get_functiondef('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure),
            '''agent_charge_order_holds'', 1), 1) >= 1') = 0 THEN
    RAISE EXCEPTION '0639 V1: the state does not read the dial';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_holds'
                    AND default_value = 1 AND NOT agent_writable) THEN
    RAISE EXCEPTION '0639 V1: the dial is not catalogued as a person''s, default 1';
  END IF;
  RAISE NOTICE '0639 V1: one L2 and two cars: no hold, a 0 and b 20; held for b, b 0 and a 60; held for b from minute 5, a 0 and b 20; held for a car not in the line, counted and left out; held for a, as without; an empty list, as without plus its counts; b seated on the fast charger frees its L2 hold at once (a 0 on the L2); held for a car that cannot use it, a at the hold''s end (30); the state and the dial as meant';
END $v1$;

-- ══ V2: without `holds`, the simulator is 0638's, key for key ═════════════════════════════════════════════════════════════
DO $v2$
DECLARE v_n int; v_diff int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE public.ottoq_charge_line_schedule(s.state, CASE WHEN p.side = 'agent' THEN s.agent_order END,
                                                                            p.k, s.seed, true) IS DISTINCT FROM p.out)
    INTO v_n, v_diff
    FROM _0639_pre p JOIN public.ottoq_charge_order_snapshots s ON s.order_id = p.order_id;
  IF v_diff > 0 THEN
    RAISE EXCEPTION '0639 V2: % of % stored simulations changed without a holds list', v_diff, v_n;
  END IF;
  RAISE NOTICE '0639 V2: % stored simulations (% states x both sides x futures 0 and 3) unchanged', v_n, v_n / 4;
END $v2$;

-- ══ V3: the state at the latest stored order carries the calendar's holds as they stood ════════════════════════════════
DO $v3$
DECLARE
  c_twin constant uuid := '11111111-1111-1111-1111-111111111111';
  s record; v_st jsonb; v_h jsonb; v_t timestamptz;
BEGIN
  -- the latest order of the latest run with 20 stored orders (a short run's calendar may hold nothing), else the latest
  SELECT sn.order_id, sn.sim_run_id, sn.sim_clock, sn.seed INTO s FROM public.ottoq_charge_order_snapshots sn
   WHERE sn.depot_id = c_twin
   ORDER BY (SELECT count(*) FROM public.ottoq_charge_order_snapshots x WHERE x.sim_run_id = sn.sim_run_id) >= 20 DESC,
            sn.order_id DESC
   LIMIT 1;
  IF s.order_id IS NULL THEN
    RAISE NOTICE '0639 V3: no stored order; the state is executed by the tests';
    RETURN;
  END IF;
  v_t := clock_timestamp();
  v_st := public.ottoq_charge_line_state(s.sim_run_id, c_twin, s.sim_clock);
  v_h := public.ottoq_charge_line_holds(s.sim_run_id, s.sim_clock, 480);
  IF v_st -> 'holds' IS DISTINCT FROM v_h THEN
    RAISE EXCEPTION '0639 V3: the state at order % carries % holds, the calendar %', s.order_id,
      jsonb_array_length(COALESCE(v_st -> 'holds', '[]'::jsonb)), jsonb_array_length(v_h);
  END IF;
  RAISE NOTICE '0639 V3: the state at order % (run %, sim %) in % s carries the % charge bookings the calendar held then for named cars (% on L2s)',
    s.order_id, left(s.sim_run_id::text, 8), to_char(s.sim_clock, 'HH24:MI'),
    round(extract(epoch FROM clock_timestamp() - v_t)::numeric, 2), jsonb_array_length(v_h),
    (SELECT count(*) FROM jsonb_array_elements(v_h) x JOIN public.stalls st ON st.id = (x.value ->> 'c')::uuid
      WHERE st.stall_type::text = 'l2');
END $v3$;

-- ══ V4: the replay given what happened, with and without the calendar's holds ═══════════════════════════════════════════
DO $v4$
DECLARE
  c_twin constant uuid := '11111111-1111-1111-1111-111111111111';
  g record; m record; v_t timestamptz := clock_timestamp();
BEGIN
  SELECT x.run INTO g
    FROM (SELECT h.sim_run_id AS run, max(h.order_id) AS last
            FROM public.ottoq_charge_order_grades h
           WHERE h.depot_id = c_twin AND h.observed_min >= h.window_min - 1
           GROUP BY h.sim_run_id
          HAVING count(*) >= 20
           ORDER BY max(h.order_id) DESC LIMIT 1) x;
  IF g.run IS NULL THEN
    RAISE NOTICE '0639 V4: no run has 20 graded full-window orders; the replay is executed by the tests';
    RETURN;
  END IF;
  WITH ord AS (
    SELECT s.order_id, s.sim_clock, s.state, s.seed, s.agent_order, h.taken, h.realized
      FROM public.ottoq_charge_order_grades h
      JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
     WHERE h.sim_run_id = g.run AND h.depot_id = c_twin AND h.observed_min >= h.window_min - 1
     ORDER BY h.order_id DESC LIMIT 40
  ), rep AS (
    SELECT o.order_id, o.realized,
           public.ottoq_charge_line_schedule(f.full - 'holds', CASE WHEN o.taken THEN o.agent_order END, 0, o.seed, true) AS r0,
           public.ottoq_charge_line_schedule((f.full - 'holds')
                                               || jsonb_build_object('holds', public.ottoq_charge_line_holds(g.run, o.sim_clock, 480)),
                                             CASE WHEN o.taken THEN o.agent_order END, 0, o.seed, true) AS r1
      FROM ord o
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_line_realize(o.state, o.realized,
                                   ARRAY['arrivals', 'appeared', 'charge_times', 'running', 'faults']) AS full) f
  ), act AS (
    SELECT r.order_id, c.key AS id, (c.value ->> 's0')::numeric AS s0, (r.realized ->> 'observed_min')::numeric AS w,
           'depot' AS src
      FROM rep r, jsonb_each(COALESCE(r.realized -> 'cars', '{}'::jsonb)) c
    UNION ALL
    SELECT r.order_id, c.key, (c.value ->> 's0')::numeric, (r.realized ->> 'observed_min')::numeric, 'inbound'
      FROM rep r, jsonb_each(COALESCE(r.realized -> 'inbound', '{}'::jsonb)) c
     WHERE COALESCE((c.value ->> 'arrived')::boolean, false)
    UNION ALL
    SELECT r.order_id, x.value ->> 'id', (x.value ->> 's0')::numeric, (r.realized ->> 'observed_min')::numeric, 'inbound'
      FROM rep r, jsonb_array_elements(COALESCE(r.realized -> 'appeared', '[]'::jsonb)) x WHERE x.value ->> 'how' = 'returned'
  ), j AS (
    SELECT a.src, a.s0 AS act,
           (SELECT CASE WHEN (y.value ->> 's0')::numeric < a.w THEN (y.value ->> 's0')::numeric END
              FROM rep r, jsonb_array_elements(r.r0 -> 'seats') y
             WHERE r.order_id = a.order_id AND y.value ->> 'id' = a.id LIMIT 1) AS p0,
           (SELECT CASE WHEN (y.value ->> 's0')::numeric < a.w THEN (y.value ->> 's0')::numeric END
              FROM rep r, jsonb_array_elements(r.r1 -> 'seats') y
             WHERE r.order_id = a.order_id AND y.value ->> 'id' = a.id LIMIT 1) AS p1
      FROM act a
  )
  SELECT (SELECT count(*) FROM rep) AS orders,
         round(avg(abs(p0 - act)) FILTER (WHERE act IS NOT NULL AND p0 IS NOT NULL), 2) AS mae0,
         round(avg(abs(p1 - act)) FILTER (WHERE act IS NOT NULL AND p1 IS NOT NULL), 2) AS mae1,
         round(avg(abs(p0 - act)) FILTER (WHERE src = 'depot' AND act IS NOT NULL AND p0 IS NOT NULL), 2) AS dep0,
         round(avg(abs(p1 - act)) FILTER (WHERE src = 'depot' AND act IS NOT NULL AND p1 IS NOT NULL), 2) AS dep1,
         round(avg(abs(p0 - act)) FILTER (WHERE src = 'inbound' AND act IS NOT NULL AND p0 IS NOT NULL), 2) AS inb0,
         round(avg(abs(p1 - act)) FILTER (WHERE src = 'inbound' AND act IS NOT NULL AND p1 IS NOT NULL), 2) AS inb1,
         count(*) FILTER (WHERE act IS NOT NULL AND p0 IS NOT NULL) AS both0,
         count(*) FILTER (WHERE act IS NOT NULL AND p1 IS NOT NULL) AS both1,
         count(*) FILTER (WHERE act IS NOT NULL AND p0 IS NULL) AS missed0,
         count(*) FILTER (WHERE act IS NOT NULL AND p1 IS NULL) AS missed1,
         count(*) FILTER (WHERE act IS NULL AND p0 IS NOT NULL) AS invented0,
         count(*) FILTER (WHERE act IS NULL AND p1 IS NOT NULL) AS invented1,
         (SELECT sum((r1 ->> 'holds')::int) FROM rep) AS holds,
         (SELECT sum((r1 ->> 'holds_unmodelled')::int) FROM rep) AS unmodelled
    INTO m FROM j;
  RAISE NOTICE '0639 V4: run % (its latest % full-window graded orders, % s): the replay given what happened placed a plug-in a mean % minutes from the real one without the calendar''s holds and % with them (cars at the depot % -> %, cars coming home % -> %); compared % -> %, missed % -> %, invented % -> %; % holds read, % on cars the futures do not model',
    left(g.run::text, 8), m.orders, round(extract(epoch FROM clock_timestamp() - v_t)::numeric, 1),
    m.mae0, m.mae1, m.dep0, m.dep1, m.inb0, m.inb1, m.both0, m.both1, m.missed0, m.missed1, m.invented0, m.invented1,
    m.holds, m.unmodelled;
END $v4$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0639_the_futures_hold_a_charger_for_the_car_the_calendar_names', false, false,
  'ottoq_charge_line_holds reads the charge bookings a run''s calendar held at a moment for a named car, from its own '
  'sim-clock columns; the charge line''s state carries them behind the person''s dial agent_charge_order_holds (1; 0 is '
  '0638''s check); the simulator gives a held charger to no other car inside its window, as the kernel''s assignment gate '
  'refuses it, ends a car''s holds when it is seated, counts a hold for a car it does not model and reads a hold''s end as '
  'a moment; the self-review no longer lists holds among what the simulator does not model. FALSE/FALSE as 0619-0638: '
  'read by the check on an agent''s charge order, its futures and the grader; no kernel decision, dial or seat reads them, '
  'and no certification arm runs the agent or the charge order.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
