-- migration-version: 20260926161853
-- migration-name:    the_refusal_reactor_leaves_a_car_the_decide_path_has_already_replanned
--
-- 0490  **The refusal reactor leaves a car the decide path has already re-planned (G225).** A refused command from
--       an earlier tick was rerouted after the decide path had given the car a newer command, so one car held two
--       plans and was sent to a second stall.
--
-- ══ §1 WHAT WAS WRONG (measured 2026-09-26) ════════════════════════════════════════════════════════════════════
--
--   `ottoq.ottoq_react_to_refusals` walks every refused, unreacted command (oldest first, 20 per tick) and, for a
--   `target_occupied` or `resource_faulted` refusal of `proceed_to_stall`, `begin_charge` or `stage`, books a free
--   stall of the same type and emits a new command to it. It never asks whether the car still wants what the old
--   command asked for.
--
--   Found while reading G224's tie (0489). Busy_day/171717/48, arm A of verdict 364, car a1111111-...-0001:
--     22:30  proceed_to_stall to L2 fbb3a3df, refused (target_occupied)
--     23:00  the decide path re-plans the car: begin_charge on DCFC 3a7310ac, with a booking 23:00-23:48
--     23:00  the reactor reroutes the 22:30 refusal anyway: L2 fe18413d booked 23:00-00:00, proceed_to_stall to it
--     23:30  the car drives to the L2 and does not charge there
--     00:00  the car moves to the DCFC and charges, 00:00-00:30
--   One extra move, an L2 charger held for an hour for a car that never charged on it, and two `done` charge
--   bookings starting at the same instant (the tie 0489 fixes in the completion probe).
--
--   Counted on the current engine: a reroute of a refusal whose car already held a command from a later tick
--     canon arms under 0487 (verdicts 358-364):  1, 3, 1, 1, 3, 6 per arm with reroutes (6 of 48 on the 48-tick column)
--     dial-experiment arms today:                 0-2 per arm
--     today's three demo runs after G204:         0
--   The other shape of one car sent to two stalls, two reroutes in one pass, was mostly G204's duplicate commands
--   (fixed by 0472). The 6 left after 0472 (dial arms at 09:00 and 09:20 UTC, one cert pair at 13:25) are this
--   finding again: the car's refusal from the tick before and its refusal from this tick, both rerouted in one pass.
--   Under this change the older one is superseded by the newer command, so they go too. (0365 §3(c))
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   Before a reroutable refusal is rerouted, the reactor looks for a command to the same car issued in a LATER tick.
--   If one exists, that command is the car's plan: the refusal is marked reacted with
--   `reaction = {action: 'superseded', by_command_id, by_command_type, by_issued_at}` and nothing is booked,
--   emitted or escalated. A refusal with no later command is rerouted or escalated exactly as before, and
--   non-reroutable refusals (every other reason) escalate exactly as before.
--
--   "Later tick" and not "later command": a refusal is often rerouted in the same tick it was refused, beside other
--   same-tick commands whose ordering is its own question (recorded on G225). This change touches only the case
--   measured above.
--
-- ══ §3 forces_recert TRUE ═══════════════════════════════════════════════════════════════════════════════════════
--
--   The reactor runs inside the certified tick. Six reroutes on the 48-tick column become `superseded`, so
--   bookings, commands and events move, and the canon re-certifies.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0490 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('ottoq.ottoq_react_to_refusals(uuid,uuid,timestamp with time zone)'::regprocedure))
     <> '92b157a208739835be9e0ecafc78678b' THEN
    RAISE EXCEPTION '0490 P2: ottoq.ottoq_react_to_refusals is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0490_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'ottoq.ottoq_react_to_refusals(uuid,uuid,timestamp with time zone)'::regprocedure;

DO $patch$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_react_to_refusals(uuid,uuid,timestamp with time zone)'::regprocedure);
  -- (a) the cursor carries the refusal's tick
  v_old_a text := $o$    SELECT command_id, vehicle_id, command_type, payload, reason_code, reason_detail
      FROM public.ottoq_vehicle_commands$o$;
  v_new_a text := $n$    SELECT command_id, vehicle_id, command_type, payload, reason_code, reason_detail, issued_at  /* 0490 */
      FROM public.ottoq_vehicle_commands$n$;
  -- (b) three scalars for the later command, if there is one
  v_old_b text := $o$  v_outcome jsonb; v_zones text[];
$o$;
  v_new_b text := $n$  v_outcome jsonb; v_zones text[];
  v_newer_id uuid; v_newer_type text; v_newer_at timestamptz;  /* 0490 */
