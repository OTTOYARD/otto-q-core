-- migration-version: 20260830230000
-- migration-name:    the_visit_ledger_belongs_to_the_run
-- 0124 -- the completion of 0123, forced by its own verification pair (db/checks/0046
-- pair 40): with all nine tiebroken latest-need cursors run-scoped, the 424242/24t pair
-- STILL forked streams -- same two variants as P39, arms swapped, fps equal at 8de3415f.
-- The archaeology (this time with a one-command diff instead of a wash/detail tangle)
-- ran the fork to the same first divergent write -- vehicle 9f5d69bb's 12:45:24 bay
-- booking, purpose detail in one arm, wash in the other -- and the reads behind that
-- choice exposed what the 0123 census had missed: its regexp keyed on the 0099-tiebroken
-- cursor form (created_at DESC, visit_key DESC), so every OLDER read of the visit ledger
-- was invisible to it. A full census of ottoq_visit_needs (51 functions, ~95 sites) found
-- the class is three shapes, not one:
--
--   1. BARE latest-need cursors -- ORDER BY created_at DESC LIMIT 1, no tiebreak, no run
--      scope: mark_visit_atoms_done (the atom-credit writer! its UPDATE lands on whatever
--      row the heap hands it), plan_visit_itinerary, reopen_visit_atoms, l2_propose_
--      stall_assignment, start_concurrent_atoms, service_priority_propose, cuopt_refresh,
--      eval_sla_004, generate_service_manifest's carried_over resolver (left -- see below).
--   2. MEMBERSHIP GATES -- EXISTS/COUNT/JOIN over open('in_progress') visits, keyed by
--      vehicle or depot, no run scope: ottoq_visit_wants_detail (the very CASE that picks
--      wash-vs-detail purpose at the divergence site), five gates in decide_tick, the l2
--      proposers' need-checks, ingest_service_complete's before/after counts, the depot
--      loops in sim_advance_visit_atoms / sim_advance_flow_contract / prearrival_contracts.
--   3. UNSCOPED WRITES -- sim_advance_visit_atoms' end-of-loop status rewrite (parks
--      carryover / completes visits) hits EVERY open row on the depot, any run's.
--
-- Inside a determinism pair the arms share one frozen transaction: arm B's world carries
-- arm A's leftover rows, arm A's carries the pre-pair lineage's, and every shape-1/2/3
-- read can resolve differently between them the moment a leftover is visible. Run-scoping
-- all of it is the same 0020/0123 semantics: a run reads its own visit ledger; production
-- (sim_run_id NULL) reads production rows.
--
-- Two idioms below:
--   * functions WITH p_sim_run_id: append the strict zero-uuid filter (0123's f_vn).
--   * functions WITHOUT a run parameter (helpers keyed by vehicle/depot): resolve the
--     depot's running run in place -- 0123's decide_wash_triage idiom -- via the row's
--     own depot_id (or the local depot variable) so no signature changes and no caller
--     ripple. In production no sim run is 'running', the resolve yields NULL, and the
--     COALESCE matches production rows; during any cert arm exactly that arm's run is
--     'running'.
--
-- DELIBERATELY LEFT UNSCOPED (each is cross-run by design or inert):
--   * the janitors: release_visit_artifacts, benchmark_reset, sweep_orphaned_visit_
--     artifacts, generate_service_manifest's per-vehicle supersede -- their job is to
--     retire other runs' leftovers;
--   * generate_service_manifest's carried_over resolver -- cross-session carryover is a
--     production feature; the teardown path supersedes carried_over rows per vehicle, so
--     no carryover survives a cert pair (P39's ledger confirmed none existed);
--   * reporting reads (agent_board, booking_why, depot_cards, twin_snapshot, ...);
--   * decide_tick's departure gate that already carries the `= p_sim_run_id OR IS NULL`
--     idiom, and rider_flag_indepot_sweep (already scoped; its plain `= p_sim_run_id`
--     matches nothing in production -- noted in 0049, not this migration's charter).
--
-- Prediction (falsifiable, the 0121 discipline): the next 424242/24t transition+confirm
-- sequence must land both arms on ONE stream set. If streams still fork, the carrier is
-- outside the visit ledger and the pair diff will say where.
--
-- Pre-image pins, read live 2026-08-30 post-0123:
--   public.ottoq_decide_tick                    0eaa482907f297054172a1acd98e479e  (5 sites)
--   twin.ottoq_sim_advance_service_flow         02a4d9bce49a409a73a8fd35017bb244  (1 site)
--   twin.ottoq_sim_advance_visit_atoms          818e5c22960b97ee44524d542e83aab9  (3 sites)
--   twin.ottoq_sim_advance_flow_contract        f056a974faa0e980bdbf1fdd94b58ffb  (1 site)
--   twin.ottoq_demand_rebook_after_eviction     fc1c2e722f5ea2dd370c534481d7244a  (1 site)
--   ottoq.ottoq_emit_booking_interrupted        ef5a56706a05f9af264343daaa86c585  (1 site)
--   ottoq.ottoq_plan_opportunistic_charges      bb17ea0ff73c2cbd54ed64e3daaef117  (1 site)
--   ottoq.ottoq_sim_prearrival_contracts        062e94327d78d550c5c46a4b90e289ae  (2 sites)
--   public.ottoq_cuopt_refresh                  5d6448d94f36ecd933de4b4b9d0c4258  (1 site)
--   public.ottoq_plan_visit_itinerary           0f22884229e7b2a6ee1d838e0874a3d5  (1 site)
--   public.ottoq_service_priority_propose       bc412ec7077ace723d1733ab743febf5  (2 sites)
--   public.ottoq_l2_propose_stall_assignment    0c35af2e4223f79a696dacffb5dc8aad  (1 site)
--   public.ottoq_l2_propose_charge_disposition  1e7e16cd53aa5e585c5e006b87de4304  (2 sites, one anchor)
--   public.ottoq_l2_propose_service             5338e40160095d8bd0469be580ad8ce3  (1 site)
--   public.ottoq_ingest_service_complete        0436d768509840dfe544cc58eb1538b8  (2 sites, one anchor)
--   public.ottoq_eval_sla_004_required_services 5f5073c63c54349376197651c4fb6470  (1 site)
--   public.ottoq_reopen_visit_atoms             b4d64e2c71a1452e5a93f0ee255ea866  (2 sites)
--   public.ottoq_start_concurrent_atoms         d28e69d41b2faedad83a56925df043ee  (2 sites)
--   public.ottoq_mark_visit_atoms_done          6d9b236633f66ee4494cbe241e84b1f6  (1 site)
--   public.ottoq_visit_wants_detail             82ac1b1e77252ef4ac26b8c4206fa2f2  (1 site)

-- Same helper contract as 0123: pin asserted (NULL = later patch to a function already
-- patched above), anchor count asserted, patched source re-verified by 0124 marker count
-- (p_prior = markers already planted by earlier calls to the same function).
CREATE FUNCTION pg_temp.ottoq_0124_scope(p_ns text, p_fn text, p_md5 text,
                                         p_anchor text, p_filter text, p_expect int,
                                         p_prior int DEFAULT 0)
RETURNS void LANGUAGE plpgsql AS $helper$
DECLARE v_oid oid; v_src text; v_cnt int;
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = p_ns AND p.proname = p_fn;
  v_src := pg_get_functiondef(v_oid);
  IF p_md5 IS NOT NULL AND md5(v_src) <> p_md5 THEN
    RAISE EXCEPTION '0124 abort: %.% drifted (md5 %)', p_ns, p_fn, md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, p_anchor, ''))) / length(p_anchor);
  IF v_cnt <> p_expect THEN
    RAISE EXCEPTION '0124 abort: %.% anchor found % times, expected %', p_ns, p_fn, v_cnt, p_expect;
  END IF;
  EXECUTE replace(v_src, p_anchor, p_anchor || p_filter);
  v_src := pg_get_functiondef(v_oid);
  v_cnt := (length(v_src) - length(replace(v_src, '/* 0124 */', ''))) / length('/* 0124 */');
  IF v_cnt <> p_prior + p_expect THEN
    RAISE EXCEPTION '0124 abort: %.% patch survived % of % sites', p_ns, p_fn, v_cnt - p_prior, p_expect;
  END IF;
  RAISE NOTICE '0124: %.% run-scoped (% site%)', p_ns, p_fn, p_expect, CASE WHEN p_expect > 1 THEN 's' ELSE '' END;
