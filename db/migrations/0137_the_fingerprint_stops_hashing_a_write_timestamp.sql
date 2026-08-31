-- migration-version: 20260831221500
-- migration-name:    the_fingerprint_stops_hashing_a_write_timestamp
-- 0137 -- the instrument was failing on bookkeeping, not on world state.
--
-- THE SYMPTOM. After 0136 every determinism pair failed, on both re-run columns, twice each --
-- and failed in a shape that is the exact inverse of a real defect:
--     ALL FOUR decision streams byte-identical (h_cmd, h_dec, h_evt, h_bkg), booking counts
--     identical (normal_day 1045/1045, busy_day 1113/1113), and ONLY the boot world
--     fingerprint differing -- reproducibly, arm A on one value and arm B on another, the
--     same two values every single run.
-- db/checks/0046 s1 names the opposite pattern (fp equal + streams differing) as always a real
-- defect. This one is its mirror: the engine agreed with itself completely and the instrument
-- disagreed anyway.
--
-- THE BISECTION, in order, each step discarding a hypothesis I had actually formed:
--   1. reset_fleet is IDEMPOTENT -- two resets in a row produce the same fingerprint.
--   2. A clean boot -> stop_and_reset -> boot with NO TICKS produces an IDENTICAL fingerprint
--      (1bad411e twice). So the boot path itself is symmetric and deterministic.
--   3. 40 seconds of elapsed wall time, with all four every-minute/every-two-minute infra cron
--      jobs live against the same depot, ALSO produces an identical fingerprint. Concurrency
--      and timing are NOT the cause -- a hypothesis I had reached for twice and which is now
--      dead by measurement rather than by argument.
--   4. Adding just TWO TICKS to the first run reproduces the divergence: 1bad411e -> 01d6215e.
--      A two-tick repro, in one rolled-back transaction. That is the whole minimal case.
--   5. ottoq_world_fingerprint reads exactly five sources. Probed all five with their REAL
--      hashed column sets -- not row images, which is where two earlier probes of mine went
--      wrong and produced two false accusations, both corrected here:
--        ottoq_bess_units      RESTORED (25.0|100.0|0|0|69.99|0|idle) -- 0135 is correct
--        stalls                RESTORED on all six hashed columns, reserved_at and
--                              reservation_expires_at included (an earlier probe of mine
--                              compared only id||status and proved nothing about them)
--        ottoq_ocpp_chargers   RESTORED on both hashed columns, station_state and
--                              last_fault_code -- 0 rows differing (an earlier probe compared
--                              the whole row and wrongly indicted this table)
--        vehicle_need_profile  RESTORED -- reset_fleet alone does not restore it, but
--                              ottoq_seed_vehicle_need_profiles (inside sim_start_run, which
--                              always follows reset) rewrites every hashed column via
--                              ON CONFLICT DO UPDATE. Measured 0 differing rows post-seed.
--        vehicles              ALL 116 ROWS DIFFER  <-- the carrier
--   6. Per-column diff of vehicles: exactly TWO keys move, both on all 116 rows --
--        config                     -- and the ONLY differing config key is
--                                      'condition_drawn_run', which the fingerprint ALREADY
--                                      subtracts. Clean.
--        current_soc_updated_at     -- 2026-09-01T06:00:00Z vs 2026-09-01T03:00:00Z
-- Exactly one residue column, and it is a WRITE TIMESTAMP.
--
-- WHAT IT IS AND IS NOT. The vehicles section hashes
--     id | current_soc | current_state | current_stall_id | current_soc_source | target_soc
--        | current_soc_updated_at | (config - 'condition_drawn_run')
-- current_soc_updated_at records WHEN state of charge was last written. It is not the charge,
-- it is metadata about the write. current_soc itself -- the actual value -- is hashed, matches
-- between arms, and stays hashed after this migration. So removing the timestamp costs the
-- instrument nothing it can detect: if any vehicle's SoC, state, stall, source, target or
-- config differs, the fingerprint still catches it. What it stops catching is the hour at
-- which an identical value happened to be stamped.
--
-- WHY REMOVING A COLUMN IS THE RIGHT FIX HERE, AND IS NOT 0135 IN REVERSE. 0135 taught this
-- function to see battery temperature because temperature was REAL START-RELEVANT STATE that
-- the reset left carrying across runs -- a fingerprint that cannot fail on real state is not a
-- check. The mirror error is equally real: a fingerprint that hashes per-run bookkeeping fails
-- on things that are not the world, and a check that fires on non-defects is just as useless,
-- because it trains its readers to discount it. This function's own header already states the
-- rule -- "Extend the column set only alongside the 0046 probe that justifies it" -- and the
-- codebase has drawn this exact line twice before: 0107 hashes the need profile as a row image
-- explicitly "minus wall-clock / per-run bookkeeping" (drawn_at, updated_at, drawn_for_run,
-- wear_km_applied_run), and 0115 subtracts config's 'condition_drawn_run' for the same reason.
-- current_soc_updated_at is that same class and was simply missed. This migration finishes a
-- line the fingerprint already drew, rather than moving it.
--
-- The alternative -- canonicalizing the timestamp in reset_fleet -- was considered and
-- rejected: it writes 116+ rows on every reset to make a value identical that carries no
-- information either way, and it would leave the fingerprint asserting something it has no
-- reason to assert.
--
-- Pre-image pin, read live 2026-08-31 (anchor asserted at exactly 1 occurrence):
--   ottoq.ottoq_world_fingerprint  59b0016d9885d73034206878f3b4a378

