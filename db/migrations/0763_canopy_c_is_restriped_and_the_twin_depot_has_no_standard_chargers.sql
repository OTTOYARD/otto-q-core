-- migration-version: PENDING
-- migration-name:    canopy_c_is_restriped_and_the_twin_depot_has_no_standard_chargers
--
-- 0763  **Canopy C is re-striped as canopies A and B: the twin depot is built with thirty robotic fast chargers and no
--       standard charger, and its power limits are what its hardware can draw, so the cars take what they need and the
--       depot's ceiling is set later from what they drew.** (G481)
--
-- ══ §0 CHASE'S CALL, AND HOW IT IS APPLIED ════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-10-21 at 6:52 AM CT: "Still don't see the additional DCFC robotic, charging and overhead Robo, vacuum for
--   the rest of the stalls. I see it on the original 10, but we discussed swapping out all of the L2's or 90% of the L2's
--   for DCFC ever bought charging arm with overhead robovac ." On 2026-10-17 he had written: "If you think it's favorable,
--   convert all L2 charging into robotic DC FC charging ... Only worry would be ... maximum energy capacity ... massive
--   megawatt usage." 0759 re-stripes canopy B and this file canopy C, so with both applied the twin depot has thirty
--   robotic fast chargers, each with its OTTO-CHARGE ARM and its OTTO-CLEAN ARM (0758), and no standard charger.
--
--   It changes the depot every demo reads, so it is applied as 0759 is: after 0759, between runs, with no research sweep
--   or dial experiment active at the twin depot (P0), through the connector, which asks (this UPDATEs stalls, chargers,
--   the depot and the build-outs, and DROPs its own temporary function), and once the renderer draws the 30-post depot
--   (ottoyarddepot-sim #152, build dcfc30, merged and published 2026-10-21).
--
-- ══ §1 THIRTY POSTS, AND THE POWER THEY NEED ══════════════════════════════════════════════════════════════════════════
--
--   Thirty is the most this site holds at this arm design: ten posts a canopy on the 14-unit pitch, three canopies (0759
--   §1). The research wing recommended twenty now and the next twenty as measured demand fills them (db/checks/0451 §10
--   point 2: posts 11-20 met 6.8-7.7 car-hours each in a 12-hour day, posts 21-40 1.6-3.2, two seeds). Chase chose all
--   thirty: rule 10 makes the research a recommendation and the build his call, and this file builds his call. Past twenty
--   posts the wash line was the wall (0451 §13); the depot's wash lanes have been robotic since 2026-10-20 (G460).
--
--   THE POWER: NO CEILING ON THE FRONT END (CLAUDE.md rule 13). Chase, 2026-10-21, on reading the held-site design this
--   file first carried: "never base variable allocation of resources or throughput or up time or energy consumption
--   based on a hard ceiling until we have everything built out ... The vehicles needs take absolute precedence, and any
--   energy needed is consumed, and we have to fit around that ... once we run test and see what their consumption is like
--   with additional vehicles and everything considered, then we can raise that ceiling ... Once we get that idea, we can
--   set the new benchmarks and then try to work down that margin with battery energy storage or any other methods." So
--   the depot's limits are what is installed, and no limit below it: dcfc_max_concurrent_kw 10,500, thirty posts at their
--   350 kW rating at once; service_max_kw 12,250, those posts plus the battery charging at its rating (NASH-BESS-01, a
--   Megapack 2 XL, max_charge_kw 1,500) plus 250 kW of building (the most the depot's energy snapshots have read is
--   228.2 kW). No car can be refused, slowed or held for power: a car charges at what it and its post can take. What the
--   thirty posts then draw is the measurement a ceiling is set from, when testing resumes (rule 12), and the margin under
--   it is then worked down on the operator's side (the battery, the tariff), never by a vehicle. The held site the
--   research wing measured (0451 §10 point 3; arm 112, sweep heldtick_normal_2026_10_19: forty posts on 2,400 kW of
--   shared cabinets met 939.8 car-hours against 940.5 with power to spare, one seed) stays the build-out
--   dcfc30_cab2400, for that later work and not as the base.
--
-- ══ §2 WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Canopy C's ten posts. The rows of NASH-L2-STALL-16..20 become NASH-DCFC-STALL-21..25 (west column, relative_x
--       288.8583, heading 60) and NASH-L2-STALL-26..30 become NASH-DCFC-STALL-26..30 (east column, 310.8366, heading 300),
--       on canopy A's rows (relative_y 185.2461, 163.2677, 141.2894, 119.3110, 97.3327): render x 190 and 204 at rows 88,
--       102, 116, 130, 144, as scripts/buildLayoutSeed.mjs writes canopy A's pattern there. Every column is the one 0759
--       wrote into its dcfc30 build-out for the day, and P1 asserts this file's plan equals that build-out's stall set entry
--       for entry: display_name CANOPY-03 W-21 .. CANOPY-03 E-30; zone dcfc_zone; connector 350 kW; fiducial FID-D3-nn-A
--       and UWB beacon UWB-D3-nn; equipment_config {charger_kw 350, canopy_code CANOPY-03, canopy_side W/E}; latitude
--       canopy A's post's on the same row, longitude canopy C's column's; distance_from_entrance west 181, 152, 125, 98,
--       70 and east 180, 151, 123, 94, 64. Width, depth, connector type, inlets, stall_kind, canopy and cover are what
--       they were.
--   (b) Their chargers NASH-L2-16..20 and 26..30 become NASH-DCFC-21..30 with canopy A's make, model, rating, firmware,
--       protocol and connectors (ABB Terra HP 350, 350 kW, 1.4.2, OCPP 1.6J, one connector); installed_at the apply;
--       Available, no fault.
--   (c) Their capabilities: charge_l2 becomes charge_dcfc for each of the seven asset classes.
--   (d) NASH-L2-STALL-31..35 are retired as 0759 retires 11..15: stall_type parking, no position, no charger, no zone,
--       stall_kind retired, no canopy, not covered, every capability inactive, the row kept because history references it.
--       Their chargers NASH-L2-31..35 are decommissioned at the apply.
--   (e) The depot: dcfc_max_concurrent_kw 3,600 -> 10,500 and service_max_kw 4,363 -> 12,250, what is installed (§1);
--       site_layout dcfc_count 30 and l2_count 0.
--   (f) CANOPY-03 reads 'Solar Canopy C (DCFC)', chargers {dcfc: 10}, stall_capacity 10, as CANOPY-01 and CANOPY-02 do.
--       Its panels and solar are unchanged.
--   (g) No setting changes. The held-site settings (dc_power_sharing, dc_power_managed, dc_power_first_reading, 0726-0733)
--       stay off at the twin depot: they divide a held limit, and the depot holds none.
--   (h) The renderer draws canopy C from these rows (§0).
--   Not changed: canopies A and B, the 113 staging spaces, the bays, and every engine function. No function body is
--   replaced; the base history and ottoq_stall_type_at (0759) carry the past (§4).
--
-- ══ §3 THE BUILD-OUTS AFTER THIS FILE ════════════════════════════════════════════════════════════════════════════════
--
--   Every build-out keeps the day it meant. Each that drew canopy C as fifteen standard chargers gains canopy C as it
--   stood until this file (the history's before images, the columns that moved), after the set 0759 gave it:
--     dcfc10, dcfc15, dcfc20_in_place, dcfc40, dcfc40_cab2400, dcfc40_grid_dcfc20, dcfc40_grid_today
--                          canopy B back (0759), then canopy C back, then their in-place conversions as before;
--     dcfc20, dcfc20_grid_today
--                          canopy C back: the 20-post depot 0759 built, on its grid (3,600/4,363) or today's (1,800/2,500).
--   and two describe the new depot:
--     dcfc30               the depot as built from this file, on its limits (10,500/12,250): no set. Until this file it
--                          converted canopy C for the day on 5,400/6,226; 0759 defined it and P1 asserts no run, cell or
--                          arm has named it, so no day changes meaning.
--     dcfc30_cab2400       new: the same depot on today's service through 2,400 kW of shared cabinets (2,400/2,500), the
--                          held site the research wing measured at forty posts, kept for the margin work after a ceiling
--                          is set (§1). Not the base.
--   V4 proves the table: every build-out applied and restored leaves the depot exactly as built, each old one reproduces,
--   column by column, the depot it built before this file (read here before anything moves), and the two new ones are the
--   depot as built on their grids.
--
-- ══ §4 A BASE CHANGE MUST NOT REWRITE THE PAST ═══════════════════════════════════════════════════════════════════════
--
--   0759 built the machinery: public.ottoq_site_base_history (append-only) and public.ottoq_stall_type_at, which
--   ottoq_throughput_scorecard (version 0759) reads, so a run is scored with the spaces it ran on. This file appends its
--   fifteen rows under change_code '0763', valid_until the apply. V5 scores the latest completed day of each kind before
--   anything moves and again after, and each must match key for key. V6 reads the history and the type each space had.
--
-- ══ §5 CHECKS ════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight; no run live at the twin depot; no build-out applied; no active sweep or dial experiment there.
--   P1 0759 is applied and its lineage row present; the bodies 0759 leaves (prosrc md5s below, read from 0759 applied on
--   the scratch PostgreSQL over the live bodies of 2026-10-19, which live still carried on 2026-10-21) and the four stall
--   triggers; the depot as 0759 declares it (census, power, layout counts, canopy C's structure); canopy C's fifteen as
--   this file's plan names them, each with 35 capability rows, all active, 7 of them charge_l2; the dcfc30 build-out's
--   stall set equal to this file's plan; no car, reservation or open booking on canopy C; the new codes, identifiers,
--   build-out and history rows free; no run, sweep cell or sweep arm naming dcfc30 or dcfc30_cab2400; no function naming a
--   charger space, the parking type or stall_kind but those 0759 read. P2 once. Pre-images under '0763_pre'.
--   V1 the census and the layout as declared; everything else unchanged; ottoq_check_stall_overlap and
--   ottoq_check_fence_containment pass; each canopy C post on canopy A's row, 14 units from its neighbour. V3 the stall
--   trigger signed one event per moved space, as migration_script 0763, to no run. V4 the build-outs (§3). V5 the stored
--   days (§4). V6 the history and ottoq_stall_type_at. tests/test_thirty_post_base_sql.py runs 0759 and then this file on
--   the scratch PostgreSQL against the live bodies and the depot's rows as read on 2026-10-19.
--
-- ══ §6 RECERT AND DIAL CLASSIFICATION ════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert TRUE: every certified canon column runs on the twin depot and reads the stalls, chargers and power this
--   changes. forces_dial_restart TRUE: a dial pair or sweep arm read across this change would compare two depots.
--
-- ══ §7 WHAT IT NEEDS ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0759 applied; every sweep at the twin depot paused and every dial experiment concluded or abandoned (P0); the
--   renderer's 30-post layout live first; the connector's approval. A ceiling below what is installed is set later, as
--   its own certified change, from what the thirty posts are measured to draw (rule 13).
--
-- ROLLBACK is a base change of its own, filed as its own migration with both flags TRUE, with no run live and nothing in
--   flight, and this file's lineage row kept. As migration_script, to no run, it puts each space, charger and capability
--   back from the before images in public.ottoq_site_base_history WHERE change_code = '0763' and records that change there
--   as its own; it puts the depot's power limits and site_layout, CANOPY-03's title and properties and the build-out rows
--   back from the '0763_pre' rows snapshots, and DELETEs dcfc30_cab2400 if no cell names it.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing queued, running or applied at the twin depot ──
DO $p0$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_n int;
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0763 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = c_depot AND status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0763 P0: a run is live at the twin depot; the depot changes only between runs';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_site_buildout_active WHERE depot_id = c_depot) THEN
    RAISE EXCEPTION '0763 P0: a build-out is applied at the twin depot in this transaction';
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_throughput_sweeps WHERE depot_id = c_depot AND status = 'active';
  IF v_n > 0 THEN
    RAISE EXCEPTION '0763 P0: % research sweeps are active at the twin depot. This file changes the depot every queued cell reads, and its dial floor re-queues every active sweep: pause or conclude each first (Chase''s call)', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_dial_experiments WHERE depot_id = c_depot AND status = 'active';
  IF v_n > 0 THEN
    RAISE EXCEPTION '0763 P0: % dial experiments are active at the twin depot. Their pairs ran on the depot this file changes: conclude or abandon each first (Chase''s call)', v_n;
  END IF;
END $p0$;

-- ── P1: 0759 applied, the bodies it leaves, the depot as it declares it, and the vocabulary ──
DO $p1$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_bad text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0759_canopy_b_is_restriped_for_ten_more_robotic_fast_chargers') THEN
    RAISE EXCEPTION '0763 P1: 0759 is not applied; apply in order';
  END IF;
  SELECT string_agg(f.sig, ', ') INTO v_bad
    FROM (VALUES ('public.ottoq_site_buildout_apply(uuid,text)', '3747f9959a8dce8409b0a13f2de49b12'),
                 ('public.ottoq_site_buildout_restore(uuid)', '5d6458a109e0bbeb287f22687627b281'),
                 ('public.ottoq_throughput_scorecard(uuid)', 'f16f725c4a352ae4ea94f07e1fb093e6'),
                 ('public.ottoq_stall_type_at(uuid,timestamp with time zone)', 'ef53e2f546a80afc3f1e343f8d7d3d0a'),
                 ('public.ottoq_site_base_history_append_only()', '761155bcea6e384f0fa2944f3ccd7447'),
                 ('public.ottoq_site_buildout_census(uuid)', 'a2663c6fd8bdc090b82f17b981e8785b'),
                 ('public.ottoq_site_buildout_must_not_commit()', '4becb79612000a453dc5e31431324acb'),
                 ('public.ottoq_check_stall_overlap(uuid)', '725e099f3e62f9c8f63c09b167f5563d'),
                 ('public.ottoq_check_fence_containment(uuid)', '6bab817c468c5f803d72dbb39eceb732'),
                 ('public.ottoq_stalls_state_change()', '1b5668fda6c5e0f9eb8565db822180b9'),
                 ('public.ottoq_trg_reassignment_guard()', 'b45ed80258565075f6cacc1e841d76c4'),
                 ('public.ottoq_stall_seat_is_exclusive()', '7ce8d314e45733b164b7ad183990f043'),
                 ('public.update_timestamp()', 'da5ac28a58c8b4bb30209bf0d3d7082c')) AS f(sig, m)
   WHERE (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(f.sig)) IS DISTINCT FROM f.m;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0763 P1: these are not the bodies 0759 leaves: %', v_bad;
  END IF;
  IF (SELECT string_agg(tgname::text, ',' ORDER BY tgname) FROM pg_trigger
       WHERE tgrelid = 'public.stalls'::regclass AND NOT tgisinternal)
     IS DISTINCT FROM 'trg_ottoq_stall_seat_is_exclusive,trg_ottoq_stalls_state_change,trg_reassignment_guard,trg_stalls_updated' THEN
    RAISE EXCEPTION '0763 P1: the triggers on public.stalls are not the four read';
  END IF;

  -- the depot as 0759 declares it
  IF (SELECT jsonb_object_agg(t, n) FROM (SELECT s.stall_type::text AS t, count(*) AS n FROM public.stalls s
                                            WHERE s.depot_id = c_depot GROUP BY 1) z)
       IS DISTINCT FROM '{"dcfc": 20, "l2": 15, "parking": 5, "staging": 113, "wash_bay": 3, "service_bay": 2}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.depots WHERE id = c_depot AND dcfc_max_concurrent_kw = 3600 AND service_max_kw = 4363
                       AND site_layout->'dcfc_count' = '20'::jsonb AND site_layout->'l2_count' = '15'::jsonb)
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_site_structures WHERE depot_id = c_depot AND structure_code = 'CANOPY-03'
                       AND title = 'Solar Canopy C (L2)' AND properties->'chargers' = '{"l2": 15}'::jsonb
                       AND properties->'stall_capacity' = '15'::jsonb) THEN
    RAISE EXCEPTION '0763 P1: the twin depot is not as 0759 declares it (its census, power, layout counts or canopy C)';
  END IF;
  -- canopy C's fifteen: no car, no reservation, no open booking
  IF EXISTS (SELECT 1 FROM public.stalls s WHERE s.depot_id = c_depot AND s.canopy_code = 'CANOPY-03'
                AND (s.current_vehicle_id IS NOT NULL OR s.reserved_by IS NOT NULL OR s.reserved_for_mission_id IS NOT NULL))
     OR EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
                 WHERE s.depot_id = c_depot AND s.canopy_code = 'CANOPY-03' AND b.state IN ('held', 'active')) THEN
    RAISE EXCEPTION '0763 P1: a car, a reservation or an open booking is on canopy C';
  END IF;
  -- what this file adds is free
  IF EXISTS (SELECT 1 FROM public.stalls WHERE depot_id = c_depot AND stall_code ~ '^NASH-DCFC-STALL-(2[1-9]|30)$')
     OR EXISTS (SELECT 1 FROM public.ottoq_ocpp_chargers WHERE ocpp_identifier ~ '^NASH-DCFC-(2[1-9]|30)$')
     OR EXISTS (SELECT 1 FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc30_cab2400')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc30' AND depot_id = c_depot)
     OR EXISTS (SELECT 1 FROM public.ottoq_site_base_history WHERE change_code = '0763') THEN
    RAISE EXCEPTION '0763 P1: a code, an identifier, a build-out or a history row this file adds exists already, or 0759''s dcfc30 is missing';
  END IF;
  -- no day has run on dcfc30 or dcfc30_cab2400, and no queued cell or arm names them (dcfc30 changes meaning here)
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs
              WHERE payload->'site_buildout'->>'buildout_code' IN ('dcfc30', 'dcfc30_cab2400')) THEN
    RAISE EXCEPTION '0763 P1: a run has named dcfc30 or dcfc30_cab2400';
  END IF;
  IF to_regclass('public.ottoq_throughput_sweep_cells') IS NOT NULL THEN
    EXECUTE $q$SELECT string_agg(cell_code, ', ') FROM public.ottoq_throughput_sweep_cells
                WHERE buildout_code IN ('dcfc30', 'dcfc30_cab2400')$q$ INTO v_bad;
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION '0763 P1: these sweep cells name dcfc30 or dcfc30_cab2400: %', v_bad;
    END IF;
  END IF;
  IF to_regclass('public.ottoq_throughput_sweep_arms') IS NOT NULL THEN
    EXECUTE $q$SELECT string_agg(arm_id::text, ', ') FROM public.ottoq_throughput_sweep_arms
                WHERE buildout->>'buildout_code' IN ('dcfc30', 'dcfc30_cab2400')$q$ INTO v_bad;
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION '0763 P1: these sweep arms ran dcfc30 or dcfc30_cab2400: %', v_bad;
    END IF;
  END IF;
  -- nothing knows a charger space by its name, zone, canopy, fiducial or OCPP identifier but the build-out apply;
  -- comments stripped (0759 P1's three reads, unchanged)
  SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY 1) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'ottoq', 'twin') AND p.proname NOT LIKE 'ottoq_fn_backup%'
     AND p.oid <> 'public.ottoq_site_buildout_apply(uuid,text)'::regprocedure
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g')
         ~ '(NASH-L2|NASH-DCFC|DCFC-STALL|L2-STALL|dcfc_zone|l2_zone|CANOPY-0[123]|FID-D|UWB-D)';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0763 P1: these functions name a charger space, zone, canopy, fiducial or identifier, so a moved or retired space could read wrong to them: %', v_bad;
  END IF;
  SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY 1) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'ottoq', 'twin') AND p.proname NOT LIKE 'ottoq_fn_backup%'
     AND (n.nspname, p.proname) <> ('ottoq', 'ottoq_record_enacted_booking')
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') ~ $re$'parking'$re$;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0763 P1: these functions name the parking type, so a retired space could be offered: %', v_bad;
  END IF;
  -- (0759's build-out apply names stall_kind among the columns a stall set may set: it writes a retired space's, and
  -- reads none)
  SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY 1) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'ottoq', 'twin') AND p.proname NOT LIKE 'ottoq_fn_backup%'
     AND p.oid <> 'public.ottoq_site_buildout_apply(uuid,text)'::regprocedure
     AND p.proname NOT IN ('ottoq_depot_cards', 'ottoq_recall_interval_scheduled_v1', 'ottoq_recall_naive_threshold_v1',
                           'ottoq_shield_and_log', 'workload_harness_metrics')
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') ~ 'stall_kind';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0763 P1: these functions read stall_kind and were not read for a retired space: %', v_bad;
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0763_canopy_c_is_restriped_and_the_twin_depot_has_no_standard_chargers') THEN
    RAISE EXCEPTION '0763 P2: already applied';
  END IF;
