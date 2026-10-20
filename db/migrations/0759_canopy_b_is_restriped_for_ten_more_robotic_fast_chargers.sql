-- migration-version: PENDING
-- migration-name:    canopy_b_is_restriped_for_ten_more_robotic_fast_chargers
--
-- 0759  **Canopy B is re-striped for ten more robotic fast chargers: the twin depot is built with 20 fast chargers and 15
--       standard chargers.** (G477)
--
-- ══ §0 FILE ONLY. NOT APPLIED. APPLYING IT IS CHASE'S CALL ════════════════════════════════════════════════════════════
--
--   This changes the depot that every queued cell, every demo and every canon column reads. It must not be applied while
--   any arm is queued or running against the depot as built: P0 refuses while a research sweep or a dial experiment at
--   the twin depot is active, while a pair, the recert runner, a dial pair or a sweep arm is in flight, while a run is
--   live there, or while a build-out is applied. If Chase decides to apply it: after the night's window closes (the
--   runner's window is 04:00-11:00 UTC, 11:00 PM-6:00 AM CT; with no active sweep or dial experiment it has nothing to
--   run anyway), through the connector, which will ask (this ALTERs a table, UPDATEs stalls, chargers and the depot, and
--   DROPs its own temporary function), and once the renderer draws canopy B as ten fast-charger posts (§2 (g)). Its
--   lineage row moves the recert floor and the dial floor (§6): the canon recertifies on the new depot, and every sweep
--   or dial experiment run afterwards runs on it.
--
-- ══ §1 WHY: THE 20-POST DEPOT 0567 MEASURED CANNOT BE BUILT; THIS ONE CAN ═════════════════════════════════════════════
--
--   0567's dcfc20 converts NASH-L2-STALL-01..10 in place: ten 350 kW posts on the standard rows' pitch, 8.4 render units
--   at a 60-degree heading, 7.27 units square to the car (ottoyarddepot-sim src/lib/sitePlan.ts:274 L2_ROW_PITCH, and its
--   comment at :336). A robotic charger's pedestal stands 5.9 units from the parked car's centreline
--   (src/lib/ottoChargeArm/cobotSpec.ts:186, PEDESTAL_OFFSET_PU = FLANK_STANDOFF_PU 3.9 + half the 4.0-unit car of
--   src/engine/motion/traffic.ts:54), and the next car's near flank is 7.27 - 2.0 = 5.27 units away: at the standard
--   pitch the pedestal stands inside the next car. At the fast chargers' pitch (DCFC_ROW_PITCH 14, sitePlan.ts:272; 12.12
--   units square) the next car's flank is 10.12 units away. So the buildable 20 is canopy A's pattern on canopy B: ten
--   posts on the 14-unit pitch where fifteen standard spaces stood. The site then holds at most 30 posts, three canopies
--   of ten, and 40 do not fit at all. (Read from ottoyarddepot-sim at commit 7a19117.)
--
--   What the five spaces this retires carried (db/checks/0458 (1)-(2), read 2026-10-19 between 9:58 and 10:32 AM CT):
--   on the 39 complete dcfc20 arms at the twin depot (26 distinct days: a cell repeated on its seed replays its day),
--   NASH-L2-STALL-11..15, which dcfc20 left as standard chargers beside canopy C's fifteen, delivered 17.0-26.4% of the
--   standard chargers' energy (arm 109: 300 of 1,766 kWh; arm 86: 495 of 1,913). All twenty standard chargers were in use
--   at once on every arm; more than fifteen were in use for 85-930 minutes of the day (4.92-52.33 car-hours beyond
--   fifteen), from the day's first or second tick (11:05-11:10 sim), and in 5-81 of the five-minute samples the cars
--   beyond fifteen outnumbered the fast chargers idle at that moment. Read off the recorded days, not re-run: on this
--   base the kernel would seat those cars otherwise. So the buildable 20 has five fewer standard chargers than the 20
--   0567 measured, and the cell that measures it is dcfc20 as redefined here (§3).
--
-- ══ §2 WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Canopy B's ten posts. The rows of NASH-L2-STALL-01..10 become NASH-DCFC-STALL-11..20, robotic fast chargers like
--       canopy A's: the twin opens an OTTO-CHARGE ARM cycle (twin.arm_cycles) on every charge at a stall whose stall_type
--       is dcfc (twin.ottoq_sim_start_charge_session); equipment_config.robotic_arm is read by nothing. The positions are
--       what scripts/buildLayoutSeed.mjs writes for canopy A's pattern at canopy B (render x 143 and 157, rows 88, 102,
--       116, 130, 144; toX/toY at 4 decimals): west relative_x 215.0738 at heading 60 (NASH-DCFC-STALL-11..15), east
--       237.0522 at heading 300 (16..20), relative_y 185.2461, 163.2677, 141.2894, 119.3110, 97.3327, canopy A's rows.
--       Latitude is canopy A's post's on the same row; longitude canopy B's column's. display_name CANOPY-02 W-11 ..
--       CANOPY-02 E-20; zone dcfc_zone; connector 350 kW; fiducial FID-D2-nn-A and UWB beacon UWB-D2-nn (canopy A's are
--       FID-D1/UWB-D1); equipment_config {charger_kw 350, canopy_code CANOPY-02, canopy_side W/E}. Width (10.0000 ft),
--       depth (19.0276 ft), connector type, inlets, stall_kind, canopy and cover are what they were. distance_from_entrance,
--       which nine functions order by and nothing maintains, is interpolated along each column through canopy B's
--       standard values by relative_y and rounded to the foot: west 201, 176, 153, 132, 113; east 192, 166, 140, 115, 94.
--   (b) Their chargers: NASH-L2-01..10 become NASH-DCFC-11..20 with canopy A's make, model, rating, firmware, protocol
--       and connectors (ABB Terra HP 350, 350 kW, 1.4.2, OCPP 1.6J, one connector); installed_at the apply; Available,
--       no fault.
--   (c) Their capabilities: charge_l2 becomes charge_dcfc for each of the seven asset classes, as 0567's conversion does.
--   (d) NASH-L2-STALL-11..15 are retired. A row the history references is never deleted (0010's precedent), so each keeps
--       its id and code and becomes a space nothing is offered: stall_type parking (no function chooses a parking space;
--       the one that names it, ottoq.ottoq_record_enacted_booking, maps it to staging for a booking's class), no
--       position, no charger, no zone, stall_kind retired (the two recall functions count stall_kind charging), no canopy,
--       not covered, every capability inactive. A status cannot retire a space: twin.ottoq_sim_seed_fleet sets every depot
--       stall available at each run start. Their chargers NASH-L2-11..15 are decommissioned at the apply; seed_fleet will
--       still mark them Available at each run start, as it marks NASH-L2-21..25, which 0010 left with no stall, and with
--       no stall pointing at them nothing seats a car there.
--   (e) The depot: dcfc_max_concurrent_kw 1,800 -> 3,600 and service_max_kw 2,500 -> 4,363, the grid every measured
--       20-post arm ran on (0567 §3: +180 kW DC and +186.3 kW service for each added post); site_layout dcfc_count 20 and
--       l2_count 15. Twenty posts on today's 2.5 MW service is the cell dcfc20_grid_today, not yet run on this base.
--       Which service the site buys is Chase's (§7).
--   (f) CANOPY-02 reads 'Solar Canopy B (DCFC)', chargers {dcfc: 10}, stall_capacity 10, as CANOPY-01 does. Its panels
--       and solar are unchanged.
--   (g) The renderer draws canopy B from these rows (TwinMotionDriver.setTwinStallMap maps the twin's stalls by type,
--       column and rank and skips a stall with no finite position), so its 20-post layout goes live before or with this.
--   Not changed: canopy A, canopy C's fifteen standard chargers (NASH-L2-STALL-16..20 and 26..35), the 113 staging
--   spaces, the bays, absolute_point (stale for every stall since 0561, read only by twin.ottoq_grid_fixture_create), and
--   every engine function but the three in §3 and §4. No pinned function is touched.
--
-- ══ §3 THE BUILD-OUTS AFTER THIS FILE ════════════════════════════════════════════════════════════════════════════════
--
--   A build-out gains stall_set, spaces it sets before its conversions as the depot had or will have them (the layout,
--   the charger and the capabilities; never a space's state or its car), and buildable, false where its drawing cannot
--   be built. apply checks the set whole, records exactly what it will change, applies it, then converts as 0567 does;
--   restore undoes the conversion, then the set, last entry first, and refuses if any space, charger or capability is
--   not put back. Every old build-out keeps the day it meant:
--     dcfc10               10 posts, 1,800/2,500 kW. Its set puts canopy B back as it stood until this file (15 standard).
--     dcfc15               the same set, then NASH-L2-STALL-01..05 in place; 2,700/3,431.5. buildable false.
--     dcfc20_in_place      new: the same set, then 01..10 in place; 3,600/4,363. This is dcfc20 until this file.
--                          buildable false.
--     dcfc40, dcfc40_cab2400, dcfc40_grid_dcfc20, dcfc40_grid_today
--                          the same set, then all 30 in place, on their grids. buildable false: 40 posts do not fit.
--   and two move to the new depot:
--     dcfc20               the depot as built from this file: no set, no conversion; 3,600/4,363.
--     dcfc20_grid_today    the same posts on 1,800/2,500.
--   and one is new:
--     dcfc30               canopy C as canopy B: NASH-L2-STALL-16..20 and 26..30 become NASH-DCFC-STALL-21..30 at render x
--                          190 and 204 on the same rows, 31..35 retired for the day (their chargers stay commissioned
--                          and unattached); 5,400/6,226 (+10 x 180 DC, +10 x 186.3 service). buildable true: the
--                          site's ceiling.
--   A sweep re-activated after this file runs its dcfc20 cells on the new depot. V4 proves the table: every build-out
--   applied on the new depot and restored leaves it exactly as it was, and each old one reproduces, column by column,
--   the depot it built before this file (read in this file before anything moves).
--
-- ══ §4 A BASE CHANGE MUST NOT REWRITE THE PAST ═══════════════════════════════════════════════════════════════════════
--
--   public.ottoq_throughput_scorecard classifies a day's charge sessions by today's stalls.stall_type (correcting only
--   the converted ids its receipt names), and counts a day's fast chargers from today's stalls when the day has no
--   receipt (195 completed twin runs have none). After this file, re-scoring an old dcfc10 day would count its sessions
--   on NASH-L2-STALL-01..10 as fast charges, drop the retired five's sessions from l2_sessions, and count 20 fast
--   chargers on a day that had 10. So:
--     public.ottoq_site_base_history      one append-only row per space a base change moves: the space, its charger
--                                         and its capabilities before and after, valid_until the change.
--     public.ottoq_stall_type_at(stall, at)  the type a space had at a moment; null when it has not changed since.
--     public.ottoq_throughput_scorecard   (scorecard_version 0759) reads a session's kind as the run's receipt names
--                                         it (stall_types, new in the receipt), else as of the run's start
--                                         (ottoq_sim_runs.started_at, the real clock, the clock valid_until is in),
--                                         else today's; and a receipt-less day's fast chargers as of its start.
--   V5 proves no stored day reads differently: the latest completed day of each kind at the depot (on 2026-10-19 those
--   were dcfc10, dcfc20, dcfc40, dcfc40_cab2400 and no receipt) is scored before anything moves and again after, and each
--   must match key for key but scorecard_version. Not patched, and named in G477: 23 other STABLE functions name stall_type beside a run and
--   a session or booking table; most read a live run's present, where today's type is the right one, but
--   ottoq_charge_order_realized grades a past order by today's types, and ottoq_charger_fit_profile (no caller) reads
--   past sessions the same way. The charge clock is safe: ottoq_charge_duration_ledger records charger_type at capture.
--
-- ══ §5 CHECKS ════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight; no run live at the twin depot; no build-out applied; no active sweep or dial experiment there.
--   P1 the functions this replaces or reads, and the stall triggers, are the bodies read on 2026-10-19 (prosrc md5s
--   below); 0758 is applied; the depot is as read: digests of the 40 charger stalls, the 118 others, the 45 chargers,
--   the charger stalls' 1,400 capabilities and the 8 build-outs, and 1,800/2,500 kW; canopy B's fifteen hold no car, no
--   reservation and no open booking; the new codes, identifiers, build-outs, columns and objects are free; no function
--   names a charger's code, zone, canopy, fiducial or OCPP identifier but the build-out apply, none the parking type but
--   ottoq.ottoq_record_enacted_booking, and none reads stall_kind but the five read. P2 once. Pre-images: the three
--   functions and the rows this changes, under '0759_pre'.
--   V1 the census and the layout as declared; everything else unchanged; ottoq_check_stall_overlap and
--   ottoq_check_fence_containment pass; each canopy B post on canopy A's row, 14 units from its neighbour. V2 the
--   scorecard less its changes is its pre-image. V3 the stall trigger signed one event per moved space, as
--   migration_script 0759, to no run. V4 the build-outs (§3). V5 the stored days (§4). V6 the history and
--   ottoq_stall_type_at. V7 grants. tests/test_twenty_post_base_sql.py runs this file on the scratch PostgreSQL against
--   the live bodies (md5 asserted) and the depot's rows as read on 2026-10-19.
--
-- ══ §6 RECERT AND DIAL CLASSIFICATION ════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert TRUE: every certified canon column runs on the twin depot, and its fingerprints, sessions and decisions
--   read the stalls, chargers and power this changes, so the canon recertifies on the new depot.
--   forces_dial_restart TRUE: every dial pair and sweep arm so far ran on the old depot, and a pair read across this
--   change would compare two depots. Moving the dial floor re-queues every active sweep's cells, which is why P0 asks
--   that none be active.
--
-- ══ §7 WHAT IT NEEDS ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase's decision to make the 20-post depot the twin's base and the grid that goes with it (3,600/4,363 kW here, or
--   today's 1,800/2,500: the two numbers in §2 (e) and dcfc20's row); every active sweep at the twin depot paused or
--   concluded (32 active when read) and every active dial experiment concluded or abandoned (8); the window closed; the
--   connector's approval; the renderer's 20-post layout live first; the canon recertified afterwards.
--
-- ROLLBACK is a base change of its own, filed as its own migration with both flags TRUE, with no run live and nothing
--   in flight, and 0759's lineage row kept (the canon recertified on it). As migration_script, to no run, it puts each
--   space, charger and capability back from the before images in public.ottoq_site_base_history WHERE change_code =
--   '0759', and records that change there as its own (its before images are this file's after images), so a day run on
--   the 20-post depot is still read as it ran; it puts the depot's power limits and site_layout, CANOPY-02's title and
--   properties, and the eight build-out rows back from the '0759_pre' rows snapshots (stall_set '[]' and buildable true
--   on each), and DELETEs dcfc20_in_place and dcfc30 if no cell names them. The scorecard, ottoq_stall_type_at, the
--   history and the two build-out columns stay: with an empty stall set a build-out applies exactly as 0567's did.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing queued, running or applied at the twin depot ──
DO $p0$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_n int;
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0759 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = c_depot AND status IN ('initializing', 'running', 'paused')) THEN
    RAISE EXCEPTION '0759 P0: a run is live at the twin depot; the depot changes only between runs';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_site_buildout_active WHERE depot_id = c_depot) THEN
    RAISE EXCEPTION '0759 P0: a build-out is applied at the twin depot in this transaction';
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_throughput_sweeps WHERE depot_id = c_depot AND status = 'active';
  IF v_n > 0 THEN
    RAISE EXCEPTION '0759 P0: % research sweeps are active at the twin depot. This file changes the depot every queued cell reads, and its dial floor re-queues every active sweep: pause or conclude each first (Chase''s call)', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_dial_experiments WHERE depot_id = c_depot AND status = 'active';
  IF v_n > 0 THEN
    RAISE EXCEPTION '0759 P0: % dial experiments are active at the twin depot. Their pairs ran on the depot this file changes: conclude or abandon each first (Chase''s call)', v_n;
  END IF;
END $p0$;

-- ── P1: the bodies, the depot and the vocabulary, as read on 2026-10-19 ──
DO $p1$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_bad text;
BEGIN
  SELECT string_agg(f.sig, ', ') INTO v_bad
    FROM (VALUES ('public.ottoq_site_buildout_apply(uuid,text)', 'cb079839be8f1193989f2ad088f0ab8b'),
                 ('public.ottoq_site_buildout_restore(uuid)', '2c0df4dcab28c428977be901033a2eda'),
                 ('public.ottoq_throughput_scorecard(uuid)', 'a591253c15105520d4b6d612059bb2fb'),
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
    RAISE EXCEPTION '0759 P1: these are not the bodies this file was written against: %', v_bad;
  END IF;
  IF (SELECT string_agg(tgname::text, ',' ORDER BY tgname) FROM pg_trigger
       WHERE tgrelid = 'public.stalls'::regclass AND NOT tgisinternal)
     IS DISTINCT FROM 'trg_ottoq_stall_seat_is_exclusive,trg_ottoq_stalls_state_change,trg_reassignment_guard,trg_stalls_updated' THEN
    RAISE EXCEPTION '0759 P1: the triggers on public.stalls are not the four read';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0758_a_fast_chargers_cleaning_arm_cleans_the_cabin_while_the_car_charges') THEN
    RAISE EXCEPTION '0759 P1: 0758 is not applied; apply in order';
  END IF;

  -- the depot as read (structural columns; a space's status and a charger's state move every run and are not read)
  IF (SELECT md5(string_agg(concat_ws('|', s.id, s.stall_code, s.stall_type, round(s.relative_x::numeric, 4),
                   round(s.relative_y::numeric, 4), s.heading_degrees, s.zone, COALESCE(s.ocpp_charger_id::text, '-'),
                   COALESCE(round(s.connector_max_kw, 1)::text, '-'), COALESCE(round(s.absolute_lat::numeric, 8)::text, '-'),
                   COALESCE(round(s.absolute_lng::numeric, 8)::text, '-'), COALESCE(s.display_name, '-'),
                   COALESCE(s.distance_from_entrance::text, '-'), COALESCE(s.equipment_config->>'canopy_side', '-'),
                   COALESCE(s.fiducial_marker_id, '-'), COALESCE(s.uwb_beacon_id, '-'), COALESCE(s.canopy_code, '-'),
                   COALESCE(s.stall_kind, '-')), ';' ORDER BY s.stall_code))
        FROM public.stalls s WHERE s.depot_id = c_depot AND s.stall_type IN ('dcfc', 'l2'))
       IS DISTINCT FROM '26a57f16af59039fd2aba53e83e8a8ae'
     OR (SELECT md5(string_agg(concat_ws('|', s.id, s.stall_code, s.stall_type, round(s.relative_x::numeric, 4),
                   round(s.relative_y::numeric, 4), s.heading_degrees, s.zone, s.stall_kind), ';' ORDER BY s.stall_code))
           FROM public.stalls s WHERE s.depot_id = c_depot AND s.stall_type NOT IN ('dcfc', 'l2'))
       IS DISTINCT FROM 'c535463737f7dba1dbbda50b707e0615'
     OR (SELECT md5(string_agg(concat_ws('|', c.charger_id, c.ocpp_identifier, c.vendor, c.model,
                   COALESCE(c.firmware_version, '-'), COALESCE(c.ocpp_protocol_version, '-'),
                   COALESCE(round(c.max_kw, 1)::text, '-'), c.num_connectors, COALESCE(c.installed_at::text, '-'),
                   COALESCE(c.decommissioned_at::text, '-')), ';' ORDER BY c.ocpp_identifier))
           FROM public.ottoq_ocpp_chargers c WHERE c.depot_id = c_depot)
       IS DISTINCT FROM 'a626f9ab4d43d011c08be094113b3927'
     OR (SELECT md5(string_agg(concat_ws('|', k.stall_id, k.asset_class_code, k.pack_id, k.operation_code, k.active, k.source),
                   ';' ORDER BY k.stall_id, k.asset_class_code, k.operation_code))
           FROM public.ottoq_service_point_capabilities k JOIN public.stalls s ON s.id = k.stall_id
          WHERE s.depot_id = c_depot AND s.stall_type IN ('dcfc', 'l2'))
       IS DISTINCT FROM 'f9e774f2c9b9a11b14810c38d908bcf7'
     OR (SELECT md5(string_agg(concat_ws('|', b.buildout_code, b.dcfc_posts, array_to_string(b.convert_l2, ','),
                   round(b.dcfc_max_concurrent_kw, 1), round(b.service_max_kw, 1)), ';' ORDER BY b.buildout_code))
           FROM public.ottoq_site_buildouts b)
       IS DISTINCT FROM '4b96d9863b168138c9f655fd69080a54'
     OR NOT EXISTS (SELECT 1 FROM public.depots WHERE id = c_depot AND dcfc_max_concurrent_kw = 1800 AND service_max_kw = 2500)
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_site_structures WHERE depot_id = c_depot AND structure_code = 'CANOPY-02'
                       AND title = 'Solar Canopy B (L2)' AND properties->'chargers' = '{"l2": 15}'::jsonb
                       AND properties->'stall_capacity' = '15'::jsonb) THEN
    RAISE EXCEPTION '0759 P1: the twin depot is not as read on 2026-10-19 (its charger stalls, other stalls, chargers, capabilities, build-outs, power or canopy B)';
  END IF;
  -- canopy B's fifteen: no car, no reservation, no open booking
  IF EXISTS (SELECT 1 FROM public.stalls s WHERE s.depot_id = c_depot AND s.canopy_code = 'CANOPY-02'
                AND (s.current_vehicle_id IS NOT NULL OR s.reserved_by IS NOT NULL OR s.reserved_for_mission_id IS NOT NULL))
     OR EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id
                 WHERE s.depot_id = c_depot AND s.canopy_code = 'CANOPY-02' AND b.state IN ('held', 'active')) THEN
    RAISE EXCEPTION '0759 P1: a car, a reservation or an open booking is on canopy B';
  END IF;
  -- what this file adds is free
  IF EXISTS (SELECT 1 FROM public.stalls WHERE depot_id = c_depot AND stall_code ~ '^NASH-DCFC-STALL-(1[1-9]|2[0-9]|30)$')
     OR EXISTS (SELECT 1 FROM public.ottoq_ocpp_chargers WHERE ocpp_identifier ~ '^NASH-DCFC-(1[1-9]|2[0-9]|30)$')
     OR EXISTS (SELECT 1 FROM public.ottoq_site_buildouts WHERE buildout_code IN ('dcfc20_in_place', 'dcfc30'))
     OR EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ottoq_site_buildouts'
                   AND column_name IN ('stall_set', 'buildable'))
     OR to_regclass('public.ottoq_site_base_history') IS NOT NULL
     OR to_regprocedure('public.ottoq_stall_type_at(uuid,timestamp with time zone)') IS NOT NULL THEN
    RAISE EXCEPTION '0759 P1: a code, an identifier, a build-out, a column or an object this file adds exists already';
  END IF;
  -- nothing knows a charger space by its name, zone, canopy, fiducial or OCPP identifier but the build-out apply (which
  -- writes dcfc_zone and its own FID-BO/UWB-BO names); comments stripped
  SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY 1) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'ottoq', 'twin') AND p.proname NOT LIKE 'ottoq_fn_backup%'
     AND p.oid <> 'public.ottoq_site_buildout_apply(uuid,text)'::regprocedure
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g')
         ~ '(NASH-L2|NASH-DCFC|DCFC-STALL|L2-STALL|dcfc_zone|l2_zone|CANOPY-0[123]|FID-D|UWB-D)';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0759 P1: these functions name a charger space, zone, canopy, fiducial or identifier, so a moved or retired space could read wrong to them: %', v_bad;
  END IF;
  -- a parking space is chosen by nothing
  SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY 1) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'ottoq', 'twin') AND p.proname NOT LIKE 'ottoq_fn_backup%'
     AND (n.nspname, p.proname) <> ('ottoq', 'ottoq_record_enacted_booking')
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') ~ $re$'parking'$re$;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0759 P1: these functions name the parking type, so a retired space could be offered: %', v_bad;
  END IF;
  -- and stall_kind is read only where 'retired' counts as nothing
  SELECT string_agg(n.nspname || '.' || p.proname, ', ' ORDER BY 1) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'ottoq', 'twin') AND p.proname NOT LIKE 'ottoq_fn_backup%'
     AND p.proname NOT IN ('ottoq_depot_cards', 'ottoq_recall_interval_scheduled_v1', 'ottoq_recall_naive_threshold_v1',
                           'ottoq_shield_and_log', 'workload_harness_metrics')
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') ~ 'stall_kind';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0759 P1: these functions read stall_kind and were not read for a retired space: %', v_bad;
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0759_canopy_b_is_restriped_for_ten_more_robotic_fast_chargers') THEN
    RAISE EXCEPTION '0759 P2: already applied';
  END IF;