DO $apply$
DECLARE v_oid oid; v_src text; v_cnt int;
        v_old text := '||COALESCE(v.current_soc_updated_at::text,''-'')||''|''||COALESCE((v.config - ''condition_drawn_run'')::text,''{}'')';
        v_new text := '||COALESCE((v.config - ''condition_drawn_run'')::text,''{}'')  /* 0137: current_soc_updated_at removed -- a write timestamp, not world state; current_soc itself stays hashed */';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_world_fingerprint' AND p.prokind = 'f';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '59b0016d9885d73034206878f3b4a378' THEN
    RAISE EXCEPTION '0137 abort: ottoq_world_fingerprint drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0137 abort: anchor found % times, expected 1', v_cnt;
  END IF;
  EXECUTE replace(v_src, v_old, v_new);
  RAISE NOTICE '0137 applied: the fingerprint stops hashing current_soc_updated_at.';
END
$apply$;

-- Post-condition. The point of this migration is a NARROWING, so the verify has to prove both
-- halves: the bookkeeping column is gone AND every substantive column survives. A fingerprint
-- that lost current_soc would pass a naive "column removed" check and be worthless.
DO $verify$
DECLARE v_src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_world_fingerprint' AND p.prokind = 'f';

  IF v_src NOT LIKE '%/* 0137%' THEN
    RAISE EXCEPTION '0137 abort: marker missing';
  END IF;

  /* The marker comment NAMES the column it removed, so the absence test has to run against
     code with comments stripped -- exactly the trap 0136's verify hit. Test code, not prose. */
  v_src := regexp_replace(v_src, '/\*.*?\*/', '', 'g');
  IF v_src LIKE '%current_soc_updated_at%' THEN
    RAISE EXCEPTION '0137 abort: the write timestamp is still hashed';
  END IF;

  -- Everything that carries actual world state must still be there.
  IF v_src NOT LIKE '%v.current_soc::text%'      THEN RAISE EXCEPTION '0137 abort: current_soc lost';      END IF;
  IF v_src NOT LIKE '%v.current_state::text%'    THEN RAISE EXCEPTION '0137 abort: current_state lost';    END IF;
  IF v_src NOT LIKE '%v.current_stall_id::text%' THEN RAISE EXCEPTION '0137 abort: current_stall_id lost'; END IF;
  IF v_src NOT LIKE '%v.current_soc_source%'     THEN RAISE EXCEPTION '0137 abort: current_soc_source lost'; END IF;
  IF v_src NOT LIKE '%v.target_soc::text%'       THEN RAISE EXCEPTION '0137 abort: target_soc lost';       END IF;
  IF v_src NOT LIKE '%condition_drawn_run%'      THEN RAISE EXCEPTION '0137 abort: config section lost';   END IF;
  -- and the sections earlier rounds fought for.
  IF v_src NOT LIKE '%current_temperature_c::text%' THEN RAISE EXCEPTION '0137 abort: 0135 battery temperature lost'; END IF;
  IF v_src NOT LIKE '%reservation_expires_at%'   THEN RAISE EXCEPTION '0137 abort: stall reservation columns lost'; END IF;

  RAISE NOTICE '0137 verified: bookkeeping removed, every state-bearing column retained.';
END
$verify$;
