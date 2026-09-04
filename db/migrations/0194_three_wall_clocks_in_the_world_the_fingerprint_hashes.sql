-- =====================================================================
-- 0194  Three wall clocks in the world the fingerprint hashes
-- =====================================================================
-- forces_recert = TRUE. This changes the world a run boots from (two
-- charger columns the reset never owned), the stamps the engine writes
-- when it re-opens work mid-run, and the stamps teardown leaves on the
-- calendar. None of the three is read by the decide path today. All
-- three are hashed by the end-state fingerprint. One of them is a
-- liveness gate the decide path reads at boot.
--
-- THE FINDING (round 14, pair 1, 19:06 UTC, busy_day/171717/12t)
-- ---------------------------------------------------------------------
-- The pair PASSED: equal on fp, h_cmd, h_dec, h_evt, h_bkg, h_nrg and
-- endst. Its two BOOT fingerprints disagree on chargers.world
-- (bce038e9... in the first arm, bb34f348... in the second): the same
-- depot, reset by the same function with the same seed, ten minutes
-- apart. That is not the engine; that is the reset leaving world state
-- behind. It is also why endst has never matched between two PAIRS
-- (db/checks/0108; the inter-pair bar): a fingerprint that hashes a
-- column nobody resets, or a column stamped with the wall clock, cannot
-- agree across time however deterministic the engine is.
--
-- Measured on the flagship depot at 19:20 UTC, 45 chargers:
--   last_fault_at      45 non-null, 31 distinct, 2026-07-23 .. 2026-09-02
--   last_heartbeat_at  1 distinct: 2026-09-01 08:00, the previous run's
--                      final sim clock (the world tick writes it)
--   station_state      1 distinct ('Available'); last_fault_code none
-- ottoq_tick_invariance_reset_fleet resets station_state,
-- last_fault_code and station_state_changed_at (0093/0094). It does not
-- mention last_fault_at or last_heartbeat_at. Both are hashed by the
-- fingerprint's ch CTE (everything but created_at, updated_at and
-- last_fault_payload). A charger the first arm faults at sim clock X
-- boots the second arm with last_fault_at = X, where the first arm
-- booted with whatever an older run left. Different boot hashes, same
-- behaviour -- because nothing on the decide path reads last_fault_at.
--
-- last_heartbeat_at is different in kind. The decide path reads it:
--   >= p_clock - 35 min   book_appointment, plan_opportunistic_charges,
--                         prearrival_contracts
--   >= clock  - 90 s      l2_optimize_assignments,
--                         l2_propose_stall_assignment
--   HW.002                the offline rule
-- The world tick (ord 107) rewrites it to the sim clock every tick for
-- every non-Faulted charger, so inside a run it is deterministic. At
-- boot, before tick 1, it is whatever the previous run left. Today that
-- is always a LATER sim instant than the new run's start (every
-- certification run starts at 2026-09-01 02:00 and ends after it), so
-- every gate passes and the channel is silent. Start a run at an earlier
-- sim date than the last one that ran and every charger is "offline" at
-- boot: the primed deployment books nothing, and two pairs disagree for
-- a reason no fingerprint names. The reset must own this column.
--
-- TWO MORE WALL CLOCKS, SAME FINGERPRINT
-- ---------------------------------------------------------------------
-- 1. public.ottoq_reopen_visit_atoms stamps reopened_at (x2),
--    cut_short_at, reopen_escalated_at and last_at with now() -- the
--    wall clock -- inside ottoq_visit_needs.atoms and .meta, and the
--    fingerprint's vn CTE hashes atoms whole. 0181 moved done_at to the
--    sim clock; these five sites were missed because the function has
--    no clock argument: p_since is the SESSION START it uses to decide
--    which credits are void, not the moment of the call. Substituting
--    p_since would stamp "re-opened at" with the time the work began.
--    73 flagship visits carry a wall-clock reopened_at today. And this
--    is the WHOLE visit_needs channel, not a guess: the 15:20 and 19:06
--    busy_day/171717/12t arms (5dbc3de9, 9a82a2ff), diffed row by row
--    on every column the vn CTE hashes, match on 116 of 116 visits
--    except one row, one atom, one key -- reopened_at, holding the two
--    transactions' start instants (15:20:00.118941, 19:06:00.14789).
--    Fix: a fifth argument p_at (DEFAULT NULL -> now(), so any caller
--    without a clock behaves exactly as before), and both tick-path
--    callers pass the clock they already hold:
--      twin.ottoq_sim_vehicle_exception_handler   p_sim_clock
--      ottoq.ottoq_release_vacated_spaces         p_clock
-- 2. public.ottoq_sim_release_depot releases the run's open bookings
--    with released_at = now() and cancels the depot's active OCPP
--    sessions with ended_at = now(). Every other released_at writer in
--    the engine uses the sim clock; teardown is the one wall-clock
--    writer, and it sits three statements before the leg-close that
--    0089 wrote "stamped with the run's final sim clock", using exactly
--    the idiom this migration reuses. 91,196 flagship bookings carry a
--    wall-clock run_stopped release today; 13,247 of them since 09-03.
--    No decide-path function reads released_at (assertion A5 is the
--    census: the only mentions outside teardown are a comment and a
--    jsonb key).
--
-- WHAT THIS DOES NOT DO
-- ---------------------------------------------------------------------
-- It does not narrow the fingerprint. released_at, last_fault_at and
-- last_heartbeat_at stay hashed. Fixing the writer makes the fingerprint
-- sharper, not blinder: after this, two pairs that disagree on endst
-- disagree because the engine did something different.
-- It does not touch twin.ottoq_sim_seed_fleet, ottoq_benchmark_reset or
-- ottoq_cert_arm_start, which also stamp heartbeat = now(). None is on
-- the pair path (the harness resets only through
-- ottoq_tick_invariance_reset_fleet). Recorded; the next instance.
-- It does not backfill. The wall-clock releases and reopen stamps are
-- what happened; the ledger keeps them.
-- =====================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────
-- 1. THE ANCHORED EDITS (four functions, one signature change)
-- ─────────────────────────────────────────────────────────────────────
DO $mig$
DECLARE
  v_src text; v_n int; v_acl text;
  v_clock_idiom text := '(SELECT COALESCE(r.sim_clock_current, now()) FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id) /* 0194 */';
  -- reset_fleet
  v_r1 text := 'SET station_state = ''Available'', last_fault_code = NULL,';
  v_r2 text := 'OR c.station_state_changed_at IS DISTINCT FROM ''epoch''::timestamptz);';
  -- reopen_visit_atoms
  v_hdr_old text := '(p_vehicle uuid, p_svcs text[], p_since timestamp with time zone, p_reason text)';
  v_hdr_new text := '(p_vehicle uuid, p_svcs text[], p_since timestamp with time zone, p_reason text, p_at timestamp with time zone DEFAULT NULL)';
  v_s1 text := '''reopened_at'', to_jsonb(now()),';
  v_s2 text := '''cut_short_at'', to_jsonb(now()),';
  v_s3 text := '''reopen_escalated_at'', now(),';
  v_s4 text := '''last_at'', now(),';
  -- release_depot
  v_d1 text := 'released_at=now(), release_reason=''run_stopped''';
