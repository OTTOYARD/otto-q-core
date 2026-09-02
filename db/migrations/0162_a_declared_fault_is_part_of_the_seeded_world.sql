-- =====================================================================
-- 0162  A declared fault is part of the seeded world
--       forces_recert = TRUE; inert for any depot declaring no fault.
--       Its clock was WRONG - corrected by 0163. Kept for the record.
-- =====================================================================
-- 0161 set a grid charger Faulted and the run still booked on it. I blamed
-- ottoq_tick_invariance_reset_fleet - the reset the determinism pair runs
-- before EACH arm so both start identically - which sets every charger back
-- to Available and clears last_fault_code. That reset is not a mistake; its
-- own comment records why:
--   "0093: sim-injected charger faults survive the teardown reconcile; a
--    seeded world reset canonicalizes them (measured: 4 chargers stuck
--    non-Available)."
--
-- THE DISTINCTION THIS DRAWS, which is right and stands: a LEFTOVER fault is
-- residue and must be canonicalized away; a DECLARED fault is part of the
-- world definition and must be re-applied after canonicalizing, so both arms
-- start identically broken and determinism is preserved.
--
-- WHAT WAS STILL WRONG: this re-applied the fault with station_state_changed_at
-- = 'epoch' too, so the twin's per-tick repair model healed it on tick one
-- exactly as before. The run after this migration was byte-for-byte as broken
-- as the run before it. See 0163.
-- =====================================================================

DO $patch$
DECLARE v_src text; v_before text; v_after text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_tick_invariance_reset_fleet';
  v_before := chr(10) || '  RETURN v_n;' || chr(10) || 'END;';
  v_n := (length(v_src) - length(replace(v_src, v_before, ''))) / length(v_before);
  IF v_n <> 1 THEN RAISE EXCEPTION '0162: tail anchor must occur exactly once, found %', v_n; END IF;
  v_after := chr(10) || chr(10)
    || '  /* 0162: A DECLARED FAULT IS PART OF THE SEEDED WORLD. Everything above' || chr(10)
    || '     canonicalizes residue away (0093). A fault the fixture DECLARES is not' || chr(10)
    || '     residue - it is the world we meant to test - so it is re-applied here,' || chr(10)
    || '     after canonicalization, identically for every arm. */' || chr(10)
    || '  DECLARE v_fault jsonb; BEGIN' || chr(10)
    || '    SELECT d.config->''injected_fault'' INTO v_fault FROM public.depots d WHERE d.id = p_depot_id;' || chr(10)
    || '    IF v_fault IS NOT NULL THEN' || chr(10)
    || '      IF v_fault->>''kind'' = ''charger_offline'' THEN' || chr(10)
    || '        UPDATE public.ottoq_ocpp_chargers c' || chr(10)
    || '           SET station_state = ''Faulted'', last_fault_code = ''fault.injected_offline'',' || chr(10)
    || '               station_state_changed_at = ''epoch''::timestamptz' || chr(10)
    || '         WHERE c.charger_id = (SELECT s.ocpp_charger_id FROM public.stalls s' || chr(10)
    || '                                WHERE s.id = (v_fault->>''stall_id'')::uuid);' || chr(10)
    || '      ELSIF v_fault->>''kind'' = ''point_blocked'' THEN' || chr(10)
    || '        UPDATE public.stalls SET status = ''blocked''' || chr(10)
    || '         WHERE id = (v_fault->>''stall_id'')::uuid;' || chr(10)
    || '      END IF;' || chr(10)
    || '    END IF;' || chr(10)
    || '  END;' || chr(10) || chr(10)
    || '  RETURN v_n;' || chr(10) || 'END;';
  v_src := replace(v_src, v_before, v_after);
  EXECUTE v_src;
END $patch$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('a_declared_fault_is_part_of_the_seeded_world', true,
        'Certification reset re-applies depots.config->injected_fault after canonicalizing residue. Clock corrected by 0163.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