END $once$;

-- ── what the checks compare: 0759's column-by-column image of the depot, unchanged ──
CREATE FUNCTION pg_temp.f_0763_depot(p_depot uuid) RETURNS jsonb LANGUAGE sql STABLE AS $fn$
  SELECT jsonb_build_object(
    'stalls', (SELECT md5(string_agg(jsonb_build_array(s.id, s.stall_code, s.stall_type, s.display_name,
                 round(s.relative_x::numeric, 4), round(s.relative_y::numeric, 4), s.heading_degrees,
                 round(s.absolute_lat::numeric, 8), round(s.absolute_lng::numeric, 8), s.distance_from_entrance,
                 s.equipment_config - 'buildout', s.fiducial_marker_id, s.uwb_beacon_id, s.zone, s.connector_type,
                 round(s.connector_max_kw, 1), s.supported_inlet_types, s.ocpp_charger_id, s.stall_kind, s.canopy_code,
                 s.covered, s.stall_width_ft, s.stall_depth_ft, s.staging_role)::text, ';' ORDER BY s.id))
                 FROM public.stalls s WHERE s.depot_id = p_depot),
    'chargers', (SELECT md5(string_agg(jsonb_build_array(c.charger_id, c.ocpp_identifier, c.vendor, c.model,
                   c.serial_number, c.firmware_version, c.ocpp_protocol_version, round(c.max_kw, 1), c.num_connectors,
                   c.installed_at, c.decommissioned_at)::text, ';' ORDER BY c.charger_id))
                   FROM public.ottoq_ocpp_chargers c WHERE c.depot_id = p_depot),
    'capabilities', (SELECT md5(string_agg(jsonb_build_array(k.stall_id, k.asset_class_code, k.pack_id, k.operation_code,
                       k.active, k.source)::text, ';' ORDER BY k.stall_id, k.asset_class_code, k.operation_code))
                       FROM public.ottoq_service_point_capabilities k JOIN public.stalls s ON s.id = k.stall_id
                      WHERE s.depot_id = p_depot),
    'power', (SELECT jsonb_build_object('dcfc_max_concurrent_kw', d.dcfc_max_concurrent_kw, 'service_max_kw', d.service_max_kw)
                FROM public.depots d WHERE d.id = p_depot),
    'census', (SELECT jsonb_object_agg(t, n) FROM (SELECT s.stall_type::text AS t, count(*) AS n FROM public.stalls s
                                                    WHERE s.depot_id = p_depot GROUP BY 1) z));
