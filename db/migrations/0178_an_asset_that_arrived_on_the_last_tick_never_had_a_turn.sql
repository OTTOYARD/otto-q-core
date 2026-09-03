-- =====================================================================
-- 0178  An asset that arrived on the last tick never had a turn
-- =====================================================================
-- The other half of the finding in db/checks/0084 section 6. 0176 fixed
-- the deadline side; this fixes the arrival side.
--
--   no_asset_starves_while_a_capable_point_is_free   FALSE
--   "2 of 4 assets ended below their own target SoC having never been
--    assigned a charge point while one stood free"
--
-- Both of those assets (4384f56b, 4e59acce) arrived at 05:00:00 - the
-- run's FINAL decision clock. There was no tick after their arrival in
-- which they could have been seated. The check was reporting the
-- horizon, not the engine, and it could never pass on a short run.
--
-- Fourth instance of one shape:
--   0170  returns_unserved counted work due beyond the horizon
--   0172  a return stamped after the run ended never happened
--   0176  a dispatch deadline beyond the horizon was never missed
--   0178  an asset that arrived on the last tick never had a turn
--
-- The rule, once more: a run may only be judged on what it had time to
-- do. An asset whose earliest arrival is at or after the last decision
-- clock is EXCLUDED from the starvation judgement and REPORTED in the
-- detail, never silently dropped and never counted as starved.
--
-- Deliberately minimal. An asset with NO visit in this run keeps its
-- previous treatment (COALESCE to -infinity leaves it judged): it may
-- have been at the depot all along, and widening the exclusion to
-- "never arrived" would change what the check means, not just when it
-- can be trusted.
--
-- forces_recert = false. twin.ottoq_grid_assert is a check function -
-- nothing on the tick path calls it, and it cannot alter a run.
-- =====================================================================

DO $do$
DECLARE
  v_src text; v_n int;
  a_from CONSTANT text :=
    '      FROM public.vehicles v WHERE v.home_depot_id = v_depot AND v.category = ''autonomous'') x;';
  a_code CONSTANT text :=
    '  check_code := ''no_asset_starves_while_a_capable_point_is_free''; passed := (n > 0 AND n2 = 0);';
  f_from CONSTANT text :=
    '      FROM public.vehicles v WHERE v.home_depot_id = v_depot AND v.category = ''autonomous'''||E'\n'||
    '        /* 0178: only assets that had a tick in which to be seated. An asset'||E'\n'||
    '           whose earliest arrival is at or after the last decision clock of the run'||E'\n'||
    '           had no opportunity at all; counting it starved reports the horizon,'||E'\n'||
    '           not the engine. An asset with no visit at all keeps its previous'||E'\n'||
    '           treatment. Same family as 0170/0172/0176. */'||E'\n'||
    '        AND COALESCE((SELECT min(vn2.arrived_at) FROM public.ottoq_visit_needs vn2'||E'\n'||
    '                       WHERE vn2.sim_run_id = p_run AND vn2.vehicle_id = v.id),'||E'\n'||
    '                     ''-infinity''::timestamptz)'||E'\n'||
    '            < (SELECT max(d3.sim_clock) FROM public.ottoq_decisions d3'||E'\n'||
    '                WHERE d3.sim_run_id = p_run)) x;';
  f_code CONSTANT text :=
    '  /* 0178: how many were set aside for arriving too late to be seated */'||E'\n'||
    '  SELECT count(*) INTO n3 FROM public.vehicles v'||E'\n'||
    '   WHERE v.home_depot_id = v_depot AND v.category = ''autonomous'''||E'\n'||
    '     AND COALESCE((SELECT min(vn2.arrived_at) FROM public.ottoq_visit_needs vn2'||E'\n'||
    '                    WHERE vn2.sim_run_id = p_run AND vn2.vehicle_id = v.id),'||E'\n'||
    '                  ''-infinity''::timestamptz)'||E'\n'||
    '         >= (SELECT max(d3.sim_clock) FROM public.ottoq_decisions d3'||E'\n'||
    '              WHERE d3.sim_run_id = p_run);'||E'\n'||
    '  check_code := ''no_asset_starves_while_a_capable_point_is_free''; passed := (n > 0 AND n2 = 0);';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_grid_assert';
  IF v_src IS NULL THEN RAISE EXCEPTION '0178: twin.ottoq_grid_assert not found'; END IF;

  IF position('0178: only assets that had a tick' in v_src) > 0 THEN
    RAISE NOTICE '0178: already applied; nothing to do'; RETURN;
  END IF;

  v_n := (length(v_src) - length(replace(v_src, a_from, ''))) / length(a_from);
  IF v_n <> 1 THEN RAISE EXCEPTION '0178: from-anchor occurs % times, expected 1', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, a_code, ''))) / length(a_code);
  IF v_n <> 1 THEN RAISE EXCEPTION '0178: code-anchor occurs % times, expected 1', v_n; END IF;

  v_src := replace(v_src, a_from, f_from);
  v_src := replace(v_src, a_code, f_code);

  -- the detail line must say what was set aside, or the exclusion is a silent cap
  v_src := replace(v_src,
    'detail := n2||'' of ''||n||'' assets ended below their own target SoC having never been assigned a charge point while one stood free''',
    'detail := n2||'' of ''||n||'' assets ended below their own target SoC having never been assigned a charge point while one stood free'''
    ||E'\n'||'            ||CASE WHEN n3 > 0 THEN '' (''||n3||'' set aside: arrived at or after the last decision clock, so never had a turn)'' ELSE '''' END');

  EXECUTE v_src;
  RAISE NOTICE '0178: starvation check now judges only assets that had a turn';
END
$do$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('an_asset_that_arrived_on_the_last_tick_never_had_a_turn', false,
        'twin.ottoq_grid_assert check 12 counted an asset as starved when it had never been assigned a charge point, without asking whether it arrived early enough to be seated at all. On the 0169 grid smoke two of four assets arrived at 05:00:00 - the run''s final decision clock - so no tick existed in which they could be seated, and the check reported the horizon rather than the engine. Assets whose earliest arrival is at or after the last decision clock are now excluded and reported in the detail rather than counted starved or silently dropped. Fourth instance of the shape closed by 0170, 0172 and 0176. Check function only; nothing on the tick path calls it and it cannot alter a run.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