END $once$;

-- ── what the checks compare: the depot's layout, hardware, capabilities and power, column by column (equipment_config
--    less a build-out's own name; a space's state, its car and the write times left out) ──
CREATE FUNCTION pg_temp.f_0759_depot(p_depot uuid) RETURNS jsonb LANGUAGE sql STABLE AS $fn$
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

-- ── the plan: canopy B's ten posts (§2 (a), (b)) and its five retired spaces (§2 (d)), as the layout seed writes them ──
CREATE TEMP TABLE _0759_restripe (stall_id uuid PRIMARY KEY, old_code text NOT NULL, new_code text NOT NULL,
  display_name text NOT NULL, x double precision NOT NULL, y double precision NOT NULL, heading smallint NOT NULL,
  lat double precision NOT NULL, lng double precision NOT NULL, dist integer NOT NULL, side text NOT NULL,
  fid text NOT NULL, uwb text NOT NULL, charger_id uuid NOT NULL, old_ocpp text NOT NULL, new_ocpp text NOT NULL)
  ON COMMIT DROP;
INSERT INTO _0759_restripe VALUES
  ('a643de50-a12a-417d-b677-f7f9acf6e303', 'NASH-L2-STALL-01', 'NASH-DCFC-STALL-11', 'CANOPY-02 W-11', 215.0738, 185.2461, 60,
   36.14020892, -86.77206836, 201, 'W', 'FID-D2-11-A', 'UWB-D2-11', 'd301c043-64d2-4a48-9b9b-166497befbfe', 'NASH-L2-01', 'NASH-DCFC-11'),
  ('53b217b7-1d89-429a-9030-6295438ad32c', 'NASH-L2-STALL-02', 'NASH-DCFC-STALL-12', 'CANOPY-02 W-12', 215.0738, 163.2677, 60,
   36.14014854, -86.77206836, 176, 'W', 'FID-D2-12-A', 'UWB-D2-12', 'f523b1b5-54c1-435b-8a64-13082061761a', 'NASH-L2-02', 'NASH-DCFC-12'),
  ('fe18413d-9273-4199-8ae3-b063d633b27d', 'NASH-L2-STALL-03', 'NASH-DCFC-STALL-13', 'CANOPY-02 W-13', 215.0738, 141.2894, 60,
   36.14008816, -86.77206836, 153, 'W', 'FID-D2-13-A', 'UWB-D2-13', 'bf363754-6e2b-4e0b-ba76-0a884e9815a2', 'NASH-L2-03', 'NASH-DCFC-13'),
  ('70fa3080-2092-4d54-bd94-4f874bf3d161', 'NASH-L2-STALL-04', 'NASH-DCFC-STALL-14', 'CANOPY-02 W-14', 215.0738, 119.3110, 60,
   36.14002778, -86.77206836, 132, 'W', 'FID-D2-14-A', 'UWB-D2-14', 'f94ec0c0-f581-4951-bb75-6d22e81bac18', 'NASH-L2-04', 'NASH-DCFC-14'),
  ('ab17cc0e-479d-484b-8ccf-e0aba55b7078', 'NASH-L2-STALL-05', 'NASH-DCFC-STALL-15', 'CANOPY-02 W-15', 215.0738, 97.3327, 60,
   36.13996740, -86.77206836, 113, 'W', 'FID-D2-15-A', 'UWB-D2-15', '0d46cfd0-4c47-43dc-b596-4e82cff27e2e', 'NASH-L2-05', 'NASH-DCFC-15'),
  ('55fe979e-00b1-44e7-bbcf-066f787976cd', 'NASH-L2-STALL-06', 'NASH-DCFC-STALL-16', 'CANOPY-02 E-16', 237.0522, 185.2461, 300,
   36.14020892, -86.77199359, 192, 'E', 'FID-D2-16-A', 'UWB-D2-16', '669cc797-fabd-4edf-a498-84d34c075cd3', 'NASH-L2-06', 'NASH-DCFC-16'),
  ('74f716c7-77dd-475c-bd59-54b9ee2b200e', 'NASH-L2-STALL-07', 'NASH-DCFC-STALL-17', 'CANOPY-02 E-17', 237.0522, 163.2677, 300,
   36.14014854, -86.77199359, 166, 'E', 'FID-D2-17-A', 'UWB-D2-17', '31a902ac-7b83-475f-a207-45822814de93', 'NASH-L2-07', 'NASH-DCFC-17'),
  ('fbb3a3df-d872-41e5-b834-a304186f82f2', 'NASH-L2-STALL-08', 'NASH-DCFC-STALL-18', 'CANOPY-02 E-18', 237.0522, 141.2894, 300,
   36.14008816, -86.77199359, 140, 'E', 'FID-D2-18-A', 'UWB-D2-18', '224e1d48-f919-4400-af8a-a71ddfd0ffd4', 'NASH-L2-08', 'NASH-DCFC-18'),
  ('d5b7d268-e4d5-4141-b3f6-1d00df5e6357', 'NASH-L2-STALL-09', 'NASH-DCFC-STALL-19', 'CANOPY-02 E-19', 237.0522, 119.3110, 300,
   36.14002778, -86.77199359, 115, 'E', 'FID-D2-19-A', 'UWB-D2-19', '63e198f2-3575-482a-ae6a-98f8711129cc', 'NASH-L2-09', 'NASH-DCFC-19'),
  ('7d9cedda-5016-4a47-9c29-b5a53651a9ef', 'NASH-L2-STALL-10', 'NASH-DCFC-STALL-20', 'CANOPY-02 E-20', 237.0522, 97.3327, 300,
   36.13996740, -86.77199359, 94, 'E', 'FID-D2-20-A', 'UWB-D2-20', 'eda6ec6a-621e-4ccb-bc00-df69af992ab2', 'NASH-L2-10', 'NASH-DCFC-20');
