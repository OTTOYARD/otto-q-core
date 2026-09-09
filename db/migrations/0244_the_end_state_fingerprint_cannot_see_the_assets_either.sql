-- migration-version: PENDING
-- migration-name: 0244_the_end_state_fingerprint_cannot_see_the_assets_either
-- ===========================================================================
-- 0244  THE END-STATE FINGERPRINT CANNOT SEE THE ASSETS EITHER
-- ===========================================================================
-- probe:          db/checks/0160 section 8, item (1)
-- forces_recert:  TRUE
-- DO NOT APPLY WHILE A ROUND IS IN FLIGHT. Blocked on round 32 completing
-- (six jobs, 06:20-07:36 UTC 2026-09-09), because it invalidates canons and
-- applying it mid-round would void the round it interrupts.
--
-- WHAT IS WRONG
--
-- 0243 closed the BOOT half of G43: fp now hashes the robotic_tether family and
-- the per-arm reset clears it, so two arms that start from different fleet
-- states are now detected at fp on tick zero.
--
-- The END half is still open, and 0160 section 8 said so before 0243 was
-- applied rather than after:
--
--   public.ottoq_boot_state_fingerprint(uuid,uuid) hashes six things --
--   visit_needs, stall_bookings, itinerary_legs, vehicle_dispatches,
--   ocpp_chargers, calibration. public.vehicles and public.stalls appear in its
--   body ONLY inside EXISTS(...) subqueries used to scope those six to a depot.
--   NEITHER TABLE IS EVER HASHED.
--
-- That function computes 'endst', which IS one of the fourteen enforced atoms.
-- So two arms that END in different asset states are not caught by endst. In
-- practice a divergence that large also moves h_evt, h_dec or h_bkg, which is
-- why it has not bitten -- but "caught by a different atom, usually" is not
-- coverage, and an enforced atom that cannot see the assets is exactly the
-- narrower-than-the-claim defect G25 was about.
--
-- THE FIX, AND WHY IT IS ONE LINE RATHER THAN A NEW HASH
--
-- The obvious move is to write a fresh fleet-and-points CTE inside
-- ottoq_boot_state_fingerprint. That would be the mistake CLAUDE.md rule 5
-- names: a second, differently-shaped, separately-maintained hash of the same
-- tables, which would then need its own probe history and could drift from the
-- first.
--
-- ottoq.ottoq_world_fingerprint(uuid) ALREADY IS that hash. It is id-blind, it
-- excludes write timestamps (0137), it excludes each arm's own run id, its
-- column set is probe-justified line by line (0115, 0107, 0133, 0135, and 0243
-- for the tether family), and 0243 just widened it. Calling it is the whole fix:
--
--   'world', ottoq.ottoq_world_fingerprint(p_depot)
--
-- added as a key of the object ottoq_boot_state_fingerprint returns. endst then
-- covers the assets and the service points, and inherits every future extension
-- of the world fingerprint for free instead of drifting from it.
--
-- WHAT IT COSTS, AND THE STEP THAT MUST HAPPEN BEFORE THIS IS APPLIED
--
-- ottoq_boot_state_fingerprint is called TWICE per arm -- once at boot (v_boot)
-- and once at the end (endst) -- so this adds FOUR ottoq_world_fingerprint calls
-- per pair. G19 (db/checks/0129) found the boot fingerprint was 36% of a pair's
-- runtime from four calls, and 0222 fixed that by bounding what it scanned. The
-- same arithmetic applies here and it is NOT yet measured.
--
--   BEFORE APPLYING: time ottoq.ottoq_world_fingerprint(flagship) on its own and
--   multiply by four. If it is not small against a ~130 s pair, this migration
--   is wrong as written and the right shape is a separate end-only atom rather
--   than a key inside a function that also runs at boot. Measure, do not assume
--   -- that is the whole lesson of 0129 and 0144.
--
-- At boot the new key is redundant with fp by construction (same function, same
-- depot, same moment). That redundancy is harmless and is not worth a second
-- function to avoid; the value is at the END, where nothing else looks.
--
-- No explicit BEGIN/COMMIT: apply_migration supplies the transaction.
-- ===========================================================================

DO $mig$
DECLARE
  v_sig constant text := 'public.ottoq_boot_state_fingerprint(uuid,uuid)';
  d text; a text; nd text; n int;
  v_out jsonb;
