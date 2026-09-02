-- =====================================================================
-- 0163  A fault needs a clock and a repair time
--       forces_recert = TRUE; inert for any depot declaring no fault.
-- =====================================================================
-- ASK WHY BEFORE PATCHING AGAIN. 0161 injected a charger fault and the run
-- booked on the broken point anyway. 0162 blamed the seeded-world reset and
-- re-applied the fault after it. The run STILL booked on the broken point.
-- The second failure is the useful one, because the premise was wrong both
-- times.
--
-- twin.ottoq_sim_recover_chargers runs on EVERY tick (from
-- twin.ottoq_world_advance and public.ottoq_sim_advance_tick_world) and
-- repairs any Faulted charger whose station_state_changed_at is older than its
-- repair window:
--     WHERE station_state = 'Faulted'
--       AND station_state_changed_at <= p_sim_clock
--           - COALESCE((last_fault_payload->>'repair_minutes')::numeric,
--                      p_repair_minutes) * '1 minute'
-- I stamped the injected fault station_state_changed_at = 'epoch' - 1970 -
-- copying the canonicalization idiom from 0093/0094 without asking what that
-- column MEANS to the recovery model. An epoch timestamp makes a fault
-- infinitely old, so it is eligible for repair on the very first tick. The
-- twin healed it immediately and correctly, every time.
--
-- So the engine was right three times over: it booked a healthy charger,
-- because the charger WAS healthy. What was wrong was my injection (a
-- meaningless clock), my diagnosis (blaming the reset), and nearly my
-- assertion. 'epoch' is the correct canonical value for a charger with NO
-- fault - exactly what 0093 uses it for - and the wrong value for one WITH a
-- fault.
--
-- THE FIX uses the twin's own model rather than working around it. A declared
-- fault carries a duration, stored as last_fault_payload.repair_minutes - the
-- per-charger knob ottoq_sim_recover_chargers already honours - and is stamped
-- with the reset's as-of clock. A fault declared to outlast the horizon stays
-- down all run; a short repair time heals mid-run, which is the
-- mid-session-fault scenario from CLAUDE.md C7.3 and is now expressible.
--
-- VERIFIED live on grid-f4 (seed 424242, 12 ticks, cap 600 kW), rolled back:
--   charger after run   Faulted / fault.injected_offline / repair=100000
--   fault assertion     0 bookings landed on the broken point (31 in the run)
--   sessions on it      0
--   pair verdict        passed, equal = true   (both arms identically broken)
--   end SoC             100 / 81 / 90 / 100   vs 100 / 96 / 100 / 90 healthy
-- The first genuine failure-scenario run in this system: a charger dies, the
-- engine routes around it, the fleet degrades rather than collapses, and
-- determinism holds.
-- =====================================================================

CREATE OR REPLACE FUNCTION twin.ottoq_grid_fault(p_slug text, p_kind text, p_duration_minutes int DEFAULT 100000)
 RETURNS text LANGUAGE plpgsql
AS $fn$
DECLARE
  v_depot uuid := md5('ottoq_grid_fixture:'||p_slug)::uuid;
  v_stall RECORD; v_note text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.depots WHERE id = v_depot) THEN
    RAISE EXCEPTION 'grid fault: fixture % does not exist', p_slug;
  END IF;
  IF p_kind = 'charger_offline' THEN
    SELECT s.id, s.stall_code, s.ocpp_charger_id INTO v_stall
      FROM public.stalls s
     WHERE s.depot_id = v_depot AND s.stall_type::text = 'dcfc' AND s.ocpp_charger_id IS NOT NULL
     ORDER BY s.stall_code LIMIT 1;
    IF v_stall.id IS NULL THEN RAISE EXCEPTION 'grid fault: no DCFC point with a charger on %', p_slug; END IF;
    v_note := 'charger_offline on '||v_stall.stall_code||' for '||p_duration_minutes||' min';
  ELSIF p_kind = 'point_blocked' THEN
    SELECT s.id, s.stall_code INTO v_stall
      FROM public.stalls s WHERE s.depot_id = v_depot AND s.stall_type::text = 'staging'
     ORDER BY s.stall_code LIMIT 1;
    IF v_stall.id IS NULL THEN RAISE EXCEPTION 'grid fault: no staging point on %', p_slug; END IF;
    UPDATE public.stalls SET status = 'blocked' WHERE id = v_stall.id;
    v_note := 'point_blocked on '||v_stall.stall_code;
  ELSE
    RAISE EXCEPTION 'grid fault: unknown kind % (charger_offline, point_blocked)', p_kind;
  END IF;
  /* The declaration is the durable thing; the reset re-applies it with a real
     clock before every arm. Applying it here as well would be healed on tick
     one, which is precisely the 0161/0162 mistake. */
  UPDATE public.depots
     SET config = COALESCE(config,'{}'::jsonb) || jsonb_build_object(
           'injected_fault', jsonb_build_object('kind', p_kind, 'stall_id', v_stall.id,
                                                'stall_code', v_stall.stall_code,
                                                'repair_minutes', p_duration_minutes))
   WHERE id = v_depot;
  RETURN v_note;
END;
$fn$;

DO $patch$
DECLARE v_src text; v_before text; v_after text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_tick_invariance_reset_fleet';
  v_before := '           SET station_state = ''Faulted'', last_fault_code = ''fault.injected_offline'',' || chr(10)
           || '               station_state_changed_at = ''epoch''::timestamptz';
  v_n := (length(v_src) - length(replace(v_src, v_before, ''))) / length(v_before);
  IF v_n <> 1 THEN RAISE EXCEPTION '0163: 0162 charger-fault anchor must occur exactly once, found %', v_n; END IF;
  v_after := '           SET station_state = ''Faulted'', last_fault_code = ''fault.injected_offline'',' || chr(10)
          || '               last_fault_payload = jsonb_build_object(''repair_minutes'',' || chr(10)
          || '                 COALESCE((v_fault->>''repair_minutes'')::numeric, 100000)),' || chr(10)
          || '               station_state_changed_at = COALESCE(p_as_of, ''epoch''::timestamptz)';
  v_src := replace(v_src, v_before, v_after);
  EXECUTE v_src;
END $patch$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('a_fault_needs_a_clock_and_a_repair_time', true,
        'A declared charger fault is stamped with the reset''s as-of clock and carries repair_minutes in last_fault_payload, the per-charger knob twin.ottoq_sim_recover_chargers already honours. Stamping it ''epoch'' (the canonical value for NO fault, per 0093/0094) made every injected fault infinitely old and therefore repaired on tick one - which is why 0161 and 0162 both looked like engine defects and were not.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