CREATE TEMP TABLE _0759_retire (stall_id uuid PRIMARY KEY, code text NOT NULL, charger_id uuid NOT NULL, ocpp text NOT NULL)
  ON COMMIT DROP;
INSERT INTO _0759_retire VALUES
  ('ccac745f-a9ca-47eb-94f4-8a3a1080d79c', 'NASH-L2-STALL-11', 'bc472f1f-9ce1-4a72-a875-b2f6d1d25da2', 'NASH-L2-11'),
  ('ce92a558-430f-4b2e-b248-621c568415ba', 'NASH-L2-STALL-12', '57a451e4-4643-4b97-8d06-931b2343d404', 'NASH-L2-12'),
  ('95fe1b50-7e51-4b47-813f-b87774d53642', 'NASH-L2-STALL-13', '1c93ef7b-1be7-49a9-ad3f-c7a67043903b', 'NASH-L2-13'),
  ('baded1fa-b635-43a1-9745-30f5ea1e3932', 'NASH-L2-STALL-14', '29d483e5-84e5-4578-90c3-474efc3eb605', 'NASH-L2-14'),
  ('f7ac0175-e8b2-4a15-a9aa-c29537ab78da', 'NASH-L2-STALL-15', 'ad150cbb-b526-4b96-b7af-3f73bbfacd1c', 'NASH-L2-15');
-- dcfc30's canopy C, laid out as canopy B (§3)
CREATE TEMP TABLE _0759_c30 (LIKE _0759_restripe) ON COMMIT DROP;
INSERT INTO _0759_c30 VALUES
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
CREATE TEMP TABLE _0759_c30_retire (LIKE _0759_retire) ON COMMIT DROP;
INSERT INTO _0759_c30_retire VALUES
  ('bed6e8cf-4816-4451-b6ee-5294291912cd', 'NASH-L2-STALL-31', 'ef25544a-9d8f-4928-bee0-738aec3c7c1f', 'NASH-L2-31'),
  ('1bcc7405-d157-43ae-ac0c-ccb88791a451', 'NASH-L2-STALL-32', '76fdb945-47f9-4398-ba81-34d2b8fb7d64', 'NASH-L2-32'),
  ('f517a13e-c512-485f-af8b-4e92e9aae972', 'NASH-L2-STALL-33', '3caee32b-a3f3-4c40-b598-be5146fb5eff', 'NASH-L2-33'),
  ('f99a8657-b524-46a5-9080-c37f25c6a33d', 'NASH-L2-STALL-34', 'a273725f-61da-4de5-827b-257d6b95de88', 'NASH-L2-34'),
  ('35c6e6f3-8291-42e6-95a0-a9a4dc7daec1', 'NASH-L2-STALL-35', '443a7c32-7914-4002-955f-c9cb100f6a79', 'NASH-L2-35');

DO $plan$
BEGIN
  -- the plan names the rows read, and canopy A's posts share its rows
  IF (SELECT count(*) FROM _0759_restripe r JOIN public.stalls s ON s.id = r.stall_id
       WHERE s.stall_code = r.old_code AND s.stall_type = 'l2' AND s.canopy_code = 'CANOPY-02' AND s.ocpp_charger_id = r.charger_id) <> 10
     OR (SELECT count(*) FROM _0759_retire r JOIN public.stalls s ON s.id = r.stall_id
          WHERE s.stall_code = r.code AND s.stall_type = 'l2' AND s.canopy_code = 'CANOPY-02' AND s.ocpp_charger_id = r.charger_id) <> 5
     OR (SELECT count(*) FROM _0759_c30 r JOIN public.stalls s ON s.id = r.stall_id
          WHERE s.stall_code = r.old_code AND s.stall_type = 'l2' AND s.canopy_code = 'CANOPY-03' AND s.ocpp_charger_id = r.charger_id) <> 10
     OR (SELECT count(*) FROM _0759_c30_retire r JOIN public.stalls s ON s.id = r.stall_id
          WHERE s.stall_code = r.code AND s.stall_type = 'l2' AND s.canopy_code = 'CANOPY-03' AND s.ocpp_charger_id = r.charger_id) <> 5
     OR (SELECT count(*) FROM _0759_restripe r WHERE EXISTS (
           SELECT 1 FROM public.stalls a WHERE a.depot_id = '11111111-1111-1111-1111-111111111111' AND a.canopy_code = 'CANOPY-01'
              AND a.stall_type = 'dcfc' AND round(a.relative_y::numeric, 4) = round(r.y::numeric, 4)
              AND a.heading_degrees = r.heading AND a.absolute_lat = r.lat)) <> 10
     OR (SELECT count(*) FROM public.ottoq_ocpp_chargers WHERE ocpp_identifier = 'NASH-DCFC-01' AND vendor = 'ABB'
          AND model = 'Terra HP 350' AND max_kw = 350 AND firmware_version = '1.4.2' AND ocpp_protocol_version = '1.6J'
          AND num_connectors = 1) <> 1 THEN
    RAISE EXCEPTION '0759: the plan does not name the depot as read';
  END IF;
END $plan$;

-- ── what V1, V4 and V5 compare against, read before anything moves ──
CREATE TEMP TABLE _0759_read (k text PRIMARY KEY, v jsonb) ON COMMIT DROP;
INSERT INTO _0759_read
SELECT 'depot', pg_temp.f_0759_depot('11111111-1111-1111-1111-111111111111')
UNION ALL
SELECT 'untouched', jsonb_build_object(
  'stalls', (SELECT md5(string_agg((to_jsonb(s) - 'updated_at')::text, ';' ORDER BY s.id)) FROM public.stalls s
              WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
                AND s.id NOT IN (SELECT stall_id FROM _0759_restripe UNION ALL SELECT stall_id FROM _0759_retire)),
  'chargers', (SELECT md5(string_agg((to_jsonb(c) - 'updated_at')::text, ';' ORDER BY c.charger_id)) FROM public.ottoq_ocpp_chargers c
                WHERE c.depot_id = '11111111-1111-1111-1111-111111111111'
                  AND c.charger_id NOT IN (SELECT charger_id FROM _0759_restripe UNION ALL SELECT charger_id FROM _0759_retire)),
  'capabilities', (SELECT md5(string_agg(to_jsonb(k)::text, ';' ORDER BY k.stall_id, k.asset_class_code, k.operation_code))
                     FROM public.ottoq_service_point_capabilities k JOIN public.stalls s ON s.id = k.stall_id
                    WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
                      AND s.id NOT IN (SELECT stall_id FROM _0759_restripe UNION ALL SELECT stall_id FROM _0759_retire)));

-- each build-out as the depot built it until now: applied and restored, its depot read, then rolled back
DO $old$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  r record; v_depot jsonb; v_receipt jsonb; v_back jsonb;
BEGIN
  FOR r IN SELECT buildout_code FROM public.ottoq_site_buildouts WHERE depot_id = c_depot ORDER BY buildout_code LOOP
    BEGIN
      v_receipt := public.ottoq_site_buildout_apply(c_depot, r.buildout_code);
      v_depot := pg_temp.f_0759_depot(c_depot);
      PERFORM public.ottoq_site_buildout_restore(c_depot);
      v_back := pg_temp.f_0759_depot(c_depot);
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '0759_OLD_ROLLBACK';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> '0759_OLD_ROLLBACK' THEN RAISE; END IF;
    END;
    IF v_back IS DISTINCT FROM (SELECT v FROM _0759_read WHERE k = 'depot') THEN
      RAISE EXCEPTION '0759: % did not restore the depot as built before this file', r.buildout_code;
    END IF;
    INSERT INTO _0759_read VALUES ('old:' || r.buildout_code, v_depot || jsonb_build_object('receipt', v_receipt));
  END LOOP;
