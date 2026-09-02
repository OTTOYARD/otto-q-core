-- 0166  Starved means below its OWN target, not below ninety. Harness; forces_recert = false.
--
-- Assertion 12 (0157) called an asset starved when it ended under a hard-coded
-- 90% having never been assigned a charge point. On grid-f8 (a DCFC down two
-- hours) it fired for an asset that ended at 88% and had simply never needed a
-- charge - fleet end SoCs were 88 / 90 / 100 / 90 and every asset that wanted
-- power got it.
--
-- Same error as the first cut of the readiness KPI (0158), where counting
-- vehicles that arrived full as misses turned 17% into 32%: a fixed threshold is
-- not a statement about need. An asset is starved when it is below ITS OWN
-- target - ottoq_visit_needs.target_soc, falling back to
-- ottoq_default_target_soc() - and was never offered a point while one stood
-- free. The 90 was mine, not the engine's, and it was wrong in exactly the
-- direction that manufactures false alarms under degraded conditions, which is
-- when a check most needs to be trusted.
--
-- After: F1 (permanent outage) and F2 (2-hour outage that heals) both 14 of 14.
DO $patch$
DECLARE v_src text; v_before text; v_after text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_grid_assert';
  v_before := '           (v.current_soc < 90';
  v_n := (length(v_src) - length(replace(v_src, v_before, ''))) / length(v_before);
  IF v_n <> 1 THEN RAISE EXCEPTION '0166: starvation threshold anchor must occur exactly once, found %', v_n; END IF;
  v_after := '           (v.current_soc < COALESCE((SELECT max(vn.target_soc) FROM public.ottoq_visit_needs vn'
          || ' WHERE vn.sim_run_id = p_run AND vn.vehicle_id = v.id), public.ottoq_default_target_soc())  /* 0166 */';
  v_src := replace(v_src, v_before, v_after);
  EXECUTE v_src;
END $patch$;

DO $patch$
DECLARE v_src text; v_before text; v_after text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_grid_assert';
  v_before := ''' assets ended under 90% having never been assigned a charge point while one stood free''';
  v_n := (length(v_src) - length(replace(v_src, v_before, ''))) / length(v_before);
  IF v_n <> 1 THEN RAISE EXCEPTION '0166: starvation detail anchor must occur exactly once, found %', v_n; END IF;
  v_after := ''' assets ended below their own target SoC having never been assigned a charge point while one stood free''';
  v_src := replace(v_src, v_before, v_after);
  EXECUTE v_src;
END $patch$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('starved_means_below_its_own_target_not_below_ninety', false,
        'Harness: grid assertion 12 judges starvation against the asset''s own target_soc rather than a hard-coded 90%, which was manufacturing false alarms under degraded conditions.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
