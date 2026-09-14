-- migration-version: PENDING
-- migration-name:    0317_the_twin_writes_where_each_asset_is_not_only_how_charged
--
-- 0317  OTTO-TWIN PERSISTS POSITION ON EVERY TELEMETRY PACKET IT EMITS
--
-- ---------------------------------------------------------------------------
-- WHY THIS IS SEPARATE FROM 0314-0316, AND WHY IT MATTERS MORE THAN IT LOOKS
--
-- 0314 and 0315 built position and ETA as PURE FUNCTIONS -- computed on demand,
-- stored nowhere. 0316 wired the ETA into ottoq_return_eta_minutes, which the
-- twin's tick does call, so arrival times became real. But position itself was
-- still only ever computed when something asked, and nothing in OTTO-Twin ever
-- asked. The consequence: a run could complete with every arrival time computed
-- from a position that the run did not record, so
--   * ottoq_telemetry_packets.current_lat/.current_lng stayed NULL, as they
--     have been in all 406,054 rows,
--   * the playback timeline the 3D layer renders from (CLAUDE.md 2.8:
--     entity_id, event_type, t_start, t_end, from_pose, to_pose) had no pose
--     to export,
--   * and nothing downstream -- renderer, dashboards, exports, a future pilot's
--     comparison against real GPS -- could see where an asset was.
--
-- A model that only exists while a function is running is a demo. This makes it
-- part of the twin's own record.
--
-- ---------------------------------------------------------------------------
-- THE INTEGRATION POINT, chosen by reading rather than assuming
--
-- twin.ottoq_sim_emit_telemetry is the twin's SINGLE writer of
-- ottoq_telemetry_packets -- it holds the only two INSERTs into that table in
-- the entire database. So every packet any run emits passes through here, which
-- means positions arrive for every scenario, every seed and every depot without
-- touching the scenario library, the run starter or the metronome.
--
-- The emitter already receives everything the position model needs:
-- p_vehicle_id, p_sim_run_id and p_sim_clock. The depot is resolved the same
-- way 0316 resolved it -- vehicles.home_depot_id, then ottoq_sim_runs.depot_id.
--
-- THREE EXACT SUBSTITUTIONS, each asserted unique before it is made. The
-- emitter is 3,491 bytes; re-typing it to change four lines would invite the
-- transcription defect 0313's header warned about, so the reviewer checks four
-- short strings instead:
--   1. the DECLARE block gains v_lat / v_lng
--   2. `  END IF;` (occurs once) gains the position lookup after it
--   3. the INSERT column list gains current_lat, current_lng
--   4. the VALUES list gains v_lat, v_lng
--
-- ---------------------------------------------------------------------------
-- WHEN POSITION IS NULL, AND WHY THAT IS THE RIGHT ANSWER
--
-- ottoq_vehicle_position returns no row for a vehicle with no open dispatch, so
-- v_lat/v_lng stay NULL for a vehicle sitting in the depot. That is deliberate
-- and is NOT a gap to be filled with the depot's own coordinates: a vehicle in
-- the depot is at a STALL, and stall geometry already exists in
-- ottoq_site_structures, which is what the renderer should place it by. Writing
-- the depot origin for every parked vehicle would put 226 assets on one pin and
-- would make "at the depot" and "arriving at the depot" indistinguishable --
-- the same conflation ottoq_vehicle_position's own comment refuses.
--
-- NULL here means "not on a trip", and vehicle_state on the same row says so
-- explicitly.
--
-- ---------------------------------------------------------------------------
-- DETERMINISM. Everything the lookup touches is already seeded and scoped: the
-- bearing and radius come from twin.ottoq_sim_seeded_random and
-- ottoq_sample_calibrated keyed on the run seed plus (vehicle, dispatch), the
-- dispatch read is run-scoped, and the clock is the sim clock the emitter was
-- handed -- never the wall clock. Two arms of a pair emitting the same packet
-- compute the same position.
--
-- COST. One position lookup per emitted packet. It is computed ONCE into
-- v_lat/v_lng rather than twice inside the VALUES list, which would have been
-- the obvious way to write it and would have doubled the cost on the twin's
-- hottest write path -- the path G29 spent a migration making faster.
--
-- forces_recert: TRUE. New non-NULL content on a run-scoped table that the
-- world fingerprint reads. Lineage row IN THIS FILE.
-- ===========================================================================