END $old$;

-- the latest completed day of each kind, scored before anything moves (V5)
CREATE TEMP TABLE _0759_days ON COMMIT DROP AS
SELECT q.sim_run_id, q.kind, public.ottoq_throughput_scorecard(q.sim_run_id) AS before
  FROM (SELECT DISTINCT ON (COALESCE(sr.payload->'site_buildout'->>'buildout_code', '-'))
               sr.sim_run_id, COALESCE(sr.payload->'site_buildout'->>'buildout_code', '-') AS kind
          FROM public.ottoq_sim_runs sr
         WHERE sr.depot_id = '11111111-1111-1111-1111-111111111111' AND sr.status = 'completed'
         ORDER BY COALESCE(sr.payload->'site_buildout'->>'buildout_code', '-'), sr.started_at DESC) q;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0759_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_site_buildout_apply(uuid,text)'::regprocedure,
                 'public.ottoq_site_buildout_restore(uuid)'::regprocedure,
                 'public.ottoq_throughput_scorecard(uuid)'::regprocedure);
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0759_pre', 'rows', 'public', t.object_name, t.def::text, md5(t.def::text)
  FROM (SELECT 'depots' AS object_name,
               (SELECT jsonb_agg(jsonb_build_object('id', d.id, 'dcfc_max_concurrent_kw', d.dcfc_max_concurrent_kw,
                                                    'service_max_kw', d.service_max_kw, 'site_layout', d.site_layout))
                  FROM public.depots d WHERE d.id = '11111111-1111-1111-1111-111111111111') AS def
        UNION ALL
        SELECT 'ottoq_site_structures',
               (SELECT jsonb_agg(to_jsonb(x)) FROM public.ottoq_site_structures x
                 WHERE x.depot_id = '11111111-1111-1111-1111-111111111111' AND x.structure_code = 'CANOPY-02')
        UNION ALL
        SELECT 'ottoq_site_buildouts', (SELECT jsonb_agg(to_jsonb(b) ORDER BY b.buildout_code) FROM public.ottoq_site_buildouts b)) t;

-- ── 1. the base history, and the type a space had at a moment ──
CREATE TABLE public.ottoq_site_base_history (
  change_code  text NOT NULL,
  depot_id     uuid NOT NULL REFERENCES public.depots(id),
  stall_id     uuid NOT NULL REFERENCES public.stalls(id),
  valid_until  timestamptz NOT NULL,
  stall_code   text NOT NULL,
  stall_type   text NOT NULL,
  before       jsonb NOT NULL,
  after        jsonb NOT NULL,
  recorded_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (change_code, stall_id)
);
ALTER TABLE public.ottoq_site_base_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_site_base_history_read ON public.ottoq_site_base_history FOR SELECT TO authenticated, service_role
  USING (true);
CREATE INDEX ottoq_site_base_history_stall ON public.ottoq_site_base_history (stall_id, valid_until);
REVOKE ALL ON public.ottoq_site_base_history FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_site_base_history TO authenticated, service_role;
COMMENT ON TABLE public.ottoq_site_base_history IS
'0759. One row per space a change to a depot''s base moves: the space (stall), its charger and its capabilities before and after the change, and valid_until, the real-clock moment the change took effect (ottoq_sim_runs.started_at is in the same clock). Append-only. public.ottoq_stall_type_at reads it so a run started before a base change is read with the depot it ran on.';

CREATE FUNCTION public.ottoq_site_base_history_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
BEGIN
  RAISE EXCEPTION 'ottoq_site_base_history is append-only: a base change is history, and a run started before it is read with it (0759)'
    USING ERRCODE = 'P0001';
END $fn$;
REVOKE ALL ON FUNCTION public.ottoq_site_base_history_append_only() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER ottoq_site_base_history_no_update BEFORE UPDATE OR DELETE ON public.ottoq_site_base_history
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_site_base_history_append_only();
CREATE TRIGGER ottoq_site_base_history_no_truncate BEFORE TRUNCATE ON public.ottoq_site_base_history
  FOR EACH STATEMENT EXECUTE FUNCTION public.ottoq_site_base_history_append_only();

