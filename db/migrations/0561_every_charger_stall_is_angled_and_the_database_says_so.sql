-- migration-version: PENDING
-- migration-name:    every_charger_stall_is_angled_and_the_database_says_so
--
-- 0561  **Every charger stall at the twin depot is angled 60° to its gap lane, and public.stalls now says so.** 40
--       rows: heading, declared footprint, and — on the 36 whose row moved — relative_y and absolute_lat. No stall
--       changes column (relative_x), code, type, charger, status, pointer or reservation.
--
-- ══ §1 WHAT CHANGED IN THE WORLD ════════════════════════════════════════════════════════════════════════════════════
--
--   ottoyarddepot-sim#115 turned all 40 charger stalls into the diagonal stalls of a one-way charging aisle (founder,
--   2026-09-28, of the 90° head-in layout that preceded it: "This looks horizontal pull-in/parking which is not
--   viable"). A car rides its northbound gap lane to where the stall's own axis crosses it, turns 60° in nose first,
--   and leaves by backing out and swinging 60° to face north. The seed this table was built from (ottoyarddepot-sim
--   unreal/layoutSeed.json, generated from src/lib/sitePlan.ts; the builder's SEED MD5 4da9a8d7bc209dfeaa5dbfcd46a34f4c)
--   now declares:
--     heading_degrees   60 on each canopy's WEST column (the car noses north-east, toward the spine and the way its
--                       lane runs), 300 on its EAST column (north-west), where every one of the 40 reads 180;
--     relative_y        the rows RE-PITCHED, north end held: DCFC 16 -> 14 plan units (25.1 -> 22.0 ft), both L2
--                       columns 8.4u (13.2 ft), the east column half a pitch behind the west. A 60° car needs ~15.6u
--                       of straight lane south of its stall to turn in; at the old rows the southernmost L2 stalls'
--                       axes met their lane south of the collector's westbound stream — no car could reach them —
--                       and their back-outs ended across the collector. 36 of 40 rows move north, by 1.4 to 25.9 ft;
--                       DCFC-01 and -06 and L2-01 and -16, the first rows, do not move. absolute_lat follows
--                       (ottoq_local_to_latlng, as the seed computes it); x and longitude do not move.
--     width x depth     10 x 19.0276 ft on all 40. An angled stall's width is capped by the pitch measured square to
--                       the car (8.4u x sin 60° = 11.4 ft) and its depth by the canopy spine, which the facing
--                       column's noses lean toward (the seed's chargerDepthCap). It was 10 x 20 (DCFC) and 10 x 16.14
--                       / 16.77 (L2), sized for cars parked along the column.
--
-- ══ §2 WHAT THIS FILE DOES NOT CHANGE ═══════════════════════════════════════════════════════════════════════════════
--
--   relative_x (every stall keeps its column), codes, types, chargers, status, pointers, reservations, bookings — nor
--   any other depot: rule 8, the twin depot is the one site, and it is the only one whose renderer layout changed.
--   Rank within a column is preserved (V1b), and so is every type's order by (relative_y, id) (V1c) — see §3.
--
-- ══ §3 WHO READS THESE COLUMNS (measured 2026-09-28; P2 re-asserts it at apply time) ═══════════════════════════════
--
--   POSITION (relative_x / relative_y; nothing reads absolute_lat / absolute_lng):
--     public.ottoq_itin_travel_leg              taxi-leg LENGTH between two stalls (feet -> metres -> seconds).
--                                                THIS is what makes the change engine-visible: a leg to or from a
--                                                moved charger stall is up to 25.9 ft shorter or longer.
--     ottoq.ottoq_book_appointment              ORDER BY type match, relative_y, id
--     ottoq.ottoq_sim_prearrival_contracts      ORDER BY ..., relative_y, id
--     public.ottoq_l2_propose_stall_assignment  ORDER BY type match, relative_y, id
--                                                — within a type the order is unchanged (V1c asserts it: the DCFC rows
--                                                stay level across the spine and the L2 columns interleave exactly as
--                                                before); a fallback list that mixes types can order differently.
--     twin.ottoq_sim_dispatch_vehicle           ORDER BY relative_x DESC — x does not move.
--     public.ottoq_twin_snapshot, public.ottoq_twin_depot_layout, public.ottoq_twin_playback_timeline
--                                                what the cockpit and a 3D layer draw from.
--     public.ottoq_check_stall_overlap, public.ottoq_check_fence_containment, public.ottoq_site_geometry
--                                                guards (V4, V5) and a description string.
--   GEOMETRY (heading_degrees / stall_width_ft / stall_depth_ft): ottoq_twin_playback_timeline (a parked car's pose —
--   it said every charger car parks facing south), ottoq_twin_depot_layout, ottoq_check_stall_overlap, and the
--   description in ottoq_site_geometry. No decide-path function, rule evaluator or fingerprint reads them.
--
--   SO forces_recert AND forces_dial_restart ARE BOTH TRUE. Travel legs change length, so a certified cell re-run
--   after this file does not reproduce its digests, and a dial experiment spanning it would compare arms run on two
--   different depots. That is the correct outcome for a change to the world, not a cost to route around.
--
-- ══ §4 THE EVENTS IT WRITES ═════════════════════════════════════════════════════════════════════════════════════════
--
--   trg_ottoq_stalls_state_change writes one signed stall.state_changed per changed row, its diff carrying the moved
--   columns. That is the record of this change and it is wanted — but not as a live run's evidence and not attributed
--   to the engine: the trigger files a row under whichever run happens to be live and infers the actor from that
--   (db/checks/0337 §4). So the file detaches from any run the way 0421 detaches harness setup
--   (ottoq.sim_run_id = 'none') and names itself: actor_type migration_script, actor_id 0561. V3 counts them. The
--   SM.003 probe does not fire: no status moves.
--
-- ══ §5 WHEN TO APPLY ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) AFTER ottoyarddepot-sim#115 is merged. The renderer on main maps a twin stall to the renderer stall at its
--       database position and nowhere else; with these rows moved first it would draw charger cars at the wrong
--       stalls. #115's renderer maps charger stalls by column and rank (setTwinStallMap), so it draws both the rows
--       this file replaces and the rows it writes correctly — #115 first, then this, never the other way round.
--   (b) With NO run live at the twin depot (P0 refuses otherwise). Moving stalls mid-run changes that run's leg
--       lengths from one tick to the next, and a live run may be someone's validation: check 0410's ab8075a3 was
--       running a same-seed comparison against 0409 when this file was written.