$fn$;

-- ── the plan: canopy C's ten posts (§2 (a), (b)) and its five retired spaces (§2 (d)), 0759's dcfc30 values ──
CREATE TEMP TABLE _0763_restripe (stall_id uuid PRIMARY KEY, old_code text NOT NULL, new_code text NOT NULL,
  display_name text NOT NULL, x double precision NOT NULL, y double precision NOT NULL, heading smallint NOT NULL,
  lat double precision NOT NULL, lng double precision NOT NULL, dist integer NOT NULL, side text NOT NULL,
  fid text NOT NULL, uwb text NOT NULL, charger_id uuid NOT NULL, old_ocpp text NOT NULL, new_ocpp text NOT NULL)
  ON COMMIT DROP;
INSERT INTO _0763_restripe VALUES
  ('56f6854b-63f7-46db-b145-6e445ee4eb3b', 'NASH-L2-STALL-16', 'NASH-DCFC-STALL-21', 'CANOPY-03 W-21', 288.8583, 185.2461, 60,
   36.14020892, -86.77181735, 181, 'W', 'FID-D3-21-A', 'UWB-D3-21', '1c0a3045-c430-453e-8b87-bb7464bd70cd', 'NASH-L2-16', 'NASH-DCFC-21'),
  ('e9952b02-4f4c-4c4e-bb4b-fdd130f3051c', 'NASH-L2-STALL-17', 'NASH-DCFC-STALL-22', 'CANOPY-03 W-22', 288.8583, 163.2677, 60,
   36.14014854, -86.77181735, 152, 'W', 'FID-D3-22-A', 'UWB-D3-22', '0b2ae0e1-172b-45ce-9164-c441d1ec6a74', 'NASH-L2-17', 'NASH-DCFC-22'),
  ('f0d61886-45fa-4187-acb0-9560f85390cb', 'NASH-L2-STALL-18', 'NASH-DCFC-STALL-23', 'CANOPY-03 W-23', 288.8583, 141.2894, 60,
   36.14008816, -86.77181735, 125, 'W', 'FID-D3-23-A', 'UWB-D3-23', '57b526e7-c09c-4736-84ed-f55b25362935', 'NASH-L2-18', 'NASH-DCFC-23'),
  ('87f204a1-c4eb-43ba-85f9-5d967f91b706', 'NASH-L2-STALL-19', 'NASH-DCFC-STALL-24', 'CANOPY-03 W-24', 288.8583, 119.3110, 60,
   36.14002778, -86.77181735, 98, 'W', 'FID-D3-24-A', 'UWB-D3-24', 'ad5dfafc-9c22-4199-a210-c98ac7468bf3', 'NASH-L2-19', 'NASH-DCFC-24'),
  ('d01cc4ff-a0dd-4db0-a6ec-f8e5b95d7be7', 'NASH-L2-STALL-20', 'NASH-DCFC-STALL-25', 'CANOPY-03 W-25', 288.8583, 97.3327, 60,
   36.13996740, -86.77181735, 70, 'W', 'FID-D3-25-A', 'UWB-D3-25', 'da614701-ef70-4eb6-b6c5-59e2bd2d4fe6', 'NASH-L2-20', 'NASH-DCFC-25'),
  ('254d40a1-4c83-4b4f-a1b5-477300c3bc3f', 'NASH-L2-STALL-26', 'NASH-DCFC-STALL-26', 'CANOPY-03 E-26', 310.8366, 185.2461, 300,
   36.14020892, -86.77174259, 180, 'E', 'FID-D3-26-A', 'UWB-D3-26', 'd9f483b1-73a0-4936-95e5-60a278f8c5dd', 'NASH-L2-26', 'NASH-DCFC-26'),
  ('6b043f2d-e7b5-485b-beb1-3e7b7c283964', 'NASH-L2-STALL-27', 'NASH-DCFC-STALL-27', 'CANOPY-03 E-27', 310.8366, 163.2677, 300,
   36.14014854, -86.77174259, 151, 'E', 'FID-D3-27-A', 'UWB-D3-27', 'e211c51f-2f13-4d2e-8216-4539ca674fa7', 'NASH-L2-27', 'NASH-DCFC-27'),
  ('c957b07b-8481-446d-af1b-974421a10641', 'NASH-L2-STALL-28', 'NASH-DCFC-STALL-28', 'CANOPY-03 E-28', 310.8366, 141.2894, 300,
   36.14008816, -86.77174259, 123, 'E', 'FID-D3-28-A', 'UWB-D3-28', 'f0813a87-9d60-4fe8-bfd1-dc4c5924aa89', 'NASH-L2-28', 'NASH-DCFC-28'),
  ('c1808c59-6c55-406e-9821-25ba548698bc', 'NASH-L2-STALL-29', 'NASH-DCFC-STALL-29', 'CANOPY-03 E-29', 310.8366, 119.3110, 300,
   36.14002778, -86.77174259, 94, 'E', 'FID-D3-29-A', 'UWB-D3-29', '5b918708-e2ae-4727-bedf-27496628aa73', 'NASH-L2-29', 'NASH-DCFC-29'),
  ('3f2338b8-5844-4bc3-a7d9-152439279fcd', 'NASH-L2-STALL-30', 'NASH-DCFC-STALL-30', 'CANOPY-03 E-30', 310.8366, 97.3327, 300,
   36.13996740, -86.77174259, 64, 'E', 'FID-D3-30-A', 'UWB-D3-30', 'e9a32d48-f506-48a0-94cd-7e1d3a2a7933', 'NASH-L2-30', 'NASH-DCFC-30');