DO $pre$
DECLARE v_md5 text; v_nonnull bigint; v_writers int;
BEGIN
  -- P1. THE EMITTER IS WHAT THIS MIGRATION READ.
  SELECT md5(p.prosrc) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_emit_telemetry';
  IF v_md5 IS DISTINCT FROM 'fdca53cfc44beeed334b4530c4051bd5' THEN
    RAISE EXCEPTION '0317 P1: twin.ottoq_sim_emit_telemetry prosrc md5 is %, expected fdca53cfc44beeed334b4530c4051bd5', COALESCE(v_md5,'ABSENT');
  END IF;

  -- P2. IT REALLY IS THE ONLY WRITER. The claim that every run gets positions
  --     rests entirely on this, so assert it rather than repeat it.
  -- THIS PRECONDITION REFUSED THE FIRST APPLY, and it was right to. Written as
  -- ILIKE '%INSERT INTO%ottoq_telemetry_packets%' it counted 2, because that
  -- pattern matches any function containing both strings ANYWHERE -- and
  -- twin.ottoq_sim_advance_deployed_telemetry contains an unrelated INSERT and,
  -- 260 lines later, a SELECT ... FROM ottoq_telemetry_packets. The claim was
  -- right and the test was wrong, which is the harder way round to catch. A
  -- real INSERT is asserted with a real pattern; the loose one is not loosened
  -- until it passes, it is replaced by one that means what it says.
  SELECT count(*) INTO v_writers
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
     AND p.prosrc ~* 'insert\s+into\s+(public\.)?ottoq_telemetry_packets';
  IF v_writers <> 1 THEN
    RAISE EXCEPTION '0317 P2: % functions INSERT into ottoq_telemetry_packets, expected exactly 1; '
                    'patching one emitter would leave the others writing NULL positions', v_writers;
  END IF;

  -- P3. THE COLUMNS ARE STILL EMPTY, so this migration is what fills them.
  SELECT count(current_lat) INTO v_nonnull FROM public.ottoq_telemetry_packets;
  IF v_nonnull <> 0 THEN
    RAISE NOTICE '0317 P3: current_lat already has % non-NULL value(s); positions are being written by something else', v_nonnull;
  END IF;

  -- P4. THE POSITION MODEL IS PRESENT AND IS 0315's CORRECTED ONE.
  IF (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_trip_geometry') LIKE '%v_speed / 60.0%' THEN
    RAISE EXCEPTION '0317 P4: ottoq_trip_geometry still derives its radius from speed; 0315 is not applied';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE state='active' AND pid <> pg_backend_pid()
                AND (query ILIKE '%determinism_pair%' OR query ILIKE '%cert_arm%' OR query ILIKE '%ab_pair%')) THEN
    RAISE EXCEPTION '0317 P5: a certification pair is in flight';
  END IF;
END $pre$;

DO $swap$
DECLARE
  v_def text; v_new text;
  c_decl_old CONSTANT text := '  v_fleet_op_id      UUID;';
  c_decl_new CONSTANT text := '  v_fleet_op_id      UUID;' || E'\n' ||
                              '  v_lat              DOUBLE PRECISION;   -- 0317' || E'\n' ||
                              '  v_lng              DOUBLE PRECISION;   -- 0317';
  -- SECOND REFUSAL, also correct. Anchored on '  END IF;' this counted 2:
  -- replace() matches SUBSTRINGS, and a deeper-indented '    END IF;' contains
  -- the two-space anchor inside it. An earlier check that counted whole LINES
  -- returned 1 and was measuring a different thing than the substitution does.
  -- The anchor is now the two-line block, verified to occur exactly once.
  c_endif_old CONSTANT text := E'    RETURN v_id;\n  END IF;';
  c_endif_new CONSTANT text :=
    '    RETURN v_id;' || E'\n' ||
    '  END IF;' || E'\n' ||
    '' || E'\n' ||
    '  -- 0317: persist WHERE the asset is, not only how charged it is. Computed' || E'\n' ||
    '  -- ONCE here rather than twice inside the VALUES list, because this is the' || E'\n' ||
    '  -- twin''s hottest write path. NULL means "not on a trip" -- a parked vehicle' || E'\n' ||
    '  -- is at a stall, and stall geometry lives in ottoq_site_structures.' || E'\n' ||
    '  SELECT pp.lat, pp.lng INTO v_lat, v_lng' || E'\n' ||
    '    FROM public.ottoq_vehicle_position(' || E'\n' ||
    '           p_vehicle_id,' || E'\n' ||
    '           (SELECT COALESCE(vv.home_depot_id, rr.depot_id)' || E'\n' ||
    '              FROM public.ottoq_sim_runs rr' || E'\n' ||
    '              LEFT JOIN public.vehicles vv ON vv.id = p_vehicle_id' || E'\n' ||
    '             WHERE rr.sim_run_id = p_sim_run_id),' || E'\n' ||
    '           p_sim_run_id, p_sim_clock) pp;';
  c_cols_old CONSTANT text := '    tire_pressures_psi, speed_kmh,';
  c_cols_new CONSTANT text := '    tire_pressures_psi, speed_kmh, current_lat, current_lng,';
  c_vals_old CONSTANT text := '    v_tire_p, p_speed_kmh,';
  c_vals_new CONSTANT text := '    v_tire_p, p_speed_kmh, v_lat, v_lng,';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_emit_telemetry';

  -- Each target must occur EXACTLY ONCE. Counted by length arithmetic over a
  -- literal replace -- no regex escaping, which cannot silently match something
  -- slightly different.
  IF (length(v_def) - length(replace(v_def, c_decl_old,  ''))) / length(c_decl_old)  <> 1 THEN
    RAISE EXCEPTION '0317 SWAP: the DECLARE anchor does not occur exactly once';
  END IF;
  IF (length(v_def) - length(replace(v_def, c_endif_old, ''))) / length(c_endif_old) <> 1 THEN
    RAISE EXCEPTION '0317 SWAP: the END IF anchor does not occur exactly once';
  END IF;
  IF (length(v_def) - length(replace(v_def, c_cols_old,  ''))) / length(c_cols_old)  <> 1 THEN
    RAISE EXCEPTION '0317 SWAP: the column-list anchor does not occur exactly once';
  END IF;
  IF (length(v_def) - length(replace(v_def, c_vals_old,  ''))) / length(c_vals_old)  <> 1 THEN
    RAISE EXCEPTION '0317 SWAP: the VALUES anchor does not occur exactly once';
  END IF;

  v_new := replace(v_def,  c_decl_old,  c_decl_new);
  v_new := replace(v_new,  c_endif_old, c_endif_new);
  v_new := replace(v_new,  c_cols_old,  c_cols_new);
  v_new := replace(v_new,  c_vals_old,  c_vals_new);

  IF v_new = v_def THEN
    RAISE EXCEPTION '0317 SWAP: substitution produced an identical definition';
  END IF;
  EXECUTE v_new;
