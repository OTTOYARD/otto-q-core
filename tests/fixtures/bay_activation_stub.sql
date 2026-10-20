-- tests/fixtures/bay_activation_stub.sql: the bay calendar's activation and reconcile as live, for
-- tests/test_bay_activation_per_seat_sql.py (db/migrations/0743) and tests/test_bay_hold_follows_charge_sql.py (0744).
-- Loaded after tests/fixtures/agent_charge_order_stub.sql, whose vehicles, stalls, bookings, runs and policy reader it
-- uses. Read from the live catalog on 2026-10-17 (the tests assert each md5 of prosrc):
--   ottoq.ottoq_activate_due_bay_reservations 4fb04e0a, ottoq.ottoq_reconcile_bay_reservations f6d8b538 (with its log,
--   public.bay_reservation_reconcile_2026_08_02, as live), ottoq.ottoq_vehicle_bay_ready f52356da,
--   ottoq.ottoq_uplink_transfer_holds e586ee27, public.ottoq_reserve_stall ac95d032, public.ottoq_vehicle_is_tethered 306c42af,
--   and the two vehicle triggers that move a car between stalls, public.sync_stall_occupancy db14b363 and
--   public.ottoq_arm_interlock_guard ac1e1c70, with the live index that gives a car one stall and the calendar's
--   no-overlap constraint. ottoq_record_event and ottoq_emit_vehicle_command are stand-ins that record their calls.
--   Arm 84's sweep and cell are the live rows 0743's P1 reads.
SET client_min_messages = warning;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE IF NOT EXISTS public.ottoq_itinerary_legs (
  leg_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sim_run_id uuid, vehicle_id uuid, seq integer, leg_type text,
  status text, planned_start_sim timestamptz, planned_end_sim timestamptz, actual_start_sim timestamptz,
  actual_end_sim timestamptz, to_stall_id uuid);

-- live: the reconcile's log
CREATE TABLE IF NOT EXISTS public.bay_reservation_reconcile_2026_08_02 (
  id bigserial PRIMARY KEY, logged_at timestamptz DEFAULT now(), sim_run_id uuid, booking_id uuid, vehicle_id uuid,
  stall_id uuid, purpose text, sim_clock timestamptz, action text, reason text, blocked_by text, old_from timestamptz,
  old_to timestamptz, new_from timestamptz, new_to timestamptz, defer_seq integer, eta timestamptz);

-- live: one stall per car, and the calendar's no-overlap constraint (ottoq_stall_bookings_no_overlap_v3)
CREATE UNIQUE INDEX IF NOT EXISTS idx_stalls_one_vehicle_per_stall ON public.stalls USING btree (current_vehicle_id)
  WHERE (current_vehicle_id IS NOT NULL);
ALTER TABLE public.ottoq_stall_bookings ADD CONSTRAINT ottoq_stall_bookings_no_overlap_v3
  EXCLUDE USING gist (sim_run_id WITH =, stall_id WITH =, during WITH &&)
  WHERE (((state = ANY (ARRAY['held'::text, 'active'::text, 'done'::text, 'interrupted'::text]))
          AND (booked_at >= '2026-08-02 03:19:00+00'::timestamp with time zone)));

CREATE TABLE IF NOT EXISTS public.ottoq_event_types_catalog (
  event_type text PRIMARY KEY, category text, description text, payload_schema jsonb, emitter text, default_severity text,
  introduced_in text, deprecated boolean DEFAULT false, created_at timestamptz DEFAULT now());

CREATE TABLE IF NOT EXISTS public.ottoq_throughput_sweeps (sweep_id uuid DEFAULT gen_random_uuid(), sweep_code text, title text,
  depot_id uuid, scenario text, sim_start timestamp with time zone, ticks integer, sim_min_per_tick numeric, seeds bigint[],
  replicates integer DEFAULT 1, priority integer DEFAULT 100, arm_budget_s integer, status text DEFAULT 'active'::text,
  run_after timestamp with time zone, notes text, created_by text DEFAULT 'research_wing'::text,
  created_at timestamp with time zone DEFAULT now(), concluded_at timestamp with time zone, fleet_code text);
CREATE TABLE IF NOT EXISTS public.ottoq_throughput_sweep_cells (cell_id uuid DEFAULT gen_random_uuid(), sweep_id uuid,
  cell_code text, ord integer, seat text, buildout_code text, fixed_params jsonb DEFAULT '{}'::jsonb, control_cell_code text);
