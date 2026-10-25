-- migration-version: APPLIED-NO-LEDGER-ROW
-- migration-name:    the_agents_board_says_where_the_depots_wall_is
--
-- 0783  **The agent's board says where the depot's wall is: each resource's queued work against its units, the hours
--       to clear it, the units idle with a car ready, and the cars whose exit it decides.** (G503)
--       Chase, 2026-10-24: "Dive deep into the agent layer now within OTTO-Q. Make sure we're not missing any edge in
--       our intelligence." The agent proposes and the kernel disposes (rule 10): this is what it reads, nothing more.
--
-- ══ §1 WHY, MEASURED (db/checks/0470 §5) ═══════════════════════════════════════════════════════════════════════════════
--
--   On run 78c0624c the agent was consulted 266 times on 6.01 million prompt tokens. The fifteen most frequent shapes of
--   its directives restate the board's counts (a car past its contract wait, "Capacity finding: N cars wait for N free
--   DCFC", deploy overdue, scout findings), and none names the service bays, which were the depot's wall at 6.9 times
--   their capacity, or what the posts spent on cars the bays would hold. The board's lesson is more_cars_than_chargers
--   and its resources block is pointer counts per stall type: nothing on it compares a resource's queued work with its
--   capacity or says which resource decides each car's exit. The agent restates what it is shown.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) A dial, a person's (rule 10): agent_constraint_board (0..1, default 0).
--   (b) public.ottoq_depot_constraint(run, depot, clock), read-only: per resource (the service bays; the wash bays with
--       the detail work they share; the charging posts), its units up, busy and idle now, idle_with_car_ready, the cars
--       queued for it and the minutes they owe there, the minutes left of the work under way on it, and hours_to_clear
--       (that work over its units, in hours); exit_decided_by, the cars waiting at the depot counted by the resource
--       their exit waits on longest; posts.queued_min_bays_decide, the minutes of charge the line owes to cars whose exit
--       a bay decides; wall, the resource with the most hours to clear; and a one-line lesson. The bays' lines are
--       0781's public.ottoq_bay_line, a car ready for a bay is one that owes no charge (0780's helper), the posts' line
--       is the kernel's own with the kernel's minutes, and the work under way on a post is what is left of its charge on
--       the depot's charge clock. An estimate, stated in its own comment.
--   (c) public.ottoq_agent_board carries it as 'constraint' when grounding is on (agent_board_grounding_enabled, set
--       on every armed run) and the dial is 1. A board without both is unchanged, byte for byte.
--   (d) Not in this file: the agent's prompt (edge-functions/ottoq-orchestrator-agent, v31) reads 'constraint', and the
--       charge-line section says how the kernel orders a car the bays hold (0781). They deploy with the edge function.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 0780 and 0781 applied (their helper and bay line are read); the board is the body this file
--   was written against (md5); nothing it creates exists. Pre-image under '0783_pre'. The anchor matches once. V1 the
--   board less its insertion is its pre-image. V2 the latest twin-depot run's board reads as before at the default. V3
--   with the dial at 1 on that run, in a sub-block that rolls back, the board carries 'constraint' with its three
--   resources and a wall. Executed in full by tests/test_depot_constraint_sql.py.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: the board is not an atom, and at the default it is unchanged.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0783_pre';
--   DROP FUNCTION public.ottoq_depot_constraint(uuid, uuid, timestamptz);
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_constraint_board' (and its policy rows);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0783_the_agents_board_says_where_the_depots_wall_is'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0783 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: 0780 and 0781 applied; the board is the body this file was written against; nothing of this file ──
DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0783_the_agents_board_says_where_the_depots_wall_is') THEN
    RAISE EXCEPTION '0783 P1: already applied';
  END IF;
  IF to_regprocedure('ottoq.ottoq_vehicle_owes_charge_now(uuid,timestamp with time zone)') IS NULL THEN
    RAISE EXCEPTION '0783 P1: 0780 is not applied (ottoq.ottoq_vehicle_owes_charge_now); apply it first';
  END IF;
  IF to_regprocedure('public.ottoq_bay_line(uuid,uuid,timestamp with time zone)') IS NULL THEN
    RAISE EXCEPTION '0783 P1: 0781 is not applied (public.ottoq_bay_line); apply it first';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_agent_board(uuid)'))
     IS DISTINCT FROM 'cc155a31209fd8e89260028d24a9715f' THEN
    RAISE EXCEPTION '0783 P1: the agent''s board is not the body this file patches (md5 cc155a31)';
  END IF;
  IF to_regprocedure('public.ottoq_depot_constraint(uuid,uuid,timestamp with time zone)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_constraint_board') THEN
    RAISE EXCEPTION '0783 P1: the read model or the dial already exists';
  END IF;
