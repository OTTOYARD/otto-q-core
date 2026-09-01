-- 0144: the reset stamp leaves the wall clock
--
-- ottoq_decide_tick has five vehicle loops. Three of them order by
--
--     ORDER BY v.last_state_change ASC NULLS FIRST, v.id
--
-- so last_state_change decides which vehicle reaches a scarce staging stall first.
-- ottoq_tick_invariance_reset_fleet writes that column as now() -- WALL CLOCK. Of the 25
-- functions that write it, the reset is the only one writing a wall-clock value; every
-- other writer is in the sim domain. And ottoq.ottoq_world_fingerprint does not hash the
-- column at all, so the certification is blind to it.
--
-- Put together: a wall-clock value is a sort key for the decide loop, and nothing in the
-- cert can see it.
--
-- WHY IT BITES. The sim clock of a 12-tick run covers 02:30-08:00 on the run date. The
-- reset stamp is the real time of day the pair was armed, on the same date. So where the
-- untouched vehicles sort relative to the sim-stamped ones depends on when you ran it:
--
--   armed 08-31 23:33  ->  stamp precedes the whole sim window  ->  untouched sort FIRST
--   armed 09-01 04:26  ->  stamp lands INSIDE the window        ->  they sort in the middle
--
-- Not hypothetical. Measured at the flagship depot right now: 120 vehicles, two distinct
-- last_state_change values, 116 of them carrying 09-01 04:26 -- the wall-clock arming time
-- of the last pair (rc_f2) -- which is inside the 02:30-08:00 window of a 12-tick run.
--
-- PRECEDENT. This is the disease 0065 already convicted in the sibling harness, where
-- ottoq_cert_arm_start pinned the run's sim clock to the arming minute and no two rounds
-- could be differenced. Its rule is the one applied here: everything in the SIM domain
-- moves together; only the real-time metronome stamps keep now(). last_state_change is a
-- sim-domain attribute -- nine functions do age arithmetic against it with sim clocks -- so
-- it belongs on sim time.
--
-- WHAT THIS DOES NOT CLAIM. It does not claim to be the cause of the busy_day 424242/12t
-- canon step recorded in db/checks/0063. The clean prediction there -- that arm B of the
-- 02:28 pair, arming inside the window, should diverge from arm A arming outside it -- is
-- NOT confirmed: that pair passed. This is a real defect on its own evidence, fixed on its
-- own merits, and 0063's step stays open until something actually explains it.
--
-- THE FIX. The reset takes the sim start and stamps it, falling back to now() only when no
-- caller supplies one (production callers, of which there are none today -- both callers are
-- cert harnesses). A constant, per the reset's own 0096 convention: "canonical means a
-- CONSTANT". Untouched vehicles then sort ahead of every sim-stamped one, always, whatever
-- time of day the pair runs. And the fingerprint starts hashing the column, so the blindness
-- cannot come back silently.
--
-- Not a sentinel epoch: nine functions do age arithmetic on this column, so a year-2000
-- constant would make every vehicle look ancient and change behaviour. The sim start is the
-- value that is both constant and semantically true -- the fleet was reset as the run began.

BEGIN;

-- ---------------------------------------------------------------------------------------
-- 0. Self-classification (0142 convention). This changes an engine ordering input AND the
--    fingerprint, so it forces re-certification and claims no exemption.
-- ---------------------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('the_reset_stamp_leaves_the_wall_clock', true,
   '0144: the fleet reset stamps last_state_change with the sim start instead of now(), and '
   'the world fingerprint starts hashing it. Changes a decide-loop ordering input and the '
   'fingerprint -- forces re-certification.')
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note, classified_at = now();