CREATE FUNCTION public.ottoq_stall_type_at(p_stall uuid, p_at timestamptz)
RETURNS text
LANGUAGE sql STABLE
SET search_path = public, pg_temp
AS $fn$
  -- the type before the first base change after p_at; null when none came after it (today's type is the answer)
  SELECT h.stall_type FROM public.ottoq_site_base_history h
   WHERE h.stall_id = p_stall AND p_at < h.valid_until
   ORDER BY h.valid_until LIMIT 1
$fn$;
REVOKE ALL ON FUNCTION public.ottoq_stall_type_at(uuid, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_stall_type_at(uuid, timestamptz) TO authenticated, service_role;
COMMENT ON FUNCTION public.ottoq_stall_type_at(uuid, timestamptz) IS
'0759. The stall_type a space had at a real-clock moment, from public.ottoq_site_base_history: the type before the first base change after that moment, or null when the space has not changed since (read today''s stalls.stall_type).';

-- ── 2. a build-out's stall set and whether it can be built ──
ALTER TABLE public.ottoq_site_buildouts
  ADD COLUMN stall_set jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(stall_set) = 'array'),
  ADD COLUMN buildable boolean NOT NULL DEFAULT true;
COMMENT ON COLUMN public.ottoq_site_buildouts.stall_set IS
'0759. Spaces this build-out first sets as the depot had (or will have) them, before converting convert_l2: entries {stall_id, stall: {column: value}, charger_id, charger: {column: value}, capabilities: {operation_from, operation_to} and/or {active}}. Only layout and hardware columns; never a space''s state or its car. public.ottoq_site_buildout_apply checks it whole and records what it changes; public.ottoq_site_buildout_restore puts it back.';
COMMENT ON COLUMN public.ottoq_site_buildouts.buildable IS
'0759. False where the drawing cannot be built: a fast charger converted in place on the standard rows'' 8.4-unit pitch puts its pedestal inside the next car (db/migrations/0759 §1). Such a build-out still reproduces the day it measured.';

-- ── 3. apply and restore, with the stall set (§3) ──
CREATE OR REPLACE FUNCTION public.ottoq_site_buildout_apply(p_depot uuid, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  b        public.ottoq_site_buildouts%ROWTYPE;
  v_ids    uuid[];
  v_found  integer;
  v_bad    text;
  v_dcfc   integer;
  v_pre    jsonb;
  -- 0759: a build-out can first set spaces as the depot had (or will have) them: its stall_set. These are the
  -- columns an entry may set, the layout and the hardware, never a space's state or its car.
  c_stall_cols   constant text[] := ARRAY['stall_code', 'stall_type', 'display_name', 'relative_x', 'relative_y',
                                          'heading_degrees', 'absolute_lat', 'absolute_lng', 'distance_from_entrance',
                                          'equipment_config', 'fiducial_marker_id', 'uwb_beacon_id', 'zone',
                                          'connector_type', 'connector_max_kw', 'supported_inlet_types', 'ocpp_charger_id',
                                          'stall_kind', 'canopy_code', 'covered', 'stall_width_ft', 'stall_depth_ft'];
  c_charger_cols constant text[] := ARRAY['ocpp_identifier', 'vendor', 'model', 'serial_number', 'firmware_version',
                                          'ocpp_protocol_version', 'max_kw', 'num_connectors', 'installed_at',
                                          'decommissioned_at'];
  e        jsonb;
  v_set    jsonb := '[]'::jsonb;   -- the set's pre-image, entry by entry
  v_cols   text;
  v_n      integer;
  v_flip   integer;
  v_actor_type text := current_setting('ottoq.actor_type', true);
  v_actor_id   text := current_setting('ottoq.actor_id', true);
BEGIN
  SELECT * INTO b FROM public.ottoq_site_buildouts WHERE buildout_code = p_code;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'site_buildout_apply: no build-out %', p_code USING ERRCODE = 'P0002';
  END IF;
  IF b.depot_id IS DISTINCT FROM p_depot THEN
    RAISE EXCEPTION 'site_buildout_apply: build-out % belongs to depot %, not %', p_code, b.depot_id, p_depot
      USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_site_buildout_active WHERE depot_id = p_depot) THEN
    RAISE EXCEPTION 'site_buildout_apply: build-out % is already applied to depot % in this transaction; restore it first',
      (SELECT buildout_code FROM public.ottoq_site_buildout_active WHERE depot_id = p_depot), p_depot USING ERRCODE = 'P0001';
  END IF;
  -- Only between runs: a run in progress was dealt the depot as it was.
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = p_depot AND status IN ('running', 'paused')) THEN
    RAISE EXCEPTION 'site_buildout_apply: a run is live at depot %; a build-out is applied only before a test day starts', p_depot
      USING ERRCODE = '55006';
  END IF;

  -- 0759: the stall set is checked whole before anything moves.
  FOR e IN SELECT x FROM jsonb_array_elements(b.stall_set) AS x LOOP
    IF NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = (e->>'stall_id')::uuid AND s.depot_id = p_depot) THEN
      RAISE EXCEPTION 'site_buildout_apply: % sets a space % that is not at depot %', p_code, e->>'stall_id', p_depot
        USING ERRCODE = 'P0001';
    END IF;
    SELECT string_agg(k, ', ' ORDER BY k) INTO v_bad
      FROM jsonb_object_keys(COALESCE(e->'stall', '{}'::jsonb)) AS k WHERE k <> ALL (c_stall_cols);
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'site_buildout_apply: % sets space columns a build-out may not set: %', p_code, v_bad USING ERRCODE = 'P0001';
    END IF;
    SELECT string_agg(k, ', ' ORDER BY k) INTO v_bad
      FROM jsonb_object_keys(COALESCE(e->'charger', '{}'::jsonb)) AS k WHERE k <> ALL (c_charger_cols);
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'site_buildout_apply: % sets charger columns a build-out may not set: %', p_code, v_bad USING ERRCODE = 'P0001';
    END IF;
    IF e ? 'charger' AND NOT EXISTS (SELECT 1 FROM public.ottoq_ocpp_chargers c
                                      WHERE c.charger_id = (e->>'charger_id')::uuid AND c.depot_id = p_depot) THEN
      RAISE EXCEPTION 'site_buildout_apply: % sets a charger % that is not at depot %', p_code, e->>'charger_id', p_depot
        USING ERRCODE = 'P0001';
    END IF;
    IF jsonb_typeof(e->'stall'->'ocpp_charger_id') = 'string'
       AND NOT EXISTS (SELECT 1 FROM public.ottoq_ocpp_chargers c
                        WHERE c.charger_id = (e->'stall'->>'ocpp_charger_id')::uuid AND c.depot_id = p_depot) THEN
      RAISE EXCEPTION 'site_buildout_apply: % points a space at a charger % that is not at depot %', p_code,
        e->'stall'->>'ocpp_charger_id', p_depot USING ERRCODE = 'P0001';
    END IF;
    SELECT string_agg(k, ', ' ORDER BY k) INTO v_bad
      FROM jsonb_object_keys(COALESCE(e->'capabilities', '{}'::jsonb)) AS k
     WHERE k <> ALL (ARRAY['operation_from', 'operation_to', 'active']);
    IF v_bad IS NOT NULL OR (e->'capabilities' ? 'operation_from') <> (e->'capabilities' ? 'operation_to') THEN
      RAISE EXCEPTION 'site_buildout_apply: % sets a capability the way a build-out may not: %', p_code, e->'capabilities'
        USING ERRCODE = 'P0001';
    END IF;
  END LOOP;
  IF (SELECT count(*) <> count(DISTINCT x->>'stall_id') FROM jsonb_array_elements(b.stall_set) AS x) THEN
    RAISE EXCEPTION 'site_buildout_apply: % sets a space twice', p_code USING ERRCODE = 'P0001';
  END IF;

  -- 0759: exactly what the set will change, so the restore puts back exactly what it found: each named column of the
  -- space and of the charger as they are now, and every capability row of the space.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'stall_id', s.id,
           'stall', (SELECT COALESCE(jsonb_object_agg(k, to_jsonb(s) -> k), '{}'::jsonb)
                       FROM jsonb_object_keys(COALESCE(t.e->'stall', '{}'::jsonb)) AS k),
           'charger_id', t.e->'charger_id',
           'charger', (SELECT COALESCE(jsonb_object_agg(k, to_jsonb(c) -> k), '{}'::jsonb)
                         FROM jsonb_object_keys(COALESCE(t.e->'charger', '{}'::jsonb)) AS k, public.ottoq_ocpp_chargers c
                        WHERE c.charger_id = (t.e->>'charger_id')::uuid),
           'operation_from', t.e->'capabilities'->'operation_from',
           'operation_to', t.e->'capabilities'->'operation_to',
           'capabilities', COALESCE((SELECT jsonb_agg(jsonb_build_object('asset_class_code', k.asset_class_code,
                                                                         'operation_code', k.operation_code, 'active', k.active)
                                                      ORDER BY k.asset_class_code, k.operation_code)
                                       FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id), '[]'::jsonb))
         ORDER BY t.o), '[]'::jsonb)
    INTO v_set
    FROM jsonb_array_elements(b.stall_set) WITH ORDINALITY AS t(e, o)
    JOIN public.stalls s ON s.id = (t.e->>'stall_id')::uuid;

  INSERT INTO public.ottoq_site_buildout_active (depot_id, buildout_code, pre_image)
  VALUES (p_depot, p_code, jsonb_build_object('stall_set', v_set));

  -- Say who is acting: the stall trigger signs an event for each converted space (0423(C)'s doctrine).
  PERFORM set_config('ottoq.actor_type', 'ottoq_engine', true);
  PERFORM set_config('ottoq.actor_id', 'site_buildout:' || p_code, true);

  -- 0759: the set first, so the conversion below reads the depot as the set leaves it.
  FOR e IN SELECT t.x FROM jsonb_array_elements(b.stall_set) WITH ORDINALITY AS t(x, o) ORDER BY t.o LOOP
    IF COALESCE(e->'stall', '{}'::jsonb) <> '{}'::jsonb THEN
      SELECT string_agg(format('%I = r.%I', k, k), ', ' ORDER BY k) INTO v_cols FROM jsonb_object_keys(e->'stall') AS k;
      EXECUTE format('UPDATE public.stalls s SET %s FROM jsonb_populate_record(NULL::public.stalls, $1) AS r WHERE s.id = $2',
                     v_cols) USING e->'stall', (e->>'stall_id')::uuid;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      IF v_n <> 1 THEN
        RAISE EXCEPTION 'site_buildout_apply: % set % spaces for %', p_code, v_n, e->>'stall_id' USING ERRCODE = 'P0001';
      END IF;
    END IF;
    IF COALESCE(e->'charger', '{}'::jsonb) <> '{}'::jsonb THEN
      SELECT string_agg(format('%I = r.%I', k, k), ', ' ORDER BY k) INTO v_cols FROM jsonb_object_keys(e->'charger') AS k;
      EXECUTE format('UPDATE public.ottoq_ocpp_chargers c SET %s FROM jsonb_populate_record(NULL::public.ottoq_ocpp_chargers, $1) AS r WHERE c.charger_id = $2',
                     v_cols) USING e->'charger', (e->>'charger_id')::uuid;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      IF v_n <> 1 THEN
        RAISE EXCEPTION 'site_buildout_apply: % set % chargers for %', p_code, v_n, e->>'charger_id' USING ERRCODE = 'P0001';
      END IF;
    END IF;
    IF e->'capabilities' ? 'operation_to' THEN
      UPDATE public.ottoq_service_point_capabilities k
         SET operation_code = e->'capabilities'->>'operation_to'
       WHERE k.stall_id = (e->>'stall_id')::uuid AND k.operation_code = e->'capabilities'->>'operation_from';
      GET DIAGNOSTICS v_flip = ROW_COUNT;
      UPDATE public.ottoq_site_buildout_active a
         SET pre_image = jsonb_set(a.pre_image, '{stall_set}',
                                   (SELECT jsonb_agg(CASE WHEN z.x->>'stall_id' = e->>'stall_id'
                                                          THEN z.x || jsonb_build_object('flipped', v_flip) ELSE z.x END
                                                     ORDER BY z.o)
                                      FROM jsonb_array_elements(a.pre_image->'stall_set') WITH ORDINALITY AS z(x, o)))
       WHERE a.depot_id = p_depot;
    END IF;
    IF e->'capabilities' ? 'active' THEN
      UPDATE public.ottoq_service_point_capabilities k
         SET active = (e->'capabilities'->>'active')::boolean
       WHERE k.stall_id = (e->>'stall_id')::uuid;
    END IF;
  END LOOP;

  SELECT array_agg(s.id ORDER BY u.ord), count(*) INTO v_ids, v_found
    FROM unnest(b.convert_l2) WITH ORDINALITY AS u(code, ord)
    JOIN public.stalls s ON s.stall_code = u.code AND s.depot_id = p_depot
                        AND s.stall_type = 'l2' AND s.ocpp_charger_id IS NOT NULL;
  v_ids := COALESCE(v_ids, '{}'::uuid[]);
  IF COALESCE(v_found, 0) <> cardinality(b.convert_l2) THEN
    SELECT string_agg(u.code, ', ') INTO v_bad
      FROM unnest(b.convert_l2) AS u(code)
     WHERE NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.stall_code = u.code AND s.depot_id = p_depot
                          AND s.stall_type = 'l2' AND s.ocpp_charger_id IS NOT NULL);
    RAISE EXCEPTION 'site_buildout_apply: % names spaces that are not L2 chargers at depot %: %', p_code, p_depot, v_bad
      USING ERRCODE = 'P0001';
  END IF;
  SELECT count(*) INTO v_dcfc FROM public.stalls WHERE depot_id = p_depot AND stall_type = 'dcfc';
  IF v_dcfc + cardinality(b.convert_l2) <> b.dcfc_posts THEN
    RAISE EXCEPTION 'site_buildout_apply: % declares % fast chargers, but the depot has % and it converts %', p_code,
      b.dcfc_posts, v_dcfc, cardinality(b.convert_l2) USING ERRCODE = 'P0001';
  END IF;

  -- Exactly the columns this changes, so the restore puts back exactly what it found.
  v_pre := jsonb_build_object(
    'stalls', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                 'id', s.id, 'stall_type', s.stall_type::text, 'connector_max_kw', s.connector_max_kw,
                 'fiducial_marker_id', s.fiducial_marker_id, 'uwb_beacon_id', s.uwb_beacon_id,
                 'equipment_config', s.equipment_config, 'zone', s.zone) ORDER BY s.id)
               FROM public.stalls s WHERE s.id = ANY (v_ids)), '[]'::jsonb),
    'chargers', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                 'charger_id', c.charger_id, 'max_kw', c.max_kw, 'vendor', c.vendor, 'model', c.model) ORDER BY c.charger_id)
               FROM public.ottoq_ocpp_chargers c JOIN public.stalls s ON s.ocpp_charger_id = c.charger_id
              WHERE s.id = ANY (v_ids)), '[]'::jsonb),
    'capabilities', COALESCE((SELECT jsonb_agg(jsonb_build_object('stall_id', k.stall_id, 'asset_class_code', k.asset_class_code)
                                               ORDER BY k.stall_id, k.asset_class_code)
               FROM public.ottoq_service_point_capabilities k
              WHERE k.stall_id = ANY (v_ids) AND k.operation_code = 'charge_l2'), '[]'::jsonb),
    'depot', (SELECT jsonb_build_object('dcfc_max_concurrent_kw', d.dcfc_max_concurrent_kw, 'service_max_kw', d.service_max_kw)
                FROM public.depots d WHERE d.id = p_depot));

  UPDATE public.ottoq_site_buildout_active a SET pre_image = v_pre || jsonb_build_object('stall_set', a.pre_image->'stall_set')
   WHERE a.depot_id = p_depot;

  UPDATE public.stalls s
     SET stall_type         = 'dcfc',
         connector_max_kw   = 350.0,
         fiducial_marker_id = 'FID-BO-' || regexp_replace(s.stall_code, '^[A-Z]+-', '') || '-A',
         uwb_beacon_id      = 'UWB-BO-' || regexp_replace(s.stall_code, '^[A-Z]+-', ''),
         equipment_config   = COALESCE(s.equipment_config, '{}'::jsonb)
                              || jsonb_build_object('charger_kw', 350, 'robotic_arm', true, 'buildout', p_code),
         zone               = 'dcfc_zone'
   WHERE s.id = ANY (v_ids);
  UPDATE public.ottoq_ocpp_chargers c
     SET max_kw = 350, vendor = 'ABB', model = 'Terra HP 350'
    FROM public.stalls s
   WHERE s.ocpp_charger_id = c.charger_id AND s.id = ANY (v_ids);
  UPDATE public.ottoq_service_point_capabilities k
     SET operation_code = 'charge_dcfc'
   WHERE k.stall_id = ANY (v_ids) AND k.operation_code = 'charge_l2';
  UPDATE public.depots d
     SET dcfc_max_concurrent_kw = b.dcfc_max_concurrent_kw, service_max_kw = b.service_max_kw
   WHERE d.id = p_depot;

  PERFORM set_config('ottoq.actor_type', COALESCE(v_actor_type, ''), true);
  PERFORM set_config('ottoq.actor_id', COALESCE(v_actor_id, ''), true);

  RETURN jsonb_build_object(
    'buildout_code', p_code, 'depot_id', p_depot, 'title', b.title,
    'dcfc_posts', b.dcfc_posts,
    'converted', COALESCE((SELECT jsonb_agg(jsonb_build_object('stall_id', s.id, 'stall_code', s.stall_code) ORDER BY u.ord)
                             FROM unnest(v_ids) WITH ORDINALITY AS u(id, ord) JOIN public.stalls s ON s.id = u.id), '[]'::jsonb),
    'converted_stall_ids', to_jsonb(v_ids),
    'dcfc_max_concurrent_kw', b.dcfc_max_concurrent_kw, 'service_max_kw', b.service_max_kw,
    -- 0759: the spaces the set changed as the day had them, and every changed space's type that day, so a re-score
    -- after the restore reads the day's depot, not today's
    'stall_set', COALESCE((SELECT jsonb_agg(jsonb_build_object('stall_id', s.id, 'stall_code', s.stall_code,
                                                               'stall_type', s.stall_type::text) ORDER BY s.stall_code)
                             FROM public.stalls s
                            WHERE s.id IN (SELECT (x->>'stall_id')::uuid FROM jsonb_array_elements(b.stall_set) AS x)),
                          '[]'::jsonb),
    'stall_types', COALESCE((SELECT jsonb_object_agg(s.id::text, s.stall_type::text)
                               FROM public.stalls s
                              WHERE s.id IN (SELECT (x->>'stall_id')::uuid FROM jsonb_array_elements(b.stall_set) AS x)
                                 OR s.id = ANY (v_ids)), '{}'::jsonb),
    'buildable', b.buildable,
    'applied_at', clock_timestamp());
END $function$;

