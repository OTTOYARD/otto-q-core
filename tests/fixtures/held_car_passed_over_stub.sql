-- tests/fixtures/held_car_passed_over_stub.sql — the world db/migrations/0761 runs in, for
-- tests/test_held_car_is_passed_over_sql.py.
--
-- Five bodies are the live ones, read from gxdrcyphqjzjsuhxuqtg on 2026-10-20 between 5:36 and 5:48 PM CT (22:36:49 and
-- 22:47:58 UTC, the clock read either side) and copied byte for byte. The test asserts each one's prosrc md5 against the pin 0761's P1 reads:
--   ottoq.ottoq_enact_space_assignment   8334b01ae1fe40a3c67da111b93faee4  (the assignment 0761 patches)
--   ottoq.ottoq_uplink_transfer_holds    dfd5d9d7b68066b2e933f5056bcaaceb  (the hold, 0695 and 0758)
--   public.ottoq_vehicle_is_tethered     306c42afd9c974881402fdfc579ecf15  (the charge arm's tether test)
--   public.ottoq_arm_interlock_guard     ac1e1c702521e4b2e0708ebef513071c  (the interlock, a trigger on vehicles)
--   public.ottoq_policy_get              72b658f3a9c5a7ec0fae15aecc907f38  (the dial reader)
-- Everything else is the least each of them reads. The assignment's three helpers are stubs that choose the first
-- free stall of the kind asked for, reserve it, and book it. Columns are text where the live ones are enums: every read
-- here casts them to text.

CREATE SCHEMA IF NOT EXISTS ottoq;
CREATE SCHEMA IF NOT EXISTS twin;

CREATE TABLE public.ottoq_sim_runs (
  sim_run_id uuid PRIMARY KEY, depot_id uuid, status text, started_at timestamptz, sim_clock_current timestamptz);

CREATE TABLE public.ottoq_policy_params (
  scope_type text NOT NULL, scope_id uuid NOT NULL, param_key text NOT NULL, param_value numeric,
  updated_by text, updated_at timestamptz DEFAULT now(), PRIMARY KEY (scope_type, scope_id, param_key));

CREATE TABLE public.ottoq_policy_param_catalog (
  param_key text PRIMARY KEY, description text, default_value numeric, min_value numeric, max_value numeric,
  affects text, min_exclusive numeric, max_exclusive numeric, agent_writable boolean NOT NULL DEFAULT false,
  agent_min_value numeric, agent_max_value numeric, agent_max_drift_pct numeric);

CREATE TABLE public.stalls (
  id uuid PRIMARY KEY, depot_id uuid, stall_code text, stall_type text, zone text, status text DEFAULT 'available',
  current_vehicle_id uuid, reserved_by uuid, reserved_at timestamptz, reservation_expires_at timestamptz);

CREATE TABLE public.vehicles (
  id uuid PRIMARY KEY, home_depot_id uuid, current_depot_id uuid, category text DEFAULT 'autonomous',
  current_state text, current_stall_id uuid, last_state_change timestamptz,
  robotic_tether_until timestamptz, robotic_tether_stall_id uuid, robotic_tether_direction text,
  robotic_tether_phase text);

CREATE TABLE public.ottoq_visit_needs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), vehicle_id uuid, sim_run_id uuid, status text, atoms jsonb);

CREATE TABLE public.ottoq_stall_bookings (
  booking_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sim_run_id uuid, stall_id uuid, vehicle_id uuid, leg_id uuid,
  purpose text, state text, during tstzrange, booked_at timestamptz DEFAULT now(), released_at timestamptz,
  release_reason text, source text);

CREATE TABLE public.ottoq_itinerary_legs (leg_id uuid PRIMARY KEY, to_stall_id uuid, status text);

-- ── the assignment's three helpers (stubs) ──
CREATE FUNCTION ottoq.ottoq_stall_free_between(p_run uuid, p_depot uuid, p_from timestamptz, p_to timestamptz,
                                               p_stall_type text, p_role text, p_limit integer, p_zones text[])
RETURNS TABLE(stall_id uuid, stall_code text, stall_type text, staging_role text, zone text)
LANGUAGE sql STABLE AS $$
  SELECT s.id, s.stall_code, s.stall_type, NULL::text, s.zone
    FROM public.stalls s
   WHERE s.depot_id = p_depot AND s.stall_type = p_stall_type AND s.current_vehicle_id IS NULL
     AND s.reserved_by IS NULL AND (p_zones IS NULL OR s.zone = ANY (p_zones))
   ORDER BY s.stall_code LIMIT p_limit
