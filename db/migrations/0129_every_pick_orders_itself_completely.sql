-- migration-version: 20260831001500
-- migration-name:    every_pick_orders_itself_completely
-- 0129 -- tier A of the ordering census (db/checks/0050 round-2 verdict: world-purity is
-- proven; what remains is pick-order totality inside a run). The census enumerated 197
-- ordered picks across 112 engine functions; this migration totalizes the 24 sites in the
-- 24t-implicated write path -- the classes the round-2 forks (0046 pairs 56-58, 67-68)
-- exercised. Every tail follows the 0062/0063 discipline: content keys first, a uuid only
-- as the last resort for byte-identical candidates.
--
--   * THE ITINERARY PICK (3 fns): "the vehicle's active itinerary" chosen by created_at
--     DESC alone -- frozen inside a pair, so a SECOND active itinerary (a second visit)
--     makes the pick a heap coin that steers every downstream leg operation. New order:
--     sim_created_at DESC (sim-domain, differs between visits), created_at DESC,
--     itinerary_id DESC.
--   * THE LEG-SEQ FAMILY (decide_tick x7, bind_unbooked, enact_inspection_seam,
--     close_atom_leg, itin_leg_open): ORDER BY l.seq -- unique per itinerary, TIED across
--     two itineraries of the same vehicle. Tail: planned_start_sim, planned_end_sim,
--     leg_id.
--   * THE WASH-ADMISSION PICK (advance_service_flow x2): ORDER BY lower(b2.during) over
--     the vehicle's held wash/detail bookings -- the P44-era suspect, finally totalized:
--     + b2.stall_id, b2.booking_id DESC.
--   * VISIT CURSORS MISSING THE 0099 TIEBREAK (plan_visit_itinerary, honour_reservation
--     x2, service_priority_propose, cuopt_refresh, eval_sla_004): + vn.visit_key DESC.
--   * itin_leg_open's nearest-booking pick (equidistant tie), itin_travel_leg's
--     prior-leg pick, readmit_reopened_needs' LIMIT-4 admission (all-NULL flagged_at
--     collapses to one key): content tails as below.
--
-- Tier B (purity, not 24t-implicated) stays censused in 0046 for the next migration:
-- approvals/reassignment requested_at picks, reoptimize proposal pick, l2_external
-- proposal pick, wear-counters ORDER BY 1, rider_flag mark_served ORDER BY 1, cil_tick
-- score pick, link_bookings decision pick, score_run tick pick, DISTINCT ON tails.
--
-- Pre-image pins, read live 2026-08-31 (per-anchor counts asserted; NULL pin = later
-- patch to a function already patched above):
--   public.ottoq_decide_tick                    a75ed2fc03ab0f4f6f9995fdd6c63ccd  (7 sites, 3 anchors)
--   ottoq.ottoq_bind_unbooked_bay_occupants     c3ac1b08f724276ccd4f34fe7f89c761
--   ottoq.ottoq_enact_inspection_seam           3a90248e2f338efa76ff3bc096532aa3
--   public.ottoq_close_atom_leg                 8e2d37f31c213ec5e7404cc6b1628440
--   public.ottoq_itin_leg_open                  83cdf2d524b8e71b5624ebdb335fa651  (3 sites)
--   public.ottoq_itin_travel_leg                fa1c6ca19ecbf5584365d37291d7ea98  (2 sites)
--   public.ottoq_plan_visit_itinerary           38c6c18996e4826b135e1efcd66d1737  (2 sites)
--   public.ottoq_honour_reservation_proposal    65f716714786d2f6515a565b462e241f  (2 sites, one anchor)
--   public.ottoq_service_priority_propose       22d09626dc5485396d46d116daee46c5
--   public.ottoq_cuopt_refresh                  2248eba0213fa01e125f63ef4eb9627d
--   public.ottoq_eval_sla_004_required_services af472aa0de0f91761a4e715cb700d2e5
--   twin.ottoq_sim_advance_service_flow         6b0fbc53fce2f12e62341ff490c275d6  (2 sites, one anchor)
--   ottoq.ottoq_readmit_reopened_needs          67b7a2d16f1b884f3bd8a2b2958b9eb6