CREATE OR REPLACE FUNCTION public.ottoq_site_buildout_restore(p_depot uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  a public.ottoq_site_buildout_active%ROWTYPE;
  v_stalls int; v_chargers int; v_caps int;
  e jsonb; v_cols text; v_n int; v_set int := 0;
  v_actor_type text := current_setting('ottoq.actor_type', true);
  v_actor_id   text := current_setting('ottoq.actor_id', true);
BEGIN
  SELECT * INTO a FROM public.ottoq_site_buildout_active WHERE depot_id = p_depot FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('restored', false, 'depot_id', p_depot, 'why', 'no build-out is applied');
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = p_depot AND status IN ('running', 'paused')) THEN
    RAISE EXCEPTION 'site_buildout_restore: a run is live at depot %; restore after its teardown', p_depot USING ERRCODE = '55006';
  END IF;

  PERFORM set_config('ottoq.actor_type', 'ottoq_engine', true);
  PERFORM set_config('ottoq.actor_id', 'site_buildout:' || a.buildout_code, true);

  UPDATE public.stalls s
     SET stall_type         = (x->>'stall_type')::public.stall_type,
         connector_max_kw   = (x->>'connector_max_kw')::numeric,
         fiducial_marker_id = x->>'fiducial_marker_id',
         uwb_beacon_id      = x->>'uwb_beacon_id',
         equipment_config   = CASE WHEN jsonb_typeof(x->'equipment_config') = 'null' THEN NULL ELSE x->'equipment_config' END,
         zone               = x->>'zone'
    FROM jsonb_array_elements(COALESCE(a.pre_image->'stalls', '[]'::jsonb)) AS x
   WHERE s.id = (x->>'id')::uuid;
  GET DIAGNOSTICS v_stalls = ROW_COUNT;
  UPDATE public.ottoq_ocpp_chargers c
     SET max_kw = (x->>'max_kw')::numeric, vendor = x->>'vendor', model = x->>'model'
    FROM jsonb_array_elements(COALESCE(a.pre_image->'chargers', '[]'::jsonb)) AS x
   WHERE c.charger_id = (x->>'charger_id')::uuid;
  GET DIAGNOSTICS v_chargers = ROW_COUNT;
  UPDATE public.ottoq_service_point_capabilities k
     SET operation_code = 'charge_l2'
    FROM jsonb_array_elements(COALESCE(a.pre_image->'capabilities', '[]'::jsonb)) AS x
   WHERE k.stall_id = (x->>'stall_id')::uuid AND k.asset_class_code = x->>'asset_class_code'
     AND k.operation_code = 'charge_dcfc';
  GET DIAGNOSTICS v_caps = ROW_COUNT;
  UPDATE public.depots d
     SET dcfc_max_concurrent_kw = (a.pre_image->'depot'->>'dcfc_max_concurrent_kw')::numeric,
         service_max_kw         = (a.pre_image->'depot'->>'service_max_kw')::numeric
   WHERE d.id = p_depot;

  IF v_stalls <> jsonb_array_length(COALESCE(a.pre_image->'stalls', '[]'::jsonb))
     OR v_chargers <> jsonb_array_length(COALESCE(a.pre_image->'chargers', '[]'::jsonb))
     OR v_caps <> jsonb_array_length(COALESCE(a.pre_image->'capabilities', '[]'::jsonb)) THEN
    RAISE EXCEPTION 'site_buildout_restore: % put back % of % spaces, % of % chargers and % of % capabilities; the depot is not as built',
      a.buildout_code, v_stalls, jsonb_array_length(COALESCE(a.pre_image->'stalls', '[]'::jsonb)), v_chargers,
      jsonb_array_length(COALESCE(a.pre_image->'chargers', '[]'::jsonb)), v_caps,
      jsonb_array_length(COALESCE(a.pre_image->'capabilities', '[]'::jsonb))
      USING ERRCODE = 'P0001';
  END IF;

  -- 0759: then the stall set, from its pre-image, last entry first: the capabilities back to their operation and
  -- their active flag, then the charger, then the space.
  FOR e IN SELECT t.x FROM jsonb_array_elements(COALESCE(a.pre_image->'stall_set', '[]'::jsonb)) WITH ORDINALITY AS t(x, o)
            ORDER BY t.o DESC LOOP
    IF e ? 'flipped' THEN
      UPDATE public.ottoq_service_point_capabilities k
         SET operation_code = e->>'operation_from'
       WHERE k.stall_id = (e->>'stall_id')::uuid AND k.operation_code = e->>'operation_to';
      GET DIAGNOSTICS v_n = ROW_COUNT;
      IF v_n <> (e->>'flipped')::int THEN
        RAISE EXCEPTION 'site_buildout_restore: % put back % of % capabilities of space %; the depot is not as built',
          a.buildout_code, v_n, e->>'flipped', e->>'stall_id' USING ERRCODE = 'P0001';
      END IF;
    END IF;
    UPDATE public.ottoq_service_point_capabilities k
       SET active = (x->>'active')::boolean
      FROM jsonb_array_elements(e->'capabilities') AS x
     WHERE k.stall_id = (e->>'stall_id')::uuid AND k.asset_class_code = x->>'asset_class_code'
       AND k.operation_code = x->>'operation_code' AND k.active IS DISTINCT FROM (x->>'active')::boolean;
    IF COALESCE(e->'charger', '{}'::jsonb) <> '{}'::jsonb THEN
      SELECT string_agg(format('%I = r.%I', k, k), ', ' ORDER BY k) INTO v_cols FROM jsonb_object_keys(e->'charger') AS k;
      EXECUTE format('UPDATE public.ottoq_ocpp_chargers c SET %s FROM jsonb_populate_record(NULL::public.ottoq_ocpp_chargers, $1) AS r WHERE c.charger_id = $2',
                     v_cols) USING e->'charger', (e->>'charger_id')::uuid;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      IF v_n <> 1 THEN
        RAISE EXCEPTION 'site_buildout_restore: % put back % chargers for %', a.buildout_code, v_n, e->>'charger_id'
          USING ERRCODE = 'P0001';
      END IF;
    END IF;
    IF COALESCE(e->'stall', '{}'::jsonb) <> '{}'::jsonb THEN
      SELECT string_agg(format('%I = r.%I', k, k), ', ' ORDER BY k) INTO v_cols FROM jsonb_object_keys(e->'stall') AS k;
      EXECUTE format('UPDATE public.stalls s SET %s FROM jsonb_populate_record(NULL::public.stalls, $1) AS r WHERE s.id = $2',
                     v_cols) USING e->'stall', (e->>'stall_id')::uuid;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      IF v_n <> 1 THEN
        RAISE EXCEPTION 'site_buildout_restore: % put back % spaces for %', a.buildout_code, v_n, e->>'stall_id'
          USING ERRCODE = 'P0001';
      END IF;
    END IF;
    IF (SELECT COALESCE(jsonb_agg(jsonb_build_object('asset_class_code', k.asset_class_code, 'operation_code', k.operation_code,
                                                     'active', k.active) ORDER BY k.asset_class_code, k.operation_code), '[]'::jsonb)
          FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = (e->>'stall_id')::uuid)
       IS DISTINCT FROM e->'capabilities' THEN
      RAISE EXCEPTION 'site_buildout_restore: % did not put back the capabilities of space %; the depot is not as built',
        a.buildout_code, e->>'stall_id' USING ERRCODE = 'P0001';
    END IF;
    v_set := v_set + 1;
  END LOOP;

  DELETE FROM public.ottoq_site_buildout_active WHERE depot_id = p_depot;
  PERFORM set_config('ottoq.actor_type', COALESCE(v_actor_type, ''), true);
  PERFORM set_config('ottoq.actor_id', COALESCE(v_actor_id, ''), true);

  RETURN jsonb_build_object('restored', true, 'buildout_code', a.buildout_code, 'depot_id', p_depot,
                            'spaces', v_stalls, 'chargers', v_chargers, 'capabilities', v_caps, 'stall_set', v_set);
END $function$;

-- ── 4. the scorecard reads a run's spaces as they were when it ran (§4) ──
CREATE TEMP TABLE _0759_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0759_patch VALUES
  ('public.ottoq_throughput_scorecard(uuid)', 1,
   $s1o$  v_conv   uuid[];
$s1o$,
   $s1n$  v_conv   uuid[];
  v_started timestamptz;   -- 0759: when the run started (the real clock ottoq_site_base_history.valid_until is in)
$s1n$),
  ('public.ottoq_throughput_scorecard(uuid)', 2,
   $s2o$  SELECT sr.payload->'site_buildout' INTO v_bo FROM public.ottoq_sim_runs sr WHERE sr.sim_run_id = p_run;$s2o$,
   $s2n$  SELECT sr.payload->'site_buildout', sr.started_at INTO v_bo, v_started FROM public.ottoq_sim_runs sr WHERE sr.sim_run_id = p_run;$s2n$),
  ('public.ottoq_throughput_scorecard(uuid)', 3,
   $s3o$    SELECT CASE WHEN x.stall_id = ANY (v_conv) THEN 'dcfc' ELSE st.stall_type::text END AS stall_type,$s3o$,
   $s3n$    -- 0759: a space's kind as the day had it: the receipt's, else as of the run's start, else today's
    SELECT CASE WHEN x.stall_id = ANY (v_conv) THEN 'dcfc'
                ELSE COALESCE(v_bo->'stall_types'->>(x.stall_id::text),
                              public.ottoq_stall_type_at(x.stall_id, v_started), st.stall_type::text) END AS stall_type,$s3n$),
  ('public.ottoq_throughput_scorecard(uuid)', 4,
   $s4o$(SELECT count(*) FROM public.stalls st, r WHERE st.depot_id = r.depot_id AND st.stall_type = 'dcfc'))$s4o$,
   $s4n$(SELECT count(*) FROM public.stalls st, r WHERE st.depot_id = r.depot_id
                       AND COALESCE(public.ottoq_stall_type_at(st.id, v_started), st.stall_type::text) = 'dcfc'))$s4n$),
  ('public.ottoq_throughput_scorecard(uuid)', 5,
   $s5o$'scorecard_version', '0567',$s5o$,
   $s5n$'scorecard_version', '0759',$s5n$);

DO $patch$
DECLARE f text; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0759_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(f::regprocedure);
    FOR p IN SELECT * FROM _0759_patch WHERE fn = f ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0759: anchor % of % matches % times, not 1', p.seq, f, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(f::regprocedure) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0759: % is not stored as patched', f;
    END IF;
  END LOOP;
END $patch$;

-- ── 5. the base change: canopy B re-striped (§2) ──
-- Who is acting, and filed to no run (0421's doctrine): the stall trigger signs one event per moved space.
SELECT set_config('ottoq.actor_type', 'migration_script', true), set_config('ottoq.actor_id', '0759', true),
       set_config('ottoq.sim_run_id', 'none', true);

CREATE TEMP TABLE _0759_before ON COMMIT DROP AS
SELECT s.id AS stall_id, s.stall_code, s.stall_type::text AS stall_type,
       jsonb_build_object('stall', to_jsonb(s), 'charger_id', s.ocpp_charger_id, 'charger', to_jsonb(c),
                          'capabilities', COALESCE((SELECT jsonb_agg(jsonb_build_object('asset_class_code', k.asset_class_code,
                                                                                        'operation_code', k.operation_code,
                                                                                        'active', k.active)
                                                                     ORDER BY k.asset_class_code, k.operation_code)
                                                      FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id),
                                                   '[]'::jsonb)) AS image
  FROM public.stalls s LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
 WHERE s.id IN (SELECT stall_id FROM _0759_restripe UNION ALL SELECT stall_id FROM _0759_retire);

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
       equipment_config       = jsonb_build_object('charger_kw', 350, 'canopy_code', 'CANOPY-02', 'canopy_side', r.side),
       fiducial_marker_id     = r.fid,
       uwb_beacon_id          = r.uwb,
       zone                   = 'dcfc_zone',
       connector_max_kw       = 350.0
  FROM _0759_restripe r
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
  FROM _0759_restripe r, public.ottoq_ocpp_chargers a
 WHERE c.charger_id = r.charger_id AND a.ocpp_identifier = 'NASH-DCFC-01';
UPDATE public.ottoq_service_point_capabilities k
   SET operation_code = 'charge_dcfc'
 WHERE k.stall_id IN (SELECT stall_id FROM _0759_restripe) AND k.operation_code = 'charge_l2';

-- (d) the five retired spaces and their chargers
UPDATE public.stalls s
   SET stall_type            = 'parking',
       display_name          = 'Retired by 0759 (was ' || s.display_name || ')',
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
       equipment_config      = jsonb_build_object('retired_by', '0759', 'was', s.stall_code)
  FROM _0759_retire r
 WHERE s.id = r.stall_id;
UPDATE public.ottoq_ocpp_chargers c
   SET decommissioned_at = now(), station_state = 'Unavailable', station_state_changed_at = now(), updated_at = now()
  FROM _0759_retire r
 WHERE c.charger_id = r.charger_id;
UPDATE public.ottoq_service_point_capabilities k
   SET active = false
 WHERE k.stall_id IN (SELECT stall_id FROM _0759_retire);

-- (e) the depot, (f) canopy B
UPDATE public.depots
   SET dcfc_max_concurrent_kw = 3600, service_max_kw = 4363,
       site_layout = COALESCE(site_layout, '{}'::jsonb) || jsonb_build_object('dcfc_count', 20, 'l2_count', 15)
 WHERE id = '11111111-1111-1111-1111-111111111111';
UPDATE public.ottoq_site_structures
   SET title = 'Solar Canopy B (DCFC)',
       properties = properties || jsonb_build_object('chargers', jsonb_build_object('dcfc', 10), 'stall_capacity', 10)
 WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND structure_code = 'CANOPY-02';

SELECT set_config('ottoq.actor_type', '', true), set_config('ottoq.actor_id', '', true);

-- the history: each moved space, before and after
INSERT INTO public.ottoq_site_base_history (change_code, depot_id, stall_id, valid_until, stall_code, stall_type, before, after)
SELECT '0759', '11111111-1111-1111-1111-111111111111', b.stall_id, now(), b.stall_code, b.stall_type, b.image,
       jsonb_build_object('stall', to_jsonb(s), 'charger_id', b.image->'charger_id',
                          'charger', (SELECT to_jsonb(c) FROM public.ottoq_ocpp_chargers c
                                       WHERE c.charger_id = (b.image->>'charger_id')::uuid),
                          'capabilities', COALESCE((SELECT jsonb_agg(jsonb_build_object('asset_class_code', k.asset_class_code,
                                                                                        'operation_code', k.operation_code,
                                                                                        'active', k.active)
                                                                     ORDER BY k.asset_class_code, k.operation_code)
                                                      FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id),
                                                   '[]'::jsonb))
  FROM _0759_before b JOIN public.stalls s ON s.id = b.stall_id;

-- ── 6. the build-outs (§3) ──
CREATE TEMP TABLE _0759_sets (code text PRIMARY KEY, stall_set jsonb NOT NULL) ON COMMIT DROP;
-- canopy B as it stood until this file: the history's before images, the columns that moved
INSERT INTO _0759_sets
SELECT 'revert', jsonb_agg(z.e ORDER BY z.code)
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
                 'capabilities', CASE WHEN h.stall_id IN (SELECT stall_id FROM _0759_restripe)
                                      THEN jsonb_build_object('operation_from', 'charge_dcfc', 'operation_to', 'charge_l2')
                                      ELSE jsonb_build_object('active', true) END) AS e
          FROM public.ottoq_site_base_history h
         WHERE h.change_code = '0759') z;
