-- migration-version: 20260806223619
-- migration-name:    unify_depot_layout

-- ============================================================================
-- 0010_unify_depot_layout.sql
--
-- THE SHORT VERSION, IN PLAIN LANGUAGE
--
-- THE PROBLEM. The depot exists twice. There is the depot the renderer draws, and
-- there is the depot this database has rows for, and until last week nobody had
-- ever put the two side by side. When someone finally drew the database's version,
-- it was not a depot. It was 150 parking spaces stacked on top of each other:
--
--   * 54 pairs of stalls overlapped -- 76 of the 150 spaces were sitting on
--     another space. Not close to. On top of.
--   * 13 staging spaces were inside the wash building. 4 were inside the fenced
--     battery compound.
--   * 20 of the 45 charging spaces had no aisle a car could drive down. There was
--     12 ft of clearance where a row of parking plus its aisle needs 64.
--   * 2 of the 4 solar canopies covered no chargers at all. Two spaces shared one
--     identical point -- the same coordinate, twice.
--   * The 5 service and wash bays had no width and no depth recorded. Blank.
--   * All 300 rows had no map position at all.
--
-- MEASURED AGAINST THE LIVE DATABASE BEFORE WRITING THIS FILE, because the overlap
-- count depends entirely on how big you assume a car is, and that deserves to be
-- said out loud rather than quoted as one number:
--   * at the design vehicle (6.6 x 16.0 ft):        29 overlapping pairs per depot
--   * at the dimensions the database ITSELF
--     declares for these stalls (10x18 / 10x20):   779 overlapping pairs per depot
--   * stalls with no map point (absolute_point):    300 of 300 -- every single row
--   * depots recording the wrong parcel:            2 of 2
-- The audit's headline of 54 pairs sits between those two footprints. The point is
-- not which number is right. The point is that the database's own declared stall
-- sizes do not fit in the space the database says it has, at any footprint.
--
-- WHY. The program was drawn onto a parcel too small to hold it. The database says
-- the site is 360 x 220 ft -- 1.82 acres. Everything was squeezed to fit that, and
-- when it would not fit, it overlapped instead. The renderer's lot is the real one:
-- 452 x 314 ft, 3.26 acres, with zero overlaps and a 24.8 ft main aisle, and a
-- human has reviewed it.
--
-- WHAT THIS FILE DOES. It makes the renderer's depot the single definition and
-- corrects the database to match. Coordinates, footprints, headings, zones, the
-- buildings, the canopies, the gates, the fence. After this, the renderer and the
-- 3D generator both read the layout FROM here instead of each keeping their own.
--
-- WHAT IT COSTS -- read this part.
--
--   1. THE DEPOT GETS TEN SPACES BIGGER, BUT FIVE CHARGERS SMALLER.
--      150 stalls become 160: staging goes 100 -> 115, L2 charging goes 35 -> 30.
--      Losing 5 L2 chargers is the POINT, not a side effect. Those five
--      (NASH-L2-STALL-21 through 25) ran off the south end of canopy 2, they were
--      10 of the 54 overlaps, and one was parked on top of a staging space. They
--      were capacity that existed only in the database. Every plan that counted
--      them was over-promising by five chargers.
--
--      This number is load-bearing. ottoq_plan_overnight_wave counts L2 stalls with
--      no filter at all and broadcasts that count into every overnight charging
--      slot. So from the moment this applies, the overnight wave plans for 30
--      chargers instead of 35. That is the correction working. It also means any
--      capacity or utilisation figure measured BEFORE this migration used a
--      denominator that was 5 chargers too generous.
--
--   2. NINETEEN CODES LEAVE THE LAYOUT: 14 ARE RE-HOMED, 5 ARE DELETED.
--      True set difference per depot, measured against the live 150-stall layout:
--      131 codes preserved, 29 minted, 19 leaving.
--
--      A stall ROW may only be DELETED if NOTHING references it. Otherwise it is
--      RE-HOMED -- UPDATEd onto a surviving position, keeping its id and therefore
--      its whole history. Staging is fungible; its bookings are not.
--
--        * 14 staging codes are RE-HOMED (12 north apron spaces the renderer keeps
--          clear for bay-rear swing-out, plus 2 trimmed from the temp block). All 14
--          land on minted staging positions -- 29 are available for 14.
--        * 5 phantom L2 stalls are DELETED. There is no spare L2 code to re-home
--          onto, and they are referenced by nothing.
--
--      This is a CORRECTION to an earlier draft of this migration, which deleted all
--      19. On the live database at the time, 13 of the doomed staging rows carried
--      released bookings and 3 more carried 11 vehicle_state_log rows. Because
--      ottoq_stall_bookings.stall_id is ON DELETE CASCADE, that draft would not have
--      errored -- it would have silently destroyed 13 rows of the booking ledger.
--
--      Rows, not columns and not tables -- nothing is DROPped anywhere in this file.
--      If any stall in the DELETE set is still referenced, this migration ABORTS and
--      names the referencing table, column and delete action. It checks twice: once
--      up front (section 1.5) and once at apply time against the same temp table the
--      DELETE reads (section 5.2), so the two cannot drift apart.
--
--   3. EVERY STALL MOVES. The whole site is re-plotted into the renderer's frame.
--      Two conversions are involved and both have bitten this project before:
--        - 1 render unit = 1.56988189 ft (0.4785 m per unit / 0.3048 m per foot).
--          A past outage applied 0.4785 to a value already in feet and made every
--          travel leg 1.57x too long. The inverse trap is live here: storing raw
--          render units would make every leg 1.57x too SHORT. The seed stores feet.
--        - the renderer's y axis counts SOUTH, this database's counts NORTH. So
--          this is a mirror, not just a rescale. Compass headings carry through
--          unchanged, because a bearing does not care which way y counts.
--
--   4. THE SERVICE BAYS STAY INSIDE THE OFFICE BUILDING. They are not a mistake.
--      It is an attached service garage, the founder confirmed it, and this file
--      RELABELS the building to say so rather than pretending the bays are
--      somewhere else. The geometry guard whitelists those two bays by ID.
--
--   5. THE FIVE BAYS GET DIMENSIONS FOR THE FIRST TIME, AND THEY ARE ESTIMATES.
--      Service bays 14 x 30 ft, wash bays 14 x 35 ft. Nothing measured these; they
--      are sized to fit inside the building and the bay spacing the renderer drew.
--      They are tunable and they are flagged wherever they appear.
--
--   6. ONE SOLAR CANOPY HAS NO COUNTERPART AND IS RETIRED ON PAPER ONLY.
--      The renderer has 3 canopies; the database has 4. CANOPY-04 is marked
--      decommissioned -- the row is KEPT, never dropped. But ottoq_canopy_state,
--      which is what the energy model actually reads, is DELIBERATELY NOT TOUCHED.
--      Solar output after this migration is byte-for-byte what it was before.
--      Reconciling that 4th canopy's 180 kW is a real decision and it is NOT this
--      file's to make. It is left on the table, in the open.
--
-- WHAT THIS FILE DELIBERATELY DOES NOT DO. It does not change orchestration, the
-- LP, Gate B, cuOpt, Nemotron, any decision function, any tick behaviour, or the
-- approval gate. It does not enable ottoq_apply_need_escalation. It does not DROP a
-- table, a column or a function. It moves geometry and it corrects counts. That is
-- the whole scope.
--
-- HOW TO UNDO IT. Section 2 snapshots public.stalls, ottoq_site_structures and the
-- depots' site fields into ottoq_layout_backup_0010_* before anything is written.
-- Restore instructions are at the bottom of this file.
--
-- WHERE THE DATA COMES FROM. ottoyarddepot-sim, scripts/buildLayoutSeed.mjs, which
-- reads src/lib/sitePlan.ts. Section 3 of this file is that generator's output,
-- pasted verbatim. It is deterministic: same site plan in, byte-identical SQL out.
--
--   To regenerate section 3:
--     cd ottoyarddepot-sim
--     npm run layout:seed && npm run layout:check
--     then replace everything between the SEED BEGIN / SEED END markers with
--     unreal/layoutSeed.sql, and update SEED_MD5 in section 4 to the hash the
--     generator prints.
-- ============================================================================


-- ============================================================================
-- SECTION 1 -- PRECONDITIONS
--
-- These are GUARDS, not comments. A careless apply fails here, loudly, with the
-- offending rows named, instead of half-rewriting a running depot.
-- ============================================================================

DO $mig$
DECLARE
  v_n           bigint;
  v_names       text;
  v_depots      bigint;
  v_fk          record;
  v_hits        bigint;
  v_blocked     text := '';
BEGIN
  ------------------------------------------------------------------ 1.1 extensions
  IF to_regprocedure('extensions.uuid_generate_v5(uuid,text)') IS NULL THEN
    RAISE EXCEPTION
      '0010 ABORT: extensions.uuid_generate_v5 is missing. New stall ids are derived '
      'from it so that re-running this migration is idempotent; without it the apply '
      'would mint random keys and stop being repeatable.';
  END IF;
  IF to_regprocedure('public.st_makepoint(double precision,double precision)') IS NULL THEN
    RAISE EXCEPTION
      '0010 ABORT: PostGIS ST_MakePoint not found in schema public. absolute_point '
      'cannot be populated.';
  END IF;

  ------------------------------------------------------------- 1.2 nothing running
  -- Re-plotting every coordinate underneath a live sim would corrupt in-flight
  -- travel legs, which are computed from exactly these numbers.
  SELECT count(*) INTO v_n
    FROM public.ottoq_sim_runs
   WHERE status IN ('running', 'paused');
  IF v_n > 0 THEN
    SELECT string_agg(id::text || ' (' || status || ')', ', ' ORDER BY id) INTO v_names
      FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused');
    RAISE EXCEPTION
      '0010 ABORT: % sim run(s) are running or paused: %. Stop them first -- this '
      'migration moves every stall coordinate and any in-flight leg would be '
      'computed against geometry that no longer exists.', v_n, v_names;
  END IF;

  ---------------------------------------------------------- 1.3 the depots we expect
  -- Both depots are seeded identically and both are broken the same way. If the
  -- shape is not what this migration was written against, stop.
  SELECT count(DISTINCT depot_id) INTO v_depots FROM public.stalls;
  IF v_depots = 0 THEN
    RAISE EXCEPTION '0010 ABORT: no depot has any stalls. Nothing to unify.';
  END IF;

  SELECT string_agg(depot_id::text || ' has ' || n::text, ', ' ORDER BY depot_id)
    INTO v_names
    FROM (SELECT depot_id, count(*) n FROM public.stalls GROUP BY depot_id) q
   WHERE n <> 150;
  IF v_names IS NOT NULL THEN
    RAISE EXCEPTION
      '0010 ABORT: expected every depot to hold exactly 150 stalls (the broken '
      'layout this migration was written against). Found: %. Either 0010 has already '
      'been applied, or the layout has changed and this file needs re-deriving.',
      v_names;
  END IF;

  ------------------------------------------------- 1.4 leaving stalls are not in use
  -- All 19 codes that leave the layout -- the 14 re-homed AND the 5 deleted -- must be
  -- empty. Occupancy is checked for BOTH, not just the deleted ones: a re-homed stall
  -- keeps its row but its position jumps across the site, so a car sitting in one
  -- would silently teleport. Emptiness is the precondition for moving a space, not
  -- just for removing it.
  SELECT count(*), string_agg(DISTINCT stall_code, ', ' ORDER BY stall_code)
    INTO v_n, v_names
    FROM public.stalls
   WHERE stall_code = ANY (ARRAY[
           'NASH-L2-STALL-21','NASH-L2-STALL-22','NASH-L2-STALL-23','NASH-L2-STALL-24',
           'NASH-L2-STALL-25',
           'NASH-STG-N008','NASH-STG-N009','NASH-STG-N010','NASH-STG-N011','NASH-STG-N012',
           'NASH-STG-N013','NASH-STG-N014','NASH-STG-N015','NASH-STG-N016','NASH-STG-N017',
           'NASH-STG-N018','NASH-STG-N019',
           'NASH-STG-I014','NASH-STG-B014'])
     AND (current_vehicle_id IS NOT NULL
          OR reserved_by IS NOT NULL
          OR reserved_for_mission_id IS NOT NULL);
  IF v_n > 0 THEN
    RAISE EXCEPTION
      '0010 ABORT: % stall(s) being retired are still occupied or reserved: %. '
      'Release them first.', v_n, v_names;
  END IF;

  --------------------------------------- 1.5 doomed stalls are not referenced by ANYTHING
  --
  -- THIS CHECK USED TO FILTER confdeltype IN ('a','r') -- NO ACTION and RESTRICT
  -- only -- on the reasoning that "CASCADE and SET NULL keys resolve themselves."
  -- They do not resolve themselves. They resolve SILENTLY, which is worse:
  --
  --   * 3 of the 17 keys are ON DELETE CASCADE, and one of them is
  --     ottoq_stall_bookings.stall_id. Deleting a referenced stall does not raise --
  --     it deletes the booking ledger rows with it, with no error and no trace.
  --   * 4 more are ON DELETE SET NULL (vehicles.current_stall_id,
  --     ottow_missions.destination_stall_id, progression_decisions.from/to), which
  --     silently blanks the history instead of destroying it.
  --
  -- Only the remaining 10 would actually have raised. So the earlier version of this
  -- check reported confidence it had not earned: when this migration was first
  -- prepared, the 12 NASH-STG-N008..N019 rows plus NASH-STG-B014 held 13 released
  -- bookings, and this check was structurally incapable of seeing them. What halted
  -- the apply was 11 vehicle_state_log rows -- a NO ACTION key, caught by luck. Had
  -- that table been empty, 0010 would have applied cleanly and eaten the ledger.
  --
  -- Now: every key, every delete action. A row that anything points at is not
  -- deletable, full stop -- it gets re-homed instead (section 5.2).
  --
  -- The delete set is also much smaller than it was. Staging is fungible, so the 14
  -- staging codes that leave the layout are re-homed and are NOT in this list; only
  -- the 5 phantom L2 stalls are actually deleted.
  FOR v_fk IN
    SELECT c.conname,
           n.nspname  AS child_schema,
           cl.relname AS child_table,
           a.attname  AS child_column,
           c.confdeltype AS del_action
      FROM pg_constraint c
      JOIN pg_class      cl ON cl.oid = c.conrelid
      JOIN pg_namespace  n  ON n.oid  = cl.relnamespace
      JOIN unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord) ON true
      JOIN pg_attribute  a  ON a.attrelid = c.conrelid AND a.attnum = k.attnum
     WHERE c.contype = 'f'
       AND c.confrelid = 'public.stalls'::regclass
     ORDER BY 2, 3, 4
  LOOP
    EXECUTE format(
      'SELECT count(*) FROM %I.%I ch JOIN public.stalls s ON s.id = ch.%I
        WHERE s.stall_code = ANY ($1)',
      v_fk.child_schema, v_fk.child_table, v_fk.child_column)
      INTO v_hits
      USING ARRAY[
        'NASH-L2-STALL-21','NASH-L2-STALL-22','NASH-L2-STALL-23','NASH-L2-STALL-24',
        'NASH-L2-STALL-25'];
    IF v_hits > 0 THEN
      v_blocked := v_blocked || format('%s.%s.%s [on delete %s]: %s row(s); ',
        v_fk.child_schema, v_fk.child_table, v_fk.child_column,
        CASE v_fk.del_action WHEN 'c' THEN 'CASCADE -- WOULD HAVE BEEN DESTROYED SILENTLY'
                             WHEN 'n' THEN 'SET NULL -- WOULD HAVE BEEN BLANKED SILENTLY'
                             WHEN 'r' THEN 'RESTRICT' ELSE 'NO ACTION' END,
        v_hits);
    END IF;
  END LOOP;

  IF v_blocked <> '' THEN
    RAISE EXCEPTION
      '0010 ABORT: a stall this migration would DELETE is still referenced -- %. '
      'Nothing has been written. A referenced stall must be RE-HOMED (updated onto a '
      'surviving position, keeping its id and its history), never deleted. Move it '
      'into ottoq_layout_seed_rehome in ottoyarddepot-sim/scripts/buildLayoutSeed.mjs '
      'and regenerate, or purge the referencing history first.',
      v_blocked;
  END IF;

  RAISE NOTICE '0010 preconditions passed: % depot(s), 150 stalls each, nothing running.', v_depots;