END $premises$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0783_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_agent_board(uuid)'::regprocedure;

-- ── V2's before: the latest twin-depot run's board at the default ──
CREATE TEMP TABLE _0783_before ON COMMIT DROP AS
SELECT r.sim_run_id, public.ottoq_agent_board(r.sim_run_id) AS board
  FROM public.ottoq_sim_runs r
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.sim_clock_current IS NOT NULL
 ORDER BY r.started_at DESC NULLS LAST LIMIT 1;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('agent_constraint_board',
        '0783 (G503): 1 = with grounding on, the agent''s board carries ''constraint'' (public.ottoq_depot_constraint): '
        'each resource''s queued work against its units, the hours to clear it, its units idle with a car ready, the '
        'cars whose exit it decides, and which resource is the wall. 0 = the board as before. A person''s dial, never '
        'the agent''s (rule 10).',
        0, 0, 1, 'public.ottoq_agent_board', false);

-- ── (b) the read model ──
CREATE FUNCTION public.ottoq_depot_constraint(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0783 (G503): where the depot's wall is, read as the engine can read it now, for the agent's board. Per resource
   (the service bays; the wash bays with the detail work they share; the charging posts), its units up, busy and idle
   now, the cars queued for it and the minutes of work they owe there, the minutes left of the work under way on it,
   and hours_to_clear: that work over its units, in hours. For the bays the line is public.ottoq_bay_line (0781), a
   car ready for a bay is one that owes no charge (ottoq.ottoq_vehicle_owes_charge_now, 0780), and the work under way
   is each active booking's planned end. For the posts the line is the kernel's own (ottoq_charge_queue_kernel_order),
   each car's minutes are the kernel's (ottoq_charge_order_minutes), and the work under way is what is left of each
   charge on the depot's charge clock (ottoq_charge_clock_remaining).
   exit_decided_by counts the cars waiting at the depot by the resource their exit waits on longest: for a bay, its
   turn and its work there (eta_min + open_min); for the posts, the work ahead of it in the kernel's line and on the
   posts now, over the posts up, and its own minutes. posts.queued_min_bays_decide is the minutes the line owes to cars
   whose exit a bay decides. wall is the resource with the most hours to clear. Read-only; an estimate, stated as one:
   the bays' own order (decide section (4b)) also ranks by urgency, and the cars still to come home are in no line. */
DECLARE
  v_ct jsonb := public.ottoq_charge_clock_model(p_depot_id);
  v_ev jsonb;
  v_bays jsonb; v_exit jsonb; v_res jsonb; v_wall jsonb;
  v_up int; v_down int; v_busy int; v_free int; v_q int; v_qmin numeric; v_prog numeric; v_qbay numeric;
BEGIN
  v_ev := public.ottoq_charge_clock_run_evidence(v_ct, p_sim_run_id, p_clock);

  -- the posts: up and down, free now, and the work under way on them
  SELECT count(*) FILTER (WHERE COALESCE(c.station_state, '') <> 'Faulted'),
         count(*) FILTER (WHERE c.station_state = 'Faulted')
    INTO v_up, v_down
    FROM stalls s LEFT JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc', 'l2');
  SELECT count(*) INTO v_free
    FROM stalls s JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc', 'l2') AND s.current_vehicle_id IS NULL
     AND c.station_state = 'Available'
     AND NOT (s.reserved_by IS NOT NULL AND COALESCE(s.reservation_expires_at, 'infinity'::timestamptz) > p_clock)
     AND NOT EXISTS (SELECT 1 FROM ottoq_stall_bookings b
                      WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                        AND b.state IN ('held', 'active', 'done', 'interrupted') AND b.during @> p_clock);
  SELECT count(*), COALESCE(sum(GREATEST(COALESCE((rm.c ->> 'm')::numeric, 0), 0)), 0)
    INTO v_busy, v_prog
    FROM vehicles cv
    JOIN stalls s ON s.id = cv.current_stall_id
    LEFT JOIN LATERAL (SELECT os.soc_start, os.started_at FROM ocpp_sessions os
                        WHERE os.stall_id = s.id AND os.status = 'active' AND os.vehicle_id = cv.id
                        ORDER BY os.started_at DESC LIMIT 1) ses ON true
    LEFT JOIN LATERAL (SELECT public.ottoq_charge_clock_remaining(
                                v_ct, s.stall_type::text,
                                public.ottoq_charge_clock_who(cv.id, cv.vehicle_class_code, cv.make, cv.model),
                                cv.battery_capacity_kwh, ses.soc_start, cv.current_soc,
                                public.ottoq_effective_target_soc_at(cv.id, p_clock), s.connector_max_kw, cv.inlet_max_kw,
                                extract(epoch FROM (p_clock - ses.started_at)) / 60.0,
                                v_ev -> s.stall_type::text) AS c) rm ON ses.started_at IS NOT NULL
   WHERE cv.home_depot_id = p_depot_id AND cv.current_state::text IN ('charging_dcfc', 'charging_l2');

  -- each waiting car's finish on each resource it owes, the resource its exit waits on longest, and the lines' sums
  WITH fin AS (
    SELECT l.vehicle_id, l.lane AS res, l.eta_min + l.open_min AS finish, l.open_min AS owe_min
      FROM public.ottoq_bay_line(p_sim_run_id, p_depot_id, p_clock) l
    UNION ALL
    SELECT k.vehicle_id, 'posts',
           (v_prog + COALESCE(sum(COALESCE(m.minutes, 0)) OVER (ORDER BY k.kernel_pos
                                                                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0))
             / GREATEST(v_up, 1) + COALESCE(m.minutes, 0),
           COALESCE(m.minutes, 0)
      FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, p_depot_id, p_clock) k
      LEFT JOIN public.ottoq_charge_order_minutes(p_sim_run_id, p_depot_id, p_clock) m ON m.vehicle_id = k.vehicle_id
  ), by_ AS (
    SELECT DISTINCT ON (f.vehicle_id) f.vehicle_id, f.res
      FROM fin f
     ORDER BY f.vehicle_id, f.finish DESC, CASE f.res WHEN 'service_bay' THEN 1 WHEN 'wash_bay' THEN 2 ELSE 3 END
  ), lanes AS (
    SELECT l.lane,
           (SELECT count(*) FROM stalls s WHERE s.depot_id = p_depot_id AND s.stall_type::text = l.lane
                                            AND COALESCE(s.status::text, '') NOT IN ('maintenance', 'closed'))::int AS up,
           (SELECT count(*) FROM vehicles v WHERE v.home_depot_id = p_depot_id
               AND v.current_state::text = ANY (CASE l.lane WHEN 'service_bay' THEN ARRAY['in_service_bay']
                                                            ELSE ARRAY['in_wash_bay', 'in_detail_bay'] END))::int AS busy,
           (SELECT COALESCE(sum(GREATEST(extract(epoch FROM (upper(b.during) - p_clock)) / 60.0, 0)), 0)
              FROM ottoq_stall_bookings b JOIN stalls s ON s.id = b.stall_id
             WHERE b.sim_run_id = p_sim_run_id AND s.depot_id = p_depot_id AND s.stall_type::text = l.lane
               AND b.state = 'active' AND b.during @> p_clock)::numeric AS prog
      FROM (VALUES ('service_bay'), ('wash_bay')) AS l(lane)
  ), bay AS (
    SELECT l.lane, l.up, l.busy, l.prog, count(f.vehicle_id)::int AS q, COALESCE(sum(f.owe_min), 0) AS qmin,
           (count(f.vehicle_id) FILTER (WHERE NOT ottoq.ottoq_vehicle_owes_charge_now(f.vehicle_id, p_clock)))::int AS ready
      FROM lanes l LEFT JOIN fin f ON f.res = l.lane
     GROUP BY l.lane, l.up, l.busy, l.prog
  ), post AS (
    SELECT count(*)::int AS q, COALESCE(sum(f.owe_min), 0) AS qmin,
           COALESCE(sum(f.owe_min) FILTER (WHERE b.res IN ('service_bay', 'wash_bay')), 0) AS qbay
      FROM fin f JOIN by_ b ON b.vehicle_id = f.vehicle_id
     WHERE f.res = 'posts'
  )
  SELECT (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'resource', x.lane, 'units_up', x.up, 'busy_now', x.busy, 'idle_now', GREATEST(x.up - x.busy, 0),
                   'idle_with_car_ready', LEAST(GREATEST(x.up - x.busy, 0), x.ready),
                   'queued_cars', x.q, 'queued_min', round(x.qmin, 0), 'in_progress_min', round(x.prog, 0),
                   'hours_to_clear', round((x.qmin + x.prog) / GREATEST(x.up, 1) / 60.0, 2))
                   ORDER BY x.lane DESC), '[]'::jsonb) FROM bay x),
         (SELECT COALESCE(jsonb_object_agg(z.res, z.n), '{}'::jsonb)
            FROM (SELECT b.res, count(*) AS n FROM by_ b GROUP BY b.res) z),
         p.q, p.qmin, p.qbay
    INTO v_bays, v_exit, v_q, v_qmin, v_qbay
    FROM post p;

  v_res := v_bays || jsonb_build_array(jsonb_build_object(
    'resource', 'posts', 'units_up', v_up, 'units_down', v_down, 'busy_now', v_busy, 'idle_now', v_free,
    'idle_with_car_ready', LEAST(v_free, v_q),
    'queued_cars', v_q, 'queued_min', round(v_qmin, 0), 'in_progress_min', round(v_prog, 0),
    'hours_to_clear', round((v_qmin + v_prog) / GREATEST(v_up, 1) / 60.0, 2),
    'queued_min_bays_decide', round(v_qbay, 0)));
  SELECT r INTO v_wall FROM jsonb_array_elements(v_res) r
   ORDER BY (r ->> 'hours_to_clear')::numeric DESC, r ->> 'resource' LIMIT 1;
  RETURN jsonb_build_object(
    'resources', v_res,
    'wall', v_wall ->> 'resource',
    'exit_decided_by', v_exit,
    'lesson', format('The %s are the wall: %s hours of work queued for %s of them, %s cars waiting.%s',
                     CASE v_wall ->> 'resource' WHEN 'service_bay' THEN 'service bays' WHEN 'wash_bay' THEN 'wash bays'
                                                ELSE 'charging posts' END,
                     v_wall ->> 'hours_to_clear', v_wall ->> 'units_up', v_wall ->> 'queued_cars',
                     CASE WHEN v_wall ->> 'resource' <> 'posts' AND v_qbay > 0
                          THEN format(' %s of the %s minutes of charge the line owes are for cars whose exit a bay decides.',
                                      round(v_qbay, 0), round(v_qmin, 0))
                          ELSE '' END));