BEGIN
  ------------------------------------------------------------------
  -- (a) ottoq_tick_invariance_reset_fleet: own the two charger columns
  ------------------------------------------------------------------
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_tick_invariance_reset_fleet';
  IF v_src IS NULL THEN RAISE EXCEPTION '0194: public.ottoq_tick_invariance_reset_fleet not found'; END IF;
  IF position('/* 0194 */' in v_src) > 0 THEN
    RAISE EXCEPTION '0194: reset_fleet already carries a 0194 edit - refusing to double-apply';
  END IF;
  IF position('0133' in v_src) = 0 OR position('0094' in v_src) = 0 THEN
    RAISE EXCEPTION '0194: reset_fleet is missing its 0133/0094 blocks - refusing to edit a body that is not the one certified';
  END IF;
  IF v_src ~ 'last_heartbeat_at' OR v_src ~ 'last_fault_at' THEN
    RAISE EXCEPTION '0194: reset_fleet already mentions heartbeat/fault_at - the premise of this migration is false, stop';
  END IF;
  v_n := (length(v_src) - length(replace(v_src, v_r1, ''))) / length(v_r1);
  IF v_n <> 1 THEN RAISE EXCEPTION '0194: anchor R1 occurs % times, expected 1', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, v_r2, ''))) / length(v_r2);
  IF v_n <> 1 THEN RAISE EXCEPTION '0194: anchor R2 occurs % times, expected 1', v_n; END IF;

  v_src := replace(v_src, v_r1,
    v_r1 || E'\n         -- 0194: the fingerprint hashes both; the decide path gates on heartbeat. The reset owns them.\n'
         || '         last_fault_at = NULL, last_heartbeat_at = COALESCE(p_as_of, now()), /* 0194 */');
  v_src := replace(v_src, v_r2,
    'OR c.station_state_changed_at IS DISTINCT FROM ''epoch''::timestamptz'
    || E'\n          OR c.last_fault_at IS NOT NULL'
    || E'\n          OR c.last_heartbeat_at IS DISTINCT FROM COALESCE(p_as_of, now()) /* 0194 */);');
  EXECUTE v_src;

  ------------------------------------------------------------------
  -- (b) ottoq_reopen_visit_atoms: a clock argument; five stamps
  ------------------------------------------------------------------
  SELECT pg_get_functiondef(p.oid),
         COALESCE((SELECT string_agg(a::text, ',' ORDER BY a::text) FROM unnest(p.proacl) a), '(null)')
    INTO v_src, v_acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_reopen_visit_atoms'
     AND pg_get_function_identity_arguments(p.oid) = 'p_vehicle uuid, p_svcs text[], p_since timestamp with time zone, p_reason text';
  IF v_src IS NULL THEN RAISE EXCEPTION '0194: public.ottoq_reopen_visit_atoms(uuid,text[],timestamptz,text) not found'; END IF;
  IF position('/* 0124 */' in v_src) = 0 THEN
    RAISE EXCEPTION '0194: reopen_visit_atoms has lost its 0124 run scoping - refusing to edit a body that is not the one certified';
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'ottoq_reopen_visit_atoms') <> 1 THEN
    RAISE EXCEPTION '0194: more than one ottoq_reopen_visit_atoms overload exists - resolve by hand';
  END IF;
  v_n := (length(v_src) - length(replace(v_src, 'now()', ''))) / length('now()');
  IF v_n <> 6 THEN RAISE EXCEPTION '0194: reopen_visit_atoms has % now() sites, expected 6 (five stamps + the 24h created_at filter)', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, v_hdr_old, ''))) / length(v_hdr_old);
  IF v_n <> 1 THEN RAISE EXCEPTION '0194: header anchor occurs % times, expected 1', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, v_s1, ''))) / length(v_s1);
  IF v_n <> 2 THEN RAISE EXCEPTION '0194: anchor S1 (reopened_at) occurs % times, expected 2', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, v_s2, ''))) / length(v_s2);
  IF v_n <> 1 THEN RAISE EXCEPTION '0194: anchor S2 (cut_short_at) occurs % times, expected 1', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, v_s3, ''))) / length(v_s3);
  IF v_n <> 1 THEN RAISE EXCEPTION '0194: anchor S3 (reopen_escalated_at) occurs % times, expected 1', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, v_s4, ''))) / length(v_s4);
  IF v_n <> 1 THEN RAISE EXCEPTION '0194: anchor S4 (last_at) occurs % times, expected 1', v_n; END IF;

  v_src := replace(v_src, v_hdr_old, v_hdr_new);
  v_src := replace(v_src, v_s1, '''reopened_at'', to_jsonb(COALESCE(p_at, now())), /* 0194 */');
  v_src := replace(v_src, v_s2, '''cut_short_at'', to_jsonb(COALESCE(p_at, now())), /* 0194 */');
  v_src := replace(v_src, v_s3, '''reopen_escalated_at'', COALESCE(p_at, now()), /* 0194 */');
  v_src := replace(v_src, v_s4, '''last_at'', COALESCE(p_at, now()), /* 0194 */');

  -- A new parameter is a new signature: CREATE OR REPLACE would leave the
  -- 4-argument body beside it and make every 4-argument call ambiguous.
  DROP FUNCTION public.ottoq_reopen_visit_atoms(uuid, text[], timestamptz, text);
  EXECUTE v_src;
  IF (SELECT COALESCE((SELECT string_agg(a::text, ',' ORDER BY a::text) FROM unnest(p.proacl) a), '(null)')
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'ottoq_reopen_visit_atoms') IS DISTINCT FROM v_acl THEN
    RAISE EXCEPTION '0194: the recreated reopen_visit_atoms does not carry the ACL the dropped one had (%)', v_acl;
  END IF;

  -- caller 1: the exception handler calls it TWICE (the eviction and the
  -- deferred-resume branch, reasons 'vehicle_fault_eviction' and
  -- 'vehicle_fault_eviction_deferred_resumed'); both pass p_sim_clock.
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_vehicle_exception_handler';
  IF v_src IS NULL THEN RAISE EXCEPTION '0194: twin.ottoq_sim_vehicle_exception_handler not found'; END IF;
  IF position('/* 0194 */' in v_src) > 0 THEN RAISE EXCEPTION '0194: exception handler already edited'; END IF;
  SELECT count(*) INTO v_n FROM regexp_matches(v_src, 'ottoq_reopen_visit_atoms\(', 'g');
  IF v_n <> 2 THEN RAISE EXCEPTION '0194: exception handler makes % reopen calls, expected 2', v_n; END IF;
  SELECT count(*) INTO v_n FROM regexp_matches(v_src, 'COALESCE\(v_starts, v_rec\.last_state_change\),\s*''vehicle_fault_eviction[^'']*''\s*\)', 'g');
  IF v_n <> 2 THEN RAISE EXCEPTION '0194: exception-handler call anchor occurs % times, expected 2 (one per call)', v_n; END IF;
  v_src := regexp_replace(v_src, '(COALESCE\(v_starts, v_rec\.last_state_change\),\s*''vehicle_fault_eviction[^'']*'')(\s*\))', '\1, p_sim_clock /* 0194 */\2', 'g');
  EXECUTE v_src;

  -- caller 2: release_vacated_spaces passes p_clock
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_release_vacated_spaces';
  IF v_src IS NULL THEN RAISE EXCEPTION '0194: ottoq.ottoq_release_vacated_spaces not found'; END IF;
  IF position('/* 0194 */' in v_src) > 0 THEN RAISE EXCEPTION '0194: release_vacated_spaces already edited'; END IF;
  SELECT count(*) INTO v_n FROM regexp_matches(v_src, 'ottoq_reopen_visit_atoms\(', 'g');
  IF v_n <> 1 THEN RAISE EXCEPTION '0194: release_vacated_spaces makes % reopen calls, expected 1', v_n; END IF;
  SELECT count(*) INTO v_n FROM regexp_matches(v_src, 'v_rec\.lo,\s*''bay_session_interrupted''\s*\)', 'g');
  IF v_n <> 1 THEN RAISE EXCEPTION '0194: release_vacated call anchor occurs % times, expected 1', v_n; END IF;
  v_src := regexp_replace(v_src, '(v_rec\.lo,\s*''bay_session_interrupted'')(\s*\))', '\1, p_clock /* 0194 */\2');
  EXECUTE v_src;

  ------------------------------------------------------------------
  -- (c) ottoq_sim_release_depot: teardown stamps with the run's clock
  ------------------------------------------------------------------
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_release_depot';
  IF v_src IS NULL THEN RAISE EXCEPTION '0194: public.ottoq_sim_release_depot not found'; END IF;
  IF position('/* 0194 */' in v_src) > 0 THEN RAISE EXCEPTION '0194: release_depot already edited'; END IF;
  IF position('0127' in v_src) = 0 OR position('0089' in v_src) = 0 OR position('0114' in v_src) = 0 THEN
    RAISE EXCEPTION '0194: release_depot is missing its 0114/0127/0089 blocks - refusing to edit a body that is not the one certified';
  END IF;
  v_n := (length(v_src) - length(replace(v_src, v_d1, ''))) / length(v_d1);
  IF v_n <> 1 THEN RAISE EXCEPTION '0194: anchor D1 (released_at=now()) occurs % times, expected 1', v_n; END IF;
  SELECT count(*) INTO v_n FROM regexp_matches(v_src, 'ended_at=now\(\),\s*stopped_reason=''sim_reset''', 'g');
  IF v_n <> 1 THEN RAISE EXCEPTION '0194: anchor D2 (ended_at=now()) occurs % times, expected 1', v_n; END IF;

  v_src := replace(v_src, v_d1, 'released_at=' || v_clock_idiom || ', release_reason=''run_stopped''');
  v_src := regexp_replace(v_src, 'ended_at=now\(\),(\s*)stopped_reason=''sim_reset''',
                                 'ended_at=' || v_clock_idiom || ',\1stopped_reason=''sim_reset''');
  EXECUTE v_src;
END
$mig$;

-- ─────────────────────────────────────────────────────────────────────
-- 2. THE ASSERTIONS -- A CHECK THAT CANNOT FAIL IS NOT A CHECK
-- ─────────────────────────────────────────────────────────────────────
DO $assert$
DECLARE
  v_src text; v_n int; v_m int;
  v_probe_depot uuid; v_probe_charger uuid; v_dirty int; v_total int;
  v_bad text[];
BEGIN
  -- A1. reset_fleet post-edit shape: both columns in the SET and in the
  --     change-detection predicate; two markers.
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_tick_invariance_reset_fleet';
  v_n := (length(v_src) - length(replace(v_src, 'last_heartbeat_at', ''))) / length('last_heartbeat_at');
  v_m := (length(v_src) - length(replace(v_src, 'last_fault_at', ''))) / length('last_fault_at');
  IF v_n <> 2 OR v_m <> 2 THEN RAISE EXCEPTION '0194 A1 FAILED: reset_fleet heartbeat mentions = %, fault_at mentions = %, expected 2 and 2', v_n, v_m; END IF;
  v_n := (length(v_src) - length(replace(v_src, '/* 0194 */', ''))) / length('/* 0194 */');
  IF v_n <> 2 THEN RAISE EXCEPTION '0194 A1 FAILED: reset_fleet 0194 markers = %, expected 2', v_n; END IF;

  -- A2. reset_fleet BEHAVIOUR, on live rows, rolled back. Pick the
  --     smallest non-flagship depot that has a stall-linked charger
  --     (the grid fixture), dirty one charger the way a real run does,
  --     run the reset, measure, then throw so the probe leaves nothing.
  SELECT d.id INTO v_probe_depot
    FROM depots d
   WHERE d.id <> '11111111-1111-1111-1111-111111111111'
     AND EXISTS (SELECT 1 FROM stalls s WHERE s.depot_id = d.id AND s.ocpp_charger_id IS NOT NULL)
   ORDER BY (SELECT count(*) FROM vehicles v WHERE v.home_depot_id = d.id), d.id
   LIMIT 1;
  IF v_probe_depot IS NULL THEN RAISE EXCEPTION '0194 A2 FAILED: no non-flagship depot with a linked charger to probe on'; END IF;
  SELECT s.ocpp_charger_id INTO v_probe_charger FROM stalls s
   WHERE s.depot_id = v_probe_depot AND s.ocpp_charger_id IS NOT NULL ORDER BY s.id LIMIT 1;
  BEGIN
    UPDATE ottoq_ocpp_chargers SET last_fault_at = '2026-07-23 12:00:00+00', last_heartbeat_at = '2026-09-01 08:00:00+00'
     WHERE charger_id = v_probe_charger;
    PERFORM public.ottoq_tick_invariance_reset_fleet(v_probe_depot, 4242, '2026-09-01 02:00:00+00'::timestamptz);
    SELECT count(*) FILTER (WHERE c.last_fault_at IS NOT NULL
                               OR c.last_heartbeat_at IS DISTINCT FROM '2026-09-01 02:00:00+00'::timestamptz),
           count(*)
      INTO v_dirty, v_total
      FROM ottoq_ocpp_chargers c
     WHERE c.charger_id IN (SELECT s.ocpp_charger_id FROM stalls s
                             WHERE s.depot_id = v_probe_depot AND s.ocpp_charger_id IS NOT NULL);
    RAISE EXCEPTION USING ERRCODE = 'P0194', MESSAGE = v_dirty::text || '/' || v_total::text;
  EXCEPTION WHEN SQLSTATE 'P0194' THEN
    -- the subtransaction is rolled back; only the measurement survives
    v_dirty := split_part(SQLERRM, '/', 1)::int;
    v_total := split_part(SQLERRM, '/', 2)::int;
  END;
  IF v_total = 0 THEN RAISE EXCEPTION '0194 A2 FAILED: probe depot % has no linked chargers after all', v_probe_depot; END IF;
  IF v_dirty <> 0 THEN RAISE EXCEPTION '0194 A2 FAILED: % of % chargers on depot % still carry a fault_at or a foreign heartbeat after reset', v_dirty, v_total, v_probe_depot; END IF;
  RAISE NOTICE '0194 A2: reset on depot % canonicalised %/% linked chargers (probe rolled back)', v_probe_depot, v_total, v_total;

  -- A3. reopen_visit_atoms post-edit shape: one overload, five
  --     arguments, the fifth defaulted; five clocked stamps; exactly one
  --     bare now() left (the 24-hour created_at window, a wall-clock
  --     column filtered by the wall clock, correct as it is).
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'ottoq_reopen_visit_atoms') <> 1 THEN
    RAISE EXCEPTION '0194 A3 FAILED: ottoq_reopen_visit_atoms overload count <> 1';
  END IF;
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_reopen_visit_atoms'
     AND pg_get_function_identity_arguments(p.oid) = 'p_vehicle uuid, p_svcs text[], p_since timestamp with time zone, p_reason text, p_at timestamp with time zone'
     AND pg_get_function_arguments(p.oid) LIKE '%p_at timestamp with time zone DEFAULT NULL%';
  IF v_src IS NULL THEN RAISE EXCEPTION '0194 A3 FAILED: the five-argument reopen_visit_atoms with p_at DEFAULT NULL does not exist'; END IF;
  v_n := (length(v_src) - length(replace(v_src, 'COALESCE(p_at, now())', ''))) / length('COALESCE(p_at, now())');
  IF v_n <> 5 THEN RAISE EXCEPTION '0194 A3 FAILED: clocked stamp sites = %, expected 5', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, 'now()', ''))) / length('now()');
  IF v_n <> 6 THEN RAISE EXCEPTION '0194 A3 FAILED: total now() sites = %, expected 6 (5 inside COALESCE + the created_at window)', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, 'created_at >= now() - interval ''24 hours''', ''))) / length('created_at >= now() - interval ''24 hours''');
  IF v_n <> 1 THEN RAISE EXCEPTION '0194 A3 FAILED: the created_at window is not the one remaining bare now()'; END IF;

  -- A4. EVERY call in both tick-path callers passes a clock: the number
  --     of reopen calls in each function equals the number of clocked
  --     calls (exception handler: 2 of 2 with p_sim_clock;
  --     release_vacated_spaces: 1 of 1 with p_clock). Nobody else calls it.
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_vehicle_exception_handler';
  SELECT count(*) INTO v_n FROM regexp_matches(v_src, 'ottoq_reopen_visit_atoms\(', 'g');
  SELECT count(*) INTO v_m FROM regexp_matches(v_src, 'ottoq_reopen_visit_atoms\([^;]*, p_sim_clock /\* 0194 \*/\s*\);', 'g');
  IF v_n <> 2 OR v_m <> 2 THEN
    RAISE EXCEPTION '0194 A4 FAILED: exception handler has % reopen calls, % of them clocked with p_sim_clock (expected 2 and 2)', v_n, v_m;
  END IF;
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_release_vacated_spaces';
  SELECT count(*) INTO v_n FROM regexp_matches(v_src, 'ottoq_reopen_visit_atoms\(', 'g');
  SELECT count(*) INTO v_m FROM regexp_matches(v_src, 'ottoq_reopen_visit_atoms\([^;]*, p_clock /\* 0194 \*/\s*\);', 'g');
  IF v_n <> 1 OR v_m <> 1 THEN
    RAISE EXCEPTION '0194 A4 FAILED: release_vacated_spaces has % reopen calls, % of them clocked with p_clock (expected 1 and 1)', v_n, v_m;
  END IF;
  SELECT array_agg(n.nspname||'.'||p.proname ORDER BY 1) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq') AND p.prokind IN ('f','p')
     AND p.proname <> 'ottoq_reopen_visit_atoms'
     AND pg_get_functiondef(p.oid) LIKE '%ottoq_reopen_visit_atoms(%'
     AND pg_get_functiondef(p.oid) NOT LIKE '%/* 0194 */%';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0194 A4 FAILED: callers of reopen_visit_atoms that still pass no clock: %', v_bad;
  END IF;

  -- A5. release_depot post-edit: no wall-clock release or session end
  --     remains; the run-clock idiom appears three times (0089's leg
  --     close plus the two edits); two markers. And THE CLASS: no
  --     function in the engine schemas reads released_at as a value.
  --     Allowed: assignments, comment lines, and the jsonb key
  --     'released_at' that emergency release writes into a payload.
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_release_depot';
  IF v_src ~ 'released_at\s*=\s*now\(\)' THEN RAISE EXCEPTION '0194 A5 FAILED: released_at=now() survives in release_depot'; END IF;
  IF v_src ~ 'ended_at\s*=\s*now\(\)' THEN RAISE EXCEPTION '0194 A5 FAILED: ended_at=now() survives in release_depot'; END IF;
  SELECT count(*) INTO v_n FROM regexp_matches(v_src, 'SELECT COALESCE\(r\.sim_clock_current, now\(\)\) FROM ottoq_sim_runs r', 'g');
  IF v_n <> 3 THEN RAISE EXCEPTION '0194 A5 FAILED: run-clock idiom count = %, expected 3', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, '/* 0194 */', ''))) / length('/* 0194 */');
  IF v_n <> 2 THEN RAISE EXCEPTION '0194 A5 FAILED: release_depot 0194 markers = %, expected 2', v_n; END IF;

  SELECT array_agg(DISTINCT fn ORDER BY fn) INTO v_bad
    FROM (
      SELECT n.nspname||'.'||p.proname AS fn, m.line
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        CROSS JOIN LATERAL regexp_split_to_table(pg_get_functiondef(p.oid), E'\n') AS m(line)
       WHERE n.nspname IN ('public','twin','ottoq') AND p.prokind IN ('f','p')
         AND (p.proname LIKE 'ottoq%' OR n.nspname <> 'public')
         AND regexp_replace(m.line, '--.*$', '') ~ '\mreleased_at\M'
         AND regexp_replace(m.line, '--.*$', '') !~ 'released_at\s*='
         AND regexp_replace(m.line, '--.*$', '') !~ '''released_at'''
    ) q;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0194 A5 FAILED: functions that read released_at as a value (the premise "nothing on the decide path reads it" is false): %', v_bad;
  END IF;

  RAISE NOTICE '0194: all assertions passed.';
