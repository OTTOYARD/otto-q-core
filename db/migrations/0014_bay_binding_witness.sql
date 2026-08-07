-- migration-version: 20260807005437
-- migration-name:    bay_binding_witness
-- 0014_bay_binding_witness.sql
--
-- ════════════════════════════════════════════════════════════════════════════════════════
-- WHY THIS EXISTS: THE BINDING PROOF CANNOT BE WRITTEN AS A POST-HOC QUERY
-- ════════════════════════════════════════════════════════════════════════════════════════
-- The assertion we owe is:
--     a booking created with source='return_signal_prearrival' reaches state='active'
--     AND vehicles.current_stall_id = booking.stall_id for THAT SAME vehicle, INSIDE the
--     reserved window, and then reaches 'done'.
--
-- That assertion is NOT answerable after the run, for two independent reasons. Both were
-- measured on run 6f7518ef, not assumed:
--
--  (1) `vehicles.current_stall_id` IS A POINT-IN-TIME SCALAR. It is overwritten on every
--      move. By the time a run stops, every vehicle has been re-seated many times, so
--      "was the car on the reserved stall inside the window" leaves NO row behind. Polling
--      it from outside cannot close the gap either: a bay leg is minutes long in sim time
--      but the seating instant is a single statement inside one tick.
--
--  (2) 🔴 THE ACTIVATION PATH DESTROYS THE PROVENANCE THE ASSERTION IS KEYED ON.
--      ottoq.ottoq_activate_due_bay_reservations -- the ONLY path that physically moves a
--      car into its reserved bay -- ends with:
--          UPDATE public.ottoq_stall_bookings
--             SET state='active', booked_by='otto_q_enacted',
--                 source='bay_reservation_activated'          <-- overwrites the source
--           WHERE booking_id = v_res.booking_id;
--      So the instant a pre-arrival hold BINDS, it stops being a row with
--      source='return_signal_prearrival'. The literal proof query
--          WHERE source='return_signal_prearrival' AND state='active'
--      is therefore GUARANTEED to return zero rows through the binding path -- not because
--      nothing bound, but because success renames the evidence. Every previous session ran
--      that query, got zero, and concluded "no hold has ever been observed binding". That
--      conclusion was not wrong about the 17 rows still sitting in 'held', but the query
--      could never have proven the positive case either.
--
-- This migration adds a WITNESS: an append-only record of every booking state/source
-- transition, stamped at the moment it happens with the vehicle's ACTUAL current_stall_id,
-- the reserved window, and BOTH clock domains. It changes no decision, no assignment and
-- no existing routine. It only remembers.
--
-- ════════════════════════════════════════════════════════════════════════════════════════
-- IT ALSO SEPARATES CAUSATION FROM CORRELATION, WHICH THE BRIEF EXPLICITLY DEMANDS
-- ════════════════════════════════════════════════════════════════════════════════════════
-- There are exactly two routines that can flip a held bay booking to 'active':
--
--   * ottoq.ottoq_activate_due_bay_reservations -- reads the BOOKING, CAS-reserves the
--     stall, then writes vehicles.current_stall_id := booking.stall_id. The reservation is
--     the CAUSE of the seating. It stamps source='bay_reservation_activated'.
--
--   * ottoq.ottoq_activate_present_bookings -- matches a booking whose vehicle is ALREADY
--     standing on that stall. It does not move anything and leaves `source` untouched. A
--     binding observed only here is CORRELATION: the car may have been sent there by the
--     ordinary assignment path and the hold merely agreed with it after the fact.
--
-- Because the witness captures old_source AND new_source, the two are distinguishable
-- after the fact, which is the whole difference between "the reservation worked" and
-- "the reservation was not contradicted".
--
-- ════════════════════════════════════════════════════════════════════════════════════════
-- SAFETY POSTURE
-- ════════════════════════════════════════════════════════════════════════════════════════
--   * PURELY ADDITIVE. One new table, one new trigger function, one new trigger.
--     NOTHING is dropped, replaced, or altered. No existing function is touched, so the
--     drift baseline moves by exactly the objects named here.
--   * The trigger is TOTAL: its entire body is wrapped so that any failure returns without
--     raising. An audit write must never abort a booking transition or cost a tick. This
--     is the same contract 0011 used for its own emission blocks, and the reason is the
--     lesson from the leg_type abort -- one unmapped value must not kill a decision.
--   * COST is bounded and measured, not hoped for: the trigger fires only on rows whose
--     state or source actually changed (WHEN clause, evaluated before the body), and does
--     two primary-key lookups. Booking transitions run in the low tens per tick against a
--     ~1 s tick, so this is well under 1% of tick cost.
--   * It is RUN-SCOPED and self-limiting: rows carry sim_run_id and are purged with the
--     run like every other run-scoped table.

