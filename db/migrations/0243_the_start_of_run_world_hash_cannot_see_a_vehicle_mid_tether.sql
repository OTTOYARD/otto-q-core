-- migration-version: 20260909060909
-- migration-name: 0243_the_start_of_run_world_hash_cannot_see_a_vehicle_mid_tether
-- ===========================================================================
-- 0243  THE START-OF-RUN WORLD HASH CANNOT SEE A VEHICLE MID-TETHER
-- ===========================================================================
-- probe:          db/checks/0160   (G43)
-- forces_recert:  TRUE
--
-- WHY forces_recert IS TRUE AND MUST BE
--
-- This migration changes ottoq.ottoq_world_fingerprint, which produces the 'fp'
-- atom -- one of the fourteen ENFORCED atoms of the certification pair. Every
-- canon in ottoq_cert_matrix was recorded against the narrow hash. They do not
-- survive the correction and must not: a canon derived from an atom that was
-- wrong is not evidence. 0192 built forces_recert for exactly this case, and
-- 0133 paid the same price when the BESS was added.
--
-- WHAT WAS WRONG
--
-- The pair on busy_day / 314159 / 12t failed on 2026-09-09 05:24 UTC with
-- exactly one atom moved, h_evt, on ONE arm -- while fp, the atom whose entire
-- job is "both arms began from the same world", reported the two arms IDENTICAL
-- (803698f332adc0d06cbefca79dad1ce0 on both).
--
-- They had not begun from the same world. Seven vehicles at the flagship depot
-- were carrying live robotic-tether state when arm A booted -- written 102
-- seconds before the pair's own transaction -- and arm B, which always boots
-- from what arm A left behind, had none. At tick 10 the tether deadline
-- (robotic_tether_until, sim 06:00:18.5) came due in arm A only, nine events
-- were emitted that arm B never emitted, and h_evt diverged.
--
-- Two functions had to both be blind for this to happen, and both are:
--
--   public.ottoq_tick_invariance_reset_fleet   does not mention robotic_tether
--   ottoq.ottoq_world_fingerprint              does not mention robotic_tether
--
-- so the residue is never cleared and never seen. A pair therefore fails or
-- passes according to whether anything happened to leave a vehicle mid-tether
-- before it started. Every green column to date has been green partly by luck.
--
-- WHY THE TETHER COLUMNS BELONG IN THIS HASH
--
-- ottoq.ottoq_world_fingerprint is an enumerated column list, not a row image,
-- and its own header says: "The start-relevant world, hashed. ... Extend the
-- column set only alongside the probe that justifies it." Every prior extension
-- left its probe number in the body -- 0115, 0107, 0133 (the BESS, after 0051
-- showed peak_site_kw differing between two byte-identical arms because the
-- battery carried across runs), 0135 -- and 0137 REMOVED a column on the same
-- discipline. db/checks/0160 is this extension's probe.
--
-- A vehicle mid-tether holds a deadline that will come due during the run and
-- change what the engine does. That is start-relevant world state by the same
-- argument 0133 made for the battery, one table over.
--
-- WHY BOTH HALVES ARE IN ONE MIGRATION
--
--   (a) the reset clears the tether family, so the arms genuinely start equal;
--   (b) the fingerprint hashes it, so when they do not, the pair says so at fp
--       on tick zero instead of at h_evt nine ticks later with no indication why.
--
-- (a) alone closes this instance and leaves the class invisible -- the mistake
-- that let V7's residue sweep miss these four columns. (b) alone is an alarm
-- that fires intermittently on a condition nothing fixes. Neither is shippable
-- on its own.
--
-- WHAT IS DELIBERATELY NOT INCLUDED
--
-- The catalog sweep in 0160 s3 found nine mutable columns on vehicles+stalls
-- invisible to both functions. Only the four tether columns are convicted by a
-- probe, so only they are added:
--   current_depot_id, is_active, stalls.reserved_for_mission_id,
--   stalls.staging_role   -- plausible on the same argument, unconvicted;
--                            adding them on suspicion is how a fingerprint
--                            accretes noise, and the function's own comment
--                            forbids it.
--   owning_sim_run_id     -- MUST NOT be hashed; it holds each arm's own run id
--                            and differs between arms by design.
--   current_soc_updated_at -- correctly excluded already, by 0137.
--
-- DRY RUN, 2026-09-09 05:54 UTC, BEFORE APPLYING
--
-- Both substitutions and every assertion were executed against the live database
-- inside a transaction deliberately aborted by a final RAISE, so nothing was
-- committed. This is not a claim that the migration "should" work:
--
--   fp, old definition, clean world     49121f67efc726d0a2759ede4a8049fb
--   fp, NEW definition, clean world     4249329e7dc6aaba3df29ce27eeee5a5   <- A5 moves
--   fp, NEW definition, one vehicle
--       put mid-tether by the probe     6b411b02e65a8bd29d622f5802596217   <- A4 moves again
--   probe residue after subtransaction  0                                  <- A4b clean
--   reset names robotic_tether_direction   t                               <- A1
--   fp   hashes robotic_tether_direction   t                               <- A2
--
-- Both anchors resolved to exactly one occurrence, both rewritten function
-- bodies compiled, and the new fingerprint ran and returned an md5.
--
-- Rollback verified afterwards: reset md5 back to b6371136cd4ba924cb7953c5fd15216e,
-- fingerprint md5 back to ae1cb9d9659029584c373bc10ce5c6fc, zero tether rows at
-- the flagship depot, zero rows in ottoq_cert_lineage matching '0243%'.
--
-- (The dry-run "before" value differs from the 803698f3... that the failing pair
-- recorded as fp. That is expected and is not a discrepancy: 803698f3 was the
-- world at that pair's boot; 49121f67 is the world as it stands now, after C1
-- and C2 have each run and reset it.)
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
  v_probe uuid;
