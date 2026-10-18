-- tests/fixtures/opportunistic_scan_stub.sql: the twin technician's verdict loop as live, for
-- tests/test_production_technician_sql.py (db/migrations/0751, G465). Loaded after
-- tests/fixtures/agent_charge_order_stub.sql, whose vehicles, stalls, runs and target reader it uses. Read from the live
-- catalog on 2026-10-18 between 12:37 and 12:55 AM CT (the test asserts each md5 of prosrc):
--   twin.ottoq_opportunistic_scan fce0e060, twin.ottoq_sim_seeded_random 237b754a,
-- the depots' feed mode and the ops approvals table with their live columns and constraints (its visit key, which needs
-- the visit table's primary key, aside). Four stand-ins, noted where defined: the feed plan, the planner that raises
-- top-off questions, the top-off's enactment and the arm's refusal; each records its call in
-- public.scan_stub_calls so the test can see what the scan did and did not reach.
SET client_min_messages = warning;

CREATE TABLE IF NOT EXISTS public.depots (id uuid PRIMARY KEY, feed_mode text,
  CONSTRAINT chk_depot_feed_mode CHECK (feed_mode = ANY (ARRAY['sim'::text, 'external'::text])));
INSERT INTO public.depots (id, feed_mode) VALUES ('11111111-1111-1111-1111-111111111111', 'sim') ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.ottoq_ops_approvals (
  approval_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  approval_type text NOT NULL
    CONSTRAINT ottoq_ops_approvals_approval_type_check
    CHECK (approval_type = ANY (ARRAY['opportunistic_charge'::text, 'tech_greenlight'::text, 'indepot_reassign'::text])),
  vehicle_id uuid NOT NULL REFERENCES public.vehicles (id), visit_id uuid,
  sim_run_id uuid REFERENCES public.ottoq_sim_runs (sim_run_id), depot_id uuid,
  status text NOT NULL DEFAULT 'pending'
    CONSTRAINT ottoq_ops_approvals_status_check
    CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'declined'::text, 'expired'::text])),
  priority text NOT NULL DEFAULT 'normal'
    CONSTRAINT ottoq_ops_approvals_priority_check CHECK (priority = ANY (ARRAY['normal'::text, 'high'::text])),
  payload jsonb, requested_at timestamptz NOT NULL, decide_after timestamptz, expires_at timestamptz,
  decided_at timestamptz, decided_by text, created_at timestamptz NOT NULL DEFAULT now());

CREATE TABLE IF NOT EXISTS public.scan_stub_calls (n bigserial PRIMARY KEY, fn text, vehicle_id uuid, args jsonb);
CREATE TABLE IF NOT EXISTS public.scan_stub_plan (plan jsonb);
CREATE TABLE IF NOT EXISTS public.scan_stub_enact (vehicle_id uuid PRIMARY KEY, stall_id uuid);

-- stand-in: the live plan is the twin's feed plan; here the test sets it (empty: the scan's own 0.70 and 0.92)
CREATE OR REPLACE FUNCTION public.ottoq_feed_plan(p_stream text) RETURNS jsonb LANGUAGE sql STABLE
AS $$ SELECT COALESCE((SELECT plan FROM public.scan_stub_plan LIMIT 1), '{}'::jsonb) $$;

-- stand-in: the live planner raises top-off questions; here it raises none and records that it was asked
CREATE OR REPLACE FUNCTION ottoq.ottoq_plan_opportunistic_charges(p_sim_run_id uuid, p_depot_id uuid,
                                                                  p_clock timestamp with time zone, p_seed bigint)
RETURNS jsonb LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.scan_stub_calls (fn, args)
  VALUES ('plan', jsonb_build_object('run', p_sim_run_id, 'depot', p_depot_id, 'clock', p_clock));
  RETURN jsonb_build_object('raised', 0);
END $$;

-- stand-in: the live enactment books and starts the top-off; here it records the call and names the stall the test set
CREATE OR REPLACE FUNCTION ottoq.ottoq_enact_opportunistic_charge(p_sim_run_id uuid, p_vehicle_id uuid,
                                                                  p_current_soc numeric, p_target_soc numeric,
                                                                  p_clock timestamp with time zone)