END $swap$;

DO $post$
DECLARE v_md5 text; v_src text;
BEGIN
  SELECT md5(p.prosrc), p.prosrc INTO v_md5, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_emit_telemetry';

  IF v_md5 = 'fdca53cfc44beeed334b4530c4051bd5' THEN
    RAISE EXCEPTION '0317 A1: prosrc md5 unchanged; the replacement did not take';
  END IF;
  IF position('current_lat, current_lng' in v_src) = 0 THEN
    RAISE EXCEPTION '0317 A1: the INSERT column list does not carry the position columns';
  END IF;
  IF position('ottoq_vehicle_position' in v_src) = 0 THEN
    RAISE EXCEPTION '0317 A1: the emitter does not call the position model';
  END IF;
  -- Computed once, not once per VALUES reference.
  IF (length(v_src) - length(replace(v_src, 'ottoq_vehicle_position', ''))) / length('ottoq_vehicle_position') <> 1 THEN
    RAISE EXCEPTION '0317 A1: the position model is called more than once per packet on the twin''s hottest write path';
  END IF;

  -- A2. THE FUNCTION STILL COMPILES AS ONE DEFINITION with its signature intact,
  --     so twin.ottoq_sim_advance_deployed_telemetry's calls still bind.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='twin' AND p.proname='ottoq_sim_emit_telemetry') <> 1 THEN
    RAISE EXCEPTION '0317 A2: twin.ottoq_sim_emit_telemetry is no longer a single definition';
  END IF;

  RAISE NOTICE '0317 applied. The next tick of any run writes positions. RECERT REQUIRED.';
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0317_the_twin_writes_where_each_asset_is_not_only_how_charged', true,
   'twin.ottoq_sim_emit_telemetry -- asserted by P2 to be the ONLY function that INSERTs into '
   'ottoq_telemetry_packets -- now writes current_lat/current_lng on every packet, so every run of every '
   'scenario records where its assets are without touching the scenario library, the run starter or the '
   'metronome. Before 0317 those two columns were NULL in all 406,054 rows and the position model existed '
   'only as pure functions computed on demand, which no part of OTTO-Twin ever called: arrival times were '
   'being computed from a position the run did not record, and the 3D layer''s playback timeline had no '
   'pose to export. Four exact substitutions, each asserted to occur exactly once by literal length '
   'arithmetic rather than regex escaping. Position is computed ONCE into locals, not twice inside the '
   'VALUES list, because this is the twin''s hottest write path. NULL is the correct answer for a vehicle '
   'with no open dispatch -- it is at a stall, and stall geometry is in ottoq_site_structures; writing the '
   'depot origin for every parked vehicle would put 226 assets on one pin and make "at the depot" and '
   '"arriving at the depot" indistinguishable. forces_recert=true: new content on a run-scoped table the '
   'world fingerprint reads.',
   now())
ON CONFLICT (name) DO NOTHING;