INSERT INTO public.ottoq_throughput_sweeps (sweep_id, sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick,
                                            seeds, replicates, priority, arm_budget_s, status, created_at)
VALUES ('5a1b0e8c-7c3a-4d6e-9f1a-0743000000a4', 'dcfc40_power_normal_2026_10_17',
        'stub of the live row (2026-10-17): arm 84''s sweep', '11111111-1111-1111-1111-111111111111', 'normal_day',
        '2026-09-01 11:00:00+00', 144, 5, ARRAY[686364201590009433]::bigint[], 0, 16, 5400, 'active',
        '2026-10-17 07:31:42.87498+00');
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
VALUES ('5a1b0e8c-7c3a-4d6e-9f1a-0743000000a4', 'dcfc40.otto_q', 1, 'otto_q', 'dcfc40', '{"deploy_peak_fraction": 0.90}');

-- STAND-INS: they record their calls, so a test can read what the calendar did
CREATE TABLE public.test_bay_events (n bigserial PRIMARY KEY, event_type text, entity_id uuid, payload jsonb, severity text,
                                     sim_run_id uuid);
CREATE TABLE public.test_bay_commands (n bigserial PRIMARY KEY, sim_run_id uuid, vehicle_id uuid, verb text, payload jsonb,
                                       clock timestamptz);
CREATE OR REPLACE FUNCTION public.ottoq_record_event(
  p_actor_type text DEFAULT NULL, p_actor_id text DEFAULT NULL, p_event_type text DEFAULT NULL,
  p_entity_type text DEFAULT NULL, p_entity_id uuid DEFAULT NULL, p_payload jsonb DEFAULT NULL, p_severity text DEFAULT NULL,
  p_ingest_source text DEFAULT NULL, p_data_source text DEFAULT NULL, p_sim_run_id uuid DEFAULT NULL)
 RETURNS uuid LANGUAGE plpgsql
AS $function$
BEGIN
  INSERT INTO public.test_bay_events (event_type, entity_id, payload, severity, sim_run_id)
  VALUES (p_event_type, p_entity_id, p_payload, p_severity, p_sim_run_id);
  RETURN gen_random_uuid();
END $function$;
CREATE OR REPLACE FUNCTION public.ottoq_emit_vehicle_command(p_sim_run_id uuid, p_depot_id uuid, p_vehicle_id uuid, p_verb text,
                                                              p_payload jsonb, p_clock timestamptz)
 RETURNS uuid LANGUAGE plpgsql
AS $function$
BEGIN
  INSERT INTO public.test_bay_commands (sim_run_id, vehicle_id, verb, payload, clock)
  VALUES (p_sim_run_id, p_vehicle_id, p_verb, p_payload, p_clock);
  RETURN gen_random_uuid();
END $function$;

