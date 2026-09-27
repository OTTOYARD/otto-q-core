-- migration-version: 20260926112337
-- migration-name:    the_gate_intake_booked_over_the_cars_own_hold_and_ran_with_no_booking
--
-- 0476  **The gate intake picked the stall the car already held its own booking on, collided with that booking, and
--       ran with no booking at all.** `db/checks/0360` §4. FINDINGS G206.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Validation run 49c45bd4 (busy_day, twin depot `11111111-…`): 3 of 46 no-charge gate intakes were enacted with no
--   staging booking. In all three the picked stall carried a live booking of the SAME car, not another's:
--   Tesla-AV-067 on S025 over its own temp_hold 14:45-15:05 UTC sim, Tesla-AV-044 on S013 over its own temp_hold
--   14:58-15:08, Zoox-AV-093 on E020 over its own perimeter_hold 16:00-18:00. Each old booking later closed as the
--   car's (`window_elapsed_occupied`, `vehicle_moved_to_next_leg`, `run_stopped`), and from then the calendar held
--   nothing for a car standing on the stall. (0359 §4 first read this as "a later booking on the stall overlapped".
--   It was the car's own booking.)
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   The intake (`ottoq_decide_tick` 3b, as 0467 left it) picks the first staging stall `ottoq_validate_assignment`
--   accepts, and the validator exempts the car's own booking, so the car's own hold is no bar to the pick. It then
--   books the stall from now to the itinerary's planned end with a bare `ottoq.ottoq_book_stall`, whose per-stall
--   EXCLUDE counts the car's own held, active and done bookings like anyone's. The insert fails, `ottoq_book_stall`
--   returns NULL, and the intake goes on with its command already emitted. Every other enacted placement records its
--   booking through `ottoq.ottoq_record_enacted_booking`, which on the given stall adopts a same-purpose booking of the
--   car, supersedes the car's own overlapping held or active booking (and any whose car is not on the stall),
--   truncates an overlapping done one at the start, and releases the car's same-purpose sibling holds, before it
--   books. It runs no search of its own, which is the property the intake's comment requires of anything it calls.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The intake records its staging booking through `ottoq.ottoq_record_enacted_booking` on the stall it picked, with
--   the same window, leg and source. Nothing else in the intake changes.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   Tick path: intake bookings, and the holds they supersede, move.
--
--   PREDICTED on the next busy_day run: every enacted gate intake carries a booking; a car's own hold on the stall it
--   is intaken to reads `superseded_by_enacted_decision` at the intake's clock.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0476 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure)) <> '03d2c1b2a03d8aad076ef47108a87739' THEN
    RAISE EXCEPTION '0476 P2: public.ottoq_decide_tick is not the body this file patches';
  END IF;
  -- the seam takes (run, stall, vehicle, clock, leg, from, to, purpose, source), and still records on the given stall
  IF pg_get_function_arguments('ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)'::regprocedure)
     <> 'p_sim_run_id uuid, p_stall_id uuid, p_vehicle_id uuid, p_clock timestamp with time zone, p_leg_id uuid DEFAULT NULL::uuid, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_purpose text DEFAULT NULL::text, p_source text DEFAULT ''unknown''::text' THEN
    RAISE EXCEPTION '0476 P2: ottoq_record_enacted_booking no longer takes the arguments this file passes';
  END IF;
  IF position('ottoq_stall_free_between' IN pg_get_functiondef('ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)'::regprocedure)) > 0
     OR position('ottoq_book_hold_stall' IN pg_get_functiondef('ottoq.ottoq_record_enacted_booking(uuid,uuid,uuid,timestamp with time zone,uuid,timestamp with time zone,timestamp with time zone,text,text)'::regprocedure)) > 0 THEN
    RAISE EXCEPTION '0476 P2: ottoq_record_enacted_booking now runs a search of its own';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0476_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_decide_tick(uuid)'::regprocedure;

DO $patch_intake$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
  v_pat text := $p$v_bkg := ottoq\.ottoq_book_stall\(p_sim_run_id, v_stage_stall, v_req\.vehicle_id,\s+'staging', v_clock, v_stage_until, NULL, v_stage_leg_id,\s+ottoq\.ottoq_booking_authorship\('gate_intake_staging'\)\);$p$;
  v_new text := $r$-- 0476 (G206): recorded through the enacted-booking seam on the stall already picked, which runs no search of its
      -- own. A bare ottoq_book_stall collided with the car's own live hold on that stall (the validator exempts it) and
      -- the intake went on with no booking, 3 of 46 on 49c45bd4. The seam supersedes the car's own overlapping booking
      -- and truncates an overlapping done one first, as it does for every other enacted placement.
      v_bkg := ottoq.ottoq_record_enacted_booking(p_sim_run_id, v_stage_stall, v_req.vehicle_id, v_clock,
                 v_stage_leg_id, v_clock, v_stage_until, 'staging', 'gate_intake_staging');$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0476: the intake booking matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat, v_new);
  EXECUTE v_def;
END $patch_intake$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_s text := pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure);
BEGIN
  -- V1: the intake records through the seam, once, and no bare staging book is left in the intake.
  IF (SELECT count(*) FROM regexp_matches(v_s, $x$v_bkg := ottoq\.ottoq_record_enacted_booking\(p_sim_run_id, v_stage_stall, v_req\.vehicle_id, v_clock,\s+v_stage_leg_id, v_clock, v_stage_until, 'staging', 'gate_intake_staging'\);$x$, 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_s, $x$ottoq_book_stall\(p_sim_run_id, v_stage_stall$x$, 'g')) <> 0
     OR (SELECT count(*) FROM regexp_matches(v_s, $x$ottoq_record_enacted_booking\($x$, 'g')) <> 2 THEN
    RAISE EXCEPTION '0476 V1: the decide tick is not the body this file writes';
  END IF;
  -- V2: one overload, the same grants (authenticated and service_role, never anon).
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'public' AND p.proname = 'ottoq_decide_tick') <> 1 THEN
    RAISE EXCEPTION '0476 V2: an overload appeared';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_decide_tick(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_decide_tick(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_decide_tick(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0476 V2: the grants moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0476_pre' (CREATE OR REPLACE; the grants are kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0476_the_gate_intake_booked_over_the_cars_own_hold_and_ran_with_no_booking', true,
  'Tick path: ottoq_decide_tick (3b) records the intake''s staging booking through ottoq_record_enacted_booking on the '
  'stall it picked. Intake bookings, and the holds they supersede, move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