END
$mig$;


-- ============================================================================
-- SECTION 2 -- SNAPSHOT BEFORE REPLACE
--
-- Full copies of everything this migration overwrites, taken before a single row
-- is touched. IF NOT EXISTS so that a re-run preserves the ORIGINAL snapshot
-- rather than overwriting it with already-migrated data.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.ottoq_layout_backup_0010_stalls AS
  SELECT *, now() AS backed_up_at FROM public.stalls;

CREATE TABLE IF NOT EXISTS public.ottoq_layout_backup_0010_structures AS
  SELECT *, now() AS backed_up_at FROM public.ottoq_site_structures;

CREATE TABLE IF NOT EXISTS public.ottoq_layout_backup_0010_depots AS
  SELECT id, site_length_ft, site_width_ft, site_acres, site_layout, now() AS backed_up_at
    FROM public.depots;

COMMENT ON TABLE public.ottoq_layout_backup_0010_stalls IS
  'Pre-0010 snapshot of public.stalls (the overlapping 150-stall layout). Restore '
  'instructions are at the foot of db/migrations/0010_unify_depot_layout.sql.';
COMMENT ON TABLE public.ottoq_layout_backup_0010_structures IS
  'Pre-0010 snapshot of public.ottoq_site_structures (360x220 ft frame).';
COMMENT ON TABLE public.ottoq_layout_backup_0010_depots IS
  'Pre-0010 snapshot of the depots site_* fields (360x220 ft, 1.82 acres).';

DO $mig$
DECLARE v_s bigint; v_t bigint;
BEGIN
  SELECT count(*) INTO v_s FROM public.ottoq_layout_backup_0010_stalls;
  SELECT count(*) INTO v_t FROM public.ottoq_layout_backup_0010_structures;
  IF v_s = 0 THEN
    RAISE EXCEPTION '0010 ABORT: the stalls snapshot is empty. Refusing to replace '
                    'a layout that has not been backed up.';
  END IF;
  RAISE NOTICE '0010 snapshot: % stall row(s), % structure row(s) preserved.', v_s, v_t;
END
$mig$;


-- ============================================================================
-- SECTION 3 -- THE GENERATED SEED
--
-- >>> SEED BEGIN -- generated by ottoyarddepot-sim/scripts/buildLayoutSeed.mjs.
-- >>> Do not hand-edit. Section 4 verifies its md5 and will abort if you do.
-- ============================================================================

-- =============================================================================
-- ottoq_layout_seed  —  GENERATED FILE, DO NOT EDIT BY HAND
--
-- Generated by scripts/buildLayoutSeed.mjs from src/lib/sitePlan.ts.
-- Deterministic: same site plan in => byte-identical file out. Re-run and diff.
--
-- 1 render unit = 0.4785 m / 0.3048 m per ft = 1.56988189 ft
-- relative_x = (render_x - 6) * UNIT_FT      [0 .. 452.13 ft]
-- relative_y = (206 - render_y) * UNIT_FT     [0 .. 313.98 ft]  <- Y IS FLIPPED
--
-- Stalls:     160  (staging 115, l2 30, dcfc 10, wash 3, service 2)
-- Structures: 26
-- Re-homed stall codes:    14  (staging; row + id + history kept, position moved)
-- Deleted stall codes:     5  (must be referenced by nothing)
-- Retired structure codes: 2  (CANOPY-04, METAL-CANOPY-PERIM)
--
-- SEED MD5: 89943752f32f98da4ef80b6baedb3174
--   md5 over stall_code|stall_type|relative_x|relative_y|heading|width|depth,
--   newline-joined, ordered by stall_code. Migration 0010 recomputes this in SQL
--   and aborts on mismatch, so a hand-edited seed cannot reshape the depot.
-- =============================================================================

-- The seed is DEPOT-AGNOSTIC. stall_code is the natural key; the migration
-- resolves it to a depot and to a primary key. See buildLayoutSeed.mjs for the
-- UUID strategy (existing codes keep their id; new codes get uuid_generate_v5).

CREATE TEMP TABLE ottoq_layout_seed_stalls (
  stall_code       text PRIMARY KEY,
  render_id        text        NOT NULL,
  stall_type       text        NOT NULL,
  stall_kind       text        NOT NULL,
  zone             text        NOT NULL,
  staging_role     text,
  display_name     text        NOT NULL,
  relative_x       numeric     NOT NULL,
  relative_y       numeric     NOT NULL,
  heading_degrees  smallint    NOT NULL,
  stall_width_ft   numeric     NOT NULL,
  stall_depth_ft   numeric     NOT NULL,
  absolute_lat     numeric     NOT NULL,
  absolute_lng     numeric     NOT NULL,
  canopy_code      text,
  canopy_side      text,
  covered          boolean     NOT NULL,
  run_id           text        NOT NULL
) ON COMMIT DROP;

INSERT INTO ottoq_layout_seed_stalls
  (stall_code, render_id, stall_type, stall_kind, zone, staging_role, display_name,
   relative_x, relative_y, heading_degrees, stall_width_ft, stall_depth_ft,
   absolute_lat, absolute_lng, canopy_code, canopy_side, covered, run_id)