-- the live bodies (pg_get_functiondef headers, prosrc byte for byte)
CREATE OR REPLACE FUNCTION ottoq.ottoq_vehicle_bay_ready(p_sim_run_id uuid, p_vehicle_id uuid, p_clock timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_charge_end timestamptz;
BEGIN
  IF p_sim_run_id IS NULL OR p_vehicle_id IS NULL OR p_clock IS NULL THEN
    RETURN false;
  END IF;

  -- BLOCKER 1, verbatim from ottoq_reconcile_bay_reservations: an unfinished charge
  -- leg. Keyed off planned_end_sim rather than status because charge legs frequently
  -- never close (75 'active' vs 1 'done' in the phase-11 cert) -- status lies here.
  SELECT max(l.planned_end_sim) INTO v_charge_end
    FROM public.ottoq_itinerary_legs l
   WHERE l.sim_run_id = p_sim_run_id
     AND l.vehicle_id = p_vehicle_id
     AND l.leg_type IN ('charge_l2','charge_dcfc')
     AND l.status IN ('planned','active','in_progress')
     AND l.actual_end_sim IS NULL
     AND l.planned_end_sim > p_clock;

  RETURN v_charge_end IS NULL;
EXCEPTION WHEN OTHERS THEN
  RETURN false;   -- unknown readiness never seats a car early
END
$function$;
CREATE OR REPLACE FUNCTION ottoq.ottoq_uplink_transfer_holds(p_vehicle uuid, p_run uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- 0695: an unfinished data transfer holds its car on the uplink stall it stands on (a charger or a service bay), as
  -- live work does: the car is not moved to its next work until the transfer ends (docs/DATA_OFFLOAD.md). False for
  -- every car while no run raises a transfer.
  SELECT EXISTS (
    SELECT 1
      FROM public.vehicles v
      JOIN public.stalls s ON s.id = v.current_stall_id AND s.stall_type::text IN ('dcfc', 'l2', 'service_bay')
      JOIN public.ottoq_visit_needs vn ON vn.vehicle_id = v.id AND vn.sim_run_id IS NOT DISTINCT FROM p_run
                                      AND vn.status IN ('open', 'in_progress')
      CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
     WHERE v.id = p_vehicle AND COALESCE((a->>'needs_uplink')::boolean, false)
       AND COALESCE(a->>'status', 'pending') IN ('pending', 'in_progress'))
$function$;
CREATE OR REPLACE FUNCTION public.ottoq_reserve_stall(p_stall_id uuid, p_vehicle_id uuid, p_now timestamp with time zone, p_ttl_seconds integer DEFAULT 600)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_ok boolean;
BEGIN
  -- atomic: reserve only if free (no current vehicle, and no live reservation by another vehicle)
  UPDATE stalls
     SET reserved_by = p_vehicle_id, reserved_at = p_now,
         reservation_expires_at = p_now + (p_ttl_seconds || ' seconds')::interval
   WHERE id = p_stall_id
     AND current_vehicle_id IS NULL
     AND (reserved_by IS NULL OR reserved_by = p_vehicle_id
          OR reservation_expires_at IS NULL OR reservation_expires_at <= p_now)
  RETURNING true INTO v_ok;
  RETURN COALESCE(v_ok, false);
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
CREATE OR REPLACE FUNCTION public.sync_stall_occupancy()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  -- Clear old stall
  -- 0011-TETHER: ...unless a robot is still mated to it. Deliberately tested against
  -- NEW's own columns only -- no function call and no extra read, because this trigger
  -- fires on every vehicles UPDATE and must stay cheap and unable to raise.
  IF OLD.current_stall_id IS NOT NULL AND OLD.current_stall_id IS DISTINCT FROM NEW.current_stall_id
     AND NOT (NEW.robotic_tether_until IS NOT NULL
              AND NEW.robotic_tether_stall_id IS NOT DISTINCT FROM OLD.current_stall_id) THEN
    UPDATE stalls SET
      status = 'available',
      current_vehicle_id = NULL
    WHERE id = OLD.current_stall_id;
  END IF;

  -- Occupy new stall
  IF NEW.current_stall_id IS NOT NULL AND OLD.current_stall_id IS DISTINCT FROM NEW.current_stall_id THEN
    UPDATE stalls SET
      status = 'occupied',
      current_vehicle_id = NEW.id
    WHERE id = NEW.current_stall_id;
  END IF;

  RETURN NEW;
END;
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
CREATE OR REPLACE FUNCTION ottoq.ottoq_reconcile_bay_reservations(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_taxi   numeric; v_max_defer int; v_horizon numeric;
  v_step   int := 10;      -- forward walk granularity when the new window collides
  v_maxsh  int := 240;     -- bounded walk budget per booking per tick
  v_b      RECORD;
  v_dur    interval; v_eta timestamptz; v_blk text; v_block_at timestamptz; v_try timestamptz;
  v_ok     boolean; v_shift int; v_seq int;
  v_def    int := 0; v_rel int := 0; v_moved int := 0; v_left int := 0;
  v_alt    RECORD; v_newstall uuid;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_reservation_reconcile_enabled',1),1) < 1
    THEN RETURN 0; END IF;

  v_taxi      := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_taxi_min',3),3),0);
  v_max_defer := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_defer_max',8),8),1)::int;
  v_horizon   := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'bay_defer_horizon_min',480),480),30);

  FOR v_b IN
    SELECT b.booking_id, b.vehicle_id, b.stall_id, b.purpose, b.leg_id,
           lower(b.during) AS lo, upper(b.during) AS hi,
           v.current_state::text AS vstate, v.config AS vcfg,
           s.depot_id AS depot_id, s.stall_type AS stall_type,
           (s.current_vehicle_id IS NULL
            AND (s.reserved_by IS NULL OR s.reserved_by = b.vehicle_id)
            AND s.status NOT IN ('maintenance','closed'))  AS stall_free_now
      FROM public.ottoq_stall_bookings b
      JOIN public.stalls   s ON s.id = b.stall_id
      JOIN public.vehicles v ON v.id = b.vehicle_id
     WHERE b.sim_run_id = p_sim_run_id
       AND b.state = 'held'
       AND s.depot_id = p_depot_id
       AND s.stall_type IN ('wash_bay'::stall_type,'service_bay'::stall_type)
       AND lower(b.during) <= p_clock + make_interval(mins => v_taxi::int)
       AND v.current_stall_id IS DISTINCT FROM b.stall_id
     ORDER BY lower(b.during), upper(b.during), b.vehicle_id, b.stall_id, b.purpose, b.booking_id  /* 0130 */
  LOOP
    v_dur := v_b.hi - v_b.lo;
    v_block_at := NULL; v_blk := NULL;

    -- ══════════ 0015 VEHICLE-FIRST PRE-EMPTION -- MUST BE THE FIRST TEST ══════════
    -- The car is standing here, idle, owes no charge leg, and its own booked bay is
    -- physically empty. There is nothing to reconcile: ottoq_activate_due_bay_reservations
    -- seats it later in THIS SAME TICK (decide_tick line 45 reconcile, line 47 activate).
    -- Deferring or releasing it here is precisely how 96 holds died `replanned_no_window`
    -- while the bays they pointed at sat empty. Leave it completely alone.
    IF v_b.stall_free_now
       AND v_b.vstate IN ('arrived_at_gate','staged_awaiting_service',
                          'charge_complete_holding','service_complete_holding')
       AND ottoq.ottoq_vehicle_bay_ready(p_sim_run_id, v_b.vehicle_id, p_clock)
    THEN
      v_left := v_left + 1;
      CONTINUE;
    END IF;

    -- ── the vehicle is not even in the depot: the reservation is dead.
    IF v_b.vstate IN ('offline','deployed','en_route_to_deployment','out_of_service','tow_requested') THEN
      UPDATE public.ottoq_stall_bookings
         SET state='released', released_at=p_clock, release_reason='replanned_vehicle_absent'
       WHERE booking_id = v_b.booking_id AND state='held';
      INSERT INTO public.bay_reservation_reconcile_2026_08_02
        (sim_run_id,booking_id,vehicle_id,stall_id,purpose,sim_clock,action,reason,blocked_by,
         old_from,old_to,defer_seq)
      VALUES (p_sim_run_id,v_b.booking_id,v_b.vehicle_id,v_b.stall_id,v_b.purpose,p_clock,
              'released','replanned_vehicle_absent',v_b.vstate,v_b.lo,v_b.hi,NULL);
      v_rel := v_rel + 1;
      CONTINUE;
    END IF;

    -- ── BLOCKER 1: an unfinished charge leg. Keyed off planned_end_sim rather than
    --    leg status, because charge legs frequently never close.
    SELECT max(l.planned_end_sim) INTO v_try
      FROM public.ottoq_itinerary_legs l
     WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_b.vehicle_id
       AND l.leg_type IN ('charge_l2','charge_dcfc')
       AND l.status IN ('planned','active','in_progress')
       AND l.actual_end_sim IS NULL
       AND l.planned_end_sim > p_clock;
    IF v_try IS NOT NULL THEN v_block_at := v_try; v_blk := 'charging'; END IF;

    -- ── BLOCKER 2: still standing in a different bay.
    IF v_b.vstate IN ('in_wash_bay','in_detail_bay','in_service_bay') THEN
      v_try := GREATEST(COALESCE(NULLIF(v_b.vcfg->>'service_ends_at','null')::timestamptz, p_clock), p_clock);
      IF v_block_at IS NULL OR v_try > v_block_at THEN v_block_at := v_try; END IF;
      v_blk := COALESCE(v_blk||'+','') || 'in_other_bay';
    END IF;

    -- ── BLOCKER 3: NARROWED BY 0015 TO remedy='need_charge'.
    --    twin.ottoq_sim_advance_service_flow pins a vehicle in staging with
    --    config.deploy_gate. remedy='need_service' means MUST-DO WORK IS OPEN --
    --    which is the very reason this bay booking exists. Blocking the booking on
    --    that gate made the gate un-clearable: the gate holds the car for want of the
    --    service, the reconcile withholds the service for want of the gate clearing.
    --    MEASURED: 52 defers + 10 relocations + 9 `replanned_no_window` releases +
    --    3 `replanned_defer_cap` releases attributed to deploy_gate:need_service alone.
    --    need_charge still blocks (conservative: it is arguably already covered by
    --    BLOCKER 1, but 0015 does not need that to be true).
    IF v_b.vcfg ? 'deploy_gate'
       AND COALESCE(v_b.vcfg#>>'{deploy_gate,remedy}','') = 'need_charge' THEN
      v_try := p_clock + make_interval(mins => v_taxi::int);
      IF v_block_at IS NULL OR v_try > v_block_at THEN v_block_at := v_try; END IF;
      v_blk := COALESCE(v_blk||'+','') || 'deploy_gate:need_charge';
    END IF;

    IF v_block_at IS NULL THEN CONTINUE; END IF;

    v_eta := v_block_at + make_interval(mins => v_taxi::int);
    IF v_eta <= v_b.lo THEN CONTINUE; END IF;

    SELECT count(*) INTO v_seq
      FROM public.bay_reservation_reconcile_2026_08_02 r
     WHERE r.booking_id = v_b.booking_id AND r.action = 'deferred';

    IF v_seq >= v_max_defer OR v_eta > v_b.lo + make_interval(mins => v_horizon::int) THEN
      UPDATE public.ottoq_stall_bookings
         SET state='released', released_at=p_clock,
             release_reason = CASE WHEN v_seq >= v_max_defer
                                   THEN 'replanned_defer_cap' ELSE 'replanned_beyond_horizon' END
       WHERE booking_id = v_b.booking_id AND state='held';
      INSERT INTO public.bay_reservation_reconcile_2026_08_02
        (sim_run_id,booking_id,vehicle_id,stall_id,purpose,sim_clock,action,reason,blocked_by,
         old_from,old_to,defer_seq,eta)
      VALUES (p_sim_run_id,v_b.booking_id,v_b.vehicle_id,v_b.stall_id,v_b.purpose,p_clock,'released',
              CASE WHEN v_seq >= v_max_defer THEN 'replanned_defer_cap' ELSE 'replanned_beyond_horizon' END,
              v_blk,v_b.lo,v_b.hi,v_seq,v_eta);
      v_rel := v_rel + 1;
      CONTINUE;
    END IF;

    -- ── DEFER: slide the window to when the vehicle can ACTUALLY be there.
    v_ok := false; v_shift := 0; v_newstall := NULL;
    WHILE NOT v_ok AND v_shift <= v_maxsh LOOP
      v_try := v_eta + make_interval(mins => v_shift);
      BEGIN
        UPDATE public.ottoq_stall_bookings
           SET during = tstzrange(v_try, v_try + v_dur, '[)')
         WHERE booking_id = v_b.booking_id AND state = 'held';
        v_ok := true; v_newstall := v_b.stall_id;
      EXCEPTION WHEN exclusion_violation THEN
        FOR v_alt IN
          SELECT s2.id
            FROM public.stalls s2
           WHERE s2.depot_id   = v_b.depot_id
             AND s2.stall_type = v_b.stall_type
             AND s2.status NOT IN ('maintenance','closed')
             AND s2.id <> v_b.stall_id
           ORDER BY s2.distance_from_entrance NULLS LAST, s2.id
        LOOP
          BEGIN
            UPDATE public.ottoq_stall_bookings
               SET stall_id = v_alt.id, during = tstzrange(v_try, v_try + v_dur, '[)')
             WHERE booking_id = v_b.booking_id AND state = 'held';
            v_ok := true; v_newstall := v_alt.id;
            EXIT;
          EXCEPTION WHEN exclusion_violation THEN
            NULL;
          END;
        END LOOP;
        IF NOT v_ok THEN v_shift := v_shift + v_step; END IF;
      END;
    END LOOP;

    IF v_ok THEN
      IF v_newstall IS DISTINCT FROM v_b.stall_id THEN v_moved := v_moved + 1; END IF;
      IF v_b.leg_id IS NOT NULL THEN
        UPDATE public.ottoq_itinerary_legs
           SET planned_start_sim = v_try, planned_end_sim = v_try + v_dur
         WHERE leg_id = v_b.leg_id AND status = 'planned';
      END IF;
      INSERT INTO public.bay_reservation_reconcile_2026_08_02
        (sim_run_id,booking_id,vehicle_id,stall_id,purpose,sim_clock,action,reason,blocked_by,
         old_from,old_to,new_from,new_to,defer_seq,eta)
      VALUES (p_sim_run_id,v_b.booking_id,v_b.vehicle_id,COALESCE(v_newstall,v_b.stall_id),v_b.purpose,p_clock,'deferred',
              CASE WHEN v_newstall IS DISTINCT FROM v_b.stall_id
                   THEN 'vehicle_not_yet_releasable_relocated_bay'
                   ELSE 'vehicle_not_yet_releasable' END,
              v_blk,v_b.lo,v_b.hi,v_try,v_try+v_dur,v_seq+1,v_eta);
      v_def := v_def + 1;
    ELSE
      UPDATE public.ottoq_stall_bookings
         SET state='released', released_at=p_clock, release_reason='replanned_no_window'
       WHERE booking_id = v_b.booking_id AND state='held';
      INSERT INTO public.bay_reservation_reconcile_2026_08_02
        (sim_run_id,booking_id,vehicle_id,stall_id,purpose,sim_clock,action,reason,blocked_by,
         old_from,old_to,defer_seq,eta)
      VALUES (p_sim_run_id,v_b.booking_id,v_b.vehicle_id,v_b.stall_id,v_b.purpose,p_clock,'released',
              'replanned_no_window',v_blk,v_b.lo,v_b.hi,v_seq,v_eta);
      v_rel := v_rel + 1;
    END IF;
  END LOOP;

  IF v_def > 0 OR v_rel > 0 OR v_left > 0 THEN
   BEGIN
    PERFORM public.ottoq_record_event(
      p_actor_type := 'ottoq_engine', p_actor_id := 'bay_reservation_reconcile',
      p_event_type := 'ottoq.bay_reservation_replanned', p_entity_type := 'depot',
      p_entity_id := p_depot_id,
      p_payload := jsonb_build_object('deferred',v_def,'released',v_rel,'relocated',v_moved,
        'left_for_early_activation',v_left,
        'taxi_min',v_taxi,'defer_max',v_max_defer,'horizon_min',v_horizon,
        'note','a reservation is honoured or re-planned; it is never left to rot. '
               'left_for_early_activation = the car is ready and its bay is free, so '
               'reconcile stood down and activation seats it this same tick'),
      p_severity := CASE WHEN v_rel > 0 THEN 'warning' ELSE 'info' END,
      p_ingest_source := 'ottoq', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
   EXCEPTION WHEN OTHERS THEN
     RAISE WARNING 'bay_reservation_reconcile: summary event not written (%): %', SQLSTATE, SQLERRM;
   END;
  END IF;

  RETURN v_def + v_rel;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_reconcile_bay_reservations: FAILED sqlstate=% msg=% run=% depot=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_depot_id;
  RETURN 0;
END
$function$;
CREATE OR REPLACE FUNCTION ottoq.ottoq_activate_due_bay_reservations(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_res record; v_n int := 0; v_prev uuid; v_state text; v_verb text;
        v_early int := 0; v_declined int := 0; v_rebased boolean;
        v_end_ts timestamptz;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;

  FOR v_res IN
    SELECT b.booking_id, b.vehicle_id, b.stall_id, b.purpose, b.leg_id,
           s.stall_type::text AS stall_type,
           (lower(b.during) <= p_clock)   AS in_window,
           (upper(b.during) - lower(b.during)) AS dur,
           upper(b.during)                AS win_end
      FROM public.ottoq_stall_bookings b
      JOIN public.stalls   s ON s.id = b.stall_id
      JOIN public.vehicles v ON v.id = b.vehicle_id
     WHERE b.sim_run_id = p_sim_run_id
       AND b.state      = 'held'
       AND s.depot_id   = p_depot_id
       AND s.stall_type IN ('wash_bay'::stall_type,'detail_bay'::stall_type,'service_bay'::stall_type)
       AND s.status NOT IN ('maintenance','closed')
       -- 0015: THE WINDOW GATE, NARROWED
       -- UNCHANGED: a hold whose window has already lapsed never seats. The grace
       -- sweep in ottoq_release_vacated_spaces owns that row.
       AND upper(b.during) >  p_clock
       -- WAS: AND lower(b.during) <= p_clock   ("not before the forecast")
       -- NOW: in window, OR the car is ready. VEHICLE-FIRST -- a free bay beats a
       -- prediction. The physical-presence guarantee the lower bound used to give is
       -- carried entirely by the v.current_state predicate below, which already means
       -- "standing in this depot, idle, not in another bay, not faulted"; readiness
       -- adds the one thing it misses -- no unfinished charge leg.
       AND ( lower(b.during) <= p_clock
             OR ottoq.ottoq_vehicle_bay_ready(p_sim_run_id, b.vehicle_id, p_clock) )
       -- the bay is physically free for this car
       AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reserved_by = b.vehicle_id)
       -- the car is HOME and IDLE. Never interrupt live work; never touch a fault state.
       -- This is also the in-depot reassignment gate: a car that is IN a bay, charging,
       -- deployed or faulted is not in this list, so 0015 can never re-route it.
       AND v.home_depot_id = p_depot_id
       AND v.current_state IN ('arrived_at_gate'::vehicle_state,
                               'staged_awaiting_service'::vehicle_state,
                               'charge_complete_holding'::vehicle_state,
                               'service_complete_holding'::vehicle_state)
       -- 0695: and not a car whose data transfer holds it on its uplink stall: that is live work too
       AND NOT ottoq.ottoq_uplink_transfer_holds(b.vehicle_id, p_sim_run_id)
     -- CONTENTION ORDER: due-now beats early; then earliest forecast; then the PK,
     -- so the order is total and stable across ticks.
     ORDER BY (lower(b.during) <= p_clock) DESC, lower(b.during), b.vehicle_id, b.stall_id /* 0195 */
     -- 0195: never the row's own uuid. It is drawn fresh every run, and two arms of
     -- one pair broke every tie on lower(during) differently (db/checks/0110).
  LOOP
    -- CAS the stall. If someone else took it first, leave the reservation alone and
    -- let the existing grace/replan path deal with it -- we never force.
    -- 0195: the cursor is a snapshot. A car this same batch already seated is no
    -- longer holding; seating it again puts one car in two stalls, the unique index
    -- refuses, and the handler below throws the WHOLE tick's seats away.
    CONTINUE WHEN NOT EXISTS (
      SELECT 1 FROM public.vehicles vv
       WHERE vv.id = v_res.vehicle_id AND vv.home_depot_id = p_depot_id
         AND vv.current_state IN ('arrived_at_gate'::vehicle_state, 'staged_awaiting_service'::vehicle_state,
                                  'charge_complete_holding'::vehicle_state, 'service_complete_holding'::vehicle_state)); /* 0195 */
    CONTINUE WHEN NOT public.ottoq_reserve_stall(v_res.stall_id, v_res.vehicle_id, p_clock, 900);

    -- 0015: REBASE THE WINDOW ON AN EARLY SEAT
    -- Duration preserved exactly. The exclusion constraints adjudicate displacement:
    -- if any other held/active/done/interrupted booking on this stall already owns
    -- part of [now, now+dur) we DECLINE the early seat outright -- we never push and
    -- never drop the other booking -- and hand the stall reservation back.
    v_rebased := true;
    IF NOT v_res.in_window THEN
      BEGIN
        UPDATE public.ottoq_stall_bookings
           SET during = tstzrange(p_clock, p_clock + v_res.dur, '[)')
         WHERE booking_id = v_res.booking_id AND state = 'held';
      EXCEPTION WHEN exclusion_violation THEN
        v_rebased := false;
      END;
    END IF;

    IF NOT v_rebased THEN
      UPDATE public.stalls
         SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
       WHERE id = v_res.stall_id
         AND reserved_by = v_res.vehicle_id
         AND current_vehicle_id IS NULL;
      v_declined := v_declined + 1;
      CONTINUE;
    END IF;

    v_state := CASE
                 WHEN v_res.stall_type = 'service_bay' THEN 'in_service_bay'
                 WHEN v_res.purpose    = 'detail'      THEN 'in_detail_bay'
                 WHEN v_res.stall_type = 'detail_bay'  THEN 'in_detail_bay'
                 ELSE 'in_wash_bay' END;
    v_verb  := CASE WHEN v_state = 'in_service_bay' THEN 'enter_service' ELSE 'enter_wash' END;

    -- Close out whatever space the car is vacating (same contract as enact_space_assignment).
    SELECT vv.current_stall_id INTO v_prev FROM public.vehicles vv WHERE vv.id = v_res.vehicle_id;
    IF v_prev IS NOT NULL AND v_prev <> v_res.stall_id THEN
      UPDATE public.ottoq_stall_bookings
         SET state = 'done', released_at = p_clock,
             release_reason = 'vehicle_moved_to_next_leg',
             during = tstzrange(lower(during),
                        GREATEST(lower(during) + interval '1 second',
                                 LEAST(upper(during), p_clock)), '[)')
       WHERE sim_run_id = p_sim_run_id AND stall_id = v_prev
         AND vehicle_id = v_res.vehicle_id AND state IN ('held','active');
    END IF;

    -- OCCUPY.
    -- 0016: and carry the TWIN'S SERVICE CONTRACT with it. Writing current_state
    -- without config->>'service_ends_at' left this seam PARTIAL: twin's
    -- ottoq_sim_advance_service_flow STEP 1 reads a null timer on an in-bay car as
    -- "null-timer stuck" and self-heals it to complete on the next tick, which turned
    -- a 38-minute service into 2 minutes. These are the same two keys the twin's own
    -- admission writes, so a bay-seated car behaves identically either way.
    -- Pinned to the booking's own window end -> booking, leg and twin timer agree.
    -- Floored 1 minute ahead so a seat can never complete on the tick that made it.
    v_end_ts := GREATEST(
                  CASE WHEN v_res.in_window THEN v_res.win_end
                       ELSE p_clock + v_res.dur END,
                  p_clock + interval '1 minute');
    UPDATE public.vehicles
       SET current_stall_id = v_res.stall_id,
           current_state    = v_state::vehicle_state,
           last_state_change = p_clock,
           config = jsonb_set(
                      jsonb_set(COALESCE(config, '{}'::jsonb),
                                '{svc_step}',
                                to_jsonb(CASE WHEN v_state = 'in_service_bay'
                                              THEN 'servicing' ELSE 'washing' END)),
                      '{service_ends_at}', to_jsonb(v_end_ts::text))
     WHERE id = v_res.vehicle_id;
    UPDATE public.stalls
       SET current_vehicle_id = v_res.vehicle_id, status = 'occupied'
     WHERE id = v_res.stall_id;

    -- The reservation is now a REAL occupancy, and is stamped so provenance can see
    -- that it was activated rather than booked fresh -- and, from 0015, whether the
    -- free bay beat the forecast.
    UPDATE public.ottoq_stall_bookings
       SET state = 'active', booked_by = 'otto_q_enacted',
           source = CASE WHEN v_res.in_window THEN 'bay_reservation_activated'
                         ELSE 'bay_reservation_activated_early' END
     WHERE booking_id = v_res.booking_id;

    IF v_res.leg_id IS NOT NULL THEN
      -- keep the leg in lockstep with the (possibly rebased) booking: ottoq_stall_free_between
      -- reads planned_end_sim, so a booking and its leg must never disagree.
      UPDATE public.ottoq_itinerary_legs
         SET to_stall_id = v_res.stall_id, status = 'active',
             planned_start_sim = CASE WHEN v_res.in_window THEN planned_start_sim ELSE p_clock END,
             planned_end_sim   = CASE WHEN v_res.in_window THEN planned_end_sim   ELSE p_clock + v_res.dur END,
             actual_start_sim  = COALESCE(actual_start_sim, p_clock)
       WHERE leg_id = v_res.leg_id AND status = 'planned';
    END IF;

    BEGIN
      PERFORM public.ottoq_emit_vehicle_command(
        p_sim_run_id, p_depot_id, v_res.vehicle_id, v_verb,
        jsonb_build_object('stall_id',   v_res.stall_id,
                           'booking_id', v_res.booking_id,
                           'leg_id',     v_res.leg_id,
                           'purpose',    v_res.purpose,
                           'via',        CASE WHEN v_res.in_window
                                              THEN 'bay_reservation_activated'
                                              ELSE 'bay_reservation_activated_early' END), p_clock);
    EXCEPTION WHEN OTHERS THEN NULL;  -- an un-emitted command must never cost the move
    END;

    IF NOT v_res.in_window THEN v_early := v_early + 1; END IF;
    v_n := v_n + 1;
  END LOOP;

  -- ONE summary event per tick (event-write amplification is the known tick-cost driver).
  IF v_early > 0 OR v_declined > 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'bay_reservation_early_activation',
        p_event_type := 'ottoq.bay_reservation_activated_early', p_entity_type := 'depot',
        p_entity_id := p_depot_id,
        p_payload := jsonb_build_object(
          'seated_early', v_early, 'declined_would_displace', v_declined, 'seated_total', v_n,
          'note','a ready car took a free bay ahead of its forecast window; declined means a '
                 'later booking on that stall already owned the time, so the early seat was refused'),
        p_severity := 'info',
        p_ingest_source := 'ottoq', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  RETURN v_n;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_activate_due_bay_reservations: FAILED sqlstate=% msg=% run=% depot=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_depot_id;
  RETURN 0;
END
$function$;

-- the live triggers that move a car between stalls
CREATE TRIGGER ottoq_arm_interlock BEFORE UPDATE OF current_stall_id ON public.vehicles FOR EACH ROW
  WHEN ((old.current_stall_id IS DISTINCT FROM new.current_stall_id)) EXECUTE FUNCTION ottoq_arm_interlock_guard();
CREATE TRIGGER trg_sync_stall_occupancy AFTER UPDATE ON public.vehicles FOR EACH ROW EXECUTE FUNCTION sync_stall_occupancy();
