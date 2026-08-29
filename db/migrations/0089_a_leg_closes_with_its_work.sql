-- migration-version: 20260829191500
-- migration-name:    a_leg_closes_with_its_work
-- 0089 -- R8 of the run-reconciliation audit (db/checks/0045): the settlement contract has a
-- hole between the booking ledger and the leg ledger.
--
-- MEASURED on run 9291ec6d: 7 charge sessions closed 'done', but only 2 produced SDRs. The
-- missing 5 (2 dcfc, 3 l2) all closed via ottoq.ottoq_release_expired_bookings with
-- release_reason='window_elapsed_occupied' -- the charge ran its FULL planned window while the
-- vehicle occupied the stall, i.e. the work COMPLETED -- and that closer sets the booking to
-- 'done' but never touches booking.leg_id. The leg stays 'active' forever, and since the 0043
-- settlement trigger fires on leg -> 'done', those five completed operations were never
-- settled. "Every completed operation terminates in an SDR" held for every path except this one.
--
-- A second, related hole in the same lifecycle: public.ottoq_sim_release_depot (the run
-- finalizer) closes every ledger EXCEPT legs -- bookings released, commands expired (0087),
-- dispatches completed, stalls/vehicles reset -- and 30 legs on 9291ec6d sat 'active' on a
-- completed run forever (21 charge_l2, 7 charge_dcfc, 2 service).
--
-- TWO PATCHES:
--
-- 1. ottoq.ottoq_release_expired_bookings: the full-window close now also closes the leg the
--    booking serves ('planned'/'active' -> 'done', actual times from the booking window,
--    deviation vs the leg's own plan -- same idiom as ottoq_close_atom_leg). This is the fix
--    that makes the 0043 SDR trigger fire for window-elapsed charges. Only the 'done' branch
--    closes the leg: 'interrupted' and 'released' bookings are NOT completed work and must
--    never settle.
--
-- 2. public.ottoq_sim_release_depot: a run that ends leaves no leg open. Still-'active' legs
--    close 'amended' (the work happened and did not finish -- never 'done': settlement is only
--    for completed operations, so no SDR fires), still-'planned' legs close 'skipped', both
--    stamped with the run's final sim clock. Same EXCEPTION-WARN isolation as the finalizer's
--    other closers.
--
-- Checks 0045 R10 (done booking => done leg) and R11 (completed run leaves no open legs) were
-- added alongside this migration and are born red against 9291ec6d; historical rows stay as
-- evidence. A fresh run is the proof this fix works.
--
-- Pre-image pins, read live 2026-08-29 (each anchor verified at exactly 1 occurrence):
--   ottoq.ottoq_release_expired_bookings   3d41e748c15db513a3f6e3984ca507cb
--   public.ottoq_sim_release_depot         429ecb4a901eb931997f1c1545bc898b

DO $do$
DECLARE
  v_oid oid; v_src text; v_new text; v_cnt int;

  -- ---- Patch 1: the RETURNING tail of the window-elapsed closer's upd CTE. 'AS actual_s'
  --      makes this unique (the same EXTRACT appears twice more, un-aliased, in the CASEs).
  v_a1_old text := E'              EXTRACT(epoch FROM (LEAST(upper(b.during), p_clock) - lower(b.during)))::numeric AS actual_s\n'
                || E'  )\n'
                || E'  SELECT count(*)::int,';
  v_a1_new text := E'              EXTRACT(epoch FROM (LEAST(upper(b.during), p_clock) - lower(b.during)))::numeric AS actual_s,\n'
                || E'              b.leg_id, lower(b.during) AS win_start, upper(b.during) AS win_end\n'
                || E'  ),\n'
                || E'  -- 0089: a booking that ran its FULL window while occupied is COMPLETED WORK, and\n'
                || E'  -- the leg it serves closes with it. Closing the leg is what fires the 0043 SDR\n'
                || E'  -- trigger; before this fix the booking closed ''done'' and its leg stayed ''active''\n'
                || E'  -- forever, so five finished charges on run 9291ec6d were never settled (0045 R8).\n'
                || E'  legs AS (\n'
                || E'    UPDATE public.ottoq_itinerary_legs l\n'
                || E'       SET status = ''done'',\n'
                || E'           actual_start_sim = COALESCE(l.actual_start_sim, u.win_start),\n'
                || E'           actual_end_sim   = u.win_end,\n'
                || E'           deviation_s      = CASE WHEN l.planned_end_sim IS NULL THEN NULL\n'
                || E'                                   ELSE EXTRACT(EPOCH FROM (u.win_end - l.planned_end_sim))::int END\n'
                || E'      FROM upd u\n'
                || E'     WHERE u.state = ''done'' AND l.leg_id = u.leg_id\n'
                || E'       AND l.status IN (''planned'',''active'')\n'
                || E'  )\n'
                || E'  SELECT count(*)::int,';

  -- ---- Patch 2: the finalizer's booking-release block; the leg close goes right after it,
  --      so the two teardown steps that describe the same work sit together.
  v_a2_old text := E'  EXCEPTION WHEN OTHERS THEN RAISE WARNING ''release_depot booking release: %'', SQLERRM; END;';
  v_a2_new text := E'  EXCEPTION WHEN OTHERS THEN RAISE WARNING ''release_depot booking release: %'', SQLERRM; END;\n'
                || E'\n'
                || E'  -- 0089: a run that ends leaves no leg open. In-flight work closes ''amended'' (it\n'
                || E'  -- happened; it did not finish -- never ''done'', settlement is only for completed\n'
                || E'  -- operations, so no SDR fires) and never-started work closes ''skipped'', both\n'
                || E'  -- stamped with the run''s final sim clock. 30 legs on 9291ec6d sat ''active'' forever.\n'
                || E'  BEGIN\n'
                || E'    UPDATE ottoq_itinerary_legs l\n'
                || E'       SET status = ''amended'',\n'
                || E'           actual_end_sim = COALESCE(l.actual_end_sim,\n'
                || E'             (SELECT COALESCE(r.sim_clock_current, now()) FROM ottoq_sim_runs r\n'
                || E'               WHERE r.sim_run_id = p_sim_run_id))\n'
                || E'     WHERE l.sim_run_id = p_sim_run_id AND l.status = ''active'';\n'
                || E'    UPDATE ottoq_itinerary_legs l\n'
                || E'       SET status = ''skipped''\n'
                || E'     WHERE l.sim_run_id = p_sim_run_id AND l.status = ''planned'';\n'
                || E'  EXCEPTION WHEN OTHERS THEN RAISE WARNING ''release_depot leg close: %'', SQLERRM; END;';
BEGIN
  -- ---------- Patch 1: ottoq.ottoq_release_expired_bookings ----------
  SELECT p.oid INTO STRICT v_oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_release_expired_bookings';
  v_src := pg_get_functiondef(v_oid);

  IF md5(v_src) <> '3d41e748c15db513a3f6e3984ca507cb' THEN
    RAISE EXCEPTION '0089 abort: release_expired_bookings drifted from the pinned pre-image (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a1_old, ''))) / length(v_a1_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0089 abort: RETURNING-tail anchor found % times, expected 1', v_cnt;
  END IF;

  v_new := replace(v_src, v_a1_old, v_a1_new);
  EXECUTE v_new;

  v_src := pg_get_functiondef(v_oid);
  IF position('legs AS (' in v_src) = 0 OR position('win_end' in v_src) = 0 THEN
    RAISE EXCEPTION '0089 abort: patched closer does not carry the leg-close CTE';
  END IF;

  -- ---------- Patch 2: public.ottoq_sim_release_depot ----------
  SELECT p.oid INTO STRICT v_oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_release_depot';
  v_src := pg_get_functiondef(v_oid);

  IF md5(v_src) <> '429ecb4a901eb931997f1c1545bc898b' THEN
    RAISE EXCEPTION '0089 abort: sim_release_depot drifted from the pinned pre-image (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a2_old, ''))) / length(v_a2_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0089 abort: booking-release anchor found % times, expected 1', v_cnt;
  END IF;

  v_new := replace(v_src, v_a2_old, v_a2_new);
  EXECUTE v_new;

  v_src := pg_get_functiondef(v_oid);
  IF position('release_depot leg close' in v_src) = 0 THEN
    RAISE EXCEPTION '0089 abort: patched finalizer does not carry the leg close';
  END IF;

  RAISE NOTICE '0089 applied: full-window closes settle their legs; a finished run leaves no leg open.';
END
$do$;