CREATE FUNCTION pg_temp.ottoq_0129_total(p_ns text, p_fn text, p_md5 text,
                                         p_old text, p_new text, p_expect int,
                                         p_prior int DEFAULT 0)
RETURNS void LANGUAGE plpgsql AS $helper$
DECLARE v_oid oid; v_src text; v_cnt int;
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = p_ns AND p.proname = p_fn;
  v_src := pg_get_functiondef(v_oid);
  IF p_md5 IS NOT NULL AND md5(v_src) <> p_md5 THEN
    RAISE EXCEPTION '0129 abort: %.% drifted (md5 %)', p_ns, p_fn, md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, p_old, ''))) / length(p_old);
  IF v_cnt <> p_expect THEN
    RAISE EXCEPTION '0129 abort: %.% anchor found % times, expected %', p_ns, p_fn, v_cnt, p_expect;
  END IF;
  EXECUTE replace(v_src, p_old, p_new);
  v_src := pg_get_functiondef(v_oid);
  v_cnt := (length(v_src) - length(replace(v_src, '/* 0129 */', ''))) / length('/* 0129 */');
  IF v_cnt <> p_prior + p_expect THEN
    RAISE EXCEPTION '0129 abort: %.% patch survived % of % sites', p_ns, p_fn, v_cnt - p_prior, p_expect;
  END IF;
  RAISE NOTICE '0129: %.% totalized (% site%)', p_ns, p_fn, p_expect, CASE WHEN p_expect > 1 THEN 's' ELSE '' END;
END
$helper$;