BEGIN;

-- ── P0: no pair, no recert runner, and no live run at the twin depot ──
DO $inflight$
DECLARE v_pairs int; v_runs text;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0561 P0: a pair or the recert runner is running right now'; END IF;

  SELECT string_agg(sim_run_id::text || ' (' || status || ', ' || scenario_code || ')', ', ') INTO v_runs
    FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status IN ('initializing', 'running', 'paused');
  IF v_runs IS NOT NULL THEN
    RAISE EXCEPTION '0561 P0: a run is live at the twin depot (%); moving stalls mid-run changes its leg lengths from one tick to the next. Apply when it has ended.', v_runs;
  END IF;
END $inflight$;

-- The 40 rows: where they are (the seed on ottoyarddepot-sim main, which the database equals) and where the angled
-- seed puts them (builder SEED MD5 4da9a8d7bc209dfeaa5dbfcd46a34f4c). x and longitude are the same in both.
CREATE TEMP TABLE _0561_target (
  stall_code text PRIMARY KEY, stall_type text, relative_x double precision,
  old_y double precision, new_y double precision, heading smallint, width_ft numeric, depth_ft numeric,
  old_lat double precision, new_lat double precision, lng double precision, old_heading smallint, old_depth numeric
) ON COMMIT DROP;
INSERT INTO _0561_target VALUES
    ('NASH-DCFC-STALL-01', 'dcfc', 141.2894, 185.2461, 185.2461, 60, 10.0000, 19.0276, 36.14020892, 36.14020892, -86.77231936, 180, 20.0000),
    ('NASH-DCFC-STALL-02', 'dcfc', 141.2894, 160.1280, 163.2677, 60, 10.0000, 19.0276, 36.14013991, 36.14014854, -86.77231936, 180, 20.0000),
    ('NASH-DCFC-STALL-03', 'dcfc', 141.2894, 135.0098, 141.2894, 60, 10.0000, 19.0276, 36.14007091, 36.14008816, -86.77231936, 180, 20.0000),
    ('NASH-DCFC-STALL-04', 'dcfc', 141.2894, 109.8917, 119.3110, 60, 10.0000, 19.0276, 36.14000190, 36.14002778, -86.77231936, 180, 20.0000),
    ('NASH-DCFC-STALL-05', 'dcfc', 141.2894, 84.7736, 97.3327, 60, 10.0000, 19.0276, 36.13993289, 36.13996740, -86.77231936, 180, 20.0000),
    ('NASH-DCFC-STALL-06', 'dcfc', 163.2677, 185.2461, 185.2461, 300, 10.0000, 19.0276, 36.14020892, 36.14020892, -86.77224459, 180, 20.0000),
    ('NASH-DCFC-STALL-07', 'dcfc', 163.2677, 160.1280, 163.2677, 300, 10.0000, 19.0276, 36.14013991, 36.14014854, -86.77224459, 180, 20.0000),
    ('NASH-DCFC-STALL-08', 'dcfc', 163.2677, 135.0098, 141.2894, 300, 10.0000, 19.0276, 36.14007091, 36.14008816, -86.77224459, 180, 20.0000),
    ('NASH-DCFC-STALL-09', 'dcfc', 163.2677, 109.8917, 119.3110, 300, 10.0000, 19.0276, 36.14000190, 36.14002778, -86.77224459, 180, 20.0000),
    ('NASH-DCFC-STALL-10', 'dcfc', 163.2677, 84.7736, 97.3327, 300, 10.0000, 19.0276, 36.13993289, 36.13996740, -86.77224459, 180, 20.0000),
    ('NASH-L2-STALL-01', 'l2', 215.0738, 188.5428, 188.5428, 60, 10.0000, 19.0276, 36.14021797, 36.14021797, -86.77206836, 180, 16.1407),
    ('NASH-L2-STALL-02', 'l2', 215.0738, 171.9021, 175.3558, 60, 10.0000, 19.0276, 36.14017226, 36.14018175, -86.77206836, 180, 16.1407),
    ('NASH-L2-STALL-03', 'l2', 215.0738, 155.2613, 162.1688, 60, 10.0000, 19.0276, 36.14012654, 36.14014552, -86.77206836, 180, 16.1407),
    ('NASH-L2-STALL-04', 'l2', 215.0738, 138.6206, 148.9818, 60, 10.0000, 19.0276, 36.14008083, 36.14010929, -86.77206836, 180, 16.1407),
    ('NASH-L2-STALL-05', 'l2', 215.0738, 121.9798, 135.7948, 60, 10.0000, 19.0276, 36.14003511, 36.14007306, -86.77206836, 180, 16.1407),
    ('NASH-L2-STALL-06', 'l2', 215.0738, 105.3391, 122.6078, 60, 10.0000, 19.0276, 36.13998939, 36.14003683, -86.77206836, 180, 16.1407),
    ('NASH-L2-STALL-07', 'l2', 215.0738, 88.6983, 109.4208, 60, 10.0000, 19.0276, 36.13994368, 36.14000061, -86.77206836, 180, 16.1407),
    ('NASH-L2-STALL-08', 'l2', 215.0738, 72.0576, 96.2338, 60, 10.0000, 19.0276, 36.13989796, 36.13996438, -86.77206836, 180, 16.1407),
    ('NASH-L2-STALL-09', 'l2', 237.0522, 180.5364, 181.9493, 300, 10.0000, 19.0276, 36.14019598, 36.14019986, -86.77199359, 180, 16.7687),
    ('NASH-L2-STALL-10', 'l2', 237.0522, 163.2677, 168.7623, 300, 10.0000, 19.0276, 36.14014854, 36.14016363, -86.77199359, 180, 16.7687),
    ('NASH-L2-STALL-11', 'l2', 237.0522, 145.9990, 155.5753, 300, 10.0000, 19.0276, 36.14010110, 36.14012740, -86.77199359, 180, 16.7687),
    ('NASH-L2-STALL-12', 'l2', 237.0522, 128.7303, 142.3883, 300, 10.0000, 19.0276, 36.14005365, 36.14009118, -86.77199359, 180, 16.7687),
    ('NASH-L2-STALL-13', 'l2', 237.0522, 111.4616, 129.2013, 300, 10.0000, 19.0276, 36.14000621, 36.14005495, -86.77199359, 180, 16.7687),
    ('NASH-L2-STALL-14', 'l2', 237.0522, 94.1929, 116.0143, 300, 10.0000, 19.0276, 36.13995877, 36.14001872, -86.77199359, 180, 16.7687),
    ('NASH-L2-STALL-15', 'l2', 237.0522, 76.9242, 102.8273, 300, 10.0000, 19.0276, 36.13991133, 36.13998249, -86.77199359, 180, 16.7687),
    ('NASH-L2-STALL-16', 'l2', 288.8583, 188.5428, 188.5428, 60, 10.0000, 19.0276, 36.14021797, 36.14021797, -86.77181735, 180, 16.1407),
    ('NASH-L2-STALL-17', 'l2', 288.8583, 171.9021, 175.3558, 60, 10.0000, 19.0276, 36.14017226, 36.14018175, -86.77181735, 180, 16.1407),
    ('NASH-L2-STALL-18', 'l2', 288.8583, 155.2613, 162.1688, 60, 10.0000, 19.0276, 36.14012654, 36.14014552, -86.77181735, 180, 16.1407),
    ('NASH-L2-STALL-19', 'l2', 288.8583, 138.6206, 148.9818, 60, 10.0000, 19.0276, 36.14008083, 36.14010929, -86.77181735, 180, 16.1407),
    ('NASH-L2-STALL-20', 'l2', 288.8583, 121.9798, 135.7948, 60, 10.0000, 19.0276, 36.14003511, 36.14007306, -86.77181735, 180, 16.1407),
    ('NASH-L2-STALL-26', 'l2', 288.8583, 105.3391, 122.6078, 60, 10.0000, 19.0276, 36.13998939, 36.14003683, -86.77181735, 180, 16.1407),
    ('NASH-L2-STALL-27', 'l2', 288.8583, 88.6983, 109.4208, 60, 10.0000, 19.0276, 36.13994368, 36.14000061, -86.77181735, 180, 16.1407),
    ('NASH-L2-STALL-28', 'l2', 288.8583, 72.0576, 96.2338, 60, 10.0000, 19.0276, 36.13989796, 36.13996438, -86.77181735, 180, 16.1407),
    ('NASH-L2-STALL-29', 'l2', 310.8366, 180.5364, 181.9493, 300, 10.0000, 19.0276, 36.14019598, 36.14019986, -86.77174259, 180, 16.7687),
    ('NASH-L2-STALL-30', 'l2', 310.8366, 163.2677, 168.7623, 300, 10.0000, 19.0276, 36.14014854, 36.14016363, -86.77174259, 180, 16.7687),
    ('NASH-L2-STALL-31', 'l2', 310.8366, 145.9990, 155.5753, 300, 10.0000, 19.0276, 36.14010110, 36.14012740, -86.77174259, 180, 16.7687),
    ('NASH-L2-STALL-32', 'l2', 310.8366, 128.7303, 142.3883, 300, 10.0000, 19.0276, 36.14005365, 36.14009118, -86.77174259, 180, 16.7687),
    ('NASH-L2-STALL-33', 'l2', 310.8366, 111.4616, 129.2013, 300, 10.0000, 19.0276, 36.14000621, 36.14005495, -86.77174259, 180, 16.7687),
    ('NASH-L2-STALL-34', 'l2', 310.8366, 94.1929, 116.0143, 300, 10.0000, 19.0276, 36.13995877, 36.14001872, -86.77174259, 180, 16.7687),
    ('NASH-L2-STALL-35', 'l2', 310.8366, 76.9242, 102.8273, 300, 10.0000, 19.0276, 36.13991133, 36.13998249, -86.77174259, 180, 16.7687);

