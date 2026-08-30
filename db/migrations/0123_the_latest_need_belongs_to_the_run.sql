-- migration-version: 20260830220000
-- migration-name:    the_latest_need_belongs_to_the_run
-- 0123 -- the CORE-CERT gate's first real catch (db/checks/0046 pairs 38-39): at the
-- 24-tick horizon on seed 424242, fingerprints matched and the STREAMS forked -- arm B
-- reproduced the canon, arm A booked one vehicle's wash and detail atoms in the opposite
-- order, and the row-level trail ran to ground at the oldest open front in the file:
--
--   THE LATEST-NEED CURSOR:  ORDER BY created_at DESC, visit_key DESC LIMIT 1
--
-- 0099 gave these cursors the visit_key tiebreak but never run-scoped them. Inside a
-- determinism pair (one transaction) created_at is FROZEN -- every row both arms write
-- carries the same now() -- and visit_key embeds (vehicle, absolute sim clock), so arm B's
-- reopened visit collides EXACTLY with arm A's copy of the same visit: created_at ties,
-- visit_key ties, and LIMIT 1 picks by heap. The winner's atom states (which services
-- remain, which resume) then steer the bay sequencing -- the wash/detail flip, one tick of
-- staging drift, and a forked horizon. It needs a vehicle on its SECOND visit, which is
-- why 12-tick pairs never saw it and the 24-tick gate did.
--
-- Census (regexp over pg_proc, verified per site): 13 latest-need cursors in 11 functions;
-- 4 already run-scoped (book_appointment, readmit_reopened_needs, record_enacted_booking
-- site 1, reserve_inbound_bays); NINE were not. This migration scopes all nine with the
-- 0020 zero-uuid convention. Single-run behavior shift: a cursor can no longer read a DEAD
-- run's leftover 'open' visit before the current run's first generation supersedes it --
-- run-pure by construction; canon movement handled by the 0046 transition-pair rule.
--
-- Anchor note (first apply aborted here, correctly): decide_tick's bare WHERE clause
-- occurs THREE times, not two -- the third is the arrival-admission EXISTS gate, a
-- membership test with no ORDER BY/LIMIT and so no heap coin. It is a DIFFERENT class
-- (decide_tick holds six visit_needs EXISTS gates, one already run-aware via the
-- `= p_sim_run_id OR IS NULL` idiom); that class gets its own census, not a ride-along
-- here. The two cursor sites are anchored by their distinct SELECT heads, expect 1 each.
--
-- Pre-image pins, read live 2026-08-30 (per-site anchor counts asserted below):
--   public.ottoq_decide_tick                  d4ca3827778088958f9b7259a32dcab0  (post-0122; 2 cursor sites, per-site anchors)
--   ottoq.ottoq_plan_opportunistic_charges    82f651544ecc6939633de45801d53a34
--   ottoq.ottoq_arrival_disposition           d0ec3406704a5feffb2b2ee54f37d193
--   ottoq.ottoq_decide_wash_triage            4696e256ea97aa32a7a5c13a0be29033  (no run param; resolves the depot's running run)
--   ottoq.ottoq_readmit_resumed_visits        6192b33dc9b85708436be8af207839a5
--   ottoq.ottoq_record_enacted_booking        fc6fc4e4a568322fb868ecba54fc1395  (site 2 only; site 1 already scoped)
--   ottoq.ottoq_reoptimize_reservation_book   1654d04df9075a454f93d306863447f1
--   twin.ottoq_sim_advance_service_flow       95fcddb900a7c3bf3d98160f7d12d13d

-- p_md5 NULL = second patch to a function already patched above (pin can't match its own
-- prior patch; the anchor-count assert still bites). p_prior = 0123 markers already
-- planted in that function by earlier calls, so the post-verify stays exact.
CREATE FUNCTION pg_temp.ottoq_0123_scope(p_ns text, p_fn text, p_md5 text,
                                         p_anchor text, p_filter text, p_expect int,
                                         p_prior int DEFAULT 0)
RETURNS void LANGUAGE plpgsql AS $helper$
DECLARE v_oid oid; v_src text; v_cnt int;
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = p_ns AND p.proname = p_fn;
  v_src := pg_get_functiondef(v_oid);
  IF p_md5 IS NOT NULL AND md5(v_src) <> p_md5 THEN
    RAISE EXCEPTION '0123 abort: %.% drifted (md5 %)', p_ns, p_fn, md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, p_anchor, ''))) / length(p_anchor);
  IF v_cnt <> p_expect THEN
    RAISE EXCEPTION '0123 abort: %.% anchor found % times, expected %', p_ns, p_fn, v_cnt, p_expect;
  END IF;
  EXECUTE replace(v_src, p_anchor, p_anchor || p_filter);
  v_src := pg_get_functiondef(v_oid);
  v_cnt := (length(v_src) - length(replace(v_src, '/* 0123 */', ''))) / length('/* 0123 */');
  IF v_cnt <> p_prior + p_expect THEN
    RAISE EXCEPTION '0123 abort: %.% patch survived % of % sites', p_ns, p_fn, v_cnt - p_prior, p_expect;
  END IF;
  RAISE NOTICE '0123: %.% run-scoped (% site%)', p_ns, p_fn, p_expect, CASE WHEN p_expect > 1 THEN 's' ELSE '' END;
