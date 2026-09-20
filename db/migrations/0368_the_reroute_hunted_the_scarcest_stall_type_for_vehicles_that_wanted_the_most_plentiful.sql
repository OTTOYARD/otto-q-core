-- migration-version: 20260920041236
-- ════════════════════════════════════════════════════════════════════════════
-- 0368  THE REROUTE HUNTED THE SCARCEST STALL TYPE ON THE SITE FOR VEHICLES
--       THAT WANTED THE MOST PLENTIFUL ONE.
--
--       forces_recert TRUE -- it changes which stall a rerouted vehicle is
--       offered, on every arm.
-- ════════════════════════════════════════════════════════════════════════════
--
-- G83, and it is the second half of G82's answer rather than a new subject. 0367
-- put the reservation reclaimer on the live path, so the depot now offers the
-- reroute real stalls. This is what the reroute then did with them.
--
-- `ottoq.ottoq_react_to_refusals` derived the stall type it should look for as:
--
--   v_stype := COALESCE(v_rec.payload->>'stall_type',
--                CASE WHEN v_rec.command_type = 'stage' THEN 'staging' ELSE 'dcfc' END);
--
-- A `proceed_to_stall` command that carries no `stall_type` therefore falls
-- through to **'dcfc'** -- ten stalls on this site -- whatever it was actually
-- sent to. Measured on run `5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10` (busy_day, seed
-- 777777, twin depot, speed 8.0) at tick 38, with 0367 live from tick 1:
--
--   refused commands                                              31
--     superseded                 (not reroutable, correctly escalated)  14
--     vehicle_state_incompatible (not reroutable, correctly escalated)  10
--     target_occupied / resource_faulted  (the reroutable class)         7
--       rerouted                                                        2
--       escalated no_capacity                                           5
--
--   of the reroutable class, by what the reroute LOOKED FOR:
--     payload stall_type 'l2', target stall 'l2'      4   -> 2 rerouted, 2 escalated
--     payload stall_type NULL, target stall 'staging' 4   -> 0 rerouted, 4 escalated
--                                                            (the walk searched 'dcfc')
--
-- Four of the eight were sent to a STAGING stall -- 113 of them on this depot --
-- and the reroute went looking for DCFC, of which there are ten, found none, and
-- escalated `no_capacity` **while 41 stalls stood unclaimed**. The command already
-- records where it was sent, in `payload->>'stall_id'`. Part A asks that stall.
--
-- AND A MEASUREMENT MISTAKE OF MY OWN, RECORDED BECAUSE IT WOULD HAVE MISPRICED
-- THIS FIX. The first reading of the reroute's success rate divided by ALL 31
-- refusals and reported 6.5%. Twenty-four of those 31 are `superseded` or
-- `vehicle_state_incompatible`, which the reactor is right to escalate and cannot
-- reroute by design. The honest denominator is the reroutable class: **2 of 7,
-- 29%**. Same defect as G78 -- a correct refusal counted as a miss -- and the
-- denominator is fixed in `db/checks/0258` Q3 as well as here.
--
-- Part B is the observability half: `no_capacity` on its own cannot distinguish
-- "the site is full" from "the walk looked in the wrong place", which is exactly
-- the ambiguity that hid this for a whole run. The escalation now carries
-- `wanted_stall_type`, `stall_type_source` (payload / target_stall /
-- command_type_default) and `candidates_seen`, in both the command payload and
-- the `ottoq.refusal_escalated` event. G71's rule, applied to a second refusal.

-- ══ P0. THE REACTOR IS AS 0367 LEFT IT, AND NOT ALREADY PATCHED ═════════════
DO $p0$
DECLARE
  v_src text;
