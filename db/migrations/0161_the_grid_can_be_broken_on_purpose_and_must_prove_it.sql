-- =====================================================================
-- 0161  The grid can be broken on purpose, and must prove it
--       INSTRUMENT. Harness only; forces_recert = false.
--       Its injection was WRONG - see 0163. Kept because the mistake is
--       the lesson. Assertion 14 introduced here is correct and stands.
-- =====================================================================
-- THE GAP, measured. Only four functions read ottoq_scenarios at all:
--   public.ottoq_sim_run_scenario   arrival_profile, timeline, initial_conditions
--   twin.ottoq_sim_start_run        scenario_code + random_seed ONLY
--   public.ottoq_production_start   scenario_code
--   twin.ottoq_grid_fixture_create  scenario_code
-- The certification path is ottoq_determinism_pair -> ottoq_sim_start_run,
-- so EVERY certification pair ever run honoured the scenario's seed and
-- nothing else. busy_day and normal_day differ to that path only by
-- random_seed; their arrival profiles and timelines are never read.
--
-- And charger_outage_morning_rush, the one failure scenario we own,
-- declares timeline.charger_overrides.force_offline_dcfc_count = 3 over
-- hours [7,9] - a key with ZERO readers anywhere in the database. Inert
-- twice over. CLAUDE.md C7.3's canonical nine had no channel into the
-- harness at all.
--
-- This opens the smallest honest one: inject the fault as WORLD STATE,
-- which the engine already reads, and REQUIRE THE RUN TO SHOW IT.
-- Assertion 14 fails when a fault is declared and no trace appears,
-- because a failure scenario that cannot prove it injected its failure
-- is exactly how charger_outage_morning_rush read as coverage while
-- testing nothing.
-- =====================================================================

CREATE OR REPLACE FUNCTION twin.ottoq_grid_fault(p_slug text, p_kind text)
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
    -- DEFECT (0163): 'epoch' is the canonical stamp for NO fault (0093/0094).
    -- Using it here made the fault infinitely old and therefore repaired on
    -- tick one by twin.ottoq_sim_recover_chargers.
    UPDATE public.ottoq_ocpp_chargers
       SET station_state = 'Faulted', last_fault_code = 'fault.injected_offline',
           station_state_changed_at = 'epoch'
     WHERE charger_id = v_stall.ocpp_charger_id;
    v_note := 'charger_offline on '||v_stall.stall_code;
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
  UPDATE public.depots
     SET config = COALESCE(config,'{}'::jsonb) || jsonb_build_object(
           'injected_fault', jsonb_build_object('kind', p_kind, 'stall_id', v_stall.id,
                                                'stall_code', v_stall.stall_code))
   WHERE id = v_depot;
  RETURN v_note;
END;
$fn$;

-- Assertion 14 appended by anchored edit with the occurrence COUNT asserted -
-- the rule 0160r had to learn the hard way. It refused a wrong anchor on the
-- first attempt here rather than corrupting the function, which is the point.
DO $patch$
DECLARE v_src text; v_before text; v_after text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_grid_assert';
  v_before := chr(10) || '  RETURN;' || chr(10) || 'END;';
  v_n := (length(v_src) - length(replace(v_src, v_before, ''))) / length(v_before);
  IF v_n <> 1 THEN RAISE EXCEPTION '0161: tail anchor must occur exactly once, found %', v_n; END IF;
  v_after := chr(10) || chr(10)
    || '  /* 14. 0161: A DECLARED FAULT MUST LEAVE A TRACE. */' || chr(10)
    || '  DECLARE v_f jsonb; v_fstall uuid; BEGIN' || chr(10)
    || '    SELECT d.config->''injected_fault'' INTO v_f FROM public.depots d WHERE d.id = v_depot;' || chr(10)
    || '    IF v_f IS NULL THEN' || chr(10)
    || '      check_code := ''injected_fault_was_met'';  passed := true;' || chr(10)
    || '      detail := ''NO FAULT INJECTED on this run - not evidence about failure handling'';' || chr(10)
    || '    ELSE' || chr(10)
    || '      v_fstall := (v_f->>''stall_id'')::uuid;' || chr(10)
    || '      SELECT count(*) INTO n FROM public.ottoq_stall_bookings b' || chr(10)
    || '       WHERE b.sim_run_id = p_run AND b.stall_id = v_fstall' || chr(10)
    || '         AND b.state IN (''held'',''active'',''done'');' || chr(10)
    || '      SELECT count(*) INTO n2 FROM public.ottoq_stall_bookings b WHERE b.sim_run_id = p_run;' || chr(10)
    || '      check_code := ''injected_fault_was_met'';' || chr(10)
    || '      passed := (n = 0 AND n2 > 0);' || chr(10)
    || '      detail := (v_f->>''kind'')||'' on ''||(v_f->>''stall_code'')||'': ''||n' || chr(10)
    || '                ||'' bookings landed on the broken point (''||n2||'' in the run)''' || chr(10)
    || '                ||CASE WHEN n2 = 0 THEN '' (vacuous: no bookings at all)'' ELSE '''' END;' || chr(10)
    || '    END IF;' || chr(10)
    || '    RETURN NEXT;' || chr(10)
    || '  END;' || chr(10) || chr(10)
    || '  RETURN;' || chr(10) || 'END;';
  v_src := replace(v_src, v_before, v_after);
  EXECUTE v_src;
END $patch$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_grid_can_be_broken_on_purpose_and_must_prove_it', false,
        'Harness: twin.ottoq_grid_fault injects a fault as world state and grid assertion 14 requires the run to show the engine met it. Injection clock corrected by 0163.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