BEGIN
  -- Pinned to the definition 0222 left. If this fails, something changed the
  -- end-state fingerprint since and the anchor below must be re-derived.
  IF md5(pg_get_functiondef(v_sig::regprocedure)) <> '5b52e61a5ae9717f5b6791eb50415f99' THEN
    RAISE EXCEPTION '0244 PRECONDITION: boot_state_fingerprint md5 is %, expected 5b52e61a5ae9717f5b6791eb50415f99',
      md5(pg_get_functiondef(v_sig::regprocedure));
  END IF;

  d := pg_get_functiondef(v_sig::regprocedure);
  a := E'  ''calibration'', jsonb_build_object(''h'', public.ottoq_calibration_fingerprint()))';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION '0244 SITE: anchor occurs % times, expected exactly 1', n; END IF;

  nd := replace(d, a,
        E'  ''calibration'', jsonb_build_object(''h'', public.ottoq_calibration_fingerprint()),\n'
     || E'  /* 0244 (probe db/checks/0160 s8): this function hashes everything ABOUT the\n'
     || E'     assets -- their needs, bookings, legs, dispatches, chargers -- and never the\n'
     || E'     assets themselves, so two arms ending in different fleet states were not\n'
     || E'     caught by endst. ottoq_world_fingerprint is already the id-blind,\n'
     || E'     probe-justified hash of exactly that; calling it beats maintaining a second\n'
     || E'     one that can drift from it. */\n'
     || E'  ''world'', ottoq.ottoq_world_fingerprint(p_depot))');
  EXECUTE nd;

  -- A1: the definition moved and now names the world fingerprint.
  d := pg_get_functiondef(v_sig::regprocedure);
  IF md5(d) = '5b52e61a5ae9717f5b6791eb50415f99' THEN
    RAISE EXCEPTION '0244 A1: boot_state_fingerprint definition did not change';
  END IF;
  IF d NOT LIKE '%ottoq.ottoq_world_fingerprint(p_depot)%' THEN
    RAISE EXCEPTION '0244 A1: boot_state_fingerprint does not call the world fingerprint';
  END IF;

  -- A2: it still runs, still returns an object, and the object now carries a
  --     'world' key holding an md5. Dynamic for the same inlining reason 0243
  --     documented.
  -- A sentinel run id, NOT NULL: the function splits rows into visible/foreign
  -- with (t.sim_run_id IS NOT NULL AND t.sim_run_id <> p_run), and a NULL p_run
  -- makes that expression NULL rather than true or false, so both the
  -- "WHERE NOT fgn" and "WHERE fgn" branches would silently select nothing and
  -- the assertion would pass against an empty hash.
  EXECUTE 'SELECT public.ottoq_boot_state_fingerprint($1, $2)'
    INTO v_out USING '11111111-1111-1111-1111-111111111111'::uuid,
                     '00000000-0000-0000-0000-000000000000'::uuid;
  IF v_out IS NULL OR jsonb_typeof(v_out) <> 'object' THEN
    RAISE EXCEPTION '0244 A2: boot_state_fingerprint returned %, not an object', v_out;
  END IF;
  IF COALESCE(v_out->>'world', '') !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION '0244 A2: the world key is %, not an md5', v_out->>'world';
  END IF;

  -- A3: the six pre-existing keys are all still there. A fingerprint that got
  --     NARROWER while claiming to get wider would be the worst outcome here.
  IF NOT (v_out ? 'visit_needs' AND v_out ? 'bookings' AND v_out ? 'legs'
      AND v_out ? 'dispatches' AND v_out ? 'chargers' AND v_out ? 'calibration') THEN
    -- jsonb_object_keys is set-returning; a bare scalar subquery over it raises
    -- "more than one row returned" and would hide the assertion it is reporting.
    RAISE EXCEPTION '0244 A3: a pre-existing key was lost. keys now: %',
      (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(v_out) k);
  END IF;

  RAISE NOTICE '0244 OK: endst now carries world=%', v_out->>'world';
END
$mig$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note)
VALUES ('0244_the_end_state_fingerprint_cannot_see_the_assets_either',
        TRUE,
        'G43 residual / probe db/checks/0160 section 8 item 1. ottoq_boot_state_fingerprint '
        'now carries ottoq_world_fingerprint under a world key, so endst covers the assets '
        'and the service points instead of only the records about them. endst is enforced, '
        'so every canon recorded against the narrow end-state hash is invalidated.');
