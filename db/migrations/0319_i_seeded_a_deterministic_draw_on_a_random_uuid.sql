-- migration-version: PENDING
-- migration-name:    0319_i_seeded_a_deterministic_draw_on_a_random_uuid
--
-- 0319  THE POSITION MODEL'S SEEDED DRAWS WERE SALTED WITH gen_random_uuid()
--
-- ---------------------------------------------------------------------------
-- THE DETERMINISM PAIR FAILED, AND IT WAS RIGHT TO
--
-- Pair: seed 171717, 12 ticks, grid_smoke, depot aacd0bb0. Verdict equal=false.
--
-- Both arms BOOT identically -- fp 5f2e25bcc2f0bb552ca39bad7679a78b on both,
-- and every boot hash matches (world 9541a871, dispatches 126e3d71, chargers
-- 8c10258e). So 0043's same-world guarantee held. They then diverge:
--
--                       arm A        arm B
--   endst legs           33           34
--   endst bookings       21           24
--   endst dispatches      5            6
--   wsec stalls      8216f139     9d390b89
--   wsec vehicles    b180e980     34a093af
--   h_bkg h_cmd h_dec h_evt h_nrg h_rcl h_sdr h_rule -- all differ
--   h_cal, h_defr, h_prop -- IDENTICAL (calibration and the proposal stream
--                            are untouched, which localises the cause)
--
-- ---------------------------------------------------------------------------
-- THE CAUSE, and it is mine, introduced in 0314 and carried by 0315
--
-- public.ottoq_trip_geometry salts BOTH of its seeded draws with the dispatch's
-- primary key:
--
--   twin.ottoq_sim_seeded_random(v_seed, 'trip_bearing:'||p_vehicle_id||':'||v_disp.dispatch_id)
--   ottoq_sample_calibrated('daily_miles_driven','global', v_seed,
--                           'trip_radius:'||p_vehicle_id||':'||v_disp.dispatch_id)
--
-- and public.ottoq_vehicle_dispatches.dispatch_id has column default
-- gen_random_uuid(). Two arms of the same seed insert their own dispatch rows
-- and mint their own ids, so the salts differ, so the bearings and radii differ,
-- so every ETA differs, so recall timing differs, so the worlds diverge. The
-- draw was deterministic in form and random in fact.
--
-- THIS IS THE 0280 CLASS, WHICH THIS REPO HAS NOW CONVICTED FOUR TIMES:
--   0137  the world fingerprint hashed a write timestamp
--   0139  the end-state fingerprint was not id-blind
--   0216  the decision snapshot digested ocpp_sessions.id (uuid_generate_v4())
--   0319  this one -- a seeded draw salted with gen_random_uuid()
-- CLAUDE.md 2.9a records the first three. I wrote the fourth today, in a
-- migration whose own header cited the class.
--
-- ---------------------------------------------------------------------------
-- THE FIX
--
-- Salt on a key that is STABLE ACROSS ARMS. p_vehicle_id already is -- vehicles
-- are shared world objects with fixed ids. dispatched_at is a SIM timestamp
-- derived from the deterministic sim clock, so two arms of one seed dispatch
-- the same vehicle at the same sim instant. Together they identify the trip
-- without naming the row:
--
--   'trip_bearing:'||p_vehicle_id::text||':'||v_disp.dispatched_at::text
--
-- If one vehicle were somehow dispatched twice at the same sim instant the two
-- trips would share a geometry, which is harmless -- the same vehicle cannot be
-- in two places, and the pair would still agree.
--
-- A2 ASSERTS THE PROPERTY DIRECTLY rather than trusting the reasoning: no
-- seeded salt in this function may reference dispatch_id, and the live source
-- is checked for it.
--
-- forces_recert: TRUE -- but note this migration REPAIRS a determinism defect
-- introduced by 0314/0315 rather than changing intended behaviour. The recert
-- owed by 0313/0316/0317/0318 was never run, so nothing was certified against
-- the broken draw.
-- ===========================================================================