$$;

CREATE FUNCTION public.ottoq_reserve_stall(p_stall uuid, p_vehicle uuid, p_clock timestamptz, p_ttl_s integer)
RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.stalls SET reserved_by = p_vehicle, reserved_at = p_clock,
         reservation_expires_at = p_clock + make_interval(secs => p_ttl_s)
   WHERE id = p_stall AND (reserved_by IS NULL OR reserved_by = p_vehicle) AND current_vehicle_id IS NULL;
  RETURN FOUND;
END $$;

CREATE FUNCTION ottoq.ottoq_record_enacted_booking(p_run uuid, p_stall uuid, p_vehicle uuid, p_at timestamptz,
                                                   p_leg uuid, p_from timestamptz, p_to timestamptz, p_purpose text,
                                                   p_source text)
RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, leg_id, purpose, state, during, source)
  VALUES (p_run, p_stall, p_vehicle, p_leg, p_purpose, 'active', tstzrange(p_from, p_to, '[)'), p_source)
  RETURNING booking_id
$$;

-- ── the five live bodies ──
CREATE OR REPLACE FUNCTION public.ottoq_policy_get(p_sim_run_id uuid, p_param_key text, p_default numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v numeric; v_depot uuid; v_seen text;
BEGIN
  SELECT param_value INTO v FROM ottoq_policy_params
   WHERE scope_type='run' AND scope_id=p_sim_run_id AND param_key=p_param_key;
  IF v IS NOT NULL THEN
    -- 0533 (G258): the read witness. A dial pair asks, after each arm, whether the arm read its own run-scoped value of
    -- the dial at all: a dial nothing reads at run scope cannot make two arms differ. One entry per run and key, in a
    -- transaction-local setting, so it costs nothing outside the run tier and leaves with the transaction.
    v_seen := COALESCE(current_setting('ottoq.run_scope_reads', true), '');
    IF strpos(v_seen, ',' || p_sim_run_id::text || ':' || p_param_key || ',') = 0 THEN
      PERFORM set_config('ottoq.run_scope_reads',
                         CASE WHEN v_seen = '' THEN ',' ELSE v_seen END || p_sim_run_id::text || ':' || p_param_key || ',', true);
    END IF;
    RETURN v;
  END IF;
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id=p_sim_run_id;
  IF v_depot IS NOT NULL THEN
    SELECT param_value INTO v FROM ottoq_policy_params
     WHERE scope_type='depot' AND scope_id=v_depot AND param_key=p_param_key;
    IF v IS NOT NULL THEN RETURN v; END IF;
  END IF;
  -- global tier: sentinel, not NULL (scope_id is in the primary key)
  SELECT param_value INTO v FROM ottoq_policy_params
   WHERE scope_type='global' AND scope_id='00000000-0000-0000-0000-000000000000'::uuid
     AND param_key=p_param_key;
  RETURN COALESCE(v, p_default);
END;
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_vehicle_is_tethered(p_vehicle_id uuid, p_now timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_until timestamptz;
  v_now   timestamptz;
BEGIN
  IF p_vehicle_id IS NULL THEN RETURN false; END IF;
  v_now := COALESCE(p_now, now());

  SELECT robotic_tether_until INTO v_until
    FROM public.vehicles WHERE id = p_vehicle_id;

  IF v_until IS NULL THEN RETURN false; END IF;
  RETURN v_until > v_now;
EXCEPTION WHEN OTHERS THEN
  -- Never propagate. See the note above on the failure direction.
  RETURN false;
END;
$function$;

CREATE OR REPLACE FUNCTION ottoq.ottoq_uplink_transfer_holds(p_vehicle uuid, p_run uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- 0695: an unfinished data transfer holds its car on the uplink stall it stands on (a charger or a service bay), as
  -- live work does: the car is not moved to its next work until the transfer ends (docs/DATA_OFFLOAD.md). False for
  -- every car while no run raises a transfer.
  -- 0758: the cleaning arm of the fast-charger stall a car stands on, at work in that car, holds it too (below).
  SELECT EXISTS (
    SELECT 1
      FROM public.vehicles v
      JOIN public.stalls s ON s.id = v.current_stall_id AND s.stall_type::text IN ('dcfc', 'l2', 'service_bay')
      JOIN public.ottoq_visit_needs vn ON vn.vehicle_id = v.id AND vn.sim_run_id IS NOT DISTINCT FROM p_run
                                      AND vn.status IN ('open', 'in_progress')
      CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
     WHERE v.id = p_vehicle
       AND ((COALESCE((a->>'needs_uplink')::boolean, false)
             AND COALESCE(a->>'status', 'pending') IN ('pending', 'in_progress'))
            -- 0758: and the cleaning arm of the stall the car stands on, at work in the car (its doors open, the arm in
            -- the cabin): the car stays until the arm's cycle ends. Only 0758's dial-on starter writes this performer.
            OR (a->>'performed_by' = 'stall_cabin_robot' AND a->>'status' = 'in_progress'
                AND a->>'robot_stall_id' = v.current_stall_id::text)))
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_arm_interlock_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_clock timestamptz;
BEGIN
  -- Not tethered after this statement -- including the case where this very
  -- statement is what lets go -- so the move is somebody's business, not ours.
  IF NEW.robotic_tether_until IS NULL THEN RETURN NEW; END IF;

  -- SIM CLOCK. The deadline was stamped from it; comparing against now() would
  -- treat every live tether in a sim-dated world as either eternal or expired.
  v_clock := COALESCE(
    (SELECT sim_clock_current FROM public.ottoq_sim_runs
      WHERE status = 'running' ORDER BY started_at DESC NULLS LAST LIMIT 1),
    now());

  IF NEW.robotic_tether_until <= v_clock THEN RETURN NEW; END IF;   -- expired
  -- Moving the car to the stall the arm is already holding it in is not a move.
  IF NEW.current_stall_id IS NOT DISTINCT FROM NEW.robotic_tether_stall_id THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION
    'arm interlock: vehicle % is held by the arm at stall % until % (sim %, %/%) — refusing to move it to %. Use twin.ottoq_arm_emergency_release() if the charger or arm has faulted.',
    NEW.id, NEW.robotic_tether_stall_id, NEW.robotic_tether_until, v_clock,
    COALESCE(NEW.robotic_tether_direction,'?'), COALESCE(NEW.robotic_tether_phase,'?'),
    COALESCE(NEW.current_stall_id::text, 'nowhere');
END;
$function$;

CREATE TRIGGER ottoq_arm_interlock BEFORE UPDATE OF current_stall_id ON public.vehicles FOR EACH ROW
  WHEN ((old.current_stall_id IS DISTINCT FROM new.current_stall_id)) EXECUTE FUNCTION ottoq_arm_interlock_guard();

CREATE OR REPLACE FUNCTION ottoq.ottoq_enact_space_assignment(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_stall_type text, p_purpose text, p_clock timestamp with time zone, p_until timestamp with time zone DEFAULT NULL::timestamp with time zone, p_leg_id uuid DEFAULT NULL::uuid, p_source text DEFAULT 'needs_card'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_cand RECORD; v_stall uuid; v_prev uuid; v_bkg uuid; v_until timestamptz; v_got boolean := false;
  v_pref uuid; v_honoured boolean := false;
  v_zones text[] := NULL;
  v_refused boolean := false; /* 0197 */
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_vehicle_id IS NULL
     OR p_stall_type IS NULL OR p_clock IS NULL THEN
    RETURN jsonb_build_object('assigned', false, 'reason', 'malformed');
  END IF;

  -- CHARGE-PATH FIREWALL
  IF p_stall_type IN ('dcfc','l2') THEN
    RAISE WARNING 'ottoq_enact_space_assignment: REFUSED charge stall_type % (run=%, vehicle=%, source=%) - charging is section (3) only',
      p_stall_type, p_sim_run_id, p_vehicle_id, p_source;
    RETURN jsonb_build_object('assigned', false, 'reason', 'charge_path_firewall');
  END IF;

  -- BUILD 3: INSPECTION IS ZONE-ADDRESSED
  IF p_purpose = 'inspect' THEN
    v_zones := ARRAY['arrival_inspection'];
  END IF;

  v_until := GREATEST(COALESCE(p_until, p_clock + interval '30 minutes'), p_clock + interval '1 minute');

  -- HONOUR THE FORWARD RESERVATION (only when it covers NOW)
  IF p_leg_id IS NOT NULL THEN
    SELECT b.stall_id INTO v_pref
      FROM public.ottoq_stall_bookings b
      JOIN public.stalls s ON s.id = b.stall_id
     WHERE b.sim_run_id = p_sim_run_id
       AND b.leg_id     = p_leg_id
       AND b.vehicle_id = p_vehicle_id
       AND b.state IN ('held','active')
       AND lower(b.during) <= p_clock
       AND upper(b.during) >  p_clock
       AND s.depot_id   = p_depot_id
       AND s.stall_type::text = p_stall_type
       AND (v_zones IS NULL OR s.zone = ANY (v_zones))
       AND s.status NOT IN ('maintenance','closed')
     ORDER BY b.booked_at DESC,
              lower(b.during) DESC, upper(b.during) DESC, s.id, b.purpose, b.booking_id DESC LIMIT 1;

    IF v_pref IS NOT NULL AND public.ottoq_reserve_stall(v_pref, p_vehicle_id, p_clock, 900) THEN
      v_stall := v_pref; v_got := true; v_honoured := true;
    END IF;
  END IF;

  -- CHOOSE
  IF NOT v_got THEN
    FOR v_cand IN
      SELECT f.stall_id
        FROM ottoq.ottoq_stall_free_between(
               p_sim_run_id, p_depot_id, p_clock, v_until, p_stall_type, NULL, 10, v_zones) f
    LOOP
      IF public.ottoq_reserve_stall(v_cand.stall_id, p_vehicle_id, p_clock, 900) THEN
        v_stall := v_cand.stall_id; v_got := true; EXIT;
      END IF;
    END LOOP;
  END IF;

  IF NOT v_got THEN
    RETURN jsonb_build_object('assigned', false, 'reason', 'no_free_space',
                              'stall_type', p_stall_type, 'purpose', p_purpose);
  END IF;

  SELECT v.current_stall_id INTO v_prev FROM public.vehicles v WHERE v.id = p_vehicle_id;

  -- 0197: ASSIGNMENT IS ALL OR NOTHING
  BEGIN /* 0197 */
    IF v_prev IS NOT NULL AND v_prev <> v_stall THEN
      UPDATE public.ottoq_stall_bookings
         SET state = 'done', released_at = p_clock, release_reason = 'vehicle_moved_to_next_leg',
             during = tstzrange(lower(during),
                                GREATEST(lower(during) + interval '1 second',
                                         LEAST(upper(during), p_clock)), '[)')
       WHERE sim_run_id = p_sim_run_id AND stall_id = v_prev
         AND vehicle_id = p_vehicle_id AND state IN ('held','active');
    END IF;

    UPDATE public.vehicles SET current_stall_id = v_stall WHERE id = p_vehicle_id;
    UPDATE public.stalls SET current_vehicle_id = p_vehicle_id, status = 'occupied' WHERE id = v_stall;

    v_bkg := ottoq.ottoq_record_enacted_booking(
               p_sim_run_id, v_stall, p_vehicle_id, p_clock,
               p_leg_id, p_clock, v_until, p_purpose, p_source);

    IF v_bkg IS NULL THEN
      RAISE EXCEPTION 'calendar refused the enacted booking' USING ERRCODE = 'OQ197'; /* 0197 */
    END IF;

    IF p_leg_id IS NOT NULL THEN
      UPDATE public.ottoq_itinerary_legs SET to_stall_id = v_stall
       WHERE leg_id = p_leg_id AND status = 'planned';
    END IF;
  EXCEPTION WHEN SQLSTATE 'OQ197' THEN
    v_refused := true; /* 0197 */
  END;

  IF v_refused THEN /* 0197 */
    UPDATE public.stalls
       SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
     WHERE id = v_stall AND reserved_by = p_vehicle_id;
    RAISE WARNING 'ottoq_enact_space_assignment: ROLLED BACK, calendar refused run=% vehicle=% stall=% type=% purpose=% source=%',
      p_sim_run_id, p_vehicle_id, v_stall, p_stall_type, p_purpose, p_source;
    RETURN jsonb_build_object('assigned', false, 'reason', 'booking_refused',
                              'stall_id', v_stall, 'stall_type', p_stall_type,
                              'purpose', p_purpose, 'source', p_source, 'leg_id', p_leg_id);
  END IF;

  RETURN jsonb_build_object('assigned', true, 'stall_id', v_stall, 'booking_id', v_bkg,
                            'booked', true, 'purpose', p_purpose,
                            'stall_type', p_stall_type, 'until', v_until,
                            'released_stall_id', v_prev, 'source', p_source,
                            'leg_id', p_leg_id, 'honoured_reservation', v_honoured);

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_enact_space_assignment: FAILED sqlstate=% msg=% run=% vehicle=% type=% purpose=% source=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_vehicle_id, p_stall_type, p_purpose, p_source;
  RETURN jsonb_build_object('assigned', false, 'reason', 'exception', 'sqlstate', SQLSTATE);
END
$function$;