VALUES
  ('NASH-DCFC-STALL-01', 'DCFC-01', 'dcfc', 'charging', 'dcfc_zone', NULL, 'CANOPY-01 W-01', 141.2894, 185.2461, 180, 10.0000, 20.0000, 36.14020892, -86.77231936, 'CANOPY-01', 'W', true, 'A'),
  ('NASH-DCFC-STALL-02', 'DCFC-02', 'dcfc', 'charging', 'dcfc_zone', NULL, 'CANOPY-01 W-02', 141.2894, 160.1280, 180, 10.0000, 20.0000, 36.14013991, -86.77231936, 'CANOPY-01', 'W', true, 'A'),
  ('NASH-DCFC-STALL-03', 'DCFC-03', 'dcfc', 'charging', 'dcfc_zone', NULL, 'CANOPY-01 W-03', 141.2894, 135.0098, 180, 10.0000, 20.0000, 36.14007091, -86.77231936, 'CANOPY-01', 'W', true, 'A'),
  ('NASH-DCFC-STALL-04', 'DCFC-04', 'dcfc', 'charging', 'dcfc_zone', NULL, 'CANOPY-01 W-04', 141.2894, 109.8917, 180, 10.0000, 20.0000, 36.14000190, -86.77231936, 'CANOPY-01', 'W', true, 'A'),
  ('NASH-DCFC-STALL-05', 'DCFC-05', 'dcfc', 'charging', 'dcfc_zone', NULL, 'CANOPY-01 W-05', 141.2894, 84.7736, 180, 10.0000, 20.0000, 36.13993289, -86.77231936, 'CANOPY-01', 'W', true, 'A'),
  ('NASH-DCFC-STALL-06', 'DCFC-06', 'dcfc', 'charging', 'dcfc_zone', NULL, 'CANOPY-01 E-06', 163.2677, 185.2461, 180, 10.0000, 20.0000, 36.14020892, -86.77224459, 'CANOPY-01', 'E', true, 'A'),
  ('NASH-DCFC-STALL-07', 'DCFC-07', 'dcfc', 'charging', 'dcfc_zone', NULL, 'CANOPY-01 E-07', 163.2677, 160.1280, 180, 10.0000, 20.0000, 36.14013991, -86.77224459, 'CANOPY-01', 'E', true, 'A'),
  ('NASH-DCFC-STALL-08', 'DCFC-08', 'dcfc', 'charging', 'dcfc_zone', NULL, 'CANOPY-01 E-08', 163.2677, 135.0098, 180, 10.0000, 20.0000, 36.14007091, -86.77224459, 'CANOPY-01', 'E', true, 'A'),
  ('NASH-DCFC-STALL-09', 'DCFC-09', 'dcfc', 'charging', 'dcfc_zone', NULL, 'CANOPY-01 E-09', 163.2677, 109.8917, 180, 10.0000, 20.0000, 36.14000190, -86.77224459, 'CANOPY-01', 'E', true, 'A'),
  ('NASH-DCFC-STALL-10', 'DCFC-10', 'dcfc', 'charging', 'dcfc_zone', NULL, 'CANOPY-01 E-10', 163.2677, 84.7736, 180, 10.0000, 20.0000, 36.13993289, -86.77224459, 'CANOPY-01', 'E', true, 'A'),
  ('NASH-L2-STALL-01', 'L2-01', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 W-01', 215.0738, 188.3858, 180, 10.0000, 15.6698, 36.14021754, -86.77206836, 'CANOPY-02', 'W', true, 'B'),
  ('NASH-L2-STALL-02', 'L2-02', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 W-02', 215.0738, 172.2160, 180, 10.0000, 15.6698, 36.14017312, -86.77206836, 'CANOPY-02', 'W', true, 'B'),
  ('NASH-L2-STALL-03', 'L2-03', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 W-03', 215.0738, 156.0463, 180, 10.0000, 15.6698, 36.14012870, -86.77206836, 'CANOPY-02', 'W', true, 'B'),
  ('NASH-L2-STALL-04', 'L2-04', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 W-04', 215.0738, 139.8765, 180, 10.0000, 15.6698, 36.14008428, -86.77206836, 'CANOPY-02', 'W', true, 'B'),
  ('NASH-L2-STALL-05', 'L2-05', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 W-05', 215.0738, 123.7067, 180, 10.0000, 15.6698, 36.14003985, -86.77206836, 'CANOPY-02', 'W', true, 'B'),
  ('NASH-L2-STALL-06', 'L2-06', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 W-06', 215.0738, 107.5369, 180, 10.0000, 15.6698, 36.13999543, -86.77206836, 'CANOPY-02', 'W', true, 'B'),
  ('NASH-L2-STALL-07', 'L2-07', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 W-07', 215.0738, 91.3671, 180, 10.0000, 15.6698, 36.13995101, -86.77206836, 'CANOPY-02', 'W', true, 'B'),
  ('NASH-L2-STALL-08', 'L2-08', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 W-08', 215.0738, 75.1973, 180, 10.0000, 15.6698, 36.13990659, -86.77206836, 'CANOPY-02', 'W', true, 'B'),
  ('NASH-L2-STALL-09', 'L2-09', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 E-09', 237.0522, 180.5364, 180, 10.0000, 16.7687, 36.14019598, -86.77199359, 'CANOPY-02', 'E', true, 'B'),
  ('NASH-L2-STALL-10', 'L2-10', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 E-10', 237.0522, 163.2677, 180, 10.0000, 16.7687, 36.14014854, -86.77199359, 'CANOPY-02', 'E', true, 'B'),
  ('NASH-L2-STALL-11', 'L2-11', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 E-11', 237.0522, 145.9990, 180, 10.0000, 16.7687, 36.14010110, -86.77199359, 'CANOPY-02', 'E', true, 'B'),
  ('NASH-L2-STALL-12', 'L2-12', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 E-12', 237.0522, 128.7303, 180, 10.0000, 16.7687, 36.14005365, -86.77199359, 'CANOPY-02', 'E', true, 'B'),
  ('NASH-L2-STALL-13', 'L2-13', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 E-13', 237.0522, 111.4616, 180, 10.0000, 16.7687, 36.14000621, -86.77199359, 'CANOPY-02', 'E', true, 'B'),
  ('NASH-L2-STALL-14', 'L2-14', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 E-14', 237.0522, 94.1929, 180, 10.0000, 16.7687, 36.13995877, -86.77199359, 'CANOPY-02', 'E', true, 'B'),
  ('NASH-L2-STALL-15', 'L2-15', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-02 E-15', 237.0522, 76.9242, 180, 10.0000, 16.7687, 36.13991133, -86.77199359, 'CANOPY-02', 'E', true, 'B'),
  ('NASH-L2-STALL-16', 'L2-16', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 W-16', 288.8583, 188.3858, 180, 10.0000, 15.6698, 36.14021754, -86.77181735, 'CANOPY-03', 'W', true, 'C'),
  ('NASH-L2-STALL-17', 'L2-17', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 W-17', 288.8583, 172.2160, 180, 10.0000, 15.6698, 36.14017312, -86.77181735, 'CANOPY-03', 'W', true, 'C'),
  ('NASH-L2-STALL-18', 'L2-18', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 W-18', 288.8583, 156.0463, 180, 10.0000, 15.6698, 36.14012870, -86.77181735, 'CANOPY-03', 'W', true, 'C'),
  ('NASH-L2-STALL-19', 'L2-19', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 W-19', 288.8583, 139.8765, 180, 10.0000, 15.6698, 36.14008428, -86.77181735, 'CANOPY-03', 'W', true, 'C'),
  ('NASH-L2-STALL-20', 'L2-20', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 W-20', 288.8583, 123.7067, 180, 10.0000, 15.6698, 36.14003985, -86.77181735, 'CANOPY-03', 'W', true, 'C'),
  ('NASH-L2-STALL-26', 'L2-21', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 W-26', 288.8583, 107.5369, 180, 10.0000, 15.6698, 36.13999543, -86.77181735, 'CANOPY-03', 'W', true, 'C'),
  ('NASH-L2-STALL-27', 'L2-22', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 W-27', 288.8583, 91.3671, 180, 10.0000, 15.6698, 36.13995101, -86.77181735, 'CANOPY-03', 'W', true, 'C'),
  ('NASH-L2-STALL-28', 'L2-23', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 W-28', 288.8583, 75.1973, 180, 10.0000, 15.6698, 36.13990659, -86.77181735, 'CANOPY-03', 'W', true, 'C'),
  ('NASH-L2-STALL-29', 'L2-24', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 E-29', 310.8366, 180.5364, 180, 10.0000, 16.7687, 36.14019598, -86.77174259, 'CANOPY-03', 'E', true, 'C'),
  ('NASH-L2-STALL-30', 'L2-25', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 E-30', 310.8366, 163.2677, 180, 10.0000, 16.7687, 36.14014854, -86.77174259, 'CANOPY-03', 'E', true, 'C'),
  ('NASH-L2-STALL-31', 'L2-26', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 E-31', 310.8366, 145.9990, 180, 10.0000, 16.7687, 36.14010110, -86.77174259, 'CANOPY-03', 'E', true, 'C'),
  ('NASH-L2-STALL-32', 'L2-27', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 E-32', 310.8366, 128.7303, 180, 10.0000, 16.7687, 36.14005365, -86.77174259, 'CANOPY-03', 'E', true, 'C'),
  ('NASH-L2-STALL-33', 'L2-28', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 E-33', 310.8366, 111.4616, 180, 10.0000, 16.7687, 36.14000621, -86.77174259, 'CANOPY-03', 'E', true, 'C'),
  ('NASH-L2-STALL-34', 'L2-29', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 E-34', 310.8366, 94.1929, 180, 10.0000, 16.7687, 36.13995877, -86.77174259, 'CANOPY-03', 'E', true, 'C'),
  ('NASH-L2-STALL-35', 'L2-30', 'l2', 'charging', 'l2_zone', NULL, 'CANOPY-03 E-35', 310.8366, 76.9242, 180, 10.0000, 16.7687, 36.13991133, -86.77174259, 'CANOPY-03', 'E', true, 'C'),
  ('NASH-STG-B001', 'TW-1', 'staging', 'staging', 'staging_buffer', 'temp', 'Staging Buffer 001', 357.9331, 188.3858, 270, 8.9193, 18.0000, 36.14021754, -86.77158237, NULL, NULL, false, 'TW'),
  ('NASH-STG-B002', 'TW-2', 'staging', 'staging', 'staging_buffer', 'temp', 'Staging Buffer 002', 357.9331, 178.9665, 270, 8.9193, 18.0000, 36.14019167, -86.77158237, NULL, NULL, false, 'TW'),
  ('NASH-STG-B003', 'TW-3', 'staging', 'staging', 'staging_buffer', 'temp', 'Staging Buffer 003', 357.9331, 169.5472, 270, 8.9193, 18.0000, 36.14016579, -86.77158237, NULL, NULL, false, 'TW'),
  ('NASH-STG-B004', 'TW-4', 'staging', 'staging', 'staging_buffer', 'temp', 'Staging Buffer 004', 357.9331, 160.1280, 270, 8.9193, 18.0000, 36.14013991, -86.77158237, NULL, NULL, false, 'TW'),
  ('NASH-STG-B005', 'TW-5', 'staging', 'staging', 'staging_buffer', 'temp', 'Staging Buffer 005', 357.9331, 150.7087, 270, 8.9193, 18.0000, 36.14011403, -86.77158237, NULL, NULL, false, 'TW'),
  ('NASH-STG-B006', 'TW-6', 'staging', 'staging', 'staging_buffer', 'temp', 'Staging Buffer 006', 357.9331, 141.2894, 270, 8.9193, 18.0000, 36.14008816, -86.77158237, NULL, NULL, false, 'TW'),
  ('NASH-STG-B007', 'TW-7', 'staging', 'staging', 'staging_buffer', 'temp', 'Staging Buffer 007', 357.9331, 131.8701, 270, 8.9193, 18.0000, 36.14006228, -86.77158237, NULL, NULL, false, 'TW'),
  ('NASH-STG-B008', 'TW-8', 'staging', 'staging', 'staging_buffer', 'temp', 'Staging Buffer 008', 357.9331, 122.4508, 270, 8.9193, 18.0000, 36.14003640, -86.77158237, NULL, NULL, false, 'TW'),
  ('NASH-STG-B009', 'TW-9', 'staging', 'staging', 'staging_buffer', 'temp', 'Staging Buffer 009', 357.9331, 113.0315, 270, 8.9193, 18.0000, 36.14001053, -86.77158237, NULL, NULL, false, 'TW'),
  ('NASH-STG-B010', 'TW-10', 'staging', 'staging', 'staging_buffer', 'temp', 'Staging Buffer 010', 357.9331, 103.6122, 270, 8.9193, 18.0000, 36.13998465, -86.77158237, NULL, NULL, false, 'TW'),
  ('NASH-STG-B011', 'TW-11', 'staging', 'staging', 'staging_buffer', 'temp', 'Staging Buffer 011', 357.9331, 94.1929, 270, 8.9193, 18.0000, 36.13995877, -86.77158237, NULL, NULL, false, 'TW'),
  ('NASH-STG-B012', 'TW-12', 'staging', 'staging', 'staging_buffer', 'temp', 'Staging Buffer 012', 357.9331, 84.7736, 270, 8.9193, 18.0000, 36.13993289, -86.77158237, NULL, NULL, false, 'TW'),
  ('NASH-STG-B013', 'TW-13', 'staging', 'staging', 'staging_buffer', 'temp', 'Staging Buffer 013', 357.9331, 75.3543, 270, 8.9193, 18.0000, 36.13990702, -86.77158237, NULL, NULL, false, 'TW'),
  ('NASH-STG-E001', 'E-1', 'staging', 'staging', 'staging_east', 'long', 'Staging East 001', 437.2121, 251.1811, 90, 8.4483, 18.0000, 36.14039006, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E002', 'E-2', 'staging', 'staging', 'staging_east', 'long', 'Staging East 002', 437.2121, 242.2328, 90, 8.4483, 18.0000, 36.14036547, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E003', 'E-3', 'staging', 'staging', 'staging_east', 'long', 'Staging East 003', 437.2121, 233.2844, 90, 8.4483, 18.0000, 36.14034089, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E004', 'E-4', 'staging', 'staging', 'staging_east', 'long', 'Staging East 004', 437.2121, 224.3361, 90, 8.4483, 18.0000, 36.14031631, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E005', 'E-5', 'staging', 'staging', 'staging_east', 'long', 'Staging East 005', 437.2121, 215.3878, 90, 8.4483, 18.0000, 36.14029172, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E006', 'E-6', 'staging', 'staging', 'staging_east', 'long', 'Staging East 006', 437.2121, 206.4395, 90, 8.4483, 18.0000, 36.14026714, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E007', 'E-7', 'staging', 'staging', 'staging_east', 'long', 'Staging East 007', 437.2121, 197.4911, 90, 8.4483, 18.0000, 36.14024256, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E008', 'E-8', 'staging', 'staging', 'staging_east', 'long', 'Staging East 008', 437.2121, 188.5428, 90, 8.4483, 18.0000, 36.14021797, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E009', 'E-9', 'staging', 'staging', 'staging_east', 'long', 'Staging East 009', 437.2121, 179.5945, 90, 8.4483, 18.0000, 36.14019339, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E010', 'E-10', 'staging', 'staging', 'staging_east', 'long', 'Staging East 010', 437.2121, 170.6462, 90, 8.4483, 18.0000, 36.14016881, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E011', 'E-11', 'staging', 'staging', 'staging_east', 'long', 'Staging East 011', 437.2121, 161.6978, 90, 8.4483, 18.0000, 36.14014422, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E012', 'E-12', 'staging', 'staging', 'staging_east', 'long', 'Staging East 012', 437.2121, 152.7495, 90, 8.4483, 18.0000, 36.14011964, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E013', 'E-13', 'staging', 'staging', 'staging_east', 'long', 'Staging East 013', 437.2121, 143.8012, 90, 8.4483, 18.0000, 36.14009506, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E014', 'E-14', 'staging', 'staging', 'staging_east', 'long', 'Staging East 014', 437.2121, 134.8529, 90, 8.4483, 18.0000, 36.14007047, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E015', 'E-15', 'staging', 'staging', 'staging_east', 'long', 'Staging East 015', 437.2121, 125.9045, 90, 8.4483, 18.0000, 36.14004589, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E016', 'E-16', 'staging', 'staging', 'staging_east', 'long', 'Staging East 016', 437.2121, 116.9562, 90, 8.4483, 18.0000, 36.14002131, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E017', 'E-17', 'staging', 'staging', 'staging_east', 'long', 'Staging East 017', 437.2121, 108.0079, 90, 8.4483, 18.0000, 36.13999672, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E018', 'E-18', 'staging', 'staging', 'staging_east', 'long', 'Staging East 018', 437.2121, 99.0595, 90, 8.4483, 18.0000, 36.13997214, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E019', 'E-19', 'staging', 'staging', 'staging_east', 'long', 'Staging East 019', 437.2121, 90.1112, 90, 8.4483, 18.0000, 36.13994756, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E020', 'E-20', 'staging', 'staging', 'staging_east', 'long', 'Staging East 020', 437.2121, 81.1629, 90, 8.4483, 18.0000, 36.13992297, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E021', 'E-21', 'staging', 'staging', 'staging_east', 'long', 'Staging East 021', 437.2121, 72.2146, 90, 8.4483, 18.0000, 36.13989839, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E022', 'E-22', 'staging', 'staging', 'staging_east', 'long', 'Staging East 022', 437.2121, 63.2662, 90, 8.4483, 18.0000, 36.13987381, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E023', 'E-23', 'staging', 'staging', 'staging_east', 'long', 'Staging East 023', 437.2121, 54.3179, 90, 8.4483, 18.0000, 36.13984923, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E024', 'E-24', 'staging', 'staging', 'staging_east', 'long', 'Staging East 024', 437.2121, 45.3696, 90, 8.4483, 18.0000, 36.13982464, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-E025', 'E-25', 'staging', 'staging', 'staging_east', 'long', 'Staging East 025', 437.2121, 36.4213, 90, 8.4483, 18.0000, 36.13980006, -86.77131268, NULL, NULL, true, 'E'),
  ('NASH-STG-I001', 'TE-1', 'staging', 'inspection', 'arrival_inspection', 'temp', 'Arrival Inspection 001', 398.7500, 188.3858, 90, 8.9193, 18.0000, 36.14021754, -86.77144352, NULL, NULL, false, 'TE'),
  ('NASH-STG-I002', 'TE-2', 'staging', 'inspection', 'arrival_inspection', 'temp', 'Arrival Inspection 002', 398.7500, 178.9665, 90, 8.9193, 18.0000, 36.14019167, -86.77144352, NULL, NULL, false, 'TE'),
  ('NASH-STG-I003', 'TE-3', 'staging', 'inspection', 'arrival_inspection', 'temp', 'Arrival Inspection 003', 398.7500, 169.5472, 90, 8.9193, 18.0000, 36.14016579, -86.77144352, NULL, NULL, false, 'TE'),
  ('NASH-STG-I004', 'TE-4', 'staging', 'inspection', 'arrival_inspection', 'temp', 'Arrival Inspection 004', 398.7500, 160.1280, 90, 8.9193, 18.0000, 36.14013991, -86.77144352, NULL, NULL, false, 'TE'),
  ('NASH-STG-I005', 'TE-5', 'staging', 'inspection', 'arrival_inspection', 'temp', 'Arrival Inspection 005', 398.7500, 150.7087, 90, 8.9193, 18.0000, 36.14011403, -86.77144352, NULL, NULL, false, 'TE'),
  ('NASH-STG-I006', 'TE-6', 'staging', 'inspection', 'arrival_inspection', 'temp', 'Arrival Inspection 006', 398.7500, 141.2894, 90, 8.9193, 18.0000, 36.14008816, -86.77144352, NULL, NULL, false, 'TE'),
  ('NASH-STG-I007', 'TE-7', 'staging', 'inspection', 'arrival_inspection', 'temp', 'Arrival Inspection 007', 398.7500, 131.8701, 90, 8.9193, 18.0000, 36.14006228, -86.77144352, NULL, NULL, false, 'TE'),
  ('NASH-STG-I008', 'TE-8', 'staging', 'inspection', 'arrival_inspection', 'temp', 'Arrival Inspection 008', 398.7500, 122.4508, 90, 8.9193, 18.0000, 36.14003640, -86.77144352, NULL, NULL, false, 'TE'),
  ('NASH-STG-I009', 'TE-9', 'staging', 'inspection', 'arrival_inspection', 'temp', 'Arrival Inspection 009', 398.7500, 113.0315, 90, 8.9193, 18.0000, 36.14001053, -86.77144352, NULL, NULL, false, 'TE'),
  ('NASH-STG-I010', 'TE-10', 'staging', 'inspection', 'arrival_inspection', 'temp', 'Arrival Inspection 010', 398.7500, 103.6122, 90, 8.9193, 18.0000, 36.13998465, -86.77144352, NULL, NULL, false, 'TE'),
  ('NASH-STG-I011', 'TE-11', 'staging', 'inspection', 'arrival_inspection', 'temp', 'Arrival Inspection 011', 398.7500, 94.1929, 90, 8.9193, 18.0000, 36.13995877, -86.77144352, NULL, NULL, false, 'TE'),
  ('NASH-STG-I012', 'TE-12', 'staging', 'inspection', 'arrival_inspection', 'temp', 'Arrival Inspection 012', 398.7500, 84.7736, 90, 8.9193, 18.0000, 36.13993289, -86.77144352, NULL, NULL, false, 'TE'),
  ('NASH-STG-I013', 'TE-13', 'staging', 'inspection', 'arrival_inspection', 'temp', 'Arrival Inspection 013', 398.7500, 75.3543, 90, 8.9193, 18.0000, 36.13990702, -86.77144352, NULL, NULL, false, 'TE'),
  ('NASH-STG-N001', 'N1-1', 'staging', 'staging', 'staging_north', 'long', 'Staging North 001', 348.5138, 266.8799, 0, 8.9193, 18.0000, 36.14043319, -86.77161442, NULL, NULL, false, 'N1'),
  ('NASH-STG-N002', 'N1-2', 'staging', 'staging', 'staging_north', 'long', 'Staging North 002', 357.9331, 266.8799, 0, 8.9193, 18.0000, 36.14043319, -86.77158237, NULL, NULL, false, 'N1'),
  ('NASH-STG-N003', 'N1-3', 'staging', 'staging', 'staging_north', 'long', 'Staging North 003', 367.3524, 266.8799, 0, 8.9193, 18.0000, 36.14043319, -86.77155033, NULL, NULL, false, 'N1'),
  ('NASH-STG-N004', 'N1-4', 'staging', 'staging', 'staging_north', 'long', 'Staging North 004', 376.7717, 266.8799, 0, 8.9193, 18.0000, 36.14043319, -86.77151829, NULL, NULL, false, 'N1'),
  ('NASH-STG-N005', 'N1-5', 'staging', 'staging', 'staging_north', 'long', 'Staging North 005', 386.1909, 266.8799, 0, 8.9193, 18.0000, 36.14043319, -86.77148625, NULL, NULL, false, 'N1'),
  ('NASH-STG-N006', 'N1-6', 'staging', 'staging', 'staging_north', 'long', 'Staging North 006', 395.6102, 266.8799, 0, 8.9193, 18.0000, 36.14043319, -86.77145420, NULL, NULL, false, 'N1'),
  ('NASH-STG-N007', 'N1-7', 'staging', 'staging', 'staging_north', 'long', 'Staging North 007', 405.0295, 266.8799, 0, 8.9193, 18.0000, 36.14043319, -86.77142216, NULL, NULL, false, 'N1'),
  ('NASH-STG-S001', 'S1-1', 'staging', 'staging', 'staging_south', 'long', 'Staging South 001', 28.2579, 14.1289, 0, 9.0824, 18.0000, 36.13973882, -86.77270387, NULL, NULL, true, 'S1'),
  ('NASH-STG-S002', 'S1-2', 'staging', 'staging', 'staging_south', 'long', 'Staging South 002', 38.3051, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77266969, NULL, NULL, true, 'S1'),
  ('NASH-STG-S003', 'S1-3', 'staging', 'staging', 'staging_south', 'long', 'Staging South 003', 48.3524, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77263551, NULL, NULL, true, 'S1'),
  ('NASH-STG-S004', 'S1-4', 'staging', 'staging', 'staging_south', 'long', 'Staging South 004', 58.3996, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77260133, NULL, NULL, true, 'S1'),
  ('NASH-STG-S005', 'S1-5', 'staging', 'staging', 'staging_south', 'long', 'Staging South 005', 68.4469, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77256716, NULL, NULL, true, 'S1'),
  ('NASH-STG-S006', 'S1-6', 'staging', 'staging', 'staging_south', 'long', 'Staging South 006', 78.4941, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77253298, NULL, NULL, true, 'S1'),
  ('NASH-STG-S007', 'S1-7', 'staging', 'staging', 'staging_south', 'long', 'Staging South 007', 88.5413, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77249880, NULL, NULL, true, 'S1'),
  ('NASH-STG-S008', 'S1-8', 'staging', 'staging', 'staging_south', 'long', 'Staging South 008', 98.5886, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77246462, NULL, NULL, true, 'S1'),
  ('NASH-STG-S009', 'S1-9', 'staging', 'staging', 'staging_south', 'long', 'Staging South 009', 108.6358, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77243044, NULL, NULL, true, 'S1'),
  ('NASH-STG-S010', 'S1-10', 'staging', 'staging', 'staging_south', 'long', 'Staging South 010', 118.6831, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77239626, NULL, NULL, true, 'S1'),
  ('NASH-STG-S011', 'S1-11', 'staging', 'staging', 'staging_south', 'long', 'Staging South 011', 128.7303, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77236208, NULL, NULL, true, 'S1'),
  ('NASH-STG-S012', 'S2-1', 'staging', 'staging', 'staging_south', 'long', 'Staging South 012', 166.4075, 14.1289, 0, 10.0000, 18.0000, 36.13973882, -86.77223391, NULL, NULL, true, 'S2'),
  ('NASH-STG-S013', 'S2-2', 'staging', 'staging', 'staging_south', 'long', 'Staging South 013', 177.2397, 14.1289, 0, 10.0000, 18.0000, 36.13973882, -86.77219706, NULL, NULL, true, 'S2'),
  ('NASH-STG-S014', 'S2-3', 'staging', 'staging', 'staging_south', 'long', 'Staging South 014', 188.0719, 14.1289, 0, 10.0000, 18.0000, 36.13973882, -86.77216021, NULL, NULL, true, 'S2'),
  ('NASH-STG-S015', 'S2-4', 'staging', 'staging', 'staging_south', 'long', 'Staging South 015', 198.9040, 14.1289, 0, 10.0000, 18.0000, 36.13973882, -86.77212336, NULL, NULL, true, 'S2'),
  ('NASH-STG-S016', 'S2-5', 'staging', 'staging', 'staging_south', 'long', 'Staging South 016', 209.7362, 14.1289, 0, 10.0000, 18.0000, 36.13973882, -86.77208651, NULL, NULL, true, 'S2'),
  ('NASH-STG-S017', 'S2-6', 'staging', 'staging', 'staging_south', 'long', 'Staging South 017', 220.5684, 14.1289, 0, 10.0000, 18.0000, 36.13973882, -86.77204966, NULL, NULL, true, 'S2'),
  ('NASH-STG-S018', 'S2-7', 'staging', 'staging', 'staging_south', 'long', 'Staging South 018', 231.4006, 14.1289, 0, 10.0000, 18.0000, 36.13973882, -86.77201282, NULL, NULL, true, 'S2'),
  ('NASH-STG-S019', 'S2-8', 'staging', 'staging', 'staging_south', 'long', 'Staging South 019', 242.2328, 14.1289, 0, 10.0000, 18.0000, 36.13973882, -86.77197597, NULL, NULL, true, 'S2'),
  ('NASH-STG-S020', 'S2-9', 'staging', 'staging', 'staging_south', 'long', 'Staging South 020', 253.0650, 14.1289, 0, 10.0000, 18.0000, 36.13973882, -86.77193912, NULL, NULL, true, 'S2'),
  ('NASH-STG-S021', 'S2-10', 'staging', 'staging', 'staging_south', 'long', 'Staging South 021', 263.8971, 14.1289, 0, 10.0000, 18.0000, 36.13973882, -86.77190227, NULL, NULL, true, 'S2'),
  ('NASH-STG-S022', 'S2-11', 'staging', 'staging', 'staging_south', 'long', 'Staging South 022', 274.7293, 14.1289, 0, 10.0000, 18.0000, 36.13973882, -86.77186542, NULL, NULL, true, 'S2'),
  ('NASH-STG-S023', 'S2-12', 'staging', 'staging', 'staging_south', 'long', 'Staging South 023', 285.5615, 14.1289, 0, 10.0000, 18.0000, 36.13973882, -86.77182857, NULL, NULL, true, 'S2'),
  ('NASH-STG-S024', 'S3-1', 'staging', 'staging', 'staging_south', 'long', 'Staging South 024', 323.3957, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77169986, NULL, NULL, true, 'S3'),
  ('NASH-STG-S025', 'S3-2', 'staging', 'staging', 'staging_south', 'long', 'Staging South 025', 333.4429, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77166568, NULL, NULL, true, 'S3'),
  ('NASH-STG-S026', 'S3-3', 'staging', 'staging', 'staging_south', 'long', 'Staging South 026', 343.4902, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77163151, NULL, NULL, true, 'S3'),
  ('NASH-STG-S027', 'S3-4', 'staging', 'staging', 'staging_south', 'long', 'Staging South 027', 353.5374, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77159733, NULL, NULL, true, 'S3'),
  ('NASH-STG-S028', 'S3-5', 'staging', 'staging', 'staging_south', 'long', 'Staging South 028', 363.5846, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77156315, NULL, NULL, true, 'S3'),
  ('NASH-STG-S029', 'S3-6', 'staging', 'staging', 'staging_south', 'long', 'Staging South 029', 373.6319, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77152897, NULL, NULL, true, 'S3'),
  ('NASH-STG-S030', 'S3-7', 'staging', 'staging', 'staging_south', 'long', 'Staging South 030', 383.6791, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77149479, NULL, NULL, true, 'S3'),
  ('NASH-STG-S031', 'S3-8', 'staging', 'staging', 'staging_south', 'long', 'Staging South 031', 393.7264, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77146061, NULL, NULL, true, 'S3'),
  ('NASH-STG-S032', 'S3-9', 'staging', 'staging', 'staging_south', 'long', 'Staging South 032', 403.7736, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77142643, NULL, NULL, true, 'S3'),
  ('NASH-STG-S033', 'S3-10', 'staging', 'staging', 'staging_south', 'long', 'Staging South 033', 413.8209, 14.1289, 0, 9.5472, 18.0000, 36.13973882, -86.77139225, NULL, NULL, true, 'S3'),
  ('NASH-STG-W001', 'W-1', 'staging', 'staging', 'staging_west', 'long', 'Staging West 001', 14.9139, 232.3425, 90, 8.4483, 18.0000, 36.14033830, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W002', 'W-2', 'staging', 'staging', 'staging_west', 'long', 'Staging West 002', 14.9139, 223.3942, 90, 8.4483, 18.0000, 36.14031372, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W003', 'W-3', 'staging', 'staging', 'staging_west', 'long', 'Staging West 003', 14.9139, 214.4459, 90, 8.4483, 18.0000, 36.14028914, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W004', 'W-4', 'staging', 'staging', 'staging_west', 'long', 'Staging West 004', 14.9139, 205.4975, 90, 8.4483, 18.0000, 36.14026455, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W005', 'W-5', 'staging', 'staging', 'staging_west', 'long', 'Staging West 005', 14.9139, 196.5492, 90, 8.4483, 18.0000, 36.14023997, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W006', 'W-6', 'staging', 'staging', 'staging_west', 'long', 'Staging West 006', 14.9139, 187.6009, 90, 8.4483, 18.0000, 36.14021539, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W007', 'W-7', 'staging', 'staging', 'staging_west', 'long', 'Staging West 007', 14.9139, 178.6526, 90, 8.4483, 18.0000, 36.14019080, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W008', 'W-8', 'staging', 'staging', 'staging_west', 'long', 'Staging West 008', 14.9139, 169.7042, 90, 8.4483, 18.0000, 36.14016622, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W009', 'W-9', 'staging', 'staging', 'staging_west', 'long', 'Staging West 009', 14.9139, 160.7559, 90, 8.4483, 18.0000, 36.14014164, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W010', 'W-10', 'staging', 'staging', 'staging_west', 'long', 'Staging West 010', 14.9139, 151.8076, 90, 8.4483, 18.0000, 36.14011705, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W011', 'W-11', 'staging', 'staging', 'staging_west', 'long', 'Staging West 011', 14.9139, 142.8593, 90, 8.4483, 18.0000, 36.14009247, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W012', 'W-12', 'staging', 'staging', 'staging_west', 'long', 'Staging West 012', 14.9139, 133.9109, 90, 8.4483, 18.0000, 36.14006789, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W013', 'W-13', 'staging', 'staging', 'staging_west', 'long', 'Staging West 013', 14.9139, 124.9626, 90, 8.4483, 18.0000, 36.14004330, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W014', 'W-14', 'staging', 'staging', 'staging_west', 'long', 'Staging West 014', 14.9139, 116.0143, 90, 8.4483, 18.0000, 36.14001872, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W015', 'W-15', 'staging', 'staging', 'staging_west', 'long', 'Staging West 015', 14.9139, 107.0659, 90, 8.4483, 18.0000, 36.13999414, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W016', 'W-16', 'staging', 'staging', 'staging_west', 'long', 'Staging West 016', 14.9139, 98.1176, 90, 8.4483, 18.0000, 36.13996955, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W017', 'W-17', 'staging', 'staging', 'staging_west', 'long', 'Staging West 017', 14.9139, 89.1693, 90, 8.4483, 18.0000, 36.13994497, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W018', 'W-18', 'staging', 'staging', 'staging_west', 'long', 'Staging West 018', 14.9139, 80.2210, 90, 8.4483, 18.0000, 36.13992039, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W019', 'W-19', 'staging', 'staging', 'staging_west', 'long', 'Staging West 019', 14.9139, 71.2726, 90, 8.4483, 18.0000, 36.13989580, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W020', 'W-20', 'staging', 'staging', 'staging_west', 'long', 'Staging West 020', 14.9139, 62.3243, 90, 8.4483, 18.0000, 36.13987122, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W021', 'W-21', 'staging', 'staging', 'staging_west', 'long', 'Staging West 021', 14.9139, 53.3760, 90, 8.4483, 18.0000, 36.13984664, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W022', 'W-22', 'staging', 'staging', 'staging_west', 'long', 'Staging West 022', 14.9139, 44.4277, 90, 8.4483, 18.0000, 36.13982205, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W023', 'W-23', 'staging', 'staging', 'staging_west', 'long', 'Staging West 023', 14.9139, 35.4793, 90, 8.4483, 18.0000, 36.13979747, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-STG-W024', 'W-24', 'staging', 'staging', 'staging_west', 'long', 'Staging West 024', 14.9139, 26.5310, 90, 8.4483, 17.5352, 36.13977289, -86.77274927, NULL, NULL, true, 'W'),
  ('NASH-SVC-01', 'SVC-01', 'service_bay', 'service', 'service', NULL, 'Service Bay 01', 178.9665, 259.0305, 0, 14.0000, 30.0000, 36.14041162, -86.77219119, NULL, NULL, true, 'BAY'),
  ('NASH-SVC-02', 'SVC-02', 'service_bay', 'service', 'service', NULL, 'Service Bay 02', 207.2244, 259.0305, 0, 14.0000, 30.0000, 36.14041162, -86.77209506, NULL, NULL, true, 'BAY'),
  ('NASH-WSH-01', 'WASH-01', 'wash_bay', 'wash', 'cleaning', NULL, 'Wash Bay 01', 254.3209, 259.0305, 0, 14.0000, 35.0000, 36.14041162, -86.77193484, NULL, NULL, true, 'BAY'),
  ('NASH-WSH-02', 'WASH-02', 'wash_bay', 'wash', 'cleaning', NULL, 'Wash Bay 02', 282.5787, 259.0305, 0, 14.0000, 35.0000, 36.14041162, -86.77183872, NULL, NULL, true, 'BAY'),
  ('NASH-WSH-03', 'WASH-03', 'wash_bay', 'wash', 'cleaning', NULL, 'Wash Bay 03', 310.8366, 259.0305, 0, 14.0000, 35.0000, 36.14041162, -86.77174259, NULL, NULL, true, 'BAY');

CREATE TEMP TABLE ottoq_layout_seed_structures (
  structure_code  text PRIMARY KEY,
  structure_kind  text    NOT NULL,
  title           text    NOT NULL,
  origin_x_ft     numeric NOT NULL,
  origin_y_ft     numeric NOT NULL,
  width_ft        numeric NOT NULL,
  length_ft       numeric NOT NULL,
  height_ft       numeric NOT NULL,
  rotation_deg    numeric NOT NULL,
  status          text    NOT NULL,
  absolute_lat    numeric NOT NULL,
  absolute_lng    numeric NOT NULL,
  properties      jsonb   NOT NULL
) ON COMMIT DROP;

INSERT INTO ottoq_layout_seed_structures
  (structure_code, structure_kind, title, origin_x_ft, origin_y_ft, width_ft, length_ft,
   height_ft, rotation_deg, status, absolute_lat, absolute_lng, properties)
VALUES
  ('BESS-COMPOUND', 'bess_compound', 'BESS + Transformer Compound', 9.4193, 248.0413, 78.4941, 56.5157, 12.0000, 0.0000, 'active', 36.14045906, -86.77263445, '{"fenced":true,"pad_material":"concrete","bess_power_kw":1500,"bess_energy_kwh":3000,"transformer_count":2}'::jsonb),
  ('CANOPY-01', 'solar_canopy', 'Solar Canopy A (DCFC)', 128.7303, 65.9350, 47.0965, 131.8701, 14.0000, 0.0000, 'active', 36.14006228, -86.77228197, '{"panel_count":288,"solar_kw_dc":180,"stall_capacity":10,"chargers":{"dcfc":10}}'::jsonb),
  ('CANOPY-02', 'solar_canopy', 'Solar Canopy B (L2)', 202.5148, 65.9350, 47.0965, 131.8701, 14.0000, 0.0000, 'active', 36.14006228, -86.77203097, '{"panel_count":288,"solar_kw_dc":180,"stall_capacity":15,"chargers":{"l2":15}}'::jsonb),
  ('CANOPY-03', 'solar_canopy', 'Solar Canopy C (L2)', 276.2992, 65.9350, 47.0965, 131.8701, 14.0000, 0.0000, 'active', 36.14006228, -86.77177997, '{"panel_count":288,"solar_kw_dc":180,"stall_capacity":15,"chargers":{"l2":15}}'::jsonb),
  ('CARPORT-E', 'metal_canopy', 'Solar Carport E (covered staging)', 427.0079, 26.6880, 20.4085, 230.7726, 12.0000, 0.0000, 'active', 36.14009031, -86.77131268, '{"covers":"perimeter_staging_stalls","purpose":"inspection-while-parked weather coverage","stall_count":25}'::jsonb),
  ('CARPORT-S1', 'metal_canopy', 'Solar Carport S1 (covered staging)', 21.9783, 3.1398, 113.0315, 20.4085, 12.0000, 0.0000, 'active', 36.13973666, -86.77253298, '{"covers":"perimeter_staging_stalls","purpose":"inspection-while-parked weather coverage","stall_count":11}'::jsonb),
  ('CARPORT-S2', 'metal_canopy', 'Solar Carport S2 (covered staging)', 160.1280, 3.1398, 131.8701, 20.4085, 12.0000, 0.0000, 'active', 36.13973666, -86.77203097, '{"covers":"perimeter_staging_stalls","purpose":"inspection-while-parked weather coverage","stall_count":12}'::jsonb),
  ('CARPORT-S3', 'metal_canopy', 'Solar Carport S3 (covered staging)', 317.1161, 3.1398, 106.7520, 20.4085, 12.0000, 0.0000, 'active', 36.13973666, -86.77153965, '{"covers":"perimeter_staging_stalls","purpose":"inspection-while-parked weather coverage","stall_count":10}'::jsonb),
  ('CARPORT-W', 'metal_canopy', 'Solar Carport W (covered staging)', 4.7096, 17.2687, 20.4085, 221.3533, 12.0000, 0.0000, 'active', 36.14005150, -86.77274927, '{"covers":"perimeter_staging_stalls","purpose":"inspection-while-parked weather coverage","stall_count":24}'::jsonb),
  ('FENCE-PERIMETER', 'fence_segment', 'Perimeter Security Fence', 0.0000, 0.0000, 452.1260, 313.9764, 8.0000, 0.0000, 'active', 36.14013129, -86.77203097, '{"material":"steel_pickets","height_ft":8,"lighting":"integrated_led"}'::jsonb),
  ('GATE-EGRESS', 'gate', 'Egress Gate (SW)', 136.5797, 0.0000, 21.9783, 9.4193, 8.0000, 0.0000, 'active', 36.13971294, -86.77229800, '{"direction":"out","controls":["alpr","barrier_arm"],"approach_point_ft":{"x":147.5689,"y":-14.1289}}'::jsonb),
  ('GATE-INGRESS', 'gate', 'Ingress Gate (SE)', 293.5679, 0.0000, 21.9783, 9.4193, 8.0000, 0.0000, 'active', 36.13971294, -86.77176395, '{"direction":"in","controls":["alpr","barrier_arm","intercom"],"approach_point_ft":{"x":304.5571,"y":-14.1289}}'::jsonb),
  ('LIGHT-01', 'lighting_pole', 'Site Light Pole 1', 47.0965, 229.2028, 1.5000, 1.5000, 28.2579, 0.0000, 'active', 36.14033174, -86.77263723, '{"fixture":"led_area","mount":"pole"}'::jsonb),
  ('LIGHT-02', 'lighting_pole', 'Site Light Pole 2', 47.0965, 135.0098, 1.5000, 1.5000, 28.2579, 0.0000, 'active', 36.14007297, -86.77263723, '{"fixture":"led_area","mount":"pole"}'::jsonb),
  ('LIGHT-03', 'lighting_pole', 'Site Light Pole 3', 47.0965, 50.2362, 1.5000, 1.5000, 28.2579, 0.0000, 'active', 36.13984007, -86.77263723, '{"fixture":"led_area","mount":"pole"}'::jsonb),
  ('LIGHT-04', 'lighting_pole', 'Site Light Pole 4', 411.3091, 229.2028, 1.5000, 1.5000, 28.2579, 0.0000, 'active', 36.14033174, -86.77139825, '{"fixture":"led_area","mount":"pole"}'::jsonb),
  ('LIGHT-05', 'lighting_pole', 'Site Light Pole 5', 411.3091, 135.0098, 1.5000, 1.5000, 28.2579, 0.0000, 'active', 36.14007297, -86.77139825, '{"fixture":"led_area","mount":"pole"}'::jsonb),
  ('LIGHT-06', 'lighting_pole', 'Site Light Pole 6', 411.3091, 50.2362, 1.5000, 1.5000, 28.2579, 0.0000, 'active', 36.13984007, -86.77139825, '{"fixture":"led_area","mount":"pole"}'::jsonb),
  ('LIGHT-07', 'lighting_pole', 'Site Light Pole 7', 152.2785, 62.7953, 1.5000, 1.5000, 28.2579, 0.0000, 'active', 36.13987457, -86.77227942, '{"fixture":"led_area","mount":"pole"}'::jsonb),
  ('LIGHT-08', 'lighting_pole', 'Site Light Pole 8', 226.0630, 62.7953, 1.5000, 1.5000, 28.2579, 0.0000, 'active', 36.13987457, -86.77202842, '{"fixture":"led_area","mount":"pole"}'::jsonb),
  ('LIGHT-09', 'lighting_pole', 'Site Light Pole 9', 299.8474, 62.7953, 1.5000, 1.5000, 28.2579, 0.0000, 'active', 36.13987457, -86.77177742, '{"fixture":"led_area","mount":"pole"}'::jsonb),
  ('LIGHT-10', 'lighting_pole', 'Site Light Pole 10', 72.2146, 309.2667, 1.5000, 1.5000, 28.2579, 0.0000, 'active', 36.14055169, -86.77255179, '{"fixture":"led_area","mount":"pole"}'::jsonb),
  ('LIGHT-11', 'lighting_pole', 'Site Light Pole 11', 332.8150, 277.8691, 1.5000, 1.5000, 28.2579, 0.0000, 'active', 36.14046544, -86.77166527, '{"fixture":"led_area","mount":"pole"}'::jsonb),
  ('OFFICE-01', 'office_building', 'Office Building + Attached Service Garage (2 bays)', 100.4724, 235.4823, 125.5906, 47.0965, 22.0000, 0.0000, 'active', 36.14041162, -86.77224459, '{"purpose":"admin+control_room+attached_service_garage","attached_service_garage":true,"encloses_stall_codes":["NASH-SVC-01","NASH-SVC-02"],"enclosure_intentional":true,"enclosure_confirmed_by":"founder","service_bays":[{"code":"NASH-SVC-01","kind":"mechanical_service","drive_through":true,"vehicle_capacity":2},{"code":"NASH-SVC-02","kind":"sensor_calibration","drive_through":true,"vehicle_capacity":2}]}'::jsonb),
  ('SIGN-OTTOYARD-FRONT', 'sign', 'OTTOYARD Front Wall Signage', 196.0630, 3.0000, 60.0000, 1.0000, 8.0000, 0.0000, 'active', 36.13970962, -86.77203097, '{"mount":"concrete_wall","illuminated":true}'::jsonb),
  ('WASH-01-BLDG', 'wash_building', 'Wash & Detail Building', 241.7618, 235.4823, 81.6339, 47.0965, 18.0000, 0.0000, 'active', 36.14041162, -86.77183872, '{"encloses_stall_codes":["NASH-WSH-01","NASH-WSH-02","NASH-WSH-03"],"enclosure_intentional":true,"wash_bays":[{"code":"NASH-WSH-01","drive_through":true},{"code":"NASH-WSH-02","drive_through":true},{"code":"NASH-WSH-03","drive_through":true}]}'::jsonb);

-- The divided ring, as the four straight runs the geometry guard tests. Emitted
-- from sitePlan.ts so the migration never hardcodes a lane coordinate -- the
-- single-source rule that applies to stalls applies to lanes too. Each run is a
-- lane BODY (one design vehicle wide) offset from its centreline; no stall
-- footprint may intersect one. Gate-approach diagonals are NOT modelled here.
CREATE TEMP TABLE ottoq_layout_seed_lanes (
  lane_name text PRIMARY KEY,
  x0 numeric NOT NULL, y0 numeric NOT NULL,
  x1 numeric NOT NULL, y1 numeric NOT NULL
) ON COMMIT DROP;

INSERT INTO ottoq_layout_seed_lanes (lane_name, x0, y0, x1, y1) VALUES
  ('west avenue northbound', 39.4008, 53.3760, 46.0008, 207.2244),
  ('west avenue southbound', 29.3535, 53.3760, 35.9535, 207.2244),
  ('east avenue northbound', 419.7047, 53.3760, 426.3047, 207.2244),
  ('east avenue southbound', 409.6574, 53.3760, 416.2574, 207.2244),
  ('north collector eastbound', 37.6772, 208.9480, 417.9811, 215.5480),
  ('north collector westbound', 37.6772, 198.9008, 417.9811, 205.5008),
  ('south collector eastbound', 37.6772, 55.0996, 417.9811, 61.6996),
  ('south collector westbound', 37.6772, 45.0524, 417.9811, 51.6524);

-- Staging codes that leave the layout. These rows are RE-HOMED, never deleted:
-- the row keeps its id, so every booking / state-log line / mission that points
-- at it survives. Staging is fungible, so the position is what changes.
CREATE TEMP TABLE ottoq_layout_seed_rehome (
  from_code text PRIMARY KEY,
  to_code   text NOT NULL UNIQUE,
  reason    text NOT NULL
) ON COMMIT DROP;

INSERT INTO ottoq_layout_seed_rehome (from_code, to_code, reason) VALUES
  ('NASH-STG-B014', 'NASH-STG-E018', 'staging_buffer resized 14 -> 13 to match temp block column TW'),
  ('NASH-STG-I014', 'NASH-STG-E019', 'arrival_inspection resized 14 -> 13 to match temp block column TE'),
  ('NASH-STG-N008', 'NASH-STG-E020', 'north apron kept clear for pull-through bay-rear maneuvering; run N1 holds 7'),
  ('NASH-STG-N009', 'NASH-STG-E021', 'north apron kept clear for pull-through bay-rear maneuvering; run N1 holds 7'),
  ('NASH-STG-N010', 'NASH-STG-E022', 'north apron kept clear for pull-through bay-rear maneuvering; run N1 holds 7'),
  ('NASH-STG-N011', 'NASH-STG-E023', 'north apron kept clear for pull-through bay-rear maneuvering; run N1 holds 7'),
  ('NASH-STG-N012', 'NASH-STG-E024', 'north apron kept clear for pull-through bay-rear maneuvering; run N1 holds 7'),
  ('NASH-STG-N013', 'NASH-STG-E025', 'north apron kept clear for pull-through bay-rear maneuvering; run N1 holds 7'),
  ('NASH-STG-N014', 'NASH-STG-S020', 'north apron kept clear for pull-through bay-rear maneuvering; run N1 holds 7'),
  ('NASH-STG-N015', 'NASH-STG-S021', 'north apron kept clear for pull-through bay-rear maneuvering; run N1 holds 7'),
  ('NASH-STG-N016', 'NASH-STG-S022', 'north apron kept clear for pull-through bay-rear maneuvering; run N1 holds 7'),
  ('NASH-STG-N017', 'NASH-STG-S023', 'north apron kept clear for pull-through bay-rear maneuvering; run N1 holds 7'),
  ('NASH-STG-N018', 'NASH-STG-S024', 'north apron kept clear for pull-through bay-rear maneuvering; run N1 holds 7'),
  ('NASH-STG-N019', 'NASH-STG-S025', 'north apron kept clear for pull-through bay-rear maneuvering; run N1 holds 7');

-- Codes DELETED outright. Only rows referenced by NOTHING may appear here; the
-- migration re-counts all 17 foreign keys at apply time and RAISEs on any hit.
CREATE TEMP TABLE ottoq_layout_seed_retired (
  stall_code text PRIMARY KEY,
  reason     text NOT NULL
) ON COMMIT DROP;

INSERT INTO ottoq_layout_seed_retired (stall_code, reason) VALUES
  ('NASH-L2-STALL-21', 'phantom L2 capacity: overran canopy 2 to the south, was among the overlapping pairs, one stacked on a staging space. Deleted not closed: ottoq_plan_overnight_wave counts stall_type=l2 with no status filter, so a closed row would keep broadcasting capacity. Provably unreferenced across all 17 FK columns.'),
  ('NASH-L2-STALL-22', 'phantom L2 capacity: overran canopy 2 to the south, was among the overlapping pairs, one stacked on a staging space. Deleted not closed: ottoq_plan_overnight_wave counts stall_type=l2 with no status filter, so a closed row would keep broadcasting capacity. Provably unreferenced across all 17 FK columns.'),
  ('NASH-L2-STALL-23', 'phantom L2 capacity: overran canopy 2 to the south, was among the overlapping pairs, one stacked on a staging space. Deleted not closed: ottoq_plan_overnight_wave counts stall_type=l2 with no status filter, so a closed row would keep broadcasting capacity. Provably unreferenced across all 17 FK columns.'),
  ('NASH-L2-STALL-24', 'phantom L2 capacity: overran canopy 2 to the south, was among the overlapping pairs, one stacked on a staging space. Deleted not closed: ottoq_plan_overnight_wave counts stall_type=l2 with no status filter, so a closed row would keep broadcasting capacity. Provably unreferenced across all 17 FK columns.'),
  ('NASH-L2-STALL-25', 'phantom L2 capacity: overran canopy 2 to the south, was among the overlapping pairs, one stacked on a staging space. Deleted not closed: ottoq_plan_overnight_wave counts stall_type=l2 with no status filter, so a closed row would keep broadcasting capacity. Provably unreferenced across all 17 FK columns.');

CREATE TEMP TABLE ottoq_layout_seed_retired_structures (
  structure_code text PRIMARY KEY,
  reason         text NOT NULL
) ON COMMIT DROP;

INSERT INTO ottoq_layout_seed_retired_structures (structure_code, reason) VALUES
  ('CANOPY-04', 'the renderer has 3 canopies, not 4; canopy 4 sheltered no chargers. Row RETAINED (never dropped) and marked decommissioned; its geometry stays in the superseded pre-0010 frame and is void. ottoq_canopy_state is DELIBERATELY untouched, so solar output does not change.'),
  ('METAL-CANOPY-PERIM', 'replaced by five real carports (CARPORT-W/E/S1/S2/S3). This row claimed to cover 100 stalls with width_ft and length_ft both NULL.');


-- ============================================================================
-- <<< SEED END
-- ============================================================================


-- ============================================================================
-- SECTION 4 -- SEED INTEGRITY (md5 guard)
--
-- The generator prints this hash. If section 3 has been hand-edited -- a nudged
-- coordinate, a pasted row, a deleted line -- the hash changes and the apply stops
-- here, before anything is written. The whole point of a generated seed is that
-- the generator, not a person, decides where the stalls are.
-- ============================================================================

DO $mig$
DECLARE
  v_expected CONSTANT text := '89943752f32f98da4ef80b6baedb3174';
  v_actual   text;
  v_n        bigint;
BEGIN
  SELECT count(*) INTO v_n FROM ottoq_layout_seed_stalls;
  IF v_n <> 160 THEN
    RAISE EXCEPTION '0010 ABORT: seed holds % stalls, expected 160.', v_n;
  END IF;

  SELECT md5(string_agg(
           stall_code || '|' || stall_type || '|' ||
           relative_x::text || '|' || relative_y::text || '|' ||
           heading_degrees::text || '|' ||
           stall_width_ft::text || '|' || stall_depth_ft::text,
           E'\n' ORDER BY stall_code))
    INTO v_actual
    FROM ottoq_layout_seed_stalls;

  IF v_actual IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION
      '0010 ABORT: seed md5 mismatch. Expected %, computed %. Section 3 has been '
      'edited by hand, or it was regenerated without updating this constant. '
      'Re-run  npm run layout:seed  in ottoyarddepot-sim and paste both the seed '
      'and the hash it prints.', v_expected, v_actual;
  END IF;

  RAISE NOTICE '0010 seed verified: 160 stalls, md5 %.', v_actual;
END
$mig$;


-- ============================================================================
-- SECTION 5 -- APPLY THE LAYOUT TO EVERY DEPOT
--
-- UUID strategy, restated where it happens:
--   * a stall_code that already exists KEEPS ITS id. stalls.id is pointed at by 17
--     foreign keys and by the OCPP charger link; re-keying would sever live
--     history. Existing rows are updated in place.
--   * a NEW stall_code gets uuid_generate_v5(depot_id, stall_code) -- deterministic,
--     stable across environments, never colliding across depots, so re-running this
--     migration produces exactly the same keys.
--
-- Columns deliberately NOT touched on existing rows: connector_type,
-- connector_max_kw, supported_inlet_types, ocpp_charger_id, status,
-- current_vehicle_id, the four reservation columns, distance_from_entrance,
-- fiducial_marker_id, uwb_beacon_id. Those are live wiring and operational state,
-- not geometry. equipment_config keeps charger_kw and only its canopy keys are
-- rewritten.
-- ============================================================================

DO $mig$
DECLARE
  v_depot   uuid;
  v_stalls  bigint := 0;
  v_del     bigint := 0;
  v_rehomed bigint := 0;
  v_struct  bigint := 0;
  v_lot_x   numeric;
  v_lot_y   numeric;
  v_acres   numeric;
  v_fk      record;
  v_hits    bigint;
  v_blocked text := '';
BEGIN
  SELECT width_ft, length_ft INTO v_lot_x, v_lot_y
    FROM ottoq_layout_seed_structures WHERE structure_code = 'FENCE-PERIMETER';
  v_acres := round((v_lot_x * v_lot_y) / 43560.0, 2);

  FOR v_depot IN
    SELECT DISTINCT depot_id FROM public.stalls ORDER BY 1
  LOOP
    ------------------------------------------------- 5.0 RE-HOME, don't retire
    -- Staging rows are fungible; their HISTORY is not. A staging code that leaves
    -- the layout keeps its row and its id -- and therefore its bookings, its
    -- vehicle_state_log lines, its missions -- and is simply renamed onto one of the
    -- staging positions this layout mints. 5.1 then moves it to the right place.
    --
    -- This runs BEFORE 5.1 so the upsert matches on the NEW code and updates the
    -- existing row in place, rather than minting a fresh uuid beside it.
    --
    -- Guarded: if a re-home target is somehow already present as its own row, the
    -- unique index on (depot_id, stall_code) raises rather than merging two rows.
    UPDATE public.stalls s
       SET stall_code = r.to_code,
           updated_at = now()
      FROM ottoq_layout_seed_rehome r
     WHERE s.depot_id = v_depot
       AND s.stall_code = r.from_code;
    GET DIAGNOSTICS v_rehomed = ROW_COUNT;

    ---------------------------------------------------------------- 5.1 stalls
    INSERT INTO public.stalls (
      id, depot_id, stall_code, stall_type, display_name,
      relative_x, relative_y, heading_degrees,
      absolute_lat, absolute_lng, absolute_point,
      zone, stall_kind, staging_role, canopy_code, covered,
      stall_width_ft, stall_depth_ft, equipment_config, updated_at)
    SELECT
      COALESCE(ex.id, extensions.uuid_generate_v5(v_depot, s.stall_code)),
      v_depot,
      s.stall_code,
      s.stall_type::stall_type,
      s.display_name,
      s.relative_x::double precision,
      s.relative_y::double precision,
      s.heading_degrees,
      s.absolute_lat::double precision,
      s.absolute_lng::double precision,
      public.ST_SetSRID(
        public.ST_MakePoint(s.absolute_lng::double precision,
                            s.absolute_lat::double precision), 4326)::geography,
      s.zone,
      s.stall_kind,
      s.staging_role,
      s.canopy_code,
      s.covered,
      s.stall_width_ft,
      s.stall_depth_ft,
      -- keep charger_kw and anything else already there; rewrite only the canopy keys
      (COALESCE(ex.equipment_config, '{}'::jsonb) - 'canopy_code' - 'canopy_side')
        || CASE WHEN s.canopy_code IS NULL THEN '{}'::jsonb
                ELSE jsonb_build_object('canopy_code', s.canopy_code,
                                        'canopy_side', s.canopy_side) END,
      now()
      FROM ottoq_layout_seed_stalls s
      LEFT JOIN public.stalls ex
             ON ex.depot_id = v_depot AND ex.stall_code = s.stall_code
    ON CONFLICT (depot_id, stall_code) DO UPDATE SET
      stall_type      = EXCLUDED.stall_type,
      display_name    = EXCLUDED.display_name,
      relative_x      = EXCLUDED.relative_x,
      relative_y      = EXCLUDED.relative_y,
      heading_degrees = EXCLUDED.heading_degrees,
      absolute_lat    = EXCLUDED.absolute_lat,
      absolute_lng    = EXCLUDED.absolute_lng,
      absolute_point  = EXCLUDED.absolute_point,
      zone            = EXCLUDED.zone,
      stall_kind      = EXCLUDED.stall_kind,
      staging_role    = EXCLUDED.staging_role,
      canopy_code     = EXCLUDED.canopy_code,
      covered         = EXCLUDED.covered,
      stall_width_ft  = EXCLUDED.stall_width_ft,
      stall_depth_ft  = EXCLUDED.stall_depth_ft,
      equipment_config = EXCLUDED.equipment_config,
      updated_at      = now();
    GET DIAGNOSTICS v_stalls = ROW_COUNT;

    -------------------------------------------------- 5.2 delete the phantom stalls
    -- Section 1.5 checked this before anything was written. Check it AGAIN, here,
    -- against the actual delete set, one statement before the delete fires.
    --
    -- Why twice: 1.5 runs against a hardcoded list at the top of the file, and the
    -- delete runs off ottoq_layout_seed_rehome/_retired, which are generated. If the
    -- two ever drift, the hardcoded check passes and the generated delete still eats
    -- a referenced row. This guard reads the SAME temp table the DELETE reads, so it
    -- cannot drift from it, and it walks every foreign key regardless of delete
    -- action -- CASCADE keys included, since those are the ones that fail silently.
    --
    -- This is the guard whose absence let 13 booking rows sit one apply away from
    -- being cascaded into nothing without an error.
    v_blocked := '';
    FOR v_fk IN
      SELECT n.nspname AS child_schema, cl.relname AS child_table,
             a.attname AS child_column, c.confdeltype AS del_action
        FROM pg_constraint c
        JOIN pg_class     cl ON cl.oid = c.conrelid
        JOIN pg_namespace n  ON n.oid  = cl.relnamespace
        JOIN unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord) ON true
        JOIN pg_attribute a  ON a.attrelid = c.conrelid AND a.attnum = k.attnum
       WHERE c.contype = 'f' AND c.confrelid = 'public.stalls'::regclass
       ORDER BY 1, 2, 3
    LOOP
      EXECUTE format(
        'SELECT count(*) FROM %I.%I ch
           JOIN public.stalls s ON s.id = ch.%I
           JOIN ottoq_layout_seed_retired r ON r.stall_code = s.stall_code
          WHERE s.depot_id = $1',
        v_fk.child_schema, v_fk.child_table, v_fk.child_column)
        INTO v_hits USING v_depot;
      IF v_hits > 0 THEN
        v_blocked := v_blocked || format('%s.%s.%s [on delete %s]: %s row(s); ',
          v_fk.child_schema, v_fk.child_table, v_fk.child_column,
          CASE v_fk.del_action WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL'
                               WHEN 'r' THEN 'RESTRICT' ELSE 'NO ACTION' END, v_hits);
      END IF;
    END LOOP;

    IF v_blocked <> '' THEN
      RAISE EXCEPTION
        '0010 ABORT at apply time, depot %: a stall in the delete set is referenced -- %. '
        'The whole transaction rolls back; nothing is written. Re-home this row instead '
        'of deleting it.', v_depot, v_blocked;
    END IF;

    -- Rows only -- no table, column or function is dropped anywhere in this file.
    DELETE FROM public.stalls s
      USING ottoq_layout_seed_retired r
      WHERE s.depot_id = v_depot AND s.stall_code = r.stall_code;
    GET DIAGNOSTICS v_del = ROW_COUNT;

    ------------------------------------------------------------ 5.3 structures
    INSERT INTO public.ottoq_site_structures (
      structure_id, depot_id, structure_code, structure_kind, title,
      origin_x_ft, origin_y_ft, width_ft, length_ft, height_ft, rotation_deg,
      absolute_lat, absolute_lng, properties, status, introduced_in)
    SELECT
      COALESCE(ex.structure_id, extensions.uuid_generate_v5(v_depot, t.structure_code)),
      v_depot, t.structure_code, t.structure_kind, t.title,
      t.origin_x_ft, t.origin_y_ft, t.width_ft, t.length_ft, t.height_ft, t.rotation_deg,
      t.absolute_lat, t.absolute_lng, t.properties, t.status, '0010_unify_depot_layout'
      FROM ottoq_layout_seed_structures t
      LEFT JOIN public.ottoq_site_structures ex
             ON ex.depot_id = v_depot AND ex.structure_code = t.structure_code
    ON CONFLICT (depot_id, structure_code) DO UPDATE SET
      structure_kind = EXCLUDED.structure_kind,
      title          = EXCLUDED.title,
      origin_x_ft    = EXCLUDED.origin_x_ft,
      origin_y_ft    = EXCLUDED.origin_y_ft,
      width_ft       = EXCLUDED.width_ft,
      length_ft      = EXCLUDED.length_ft,
      height_ft      = EXCLUDED.height_ft,
      rotation_deg   = EXCLUDED.rotation_deg,
      absolute_lat   = EXCLUDED.absolute_lat,
      absolute_lng   = EXCLUDED.absolute_lng,
      properties     = EXCLUDED.properties,
      status         = EXCLUDED.status,
      introduced_in  = EXCLUDED.introduced_in;
    GET DIAGNOSTICS v_struct = ROW_COUNT;

    -------------------------------------------- 5.4 retire structures WITHOUT deleting
    -- CANOPY-04 has no counterpart in the renderer, and METAL-CANOPY-PERIM is
    -- replaced by five real carports. Both rows are KEPT and marked decommissioned.
    -- Their geometry stays in the superseded pre-0010 frame and is recorded as void.
    UPDATE public.ottoq_site_structures t
       SET status     = 'decommissioned',
           properties = t.properties || jsonb_build_object(
             'retired_in',        '0010_unify_depot_layout',
             'retired_reason',    r.reason,
             'geometry_is_void',  true,
             'geometry_frame',    'superseded pre-0010 360x220ft frame')
      FROM ottoq_layout_seed_retired_structures r
     WHERE t.depot_id = v_depot
       AND t.structure_code = r.structure_code
       AND t.status <> 'decommissioned';

    ------------------------------------------------------- 5.5 the parcel itself
    -- The database recorded 360 x 220 ft / 1.82 acres. That record is what forced
    -- the overlaps. The real parcel is the renderer's.
    UPDATE public.depots d
       SET site_length_ft = v_lot_x,
           site_width_ft  = v_lot_y,
           site_acres     = v_acres,
           site_layout    = d.site_layout || jsonb_build_object(
             'l2_count',        (SELECT count(*) FROM ottoq_layout_seed_stalls WHERE stall_type = 'l2'),
             'dcfc_count',      (SELECT count(*) FROM ottoq_layout_seed_stalls WHERE stall_type = 'dcfc'),
             'staging_stalls',  (SELECT count(*) FROM ottoq_layout_seed_stalls WHERE stall_type = 'staging'),
             'wash_bays',       (SELECT count(*) FROM ottoq_layout_seed_stalls WHERE stall_type = 'wash_bay'),
             'service_bays',    (SELECT count(*) FROM ottoq_layout_seed_stalls WHERE stall_type = 'service_bay'),
             'solar_canopies',  (SELECT count(*) FROM ottoq_layout_seed_structures WHERE structure_kind = 'solar_canopy'),
             'gate_ingress',    'SE',
             'gate_egress',     'SW',
             'origin_corner',   'SW',
             'y_axis',          'north_positive',
             'units',           'feet; 1 render unit = 1.56988189 ft',
             'stall_dims_ft',   jsonb_build_object(
                                  'charging', '10x20 nominal, trimmed to run pitch',
                                  'parking',  '10x18 nominal, trimmed to run pitch',
                                  'service_bay', '14x30 ASSUMPTION',
                                  'wash_bay',    '14x35 ASSUMPTION'),
             'layout_source',   'ottoyarddepot-sim src/lib/sitePlan.ts via scripts/buildLayoutSeed.mjs',
             'layout_migration','0010_unify_depot_layout',
             'rendering_source','renderer sitePlan v2 (human reviewed)')
     WHERE d.id = v_depot;

    RAISE NOTICE '0010 depot %: % stall row(s) written, % re-homed (id + history kept), '
                 '% deleted, % structure row(s) written.',
      v_depot, v_stalls, v_rehomed, v_del, v_struct;
  END LOOP;
END
$mig$;


-- ============================================================================
-- SECTION 6 -- POST-APPLY ASSERTIONS
--
-- The same checks ottoyarddepot-sim/scripts/checkLayoutGeometry.mjs runs on the
-- seed, run here against what actually landed in the table. If the database does
-- not now hold a valid depot, this transaction rolls back.
--
-- The office/service-bay exemption is repeated here BY CODE, with the same note:
-- the two service bays are inside the office building ON PURPOSE. It is an
-- attached service garage and the founder confirmed it. Every other stall inside
-- every other structure is still a failure.
-- ============================================================================

DO $mig$
DECLARE
  v_bad      text;
  v_n        bigint;
  v_measured bigint;
  v_lot_x    numeric;
  v_lot_y    numeric;
BEGIN
  ------------------------------------------------------------------ 6.1 counts
  SELECT string_agg(msg, '; ' ORDER BY msg) INTO v_bad FROM (
    SELECT depot_id::text || ' ' || stall_type::text || '=' || count(*)::text AS msg
      FROM public.stalls
     GROUP BY depot_id, stall_type
    HAVING count(*) <> CASE stall_type::text
             WHEN 'staging' THEN 115 WHEN 'l2' THEN 30 WHEN 'dcfc' THEN 10
             WHEN 'wash_bay' THEN 3 WHEN 'service_bay' THEN 2 ELSE -1 END
  ) q;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0010 ABORT: stall counts wrong after apply -- %. Expected per '
                    'depot: staging 115, l2 30, dcfc 10, wash_bay 3, service_bay 2.', v_bad;
  END IF;

  SELECT string_agg(depot_id::text || '=' || n::text, ', ' ORDER BY depot_id) INTO v_bad
    FROM (SELECT depot_id, count(*) n FROM public.stalls GROUP BY depot_id) q
   WHERE n <> 160;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0010 ABORT: expected 160 stalls per depot, got %.', v_bad;
  END IF;

  --------------------------------------------------------- 6.2 nothing left NULL
  SELECT count(*), string_agg(stall_code, ', ' ORDER BY stall_code)
    INTO v_n, v_bad
    FROM public.stalls
   WHERE stall_width_ft IS NULL OR stall_depth_ft IS NULL
      OR relative_x IS NULL OR relative_y IS NULL
      OR absolute_lat IS NULL OR absolute_lng IS NULL OR absolute_point IS NULL
      OR stall_width_ft <= 0 OR stall_depth_ft <= 0;
  IF v_n > 0 THEN
    RAISE EXCEPTION '0010 ABORT: % stall(s) still missing dimensions or position: %',
      v_n, left(v_bad, 900);
  END IF;

  ------------------------------------------------------------ 6.3 zero overlaps
  -- A heading of 0 or 180 puts the vehicle's LENGTH on the y axis; 90 or 270 puts
  -- it on the x axis. Footprints are axis-aligned rectangles about the centre.
  WITH b AS (
    SELECT depot_id, stall_code,
           relative_x - (CASE WHEN heading_degrees IN (0,180) THEN stall_width_ft ELSE stall_depth_ft END)/2 AS x0,
           relative_x + (CASE WHEN heading_degrees IN (0,180) THEN stall_width_ft ELSE stall_depth_ft END)/2 AS x1,
           relative_y - (CASE WHEN heading_degrees IN (0,180) THEN stall_depth_ft ELSE stall_width_ft END)/2 AS y0,
           relative_y + (CASE WHEN heading_degrees IN (0,180) THEN stall_depth_ft ELSE stall_width_ft END)/2 AS y1
      FROM public.stalls)
  SELECT count(*), string_agg(a.stall_code || '<->' || c.stall_code, ', ' ORDER BY a.stall_code)
    INTO v_n, v_bad
    FROM b a JOIN b c ON c.depot_id = a.depot_id AND c.stall_code > a.stall_code
   WHERE LEAST(a.x1, c.x1) - GREATEST(a.x0, c.x0) > 0.000001
     AND LEAST(a.y1, c.y1) - GREATEST(a.y0, c.y0) > 0.000001;
  IF v_n > 0 THEN
    RAISE EXCEPTION '0010 ABORT: % overlapping stall pair(s) after apply: %',
      v_n, left(v_bad, 900);
  END IF;

  ----------------------------------------------- 6.4 nothing buried in a building
  WITH b AS (
    SELECT depot_id, stall_code,
           relative_x - (CASE WHEN heading_degrees IN (0,180) THEN stall_width_ft ELSE stall_depth_ft END)/2 AS x0,
           relative_x + (CASE WHEN heading_degrees IN (0,180) THEN stall_width_ft ELSE stall_depth_ft END)/2 AS x1,
           relative_y - (CASE WHEN heading_degrees IN (0,180) THEN stall_depth_ft ELSE stall_width_ft END)/2 AS y0,
           relative_y + (CASE WHEN heading_degrees IN (0,180) THEN stall_depth_ft ELSE stall_width_ft END)/2 AS y1
      FROM public.stalls)
  SELECT count(*), string_agg(b.stall_code || ' in ' || t.structure_code, ', ' ORDER BY b.stall_code)
    INTO v_n, v_bad
    FROM b
    JOIN public.ottoq_site_structures t
      ON t.depot_id = b.depot_id
     AND t.status = 'active'
     AND t.structure_kind IN ('office_building','service_building','wash_building',
                              'bess_compound','transformer','perimeter_wall','lighting_pole')
     AND LEAST(b.x1, t.origin_x_ft + t.width_ft)  - GREATEST(b.x0, t.origin_x_ft) > 0.000001
     AND LEAST(b.y1, t.origin_y_ft + t.length_ft) - GREATEST(b.y0, t.origin_y_ft) > 0.000001
   -- FOUNDER-CONFIRMED EXEMPTIONS, by stall code. The two service bays are inside
   -- the office building because it is an ATTACHED SERVICE GARAGE, and a wash bay
   -- is inside the wash building by definition. Nothing else is forgiven.
   WHERE NOT (b.stall_code IN ('NASH-SVC-01','NASH-SVC-02') AND t.structure_code = 'OFFICE-01')
     AND NOT (b.stall_code IN ('NASH-WSH-01','NASH-WSH-02','NASH-WSH-03') AND t.structure_code = 'WASH-01-BLDG');
  IF v_n > 0 THEN
    RAISE EXCEPTION '0010 ABORT: % stall(s) inside a structure footprint: %',
      v_n, left(v_bad, 900);
  END IF;

  -------------------------------------------------------------- 6.5 the parcel
  --
  -- HOLE CLOSED: this used to read ONE fence row with `LIMIT 1`, unscoped by depot.
  -- Exactly one FENCE-PERIMETER row existed and it belonged to depot 1111...; depot
  -- 2222... had no site_structures rows at all. So the fence check -- and the
  -- "nothing buried in a building" check above it, which INNER JOINs structures --
  -- read depot 1's geometry, found it good, and PASSED for a depot they had never
  -- looked at. A check that cannot see a depot must say NOT ESTABLISHED, not PASS.
  --
  -- Assert one fence per depot, and that every depot's fence is the right parcel.
  SELECT count(*) INTO v_n
    FROM public.depots d
   WHERE NOT EXISTS (
     SELECT 1 FROM public.ottoq_site_structures t
      WHERE t.depot_id = d.id AND t.structure_code = 'FENCE-PERIMETER');
  IF v_n > 0 THEN
    RAISE EXCEPTION
      '0010 ABORT: % depot(s) have no FENCE-PERIMETER row, so their geometry is NOT '
      'ESTABLISHED -- the fence and buried-stall checks cannot see them and must not '
      'report a pass.', v_n;
  END IF;

  SELECT count(*), string_agg(t.depot_id::text || ' has ' || c::text, ', ')
    INTO v_n, v_bad
    FROM (SELECT depot_id, count(*) AS c
            FROM public.ottoq_site_structures
           WHERE structure_code = 'FENCE-PERIMETER'
           GROUP BY depot_id) t
   WHERE t.c <> 1;
  IF v_n > 0 THEN
    RAISE EXCEPTION '0010 ABORT: % depot(s) do not have exactly one fence row: %', v_n, v_bad;
  END IF;

  SELECT count(*), string_agg(depot_id::text || ': ' ||
                              round(width_ft)::text || ' x ' || round(length_ft)::text, ', ')
    INTO v_n, v_bad
    FROM public.ottoq_site_structures
   WHERE structure_code = 'FENCE-PERIMETER'
     AND (round(width_ft) <> 452 OR round(length_ft) <> 314);
  IF v_n > 0 THEN
    RAISE EXCEPTION '0010 ABORT: % depot fence(s) are not 452 x 314 ft -- %', v_n, v_bad;
  END IF;

  SELECT width_ft, length_ft INTO v_lot_x, v_lot_y
    FROM public.ottoq_site_structures
   WHERE structure_code = 'FENCE-PERIMETER' LIMIT 1;

  SELECT count(*) INTO v_n FROM public.depots
   WHERE round(site_length_ft) <> 452 OR round(site_width_ft) <> 314;
  IF v_n > 0 THEN
    RAISE EXCEPTION '0010 ABORT: % depot(s) still record the old parcel size.', v_n;
  END IF;

  ------------------------------------------------------- 6.6 drivable aisle
  --
  -- HOLE CLOSED: minimum aisle width was measured ONLY source-side, in
  -- checkLayoutGeometry.mjs. That makes it ESTABLISHED for the seed file and NOT
  -- ESTABLISHED for the database -- which is the thing that actually drives the
  -- depot. Ported here so the database asserts it about itself.
  --
  -- Founder-accepted two-tier standard, NOT raised: >= 24 ft two-way (charging
  -- stalls, the ones the audit caught at 12 ft), >= 20 ft one-way (everything else).
  --
  -- Same method as the JS: a stall is reachable if ANY ONE of its four faces has a
  -- clear run, because this layout serves stalls from different sides (charging is
  -- gas-pump/sidestep, perimeter staging is served from behind, bays are
  -- pull-through). Measuring only out of the nose would flag the car parked ahead in
  -- the same column as a blockage. An obstruction counts only if it covers at least
  -- a design vehicle's width (6.6 ft) of the face -- a 1.5 ft light pole beside a
  -- 10 ft mouth does not stop a car.
  WITH b AS (
    SELECT depot_id, stall_code, stall_type,
           relative_x - (CASE WHEN heading_degrees IN (0,180) THEN stall_width_ft ELSE stall_depth_ft END)/2 AS x0,
           relative_x + (CASE WHEN heading_degrees IN (0,180) THEN stall_width_ft ELSE stall_depth_ft END)/2 AS x1,
           relative_y - (CASE WHEN heading_degrees IN (0,180) THEN stall_depth_ft ELSE stall_width_ft END)/2 AS y0,
           relative_y + (CASE WHEN heading_degrees IN (0,180) THEN stall_depth_ft ELSE stall_width_ft END)/2 AS y1
      FROM public.stalls),
  fence AS (
    SELECT depot_id, origin_x_ft AS fx0, origin_y_ft AS fy0,
           origin_x_ft + width_ft AS fx1, origin_y_ft + length_ft AS fy1
      FROM public.ottoq_site_structures WHERE structure_code = 'FENCE-PERIMETER'),
  solid AS (
    SELECT depot_id, structure_code AS code, origin_x_ft AS x0, origin_y_ft AS y0,
           origin_x_ft + width_ft AS x1, origin_y_ft + length_ft AS y1
      FROM public.ottoq_site_structures
     WHERE status = 'active'
       AND width_ft IS NOT NULL AND length_ft IS NOT NULL
       AND structure_kind NOT IN ('fence_segment','gate','lane_marker','sign',
                                  'solar_canopy','metal_canopy','lighting_pole')),
  -- every obstruction, as a rectangle, per depot
  obs AS (
    SELECT depot_id, stall_code AS code, x0, y0, x1, y1 FROM b
    UNION ALL
    SELECT depot_id, code, x0, y0, x1, y1 FROM solid),
  faces AS (
    SELECT b.*, f.name, f.dx, f.dy
      FROM b CROSS JOIN (VALUES ('E',1,0),('W',-1,0),('N',0,1),('S',0,-1)) AS f(name,dx,dy)),
  -- clear run on each face: distance to the fence, or to the nearest obstruction
  -- that covers >= a design vehicle's width of that face
  runs AS (
    SELECT fa.depot_id, fa.stall_code, fa.stall_type, fa.name,
           LEAST(
             -- fence
             CASE WHEN fa.dx = 1 THEN fe.fx1 - fa.x1 WHEN fa.dx = -1 THEN fa.x0 - fe.fx0
                  WHEN fa.dy = 1 THEN fe.fy1 - fa.y1 ELSE fa.y0 - fe.fy0 END,
             COALESCE((
               SELECT min(CASE WHEN fa.dx = 1 THEN o.x0 - fa.x1 WHEN fa.dx = -1 THEN fa.x0 - o.x1
                               WHEN fa.dy = 1 THEN o.y0 - fa.y1 ELSE fa.y0 - o.y1 END)
                 FROM obs o
                WHERE o.depot_id = fa.depot_id AND o.code <> fa.stall_code
                  -- covers enough of the face to actually stop a car
                  AND CASE WHEN fa.dx <> 0
                           THEN LEAST(fa.y1,o.y1) - GREATEST(fa.y0,o.y0)
                           ELSE LEAST(fa.x1,o.x1) - GREATEST(fa.x0,o.x0) END >= 6.6 - 1e-6
                  -- in front of the face, not behind it
                  AND CASE WHEN fa.dx = 1 THEN o.x0 - fa.x1 WHEN fa.dx = -1 THEN fa.x0 - o.x1
                           WHEN fa.dy = 1 THEN o.y0 - fa.y1 ELSE fa.y0 - o.y1 END >= -1e-6
             ), 1e9)) AS clear
      FROM faces fa JOIN fence fe ON fe.depot_id = fa.depot_id),
  best AS (
    SELECT depot_id, stall_code, stall_type, max(clear) AS clear
      FROM runs GROUP BY 1,2,3)
  -- Violations AND coverage in ONE pass. Coverage matters as much as the verdict:
  -- `runs` inner-joins the fence, so a depot with no fence row contributes zero rows
  -- and this check would report a clean pass for a depot it never looked at -- the
  -- same shape of hole 6.5 just closed. On the live pre-0010 database that was not
  -- hypothetical: this identical query measured 145 of 300 stalls, because only one
  -- depot had structures. 6.5 asserts a fence per depot; this asserts the consequence.
  SELECT count(*) FILTER (
           WHERE clear < CASE WHEN stall_type IN ('dcfc','l2') THEN 24.0 ELSE 20.0 END - 1e-6),
         string_agg(stall_code || ' (' || stall_type::text || '): ' ||
                    round(clear::numeric,1)::text || ' ft, needs ' ||
                    CASE WHEN stall_type IN ('dcfc','l2') THEN '24' ELSE '20' END, ', ' ORDER BY clear)
           FILTER (WHERE clear < CASE WHEN stall_type IN ('dcfc','l2') THEN 24.0 ELSE 20.0 END - 1e-6),
         -- count(clear), NOT count(*): a stall whose footprint is NULL yields a NULL
         -- clearance, which no `<` test can ever flag. That is an UNMEASURED stall,
         -- not a passing one, and it must fail coverage rather than slip through.
         count(clear)
    INTO v_n, v_bad, v_measured
    FROM best;

  IF v_measured <> (SELECT count(*) FROM public.stalls) THEN
    RAISE EXCEPTION
      '0010 ABORT: aisle check measured % stall(s) but the depots hold % -- clearance '
      'is NOT ESTABLISHED for the difference and must not report a pass.',
      v_measured, (SELECT count(*) FROM public.stalls);
  END IF;

  IF v_n > 0 THEN
    RAISE EXCEPTION
      '0010 ABORT: % stall(s) below the minimum drivable aisle (24 ft two-way for '
      'charging, 20 ft one-way otherwise): %', v_n, left(v_bad, 900);
  END IF;

  ------------------------------------------------- 6.7 stall vs LANE clearance
  --
  -- HOLE CLOSED: 6.3 tests stall-vs-stall and 6.4 tests stall-vs-structure, but
  -- nothing tested stall-vs-LANE. A travel lane could be routed straight through a
  -- parked car and every check above would still pass. That was live: the east
  -- avenue's northbound lane cut 2.41 ft into 18 E-column stalls on every pass,
  -- because EAST_AISLE_X sat at 275 with a 3.2-unit lane offset.
  --
  -- The renderer's fix (EAST_AISLE_X -> 272.25, centring the avenue in its corridor)
  -- moves no stall, so it does not change the seed md5. This check is what stops the
  -- geometry drifting back.
  --
  -- The lane rectangles come from ottoq_layout_seed_lanes, which the generator emits
  -- from sitePlan.ts. No lane coordinate is hardcoded here -- the single-source rule
  -- that applies to stalls applies to lanes too, so the renderer and this check
  -- cannot drift apart. Gate-approach diagonals are NOT modelled and are NOT claimed
  -- to be tested. Bar is OVERLAP: a lane may abut a stall -- that is what a parking
  -- aisle does -- but it must never cut into one.
  SELECT count(*) INTO v_n FROM ottoq_layout_seed_lanes;
  IF v_n <> 8 THEN
    RAISE EXCEPTION
      '0010 ABORT: expected 8 lane runs in the seed, found % -- stall-vs-lane clearance '
      'is NOT ESTABLISHED and must not report a pass.', v_n;
  END IF;

  WITH b AS (
    SELECT depot_id, stall_code,
           relative_x - (CASE WHEN heading_degrees IN (0,180) THEN stall_width_ft ELSE stall_depth_ft END)/2 AS x0,
           relative_x + (CASE WHEN heading_degrees IN (0,180) THEN stall_width_ft ELSE stall_depth_ft END)/2 AS x1,
           relative_y - (CASE WHEN heading_degrees IN (0,180) THEN stall_depth_ft ELSE stall_width_ft END)/2 AS y0,
           relative_y + (CASE WHEN heading_degrees IN (0,180) THEN stall_depth_ft ELSE stall_width_ft END)/2 AS y1
      FROM public.stalls)
  SELECT count(*), string_agg(b.stall_code || ' cuts ' || l.lane_name || ' by ' ||
           round(LEAST(LEAST(b.x1,l.x1)-GREATEST(b.x0,l.x0),
                       LEAST(b.y1,l.y1)-GREATEST(b.y0,l.y0))::numeric, 2)::text || ' ft',
           ', ' ORDER BY b.stall_code)
    INTO v_n, v_bad
    FROM b JOIN ottoq_layout_seed_lanes l
      ON LEAST(b.x1,l.x1) - GREATEST(b.x0,l.x0) > 1e-6
     AND LEAST(b.y1,l.y1) - GREATEST(b.y0,l.y0) > 1e-6;
  IF v_n > 0 THEN
    RAISE EXCEPTION
      '0010 ABORT: % stall/lane overlap(s) -- a travel lane cuts into a parked car: %',
      v_n, left(v_bad, 900);
  END IF;

  RAISE NOTICE '0010 OK: 160 stalls per depot, 0 overlaps, 0 buried stalls, '
               'parcel % x % ft. Layout unified.', round(v_lot_x), round(v_lot_y);
END
$mig$;


-- ============================================================================
-- VERIFICATION -- run these AFTER applying. Do not assume; measure.
-- ============================================================================
--
-- V1 -- THE SHAPE. Both depots, same answer.
--   SELECT depot_id, stall_type, count(*)
--     FROM public.stalls GROUP BY 1,2 ORDER BY 1,2;
--   EXPECT per depot: dcfc 10, l2 30, service_bay 2, staging 115, wash_bay 3 = 160.
--
-- V2 -- NOTHING BLANK ANY MORE. This is the row that used to be all NULLs.
--   SELECT count(*) FILTER (WHERE stall_width_ft IS NULL)  AS null_w,
--          count(*) FILTER (WHERE stall_depth_ft IS NULL)  AS null_d,
--          count(*) FILTER (WHERE absolute_point IS NULL)  AS null_point
--     FROM public.stalls;
--   EXPECT 0, 0, 0. absolute_point was NULL on all 300 rows before this file.
--
-- V3 -- THE OVERLAPS ARE GONE. Section 6.3 asserted it; prove it independently.
--   Re-run the query in section 6.3 as a plain SELECT. EXPECT 0 rows.
--
-- V4 -- THE UNIT CONVERSION DID NOT INVERT. This is the outage check.
--   SELECT max(relative_x) AS max_x, max(relative_y) AS max_y FROM public.stalls;
--   EXPECT max_x about 437 and max_y about 267 -- FEET, inside a 452 x 314 lot.
--   If you see max_x near 279 the seed stored render UNITS and every travel leg is
--   now 1.57x too short. If you see max_x near 686 it was multiplied twice.
--
-- V5 -- THE OCPP SEAM SURVIVED. Existing stalls kept their ids, so their charger
--       links must still be attached.
--   SELECT count(*) FILTER (WHERE ocpp_charger_id IS NOT NULL) AS linked
--     FROM public.stalls WHERE stall_type::text IN ('dcfc','l2');
--   EXPECT 80 (40 charging stalls x 2 depots). Before 0010 it was 90, because 10 of
--   the links were on the 5 phantom L2 stalls per depot. Those 10 OCPP charger rows
--   in ottoq_ocpp_chargers are now UNATTACHED -- deliberately left alone, since
--   touching them would change the OCPP inventory. Decide on them separately.
--
-- V6 -- THE OVERNIGHT WAVE NOW PLANS FOR 30, NOT 35.
--   SELECT count(*) FILTER (WHERE stall_type::text='l2') AS l2
--     FROM public.stalls WHERE depot_id = '<depot>';
--   EXPECT 30. ottoq_plan_overnight_wave reads exactly this, unfiltered, and
--   broadcasts it into every slot. Any capacity number quoted before 0010 used 35.
--
-- V7 -- SOLAR DID NOT MOVE. The energy model reads ottoq_canopy_state, which this
--       file does not touch. CANOPY-04 is decommissioned as a STRUCTURE only.
--   SELECT count(*), sum(...) FROM public.ottoq_canopy_state;   -- unchanged
--   SELECT structure_code, status FROM public.ottoq_site_structures
--    WHERE structure_kind = 'solar_canopy' ORDER BY 1;
--   EXPECT CANOPY-01/02/03 active, CANOPY-04 decommissioned, canopy_state untouched.
--   OPEN QUESTION FOR THE FOUNDER: 3 canopies of structure, 4 canopies of solar.
--
-- V8 -- THE GUARD AGREES WITH THE DATABASE. Export and re-check.
--   cd ottoyarddepot-sim && npm run layout:check
--   EXPECT all blocking checks pass. The WARN about 16 L2 stalls being 15.67 ft
--   deep against a 16.0 ft design vehicle is expected and is a real, open item:
--   canopy B and C west columns are pitched at 16.17 ft.
--
-- V9 -- PROTECT. Nothing here may regress certified state. Re-measure.
--   SELECT jobid, active FROM cron.job ORDER BY jobid;   -- 12 must stay ON
--   AND run scripts/check-drift.sql -- must be CLEAN.
--
-- ============================================================================
-- ROLLBACK
--
--   BEGIN;
--     DELETE FROM public.stalls;
--     INSERT INTO public.stalls
--       SELECT (b).* FROM (SELECT b FROM public.ottoq_layout_backup_0010_stalls b) x;
--     -- (drop the trailing backed_up_at column when restoring; column order matches
--     --  public.stalls otherwise)
--     UPDATE public.ottoq_site_structures t
--        SET origin_x_ft = b.origin_x_ft, origin_y_ft = b.origin_y_ft,
--            width_ft = b.width_ft, length_ft = b.length_ft, height_ft = b.height_ft,
--            title = b.title, properties = b.properties, status = b.status
--       FROM public.ottoq_layout_backup_0010_structures b
--      WHERE b.structure_id = t.structure_id;
--     UPDATE public.depots d
--        SET site_length_ft = b.site_length_ft, site_width_ft = b.site_width_ft,
--            site_acres = b.site_acres, site_layout = b.site_layout
--       FROM public.ottoq_layout_backup_0010_depots b WHERE b.id = d.id;
--   COMMIT;
--
--   Restoring stalls re-creates the 5 deleted rows with their ORIGINAL ids and puts
--   the 14 re-homed rows back under their ORIGINAL stall_codes, so any history that
--   pointed at them lines back up. (The re-homed rows never lost their ids in the
--   first place -- only their code and position changed.) The structures added by 0010
--   (CARPORT-*, LIGHT-*) are left behind by this rollback; delete them by
--   structure_code if you want the pre-0010 set exactly.
-- ============================================================================