RETURNS jsonb LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.scan_stub_calls (fn, vehicle_id, args)
  VALUES ('enact', p_vehicle_id, jsonb_build_object('soc', p_current_soc, 'target', p_target_soc, 'clock', p_clock));
  RETURN jsonb_build_object('stall_id', (SELECT e.stall_id FROM public.scan_stub_enact e WHERE e.vehicle_id = p_vehicle_id));
END $$;

-- stand-in: the live gate asks the charging arm; here no arm refuses, and the question is recorded
CREATE OR REPLACE FUNCTION twin.ottoq_arm_refuse_move(p_vehicle_id uuid, p_mover text, p_stall uuid, p_sim_run_id uuid,
                                                      p_clock timestamp with time zone)
RETURNS boolean LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.scan_stub_calls (fn, vehicle_id, args) VALUES ('arm', p_vehicle_id, jsonb_build_object('stall', p_stall));
  RETURN false;
END $$;

-- live: twin.ottoq_sim_seeded_random (prosrc md5 237b754ac865e17e0876a5df7af979b2)
CREATE OR REPLACE FUNCTION twin.ottoq_sim_seeded_random(p_seed bigint, p_salt text)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_hash BIGINT;
BEGIN
  -- Combine seed + salt into a deterministic hash, normalize to [0,1)
  v_hash := abs(hashtextextended(p_seed::text || ':' || p_salt, p_seed));
  RETURN (v_hash % 1000000)::NUMERIC / 1000000.0;
END;
$function$;

