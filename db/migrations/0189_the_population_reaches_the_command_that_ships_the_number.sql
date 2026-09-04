-- =====================================================================
-- 0189  The population reaches the command that ships the number
-- =====================================================================
-- forces_recert = FALSE. Reader only.
--
-- 0188 gave KPI 5 four columns naming the population its percentile was
-- drawn from. 0185 established why that is not finished until they reach
-- ottoq_kpi_five: a diagnostic invisible from the one command that ships
-- the number is half a fix. Same pair of migrations, same reason.
--
-- WHAT IT MAKES VISIBLE
-- ---------------------------------------------------------------------
--   run 85034701   p95 244.5 min   118 of 118 dispatches   100.0%
--   run 9291ec6d   p95   1.2 min    44 of  94 dispatches    46.8%
--   run b54929ce   p95    null       0 of  91 dispatches     0.0%
--
-- Those three lines are the argument. Read without the population,
-- 9291ec6d's 1.2 minutes looks like the best result of the three and
-- 85034701's 244.5 looks like the worst. Read with it, 244.5 is the only
-- one measured over its whole fleet, and 1.2 is what remains after the
-- half of the run most likely to have been slow was dropped.
--
-- An anchored edit rather than a retyped function: the guard asserts the
-- anchor occurs exactly once and refuses otherwise, so drift since 0185
-- cannot be silently overwritten.
-- =====================================================================

DO $do$
DECLARE
  v_src text; v_n int;
  v_anchor CONSTANT text :=
'            ''max_time_to_service_min'',         max_time_to_service_min)';
  v_fixed CONSTANT text :=
'            ''max_time_to_service_min'',         max_time_to_service_min,
            /* 0189: the POPULATION the percentile was drawn from. A p95 of
               1.2 min over 44 of 94 dispatches is not the same claim as a
               p95 of 1.2 min over all of them, and until 0188 the payload
               could not tell them apart. dispatches_admitted is what the
               percentile actually saw; the other two say why the rest are
               missing. */
            ''dispatches_total'',                 dispatches_total,
            ''dispatches_admitted'',              dispatches_admitted,
            ''dispatches_never_returned'',        dispatches_never_returned,
            ''dispatches_returned_past_horizon'', dispatches_returned_past_horizon)';
BEGIN
  SELECT pg_get_functiondef('public.ottoq_kpi_five(uuid)'::regprocedure) INTO v_src;
  IF v_src IS NULL THEN RAISE EXCEPTION '0189: ottoq_kpi_five not found'; END IF;

  IF position('0189: the POPULATION' in v_src) > 0 THEN
    RAISE NOTICE '0189: already applied; nothing to do'; RETURN;
  END IF;

  -- count, not presence
  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0189: audit-block anchor occurs % times, expected 1', v_n;
  END IF;

  EXECUTE replace(v_src, v_anchor, v_fixed);
  RAISE NOTICE '0189: KPI 5 population surfaced through ottoq_kpi_five';
END
$do$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_population_reaches_the_command_that_ships_the_number', false,
        'public.ottoq_kpi_five audit block extended with the four population columns 0188 added to KPI 5: dispatches_total, dispatches_admitted, dispatches_never_returned, dispatches_returned_past_horizon. Same pairing and same reason as 0182/0183/0184 followed by 0185 - a diagnostic that does not reach the one command shipping the number is half a fix. What it makes visible, on three real runs: 85034701 reports p95 244.5 min over 118 of 118 dispatches (100 percent), 9291ec6d reports p95 1.2 min over 44 of 94 (46.8 percent), b54929ce reports p95 null over 0 of 91 (0 percent). Read without the population, 9291ec6d looks like the best of the three and 85034701 the worst; read with it, 244.5 is the only figure measured over a whole fleet and 1.2 is what survives after the half of the run most likely to have been slow was dropped. Applied as an anchored edit whose guard asserts the anchor occurs exactly once and refuses otherwise, so drift since 0185 cannot be silently overwritten. forces_recert=false: reader only, no engine path calls it.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