BEGIN
  ------------------------------------------------------------------ preconditions
  IF md5(pg_get_functiondef(v_reset_sig::regprocedure)) <> 'b6371136cd4ba924cb7953c5fd15216e' THEN
    RAISE EXCEPTION '0243 PRECONDITION: reset_fleet md5 is %, expected b6371136cd4ba924cb7953c5fd15216e',
      md5(pg_get_functiondef(v_reset_sig::regprocedure));
  END IF;
  IF md5(pg_get_functiondef(v_fp_sig::regprocedure)) <> 'ae1cb9d9659029584c373bc10ce5c6fc' THEN
    RAISE EXCEPTION '0243 PRECONDITION: world_fingerprint md5 is %, expected ae1cb9d9659029584c373bc10ce5c6fc',
      md5(pg_get_functiondef(v_fp_sig::regprocedure));
  END IF;

  -- The fingerprint of the clean world under the OLD definition, for A5.
  -- EVERY call below is dynamic on purpose: ottoq_world_fingerprint is a STABLE
  -- SQL function, so a static call can be INLINED into a cached plan and would
  -- keep returning the pre-replace body's answer -- which would make A3/A4/A5
  -- assert against the old definition and pass while proving nothing.
  EXECUTE 'SELECT ottoq.ottoq_world_fingerprint($1)' INTO v_fp_before USING v_flagship;

  ------------------------------------------------- SITE 1: the reset clears it
  d := pg_get_functiondef(v_reset_sig::regprocedure);
  a := E'         current_stall_id = NULL,\n';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION '0243 SITE1: anchor occurs % times, expected exactly 1', n; END IF;

  nd := replace(d, a, a ||
        E'         -- 0243 (probe db/checks/0160): a vehicle left mid-tether by whatever\n'
     || E'         -- touched the depot last was inherited by arm A and never by arm B,\n'
     || E'         -- and its deadline came due mid-run. The reset owns these four.\n'
     || E'         robotic_tether_phase = NULL, robotic_tether_until = NULL,\n'
     || E'         robotic_tether_stall_id = NULL, robotic_tether_direction = NULL,\n');
  EXECUTE nd;

  ------------------------------------------- SITE 2: the fingerprint can see it
  d := pg_get_functiondef(v_fp_sig::regprocedure);
  a := '||COALESCE(v.last_state_change::text,''-'')';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION '0243 SITE2: anchor occurs % times, expected exactly 1', n; END IF;

  nd := replace(d, a, a ||
        '||''|''||COALESCE(v.robotic_tether_phase::text,''-'')'
     || '||''|''||COALESCE(v.robotic_tether_until::text,''-'')'
     || '||''|''||COALESCE(v.robotic_tether_stall_id::text,''-'')'
     || '||''|''||COALESCE(v.robotic_tether_direction::text,''-'') /* 0243: probe db/checks/0160 */');
  EXECUTE nd;

  ------------------------------------------------------------------ assertions
  -- A1: the reset now names all four, and its definition actually moved.
  d := pg_get_functiondef(v_reset_sig::regprocedure);
  IF md5(d) = 'b6371136cd4ba924cb7953c5fd15216e' THEN
    RAISE EXCEPTION '0243 A1: reset_fleet definition did not change';
  END IF;
  IF NOT (d LIKE '%robotic_tether_phase = NULL%' AND d LIKE '%robotic_tether_until = NULL%'
      AND d LIKE '%robotic_tether_stall_id = NULL%' AND d LIKE '%robotic_tether_direction = NULL%') THEN
    RAISE EXCEPTION '0243 A1: reset_fleet does not clear all four tether columns';
  END IF;

  -- A2: the fingerprint now names all four, and its definition actually moved.
  d := pg_get_functiondef(v_fp_sig::regprocedure);
  IF md5(d) = 'ae1cb9d9659029584c373bc10ce5c6fc' THEN
    RAISE EXCEPTION '0243 A2: world_fingerprint definition did not change';
  END IF;
  IF NOT (d LIKE '%robotic_tether_phase::text%' AND d LIKE '%robotic_tether_until::text%'
      AND d LIKE '%robotic_tether_stall_id::text%' AND d LIKE '%robotic_tether_direction::text%') THEN
    RAISE EXCEPTION '0243 A2: world_fingerprint does not hash all four tether columns';
  END IF;

  -- A3: it still runs and still returns an md5.
  EXECUTE 'SELECT ottoq.ottoq_world_fingerprint($1)' INTO v_fp_clean USING v_flagship;
  IF v_fp_clean !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION '0243 A3: world_fingerprint returned %, not an md5', v_fp_clean;
  END IF;

  -- A4: THE BEHAVIOURAL ASSERTION. Put one vehicle mid-tether and prove the new
  --     hash moves. The inner block is a subtransaction: the UPDATE is rolled
  --     back by the RAISE, while the PL/pgSQL variable assignment survives it.
  --     This is the property the old definition did not have, asserted rather
  --     than assumed.
  -- The probe vehicle must currently have NO tether state, or setting it would
  -- be a no-op and A4 would fail for a reason that has nothing to do with the fix.
  SELECT id INTO v_probe FROM public.vehicles
   WHERE home_depot_id = v_flagship AND category = 'autonomous'
     AND robotic_tether_phase IS NULL ORDER BY id LIMIT 1;
  IF v_probe IS NULL THEN
    RAISE EXCEPTION '0243 A4: no autonomous flagship vehicle without tether state to probe';
  END IF;

  BEGIN
    UPDATE public.vehicles SET robotic_tether_phase = 'unstow' WHERE id = v_probe;
    EXECUTE 'SELECT ottoq.ottoq_world_fingerprint($1)' INTO v_fp_probed USING v_flagship;
    RAISE EXCEPTION 'OTTOQ_0243_PROBE_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'OTTOQ_0243_PROBE_ROLLBACK' THEN RAISE; END IF;
  END;

  IF v_fp_probed IS NULL OR v_fp_probed = v_fp_clean THEN
    RAISE EXCEPTION '0243 A4: the world fingerprint did not move when a vehicle was put mid-tether (clean=%, probed=%)',
      v_fp_clean, v_fp_probed;
  END IF;

  -- A4b: the probe left nothing behind. Asserted on the PROBE ROW ONLY -- an
  -- earlier draft counted tether state across the whole depot, which would have
  -- failed on any residue this migration did not create, i.e. on exactly the
  -- condition the migration exists to survive.
  SELECT count(*) INTO n FROM public.vehicles
   WHERE id = v_probe AND robotic_tether_phase IS NOT NULL;
  IF n <> 0 THEN
    RAISE EXCEPTION '0243 A4b: the probe subtransaction did not roll back -- vehicle % is still mid-tether', v_probe;
  END IF;

  -- A5: fp moved for the clean world too. This is what makes forces_recert TRUE
  --     honest: every canon really is invalidated, not just the ones with residue.
  --     CAVEAT, stated rather than hidden: the depot metronome runs every minute
  --     and this is READ COMMITTED, so in principle a concurrent write could move
  --     the hash between the two calls and A5 would pass for the wrong reason.
  --     The assertion is still worth making -- the new body appends four fields
  --     per vehicle for all 116 autonomous vehicles, so a MOVE is certain and
  --     only its cause is theoretically ambiguous. A5 failing would be the real
  --     signal, and it cannot fail spuriously.
  IF v_fp_clean = v_fp_before THEN
    RAISE EXCEPTION '0243 A5: fp did not move on a clean world -- forces_recert TRUE would be a lie';
  END IF;

  RAISE NOTICE '0243 OK: fp % -> % (clean world); tether probe moves it to %',
    v_fp_before, v_fp_clean, v_fp_probed;