-- live: twin.ottoq_opportunistic_scan (prosrc md5 fce0e0609ef96ad49de836f95620b1f1)
CREATE OR REPLACE FUNCTION twin.ottoq_opportunistic_scan(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_seed bigint; v_plan jsonb; v_appr_p numeric; v_gl_p numeric;
  v_rec RECORD; v_n int := 0;
  v_p numeric; v_scan jsonb; v_enact jsonb; v_stall uuid;
BEGIN
  SELECT depot_id, COALESCE(random_seed,42) INTO v_depot, v_seed FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;
  v_plan := ottoq_feed_plan('service_manifest');
  v_appr_p := COALESCE((v_plan->>'opportunistic_approve_p')::numeric, 0.70);
  v_gl_p := COALESCE((v_plan->>'greenlight_approve_p')::numeric, 0.92);

  -- OTTO-Q owns the decision half
  v_scan := ottoq_plan_opportunistic_charges(p_sim_run_id, v_depot, p_clock, v_seed);
  v_n := COALESCE((v_scan->>'raised')::int, 0);

  -- TWIN: the simulated tech verdict
  FOR v_rec IN
    SELECT ap.approval_id, ap.approval_type, ap.vehicle_id, ap.requested_at, v.current_soc, COALESCE(v.target_soc, public.ottoq_default_target_soc()) AS veh_target,
           ap.payload #>> '{operator_verdict,verdict}' AS op_verdict,   -- 0487: the crew's verdict, if any
           ap.payload #>> '{operator_verdict,by}' AS op_by
      FROM ottoq_ops_approvals ap JOIN vehicles v ON v.id = ap.vehicle_id
     WHERE ap.depot_id = v_depot AND ap.status = 'pending'
       -- ══════ 0002: OWNERSHIP, MADE EXPLICIT INSTEAD OF ACCIDENTAL ══════
       -- This cursor was never type-filtered. It only knows TWO probabilities (line
       -- below: tech_greenlight vs everything-else), so if it ever reached an
       -- 'indepot_reassign' row it would settle a DOCTRINE GATE on a coin flip.
       -- Until now it was stopped only by an accident -- the real-vs-sim clock
       -- mismatch on decide_after. Migration 0002 removes that accident, so the
       -- filter has to become deliberate. The twin's simulated technician decides
       -- the twin's own questions; OTTO-Q decides the in-depot reassignment gate
       -- (public.ottoq_decide_indepot_approvals).
       AND ap.approval_type IN ('opportunistic_charge','tech_greenlight')
       AND ap.decide_after <= p_clock AND ap.expires_at > p_clock
     -- 0104: run-stable total order; the heap decided who charged where.
     ORDER BY ap.requested_at, ap.vehicle_id, ap.approval_type
  LOOP
    v_p := (CASE WHEN v_rec.approval_type = 'tech_greenlight' THEN v_gl_p ELSE v_appr_p END);
    -- 0487: THE CREW DECIDES FIRST. A verdict recorded by ottoq_ops_approval_decide replaces the simulated
    -- technician's draw and takes this same path, so an approved top-off is enacted exactly as a drawn one.
    -- With no verdict the draw is the only term, which is every certified run.
    IF COALESCE(v_rec.op_verdict = 'approved',
                ottoq_sim_seeded_random(v_seed, 'techdecide:' || v_rec.vehicle_id::text || ':' || v_rec.approval_type || ':' || extract(epoch from v_rec.requested_at)::bigint::text) < v_p) THEN
      UPDATE ottoq_ops_approvals SET status='approved', decided_at=p_clock, decided_by=COALESCE('operator:' || v_rec.op_by, 'twin_tech_sim')
       WHERE approval_id = v_rec.approval_id;
      IF v_rec.approval_type = 'opportunistic_charge' THEN
        UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state,
               last_state_change = p_clock
         WHERE id = v_rec.vehicle_id
           AND current_state IN ('staged_awaiting_service','staged_for_departure','charge_complete_holding');
        -- 0535 (G259): ONLY A CAR STILL WAITING GETS THE TOP-OFF. The approval was raised when the car was waiting and
        -- decided later; a car that has since moved on (into a bay, onto the road) is not moved again. It was: into a
        -- charger out of the wash bay it was being washed in, which the reassignment guard will not vacate, and the tick
        -- failed on idx_stalls_one_vehicle_per_stall (db/checks/0399 §2). The state update above is the test.
        IF NOT FOUND THEN
          UPDATE ottoq_ops_approvals
             SET status = 'expired',
                 payload = COALESCE(payload, '{}'::jsonb)
                        || jsonb_build_object('expired_reason', 'vehicle_moved_on', 'expired_at', p_clock,
                                              'vehicle_state', (SELECT v.current_state::text FROM vehicles v WHERE v.id = v_rec.vehicle_id))
           WHERE approval_id = v_rec.approval_id;
          CONTINUE;
        END IF;

        v_enact := ottoq_enact_opportunistic_charge(p_sim_run_id, v_rec.vehicle_id,
                     v_rec.current_soc, v_rec.veh_target, p_clock);

        v_stall := NULLIF(v_enact->>'stall_id','')::uuid;
        -- ASK THE ARM FIRST. This function runs before ottoq_arm_advance_cycles in
        -- the same tick, and its candidate state 'charge_complete_holding' IS the
        -- demate window -- so without this it can drive a car away with the arm
        -- still physically attached. A gate that can only remove a candidate; the
        -- refusal is recorded so a car that looks frozen has a reason on the record.
        IF v_stall IS NOT NULL
           AND twin.ottoq_arm_refuse_move(v_rec.vehicle_id, 'opportunistic_scan',
                                          v_stall, p_sim_run_id, p_clock) THEN
          v_stall := NULL;
        END IF;
        IF v_stall IS NOT NULL THEN
          -- ONE STALL PER VEHICLE, AND THE RELEASE COMES FIRST. The claim below is
          -- the statement that trips idx_stalls_one_vehicle_per_stall; letting go
          -- afterwards would be one statement too late.
          UPDATE stalls SET current_vehicle_id = NULL,
                 status = CASE WHEN status = 'occupied' THEN 'available' ELSE status END
           WHERE current_vehicle_id = v_rec.vehicle_id AND id <> v_stall;
          UPDATE vehicles SET current_stall_id = v_stall WHERE id = v_rec.vehicle_id;
          UPDATE stalls SET current_vehicle_id = v_rec.vehicle_id, status = 'occupied'
           WHERE id = v_stall;
        END IF;
      END IF;
    ELSE
      UPDATE ottoq_ops_approvals SET status='declined', decided_at=p_clock, decided_by=COALESCE('operator:' || v_rec.op_by, 'twin_tech_sim')
       WHERE approval_id = v_rec.approval_id;
    END IF;
  END LOOP;
  -- 0002: same ownership rule for the expiry sweep. An indepot_reassign row is expired
  -- by OTTO-Q's decider on the SIM clock, not here on a column that may be real-domain.
  UPDATE ottoq_ops_approvals SET status='expired'
   WHERE depot_id = v_depot AND status = 'pending'
     AND approval_type IN ('opportunistic_charge','tech_greenlight')
     AND expires_at <= p_clock;
  RETURN v_n;
END; $function$;