END
$helper$;

DO $apply$
DECLARE
  z CONSTANT text := '''00000000-0000-0000-0000-000000000000''::uuid';
  -- strict filters for functions that carry p_sim_run_id
  fr_vn text; fr_vn2 text; fr_vn3 text; fr_n text;
  -- resolve-the-running-run filters for paramless helpers
  rr CONSTANT text := '(SELECT r0.sim_run_id FROM public.ottoq_sim_runs r0 WHERE r0.status = ''running'' AND r0.depot_id = %DEPOT% ORDER BY r0.started_at DESC LIMIT 1)';
  rd_vn_row text; rd_n_pdepot text; rd_vn_pdepot text; rd_vn2_vdepot text;
  rd_tbl_vdepot text; rd_tbl_row text;
BEGIN
  fr_vn  := ' AND COALESCE(vn.sim_run_id, '  || z || ') = COALESCE(p_sim_run_id, ' || z || ') /* 0124 */';
  fr_vn2 := ' AND COALESCE(vn2.sim_run_id, ' || z || ') = COALESCE(p_sim_run_id, ' || z || ') /* 0124 */';
  fr_vn3 := ' AND COALESCE(vn3.sim_run_id, ' || z || ') = COALESCE(p_sim_run_id, ' || z || ') /* 0124 */';
  fr_n   := ' AND COALESCE(n.sim_run_id, '   || z || ') = COALESCE(p_sim_run_id, ' || z || ') /* 0124 */';

  rd_vn_row     := ' AND COALESCE(vn.sim_run_id, ' || z || ') = COALESCE(' || replace(rr, '%DEPOT%', 'vn.depot_id')  || ', ' || z || ') /* 0124 */';
  rd_n_pdepot   := ' AND COALESCE(n.sim_run_id, '  || z || ') = COALESCE(' || replace(rr, '%DEPOT%', 'p_depot_id')   || ', ' || z || ') /* 0124 */';
  rd_vn_pdepot  := ' AND COALESCE(vn.sim_run_id, ' || z || ') = COALESCE(' || replace(rr, '%DEPOT%', 'p_depot_id')   || ', ' || z || ') /* 0124 */';
  rd_vn2_vdepot := ' AND COALESCE(vn2.sim_run_id, '|| z || ') = COALESCE(' || replace(rr, '%DEPOT%', 'v_depot')      || ', ' || z || ') /* 0124 */';
  rd_tbl_vdepot := ' AND COALESCE(ottoq_visit_needs.sim_run_id, ' || z || ') = COALESCE(' || replace(rr, '%DEPOT%', 'v_depot') || ', ' || z || ') /* 0124 */';
  rd_tbl_row    := ' AND COALESCE(ottoq_visit_needs.sim_run_id, ' || z || ') = COALESCE(' || replace(rr, '%DEPOT%', 'ottoq_visit_needs.depot_id') || ', ' || z || ') /* 0124 */';

  -- ── decide_tick: the five membership gates (departure holds x3, arrival admission, wash skip)
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_decide_tick', '0eaa482907f297054172a1acd98e479e',
    E'WHERE vn2.vehicle_id = v.id\n             AND vn2.status IN (''open'',''in_progress'')', fr_vn2, 1);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_decide_tick', NULL,
    'WHERE vn3.vehicle_id = v.id AND vn3.status IN (''open'',''in_progress'')', fr_vn3, 1, 1);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_decide_tick', NULL,
    E'SELECT 1 FROM ottoq_visit_needs vn\n                    WHERE vn.vehicle_id = v.id AND vn.status IN (''open'',''in_progress'')', fr_vn, 1, 2);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_decide_tick', NULL,
    'WHERE vn2.vehicle_id = v_req.vehicle_id AND vn2.status IN (''open'',''in_progress'')', fr_vn2, 1, 3);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_decide_tick', NULL,
    'WHERE n.vehicle_id = v.id AND n.status IN (''open'',''in_progress'')', fr_n, 1, 4);

  -- ── the twin's flow engine
  PERFORM pg_temp.ottoq_0124_scope('twin', 'ottoq_sim_advance_service_flow', '02a4d9bce49a409a73a8fd35017bb244',
    'WHERE n.vehicle_id = v.id AND n.status IN (''open'',''in_progress'')', fr_n, 1);
  PERFORM pg_temp.ottoq_0124_scope('twin', 'ottoq_sim_advance_visit_atoms', '818e5c22960b97ee44524d542e83aab9',
    'WHERE vn.depot_id = v_depot AND vn.status IN (''open'',''in_progress'')', fr_vn, 2);
  PERFORM pg_temp.ottoq_0124_scope('twin', 'ottoq_sim_advance_visit_atoms', NULL,
    E'WHERE v.id = vn.vehicle_id AND vn.depot_id = v_depot\n    AND vn.status IN (''open'',''in_progress'')', fr_vn, 1, 2);
  PERFORM pg_temp.ottoq_0124_scope('twin', 'ottoq_sim_advance_flow_contract', 'f056a974faa0e980bdbf1fdd94b58ffb',
    'WHERE vn.depot_id = v_depot AND vn.status IN (''open'',''in_progress'')', fr_vn, 1);
  PERFORM pg_temp.ottoq_0124_scope('twin', 'ottoq_demand_rebook_after_eviction', 'fc1c2e722f5ea2dd370c534481d7244a',
    E'WHERE n.vehicle_id = p_vehicle_id\n     AND n.status = ''open''\n     AND n.meta ? ''reopen''', fr_n, 1);

  -- ── ottoq-side planners
  PERFORM pg_temp.ottoq_0124_scope('ottoq', 'ottoq_emit_booking_interrupted', 'ef5a56706a05f9af264343daaa86c585',
    E'WHERE vn.vehicle_id = p_vehicle_id\n       AND vn.status = ''open''\n       AND vn.meta ? ''reopen''', fr_vn, 1);
  PERFORM pg_temp.ottoq_0124_scope('ottoq', 'ottoq_plan_opportunistic_charges', 'bb17ea0ff73c2cbd54ed64e3daaef117',
    'WHERE vn.depot_id = p_depot_id AND vn.status IN (''open'',''in_progress'')', fr_vn, 1);
  PERFORM pg_temp.ottoq_0124_scope('ottoq', 'ottoq_sim_prearrival_contracts', '062e94327d78d550c5c46a4b90e289ae',
    'WHERE vn.vehicle_id = v.id AND vn.status IN (''open'',''in_progress'')', fr_vn, 1);
  PERFORM pg_temp.ottoq_0124_scope('ottoq', 'ottoq_sim_prearrival_contracts', NULL,
    'ON vn.vehicle_id = v.id AND vn.status IN (''open'',''in_progress'')', fr_vn, 1, 1);

  -- ── run-aware public planners/proposers
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_cuopt_refresh', '5d6448d94f36ecd933de4b4b9d0c4258',
    E'WHERE vn.vehicle_id = v.id\n                                             AND vn.status IN (''open'',''in_progress'')', fr_vn, 1);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_plan_visit_itinerary', '0f22884229e7b2a6ee1d838e0874a3d5',
    'WHERE vn.vehicle_id = p_vehicle AND vn.status IN (''open'',''in_progress'')', fr_vn, 1);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_service_priority_propose', 'bc412ec7077ace723d1733ab743febf5',
    'WHERE vn.vehicle_id = v.id AND vn.status IN (''open'',''in_progress'')', fr_vn, 1);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_service_priority_propose', NULL,
    'WHERE vn2.vehicle_id = v.id AND vn2.status IN (''open'',''in_progress'')', fr_vn2, 1, 1);

  -- ── paramless helpers: resolve the depot's running run in place
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_l2_propose_stall_assignment', '0c35af2e4223f79a696dacffb5dc8aad',
    'WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN (''open'',''in_progress'')', rd_vn_pdepot, 1);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_l2_propose_charge_disposition', '1e7e16cd53aa5e585c5e006b87de4304',
    'WHERE n.vehicle_id = p_vehicle_id AND n.status IN (''open'',''in_progress'')', rd_n_pdepot, 2);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_l2_propose_service', '5338e40160095d8bd0469be580ad8ce3',
    'WHERE n.vehicle_id = p_vehicle_id AND n.status IN (''open'',''in_progress'')', rd_n_pdepot, 1);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_ingest_service_complete', '0436d768509840dfe544cc58eb1538b8',
    'WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN (''open'',''in_progress'')', rd_vn_row, 2);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_eval_sla_004_required_services', '5f5073c63c54349376197651c4fb6470',
    'WHERE vn.vehicle_id = v_vehicle_id AND vn.status IN (''open'',''in_progress'')', rd_vn_row, 1);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_reopen_visit_atoms', 'b4d64e2c71a1452e5a93f0ee255ea866',
    'WHERE vn.vehicle_id = p_vehicle AND vn.status IN (''open'',''in_progress'')', rd_vn_row, 1);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_reopen_visit_atoms', NULL,
    E'WHERE vn.vehicle_id = p_vehicle\n           AND vn.created_at >= now() - interval ''24 hours''', rd_vn_row, 1, 1);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_start_concurrent_atoms', 'd28e69d41b2faedad83a56925df043ee',
    'WHERE vehicle_id = p_vehicle AND status IN (''open'',''in_progress'')', rd_tbl_vdepot, 1);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_start_concurrent_atoms', NULL,
    'WHERE vn2.depot_id = v_depot AND vn2.status = ''in_progress''', rd_vn2_vdepot, 1, 1);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_mark_visit_atoms_done', '6d9b236633f66ee4494cbe241e84b1f6',
    'WHERE vehicle_id = p_vehicle AND status IN (''open'',''in_progress'')', rd_tbl_row, 1);
  PERFORM pg_temp.ottoq_0124_scope('public', 'ottoq_visit_wants_detail', '82ac1b1e77252ef4ac26b8c4206fa2f2',
    'WHERE vn.vehicle_id = p_vehicle AND vn.status IN (''open'',''in_progress'')', rd_vn_row, 1);

  RAISE NOTICE '0124 applied: 32 sites in 20 functions -- the visit ledger belongs to its run.';
