-- =====================================================================
-- 0155  The site meter reports the power that flowed
--       TWIN APPARATUS (the wiring), not the engine's judgment.
-- =====================================================================
-- Chase, Sep 2: "If the energy source is incorrect in its wiring, that's
-- just a sim/twin testing apparatus fix. Still needs adjustment, but
-- isn't the same as 'otto-q incorrectly read the energy signal'."
--
-- This migration is that first category. It is nonetheless not cosmetic:
-- site_energy_snapshots.total_ev_charging_kw is the input to
-- peak_demand_kw_15min, which IS peak_site_kw - one of the five
-- canonical KPIs (CLAUDE.md 2.9), the one that "matches demand billing."
-- Measured on the grid fixture before this change: the meter read
-- 0.00 kW at all twelve ticks of a run in which the plan committed
-- 75-157 kW and four charging sessions completed. peak_site_kw computed
-- off that substrate is not a conservative number, it is a wrong one.
--
-- FOUR DEFECTS, all in the twin's emulation, none in the decide path.
--
-- 1. twin.ottoq_sim_start_charge_session wrote last_meter_value with
--    'power_kw', 0::numeric - a placeholder - while the initial rate it
--    had just computed (v_init_rate) sat in the very same INSERT, in
--    peak_power_kw. So a session reported zero for its whole first tick.
--    Same class as the OTTO-Defense diesel-to-charger fix: attest the
--    value you actually have, never a placeholder.
--
-- 2. twin.ottoq_sim_compute_charger_load_kw filtered status = 'active'.
--    The twin advances a session (writing its first real meter value)
--    and closes it on target-SoC in the SAME tick, so a session shorter
--    than two ticks was never once counted, and every session's final
--    tick counted as zero. The time predicate already says "drawing at
--    this instant"; status only has to exclude sessions that never
--    delivered.
--
-- 3. The same function scoped on sim_run_id = ottoq_depot_running_run(
--    depot). That function returns NULL when no sim run is running, and
--    "= NULL" matches nothing - so on a depot with no sim run the
--    charger load reads 0 kW unconditionally. The 0020/0124 zero-uuid
--    idiom makes a NULL run match a NULL run instead.
--
-- 4. twin.ottoq_sim_advance_site_energy carried v_dcfc_cap_kw := 1800
--    and v_service_cap_kw := 2500 as LITERALS - the flagship's own
--    numbers - so twin.dcfc_cap_exceeded / dcfc_cap_approached could not
--    fire on any other depot and fired on a stale threshold for a
--    re-rated one. Its DCFC sum was depot-scoped, not run-scoped (0145
--    class), and its demand-response lookup had LIMIT 1 with no ORDER BY
--    and no run scope (0062/0063 class: a coin flip with two open
--    calls). ottoq_effective_charge_cap_kw already reads DR calls the
--    right way; this one now matches it.
--
-- MEASURED, same fixture (grid-mtr, seed 424242, 12 ticks, cap 600 kW),
-- both arms of a pair, rolled back:
--   before  meter by tick: 0.00 x 12                     peak_ev 0.00 kW
--   after   meter by tick: 0, 0, 0, 0, 16.9, 12.0, 0,
--                          244.9, 212.7, 0, 0, 0          peak_ev 244.90 kW
--   sessions after: L2-02 16.87 kW peak, DCFC-02 132.51, DCFC-01 118.24
--   244.90 = 132.51 + 118.24 at 06:00 (both DCFC live); 212.70 = 132.51
--   + 80.16 at 06:30 as the second taper. The meter now reconciles with
--   the sessions.
--
-- forces_recert = TRUE. The engine reads site load (BESS dispatch, the
-- energy orchestrator's net_load_kw), so correcting the meter moves the
-- canon. Round 7 closed green at 9:50 AM CT Sep 2 before this was
-- applied; round 8 certifies the corrected twin.
-- =====================================================================

-- ---------------------------------------------------------------- 1 of 3
CREATE OR REPLACE FUNCTION twin.ottoq_sim_compute_charger_load_kw(p_depot_id uuid, p_sim_clock_now timestamp with time zone)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  /* 0155: THE METER MUST SEE THE POWER THAT FLOWED. status='active'
     excluded a session that ENDED during this very tick (defect 2), and
     ottoq_depot_running_run(depot) is NULL off-sim so "= NULL" matched
     nothing (defect 3). The time predicate already means "drawing at this
     instant"; status only excludes what never delivered. */
  SELECT COALESCE(SUM(((last_meter_value->>'power_kw'))::numeric), 0)
    FROM ocpp_sessions cs
   WHERE cs.depot_id = p_depot_id
     AND cs.status IN ('active'::ocpp_session_status, 'completed'::ocpp_session_status)
     AND cs.started_at <= p_sim_clock_now
     AND (cs.ended_at IS NULL OR cs.ended_at >= p_sim_clock_now)
     AND COALESCE(cs.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = COALESCE(ottoq_depot_running_run(p_depot_id), '00000000-0000-0000-0000-000000000000'::uuid);
$function$;

-- ---------------------------------------------------------------- 2 of 3
-- A session is born reporting the rate it is actually drawing.
-- Anchored edit: assert the placeholder occurs exactly once, replace it,
-- re-execute the definition. The guard is the point - if the function is
-- ever rewritten without that literal, this migration fails loudly
-- instead of silently doing nothing.
DO $patch$
DECLARE v_src text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_start_charge_session';
  v_n := (length(v_src) - length(replace(v_src, '''power_kw'', 0::numeric', '')))
         / length('''power_kw'', 0::numeric');
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0155/2: expected exactly 1 meter placeholder in ottoq_sim_start_charge_session, found %', v_n;
  END IF;
  v_src := replace(v_src, '''power_kw'', 0::numeric',
                          '''power_kw'', ROUND(v_init_rate::numeric, 2)');
  EXECUTE v_src;
END $patch$;

-- ---------------------------------------------------------------- 3 of 3
DO $patch$
DECLARE v_src text; v_before text; v_after text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_site_energy';

  -- 3a. the flagship's numbers stop standing in for every depot's
  v_before := '  v_dcfc_cap_kw      NUMERIC := 1800;' || chr(10) || '  v_service_cap_kw   NUMERIC := 2500;';
  v_after  := '  v_dcfc_cap_kw      NUMERIC;' || chr(10) || '  v_service_cap_kw   NUMERIC;';
  IF position(v_before IN v_src) = 0 THEN RAISE EXCEPTION '0155/3a: cap literals not found'; END IF;
  v_src := replace(v_src, v_before, v_after);

  -- 3b. filled from the depot row (NULL = no declared cap = no event, correctly)
  v_before := '  v_salt := to_char(p_sim_clock_now, ''YYYYMMDD-HH24MISS'');';
  v_after  := v_before || chr(10)
           || '  SELECT d.dcfc_max_concurrent_kw, d.service_max_kw INTO v_dcfc_cap_kw, v_service_cap_kw' || chr(10)
           || '    FROM public.depots d WHERE d.id = p_depot_id;';
  IF position(v_before IN v_src) = 0 THEN RAISE EXCEPTION '0155/3b: salt anchor not found'; END IF;
  v_src := replace(v_src, v_before, v_after);

  -- 3c. the DCFC sum: this run only, and count a session that ended in this tick
  v_before := '     AND cs.status = ''active''::ocpp_session_status' || chr(10)
           || '     AND cs.started_at <= p_sim_clock_now' || chr(10)
           || '     AND (cs.ended_at IS NULL OR cs.ended_at >= p_sim_clock_now);';
  v_after  := '     AND cs.status IN (''active''::ocpp_session_status, ''completed''::ocpp_session_status)' || chr(10)
           || '     AND cs.started_at <= p_sim_clock_now' || chr(10)
           || '     AND (cs.ended_at IS NULL OR cs.ended_at >= p_sim_clock_now)' || chr(10)
           || '     AND COALESCE(cs.sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)' || chr(10)
           || '       = COALESCE(p_sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid);';
  IF position(v_before IN v_src) = 0 THEN RAISE EXCEPTION '0155/3c: dcfc sum predicate not found'; END IF;
  v_src := replace(v_src, v_before, v_after);

  -- 3d. the demand-response call: run-scoped and tie-broken
  v_before := '   WHERE depot_id = p_depot_id AND call_status = ''active''' || chr(10)
           || '     AND expires_at > p_sim_clock_now LIMIT 1;';
  v_after  := '   WHERE depot_id = p_depot_id AND call_status = ''active''' || chr(10)
           || '     AND expires_at > p_sim_clock_now' || chr(10)
           || '     AND COALESCE(sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)' || chr(10)
           || '       = COALESCE(p_sim_run_id, ''00000000-0000-0000-0000-000000000000''::uuid)' || chr(10)
           || '   ORDER BY required_load_cap_kw ASC, dr_call_id LIMIT 1;';
  IF position(v_before IN v_src) = 0 THEN RAISE EXCEPTION '0155/3d: dr call predicate not found'; END IF;
  v_src := replace(v_src, v_before, v_after);

  EXECUTE v_src;
END $patch$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_site_meter_reports_the_power_that_flowed', true,
        'Twin apparatus: session meters seeded with the real initial rate, the site load counts a session that ended in this tick and is run-scoped off-sim, and the site energy step reads the depot''s caps instead of the flagship''s literals. Moves the canon because the engine reads site load.',
        now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