BEGIN
  SELECT p.prosrc INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_react_to_refusals';
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'P0: ottoq.ottoq_react_to_refusals not found';
  END IF;
  IF position('v_stype_src' in v_src) > 0 THEN
    RAISE EXCEPTION 'P0: already patched -- 0368 has been applied';
  END IF;
  IF position('CASE WHEN v_rec.command_type = ''stage'' THEN ''staging'' ELSE ''dcfc'' END' in v_src) = 0 THEN
    RAISE EXCEPTION 'P0: the dcfc fallback this migration exists to fix is not in the body; re-derive Part A';
  END IF;
  --: the reactor must still be reached from the live path, or fixing it is moot
  IF position('ottoq_react_to_refusals' in
        (SELECT p2.prosrc FROM pg_proc p2 JOIN pg_namespace n2 ON n2.oid = p2.pronamespace
          WHERE n2.nspname = 'public' AND p2.proname = 'ottoq_sim_decide_and_dispatch')) = 0 THEN
    RAISE EXCEPTION 'P0: decide_and_dispatch no longer calls the reactor';
  END IF;
  RAISE NOTICE 'P0 ok';
END $p0$;

-- ══ P1. THE DEFECT IS LIVE: REFUSALS WHOSE TARGET TYPE IS NOT THE ASSUMED ONE ═
DO $p1$
DECLARE
  v_wrong bigint;
BEGIN
  SELECT count(*) INTO v_wrong
    FROM public.ottoq_vehicle_commands c
    JOIN public.stalls s ON s.id = NULLIF(c.payload->>'stall_id','')::uuid
   WHERE c.status = 'refused'
     AND c.reason_code IN ('target_occupied','resource_faulted')
     AND c.command_type IN ('proceed_to_stall','begin_charge','stage')
     AND c.payload->>'stall_type' IS NULL
     AND s.stall_type::text
         <> CASE WHEN c.command_type = 'stage' THEN 'staging' ELSE 'dcfc' END
     AND s.depot_id = '11111111-1111-1111-1111-111111111111';
  --: NOT a failure when zero -- the run may be young or the purge may have run.
  RAISE NOTICE 'P1: refusals whose reroute would search the WRONG stall type = %', v_wrong;
END $p1$;