END
$apply$;

-- 0121b discipline: post-conditions that EXECUTE the patched code. The paramless helpers
-- run end-to-end on a vehicle id that cannot exist -- every patched statement in them
-- plans and executes against empty sets (reopen's dummy call exercises its widened
-- fallback, ingest exercises both counts plus the mark call). The run-parameterized
-- sites are executed end-to-end by the 0046 transition pair that follows this apply.
DO $smoke$
DECLARE v_dummy uuid := 'ffffffff-ffff-4fff-8fff-ffffffffffff';
BEGIN
  -- PERFORM discards returns regardless of type (eval_sla_004 returns a composite).
  PERFORM public.ottoq_visit_wants_detail(v_dummy);
  PERFORM public.ottoq_mark_visit_atoms_done(v_dummy, ARRAY['exterior_wash'], now());
  PERFORM public.ottoq_start_concurrent_atoms(v_dummy, now());
  PERFORM public.ottoq_reopen_visit_atoms(v_dummy, ARRAY['exterior_wash'], now() - interval '1 hour', '0124_smoke');
  PERFORM public.ottoq_ingest_service_complete(v_dummy, '0124_smoke', '0124_smoke', ARRAY['exterior_wash']);
  PERFORM public.ottoq_eval_sla_004_required_services('vehicle', v_dummy, '{}'::jsonb, '{}'::jsonb);
  RAISE NOTICE '0124 smoke: six paramless helpers execute clean on an empty world.';
END
$smoke$;

DROP FUNCTION pg_temp.ottoq_0124_scope(text, text, text, text, text, int, int);