-- ── P1: exactly these 40 charger stalls at the twin depot, each in its column at the old row or already the new ──
DO $premises$
DECLARE
  v_depot   uuid := '11111111-1111-1111-1111-111111111111';
  v_n       int;
  v_live    int;
  v_bad     text;
BEGIN
  SELECT count(*) INTO v_n FROM _0561_target;
  IF v_n <> 40 THEN RAISE EXCEPTION '0561 P1: expected 40 target rows, the file carries %', v_n; END IF;

  SELECT count(*) INTO v_live FROM public.stalls
   WHERE depot_id = v_depot AND stall_type::text IN ('dcfc','l2');
  IF v_live <> 40 THEN
    RAISE EXCEPTION '0561 P1: the twin depot has % charger stalls, not 40 — the layout moved since this file was written', v_live;
  END IF;

  -- each row: right code and type, in its column, and either all-old or all-new (anything else is a third layout)
  SELECT string_agg(t.stall_code, ', ' ORDER BY t.stall_code) INTO v_bad
    FROM _0561_target t
    LEFT JOIN public.stalls s ON s.stall_code = t.stall_code AND s.depot_id = v_depot
   WHERE s.id IS NULL OR s.stall_type::text <> t.stall_type
      OR abs(s.relative_x - t.relative_x) > 0.001 OR abs(s.absolute_lng - t.lng) > 1e-7
      OR NOT (   (abs(s.relative_y - t.old_y) <= 0.001 AND abs(s.absolute_lat - t.old_lat) <= 1e-7 AND s.heading_degrees = t.old_heading)
              OR (abs(s.relative_y - t.new_y) <= 0.001 AND abs(s.absolute_lat - t.new_lat) <= 1e-7 AND s.heading_degrees = t.heading));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0561 P1: neither the old layout nor the angled one (missing, retyped, moved or half-applied): %', v_bad;
  END IF;
