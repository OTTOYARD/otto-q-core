-- migration-version: PENDING
-- migration-name: 0245_current_depot_id_is_written_in_the_tick_and_cleared_by_nothing
-- ===========================================================================
-- 0245  current_depot_id IS WRITTEN IN THE TICK AND CLEARED BY NOTHING
-- ===========================================================================
-- probe:          db/checks/0160 section 11
-- forces_recert:  TRUE
-- DEPENDS ON:     0243 (both anchors below are text 0243 introduced)
-- APPLY WINDOW:   with 0244, after round 32, before round 33. Both force a
--                 recert; applying them together costs one round, separately two.
-- DO NOT APPLY WHILE A ROUND IS IN FLIGHT.
--
-- WHAT THE PROBE FOUND
--
-- 0160 section 8 named five mutable columns that neither
-- ottoq_tick_invariance_reset_fleet nor ottoq.ottoq_world_fingerprint can see,
-- and declined to sweep them into 0243 unconvicted. Section 11 swept them.
-- Four are out: stalls.reserved_for_mission_id and vehicles.is_active have no
-- assigning function in public/ottoq/twin at all, stalls.staging_role was a
-- regex false positive (a RETURNS TABLE column and a WHERE comparison, never an
-- assignment), and vehicles.owning_sim_run_id differs between arms BY DESIGN and
-- must stay unhashed.
--
-- vehicles.current_depot_id is convicted, by the same three properties that let
-- the tether family fail a certification:
--
--   1. WRITTEN DURING A TICK. From
--      twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz):
--
--        UPDATE vehicles SET current_state = v_state, current_stall_id = p_stall_id,
--               current_depot_id = v_stall.depot_id, last_state_change = v_clock
--         WHERE id = p_vehicle_id;
--
--   2. NOT CLEARED BETWEEN RUNS. ottoq_tick_invariance_reset_fleet does not name
--      it -- it is on section 3's list of 49 columns invisible to both functions.
--   3. NOT HASHED AT BOOT. ottoq.ottoq_world_fingerprint does not name it either,
--      so two arms starting with different values are not detected at fp.
--
-- WHY IT IS LESS LIKELY TO BITE THAN THE TETHER FAMILY, SAID PLAINLY RATHER THAN
-- USED AS A REASON TO SKIP IT: it is assigned v_stall.depot_id, the depot of the
-- stall being plugged into, so inside a single-depot run it converges to a
-- constant. Carrying residue across arms needs a vehicle left pointing at a
-- DIFFERENT depot from the one being certified -- which the two-lane cadence
-- (flagship + Benchmark) makes reachable rather than hypothetical.
--
-- THIS CHANGES NO ENGINE BEHAVIOUR TODAY, MEASURED BEFORE IT WAS WRITTEN
--
--   SELECT current_depot_id = home_depot_id, count(*) FROM public.vehicles
--    WHERE home_depot_id = <flagship> AND category='autonomous' GROUP BY 1;
--
--   -> true, 116     (all of them, no nulls, no other depot)
--
-- So the reset half is a no-op against the world as it stands: it writes the
-- value the column already holds. That is the point -- it is a guarantee, not a
-- correction. A5 below asserts the no-op property explicitly so that if this
-- migration ever DOES change a row, the assertion says so instead of the change
-- passing silently as a determinism fix.
--
-- No explicit BEGIN/COMMIT: apply_migration supplies the transaction.
-- ===========================================================================

DO $mig$
DECLARE
  v_flagship  constant uuid := '11111111-1111-1111-1111-111111111111';
  v_reset_sig constant text := 'public.ottoq_tick_invariance_reset_fleet(uuid,bigint,timestamptz)';
  v_fp_sig    constant text := 'ottoq.ottoq_world_fingerprint(uuid)';
  d text; a text; nd text; n int;
  v_fp_before text; v_fp_clean text; v_fp_probed text;
  v_probe uuid; v_other uuid; v_prior uuid;
