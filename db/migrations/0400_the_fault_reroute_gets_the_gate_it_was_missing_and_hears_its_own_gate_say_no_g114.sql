-- migration-version: PENDING
-- migration-name:    the_fault_reroute_gets_the_gate_it_was_missing_and_hears_its_own_gate_say_no_g114
--
-- 0400  G114, item (a) and item (b) — **the fault reroute reads the calendar, and stops ignoring
--       its own gate's verdict.** `db/checks/0310` measured that of the two functions in this
--       engine that pick a charge stall, neither implements CLAUDE.md Part 3's three-gate rule,
--       and they fail on *different* gates: the shared candidate source
--       `ottoq.ottoq_stall_free_between` has its pointer check switched off, and
--       `ottoq.ottoq_replan_after_charger_fault` — the path Chase's charger-fault requirement
--       runs through — reads pointer and charger and **no calendar at all**.
--
-- **THIS FILE FIXES ONLY THE SECOND ONE**, and deliberately. Switching
-- `calendar_occupancy_guard` on is item (d): it changes the candidate set for all SEVEN callers of
-- the shared source, and that is a behavioural change to the main assignment path which must not
-- ride along inside a fault-path fix. Item (c), the `deploy_peak_fraction` 0.55-vs-0.90 split, is
-- a product decision measurement cannot make and is not touched here.
--
-- ══ WHY A JOIN ONTO THE HELPER, AND NOT A COPY OF ITS PREDICATE ════════════
--
-- The calendar read is the one piece of this engine where a picker disagreeing with the constraint
-- has already caused a live incident: on 2026-08-02 a picker that read `held`/`active` while the
-- constraint covered four states booked **22 vehicles into one bay**. `ottoq_stall_free_between`
-- carries the aligned state set and a comment explaining the alignment. **Copying that predicate
-- into a second function creates exactly the two-places-to-drift condition that caused the
-- incident**, so this migration JOINS the helper instead — CLAUDE.md rule 5, consolidate rather
-- than duplicate.
--
-- ══ AND IT IS AN INTERSECTION, NOT A REPLACEMENT — THIS IS THE WHOLE CARE ══
--
-- The obvious edit is to swap the hand-rolled SELECTs *for* a helper call. **That would make the
-- function worse.** The helper is LOOSER on the pointer than this function is today:
--
--   this function today          helper
--   status = 'available'         status NOT IN ('maintenance','closed')
--   current_vehicle_id IS NULL   behind `calendar_occupancy_guard`, which is OFF (0310 §3)
--   reserved_by free/expired     not checked at all
--
-- So a swap trades gate 2 for gate 1 and the total is no better — precisely Part 3's *"whichever
-- single gate you quote, some stall type makes it look generous."* Every existing predicate is
-- therefore KEPT and the helper is added as an additional JOIN. The three gates are an
-- intersection; this file makes the code an intersection too.
--
-- ══ THE NULL-RUN CASE IS SAFE, AND THE CONSTRAINT IS WHAT PROVES IT ════════
--
-- `0310` §6(a) warned that the helper's calendar predicate is `b.sim_run_id = p_sim_run_id`, so a
-- NULL run makes it match nothing and "the calendar gate passes everything while LOOKING present."
-- **The mechanics are right and the conclusion was wrong, and it is corrected here.** Measured:
-- `ottoq_stall_bookings.sim_run_id` is **NOT NULL**, `0` of `15,890` rows carry a null, and the
-- EXCLUDE constraint itself is keyed `sim_run_id WITH =`. **The calendar is inherently run-scoped:
-- for a NULL run there are provably no bookings to conflict with**, so a gate that admits
-- everything is correct rather than decorative. No special-casing is needed, which is why this
-- migration has none — the measurement made the code simpler, not more complex.
--
-- ══ THE ONE GOTCHA WORTH ENCODING: THE HELPER IS A TOP-N FUNCTION ══════════
--
-- `ottoq_stall_free_between` ends `LIMIT GREATEST(p_limit, 1)`. Used as a SET-MEMBERSHIP test —
-- which is what a JOIN makes it — any `p_limit` below the candidate count silently truncates the
-- admissible set and would make this reroute refuse stalls that are genuinely free. `p_limit` is
-- therefore passed far above any depot's stall count (twin depot: 158; all depots: 330) and the
-- preflight asserts the margin rather than trusting it.
--
-- ══ forces_recert: TRUE, conservatively, and the reason ════════════════════
--
-- This changes which stall a vehicle is rerouted to when a charger faults mid-charge. Faults are
-- injected during runs, so a reroute that lands on a different stall changes bookings, commands and
-- the world fingerprint — several of the fourteen atoms. It cannot be argued to be inert, so it is
-- marked TRUE and left **PENDING**: per `0397` §1b such a change is free only when it lands
-- TOGETHER with the others already queued (G111's actor attribution, and the G112 granularity
-- decision, which forces a recert anyway). Applying this alone would buy one fix for nine
-- re-certifications.
--
-- **Item (b) is behaviour-preserving on all real data and is included for that reason.** The
-- function calls `ottoq_indepot_reassignment_guard` and uses only `v_gate->>'mode'`; it never reads
-- `allowed`. For `p_reason='resource_fault'` — the only reason it ever passes — the guard returns
-- `allowed:true` on every branch EXCEPT `vehicle_not_found`, which returns `allowed:false` with no
-- `mode` key at all. On that one path this function currently reserves a stall for a vehicle that
-- does not exist, leaving `stalls.reserved_by` pointing at a dangling uuid. Refusing early cannot
-- fire for any vehicle that exists, so it changes nothing a run can observe.
--
-- **NOT IN THIS FILE, and named so it is not mistaken for done:** the guard also returns
-- `rebook_required: true` and `preserve_work: true` for a resource fault, and this function honours
-- neither — it moves the vehicle by pointer and writes no booking at all. Making the reroute
-- *book* its new stall is a larger design question (which purpose, which `need_atom`, what window,
-- and what happens to the original booking on the faulted stall) and belongs in its own migration
-- with its own measurement. Until then the reroute remains pointer-only; it is now at least
-- pointer-only **into a stall the calendar has not already promised to someone else.**