$n$;
  -- (c) the later command wins before the reroute is tried
  v_old_c text := $o$    v_new_cmd := NULL; v_new_stall := NULL; v_booking := NULL; v_outcome := NULL; v_zones := NULL;

    IF v_rec.reason_code IN ('target_occupied','resource_faulted')
       AND v_rec.command_type IN ('proceed_to_stall','begin_charge','stage') THEN
$o$;
  v_new_c text := $n$    v_new_cmd := NULL; v_new_stall := NULL; v_booking := NULL; v_outcome := NULL; v_zones := NULL;
    v_newer_id := NULL; v_newer_type := NULL; v_newer_at := NULL;

    /* 0490 (G225): A REFUSAL THE DECIDE PATH HAS ALREADY RE-PLANNED IS NOT REROUTED. When the car holds a
       command from a later tick, that command is its plan, and a reroute of the old one sends the car to a
       second stall. Measured on busy_day/171717/48 (verdict 364, arm A): 6 of 48 reroutes were of this kind,
       one of them an L2 booked for an hour for a car the next tick had already sent to a DCFC. */
    IF v_rec.reason_code IN ('target_occupied','resource_faulted')
       AND v_rec.command_type IN ('proceed_to_stall','begin_charge','stage') THEN
      SELECT n.command_id, n.command_type, n.issued_at
        INTO v_newer_id, v_newer_type, v_newer_at
        FROM public.ottoq_vehicle_commands n
       WHERE n.sim_run_id = p_sim_run_id
         AND n.vehicle_id = v_rec.vehicle_id
         AND n.issued_at  > v_rec.issued_at
       ORDER BY n.issued_at, n.command_seq
       LIMIT 1;
    END IF;

    IF v_newer_id IS NOT NULL THEN
      v_outcome := jsonb_build_object('action','superseded','by_command_id',v_newer_id,
                                      'by_command_type',v_newer_type,'by_issued_at',v_newer_at);

    ELSIF v_rec.reason_code IN ('target_occupied','resource_faulted')
       AND v_rec.command_type IN ('proceed_to_stall','begin_charge','stage') THEN
$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old_a, ''))) / length(v_old_a);
  IF n <> 1 THEN RAISE EXCEPTION '0490: the refusal cursor matched % times, not once', n; END IF;
  n := (length(v_def) - length(replace(v_def, v_old_b, ''))) / length(v_old_b);
  IF n <> 1 THEN RAISE EXCEPTION '0490: the declaration line matched % times, not once', n; END IF;
  n := (length(v_def) - length(replace(v_def, v_old_c, ''))) / length(v_old_c);
  IF n <> 1 THEN RAISE EXCEPTION '0490: the reroute branch matched % times, not once', n; END IF;
  EXECUTE replace(replace(replace(v_def, v_old_a, v_new_a), v_old_b, v_new_b), v_old_c, v_new_c);
END $patch$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_f   regprocedure := 'ottoq.ottoq_react_to_refusals(uuid,uuid,timestamp with time zone)'::regprocedure;
  v_def text := pg_get_functiondef('ottoq.ottoq_react_to_refusals(uuid,uuid,timestamp with time zone)'::regprocedure);
BEGIN
  -- V1: the later-command test sits above the reroute, which is now its ELSIF, and the reroute itself is unchanged.
  IF position('IF v_newer_id IS NOT NULL THEN' IN v_def) = 0
     OR position($x$    ELSIF v_rec.reason_code IN ('target_occupied','resource_faulted')$x$ IN v_def) = 0
     OR position('IF v_newer_id IS NOT NULL THEN' IN v_def) > position('ELSIF v_rec.reason_code' IN v_def)
     OR position('AND n.issued_at  > v_rec.issued_at' IN v_def) = 0
     OR position($x$'otto_q_reaction')$x$ IN v_def) = 0
     OR position($x$'otto_q_reaction_last_resort')$x$ IN v_def) = 0 THEN
    RAISE EXCEPTION '0490 V1: the reactor is not the body this file leaves';
  END IF;
  -- V2: privileges and security definer kept (CREATE OR REPLACE keeps the ACL).
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_f)
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = v_f) <> 'postgres=X/postgres,service_role=X/postgres' THEN
    RAISE EXCEPTION '0490 V2: ottoq_react_to_refusals''s privileges changed';
  END IF;
END $verify$;

-- Rollback: restore ottoq.ottoq_react_to_refusals from ottoq_schema_snapshots label '0490_pre' (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0490_the_refusal_reactor_leaves_a_car_the_decide_path_has_already_replanned', true,
  'ottoq_react_to_refusals marks a reroutable refusal superseded, and reroutes nothing, when the car already holds a '
  'command from a later tick. Six reroutes on busy_day/171717/48 become superseded, so bookings, commands and events move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
