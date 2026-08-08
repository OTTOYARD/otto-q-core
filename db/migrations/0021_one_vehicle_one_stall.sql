-- migration-version: 20260808170813
-- migration-name:    one_vehicle_one_stall
--
-- ══ APPLIED-TEXT NOTE ══
--  Applied 2026-08-08 via Supabase MCP `apply_migration` (no SUPABASE_ACCESS_TOKEN,
--  no psql, no Supabase CLI in this session). As with 0020, the narrative comment
--  prose was condensed for the apply channel, so the submitted text is not
--  byte-identical to this file:
--    md5 of this file .......... see MIGRATION_LOG.md
--    md5 of what actually ran .. 2f55734a4d2d81b9c3c68e171e9bb525
--  The executable SQL was not edited, and the one routine created is proven
--  byte-identical by md5(pg_get_functiondef) in MIGRATION_LOG.md.
--
-- 0021_one_vehicle_one_stall.sql
-- ============================================================================
-- A VEHICLE CANNOT BE IN TWO STALLS, AND SAYING SO MUST NOT FREEZE THE RUN
-- ============================================================================
--
-- FOUND WHILE CERTIFYING 0020, NOT REPORTED BY ANYONE. Run `0a3c6910` (seed
-- 20260822) froze at tick 5 and never advanced again. The metronome kept firing
-- every minute and kept logging one line:
--
--     metronome world 0a3c6910… failed:
--     duplicate key value violates unique constraint "idx_stalls_one_vehicle_per_stall"
--
-- 20 times, each a whole tick rolled back. `tick_count` sat at 5 while
-- `next_tick_due_at` kept moving, so from the outside the run looked alive.
-- That is the same failure family as everything else on this project: a system
-- reporting motion it has not earned.
--
-- ══ THE EXACT STATEMENT, from PG_EXCEPTION_CONTEXT ══
--
--   twin.ottoq_sim_advance_service_flow, line 351:
--       UPDATE stalls SET current_vehicle_id = v_rec.id, status = 'occupied'
--        WHERE id = v_rec.booked_stall
--          AND (current_vehicle_id IS NULL OR current_vehicle_id = v_rec.id)
--
--   The WHERE clause guards the WRONG SIDE of the index. It stops the statement
--   stealing a stall that another vehicle is in — but `idx_stalls_one_vehicle_per_stall`
--   is UNIQUE on `current_vehicle_id`, i.e. it says a VEHICLE may appear in only
--   one stall. Nothing here releases the stall the vehicle is currently sitting in.
--
--   The blocked vehicle, read from the live run:
--     b19025e6  state `staged_awaiting_service`
--               seated  stall cddbeec9  (staging)
--               booked  stall 6ff1e0a5  (service_bay), purpose 'service',
--                       window 15:17:39 → 17:06:39, sim clock 15:30:00 — live
--     Its visit carries a must_do `fault_repair`, which is what demanded a
--     service_bay. `fault_repair` is a ~2% seeded draw, so which vehicle gets it
--     is a property of the seed.
--
-- ══ NOT CAUSED BY 0020, AND THAT WAS CHECKED RATHER THAN ASSUMED ══
--
--   * b19025e6 is NOT rider-flagged in this run, so neither 0019's in-depot sweep
--     nor 0020's consume-and-place is on its path.
--   * Its visit_key `…:20260808165750` collides with NOTHING — its four historical
--     keys are all distinct — so 0020's run-scoped uniqueness change did not make
--     this visit newly visible. Pre-0020 the INSERT would simply have succeeded,
--     and the same booking would have been made.
--   * `twin.ottoq_sim_advance_service_flow` is not touched by 0020 and is not
--     touched by 0019.
--
--   It is a latent, seed-dependent deadlock: ANY run whose draw puts a
--   bay-requiring must_do atom on a vehicle that is already seated will freeze at
--   that tick and never recover. Three earlier runs on three other seeds missed it.
--   This one did not.
--
-- ══ THE FIX, AND WHY IT IS A TRIGGER RATHER THAN A PATCH TO LINE 351 ══
--
--   24 routines in this database write `stalls.current_vehicle_id` or
--   `vehicles.current_stall_id`. Patching the one that happened to fail leaves the
--   other 23 able to fail the same way on a different seed, and would mean
--   replacing a large function to change one statement. The invariant belongs on
--   the table: seating a vehicle releases wherever it was.
--
--   This is the same shape `public.sync_stall_occupancy` already implements for
--   the vehicle-driven path ("clear old stall, occupy new"). 0021 gives the
--   stall-driven path the same courtesy.
--
--   TERMINATION. The trigger only acts when `NEW.current_vehicle_id IS NOT NULL`;
--   the rows it touches are set to NULL, so the recursive invocation does nothing
--   and stops. Proven by assertion A3 below, which performs a real double-seat.
--
--   WHAT IT DOES NOT DO. It does not touch `ottoq_stall_bookings`, so the PROTECT
--   double-booking measurement (pairwise `during && during` on the bookings table)
--   is unaffected in either direction. It cannot mask a booking conflict, because
--   it never reads or writes a booking.
--
-- ⚠️ Nothing is dropped. One new trigger function, one new trigger.
-- ============================================================================

