-- =====================================================================
-- 0160r  Repair: an anchor must be UNIQUE, not merely present
--        Harness only; forces_recert = false.
-- =====================================================================
-- 0160's edit (b) anchored on "AND s2.ocpp_charger_id IS NOT NULL", which
-- occurs TWICE in twin.ottoq_grid_assert - in check 5, where the outer alias d
-- is in scope, and in check 12, where it is not. replace() rewrites every
-- occurrence, so check 12 became "missing FROM-clause entry for table d" and
-- the entire assertion function failed at runtime. Caught within a minute by
-- the next live A/B run, which is the whole argument for a twenty-second test
-- loop.
--
-- 0155 guarded against precisely this by COUNTING occurrences and raising when
-- the count was not 1. 0160 checked only position() <> 0. The standing rule,
-- applied here and to every future anchored edit: ASSERT THE COUNT, NEVER MERE
-- PRESENCE.
--
-- Verified live after this repair, on grid-starve (cap 150, seed 424242, 12
-- ticks), all three charge_downgrade_policy modes:
--   mode 0 wait_for_wanted  12 of 13   fails exactly
--                                      no_asset_starves_while_a_capable_point_is_free
--                                      (end SoC 73 / 60 / 100 / 89 - it really does starve)
--   mode 1 fit_now          13 of 13   (end SoC 100 / 96 / 100 / 90)
--   mode 2 deadline_aware   13 of 13   (end SoC 100 / 96 / 100 / 90; one
--                                      downgrade instead of two, one hold
--                                      recorded as slow_point_misses_due_at)
-- =====================================================================

DO $patch$
DECLARE v_src text; v_injected text; v_before text; v_after text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_grid_assert';

  v_injected := chr(10)||'                             AND (s2.reserved_by IS NULL OR s2.reserved_by = d.entity_id'
             || ' OR s2.reservation_expires_at <= d.sim_clock)  /* 0160 */';
  v_n := (length(v_src) - length(replace(v_src, v_injected, ''))) / length(v_injected);
  IF v_n <> 2 THEN RAISE EXCEPTION '0160r: expected 2 injected clauses to strip, found %', v_n; END IF;
  v_src := replace(v_src, v_injected, '');

  v_before := '                             AND s2.stall_type::text = d.enacted_action->''rationale''->>''wanted_type'''
           || chr(10) || '                             AND s2.ocpp_charger_id IS NOT NULL';
  v_n := (length(v_src) - length(replace(v_src, v_before, ''))) / length(v_before);
  IF v_n <> 1 THEN RAISE EXCEPTION '0160r: check-5 anchor must occur exactly once, found %', v_n; END IF;
  v_after := v_before || chr(10)
          || '                             AND (s2.reserved_by IS NULL OR s2.reserved_by = d.entity_id'
          || ' OR s2.reservation_expires_at <= d.sim_clock)  /* 0160 */';
  v_src := replace(v_src, v_before, v_after);

  v_n := (length(v_src) - length(replace(v_src, 'held_for_wanted', ''))) / length('held_for_wanted');
  IF v_n <> 1 THEN RAISE EXCEPTION '0160r: expected exactly 1 held_for_wanted clause, found %', v_n; END IF;

  EXECUTE v_src;
END $patch$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('repair_0160_the_anchor_must_be_unique_not_merely_present', false,
        'Harness repair: 0160 anchored on a line occurring twice and broke check 12. Both copies stripped, one re-inserted on an anchor unique to check 5. Standing rule recorded: anchored edits assert the occurrence COUNT, never mere presence.',
        now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