CREATE TEMP TABLE _0763_retire (stall_id uuid PRIMARY KEY, code text NOT NULL, charger_id uuid NOT NULL, ocpp text NOT NULL)
  ON COMMIT DROP;
INSERT INTO _0763_retire VALUES
  ('bed6e8cf-4816-4451-b6ee-5294291912cd', 'NASH-L2-STALL-31', 'ef25544a-9d8f-4928-bee0-738aec3c7c1f', 'NASH-L2-31'),
  ('1bcc7405-d157-43ae-ac0c-ccb88791a451', 'NASH-L2-STALL-32', '76fdb945-47f9-4398-ba81-34d2b8fb7d64', 'NASH-L2-32'),
  ('f517a13e-c512-485f-af8b-4e92e9aae972', 'NASH-L2-STALL-33', '3caee32b-a3f3-4c40-b598-be5146fb5eff', 'NASH-L2-33'),
  ('f99a8657-b524-46a5-9080-c37f25c6a33d', 'NASH-L2-STALL-34', 'a273725f-61da-4de5-827b-257d6b95de88', 'NASH-L2-34'),
  ('35c6e6f3-8291-42e6-95a0-a9a4dc7daec1', 'NASH-L2-STALL-35', '443a7c32-7914-4002-955f-c9cb100f6a79', 'NASH-L2-35');