-- ══ PART A+B. THE REACTOR, ASKING THE STALL AND SAYING WHAT IT LOOKED FOR ════
-- Derived verbatim from pg_get_functiondef(ottoq.ottoq_react_to_refusals) with
-- six edits, each asserted unique by the patcher before substitution. NOT
-- retyped: 0360 Part C nearly broke every tick from a signature typed from
-- memory, and this function is on the tick path.
CREATE OR REPLACE FUNCTION ottoq.ottoq_react_to_refusals(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rec RECORD; v_cand RECORD; v_n int := 0;
  v_seen int := 0; v_stype_src text; v_target_stall uuid;  /* 0368 */
  v_stype text; v_purpose text; v_booking uuid; v_new_stall uuid; v_new_cmd uuid;
  v_outcome jsonb; v_zones text[];
BEGIN
  FOR v_rec IN
    SELECT command_id, vehicle_id, command_type, payload, reason_code, reason_detail
      FROM public.ottoq_vehicle_commands
     WHERE sim_run_id = p_sim_run_id AND status = 'refused' AND reacted_at IS NULL
     /* 0059: issued_at is the per-tick sim-clock stamp (up to 72 commands
        share one value), so alone it is heap order. Run-stable tiebreak:
        vehicle, command type, refused target stall. */
     ORDER BY issued_at, vehicle_id, command_type, payload->>'stall_id', command_seq   /* 0207 */
     LIMIT 20
  LOOP
    v_new_cmd := NULL; v_new_stall := NULL; v_booking := NULL; v_outcome := NULL; v_zones := NULL;

    IF v_rec.reason_code IN ('target_occupied','resource_faulted')
       AND v_rec.command_type IN ('proceed_to_stall','begin_charge','stage') THEN
      /* 0368 (G83): THE REROUTE USED TO GUESS 'dcfc' WHENEVER THE COMMAND CARRIED
         NO stall_type, AND THAT IS THE SCARCEST TYPE ON THE SITE. Measured on run
         5b37ee46 at tick 38: 4 of the 8 reroutable refusals were proceed_to_stall
         commands with no stall_type in payload whose ACTUAL target stall was
         'staging' -- 113 stalls -- and the reroute hunted 'dcfc' -- 10 stalls --
         found nothing, and escalated no_capacity while 41 stalls stood unclaimed.
         The command already says where it was sent. Ask the stall. */
      v_target_stall := NULLIF(v_rec.payload->>'stall_id','')::uuid;
      v_stype := COALESCE(
                   v_rec.payload->>'stall_type',
                   (SELECT s.stall_type::text FROM public.stalls s
                     WHERE s.id = v_target_stall),
                   CASE WHEN v_rec.command_type = 'stage' THEN 'staging' ELSE 'dcfc' END);
      v_stype_src := CASE
                       WHEN v_rec.payload->>'stall_type' IS NOT NULL THEN 'payload'
                       WHEN EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = v_target_stall)
                         THEN 'target_stall'
                       ELSE 'command_type_default' END;
      v_seen := 0;
      v_purpose := CASE v_stype WHEN 'dcfc' THEN 'charge_dcfc'
                                WHEN 'l2'   THEN 'charge_l2'
                                ELSE 'temp_hold' END;

      -- A rerouted PARKING hold must not take inspection capacity. Charge reroutes are
      -- unaffected (dcfc/l2 stalls are not in the arrival_inspection zone).
      IF v_stype = 'staging' THEN
        SELECT array_agg(DISTINCT s.zone) INTO v_zones
          FROM public.stalls s
         WHERE s.depot_id = p_depot_id
           AND s.stall_type::text = 'staging'
           AND s.zone <> 'arrival_inspection';
      END IF;

      -- reserve-first walk (the legacy pointer is the scarcer gate)
      FOR v_cand IN
        SELECT f.stall_id FROM ottoq.ottoq_stall_free_between(
          p_sim_run_id, p_depot_id, p_clock, p_clock + interval '60 minutes',
          v_stype, NULL, 25, v_zones) f
      LOOP
        v_seen := v_seen + 1;  /* 0368: a candidate the walk actually examined */
        IF ottoq_reserve_stall(v_cand.stall_id, v_rec.vehicle_id, p_clock, 3600) THEN
          v_booking := ottoq.ottoq_book_stall(
            p_sim_run_id, v_cand.stall_id, v_rec.vehicle_id, v_purpose,
            p_clock, p_clock + interval '60 minutes', NULL, NULL, 'otto_q_reaction');
          v_new_stall := v_cand.stall_id;
          EXIT;
        END IF;
      END LOOP;

      -- LAST RESORT for parking only: never strand a refused vehicle. Reached solely when
      -- every non-inspection staging stall is unavailable for the window.
      IF v_new_stall IS NULL AND v_stype = 'staging' AND v_zones IS NOT NULL THEN
        FOR v_cand IN
          SELECT f.stall_id FROM ottoq.ottoq_stall_free_between(
            p_sim_run_id, p_depot_id, p_clock, p_clock + interval '60 minutes',
            v_stype, NULL, 25, ARRAY['arrival_inspection']) f
        LOOP
          v_seen := v_seen + 1;  /* 0368 */
          IF ottoq_reserve_stall(v_cand.stall_id, v_rec.vehicle_id, p_clock, 3600) THEN
            v_booking := ottoq.ottoq_book_stall(
              p_sim_run_id, v_cand.stall_id, v_rec.vehicle_id, v_purpose,
              p_clock, p_clock + interval '60 minutes', NULL, NULL, 'otto_q_reaction_last_resort');
            v_new_stall := v_cand.stall_id;
            EXIT;
          END IF;
        END LOOP;
      END IF;

      IF v_new_stall IS NOT NULL THEN
        v_new_cmd := ottoq.ottoq_emit_vehicle_command(
          p_sim_run_id, p_depot_id, v_rec.vehicle_id, v_rec.command_type,
          (v_rec.payload - 'apply_required')
            || jsonb_build_object('stall_id', v_new_stall, 'stall_type', v_stype,
                 'apply_required', true, 'reroute_after', v_rec.command_id,
                 'reroute_reason', v_rec.reason_code),
          p_clock);
        v_outcome := jsonb_build_object('action','rerouted','new_command_id',v_new_cmd,
                                        'new_stall_id',v_new_stall,'booking_id',v_booking);
      ELSE
        /* 0368: 'no_capacity' alone cannot distinguish "the site is full" from
           "the walk looked in the wrong place". Both are recorded now. */
        v_outcome := jsonb_build_object('action','escalated','reason','no_capacity',
                       'wanted_stall_type', v_stype, 'stall_type_source', v_stype_src,
                       'candidates_seen', v_seen);
        BEGIN
          PERFORM ottoq_record_event(
            p_actor_type:='ottoq_engine', p_actor_id:='refusal_reactor',
            p_event_type:='ottoq.refusal_escalated', p_entity_type:='vehicle',
            p_entity_id:=v_rec.vehicle_id, p_depot_id:=p_depot_id,
            p_payload:=jsonb_build_object('command_id',v_rec.command_id,
              'reason_code','no_capacity','original_refusal',v_rec.reason_code,
              'wanted_stall_type',v_stype, 'stall_type_source',v_stype_src,
              'candidates_seen',v_seen, 'target_stall_id',v_target_stall),
            p_severity:='warning', p_ingest_source:='production', p_data_source:=CASE WHEN p_sim_run_id IS NULL THEN 'production' ELSE 'twin' END,
            p_sim_run_id:=p_sim_run_id);
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END IF;

    ELSE
      v_outcome := jsonb_build_object('action','escalated','reason',v_rec.reason_code);
      BEGIN
        PERFORM ottoq_record_event(
          p_actor_type:='ottoq_engine', p_actor_id:='refusal_reactor',
          p_event_type:='ottoq.refusal_escalated', p_entity_type:='vehicle',
          p_entity_id:=v_rec.vehicle_id, p_depot_id:=p_depot_id,
          p_payload:=jsonb_build_object('command_id',v_rec.command_id,
            'reason_code',v_rec.reason_code,'reason_detail',v_rec.reason_detail),
          p_severity:=CASE WHEN v_rec.reason_code='vehicle_unresponsive' THEN 'warning' ELSE 'info' END,
          p_ingest_source:='production', p_data_source:=CASE WHEN p_sim_run_id IS NULL THEN 'production' ELSE 'twin' END, p_sim_run_id:=p_sim_run_id);
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;

    UPDATE public.ottoq_vehicle_commands
       SET reacted_at = p_clock,
           payload = payload || jsonb_build_object('reaction', v_outcome)
     WHERE command_id = v_rec.command_id;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $function$