END
$helper$;

DO $apply$
DECLARE
  z  CONSTANT text := '''00000000-0000-0000-0000-000000000000''::uuid';
  f_vn  text; f_n  text; f_n2 text; f_wash text;
BEGIN
  f_vn := ' AND COALESCE(vn.sim_run_id, ' || z || ') = COALESCE(p_sim_run_id, ' || z || ') /* 0123 */';
  f_n  := ' AND COALESCE(n.sim_run_id, '  || z || ') = COALESCE(p_sim_run_id, ' || z || ') /* 0123 */';
  f_n2 := ' AND COALESCE(n2.sim_run_id, ' || z || ') = COALESCE(p_sim_run_id, ' || z || ') /* 0123 */';
  -- decide_wash_triage has no run parameter: scope to the depot's running run (inside a
  -- pair transaction only the current arm's run is 'running'; in live contexts likewise).
  f_wash := ' AND COALESCE(vn.sim_run_id, ' || z || ') = COALESCE((SELECT r.sim_run_id FROM public.ottoq_sim_runs r WHERE r.status = ''running'' AND r.depot_id = p_depot_id ORDER BY r.started_at DESC LIMIT 1), ' || z || ') /* 0123 */';

  -- decide_tick's two CURSOR sites, anchored by their SELECT heads (the bare WHERE clause
  -- also matches the arrival-admission EXISTS gate -- see header; that one stays put).
  PERFORM pg_temp.ottoq_0123_scope('public', 'ottoq_decide_tick', 'd4ca3827778088958f9b7259a32dcab0',
    E'(SELECT vn.target_soc FROM ottoq_visit_needs vn\n              WHERE vn.vehicle_id = v.id AND vn.status IN (''open'',''in_progress'')', f_vn, 1);

  PERFORM pg_temp.ottoq_0123_scope('public', 'ottoq_decide_tick', NULL,
    E'(SELECT vn.urgency = ''immediate_dispatch'' FROM ottoq_visit_needs vn\n                 WHERE vn.vehicle_id = v.id AND vn.status IN (''open'',''in_progress'')', f_vn, 1, 1);

  PERFORM pg_temp.ottoq_0123_scope('ottoq', 'ottoq_plan_opportunistic_charges', '82f651544ecc6939633de45801d53a34',
    'WHERE vn.vehicle_id = v.id AND vn.status IN (''open'',''in_progress'')', f_vn, 1);

  PERFORM pg_temp.ottoq_0123_scope('ottoq', 'ottoq_arrival_disposition', 'd0ec3406704a5feffb2b2ee54f37d193',
    'WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN (''open'',''in_progress'')', f_vn, 1);

  PERFORM pg_temp.ottoq_0123_scope('ottoq', 'ottoq_decide_wash_triage', '4696e256ea97aa32a7a5c13a0be29033',
    'WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN (''open'',''in_progress'')', f_wash, 1);

  PERFORM pg_temp.ottoq_0123_scope('ottoq', 'ottoq_readmit_resumed_visits', '6192b33dc9b85708436be8af207839a5',
    E'WHERE n.vehicle_id = vh.id\n           AND n.status = ''open''', f_n, 1);

  PERFORM pg_temp.ottoq_0123_scope('ottoq', 'ottoq_record_enacted_booking', 'fc6fc4e4a568322fb868ecba54fc1395',
    E'WHERE vn.vehicle_id = p_vehicle_id\n                               AND vn.status IN (''open'',''in_progress'')', f_vn, 1);

  PERFORM pg_temp.ottoq_0123_scope('ottoq', 'ottoq_reoptimize_reservation_book', '1654d04df9075a454f93d306863447f1',
    'WHERE vn.vehicle_id = v_rec.vehicle_id AND vn.status IN (''open'',''in_progress'')', f_vn, 1);

  PERFORM pg_temp.ottoq_0123_scope('twin', 'ottoq_sim_advance_service_flow', '95fcddb900a7c3bf3d98160f7d12d13d',
    E'WHERE n2.vehicle_id = v_rec.id\n                            AND n2.status IN (''open'',''in_progress'')', f_n2, 1);

  RAISE NOTICE '0123 applied: all nine latest-need cursors belong to their run.';
END
$apply$;

DROP FUNCTION pg_temp.ottoq_0123_scope(text, text, text, text, text, int, int);