DO $plan$
DECLARE v_set jsonb; v_bad text;
BEGIN
  -- the plan names the rows read: canopy C's fifteen standard chargers, each with 35 capabilities, all active, 7 charge_l2
  IF (SELECT count(*) FROM _0763_restripe r JOIN public.stalls s ON s.id = r.stall_id
       WHERE s.stall_code = r.old_code AND s.stall_type = 'l2' AND s.canopy_code = 'CANOPY-03' AND s.ocpp_charger_id = r.charger_id) <> 10
     OR (SELECT count(*) FROM _0763_retire r JOIN public.stalls s ON s.id = r.stall_id
          WHERE s.stall_code = r.code AND s.stall_type = 'l2' AND s.canopy_code = 'CANOPY-03' AND s.ocpp_charger_id = r.charger_id) <> 5
     OR (SELECT count(*) FROM public.stalls s WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
          AND s.canopy_code = 'CANOPY-03') <> 15
     OR EXISTS (SELECT 1 FROM (SELECT stall_id FROM _0763_restripe UNION ALL SELECT stall_id FROM _0763_retire) p
                 WHERE (SELECT count(*) FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = p.stall_id) <> 35
                    OR (SELECT count(*) FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = p.stall_id AND k.active) <> 35
                    OR (SELECT count(*) FROM public.ottoq_service_point_capabilities k
                         WHERE k.stall_id = p.stall_id AND k.operation_code = 'charge_l2') <> 7)
     OR (SELECT count(*) FROM _0763_restripe r WHERE EXISTS (
           SELECT 1 FROM public.stalls a WHERE a.depot_id = '11111111-1111-1111-1111-111111111111' AND a.canopy_code = 'CANOPY-01'
              AND a.stall_type = 'dcfc' AND round(a.relative_y::numeric, 4) = round(r.y::numeric, 4)
              AND a.heading_degrees = r.heading AND a.absolute_lat = r.lat)) <> 10
     OR (SELECT count(*) FROM public.ottoq_ocpp_chargers WHERE ocpp_identifier = 'NASH-DCFC-01' AND vendor = 'ABB'
          AND model = 'Terra HP 350' AND max_kw = 350 AND firmware_version = '1.4.2' AND ocpp_protocol_version = '1.6J'
          AND num_connectors = 1) <> 1 THEN
    RAISE EXCEPTION '0763: the plan does not name the depot as read';
  END IF;
  -- and it is 0759's dcfc30, entry for entry: the posts' layout, chargers and capability flips, and the retired five
  SELECT stall_set INTO v_set FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc30';
  SELECT string_agg(r.new_code, ', ' ORDER BY r.new_code) INTO v_bad
    FROM _0763_restripe r
   WHERE NOT EXISTS (
     SELECT 1 FROM jsonb_array_elements(v_set) e
      WHERE (e->>'stall_id')::uuid = r.stall_id
        AND e->'stall' = jsonb_build_object('stall_code', r.new_code, 'stall_type', 'dcfc', 'display_name', r.display_name,
                            'relative_x', r.x, 'relative_y', r.y, 'heading_degrees', r.heading, 'absolute_lat', r.lat,
                            'absolute_lng', r.lng, 'distance_from_entrance', r.dist,
                            'equipment_config', jsonb_build_object('charger_kw', 350, 'canopy_code', 'CANOPY-03',
                                                                   'canopy_side', r.side),
                            'fiducial_marker_id', r.fid, 'uwb_beacon_id', r.uwb, 'zone', 'dcfc_zone',
                            'connector_max_kw', 350.0)
        AND (e->>'charger_id')::uuid = r.charger_id
        AND e->'charger'->>'ocpp_identifier' = r.new_ocpp
        AND e->'capabilities' = '{"operation_from": "charge_l2", "operation_to": "charge_dcfc"}'::jsonb);
  IF v_bad IS NOT NULL OR jsonb_array_length(v_set) <> 15
     OR (SELECT count(*) FROM jsonb_array_elements(v_set) e JOIN _0763_retire r ON r.stall_id = (e->>'stall_id')::uuid
          WHERE e->'stall'->>'stall_type' = 'parking' AND e->'stall'->>'stall_kind' = 'retired'
            AND e->'capabilities' = '{"active": false}'::jsonb) <> 5 THEN
    RAISE EXCEPTION '0763: the plan is not 0759''s dcfc30 (posts not matching: %)', COALESCE(v_bad, 'none; the retired five differ');
  END IF;
END $plan$;

-- ── what V1, V4 and V5 compare against, read before anything moves ──
CREATE TEMP TABLE _0763_read (k text PRIMARY KEY, v jsonb) ON COMMIT DROP;
INSERT INTO _0763_read
SELECT 'depot', pg_temp.f_0763_depot('11111111-1111-1111-1111-111111111111')
UNION ALL
SELECT 'untouched', jsonb_build_object(
  'stalls', (SELECT md5(string_agg((to_jsonb(s) - 'updated_at')::text, ';' ORDER BY s.id)) FROM public.stalls s
              WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
                AND s.id NOT IN (SELECT stall_id FROM _0763_restripe UNION ALL SELECT stall_id FROM _0763_retire)),
  'chargers', (SELECT md5(string_agg((to_jsonb(c) - 'updated_at')::text, ';' ORDER BY c.charger_id)) FROM public.ottoq_ocpp_chargers c
                WHERE c.depot_id = '11111111-1111-1111-1111-111111111111'
                  AND c.charger_id NOT IN (SELECT charger_id FROM _0763_restripe UNION ALL SELECT charger_id FROM _0763_retire)),
  'capabilities', (SELECT md5(string_agg(to_jsonb(k)::text, ';' ORDER BY k.stall_id, k.asset_class_code, k.operation_code))
                     FROM public.ottoq_service_point_capabilities k JOIN public.stalls s ON s.id = k.stall_id
                    WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
                      AND s.id NOT IN (SELECT stall_id FROM _0763_restripe UNION ALL SELECT stall_id FROM _0763_retire)));

-- each build-out as the depot built it until now: applied and restored, its depot read, then rolled back
DO $old$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  r record; v_depot jsonb; v_receipt jsonb; v_back jsonb;
BEGIN
  FOR r IN SELECT buildout_code FROM public.ottoq_site_buildouts WHERE depot_id = c_depot ORDER BY buildout_code LOOP
    BEGIN
      v_receipt := public.ottoq_site_buildout_apply(c_depot, r.buildout_code);
      v_depot := pg_temp.f_0763_depot(c_depot);
      PERFORM public.ottoq_site_buildout_restore(c_depot);
      v_back := pg_temp.f_0763_depot(c_depot);
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '0763_OLD_ROLLBACK';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> '0763_OLD_ROLLBACK' THEN RAISE; END IF;
    END;
    IF v_back IS DISTINCT FROM (SELECT v FROM _0763_read WHERE k = 'depot') THEN
      RAISE EXCEPTION '0763: % did not restore the depot as built before this file', r.buildout_code;
    END IF;
    INSERT INTO _0763_read VALUES ('old:' || r.buildout_code, v_depot || jsonb_build_object('receipt', v_receipt));
  END LOOP;
END $old$;

-- the latest completed day of each kind, scored before anything moves (V5)
CREATE TEMP TABLE _0763_days ON COMMIT DROP AS
SELECT q.sim_run_id, q.kind, public.ottoq_throughput_scorecard(q.sim_run_id) AS before
  FROM (SELECT DISTINCT ON (COALESCE(sr.payload->'site_buildout'->>'buildout_code', '-'))
               sr.sim_run_id, COALESCE(sr.payload->'site_buildout'->>'buildout_code', '-') AS kind
          FROM public.ottoq_sim_runs sr
         WHERE sr.depot_id = '11111111-1111-1111-1111-111111111111' AND sr.status = 'completed'
         ORDER BY COALESCE(sr.payload->'site_buildout'->>'buildout_code', '-'), sr.started_at DESC) q;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0763_pre', 'rows', 'public', t.object_name, t.def::text, md5(t.def::text)
  FROM (SELECT 'depots' AS object_name,
               (SELECT jsonb_agg(jsonb_build_object('id', d.id, 'dcfc_max_concurrent_kw', d.dcfc_max_concurrent_kw,
                                                    'service_max_kw', d.service_max_kw, 'site_layout', d.site_layout))
                  FROM public.depots d WHERE d.id = '11111111-1111-1111-1111-111111111111') AS def
        UNION ALL
        SELECT 'ottoq_site_structures',
               (SELECT jsonb_agg(to_jsonb(x)) FROM public.ottoq_site_structures x
                 WHERE x.depot_id = '11111111-1111-1111-1111-111111111111' AND x.structure_code = 'CANOPY-03')
        UNION ALL
        SELECT 'ottoq_site_buildouts', (SELECT jsonb_agg(to_jsonb(b) ORDER BY b.buildout_code) FROM public.ottoq_site_buildouts b)) t;