END $premises$;

-- ── P2: nobody new reads stall position or geometry (the §3 list, from the catalog, comment-stripped) ──
DO $readers$
DECLARE v_new text;
BEGIN
  SELECT string_agg(obj, ', ' ORDER BY obj) INTO v_new FROM (
    SELECT n.nspname || '.' || p.proname AS obj
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname NOT IN ('pg_catalog','information_schema')
       AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^' || chr(10) || ']*', '', 'g')
           ~* '(heading_degrees|stall_depth_ft|stall_width_ft|relative_x|relative_y|absolute_lat|absolute_lng)'
    UNION
    SELECT schemaname || '.' || viewname FROM pg_views
     WHERE schemaname NOT IN ('pg_catalog','information_schema')
       AND definition ~* '(heading_degrees|stall_depth_ft|stall_width_ft|relative_x|relative_y|absolute_lat|absolute_lng)'
    UNION
    SELECT schemaname || '.' || matviewname FROM pg_matviews
     WHERE definition ~* '(heading_degrees|stall_depth_ft|stall_width_ft|relative_x|relative_y|absolute_lat|absolute_lng)'
  ) r
  WHERE obj NOT IN ('public.ottoq_itin_travel_leg', 'ottoq.ottoq_book_appointment', 'ottoq.ottoq_sim_prearrival_contracts',
                    'public.ottoq_l2_propose_stall_assignment', 'twin.ottoq_sim_dispatch_vehicle',
                    'public.ottoq_twin_snapshot', 'public.ottoq_twin_depot_layout', 'public.ottoq_twin_playback_timeline',
                    'public.ottoq_check_stall_overlap', 'public.ottoq_check_fence_containment', 'public.ottoq_site_geometry');
  IF v_new IS NOT NULL THEN
    RAISE EXCEPTION '0561 P2: stall position or geometry has readers this file did not measure: % — read them before moving stalls', v_new;
  END IF;