DO $apply$
BEGIN
  -- decide_tick: the (status,seq) pair first (longer anchor), then single-line seq, then
  -- the one multi-line seq site.
  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_decide_tick', 'a75ed2fc03ab0f4f6f9995fdd6c63ccd',
    'ORDER BY (l.status = ''active'') DESC, l.seq LIMIT 1;',
    'ORDER BY (l.status = ''active'') DESC, l.seq, l.planned_start_sim, l.planned_end_sim, l.leg_id /* 0129 */ LIMIT 1;', 2);
  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_decide_tick', NULL,
    'ORDER BY l.seq LIMIT 1;',
    'ORDER BY l.seq, l.planned_start_sim, l.planned_end_sim, l.leg_id /* 0129 */ LIMIT 1;', 4, 2);
  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_decide_tick', NULL,
    E'ORDER BY l.seq\n         LIMIT 1;',
    'ORDER BY l.seq, l.planned_start_sim, l.planned_end_sim, l.leg_id /* 0129 */ LIMIT 1;', 1, 6);

  PERFORM pg_temp.ottoq_0129_total('ottoq', 'ottoq_bind_unbooked_bay_occupants', 'c3ac1b08f724276ccd4f34fe7f89c761',
    E'ORDER BY (l.status = ''active'') DESC, l.seq\n     LIMIT 1;',
    'ORDER BY (l.status = ''active'') DESC, l.seq, l.planned_start_sim, l.planned_end_sim, l.leg_id /* 0129 */ LIMIT 1;', 1);

  PERFORM pg_temp.ottoq_0129_total('ottoq', 'ottoq_enact_inspection_seam', '3a90248e2f338efa76ff3bc096532aa3',
    'ORDER BY il.seq LIMIT 1)',
    'ORDER BY il.seq, il.planned_start_sim, il.planned_end_sim, il.leg_id /* 0129 */ LIMIT 1)', 1);

  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_close_atom_leg', '8e2d37f31c213ec5e7404cc6b1628440',
    'ORDER BY seq LIMIT 1;',
    'ORDER BY seq, planned_start_sim, planned_end_sim, leg_id /* 0129 */ LIMIT 1;', 1);

  -- itin_leg_open: the itinerary pick, the leg pick, the nearest-booking pick.
  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_itin_leg_open', '83cdf2d524b8e71b5624ebdb335fa651',
    'ORDER BY created_at DESC LIMIT 1;',
    'ORDER BY sim_created_at DESC, created_at DESC, itinerary_id DESC /* 0129 */ LIMIT 1;', 1);
  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_itin_leg_open', NULL,
    'ORDER BY seq LIMIT 1;',
    'ORDER BY seq, planned_start_sim, planned_end_sim, leg_id /* 0129 */ LIMIT 1;', 1, 1);
  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_itin_leg_open', NULL,
    E'ORDER BY abs(EXTRACT(EPOCH FROM (lower(bb.during) - p_now)))\n                LIMIT 1)',
    'ORDER BY abs(EXTRACT(EPOCH FROM (lower(bb.during) - p_now))), lower(bb.during), bb.stall_id, bb.booking_id DESC /* 0129 */ LIMIT 1)', 1, 2);

  -- itin_travel_leg: the prior-leg pick, the itinerary pick.
  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_itin_travel_leg', 'fa1c6ca19ecbf5584365d37291d7ea98',
    E'ORDER BY l.planned_start_sim DESC, l.seq DESC\n     LIMIT 1;',
    'ORDER BY l.planned_start_sim DESC, l.seq DESC, l.planned_end_sim DESC, l.leg_id DESC /* 0129 */ LIMIT 1;', 1);
  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_itin_travel_leg', NULL,
    'ORDER BY created_at DESC LIMIT 1;',
    'ORDER BY sim_created_at DESC, created_at DESC, itinerary_id DESC /* 0129 */ LIMIT 1;', 1, 1);

  -- plan_visit_itinerary: the visit cursor gains the 0099 tiebreak; the itinerary pick.
  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_plan_visit_itinerary', '38c6c18996e4826b135e1efcd66d1737',
    'ORDER BY vn.created_at DESC LIMIT 1;',
    'ORDER BY vn.created_at DESC, vn.visit_key DESC /* 0129 */ LIMIT 1;', 1);
  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_plan_visit_itinerary', NULL,
    'ORDER BY created_at DESC LIMIT 1;',
    'ORDER BY sim_created_at DESC, created_at DESC, itinerary_id DESC /* 0129 */ LIMIT 1;', 1, 1);

  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_honour_reservation_proposal', '65f716714786d2f6515a565b462e241f',
    'ORDER BY vn.created_at DESC LIMIT 1;',
    'ORDER BY vn.created_at DESC, vn.visit_key DESC /* 0129 */ LIMIT 1;', 2);

  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_service_priority_propose', '22d09626dc5485396d46d116daee46c5',
    'ORDER BY vn2.created_at DESC LIMIT 1)',
    'ORDER BY vn2.created_at DESC, vn2.visit_key DESC /* 0129 */ LIMIT 1)', 1);

  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_cuopt_refresh', '2248eba0213fa01e125f63ef4eb9627d',
    'ORDER BY vn.created_at DESC LIMIT 1)',
    'ORDER BY vn.created_at DESC, vn.visit_key DESC /* 0129 */ LIMIT 1)', 1);

  PERFORM pg_temp.ottoq_0129_total('public', 'ottoq_eval_sla_004_required_services', 'af472aa0de0f91761a4e715cb700d2e5',
    'ORDER BY vn.created_at DESC NULLS LAST LIMIT 1;',
    'ORDER BY vn.created_at DESC NULLS LAST, vn.visit_key DESC /* 0129 */ LIMIT 1;', 1);

  PERFORM pg_temp.ottoq_0129_total('twin', 'ottoq_sim_advance_service_flow', '6b0fbc53fce2f12e62341ff490c275d6',
    'ORDER BY lower(b2.during) LIMIT 1)',
    'ORDER BY lower(b2.during), b2.stall_id, b2.booking_id DESC /* 0129 */ LIMIT 1)', 2);

  PERFORM pg_temp.ottoq_0129_total('ottoq', 'ottoq_readmit_reopened_needs', '67b7a2d16f1b884f3bd8a2b2958b9eb6',
    E'ORDER BY COALESCE((vh.config->''exception''->>''flagged_at'')::timestamptz, p_clock)\n     LIMIT 4',
    'ORDER BY COALESCE((vh.config->''exception''->>''flagged_at'')::timestamptz, p_clock), vh.id /* 0129 */ LIMIT 4', 1);

  RAISE NOTICE '0129 applied: 24 picks in 13 functions order themselves completely.';
END
$apply$;

DROP FUNCTION pg_temp.ottoq_0129_total(text, text, text, text, text, int, int);