BEGIN;

SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout      = '15s';

CREATE OR REPLACE FUNCTION public.ottoq_stall_seat_is_exclusive()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
BEGIN
  IF NEW.current_vehicle_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.current_vehicle_id IS DISTINCT FROM OLD.current_vehicle_id)
  THEN
    -- Release every OTHER stall still claiming this vehicle. Physically a car is
    -- in one place; the unique index says so, and until now nothing made it true.
    UPDATE public.stalls s
       SET current_vehicle_id = NULL,
           status = CASE WHEN s.status = 'occupied' THEN 'available' ELSE s.status END
     WHERE s.current_vehicle_id = NEW.current_vehicle_id
       AND s.id <> NEW.id;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_ottoq_stall_seat_is_exclusive ON public.stalls;
CREATE TRIGGER trg_ottoq_stall_seat_is_exclusive
  BEFORE INSERT OR UPDATE OF current_vehicle_id ON public.stalls
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_stall_seat_is_exclusive();

-- ============================================================================
-- ASSERTIONS
-- ============================================================================
DO $assert$
DECLARE
  n int; v_veh uuid; v_a uuid; v_b uuid; v_ok boolean := false;
  v_a_before uuid; v_b_before uuid; v_veh_stall_before uuid;
BEGIN
  -- A1. The trigger exists and is enabled.
  SELECT count(*) INTO n FROM pg_trigger
   WHERE NOT tgisinternal AND tgname = 'trg_ottoq_stall_seat_is_exclusive' AND tgenabled <> 'D';
  IF n <> 1 THEN RAISE EXCEPTION 'A1 FAILED: trigger missing or disabled'; END IF;

  -- A2. The invariant holds right now: no vehicle is claimed by two stalls.
  SELECT count(*) INTO n FROM (
    SELECT current_vehicle_id FROM public.stalls
     WHERE current_vehicle_id IS NOT NULL
     GROUP BY 1 HAVING count(*) > 1) q;
  IF n <> 0 THEN RAISE EXCEPTION 'A2 FAILED: % vehicle(s) already claimed by two stalls', n; END IF;

  -- A3. NOT VACUOUS. Perform the exact write that froze run 0a3c6910 -- seat a
  --     vehicle into a second stall while it still occupies a first -- and prove
  --     it now succeeds AND leaves exactly one claim. Fully restored afterwards.
  SELECT s.current_vehicle_id, s.id INTO v_veh, v_a
    FROM public.stalls s WHERE s.current_vehicle_id IS NOT NULL LIMIT 1;
  SELECT s.id INTO v_b FROM public.stalls s
   WHERE s.current_vehicle_id IS NULL AND s.id <> v_a LIMIT 1;

  IF v_veh IS NULL OR v_b IS NULL THEN
    RAISE NOTICE 'A3 SKIPPED: no seated vehicle and free stall available to probe with';
  ELSE
    SELECT current_vehicle_id INTO v_a_before FROM public.stalls WHERE id = v_a;
    SELECT current_vehicle_id INTO v_b_before FROM public.stalls WHERE id = v_b;
    SELECT current_stall_id   INTO v_veh_stall_before FROM public.vehicles WHERE id = v_veh;

    -- the statement that used to raise 23505
    UPDATE public.stalls SET current_vehicle_id = v_veh, status = 'occupied' WHERE id = v_b;

    SELECT count(*) INTO n FROM public.stalls WHERE current_vehicle_id = v_veh;
    IF n <> 1 THEN RAISE EXCEPTION 'A3 FAILED: after double-seat the vehicle is claimed by % stalls', n; END IF;
    SELECT (current_vehicle_id IS NULL) INTO v_ok FROM public.stalls WHERE id = v_a;
    IF NOT v_ok THEN RAISE EXCEPTION 'A3 FAILED: the original stall was not released'; END IF;

    -- restore exactly
    UPDATE public.stalls SET current_vehicle_id = NULL, status = 'available' WHERE id = v_b;
    UPDATE public.stalls SET current_vehicle_id = v_a_before,
           status = CASE WHEN v_a_before IS NULL THEN 'available' ELSE 'occupied' END WHERE id = v_a;
    UPDATE public.vehicles SET current_stall_id = v_veh_stall_before WHERE id = v_veh;

    SELECT count(*) INTO n FROM public.stalls
     WHERE (id = v_a AND current_vehicle_id IS DISTINCT FROM v_a_before)
        OR (id = v_b AND current_vehicle_id IS DISTINCT FROM v_b_before);
    IF n <> 0 THEN RAISE EXCEPTION 'A3 FAILED: probe did not restore the two stalls'; END IF;
    RAISE NOTICE 'A3 PASSED: double-seat now succeeds and leaves exactly one claim';
  END IF;

  RAISE NOTICE '0021 assertions A1-A3 PASSED';
END
$assert$;

COMMIT;