;

COMMENT ON FUNCTION ottoq.ottoq_react_to_refusals(uuid, uuid, timestamptz) IS
'THE REJECTION -> RE-SOLVE LOOP. For a refused proceed_to_stall / begin_charge / '
'stage carrying target_occupied or resource_faulted, walks up to 25 calendar-free '
'stalls of the wanted type over a 60-minute window, reserves, books, and re-emits '
'the command with reroute_after / reroute_reason; escalates ottoq.refusal_escalated '
'only when every candidate fails ottoq_reserve_stall. Parking reroutes exclude the '
'arrival_inspection zone, with a last-resort pass into it so a refused vehicle is '
'never stranded. 0368: the wanted stall type is read from payload->>stall_type, '
'then from the stall the command was ACTUALLY sent to, and only then from a '
'command-type default -- before 0368 a proceed_to_stall with no stall_type was '
'assumed to want dcfc, the scarcest type on the site, and four of eight reroutable '
'refusals on run 5b37ee46 were staging vehicles hunted through ten DCFC stalls. '
'Escalations carry wanted_stall_type, stall_type_source and candidates_seen so '
'"the site is full" is distinguishable from "the walk looked in the wrong place".';

-- ══ P9. POST-ASSERTIONS ═════════════════════════════════════════════════════
DO $p9$
DECLARE
  v_src text;
BEGIN
  SELECT p.prosrc INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_react_to_refusals';
  IF position('v_stype_src' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: the stall_type provenance variable is missing -- Part A did not take';
  END IF;
  IF position('SELECT s.stall_type::text FROM public.stalls s' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: the target-stall lookup is missing';
  END IF;
  IF position('candidates_seen' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: the escalation does not report candidates_seen';
  END IF;
  --: everything the reactor did before must still be there
  IF position('otto_q_reaction_last_resort' in v_src) = 0
     OR position('arrival_inspection' in v_src) = 0
     OR position('reroute_after' in v_src) = 0
     OR position('reacted_at' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: the patch lost part of the original reactor';
  END IF;
  RAISE NOTICE 'P9 ok: reroute asks the stall, reports what it looked for, and kept every prior behaviour';
END $p9$;