END $readers$;

-- The before-state, for V1-V5 and the rollback note: every row, each column's north-to-south order, each type's
-- (relative_y, id) order, and where the event stream and the two geometry guards stood.
CREATE TEMP TABLE _0561_before ON COMMIT DROP AS
SELECT s.id, s.stall_code, s.stall_type::text AS stall_type, s.relative_x, s.relative_y, s.absolute_lat, s.heading_degrees,
       s.stall_width_ft, s.stall_depth_ft,
       rank() OVER (PARTITION BY s.stall_type, round(s.relative_x::numeric, 3) ORDER BY s.relative_y DESC) AS col_rank,
       rank() OVER (PARTITION BY s.stall_type ORDER BY s.relative_y, s.id) AS type_rank,
       (abs(s.relative_y - t.new_y) > 0.001 OR s.heading_degrees IS DISTINCT FROM t.heading
        OR s.stall_width_ft IS DISTINCT FROM t.width_ft OR s.stall_depth_ft IS DISTINCT FROM t.depth_ft) AS will_change
  FROM public.stalls s JOIN _0561_target t ON t.stall_code = s.stall_code
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111';
CREATE TEMP TABLE _0561_mark ON COMMIT DROP AS
SELECT (SELECT max(event_seq) FROM public.ottoq_events) AS seq0,
       (public.ottoq_check_stall_overlap('11111111-1111-1111-1111-111111111111'::uuid) ->> 'failure_count')::int AS overlap0,
       jsonb_array_length(public.ottoq_check_fence_containment('11111111-1111-1111-1111-111111111111'::uuid) -> 'failures') AS fence0;