-- canopy C laid out as canopy B, for the day (dcfc30)
INSERT INTO _0759_sets
SELECT 'dcfc30', jsonb_agg(z.e ORDER BY z.ord)
  FROM (SELECT r.new_code AS ord,
               jsonb_build_object('stall_id', r.stall_id,
                 'stall', jsonb_build_object('stall_code', r.new_code, 'stall_type', 'dcfc', 'display_name', r.display_name,
                            'relative_x', r.x, 'relative_y', r.y, 'heading_degrees', r.heading, 'absolute_lat', r.lat,
                            'absolute_lng', r.lng, 'distance_from_entrance', r.dist,
                            'equipment_config', jsonb_build_object('charger_kw', 350, 'canopy_code', 'CANOPY-03',
                                                                   'canopy_side', r.side),
                            'fiducial_marker_id', r.fid, 'uwb_beacon_id', r.uwb, 'zone', 'dcfc_zone',
                            'connector_max_kw', 350.0),
                 'charger_id', r.charger_id,
                 'charger', jsonb_build_object('ocpp_identifier', r.new_ocpp, 'vendor', 'ABB', 'model', 'Terra HP 350',
                                               'firmware_version', '1.4.2', 'max_kw', 350),
                 'capabilities', jsonb_build_object('operation_from', 'charge_l2', 'operation_to', 'charge_dcfc')) AS e
          FROM _0759_c30 r
        UNION ALL
        SELECT r.code,
               jsonb_build_object('stall_id', r.stall_id,
                 'stall', jsonb_build_object('stall_type', 'parking',
                            'display_name', 'Retired in dcfc30 (was ' || s.display_name || ')',
                            'relative_x', NULL, 'relative_y', NULL, 'absolute_lat', NULL, 'absolute_lng', NULL,
                            'zone', NULL, 'stall_kind', 'retired', 'ocpp_charger_id', NULL, 'connector_type', NULL,
                            'connector_max_kw', NULL, 'supported_inlet_types', '[]'::jsonb, 'canopy_code', NULL,
                            'covered', false, 'equipment_config', jsonb_build_object('retired_by', 'dcfc30', 'was', r.code)),
                 'capabilities', jsonb_build_object('active', false)) AS e
          FROM _0759_c30_retire r JOIN public.stalls s ON s.id = r.stall_id) z;

UPDATE public.ottoq_site_buildouts b
   SET stall_set = (SELECT stall_set FROM _0759_sets WHERE code = 'revert'),
       buildable = (b.buildout_code = 'dcfc10'),
       title     = CASE b.buildout_code
                     WHEN 'dcfc10' THEN '10 robotic fast chargers: the twin depot as built until 0759 (canopy B''s 15 standard chargers)'
                     ELSE b.title END,
       basis     = b.basis || jsonb_build_object('0759', CASE b.buildout_code
                     WHEN 'dcfc10' THEN 'Since 0759 the depot is built with 20 fast chargers; this build-out''s stall_set puts canopy B back as it stood until 0759 (NASH-L2-STALL-01..15), so it reads the depot it always read.'
                     ELSE 'Since 0759 this build-out''s stall_set first puts canopy B back as it stood until 0759, then converts in place as before, so it reproduces the day it measured. buildable false: a fast charger converted in place on the standard rows'' 8.4-unit pitch puts its pedestal inside the next car (0759 section 1).' END)
 WHERE b.buildout_code IN ('dcfc10', 'dcfc15', 'dcfc40', 'dcfc40_cab2400', 'dcfc40_grid_dcfc20', 'dcfc40_grid_today');

INSERT INTO public.ottoq_site_buildouts
  (buildout_code, depot_id, title, dcfc_posts, convert_l2, dcfc_max_concurrent_kw, service_max_kw, basis, stall_set, buildable)
SELECT 'dcfc20_in_place', b.depot_id,
       '20 robotic fast chargers in place: canopy B''s west row and two east spaces converted on the standard pitch (dcfc20 until 0759)',
       b.dcfc_posts, b.convert_l2, b.dcfc_max_concurrent_kw, b.service_max_kw,
       b.basis || jsonb_build_object('0759', 'dcfc20 until 0759, kept so its days can be reproduced: canopy B put back as it stood until 0759, then NASH-L2-STALL-01..10 converted in place. buildable false: on the standard rows'' 8.4-unit pitch a fast charger''s pedestal stands inside the next car (0759 section 1).'),
       (SELECT stall_set FROM _0759_sets WHERE code = 'revert'), false
  FROM public.ottoq_site_buildouts b WHERE b.buildout_code = 'dcfc20';

UPDATE public.ottoq_site_buildouts b
   SET stall_set  = '[]'::jsonb,
       convert_l2 = '{}'::text[],
       buildable  = true,
       title      = CASE b.buildout_code
                      WHEN 'dcfc20' THEN '20 robotic fast chargers: the twin depot as built from 0759 (canopy B re-striped as canopy A)'
                      ELSE '20 robotic fast chargers on today''s grid: the twin depot as built from 0759, on 1,800 kW DC and 2,500 kW service' END,
       basis      = b.basis || jsonb_build_object('0759', CASE b.buildout_code
                      WHEN 'dcfc20' THEN 'From 0759 the depot itself: canopy B re-striped to canopy A''s pattern, 10 posts on the 14-unit pitch where 15 standard spaces stood, 15 standard chargers left on canopy C. Until 0759 this code named the in-place conversion now called dcfc20_in_place, which kept 20 standard chargers.'
                      ELSE 'From 0759 the depot''s 20 posts with the power limits of the depot before 0759. Until 0759 this code named the in-place conversion on that grid.' END)
 WHERE b.buildout_code IN ('dcfc20', 'dcfc20_grid_today');

INSERT INTO public.ottoq_site_buildouts
  (buildout_code, depot_id, title, dcfc_posts, convert_l2, dcfc_max_concurrent_kw, service_max_kw, basis, stall_set, buildable)
SELECT 'dcfc30', b.depot_id,
       '30 robotic fast chargers: canopy C re-striped as canopy B, the site''s ceiling', 30, '{}'::text[], 5400, 6226,
       (b.basis - 'note' - '0759') || jsonb_build_object(
         'note', '3,600 + 10 x 180 kW DC; 4,363 + 10 x 186.3 kW service',
         '0759', 'Canopy C as canopy B: NASH-L2-STALL-16..20 and 26..30 become NASH-DCFC-STALL-21..30 at render x 190 and 204 on canopy A''s rows, 31..35 retired for the day (their chargers stay commissioned, attached to no space). No standard chargers remain. The most this site holds: three canopies of ten.'),
       (SELECT stall_set FROM _0759_sets WHERE code = 'dcfc30'), true
  FROM public.ottoq_site_buildouts b WHERE b.buildout_code = 'dcfc20';

-- ── V1: the depot as declared, and everything else as it was ──
DO $v1$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  c_unit  constant numeric := 0.4785 / 0.3048;
  v_bad text;
BEGIN
  IF (SELECT v->'census' FROM _0759_read WHERE k = 'depot')
       IS DISTINCT FROM '{"dcfc": 10, "l2": 30, "staging": 113, "wash_bay": 3, "service_bay": 2}'::jsonb
     OR pg_temp.f_0759_depot(c_depot)->'census'
       IS DISTINCT FROM '{"dcfc": 20, "l2": 15, "parking": 5, "staging": 113, "wash_bay": 3, "service_bay": 2}'::jsonb THEN
    RAISE EXCEPTION '0759 V1: the census reads % before and % after', (SELECT v->'census' FROM _0759_read WHERE k = 'depot'),
      pg_temp.f_0759_depot(c_depot)->'census';
  END IF;
  SELECT string_agg(r.new_code, ', ' ORDER BY r.new_code) INTO v_bad
    FROM _0759_restripe r JOIN public.stalls s ON s.id = r.stall_id
    LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE NOT (s.stall_code = r.new_code AND s.stall_type = 'dcfc' AND s.display_name = r.display_name
              AND s.relative_x = r.x AND s.relative_y = r.y AND s.heading_degrees = r.heading
              AND s.absolute_lat = r.lat AND s.absolute_lng = r.lng AND s.distance_from_entrance = r.dist
              AND s.zone = 'dcfc_zone' AND s.connector_max_kw = 350 AND s.connector_type = 'Multi'
              AND s.fiducial_marker_id = r.fid AND s.uwb_beacon_id = r.uwb AND s.stall_kind = 'charging'
              AND s.canopy_code = 'CANOPY-02' AND s.covered AND s.stall_width_ft = 10 AND s.stall_depth_ft = 19.0276
              AND s.equipment_config = jsonb_build_object('charger_kw', 350, 'canopy_code', 'CANOPY-02', 'canopy_side', r.side)
              AND s.ocpp_charger_id = r.charger_id AND c.ocpp_identifier = r.new_ocpp AND c.vendor = 'ABB'
              AND c.model = 'Terra HP 350' AND c.max_kw = 350 AND c.firmware_version = '1.4.2'
              AND c.decommissioned_at IS NULL AND c.installed_at = now()
              AND (SELECT count(*) FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id AND k.active) = 35
              AND (SELECT count(*) FROM public.ottoq_service_point_capabilities k
                    WHERE k.stall_id = s.id AND k.operation_code = 'charge_dcfc') = 7
              AND NOT EXISTS (SELECT 1 FROM public.ottoq_service_point_capabilities k
                               WHERE k.stall_id = s.id AND k.operation_code = 'charge_l2'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0759 V1: these posts are not as declared: %', v_bad;
  END IF;
  -- each post on canopy A's row, 14 units from its neighbour in its column
  IF EXISTS (SELECT 1 FROM _0759_restripe r WHERE NOT EXISTS (
               SELECT 1 FROM public.stalls a WHERE a.depot_id = c_depot AND a.canopy_code = 'CANOPY-01'
                  AND round(a.relative_y::numeric, 4) = round(r.y::numeric, 4) AND a.heading_degrees = r.heading))
     OR EXISTS (SELECT 1 FROM (SELECT r.side, r.y - lag(r.y) OVER (PARTITION BY r.side ORDER BY r.y) AS gap
                                 FROM _0759_restripe r) z
                 WHERE z.gap IS NOT NULL AND abs(z.gap::numeric - 14 * c_unit) > 0.001) THEN
    RAISE EXCEPTION '0759 V1: a canopy B post is not on canopy A''s rows at the 14-unit pitch';
  END IF;
  SELECT string_agg(r.code, ', ' ORDER BY r.code) INTO v_bad
    FROM _0759_retire r JOIN public.stalls s ON s.id = r.stall_id JOIN public.ottoq_ocpp_chargers c ON c.charger_id = r.charger_id
   WHERE NOT (s.stall_code = r.code AND s.stall_type = 'parking' AND s.relative_x IS NULL AND s.relative_y IS NULL
              AND s.ocpp_charger_id IS NULL AND s.zone IS NULL AND s.stall_kind = 'retired' AND s.canopy_code IS NULL
              AND NOT s.covered AND c.decommissioned_at = now() AND c.ocpp_identifier = r.ocpp
              AND NOT EXISTS (SELECT 1 FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id AND k.active)
              AND (SELECT count(*) FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id) = 35
              AND NOT EXISTS (SELECT 1 FROM public.stalls o WHERE o.ocpp_charger_id = r.charger_id));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0759 V1: these spaces are not retired as declared: %', v_bad;
  END IF;
  IF (SELECT v FROM _0759_read WHERE k = 'untouched') IS DISTINCT FROM jsonb_build_object(
       'stalls', (SELECT md5(string_agg((to_jsonb(s) - 'updated_at')::text, ';' ORDER BY s.id)) FROM public.stalls s
                   WHERE s.depot_id = c_depot
                     AND s.id NOT IN (SELECT stall_id FROM _0759_restripe UNION ALL SELECT stall_id FROM _0759_retire)),
       'chargers', (SELECT md5(string_agg((to_jsonb(c) - 'updated_at')::text, ';' ORDER BY c.charger_id))
                      FROM public.ottoq_ocpp_chargers c
                     WHERE c.depot_id = c_depot
                       AND c.charger_id NOT IN (SELECT charger_id FROM _0759_restripe UNION ALL SELECT charger_id FROM _0759_retire)),
       'capabilities', (SELECT md5(string_agg(to_jsonb(k)::text, ';' ORDER BY k.stall_id, k.asset_class_code, k.operation_code))
                          FROM public.ottoq_service_point_capabilities k JOIN public.stalls s ON s.id = k.stall_id
                         WHERE s.depot_id = c_depot
                           AND s.id NOT IN (SELECT stall_id FROM _0759_restripe UNION ALL SELECT stall_id FROM _0759_retire))) THEN
    RAISE EXCEPTION '0759 V1: a space, charger or capability this file does not move moved';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.depots WHERE id = c_depot AND dcfc_max_concurrent_kw = 3600 AND service_max_kw = 4363
                    AND site_layout->'dcfc_count' = '20'::jsonb AND site_layout->'l2_count' = '15'::jsonb)
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_site_structures WHERE depot_id = c_depot AND structure_code = 'CANOPY-02'
                       AND title = 'Solar Canopy B (DCFC)' AND properties->'chargers' = '{"dcfc": 10}'::jsonb
                       AND properties->'stall_capacity' = '10'::jsonb AND properties->'solar_kw_dc' = '180'::jsonb) THEN
    RAISE EXCEPTION '0759 V1: the depot''s power and layout, or canopy B''s structure, are not as declared';
  END IF;
  IF NOT (public.ottoq_check_stall_overlap(c_depot)->>'passed')::boolean
     OR NOT (public.ottoq_check_fence_containment(c_depot)->>'passed')::boolean THEN
    RAISE EXCEPTION '0759 V1: the layout fails a geometry check: % %', public.ottoq_check_stall_overlap(c_depot),
      public.ottoq_check_fence_containment(c_depot);
  END IF;