END
$mig$;

-- ---------------------------------------------------------------------------
-- lineage
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note)
VALUES ('0243_the_start_of_run_world_hash_cannot_see_a_vehicle_mid_tether',
        TRUE,
        'G43 / probe db/checks/0160. ottoq_world_fingerprint now hashes the four '
        'robotic_tether columns and ottoq_tick_invariance_reset_fleet now clears them. '
        'fp moves for every column: every canon recorded against the narrow hash is '
        'invalidated, which is the point.');

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-09 06:09:09 UTC (1:09 AM CT) as version 20260909060909
-- ---------------------------------------------------------------------------
-- Applied alone: 0 busy client backends, 0 tether residue at the flagship depot,
-- round 31 long finished and the three G43 control jobs unscheduled first.
--
-- Post-state, measured:
--
--   ottoq_tick_invariance_reset_fleet  md5  b6371136cd4ba924cb7953c5fd15216e
--                                       ->  8784bb1245160b035385270b2ec88187
--   ottoq.ottoq_world_fingerprint      md5  ae1cb9d9659029584c373bc10ce5c6fc
--                                       ->  f2ab1fb907ee1f63a5d25cfcf193fea9
--   reset clears all four tether columns          true
--   fingerprint hashes all four tether columns    true
--   ottoq_cert_lineage row, forces_recert TRUE    1
--   probe residue on public.vehicles              0
--   recert floor  2026-09-09 03:15:07.410339 -> 2026-09-09 06:09:09.360796
--
-- Every canon recorded before 06:09:09 is now below the floor and must be
-- re-earned. That is the intended cost, not a side effect.
--
-- WHAT JUSTIFIED APPLYING IT: db/checks/0160 section 9. C3 planted the residue
-- and ran the ORIGINAL ottoq_determinism_pair with no replay of any kind, and
-- the pair failed with TEN of fourteen atoms moved -- h_bkg, h_cmd, h_dec,
-- h_evt, h_nrg, h_prop, h_rcl, h_rule, h_sdr and endst -- while fp, the atom
-- whose entire job is "both arms began from the same world", read
-- 803698f332adc0d06cbefca79dad1ce0 on BOTH arms. Causation established by
-- controlled experiment, not inferred from a symptom.