-- ---------------------------------------------------------------------------------------
-- 1. The reset accepts a sim start and stamps it.
-- ---------------------------------------------------------------------------------------
DO $do$
DECLARE
  v_src text; v_new text; v_anchor text; v_repl text; v_n int;
  c_pin CONSTANT text := '93eeddb43810bb8035af81b0151ad8ef';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet'
     AND pg_get_function_identity_arguments(p.oid) = 'p_depot_id uuid, p_seed bigint';
  IF v_src IS NULL THEN RAISE EXCEPTION '0144: the 2-arg reset was not found'; END IF;
  IF md5(v_src) <> c_pin THEN
    RAISE EXCEPTION '0144: reset moved under this migration (pin %, found %)', c_pin, md5(v_src);
  END IF;

  v_anchor := 'public.ottoq_tick_invariance_reset_fleet(p_depot_id uuid, p_seed bigint)';
  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0144: signature anchor matched % times, expected 1', v_n; END IF;
  v_repl := 'public.ottoq_tick_invariance_reset_fleet(p_depot_id uuid, p_seed bigint, p_as_of timestamptz DEFAULT NULL)';
  v_new := replace(v_src, v_anchor, v_repl);

  v_anchor := 'last_state_change = now(),';
  v_n := (length(v_new) - length(replace(v_new, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0144: stamp anchor matched % times, expected 1', v_n; END IF;
  -- now() survives only as the fallback for a caller with no sim clock to offer.
  v_repl := 'last_state_change = COALESCE(p_as_of, now()),';
  v_new := replace(v_new, v_anchor, v_repl);

  -- The old arity has to go, or PL/pgSQL keeps resolving 2-arg calls to the wall-clock body.
  DROP FUNCTION public.ottoq_tick_invariance_reset_fleet(uuid, bigint);
  EXECUTE v_new;
END
$do$;

-- ---------------------------------------------------------------------------------------
-- 2. Both callers hand it their sim start. Both are cert harnesses; there is no production
--    caller to break.
-- ---------------------------------------------------------------------------------------
DO $do$
DECLARE
  v_src text; v_new text; v_anchor text; v_n int;
  c_pin CONSTANT text := '7bb11b84f16e1a1862dbdadcf363082d';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF md5(v_src) <> c_pin THEN
    RAISE EXCEPTION '0144: ottoq_determinism_pair moved (pin %, found %)', c_pin, md5(v_src);
  END IF;

  v_anchor := 'PERFORM public.ottoq_tick_invariance_reset_fleet(p_depot, p_seed);';
  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0144: pair call-site anchor matched % times, expected 1', v_n; END IF;
  v_new := replace(v_src, v_anchor,
             'PERFORM public.ottoq_tick_invariance_reset_fleet(p_depot, p_seed, p_sim_start);');
  EXECUTE v_new;
END
$do$;

DO $do$
DECLARE
  v_src text; v_new text; v_anchor text; v_n int;
  c_pin CONSTANT text := '3a993c878d7403cfa6561162e4542ba6';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_arm';
  IF md5(v_src) <> c_pin THEN
    RAISE EXCEPTION '0144: ottoq_tick_invariance_arm moved (pin %, found %)', c_pin, md5(v_src);
  END IF;

  v_anchor := '(SELECT id FROM depots ORDER BY id LIMIT 1), p_cert_seed);';
  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0144: arm call-site anchor matched % times, expected 1', v_n; END IF;
  v_new := replace(v_src, v_anchor,
             '(SELECT id FROM depots ORDER BY id LIMIT 1), p_cert_seed, p_start_clock);');
  EXECUTE v_new;
END
$do$;

-- ---------------------------------------------------------------------------------------
-- 3. The fingerprint stops being blind to it.
-- ---------------------------------------------------------------------------------------
DO $do$
DECLARE
  v_src text; v_new text; v_anchor text; v_n int; v_before text; v_after text;
  c_pin CONSTANT text := 'dbda9acd762383deaa59a1aaa2c45c43';
  c_depot CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_world_fingerprint';
  IF md5(v_src) <> c_pin THEN
    RAISE EXCEPTION '0144: ottoq_world_fingerprint moved (pin %, found %)', c_pin, md5(v_src);
  END IF;

  v_before := ottoq.ottoq_world_fingerprint(c_depot);

  v_anchor := '||COALESCE((v.config - ''condition_drawn_run'')::text,''{}'')';
  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0144: fingerprint anchor matched % times, expected 1', v_n; END IF;

  -- 0144: the column that orders three of the decide loops is now part of the hashed world.
  v_new := replace(v_src, v_anchor,
    v_anchor || '||''|''||COALESCE(v.last_state_change::text,''-'')');
  EXECUTE v_new;

  v_after := ottoq.ottoq_world_fingerprint(c_depot);

  -- A column added to a hash that does not move the hash was not added to the hash.
  IF v_before = v_after THEN
    RAISE EXCEPTION '0144: fingerprint unchanged at % -- last_state_change did not enter the hash', v_before;
  END IF;
  RAISE NOTICE '0144: world fingerprint % -> %', left(v_before,8), left(v_after,8);
END
$do$;

-- ---------------------------------------------------------------------------------------
-- 4. Post-conditions. Comments stripped first (0136/0137: a migration that explains itself
--    is the one whose prose contains the strings its own checks look for).
-- ---------------------------------------------------------------------------------------
DO $chk$
DECLARE v_reset text; v_pair text; v_arm text; v_fp text; v_args text;
BEGIN
  SELECT regexp_replace(pg_get_functiondef(p.oid),'/\*.*?\*/','','g'),
         pg_get_function_identity_arguments(p.oid)
    INTO v_reset, v_args
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet';

  IF v_args <> 'p_depot_id uuid, p_seed bigint, p_as_of timestamptz' THEN
    RAISE EXCEPTION '0144: reset has unexpected signature: %', v_args;
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet') <> 1 THEN
    RAISE EXCEPTION '0144: more than one reset arity survives -- 2-arg calls may still hit now()';
  END IF;
  IF v_reset NOT LIKE '%last_state_change = COALESCE(p_as_of, now())%' THEN
    RAISE EXCEPTION '0144: the reset still stamps the wall clock unconditionally';
  END IF;
  -- The rest of the canonical block must survive the edit.
  IF v_reset NOT LIKE '%target_soc = 90%' OR v_reset NOT LIKE '%current_state = ''offline''%' THEN
    RAISE EXCEPTION '0144: the reset lost part of its canonical block';
  END IF;

  SELECT regexp_replace(pg_get_functiondef(p.oid),'/\*.*?\*/','','g') INTO v_pair
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF v_pair NOT LIKE '%reset_fleet(p_depot, p_seed, p_sim_start)%' THEN
    RAISE EXCEPTION '0144: the pair harness does not pass its sim start to the reset';
  END IF;

  SELECT regexp_replace(pg_get_functiondef(p.oid),'/\*.*?\*/','','g') INTO v_arm
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_arm';
  IF v_arm NOT LIKE '%p_cert_seed, p_start_clock)%' THEN
    RAISE EXCEPTION '0144: the arm harness does not pass its sim start to the reset';
  END IF;

  SELECT regexp_replace(pg_get_functiondef(p.oid),'/\*.*?\*/','','g') INTO v_fp
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_world_fingerprint';
  IF v_fp NOT LIKE '%last_state_change%' THEN
    RAISE EXCEPTION '0144: the fingerprint is still blind to last_state_change';
  END IF;
  -- Everything the fingerprint hashed before must still be hashed.
  IF v_fp NOT LIKE '%current_soc%' OR v_fp NOT LIKE '%current_state%'
     OR v_fp NOT LIKE '%current_stall_id%' OR v_fp NOT LIKE '%target_soc%'
     OR v_fp NOT LIKE '%condition_drawn_run%' THEN
    RAISE EXCEPTION '0144: the fingerprint lost a column it used to hash';
  END IF;
END
$chk$;

COMMIT;