END $v1$;

-- ── V2: the scorecard less its changes is its pre-image ──
DO $v2$
DECLARE p record; v_body text;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc WHERE oid = 'public.ottoq_throughput_scorecard(uuid)'::regprocedure;
  FOR p IN SELECT * FROM _0759_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'a591253c15105520d4b6d612059bb2fb' THEN
    RAISE EXCEPTION '0759 V2: the scorecard less its changes is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v2$;

-- ── V3: one signed event per moved space, as migration_script 0759, filed to no run ──
DO $v3$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_events e
       WHERE e.entity_type = 'stall' AND e.event_type = 'stall.state_changed'
         AND e.entity_id IN (SELECT stall_id FROM _0759_restripe UNION ALL SELECT stall_id FROM _0759_retire)
         AND e.actor_type = 'migration_script' AND e.actor_id = '0759' AND e.sim_run_id IS NULL) <> 15 THEN
    RAISE EXCEPTION '0759 V3: the stall trigger did not sign exactly one event per moved space as migration_script 0759, to no run';
  END IF;
END $v3$;

-- ── V4: every build-out on the new depot; the old ones as they were ──
DO $v4$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  r record; v_receipt jsonb; v_depot jsonb; v_back jsonb; v_old jsonb;
  v_base jsonb := pg_temp.f_0759_depot('11111111-1111-1111-1111-111111111111');
  v_l2 int;
  v_l2_expected int;
  v_overlap boolean;
BEGIN
  IF (SELECT count(*) FROM public.ottoq_site_buildouts WHERE depot_id = c_depot) <> 10 THEN
    RAISE EXCEPTION '0759 V4: expected 10 build-outs';
  END IF;
  FOR r IN SELECT b.* FROM public.ottoq_site_buildouts b WHERE b.depot_id = c_depot ORDER BY b.buildout_code LOOP
    BEGIN
      v_receipt := public.ottoq_site_buildout_apply(c_depot, r.buildout_code);
      v_depot := pg_temp.f_0759_depot(c_depot);
      v_overlap := (public.ottoq_check_stall_overlap(c_depot)->>'passed')::boolean;
      PERFORM public.ottoq_site_buildout_restore(c_depot);
      v_back := pg_temp.f_0759_depot(c_depot);
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '0759_V4_ROLLBACK';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> '0759_V4_ROLLBACK' THEN RAISE; END IF;
    END;
    IF v_back IS DISTINCT FROM v_base THEN
      RAISE EXCEPTION '0759 V4: % did not restore the depot as built', r.buildout_code;
    END IF;
    IF NOT v_overlap THEN
      RAISE EXCEPTION '0759 V4: % fails the overlap check', r.buildout_code;
    END IF;
    v_l2 := COALESCE((v_depot->'census'->>'l2')::int, 0);
    -- standard chargers left: 30 on the old depot less the conversions; 15 on the new; none at 30 or 40 posts
    v_l2_expected := CASE r.buildout_code WHEN 'dcfc10' THEN 30 WHEN 'dcfc15' THEN 25 WHEN 'dcfc20_in_place' THEN 20
                                          WHEN 'dcfc20' THEN 15 WHEN 'dcfc20_grid_today' THEN 15 ELSE 0 END;
    IF (v_depot->'census'->>'dcfc')::int <> r.dcfc_posts
       OR (v_depot->'power'->>'dcfc_max_concurrent_kw')::numeric <> r.dcfc_max_concurrent_kw
       OR (v_depot->'power'->>'service_max_kw')::numeric <> r.service_max_kw
       OR (v_receipt->>'dcfc_posts')::int <> r.dcfc_posts OR (v_receipt->>'buildable')::boolean IS DISTINCT FROM r.buildable
       OR v_l2 <> v_l2_expected THEN
      RAISE EXCEPTION '0759 V4: % applied reads %', r.buildout_code, v_depot;
    END IF;
    -- an old build-out reproduces the depot it built before this file; dcfc20's old meaning lives on as dcfc20_in_place
    SELECT v INTO v_old FROM _0759_read WHERE k = 'old:' || CASE r.buildout_code WHEN 'dcfc20_in_place' THEN 'dcfc20'
                                                                                ELSE r.buildout_code END;
    IF r.buildout_code NOT IN ('dcfc20', 'dcfc20_grid_today', 'dcfc30') THEN
      IF v_old IS NULL OR (v_old - 'receipt') IS DISTINCT FROM v_depot
         OR (v_old->'receipt'->'converted_stall_ids') IS DISTINCT FROM (v_receipt->'converted_stall_ids') THEN
        RAISE EXCEPTION '0759 V4: % does not reproduce the depot it built before this file', r.buildout_code;
      END IF;
    ELSIF r.buildout_code = 'dcfc20' THEN
      IF v_depot IS DISTINCT FROM v_base THEN
        RAISE EXCEPTION '0759 V4: dcfc20 is not the depot as built';
      END IF;
    ELSIF r.buildout_code = 'dcfc20_grid_today' THEN
      IF (v_depot - 'power') IS DISTINCT FROM (v_base - 'power')
         OR v_depot->'power' IS DISTINCT FROM '{"dcfc_max_concurrent_kw": 1800, "service_max_kw": 2500}'::jsonb THEN
        RAISE EXCEPTION '0759 V4: dcfc20_grid_today is not the depot as built on 1,800/2,500';
      END IF;
    ELSE  -- dcfc30
      IF v_depot->'census' IS DISTINCT FROM '{"dcfc": 30, "parking": 10, "staging": 113, "wash_bay": 3, "service_bay": 2}'::jsonb
         OR jsonb_array_length(v_receipt->'stall_set') <> 15 THEN
        RAISE EXCEPTION '0759 V4: dcfc30 applied reads %', v_depot;
      END IF;
    END IF;
  END LOOP;
END $v4$;

-- ── V5: no stored day reads differently ──
DO $v5$
DECLARE r record; v_after jsonb; v_n int := 0;
BEGIN
  FOR r IN SELECT * FROM _0759_days ORDER BY kind LOOP
    v_after := public.ottoq_throughput_scorecard(r.sim_run_id);
    IF (v_after - 'scorecard_version') IS DISTINCT FROM (r.before - 'scorecard_version')
       OR v_after->>'scorecard_version' <> '0759' THEN
      RAISE EXCEPTION '0759 V5: run % (%) scores differently after the base change', r.sim_run_id, r.kind;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE '0759 V5: % stored days, one of each kind, score the same after the base change', v_n;
END $v5$;

-- ── V6: the history, and the type a space had ──
DO $v6$
DECLARE v_err text;
BEGIN
  IF (SELECT count(*) FROM public.ottoq_site_base_history WHERE change_code = '0759' AND stall_type = 'l2'
         AND valid_until = now()) <> 15
     OR EXISTS (SELECT 1 FROM public.ottoq_site_base_history h WHERE h.change_code = '0759'
                   AND (public.ottoq_stall_type_at(h.stall_id, now() - interval '1 microsecond') IS DISTINCT FROM 'l2'
                        OR public.ottoq_stall_type_at(h.stall_id, now()) IS NOT NULL))
     OR EXISTS (SELECT 1 FROM public.stalls s WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
                   AND s.id NOT IN (SELECT stall_id FROM public.ottoq_site_base_history)
                   AND public.ottoq_stall_type_at(s.id, now() - interval '1 day') IS NOT NULL) THEN
    RAISE EXCEPTION '0759 V6: the base history or ottoq_stall_type_at does not read as declared';
  END IF;
  BEGIN
    UPDATE public.ottoq_site_base_history SET stall_type = stall_type WHERE change_code = '0759';
    v_err := 'none';
  EXCEPTION WHEN OTHERS THEN
    v_err := SQLERRM;
  END;
  IF v_err NOT LIKE '%append-only%' THEN
    RAISE EXCEPTION '0759 V6: the base history accepted an update (%)', v_err;
  END IF;
END $v6$;

-- ── V7: grants ──
DO $v7$
BEGIN
  IF has_function_privilege('anon', 'public.ottoq_site_buildout_apply(uuid,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_site_buildout_apply(uuid,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_site_buildout_restore(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_site_buildout_apply(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.ottoq_site_buildout_restore(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ottoq_stall_type_at(uuid,timestamp with time zone)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.ottoq_stall_type_at(uuid,timestamp with time zone)', 'EXECUTE')
     OR has_table_privilege('anon', 'public.ottoq_site_base_history', 'SELECT')
     OR has_table_privilege('service_role', 'public.ottoq_site_base_history', 'INSERT')
     OR has_table_privilege('authenticated', 'public.ottoq_site_base_history', 'UPDATE')
     OR NOT has_table_privilege('authenticated', 'public.ottoq_site_base_history', 'SELECT') THEN
    RAISE EXCEPTION '0759 V7: grants are not as declared';
  END IF;
END $v7$;

DROP FUNCTION pg_temp.f_0759_depot(uuid);

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0759_canopy_b_is_restriped_for_ten_more_robotic_fast_chargers', true, true,
        'G477. A base change of the twin depot: canopy B re-striped as canopy A, so NASH-L2-STALL-01..10 become robotic '
        'fast chargers NASH-DCFC-STALL-11..20 on the 14-unit pitch (chargers NASH-DCFC-11..20, ABB Terra HP 350, 350 kW; '
        'charge_l2 -> charge_dcfc), NASH-L2-STALL-11..15 are retired (stall_type parking, no position, no charger, '
        'capabilities inactive, chargers decommissioned), and the depot''s limits go to 3,600 kW DC and 4,363 kW '
        'service: 20 fast chargers and 15 standard. forces_recert TRUE: every canon column runs on this depot and its '
        'fingerprints, sessions and decisions read the stalls, chargers and power this changes. forces_dial_restart '
        'TRUE: every dial pair and sweep arm before it ran on the old depot. Build-outs gain stall_set and buildable '
        '(apply and restore replaced); every old build-out reproduces the depot it built (V4); dcfc20 is now the depot '
        'as built, dcfc20_in_place the old dcfc20, dcfc30 new. public.ottoq_site_base_history and '
        'public.ottoq_stall_type_at keep the past: ottoq_throughput_scorecard (version 0759) reads a run''s spaces as '
        'they were when it ran, and the latest stored day of each kind scores the same (V5).',
        now());

COMMIT;