-- ── the change: detached from any live run, and named ──
SELECT set_config('ottoq.sim_run_id', 'none', true),
       set_config('ottoq.actor_type', 'migration_script', true),
       set_config('ottoq.actor_id', '0561', true);

UPDATE public.stalls s
   SET relative_y      = t.new_y,
       absolute_lat    = t.new_lat,
       heading_degrees = t.heading,
       stall_width_ft  = t.width_ft,
       stall_depth_ft  = t.depth_ft
  FROM _0561_target t
 WHERE s.stall_code = t.stall_code
   AND s.depot_id = '11111111-1111-1111-1111-111111111111'
   AND (abs(s.relative_y - t.new_y) > 0.001
        OR s.heading_degrees IS DISTINCT FROM t.heading
        OR s.stall_width_ft IS DISTINCT FROM t.width_ft
        OR s.stall_depth_ft IS DISTINCT FROM t.depth_ft);

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_depot  uuid := '11111111-1111-1111-1111-111111111111';
  v_bad    text;
  v_n      int;
  v_want   int;
  v_moved  int;
  v_ev     int;
  v_evbad  int;
  v_seq0   bigint;
  v_ov0    int;
  v_ov1    int;
  v_fe0    int;
  v_fe1    int;
BEGIN
  -- V1: all 40 at the angled seed's geometry, and not one changed column
  SELECT string_agg(t.stall_code, ', ' ORDER BY t.stall_code) INTO v_bad
    FROM _0561_target t JOIN public.stalls s ON s.stall_code = t.stall_code AND s.depot_id = v_depot
    JOIN _0561_before b ON b.id = s.id
   WHERE abs(s.relative_y - t.new_y) > 0.001 OR abs(s.absolute_lat - t.new_lat) > 1e-7
      OR s.heading_degrees <> t.heading OR s.stall_width_ft <> t.width_ft OR s.stall_depth_ft <> t.depth_ft
      OR s.relative_x <> b.relative_x;
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION '0561 V1: not at the angled seed geometry, or changed column: %', v_bad; END IF;
  IF (SELECT count(*) FROM public.stalls WHERE depot_id = v_depot AND stall_type::text IN ('dcfc','l2')
         AND heading_degrees IN (60, 300)) <> 40 THEN
    RAISE EXCEPTION '0561 V1: fewer than 40 charger stalls read angled (60 / 300)';
  END IF;

  -- V1b: every column keeps its north-to-south order — the invariant the renderer maps charger stalls by while
  -- the two worlds disagree (TwinMotionDriver.setTwinStallMap, column and rank)
  SELECT string_agg(b.stall_code, ', ' ORDER BY b.stall_code) INTO v_bad
    FROM _0561_before b JOIN (
      SELECT s.id, rank() OVER (PARTITION BY s.stall_type, round(s.relative_x::numeric, 3) ORDER BY s.relative_y DESC) AS r
        FROM public.stalls s WHERE s.depot_id = v_depot AND s.stall_type::text IN ('dcfc','l2')
    ) a ON a.id = b.id
   WHERE a.r <> b.col_rank;
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION '0561 V1b: a charger stall changed rank in its column: %', v_bad; END IF;

  -- V1c: every type keeps its (relative_y, id) order — what ottoq_book_appointment, ottoq_sim_prearrival_contracts
  -- and ottoq_l2_propose_stall_assignment choose within a type by
  SELECT string_agg(b.stall_code, ', ' ORDER BY b.stall_code) INTO v_bad
    FROM _0561_before b JOIN (
      SELECT s.id, rank() OVER (PARTITION BY s.stall_type ORDER BY s.relative_y, s.id) AS r
        FROM public.stalls s WHERE s.depot_id = v_depot AND s.stall_type::text IN ('dcfc','l2')
    ) a ON a.id = b.id
   WHERE a.r <> b.type_rank;
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION '0561 V1c: a charger stall changed its place in its type''s order: %', v_bad; END IF;

  -- V2: nothing else at the depot was touched in this transaction
  SELECT count(*) INTO v_n FROM public.stalls WHERE depot_id = v_depot AND updated_at = now();
  SELECT count(*) INTO v_want FROM _0561_before WHERE will_change;
  IF v_n <> v_want THEN
    RAISE EXCEPTION '0561 V2: % stall rows at the twin depot were updated in this transaction, expected %', v_n, v_want;
  END IF;
  SELECT count(*) INTO v_moved FROM _0561_before b JOIN _0561_target t USING (stall_code)
   WHERE abs(b.relative_y - t.new_y) > 0.001;

  -- V3: one stall.state_changed per changed row, filed under no run and named migration_script / 0561
  SELECT seq0 INTO v_seq0 FROM _0561_mark;
  SELECT count(*), count(*) FILTER (WHERE e.sim_run_id IS NOT NULL OR e.actor_type <> 'migration_script'
                                        OR e.actor_id IS DISTINCT FROM '0561')
    INTO v_ev, v_evbad
    FROM public.ottoq_events e
   WHERE e.event_seq > v_seq0 AND e.entity_type = 'stall' AND e.event_type = 'stall.state_changed'
     AND e.entity_id IN (SELECT id FROM _0561_before);
  IF v_ev <> v_want OR v_evbad > 0 THEN
    RAISE EXCEPTION '0561 V3: % stall.state_changed events (% misattributed), expected % filed under no run as migration_script/0561',
      v_ev, v_evbad, v_want;
  END IF;

  -- V4 / V5: the database's own stall-overlap and fence-containment guards read no worse than before
  SELECT overlap0, fence0 INTO v_ov0, v_fe0 FROM _0561_mark;
  v_ov1 := (public.ottoq_check_stall_overlap(v_depot) ->> 'failure_count')::int;
  v_fe1 := jsonb_array_length(public.ottoq_check_fence_containment(v_depot) -> 'failures');
  IF v_ov1 > v_ov0 THEN
    RAISE EXCEPTION '0561 V4: ottoq_check_stall_overlap went from % to % failures', v_ov0, v_ov1;
  END IF;
  IF v_fe1 > v_fe0 THEN
    RAISE EXCEPTION '0561 V5: ottoq_check_fence_containment went from % to % failures', v_fe0, v_fe1;
  END IF;
  RAISE NOTICE '0561: % of 40 charger stalls changed (% moved north); % events filed under no run; stall-overlap failures % -> %; fence failures % -> %',
    v_want, v_moved, v_ev, v_ov0, v_ov1, v_fe0, v_fe1;