DO $pre$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_trip_geometry';

  -- P1. THE DEFECT IS PRESENT. If the salts no longer name dispatch_id this
  --     migration is fixing something that is not there.
  IF position('dispatch_id::text' in v_src) = 0 THEN
    RAISE EXCEPTION '0319 P1: ottoq_trip_geometry does not salt on dispatch_id; the defect is absent';
  END IF;

  -- P2. AND dispatch_id REALLY IS RANDOM, which is the whole argument.
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='ottoq_vehicle_dispatches'
                    AND column_name='dispatch_id' AND column_default ILIKE '%random%') THEN
    RAISE EXCEPTION '0319 P2: dispatch_id has no random default; re-diagnose before changing the salt';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE state='active' AND pid <> pg_backend_pid()
                AND (query ILIKE '%determinism_pair%' OR query ILIKE '%cert_arm%')) THEN
    RAISE EXCEPTION '0319 P3: a certification pair is in flight';
  END IF;
END $pre$;

DO $swap$
DECLARE
  v_def text; v_new text;
  c_bear_old CONSTANT text := '''trip_bearing:''||p_vehicle_id::text||'':''||v_disp.dispatch_id::text';
  c_bear_new CONSTANT text := '''trip_bearing:''||p_vehicle_id::text||'':''||v_disp.dispatched_at::text';
  c_rad_old  CONSTANT text := '''trip_radius:''||p_vehicle_id::text||'':''||v_disp.dispatch_id::text';
  c_rad_new  CONSTANT text := '''trip_radius:''||p_vehicle_id::text||'':''||v_disp.dispatched_at::text';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_trip_geometry';

  IF (length(v_def) - length(replace(v_def, c_bear_old, ''))) / length(c_bear_old) <> 1 THEN
    RAISE EXCEPTION '0319 SWAP: the bearing salt does not occur exactly once'; END IF;
  IF (length(v_def) - length(replace(v_def, c_rad_old,  ''))) / length(c_rad_old)  <> 1 THEN
    RAISE EXCEPTION '0319 SWAP: the radius salt does not occur exactly once'; END IF;

  v_new := replace(v_def, c_bear_old, c_bear_new);
  v_new := replace(v_new, c_rad_old,  c_rad_new);
  IF v_new = v_def THEN RAISE EXCEPTION '0319 SWAP: identical definition'; END IF;
  EXECUTE v_new;
END $swap$;

DO $post$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_trip_geometry';

  -- A1. THE SALTS NOW NAME A STABLE KEY.
  IF position('trip_bearing:''||p_vehicle_id::text||'':''||v_disp.dispatched_at' in v_src) = 0 THEN
    RAISE EXCEPTION '0319 A1: the bearing salt was not repointed'; END IF;
  IF position('trip_radius:''||p_vehicle_id::text||'':''||v_disp.dispatched_at' in v_src) = 0 THEN
    RAISE EXCEPTION '0319 A1: the radius salt was not repointed'; END IF;

  -- A2. THE PROPERTY, ASSERTED RATHER THAN REASONED: no seeded draw in this
  --     function may reference the randomly-defaulted primary key at all.
  IF position('dispatch_id' in v_src) <> 0 THEN
    RAISE EXCEPTION '0319 A2: dispatch_id still appears in ottoq_trip_geometry; a randomly '
                    'defaulted column has no place in a deterministic draw';
  END IF;
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0319_i_seeded_a_deterministic_draw_on_a_random_uuid', true,
   'A determinism pair (seed 171717, 12 ticks, grid_smoke) FAILED with equal=false: identical boot '
   'fingerprints on both arms, then 33 vs 34 legs, 21 vs 24 bookings, 5 vs 6 dispatches and eight '
   'differing atom hashes. Cause: ottoq_trip_geometry salted BOTH of its seeded draws -- the bearing via '
   'twin.ottoq_sim_seeded_random and the radius via ottoq_sample_calibrated -- with '
   'ottoq_vehicle_dispatches.dispatch_id, whose column default is gen_random_uuid(). Two arms mint '
   'different ids, so the salts differ, so every ETA differs, so the worlds diverge. The draw was '
   'deterministic in form and random in fact. This is the 0280 class (after 0137, 0139, 0216), introduced '
   'by me in 0314 and carried by 0315. Fixed by salting on (vehicle_id, dispatched_at) -- a shared world '
   'object plus a deterministic sim timestamp, both stable across arms. A2 asserts dispatch_id no longer '
   'appears in the function at all. Nothing was certified against the broken draw: the recert owed by '
   '0313/0316/0317/0318 had not been run.',
   now())
ON CONFLICT (name) DO NOTHING;