END $function$;
REVOKE ALL ON FUNCTION public.ottoq_depot_constraint(uuid, uuid, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_depot_constraint(uuid, uuid, timestamp with time zone) TO service_role;

-- ── (c) the board carries it ──
CREATE TEMP TABLE _0783_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0783_patch VALUES
  (1,
   $o1$
  RETURN v_board;
END;$o1$,
   $n1$
  --: 0783 (G503). THE DEPOT'S CONSTRAINT: each resource's queued work against its units, the hours to clear it, its
  --: units idle with a car ready, the cars whose exit it decides, and which resource is the wall
  --: (ottoq_depot_constraint). Gated on grounding and on agent_constraint_board, so a board without both is unchanged.
  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_board_grounding_enabled',0),0) >= 1
     AND COALESCE(ottoq_policy_get(p_sim_run_id,'agent_constraint_board',0),0) >= 1 THEN
    v_board := v_board || jsonb_build_object('constraint', public.ottoq_depot_constraint(p_sim_run_id, v_depot, v_clock));
  END IF;

  RETURN v_board;
END;$n1$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_agent_board(uuid)'::regprocedure);
  FOR p IN SELECT * FROM _0783_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0783: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_agent_board(uuid)'::regprocedure) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0783: the board is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the board less its insertion is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc WHERE oid = 'public.ottoq_agent_board(uuid)'::regprocedure;
  FOR p IN SELECT * FROM _0783_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'cc155a31209fd8e89260028d24a9715f' THEN
    RAISE EXCEPTION '0783 V1: the board less its insertion is not its pre-image (md5 %)', md5(v_body);
  END IF;
  RAISE NOTICE '0783 V1: the board less its insertion is its pre-image';
END $v1$;

-- ── V2: at the default the latest twin-depot run's board reads as before ──
DO $v2$
DECLARE b record;
BEGIN
  SELECT * INTO b FROM _0783_before;
  IF NOT FOUND THEN
    RAISE NOTICE '0783 V2: no twin-depot run to read; the tests execute it';
    RETURN;
  END IF;
  IF public.ottoq_agent_board(b.sim_run_id) IS DISTINCT FROM b.board THEN
    RAISE EXCEPTION '0783 V2: at the default the board of run % moved', b.sim_run_id;
  END IF;
  RAISE NOTICE '0783 V2: at the default the board of run % reads as before', left(b.sim_run_id::text, 8);
END $v2$;

-- ── V3: with the dial at 1, in a sub-block that rolls back ──
DO $v3$
DECLARE b record; v_c jsonb; v_msg text;
BEGIN
  SELECT * INTO b FROM _0783_before;
  IF NOT FOUND THEN
    RAISE NOTICE '0783 V3: no twin-depot run to read; the tests execute it';
    RETURN;
  END IF;
  BEGIN
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value)
    VALUES ('run', b.sim_run_id, 'agent_constraint_board', 1), ('run', b.sim_run_id, 'agent_board_grounding_enabled', 1)
    ON CONFLICT DO NOTHING;
    v_c := public.ottoq_agent_board(b.sim_run_id) -> 'constraint';
    RAISE EXCEPTION USING ERRCODE = 'P0783', MESSAGE = 'v3 done';
  EXCEPTION WHEN SQLSTATE 'P0783' THEN
    NULL;   -- the dial rows roll back here
  END;
  IF v_c IS NULL OR jsonb_array_length(v_c -> 'resources') <> 3 OR v_c ->> 'wall' IS NULL THEN
    RAISE EXCEPTION '0783 V3: with the dial the board does not carry the constraint: %', v_c;
  END IF;
  RAISE NOTICE '0783 V3: with the dial the board of run % names the wall: % (%)', left(b.sim_run_id::text, 8),
    v_c ->> 'wall', v_c ->> 'lesson';
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0783_the_agents_board_says_where_the_depots_wall_is', false, false,
        'Dial agent_constraint_board (default 0); new public.ottoq_depot_constraint (read-only); one gated insertion in '
        'public.ottoq_agent_board (V1: the board less it is its pre-image; V2: unchanged at the default). The board is '
        'not an atom. No certification arm, canon cell or dial experiment sets the dial.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-25 17:01:29 UTC (12:01 PM CT), no ledger row ═══════════════════════════════════════════════════
--
--   Chase ran this file in the Supabase dashboard's SQL editor as the third of four in one paste made by
--   scripts/editor_paste.py from the files at 7989077 (this file md5 c4487b8d, its part of the paste 6717f7cf; the
--   paste aa85088d, 137,973 bytes), each file its own transaction once its text's md5 had been checked. The header's
--   version and this footer are the only text added since. Its checks passed inside its transaction; its lineage row
--   (FALSE/FALSE) and its '0783_pre' snapshots carry 17:01:29.826201 UTC (the paste's transactions share its start
--   time, as one editor message). Read back at 17:02:57 UTC (12:02 PM CT): the agent's board at 2ca12c61 and the
--   constraint read model at af4cef03, each the md5 the tests produced on a scratch database from the same paste;
--   `agent_constraint_board` left unset, so off: the deployed agent (v30) does not read 'constraint'; it goes on with
--   v31's deploy. No run was live; not yet seen in a demo run.