END $verify$;

-- Rollback (the before-state, which _0561_before held and _0561_target's old_* columns carry): relative_y = old_y,
-- absolute_lat = old_lat, heading_degrees = 180 and stall_depth_ft = old_depth (20 on DCFC, 16.1407 on the 16 L2
-- west-column rows, 16.7687 on the 14 L2 east-column rows) on all 40; width unchanged at 10. Run it the same way —
-- ottoq.sim_run_id 'none', actor migration_script — with no run live, after reverting ottoyarddepot-sim#115, and
-- DELETE FROM public.ottoq_cert_lineage WHERE name = '0561_every_charger_stall_is_angled_and_the_database_says_so'.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0561_every_charger_stall_is_angled_and_the_database_says_so', true, true,
  'The 40 twin-depot charger stalls are angled 60° to their gap lanes (ottoyarddepot-sim#115): heading 60/300, footprint 10 x 19.0276 ft, and 36 rows re-pitched north (DCFC 14u, L2 8.4u; relative_y and absolute_lat), columns unchanged. ottoq_itin_travel_leg reads stall positions, so taxi legs to and from a moved stall change length: a certified cell re-run after this does not reproduce its digests, and a dial experiment spanning it compares two depots. Within each type the (relative_y, id) order and each column''s rank are unchanged (V1b, V1c).',
  now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