END
$assert$;

-- ─────────────────────────────────────────────────────────────────────
-- 3. LINEAGE
-- ─────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0194_three_wall_clocks_in_the_world_the_fingerprint_hashes', TRUE,
  'Round 14 pair 1 (19:06 UTC, busy_day/171717/12t) passed on every canon while its two boot fingerprints disagreed on '
  'chargers.world: ottoq_tick_invariance_reset_fleet never owned last_fault_at (45 non-null, 31 distinct values on the flagship) '
  'or last_heartbeat_at (the previous run''s final sim clock), both hashed by the fingerprint, and heartbeat is the liveness gate '
  'book_appointment, plan_opportunistic_charges, prearrival_contracts and both L2 proposers read -- silent today only because every '
  'certification run starts at the same sim instant. The reset now sets last_fault_at NULL and last_heartbeat_at = p_as_of, with '
  'the change-detection predicate extended (A2 proves it on live rows, rolled back). Two more wall clocks in the same fingerprint: '
  'ottoq_reopen_visit_atoms stamped reopened_at/cut_short_at/reopen_escalated_at/last_at with now() because it had no clock '
  'argument (p_since is the session start, not the call time; 73 flagship visits carry wall-clock stamps) -- it gains p_at DEFAULT '
  'NULL and both tick-path callers pass the clock they hold; and ottoq_sim_release_depot released the run''s open bookings and '
  'cancelled sessions with now() (91,196 flagship bookings) three statements before 0089''s leg close already used the run''s '
  'sim_clock_current -- same idiom, now for both. No decide-path function reads released_at (A5 census refuses the migration '
  'otherwise). The fingerprint is not narrowed: all three columns stay hashed, so endst gets sharper, not blinder. Not touched: '
  'twin.ottoq_sim_seed_fleet, ottoq_benchmark_reset, ottoq_cert_arm_start (heartbeat = now(), none on the pair path). '
  'forces_recert=TRUE; the prediction is that every engine canon (h_cmd/h_dec/h_evt/h_bkg/h_nrg) is unchanged from round 14 and '
  'that endst finally agrees between two pairs of the same column.',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