BEGIN;

-- ══════════════════════════ PREFLIGHT ══════════════════════════
-- Five assertions. Each tests something that is load-bearing for the change below and that a
-- reasonable person would otherwise assume.
DO $preflight$
DECLARE
  v_n int;
  v_def text;
BEGIN
  -- (1) The function being replaced exists with the signature this file assumes. Replacing a
  --     function whose arguments moved would CREATE a second overload and leave the old one live.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_replan_after_charger_fault'
     AND pg_get_function_identity_arguments(p.oid) =
         'p_vehicle_id uuid, p_sim_run_id uuid, p_depot_id uuid, p_stall_type text, p_charger_id uuid, p_fault_code text, p_clock timestamp with time zone';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0400 preflight (1): expected exactly 1 ottoq.ottoq_replan_after_charger_fault with the known signature, found %', v_n;
  END IF;

  -- (2) The shared helper exists with the 8-argument signature this file calls positionally.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_stall_free_between'
     AND pg_get_function_identity_arguments(p.oid) =
         'p_sim_run_id uuid, p_depot_id uuid, p_from timestamp with time zone, p_to timestamp with time zone, p_stall_type text, p_staging_role text, p_limit integer, p_zones text[]';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0400 preflight (2): ottoq.ottoq_stall_free_between missing or its signature moved (found % matching)', v_n;
  END IF;

  -- (3) The fact that makes the NULL-run case safe: the calendar cannot hold an unscoped booking.
  --     If this column ever becomes nullable, the NULL-run reasoning in the header dies with it
  --     and this function needs an explicit branch.
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='ottoq_stall_bookings'
                AND column_name='sim_run_id' AND is_nullable='YES') THEN
    RAISE EXCEPTION '0400 preflight (3): ottoq_stall_bookings.sim_run_id is now NULLABLE -- the NULL-run argument in this file no longer holds';
  END IF;

  -- (4) The helper's calendar state set still matches the constraint. This is the 2026-08-02
  --     incident's exact condition, asserted rather than trusted.
  SELECT pg_get_constraintdef(oid) INTO v_def
    FROM pg_constraint WHERE conname = 'ottoq_stall_bookings_no_overlap_v3';
  IF v_def IS NULL THEN
    RAISE EXCEPTION '0400 preflight (4): ottoq_stall_bookings_no_overlap_v3 not found';
  END IF;
  IF NOT (v_def ~ 'held' AND v_def ~ 'active' AND v_def ~ 'done' AND v_def ~ 'interrupted') THEN
    RAISE EXCEPTION '0400 preflight (4): the EXCLUDE state set changed (%); ottoq_stall_free_between must be realigned BEFORE this function leans on it', v_def;
  END IF;

  -- (5) The top-N margin. p_limit below the candidate count would silently truncate the
  --     admissible set and make this reroute refuse genuinely free stalls.
  SELECT count(*) INTO v_n FROM public.stalls;
  IF v_n >= 10000 THEN
    RAISE EXCEPTION '0400 preflight (5): % stalls exist, which is no longer safely under the p_limit of 10000 this file passes', v_n;
  END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION ottoq.ottoq_replan_after_charger_fault(
  p_vehicle_id uuid, p_sim_run_id uuid, p_depot_id uuid, p_stall_type text,
  p_charger_id uuid, p_fault_code text, p_clock timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
AS $fn$
DECLARE v_gate jsonb; v_new_stall uuid; v_disp text;
        -- The reroute reserves for 3600s (below), so the window the calendar is asked about is
        -- the window the pointer is about to be held for. Asking about a different window than
        -- you intend to occupy is how a gate reads present and protects nothing.
        v_to timestamptz := p_clock + interval '1 hour';
BEGIN
  -- in-depot reassignment doctrine: a resource fault is the sanctioned auto-reroute
  v_gate := ottoq_indepot_reassignment_guard(p_vehicle_id, p_sim_run_id, 'resource_fault',
              jsonb_build_object('charger_id', p_charger_id, 'fault', p_fault_code));

  -- ══════════════ 0400 / G114 item (b): HEAR THE GATE SAY NO ══════════════
  -- This function called the gate and then used only `v_gate->>'mode'`, for its return payload.
  -- It never read `allowed`. For 'resource_fault' the guard answers true on every branch EXCEPT
  -- `vehicle_not_found`, which returns {'allowed': false, 'reason': 'vehicle_not_found'} with no
  -- `mode` key -- and on that path this function went on to reserve a real stall for a vehicle
  -- that does not exist, leaving stalls.reserved_by pointing at a dangling uuid and returning
  -- gate_mode NULL. Refusing here cannot fire for a vehicle that exists, so no run's behaviour
  -- changes; it closes a path that could only ever produce garbage.
  IF COALESCE((v_gate->>'allowed')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object('vehicle_id', p_vehicle_id, 'disposition', 'gate_refused',
                              'new_stall', NULL, 'gate_mode', v_gate->>'mode',
                              'gate_reason', v_gate->>'reason');
  END IF;

  -- prefer a healthy stall of the SAME class
  --
  -- ══════════════ 0400 / G114 item (a): THE CALENDAR IS THE MISSING GATE ══════════════
  -- Every predicate below is unchanged, and ottoq.ottoq_stall_free_between is added as an
  -- INTERSECTING join rather than a replacement -- the helper is looser on the pointer than these
  -- predicates are (see the header), so swapping would trade gate 2 for gate 1. The join also
  -- leaves this query's own ORDER BY intact, so the ONLY behavioural change is that stalls the
  -- calendar has already promised for [p_clock, +1h) stop being offered.
  -- The helper is joined rather than copied because it carries the state set aligned to
  -- ottoq_stall_bookings_no_overlap_v3, and a second copy of that predicate is the 2026-08-02
  -- two-places-to-drift condition that booked 22 vehicles into one bay.
  SELECT s2.id INTO v_new_stall
    FROM stalls s2
    JOIN ottoq_ocpp_chargers c2 ON c2.charger_id = s2.ocpp_charger_id
    JOIN ottoq.ottoq_stall_free_between(
           p_sim_run_id, p_depot_id, p_clock, v_to, p_stall_type, NULL, 10000, NULL) f
      ON f.stall_id = s2.id
   WHERE s2.depot_id = p_depot_id
     AND s2.stall_type::text = p_stall_type
     AND s2.status = 'available'
     AND s2.current_vehicle_id IS NULL
     AND (s2.reserved_by IS NULL OR COALESCE(s2.reservation_expires_at, p_clock) <= p_clock)
     AND c2.station_state = 'Available'
   ORDER BY s2.stall_code
   LIMIT 1;

  IF v_new_stall IS NOT NULL AND ottoq_reserve_stall(v_new_stall, p_vehicle_id, p_clock, 3600) THEN
    v_disp := 'requeued_same_class';
  ELSE
    -- else temp-stage it: never leave a displaced vehicle without somewhere to be
    -- p_staging_role is passed NULL rather than 'temp' on purpose: 'temp' is a PREFERENCE here,
    -- expressed by this query's ORDER BY, and passing it to the helper would turn a preference
    -- into a filter and refuse to stage a displaced vehicle anywhere else.
    SELECT s3.id INTO v_new_stall
      FROM stalls s3
      JOIN ottoq.ottoq_stall_free_between(
             p_sim_run_id, p_depot_id, p_clock, v_to, 'staging', NULL, 10000, NULL) f3
        ON f3.stall_id = s3.id
     WHERE s3.depot_id = p_depot_id
       AND s3.stall_type::text = 'staging'
       AND s3.status = 'available'
       AND s3.current_vehicle_id IS NULL
       AND (s3.reserved_by IS NULL OR COALESCE(s3.reservation_expires_at, p_clock) <= p_clock)
     ORDER BY (s3.staging_role = 'temp') DESC, s3.stall_code
     LIMIT 1;
    IF v_new_stall IS NOT NULL AND ottoq_reserve_stall(v_new_stall, p_vehicle_id, p_clock, 3600) THEN
      v_disp := 'temp_parked_awaiting_charger';
    ELSE
      v_disp := 'no_space_escalated'; v_new_stall := NULL;
    END IF;
  END IF;

  BEGIN
    IF v_new_stall IS NOT NULL AND p_sim_run_id IS NOT NULL THEN
      PERFORM ottoq_comms_send_command(p_sim_run_id, p_vehicle_id,
        CASE WHEN v_disp = 'temp_parked_awaiting_charger' THEN 'stage' ELSE 'proceed_to_stall' END,
        jsonb_build_object('plan_update','charger_fault_reroute','stall_id',v_new_stall,
                           'faulted_charger',p_charger_id,'disposition',v_disp),
        p_clock, false);
    END IF;
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'fault reroute downlink: %', SQLERRM; END;

  RETURN jsonb_build_object('vehicle_id', p_vehicle_id, 'disposition', v_disp,
                            'new_stall', v_new_stall, 'gate_mode', v_gate->>'mode');
END
$fn$;

COMMENT ON FUNCTION ottoq.ottoq_replan_after_charger_fault(uuid,uuid,uuid,text,uuid,text,timestamptz) IS
'Charger-fault reroute: same-class healthy stall, else temp staging, else escalate. Gates on all '
'THREE of CLAUDE.md Part 3''s conditions -- pointer (own predicates), calendar (joined via '
'ottoq.ottoq_stall_free_between over [clock, clock+1h), matching the reservation TTL), and OCPP '
'charger not Faulted. The helper is JOINED, never substituted: it is looser on the pointer than '
'this function, so replacing rather than intersecting would trade one gate for another (0400/G114). '
'Writes NO booking -- the reroute is pointer-only, so ottoq_stall_bookings_no_overlap_v3 never '
'sees it, and the guard''s rebook_required:true is still unhonoured. That is a known open item, '
'not an oversight.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0400_the_fault_reroute_gets_the_gate_it_was_missing_and_hears_its_own_gate_say_no_g114',
        TRUE,
        'G114 items (a) and (b). db/checks/0310 measured that NEITHER function in this engine that '
        'picks a charge stall implements CLAUDE.md Part 3''s three-gate rule, and that they fail on '
        'DIFFERENT gates: ottoq_stall_free_between (the shared source, 7 callers) has its pointer '
        'check behind calendar_occupancy_guard, which is OFF on 0 of 22 surviving twin-depot runs, '
        'and ottoq_replan_after_charger_fault reads pointer and charger and NO CALENDAR. This file '
        'fixes only the second: the shared helper is JOINED as an INTERSECTION -- never substituted, '
        'because it is LOOSER on the pointer than this function is (status NOT IN '
        '(''maintenance'',''closed'') vs status=''available''; current_vehicle_id behind the off '
        'switch; reserved_by unchecked), so a swap would trade gate 2 for gate 1 and gain nothing. '
        'Joined rather than copied because the helper carries the state set aligned to '
        'ottoq_stall_bookings_no_overlap_v3, and a second copy of that predicate is the 2026-08-02 '
        'two-places-to-drift condition that booked 22 vehicles into one bay. Window [clock, clock+1h) '
        'matches the 3600s TTL the function already passes to ottoq_reserve_stall. Item (b) makes it '
        'read its own gate''s `allowed`, which it never did: for resource_fault the guard answers '
        'true everywhere EXCEPT vehicle_not_found, and on that path the old code reserved a real '
        'DCFC stall for a nonexistent vehicle -- demonstrated, not inferred (0310 section 7). That '
        'half is behaviour-preserving on all real data, since it cannot fire for a vehicle that '
        'exists. forces_recert TRUE conservatively and for a stated reason: faults are injected '
        'during runs, so a reroute landing on a different stall moves bookings, commands and the '
        'world fingerprint -- several of the fourteen atoms -- and that cannot be argued inert. '
        'PROVEN ON A ROLLED-BACK PROBE before being written: at run b4d5f76d''s FINAL clock the gate '
        'removed 0 (dcfc 10->10) because that run''s bookings end twelve minutes earlier, which '
        'proves it wired and NOT that it binds -- the G28 trap inside a probe; at a mid-run clock it '
        'removed 4 of 10 dcfc candidates. NOT DONE, and named so it is not mistaken for done: the '
        'guard also returns rebook_required:true and this function still writes no booking at all, '
        'so the reroute stays pointer-only and the EXCLUDE constraint never sees it.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

COMMIT;