-- ── 1. the base change: canopy C re-striped (§2) ──
-- Who is acting, and filed to no run (0421's doctrine): the stall trigger signs one event per moved space.
SELECT set_config('ottoq.actor_type', 'migration_script', true), set_config('ottoq.actor_id', '0763', true),
       set_config('ottoq.sim_run_id', 'none', true);

CREATE TEMP TABLE _0763_before ON COMMIT DROP AS
SELECT s.id AS stall_id, s.stall_code, s.stall_type::text AS stall_type,
       jsonb_build_object('stall', to_jsonb(s), 'charger_id', s.ocpp_charger_id, 'charger', to_jsonb(c),
                          'capabilities', COALESCE((SELECT jsonb_agg(jsonb_build_object('asset_class_code', k.asset_class_code,
                                                                                        'operation_code', k.operation_code,
                                                                                        'active', k.active)
                                                                     ORDER BY k.asset_class_code, k.operation_code)
                                                      FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id),
                                                   '[]'::jsonb)) AS image
  FROM public.stalls s LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
 WHERE s.id IN (SELECT stall_id FROM _0763_restripe UNION ALL SELECT stall_id FROM _0763_retire);

-- (a) the ten posts, (b) their chargers, (c) their capabilities
UPDATE public.stalls s
   SET stall_code             = r.new_code,
       stall_type             = 'dcfc',
       display_name           = r.display_name,
       relative_x             = r.x,
       relative_y             = r.y,
       heading_degrees        = r.heading,
       absolute_lat           = r.lat,
       absolute_lng           = r.lng,
       distance_from_entrance = r.dist,
       equipment_config       = jsonb_build_object('charger_kw', 350, 'canopy_code', 'CANOPY-03', 'canopy_side', r.side),
       fiducial_marker_id     = r.fid,
       uwb_beacon_id          = r.uwb,
       zone                   = 'dcfc_zone',
       connector_max_kw       = 350.0
  FROM _0763_restripe r
 WHERE s.id = r.stall_id;
UPDATE public.ottoq_ocpp_chargers c
   SET ocpp_identifier          = r.new_ocpp,
       vendor                   = a.vendor,
       model                    = a.model,
       firmware_version         = a.firmware_version,
       ocpp_protocol_version    = a.ocpp_protocol_version,
       max_kw                   = a.max_kw,
       num_connectors           = a.num_connectors,
       installed_at             = now(),
       station_state            = 'Available',
       station_state_changed_at = now(),
       last_fault_code          = NULL,
       last_fault_at            = NULL,
       last_fault_payload       = NULL,
       updated_at               = now()
  FROM _0763_restripe r, public.ottoq_ocpp_chargers a
 WHERE c.charger_id = r.charger_id AND a.ocpp_identifier = 'NASH-DCFC-01';
UPDATE public.ottoq_service_point_capabilities k
   SET operation_code = 'charge_dcfc'
 WHERE k.stall_id IN (SELECT stall_id FROM _0763_restripe) AND k.operation_code = 'charge_l2';

-- (d) the five retired spaces and their chargers
UPDATE public.stalls s
   SET stall_type            = 'parking',
       display_name          = 'Retired by 0763 (was ' || s.display_name || ')',
       relative_x            = NULL,
       relative_y            = NULL,
       absolute_lat          = NULL,
       absolute_lng          = NULL,
       zone                  = NULL,
       stall_kind            = 'retired',
       ocpp_charger_id       = NULL,
       connector_type        = NULL,
       connector_max_kw      = NULL,
       supported_inlet_types = '{}'::text[],
       canopy_code           = NULL,
       covered               = false,
       equipment_config      = jsonb_build_object('retired_by', '0763', 'was', s.stall_code)
  FROM _0763_retire r
 WHERE s.id = r.stall_id;
UPDATE public.ottoq_ocpp_chargers c
   SET decommissioned_at = now(), station_state = 'Unavailable', station_state_changed_at = now(), updated_at = now()
  FROM _0763_retire r
 WHERE c.charger_id = r.charger_id;
UPDATE public.ottoq_service_point_capabilities k
   SET active = false
 WHERE k.stall_id IN (SELECT stall_id FROM _0763_retire);

-- (e) the depot, (f) canopy C
UPDATE public.depots
   SET dcfc_max_concurrent_kw = 10500, service_max_kw = 12250,
       site_layout = COALESCE(site_layout, '{}'::jsonb) || jsonb_build_object('dcfc_count', 30, 'l2_count', 0)
 WHERE id = '11111111-1111-1111-1111-111111111111';
UPDATE public.ottoq_site_structures
   SET title = 'Solar Canopy C (DCFC)',
       properties = properties || jsonb_build_object('chargers', jsonb_build_object('dcfc', 10), 'stall_capacity', 10)
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND structure_code = 'CANOPY-03';

SELECT set_config('ottoq.actor_type', '', true), set_config('ottoq.actor_id', '', true);

-- the history: each moved space, before and after
INSERT INTO public.ottoq_site_base_history (change_code, depot_id, stall_id, valid_until, stall_code, stall_type, before, after)
SELECT '0763', '11111111-1111-1111-1111-111111111111', b.stall_id, now(), b.stall_code, b.stall_type, b.image,
       jsonb_build_object('stall', to_jsonb(s), 'charger_id', b.image->'charger_id',
                          'charger', (SELECT to_jsonb(c) FROM public.ottoq_ocpp_chargers c
                                       WHERE c.charger_id = (b.image->>'charger_id')::uuid),
                          'capabilities', COALESCE((SELECT jsonb_agg(jsonb_build_object('asset_class_code', k.asset_class_code,
                                                                                        'operation_code', k.operation_code,
                                                                                        'active', k.active)
                                                                     ORDER BY k.asset_class_code, k.operation_code)
                                                      FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id),
                                                   '[]'::jsonb))
  FROM _0763_before b JOIN public.stalls s ON s.id = b.stall_id;

-- ── 2. the build-outs (§3) ──
-- canopy C as it stood until this file: the history's before images, the columns that moved
CREATE TEMP TABLE _0763_canopy_c ON COMMIT DROP AS
SELECT jsonb_agg(z.e ORDER BY z.code) AS stall_set
  FROM (SELECT h.stall_code AS code,
               jsonb_build_object('stall_id', h.stall_id,
                 'stall', (SELECT jsonb_object_agg(k, h.before->'stall'->k)
                             FROM unnest(ARRAY['stall_code', 'stall_type', 'display_name', 'relative_x', 'relative_y',
                                               'heading_degrees', 'absolute_lat', 'absolute_lng', 'distance_from_entrance',
                                               'equipment_config', 'fiducial_marker_id', 'uwb_beacon_id', 'zone',
                                               'connector_type', 'connector_max_kw', 'supported_inlet_types',
                                               'ocpp_charger_id', 'stall_kind', 'canopy_code', 'covered', 'stall_width_ft',
                                               'stall_depth_ft']) AS k
                            WHERE (h.before->'stall'->k) IS DISTINCT FROM (h.after->'stall'->k)),
                 'charger_id', h.before->'charger_id',
                 'charger', (SELECT jsonb_object_agg(k, h.before->'charger'->k)
                               FROM unnest(ARRAY['ocpp_identifier', 'vendor', 'model', 'serial_number', 'firmware_version',
                                                 'ocpp_protocol_version', 'max_kw', 'num_connectors', 'installed_at',
                                                 'decommissioned_at']) AS k
                              WHERE (h.before->'charger'->k) IS DISTINCT FROM (h.after->'charger'->k)),
                 'capabilities', CASE WHEN h.stall_id IN (SELECT stall_id FROM _0763_restripe)
                                      THEN jsonb_build_object('operation_from', 'charge_dcfc', 'operation_to', 'charge_l2')
                                      ELSE jsonb_build_object('active', true) END) AS e
          FROM public.ottoq_site_base_history h
         WHERE h.change_code = '0763') z;

UPDATE public.ottoq_site_buildouts b
   SET stall_set = b.stall_set || (SELECT stall_set FROM _0763_canopy_c),
       title     = CASE b.buildout_code
                     WHEN 'dcfc20' THEN '20 robotic fast chargers: the twin depot as built from 0759 to 0763 (canopy C''s 15 standard chargers)'
                     WHEN 'dcfc20_grid_today' THEN '20 robotic fast chargers on today''s grid: the twin depot as built from 0759 to 0763, on 1,800 kW DC and 2,500 kW service'
                     ELSE b.title END,
       basis     = b.basis || jsonb_build_object('0763', CASE
                     WHEN b.buildout_code IN ('dcfc20', 'dcfc20_grid_today') THEN 'Since 0763 the depot is built with 30 fast chargers and no standard charger; this build-out''s stall_set puts canopy C back as it stood until 0763 (NASH-L2-STALL-16..20 and 26..35), so it reads the 20-post depot it always read.'
                     ELSE 'Since 0763 this build-out''s stall_set also puts canopy C back as it stood until 0763, after canopy B (0759), so it reproduces the day it measured.' END)
 WHERE b.depot_id = '11111111-1111-1111-1111-111111111111'
   AND b.buildout_code IN ('dcfc10', 'dcfc15', 'dcfc20_in_place', 'dcfc40', 'dcfc40_cab2400', 'dcfc40_grid_dcfc20',
                           'dcfc40_grid_today', 'dcfc20', 'dcfc20_grid_today');

UPDATE public.ottoq_site_buildouts b
   SET stall_set  = '[]'::jsonb,
       convert_l2 = '{}'::text[],
       buildable  = true,
       dcfc_max_concurrent_kw = 10500,
       service_max_kw         = 12250,
       title      = '30 robotic fast chargers: the twin depot as built from 0763, on what is installed (10,500 kW DC, 12,250 kW service)',
       basis      = b.basis || jsonb_build_object('0763', 'From 0763 the depot itself, every standard charger gone, on limits no car can reach (CLAUDE.md rule 13): thirty posts at their 350 kW rating, plus the battery charging at its 1,500 kW rating and 250 kW of building on the service. Until 0763 this code converted canopy C for the day on 5,400/6,226 kW; no run, cell or arm had named it (0763 P1).')
 WHERE b.buildout_code = 'dcfc30';

INSERT INTO public.ottoq_site_buildouts
  (buildout_code, depot_id, title, dcfc_posts, convert_l2, dcfc_max_concurrent_kw, service_max_kw, basis, stall_set, buildable)
SELECT 'dcfc30_cab2400', b.depot_id,
       '30 robotic fast chargers on today''s service through 2,400 kW of shared cabinets: a held site, for after a ceiling is set',
       30, '{}'::text[], 2400, 2500,
       (b.basis - 'note' - '0759' - '0763') || jsonb_build_object(
         'note', 'today''s 2,500 kW service; the thirty posts share 2,400 kW of DC cabinets (as dcfc40_cab2400 does for forty)',
         '0763', 'The depot as built from 0763 held to 2,400/2,500 kW, the held site the research wing measured at forty posts (arm 112, with dc_power_sharing, dc_power_managed and dc_power_first_reading 1 and enforce_site_charge_cap 0 in the cell). Not the base: the depot holds no ceiling until one is set from what its thirty posts draw (CLAUDE.md rule 13).'),
       '[]'::jsonb, true
  FROM public.ottoq_site_buildouts b WHERE b.buildout_code = 'dcfc30';

-- ── V1: the depot as declared, and everything else as it was ──
DO $v1$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  c_unit  constant numeric := 0.4785 / 0.3048;
  v_bad text;
BEGIN
  IF (SELECT v->'census' FROM _0763_read WHERE k = 'depot')
       IS DISTINCT FROM '{"dcfc": 20, "l2": 15, "parking": 5, "staging": 113, "wash_bay": 3, "service_bay": 2}'::jsonb
     OR pg_temp.f_0763_depot(c_depot)->'census'
       IS DISTINCT FROM '{"dcfc": 30, "parking": 10, "staging": 113, "wash_bay": 3, "service_bay": 2}'::jsonb THEN
    RAISE EXCEPTION '0763 V1: the census reads % before and % after', (SELECT v->'census' FROM _0763_read WHERE k = 'depot'),
      pg_temp.f_0763_depot(c_depot)->'census';
  END IF;
  SELECT string_agg(r.new_code, ', ' ORDER BY r.new_code) INTO v_bad
    FROM _0763_restripe r JOIN public.stalls s ON s.id = r.stall_id
    LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE NOT (s.stall_code = r.new_code AND s.stall_type = 'dcfc' AND s.display_name = r.display_name
              AND s.relative_x = r.x AND s.relative_y = r.y AND s.heading_degrees = r.heading
              AND s.absolute_lat = r.lat AND s.absolute_lng = r.lng AND s.distance_from_entrance = r.dist
              AND s.zone = 'dcfc_zone' AND s.connector_max_kw = 350 AND s.connector_type = 'Multi'
              AND s.fiducial_marker_id = r.fid AND s.uwb_beacon_id = r.uwb AND s.stall_kind = 'charging'
              AND s.canopy_code = 'CANOPY-03' AND s.covered AND s.stall_width_ft = 10 AND s.stall_depth_ft = 19.0276
              AND s.equipment_config = jsonb_build_object('charger_kw', 350, 'canopy_code', 'CANOPY-03', 'canopy_side', r.side)
              AND s.ocpp_charger_id = r.charger_id AND c.ocpp_identifier = r.new_ocpp AND c.vendor = 'ABB'
              AND c.model = 'Terra HP 350' AND c.max_kw = 350 AND c.firmware_version = '1.4.2'
              AND c.decommissioned_at IS NULL AND c.installed_at = now()
              AND (SELECT count(*) FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id AND k.active) = 35
              AND (SELECT count(*) FROM public.ottoq_service_point_capabilities k
                    WHERE k.stall_id = s.id AND k.operation_code = 'charge_dcfc') = 7
              AND NOT EXISTS (SELECT 1 FROM public.ottoq_service_point_capabilities k
                               WHERE k.stall_id = s.id AND k.operation_code = 'charge_l2'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0763 V1: these posts are not as declared: %', v_bad;
  END IF;
  -- each post on canopy A's row, 14 units from its neighbour in its column
  IF EXISTS (SELECT 1 FROM _0763_restripe r WHERE NOT EXISTS (
               SELECT 1 FROM public.stalls a WHERE a.depot_id = c_depot AND a.canopy_code = 'CANOPY-01'
                  AND round(a.relative_y::numeric, 4) = round(r.y::numeric, 4) AND a.heading_degrees = r.heading))
     OR EXISTS (SELECT 1 FROM (SELECT r.side, r.y - lag(r.y) OVER (PARTITION BY r.side ORDER BY r.y) AS gap
                                 FROM _0763_restripe r) z
                 WHERE z.gap IS NOT NULL AND abs(z.gap::numeric - 14 * c_unit) > 0.001) THEN
    RAISE EXCEPTION '0763 V1: a canopy C post is not on canopy A''s rows at the 14-unit pitch';
  END IF;
  SELECT string_agg(r.code, ', ' ORDER BY r.code) INTO v_bad
    FROM _0763_retire r JOIN public.stalls s ON s.id = r.stall_id JOIN public.ottoq_ocpp_chargers c ON c.charger_id = r.charger_id
   WHERE NOT (s.stall_code = r.code AND s.stall_type = 'parking' AND s.relative_x IS NULL AND s.relative_y IS NULL
              AND s.ocpp_charger_id IS NULL AND s.zone IS NULL AND s.stall_kind = 'retired' AND s.canopy_code IS NULL
              AND NOT s.covered AND c.decommissioned_at = now() AND c.ocpp_identifier = r.ocpp
              AND NOT EXISTS (SELECT 1 FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id AND k.active)
              AND (SELECT count(*) FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id) = 35
              AND NOT EXISTS (SELECT 1 FROM public.stalls o WHERE o.ocpp_charger_id = r.charger_id));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0763 V1: these spaces are not retired as declared: %', v_bad;
  END IF;
  IF (SELECT v FROM _0763_read WHERE k = 'untouched') IS DISTINCT FROM jsonb_build_object(
       'stalls', (SELECT md5(string_agg((to_jsonb(s) - 'updated_at')::text, ';' ORDER BY s.id)) FROM public.stalls s
                   WHERE s.depot_id = c_depot
                     AND s.id NOT IN (SELECT stall_id FROM _0763_restripe UNION ALL SELECT stall_id FROM _0763_retire)),
       'chargers', (SELECT md5(string_agg((to_jsonb(c) - 'updated_at')::text, ';' ORDER BY c.charger_id))
                      FROM public.ottoq_ocpp_chargers c
                     WHERE c.depot_id = c_depot
                       AND c.charger_id NOT IN (SELECT charger_id FROM _0763_restripe UNION ALL SELECT charger_id FROM _0763_retire)),
       'capabilities', (SELECT md5(string_agg(to_jsonb(k)::text, ';' ORDER BY k.stall_id, k.asset_class_code, k.operation_code))
                          FROM public.ottoq_service_point_capabilities k JOIN public.stalls s ON s.id = k.stall_id
                         WHERE s.depot_id = c_depot
                           AND s.id NOT IN (SELECT stall_id FROM _0763_restripe UNION ALL SELECT stall_id FROM _0763_retire))) THEN
    RAISE EXCEPTION '0763 V1: a space, charger or capability this file does not move moved';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.depots WHERE id = c_depot AND dcfc_max_concurrent_kw = 10500 AND service_max_kw = 12250
                    AND site_layout->'dcfc_count' = '30'::jsonb AND site_layout->'l2_count' = '0'::jsonb)
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_site_structures WHERE depot_id = c_depot AND structure_code = 'CANOPY-03'
                       AND title = 'Solar Canopy C (DCFC)' AND properties->'chargers' = '{"dcfc": 10}'::jsonb
                       AND properties->'stall_capacity' = '10'::jsonb) THEN
    RAISE EXCEPTION '0763 V1: the depot''s power and layout, or canopy C''s structure, are not as declared';
  END IF;
  IF NOT (public.ottoq_check_stall_overlap(c_depot)->>'passed')::boolean
     OR NOT (public.ottoq_check_fence_containment(c_depot)->>'passed')::boolean THEN
    RAISE EXCEPTION '0763 V1: the layout fails a geometry check: % %', public.ottoq_check_stall_overlap(c_depot),
      public.ottoq_check_fence_containment(c_depot);
  END IF;
END $v1$;

-- ── V3: one signed event per moved space, as migration_script 0763, filed to no run ──
DO $v3$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_events e
       WHERE e.entity_type = 'stall' AND e.event_type = 'stall.state_changed'
         AND e.entity_id IN (SELECT stall_id FROM _0763_restripe UNION ALL SELECT stall_id FROM _0763_retire)
         AND e.actor_type = 'migration_script' AND e.actor_id = '0763' AND e.sim_run_id IS NULL) <> 15 THEN
    RAISE EXCEPTION '0763 V3: the stall trigger did not sign exactly one event per moved space as migration_script 0763, to no run';
  END IF;