BEGIN;

-- ────────────────────────────────────────────────────────────────────────────────────────
-- (1) The witness table
-- ────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ottoq_bay_binding_witness (
  witness_id        bigserial PRIMARY KEY,
  observed_real     timestamptz NOT NULL DEFAULT now(),   -- REAL clock domain
  observed_sim      timestamptz,                          -- SIM clock domain (run's sim_clock_current)
  sim_run_id        uuid,
  booking_id        uuid,
  vehicle_id        uuid,
  stall_id          uuid,                                 -- the stall the BOOKING reserved
  veh_current_stall uuid,                                 -- where the VEHICLE actually is, at this instant
  old_state         text,
  new_state         text,
  old_source        text,                                 -- provenance BEFORE any rewrite
  new_source        text,
  purpose           text,
  window_start      timestamptz,                          -- SIM domain: lower(during)
  window_end        timestamptz,                          -- SIM domain: upper(during)
  -- Derived at capture time so the proof does not depend on re-deriving it later.
  seated_on_reserved boolean,                             -- vehicle is physically on the reserved stall
  inside_window      boolean                              -- ...and the sim clock is inside the window
);

COMMENT ON TABLE public.ottoq_bay_binding_witness IS
  '0014: append-only witness of ottoq_stall_bookings state/source transitions, stamped with the '
  'vehicle''s actual current_stall_id and both clock domains. Exists because activation rewrites '
  'source (destroying the return_signal_prearrival provenance the binding proof is keyed on) and '
  'because vehicles.current_stall_id is a point-in-time scalar that leaves no history.';

CREATE INDEX IF NOT EXISTS ottoq_bay_binding_witness_run_idx
  ON public.ottoq_bay_binding_witness (sim_run_id, observed_real);
CREATE INDEX IF NOT EXISTS ottoq_bay_binding_witness_booking_idx
  ON public.ottoq_bay_binding_witness (booking_id, observed_real);

-- ────────────────────────────────────────────────────────────────────────────────────────
-- (2) The trigger function -- TOTAL by construction
-- ────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ottoq.ottoq_witness_booking_transition()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_sim   timestamptz;
  v_stall uuid;
BEGIN
  BEGIN
    SELECT r.sim_clock_current INTO v_sim
      FROM public.ottoq_sim_runs r WHERE r.sim_run_id = NEW.sim_run_id;

    SELECT v.current_stall_id INTO v_stall
      FROM public.vehicles v WHERE v.id = NEW.vehicle_id;

    INSERT INTO public.ottoq_bay_binding_witness (
      observed_sim, sim_run_id, booking_id, vehicle_id, stall_id, veh_current_stall,
      old_state, new_state, old_source, new_source, purpose,
      window_start, window_end, seated_on_reserved, inside_window)
    VALUES (
      v_sim, NEW.sim_run_id, NEW.booking_id, NEW.vehicle_id, NEW.stall_id, v_stall,
      OLD.state, NEW.state, OLD.source, NEW.source, NEW.purpose,
      lower(NEW.during), upper(NEW.during),
      (v_stall IS NOT NULL AND v_stall = NEW.stall_id),
      (v_sim IS NOT NULL AND v_sim >= lower(NEW.during) AND v_sim < upper(NEW.during))
    );
  EXCEPTION WHEN OTHERS THEN
    -- An audit write must never abort a booking transition or cost a tick.
    NULL;
  END;
  RETURN NULL;   -- AFTER trigger: return value is ignored
END
$function$;

-- ────────────────────────────────────────────────────────────────────────────────────────
-- (3) Arm it -- only on rows that actually transitioned
-- ────────────────────────────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS ottoq_witness_booking_transition_trg ON public.ottoq_stall_bookings;
CREATE TRIGGER ottoq_witness_booking_transition_trg
  AFTER UPDATE ON public.ottoq_stall_bookings
  FOR EACH ROW
  WHEN (OLD.state IS DISTINCT FROM NEW.state OR OLD.source IS DISTINCT FROM NEW.source)
  EXECUTE FUNCTION ottoq.ottoq_witness_booking_transition();

-- ────────────────────────────────────────────────────────────────────────────────────────
-- (4) Post-assertions -- the migration proves its own arrival
-- ────────────────────────────────────────────────────────────────────────────────────────
DO $assert$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname = 'ottoq_witness_booking_transition_trg'
                    AND tgrelid = 'public.ottoq_stall_bookings'::regclass
                    AND NOT tgisinternal) THEN
    RAISE EXCEPTION '0014 post-assert: witness trigger is not armed';
  END IF;

  IF to_regclass('public.ottoq_bay_binding_witness') IS NULL THEN
    RAISE EXCEPTION '0014 post-assert: witness table missing';
  END IF;
END
$assert$;

COMMIT;
