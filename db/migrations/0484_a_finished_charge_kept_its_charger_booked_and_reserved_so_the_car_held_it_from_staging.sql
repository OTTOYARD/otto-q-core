-- migration-version: 20260926132059
-- migration-name:    a_finished_charge_kept_its_charger_booked_and_reserved_so_the_car_held_it_from_staging
--
-- 0484  **A finished charge kept its charger booked and reserved, so the car held it from staging.**
--       `db/checks/0362` §10. FINDINGS G217 (the charger half of G195).
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Validation run `3dbe16db` (busy_day, twin depot, sim 8:00 AM-12:57 PM), from the stalls' own reservation events and
--   the bookings, `db/checks/0362` §10:
--
--                        sessions   still reserved to    reserved-minutes   booked past the   booked-minutes
--                        ended      the car at the end   after the end      end               after the end
--     DCFC completed        38            38                215 (max 31.8)        14               57 (max 30.0)
--     DCFC faulted           2             2                 75 (max 51.6)         2               73 (max 51.6)
--     L2 completed          23             7                  3                    3                5
--     L2 faulted             3             2                 13 (max 12.6)         3               70 (max 49.9)
--
--   Every DCFC session left its charger promised to the car that had just finished or faulted: 290 DCFC-minutes, about
--   a tenth of the ten DCFCs' 2,970 over the run, on the resource the stall assignment kept refusing cars for
--   (`no_compatible_available_stall`). `ab7adca4` finished on DCFC-01 at 10:03:14 sim at 90% and moved to staging.
--   Its booking ran to 10:14:31 (released `window_elapsed_occupied`), the reservation outlived it, and the next car
--   plugged in at 10:16:37: thirteen idle minutes on the scarcest stall in the depot.
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `twin.ottoq_sim_stop_charge_session` closes the session, frees the plug (at once, or after the arm's demate on a
--   latched DCFC), relocates the car and closes the charge itinerary leg. It never touches the charge booking or the
--   stall's reservation, so both run to their own expiry: the booking to the end of the window it was planned with, the
--   reservation to `reservation_expires_at`. The reclaimer (`ottoq_release_unusable_reservations`) frees a reservation
--   whose holder sits in another stall only when no held or active booking backs it, and the finished session's own
--   booking is exactly such a backing. So a car that finished early, or was moved off a faulted charger, kept that
--   charger promised to itself while it waited in staging, and every other car was refused it by the command gate,
--   which reads both the reservation and the calendar.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   At the end of the session, right after the charge leg closes:
--     - the car's started, active charge booking on that stall ends when the plug is free: `done` for a completed
--       session however early it finished, and for a faulted or cancelled one `interrupted` when it ran under 80% of
--       its planned length (the departure sweep's own rule, `ottoq.ottoq_occupancy_cut_short`), else `done`. A charge
--       that reached its target early is not an interruption, and `interrupted` feeds the interruption counts.
--       `release_reason` is `charge_session_<completed|faulted|cancelled>` and the window is clipped to that moment,
--       so the no-overlap exclusion (which keeps done and interrupted rows) frees the rest of it
--     - the stall's reservation is cleared if it is still this car's. A reservation already passed to another car is
--       not touched.
--   A future booking of the same car on the same stall (window not started) is not touched, and neither is a held one.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   The tick path: chargers free earlier, so the stall assignment places cars at different ticks.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0484 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure))
     <> '0b6de48a27c6fdfba15757fe3f4412ba' THEN
    RAISE EXCEPTION '0484 P2: twin.ottoq_sim_stop_charge_session is not the body this file patches';
  END IF;
  -- the reclaimer still treats a held or active booking as a reservation's backing, so ending the booking is what lets
  -- it free any reservation of this car that this file does not clear itself
  IF position('b.state IN (''held'',''active'')' IN pg_get_functiondef('public.ottoq_release_unusable_reservations(uuid,timestamp with time zone,uuid)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0484 P2: the reclaimer no longer treats a held or active booking as the backing';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0484_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure;

DO $patch_release$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure);
  v_pat text := $p$  PERFORM ottoq_itin_leg_close\(p_sim_run_id, v_session\.vehicle_id,
    ARRAY\['charge_dcfc','charge_l2'\], v_clock, 'done'\);
$p$;
  v_new text := $r$  PERFORM ottoq_itin_leg_close(p_sim_run_id, v_session.vehicle_id,
    ARRAY['charge_dcfc','charge_l2'], v_clock, 'done');

  -- 0484 (G217): the session is over, so this charger is no longer this car's. Its charge booking ends when the plug
  -- is free (now, or once the arm has demated a latched DCFC) and its reservation goes with it. Both used to run to
  -- their own expiry, so a car that had finished, or had been moved off a faulted charger, held it from staging.
  UPDATE ottoq_stall_bookings b
     SET state          = CASE WHEN v_new_status::text <> 'completed'
                                    AND ottoq.ottoq_occupancy_cut_short(
                                      EXTRACT(epoch FROM (upper(b.during) - lower(b.during)))::numeric,
                                      EXTRACT(epoch FROM (LEAST(upper(b.during), f.free_at) - lower(b.during)))::numeric)
                               THEN 'interrupted' ELSE 'done' END,
         released_at    = f.free_at,
         release_reason = 'charge_session_' || v_new_status::text,
         during         = tstzrange(lower(b.during),
                                    GREATEST(lower(b.during) + interval '1 second', LEAST(upper(b.during), f.free_at)), '[)')
    FROM (SELECT v_clock + CASE WHEN v_tether THEN make_interval(secs => v_demate_s)
                                ELSE interval '0 seconds' END AS free_at) f
   WHERE b.sim_run_id = p_sim_run_id
     AND b.stall_id   = v_session.stall_id
     AND b.vehicle_id = v_session.vehicle_id
     AND b.purpose IN ('charge_dcfc','charge_l2')
     AND b.state = 'active'
     AND lower(b.during) <= v_clock;
  UPDATE stalls
     SET reserved_by = NULL, reserved_at = NULL, reservation_expires_at = NULL
   WHERE id = v_session.stall_id AND reserved_by = v_session.vehicle_id;
$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0484: the charge-leg close matched % times, not once', n; END IF;
  EXECUTE regexp_replace(v_def, v_pat, v_new);
END $patch_release$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_s text := pg_get_functiondef('twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)'::regprocedure);
BEGIN
  -- V1: the booking close and the reservation clear sit once each, after the charge-leg close and before the event,
  -- and the rest of the body is the one it was (the tether, the requeue and the leg close are untouched).
  IF (SELECT count(*) FROM regexp_matches(v_s, $x$release_reason = 'charge_session_' \|\| v_new_status::text$x$, 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_s, $x$WHERE id = v_session\.stall_id AND reserved_by = v_session\.vehicle_id;$x$, 'g')) <> 1
     OR position('charge_session_' IN v_s) < position('PERFORM ottoq_itin_leg_close' IN v_s)
     OR position('charge_session_' IN v_s) > position('PERFORM ottoq_record_event' IN v_s)
     OR position($x$-- 0474 (G209): a step, so the deploy gate sees the car and routes it by its open work$x$ IN v_s) = 0 THEN
    RAISE EXCEPTION '0484 V1: the charge stop is not the body this file writes';
  END IF;
  -- V2: one overload, the ACL unchanged.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'twin' AND p.proname = 'ottoq_sim_stop_charge_session') <> 1 THEN
    RAISE EXCEPTION '0484 V2: an overload appeared';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'twin.ottoq_sim_stop_charge_session(uuid,text,timestamp with time zone,text,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0484 V2: the ACL moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0484_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0484_a_finished_charge_kept_its_charger_booked_and_reserved_so_the_car_held_it_from_staging', true,
  'Tick path: twin.ottoq_sim_stop_charge_session ends the car''s active charge booking when the plug is free and clears '
  'the stall''s reservation if it is still this car''s, so a finished or fault-moved car stops holding the charger.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