END $v3$;

-- ── V4: every build-out on the new depot; the old ones as they were ──
DO $v4$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  r record; v_receipt jsonb; v_depot jsonb; v_back jsonb; v_old jsonb;
  v_base jsonb := pg_temp.f_0763_depot('11111111-1111-1111-1111-111111111111');
  v_overlap boolean;
BEGIN
  IF (SELECT count(*) FROM public.ottoq_site_buildouts WHERE depot_id = c_depot) <> 11 THEN
    RAISE EXCEPTION '0763 V4: expected 11 build-outs';
  END IF;
  FOR r IN SELECT b.* FROM public.ottoq_site_buildouts b WHERE b.depot_id = c_depot ORDER BY b.buildout_code LOOP
    BEGIN
      v_receipt := public.ottoq_site_buildout_apply(c_depot, r.buildout_code);
      v_depot := pg_temp.f_0763_depot(c_depot);
      v_overlap := (public.ottoq_check_stall_overlap(c_depot)->>'passed')::boolean;
      PERFORM public.ottoq_site_buildout_restore(c_depot);
      v_back := pg_temp.f_0763_depot(c_depot);
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '0763_V4_ROLLBACK';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> '0763_V4_ROLLBACK' THEN RAISE; END IF;
    END;
    IF v_back IS DISTINCT FROM v_base THEN
      RAISE EXCEPTION '0763 V4: % did not restore the depot as built', r.buildout_code;
    END IF;
    IF NOT v_overlap THEN
      RAISE EXCEPTION '0763 V4: % fails the overlap check', r.buildout_code;
    END IF;
    IF (v_depot->'census'->>'dcfc')::int <> r.dcfc_posts
       OR (v_depot->'power'->>'dcfc_max_concurrent_kw')::numeric <> r.dcfc_max_concurrent_kw
       OR (v_depot->'power'->>'service_max_kw')::numeric <> r.service_max_kw
       OR (v_receipt->>'dcfc_posts')::int <> r.dcfc_posts OR (v_receipt->>'buildable')::boolean IS DISTINCT FROM r.buildable THEN
      RAISE EXCEPTION '0763 V4: % applied reads %', r.buildout_code, v_depot;
    END IF;
    IF r.buildout_code = 'dcfc30' THEN
      -- the depot as built, exactly
      IF v_depot IS DISTINCT FROM v_base THEN
        RAISE EXCEPTION '0763 V4: dcfc30 is not the depot as built';
      END IF;
    ELSIF r.buildout_code = 'dcfc30_cab2400' THEN
      -- the depot as built, on the held site's grid
      IF (v_depot - 'power') IS DISTINCT FROM (v_base - 'power')
         OR v_depot->'power' IS DISTINCT FROM '{"dcfc_max_concurrent_kw": 2400, "service_max_kw": 2500}'::jsonb THEN
        RAISE EXCEPTION '0763 V4: dcfc30_cab2400 is not the depot as built on 2,400/2,500';
      END IF;
    ELSE
      -- an old build-out reproduces, column by column, the depot it built before this file
      SELECT v INTO v_old FROM _0763_read WHERE k = 'old:' || r.buildout_code;
      IF v_old IS NULL OR (v_old - 'receipt') IS DISTINCT FROM v_depot
         OR (v_old->'receipt'->'converted_stall_ids') IS DISTINCT FROM (v_receipt->'converted_stall_ids') THEN
        RAISE EXCEPTION '0763 V4: % does not reproduce the depot it built before this file', r.buildout_code;
      END IF;
    END IF;
  END LOOP;
  -- and the base is what is installed
  IF v_base->'power' IS DISTINCT FROM '{"dcfc_max_concurrent_kw": 10500, "service_max_kw": 12250}'::jsonb THEN
    RAISE EXCEPTION '0763 V4: the depot''s power reads %', v_base->'power';
  END IF;