BEGIN
  -- Pinned to what 0243 left. If either fails, 0243 did not run or something
  -- else moved these functions, and the anchors below cannot be trusted.
  IF md5(pg_get_functiondef(v_reset_sig::regprocedure)) <> '8784bb1245160b035385270b2ec88187' THEN
    RAISE EXCEPTION '0245 PRECONDITION: reset_fleet md5 is %, expected 0243''s 8784bb1245160b035385270b2ec88187',
      md5(pg_get_functiondef(v_reset_sig::regprocedure));
  END IF;
  IF md5(pg_get_functiondef(v_fp_sig::regprocedure)) <> 'f2ab1fb907ee1f63a5d25cfcf193fea9' THEN
    RAISE EXCEPTION '0245 PRECONDITION: world_fingerprint md5 is %, expected 0243''s f2ab1fb907ee1f63a5d25cfcf193fea9',
      md5(pg_get_functiondef(v_fp_sig::regprocedure));
  END IF;

  -- A5's baseline: does the reset half actually change anything today?
  SELECT count(*) INTO n FROM public.vehicles
   WHERE home_depot_id = v_flagship AND category = 'autonomous'
     AND current_depot_id IS DISTINCT FROM home_depot_id;
  IF n <> 0 THEN
    RAISE EXCEPTION '0245 A5: % flagship vehicles have current_depot_id <> home_depot_id. '
                    'This migration is then a BEHAVIOUR change, not a guarantee, and the '
                    'header claim that it is a no-op is false. Re-measure and rewrite it.', n;
  END IF;

  EXECUTE 'SELECT ottoq.ottoq_world_fingerprint($1)' INTO v_fp_before USING v_flagship;

  ------------------------------------------------ SITE 1: the reset restores it
  d := pg_get_functiondef(v_reset_sig::regprocedure);
  a := E'         robotic_tether_stall_id = NULL, robotic_tether_direction = NULL,\n';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION '0245 SITE1: anchor occurs % times, expected exactly 1', n; END IF;

  nd := replace(d, a, a ||
        E'         -- 0245 (probe db/checks/0160 s11): written inside a tick by\n'
     || E'         -- twin.ottoq_sim_start_charge_session and cleared by nothing. A no-op\n'
     || E'         -- against today''s world (all 116 already equal home); a guarantee against\n'
     || E'         -- a vehicle left pointing at another depot by a run on the other lane.\n'
     || E'         current_depot_id = p_depot_id,\n');
  EXECUTE nd;

  --------------------------------------------- SITE 2: the fingerprint sees it
  d := pg_get_functiondef(v_fp_sig::regprocedure);
  a := '||''|''||COALESCE(v.robotic_tether_direction::text,''-'')';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION '0245 SITE2: anchor occurs % times, expected exactly 1', n; END IF;

  nd := replace(d, a, a ||
        '||''|''||COALESCE(v.current_depot_id::text,''-'') /* 0245: probe db/checks/0160 s11 */');
  EXECUTE nd;

  ------------------------------------------------------------------ assertions
  d := pg_get_functiondef(v_reset_sig::regprocedure);
  IF md5(d) = '8784bb1245160b035385270b2ec88187' THEN
    RAISE EXCEPTION '0245 A1: reset_fleet definition did not change';
  END IF;
  IF d NOT LIKE '%current_depot_id = p_depot_id%' THEN
    RAISE EXCEPTION '0245 A1: reset_fleet does not restore current_depot_id';
  END IF;

  d := pg_get_functiondef(v_fp_sig::regprocedure);
  IF md5(d) = 'f2ab1fb907ee1f63a5d25cfcf193fea9' THEN
    RAISE EXCEPTION '0245 A2: world_fingerprint definition did not change';
  END IF;
  IF d NOT LIKE '%COALESCE(v.current_depot_id::text%' THEN
    RAISE EXCEPTION '0245 A2: world_fingerprint does not hash current_depot_id';
  END IF;

  EXECUTE 'SELECT ottoq.ottoq_world_fingerprint($1)' INTO v_fp_clean USING v_flagship;
  IF v_fp_clean !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION '0245 A3: world_fingerprint returned %, not an md5', v_fp_clean;
  END IF;

  -- A4: behavioural. Point one vehicle at a different depot and prove the hash
  -- moves. Rolled back by the RAISE; the variable assignment survives it.
  SELECT id INTO v_probe FROM public.vehicles
   WHERE home_depot_id = v_flagship AND category = 'autonomous' ORDER BY id LIMIT 1;
  SELECT id INTO v_other FROM public.depots WHERE id <> v_flagship ORDER BY id LIMIT 1;
  IF v_probe IS NULL OR v_other IS NULL THEN
    RAISE EXCEPTION '0245 A4: need a flagship vehicle (%) and a second depot (%) to probe', v_probe, v_other;
  END IF;
  SELECT current_depot_id INTO v_prior FROM public.vehicles WHERE id = v_probe;

  BEGIN
    UPDATE public.vehicles SET current_depot_id = v_other WHERE id = v_probe;
    EXECUTE 'SELECT ottoq.ottoq_world_fingerprint($1)' INTO v_fp_probed USING v_flagship;
    RAISE EXCEPTION 'OTTOQ_0245_PROBE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'OTTOQ_0245_PROBE_ROLLBACK' THEN RAISE; END IF;
  END;

  IF v_fp_probed IS NULL OR v_fp_probed = v_fp_clean THEN
    RAISE EXCEPTION '0245 A4: the world fingerprint did not move when a vehicle was pointed at depot % (clean=%, probed=%)',
      v_other, v_fp_clean, v_fp_probed;
  END IF;

  -- A4b: the probe row is back to exactly what it held before.
  IF (SELECT current_depot_id FROM public.vehicles WHERE id = v_probe) IS DISTINCT FROM v_prior THEN
    RAISE EXCEPTION '0245 A4b: the probe subtransaction did not roll back -- vehicle % now points at %',
      v_probe, (SELECT current_depot_id FROM public.vehicles WHERE id = v_probe);
  END IF;

  IF v_fp_clean = v_fp_before THEN
    RAISE EXCEPTION '0245 A6: fp did not move on a clean world -- forces_recert TRUE would be a lie';
  END IF;

  RAISE NOTICE '0245 OK: fp % -> % (clean world); pointing one vehicle at depot % moves it to %',
    v_fp_before, v_fp_clean, v_other, v_fp_probed;
END
$mig$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note)
VALUES ('0245_current_depot_id_is_written_in_the_tick_and_cleared_by_nothing',
        TRUE,
        'G43 residual / probe db/checks/0160 section 11. vehicles.current_depot_id is '
        'written inside a tick by twin.ottoq_sim_start_charge_session, cleared by no '
        'reset and hashed by no fingerprint -- the same three properties that let the '
        'tether family fail a certification. The reset now restores it and '
        'ottoq_world_fingerprint now hashes it. A no-op against the world as measured '
        '(all 116 flagship vehicles already equal home); a guarantee against the '
        'two-lane case. fp moves, so canons below the new floor are invalidated.');