COMMIT;

-- =====================================================================
-- APPLIED 2026-09-04 20:55:20 UTC (3:55 PM CT), after round 14 closed
-- (six pairs done, zero pair backends, no jobs left). All assertions
-- passed:
--   A1  reset_fleet: heartbeat and fault_at each mentioned twice (SET +
--       predicate), two 0194 markers.
--   A2  live reset on the grid fixture depot, rolled back: every linked
--       charger left with last_fault_at NULL and heartbeat = p_as_of.
--   A3  one reopen_visit_atoms overload, five arguments, p_at DEFAULT
--       NULL, five clocked stamps, one bare now() (the created_at window).
--   A4  exception handler 2 of 2 calls clocked, release_vacated_spaces
--       1 of 1; no other caller.
--   A5  release_depot: no released_at/ended_at = now(); run-clock idiom
--       x3; no engine function reads released_at as a value.
--   lineage forces_recert = true.
-- Applied together with 0195 (the round-14 pair-2 fix) before round 15.
--
-- =====================================================================
-- THE PREDICTION (published before the round)
-- =====================================================================
-- 1. Round 15 (six columns, after round 14 completes and this applies)
--    passes every column, and every engine canon -- h_cmd, h_dec, h_evt,
--    h_bkg, h_nrg -- is BYTE-IDENTICAL to round 14's value for the same
--    column. This migration touches nothing the decide path reads
--    except a heartbeat that the world tick overwrites before the first
--    decision; if any engine canon moves, that claim is false and the
--    decision_seq diff names where.
-- 2. In every round-15 pair, the two arms' BOOT fingerprints agree on
--    chargers.world (round 14 pair 1: bce038e9 vs bb34f348), and every
--    round-15 pair of the same scenario agrees with every other on it.
-- 3. busy_day/171717/12t runs TWICE in round 15, at different times.
--    Their endst fingerprints agree on every section -- visit_needs.vis,
--    bookings.vis, legs.vis, dispatches.vis, chargers.world. This is the
--    inter-pair bar 0108 set and no round has met.
-- 4. Every reopened_at, cut_short_at and reopen_escalated_at written by
--    a round-15 run lies inside that run's sim window (2026-09-01 02:00
--    to its sim_clock_end). Zero wall-clock stamps.
-- 5. Every run_stopped booking release written by a round-15 run has
--    released_at = that run's sim_clock_end, and every sim_reset session
--    end likewise.
-- =====================================================================