END $v4$;

-- ── V5: no stored day reads differently ──
DO $v5$
DECLARE r record; v_after jsonb; v_n int := 0;
BEGIN
  FOR r IN SELECT * FROM _0763_days ORDER BY kind LOOP
    v_after := public.ottoq_throughput_scorecard(r.sim_run_id);
    IF v_after IS DISTINCT FROM r.before THEN
      RAISE EXCEPTION '0763 V5: run % (%) scores differently after the base change', r.sim_run_id, r.kind;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE '0763 V5: % stored days, one of each kind, score the same after the base change', v_n;
END $v5$;

-- ── V6: the history, and the type a space had ──
DO $v6$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_site_base_history WHERE change_code = '0763' AND stall_type = 'l2'
         AND valid_until = now()) <> 15
     OR EXISTS (SELECT 1 FROM public.ottoq_site_base_history h WHERE h.change_code = '0763'
                   AND (public.ottoq_stall_type_at(h.stall_id, now() - interval '1 microsecond') IS DISTINCT FROM 'l2'
                        OR public.ottoq_stall_type_at(h.stall_id, now()) IS NOT NULL))
     OR EXISTS (SELECT 1 FROM public.ottoq_site_base_history h0 JOIN public.ottoq_site_base_history h1 USING (stall_id)
                 WHERE h0.change_code = '0759' AND h1.change_code = '0763') THEN
    RAISE EXCEPTION '0763 V6: the base history or ottoq_stall_type_at does not read as declared';
  END IF;
END $v6$;

DROP FUNCTION pg_temp.f_0763_depot(uuid);

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0763_canopy_c_is_restriped_and_the_twin_depot_has_no_standard_chargers', true, true,
        'G481. A base change of the twin depot, Chase''s call of 2026-10-21: canopy C re-striped as canopies A and B, so '
        'NASH-L2-STALL-16..20 and 26..30 become robotic fast chargers NASH-DCFC-STALL-21..30 on the 14-unit pitch (chargers '
        'NASH-DCFC-21..30, ABB Terra HP 350, 350 kW; charge_l2 -> charge_dcfc), NASH-L2-STALL-31..35 are retired (stall_type '
        'parking, no position, no charger, capabilities inactive, chargers decommissioned), and the depot''s limits go to '
        'what is installed, 10,500 kW DC and 12,250 kW service, so no car is refused, slowed or held for power (CLAUDE.md '
        'rule 13): 30 fast chargers and no standard charger. forces_recert TRUE: every canon column runs on this depot. '
        'forces_dial_restart TRUE: every dial pair and sweep arm before it ran on another depot. Every old build-out '
        'reproduces the depot it built (V4); dcfc30 is now the depot as built, dcfc30_cab2400 the held site for after a '
        'ceiling is set. The base history keeps the past, and the latest stored day of each kind scores the same (V5).',
        now());

COMMIT;
