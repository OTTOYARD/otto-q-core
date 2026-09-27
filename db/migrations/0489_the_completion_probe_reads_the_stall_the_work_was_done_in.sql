-- migration-version: 20260926161825
-- migration-name:    the_completion_probe_reads_the_stall_the_work_was_done_in
--
-- 0489  **The completion probe reads the stall the work was done in (G224).** The canon's 48-tick busy_day
--       column failed under 0487 on the events and rules atoms alone, and the cause is a coin flip in the probe.
--
-- ══ §1 WHAT WAS WRONG (measured 2026-09-26, verdict 364) ═══════════════════════════════════════════════════════
--
--   Verdict 364 (busy_day/171717/48, 10:45 AM CT) disagreed on `events` and `rules` and on nothing else: commands,
--   decisions, bookings, energy, SDRs and recalls were equal, so both arms played the same world. The rule
--   evaluations differ by exactly one row. HW.006.physical_presence_verification at task_completion: arm A 11
--   failed and 497 passed, arm B 12 and 496. The flipped row is vehicle a1111111-0001-0001-0001-000000000001 at
--   its last charge close. Arm A judged stall 3a7310ac (the DCFC it charged on, the car present, pass). Arm B
--   judged stall fe18413d (an L2 stall it never occupied, "stall does not record this vehicle as present", fail).
--
--   `public.ottoq_probe_task_completion` resolves the stall itself from the car's bookings,
--   `ORDER BY (state IN ('held','active')) DESC, lower(during) DESC LIMIT 1`, and that order is not total. This car
--   holds two `done` charge bookings starting at the same instant, 23:00 sim: 3a7310ac (charge_dcfc,
--   otto_q_enacted) and fe18413d (charge_l2, otto_q_reaction). Identical in both arms. The tie was broken by
--   physical row order, which differs between the arms of one transaction. So the verdict was a coin flip, and a
--   wrong-stall pick also records a false HW.006 failure on live runs.
--
--   The charge-session close, the caller where this happened, already knows the stall: `v_session.stall_id`.
--   It did not say, because the probe took no stall.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `public.ottoq_probe_task_completion_at(...same six..., p_stall_id)` holds the one algorithm. With a stall it
--       judges that stall. Without one it looks the stall up as before and breaks every tie on the stall id
--       (fixed across arms), so the order is total. Same return columns, search path and SECURITY DEFINER as its
--       sibling, and service_role only.
--   (2) `public.ottoq_probe_task_completion` keeps its signature and grants and delegates with no stall, so the
--       visit-atom path behaves as before except that its ties no longer depend on row order.
--   (3) `twin.ottoq_sim_stop_charge_session` passes the session's own stall.
--
-- ══ §3 forces_recert TRUE ═══════════════════════════════════════════════════════════════════════════════════════
--
--   The probe is in the certified path and its verdicts are hashed in the rules and events atoms. Every charge
--   close now judges its own stall, so the canon's digests move and the canon re-certifies.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0489 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the bodies this file patches, exactly as measured, and nothing it creates exists yet ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_probe_task_completion(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone)'::regprocedure))
     <> '6f943c9cd2c17a8dc559accc32c23bb6' THEN
    RAISE EXCEPTION '0489 P2: public.ottoq_probe_task_completion is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure))
     <> '390b26a4cd16e71b4619de68955bef03' THEN
    RAISE EXCEPTION '0489 P2: twin.ottoq_sim_stop_charge_session is not the body this file patches';
  END IF;
  IF to_regprocedure('public.ottoq_probe_task_completion_at(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0489 P2: public.ottoq_probe_task_completion_at already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0489_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_probe_task_completion(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone)'::regprocedure,
                 'twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure);

-- ── (1) the one algorithm, told the stall when the caller knows it ──
CREATE FUNCTION public.ottoq_probe_task_completion_at(
  p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_svc text,
  p_started_at timestamp with time zone, p_ends_at timestamp with time zone, p_stall_id uuid)
 RETURNS TABLE(rule_code text, passed boolean, reason text, severity text, enforcement text, would_block boolean, had_a_stall boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $function$
/* 0489 (G224). The task_completion probe, told which stall the work was done in when the caller knows it (a
   charge close knows its session's stall). Without one it resolves the stall from the car's bookings as before,
   and breaks every tie on the stall id, so two bookings that start at the same instant can no longer be ordered
   by where their rows happen to sit. */
DECLARE
  v_stall_id   uuid;
  v_stall_type text;
  v_ctx        jsonb;
BEGIN
  IF p_stall_id IS NOT NULL THEN
    SELECT s.id, s.stall_type::text INTO v_stall_id, v_stall_type FROM public.stalls s WHERE s.id = p_stall_id;
  ELSE
    SELECT b.stall_id, s.stall_type::text
      INTO v_stall_id, v_stall_type
      FROM public.ottoq_stall_bookings b
      LEFT JOIN public.stalls s ON s.id = b.stall_id
     WHERE b.vehicle_id = p_vehicle_id
       AND b.need_atom  = p_svc
       AND b.state IN ('held','active','done','interrupted')
       AND (p_sim_run_id IS NULL OR b.sim_run_id IS NULL OR b.sim_run_id = p_sim_run_id)
     ORDER BY (b.state IN ('held','active')) DESC, lower(b.during) DESC, b.stall_id
     LIMIT 1;
  END IF;

  v_ctx := jsonb_strip_nulls(jsonb_build_object(
             'action',      'task_completion',
             'vehicle_id',  p_vehicle_id,
             'depot_id',    p_depot_id,
             'stall_id',    v_stall_id,
             'stall_type',  v_stall_type,
             'svc',         p_svc,
             'service',     p_svc,
             'started_at',  p_started_at,
             'ends_at',     p_ends_at,
             'now_ts',      COALESCE(p_ends_at, now())));

  RETURN QUERY
  SELECT sp.rule_code, sp.passed, sp.reason, sp.severity, sp.enforcement, sp.would_block,
         (v_stall_id IS NOT NULL)
    FROM public.ottoq_shield_probe(
           'task_completion', 'vehicle', p_vehicle_id, v_ctx, NULL, p_depot_id) sp;
END
$function$;

REVOKE ALL ON FUNCTION public.ottoq_probe_task_completion_at(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_probe_task_completion_at(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone,uuid) TO service_role;

-- ── (2) the six-argument probe keeps its signature and grants, and delegates ──
DO $delegate$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_probe_task_completion(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone)'::regprocedure);
  v_body_start int := position('AS $function$' IN v_def);
  v_new text;
BEGIN
  IF v_body_start = 0 THEN RAISE EXCEPTION '0489: the probe definition has no $function$ body'; END IF;
  v_new := substring(v_def FROM 1 FOR v_body_start - 1) || $b$AS $function$
/* 0489 (G224): one algorithm, in ottoq_probe_task_completion_at. This signature is kept for the visit-atom path,
   which does not know a stall, and passes none. */
BEGIN
  RETURN QUERY
  SELECT * FROM public.ottoq_probe_task_completion_at(
           p_sim_run_id, p_depot_id, p_vehicle_id, p_svc, p_started_at, p_ends_at, NULL::uuid);
END
$function$
$b$;
  EXECUTE v_new;
END $delegate$;

-- ── (3) the charge close names its own stall ──
DO $patch_close$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure);
  v_old text := $o$    PERFORM 1 FROM public.ottoq_probe_task_completion(
      p_sim_run_id := p_sim_run_id,
      p_depot_id   := (SELECT depot_id FROM stalls WHERE id = v_session.stall_id),
      p_vehicle_id := v_session.vehicle_id,
      p_svc        := 'charge',
      p_started_at := v_session.started_at,
      p_ends_at    := v_clock);
$o$;
  v_new text := $n$    -- 0489 (G224): the session's own stall, not a lookup that can tie across two bookings.
    PERFORM 1 FROM public.ottoq_probe_task_completion_at(
      p_sim_run_id := p_sim_run_id,
      p_depot_id   := (SELECT depot_id FROM stalls WHERE id = v_session.stall_id),
      p_vehicle_id := v_session.vehicle_id,
      p_svc        := 'charge',
      p_started_at := v_session.started_at,
      p_ends_at    := v_clock,
      p_stall_id   := v_session.stall_id);
$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0489: the charge-close probe call matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch_close$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_at    regprocedure := 'public.ottoq_probe_task_completion_at(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone,uuid)'::regprocedure;
  v_six   regprocedure := 'public.ottoq_probe_task_completion(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone)'::regprocedure;
  v_close regprocedure := 'twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure;
  v_pre_acl text;
BEGIN
  -- V1: the lookup order is total, and the stall is taken when given.
  IF position('ORDER BY (b.state IN (''held'',''active'')) DESC, lower(b.during) DESC, b.stall_id' IN pg_get_functiondef(v_at)) = 0
     OR position('IF p_stall_id IS NOT NULL THEN' IN pg_get_functiondef(v_at)) = 0 THEN
    RAISE EXCEPTION '0489 V1: ottoq_probe_task_completion_at is not the body this file leaves';
  END IF;
  -- V2: the six-argument probe delegates, keeps security definer and its grants as they were.
  SELECT array_to_string(p.proacl, ',') INTO v_pre_acl FROM pg_proc p WHERE p.oid = v_six;
  IF position('ottoq_probe_task_completion_at(' IN pg_get_functiondef(v_six)) = 0
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_six)
     OR v_pre_acl <> '=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres' THEN
    RAISE EXCEPTION '0489 V2: the six-argument probe does not delegate, or its grants moved (%)', v_pre_acl;
  END IF;
  -- V3: the new probe is service_role only.
  IF has_function_privilege('anon', v_at, 'EXECUTE') OR has_function_privilege('authenticated', v_at, 'EXECUTE')
     OR NOT has_function_privilege('service_role', v_at, 'EXECUTE') OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = v_at) THEN
    RAISE EXCEPTION '0489 V3: ottoq_probe_task_completion_at has the wrong privileges';
  END IF;
  -- V4: the charge close passes its session's stall, and still probes above the pointer clear.
  IF position('p_stall_id   := v_session.stall_id);' IN pg_get_functiondef(v_close)) = 0
     OR position('ottoq_probe_task_completion_at(' IN pg_get_functiondef(v_close))
        > position('UPDATE stalls SET current_vehicle_id = NULL WHERE id = v_session.stall_id' IN pg_get_functiondef(v_close)) THEN
    RAISE EXCEPTION '0489 V4: the charge close does not name its stall above the pointer clear';
  END IF;
END $verify$;

-- Rollback: restore public.ottoq_probe_task_completion and twin.ottoq_sim_stop_charge_session from
-- ottoq_schema_snapshots label '0489_pre' (CREATE OR REPLACE, ACLs kept), then
-- DROP FUNCTION public.ottoq_probe_task_completion_at(uuid,uuid,uuid,text,timestamp with time zone,timestamp with time zone,uuid).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0489_the_completion_probe_reads_the_stall_the_work_was_done_in', true,
  'The task_completion probe judges the stall its caller names (the charge close names its session''s stall), and '
  'its booking lookup breaks ties on stall id. Verdict 364 failed on a tie broken by row order. HW.006 verdicts move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
