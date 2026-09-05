-- =====================================================================
-- 0196  Two flags that die with the transaction, and the pair is one
--       transaction
-- =====================================================================
-- forces_recert = TRUE. This changes what a tick sees at its start: two
-- transaction-local settings are cleared. Under pg_cron a tick is its
-- own transaction and both already die at its end, so production does
-- not move. The certification pair runs both arms and every tick in ONE
-- transaction, so it does.
--
-- THE FAILURE (round 15, pair 1, 21:02 UTC, busy_day/314159/12t)
-- ---------------------------------------------------------------------
-- 0195 reordered the bay-seating cursor and predicted this column would
-- go green with a canon matching neither of round 14's arms. It stayed
-- RED -- and its two arms reproduced round 14's canons EXACTLY, by arm
-- position:
--
--                        round 14 (19:26)   round 15 (21:02)
--   first arm   h_cmd    cf74d080           cf74d080
--   second arm  h_cmd    f2bd5208           f2bd5208
--   swallowed 23505s     4 / 6              4 / 6
--
-- A coin does not land the same way twice by arm. The divergence is a
-- deterministic function of BEING the second arm: something the first
-- arm leaves behind that the reset cannot see, the fingerprint cannot
-- hash, and 0193's residue sweep could not find, because it is not in
-- a table.
--
-- WHAT THE FIRST ARM LEAVES BEHIND
-- ---------------------------------------------------------------------
-- public.ottoq_indepot_reassignment_guard, when it says yes, calls
-- public.ottoq_mark_reassign_granted, which appends the vehicle id to a
-- transaction-local setting:
--
--   set_config('ottoq.reassign_ok', current || vehicle_id || ',', true)
--   -- "is_local => true is TRANSACTION-scoped: the grant dies with the
--   --  transaction, so it can never authorise a release in some later,
--   --  unrelated one."
--
-- public.ottoq_trg_reassignment_guard (BEFORE UPDATE ON stalls) reads
-- it first: a vehicle in the list may vacate a mid-work bay without the
-- gate being asked again. The gate says yes on every 'outside_walls'
-- call (any vehicle deployed, en route or offline), so the list grows
-- with every fault handled and every prearrival checked. Under pg_cron
-- the list dies with the tick. Under ottoq_determinism_pair it lives
-- for both arms: the second arm starts with every grant the first arm
-- ever stamped, its guard lets cars vacate bays the first arm's guard
-- refused, one stall per car holds where it did not before, and the
-- bay-seating tick that threw 23505 in the first arm does not throw in
-- the second. Hence 4 versus 6, and hence the same 4 versus 6 twice.
-- The same list also persists across TICKS inside one arm, which is a
-- fidelity gap against production even when both arms agree.
--
-- The second flag is the same shape. twin.ottoq_sim_prime_deployment
-- sets ottoq.skip_wash_bump = '1' (transaction-local) so its boot
-- inserts do not count as deploy cycles; public.ottoq_dispatch_bump_wash_cycle
-- returns early while it is set. Under an RPC-driven prime the flag
-- dies before the first tick. Under the pair it is '1' for every tick
-- of both arms: no certification run has ever bumped a wash cycle.
-- Both arms agree, so no pair went red for it; every canon is for a
-- world in which cars never get dirtier.
--
-- ALSO: FIVE CHARGERS NO STALL POINTS AT
-- ---------------------------------------------------------------------
-- 0194 made the reset own last_fault_at and last_heartbeat_at -- for
-- the chargers a stall points at, the 0093/0094 population. The
-- fingerprint's ch CTE hashes every charger of the depot. The flagship
-- has five without a stall; the world tick writes their heartbeat too.
-- Round 15: every arm booted with chargers.world c83d7288 except the
-- first arm of the first pair (9c25b338), the only one whose
-- predecessor was a 24-tick run and left 2026-09-02 on those five.
--
-- WHAT THIS MIGRATION DOES
-- ---------------------------------------------------------------------
-- 1. public.ottoq_sim_advance_tick clears ottoq.reassign_ok and
--    ottoq.skip_wash_bump as its first act. A grant now lives at most
--    one tick in every driver; the prime-time flag never reaches a tick.
--    Production, where a tick is a transaction, cannot observe the
--    change. The pair, where it is not, now matches production.
-- 2. ottoq_tick_invariance_reset_fleet resets last_fault_at and
--    last_heartbeat_at on the depot's unlinked chargers as well.
--
-- WHAT IT DOES NOT DO
-- ---------------------------------------------------------------------
-- It does not key the grant by run (writer and reader would both take
-- ottoq.sim_run_id as a prefix). With a tick-local grant that is
-- defence in depth against a future multi-run transaction, not a fix
-- for anything observed; recorded as hardening.
-- It does not revisit 0195. Its order fix is still correct -- the
-- cursor is now total across runs -- it just was not this column's
-- cause. 0195's predictions 1 and 3 were wrong and db/checks/0111 says
-- so; its A2 proof of a differing order stands.
-- =====================================================================

BEGIN;

DO $mig$
DECLARE
  v_src text; v_n int;
  v_t1 text := E'BEGIN\n  SELECT * INTO w FROM ottoq_sim_advance_tick_world(p_sim_run_id);';
  v_r1 text := 'OR c.last_heartbeat_at IS DISTINCT FROM COALESCE(p_as_of, now()) /* 0194 */);';
BEGIN
  -- (1) the tick clears both flags first
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_advance_tick';
  IF v_src IS NULL THEN RAISE EXCEPTION '0196: public.ottoq_sim_advance_tick not found'; END IF;
  IF position('/* 0196 */' in v_src) > 0 THEN RAISE EXCEPTION '0196: advance_tick already edited - refusing to double-apply'; END IF;
  IF position('0102' in v_src) = 0 THEN RAISE EXCEPTION '0196: advance_tick is missing its 0102 block - refusing to edit a body that is not the one certified'; END IF;
  v_n := (length(v_src) - length(replace(v_src, v_t1, ''))) / length(v_t1);
  IF v_n <> 1 THEN RAISE EXCEPTION '0196: advance_tick first-statement anchor occurs % times, expected 1', v_n; END IF;
  v_src := replace(v_src, v_t1,
       E'BEGIN\n'
    || E'  -- 0196: transaction-local flags are TICK-local by contract. Under pg_cron a tick\n'
    || E'  -- is its own transaction and these die with it; under the certification pair\n'
    || E'  -- both arms and every tick share one transaction, so a grant stamped in arm A\n'
    || E'  -- authorised stall vacates in arm B (db/checks/0111). Clear them here so every\n'
    || E'  -- driver sees the same world at every tick boundary.\n'
    || E'  PERFORM set_config(''ottoq.reassign_ok'', '''', true);\n'
    || E'  PERFORM set_config(''ottoq.skip_wash_bump'', '''', true); /* 0196 */\n'
    || E'  SELECT * INTO w FROM ottoq_sim_advance_tick_world(p_sim_run_id);');
  EXECUTE v_src;

  -- (2) the reset owns the unlinked chargers' stamps too
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_tick_invariance_reset_fleet';
  IF v_src IS NULL THEN RAISE EXCEPTION '0196: public.ottoq_tick_invariance_reset_fleet not found'; END IF;
  IF position('/* 0196 */' in v_src) > 0 THEN RAISE EXCEPTION '0196: reset_fleet already edited - refusing to double-apply'; END IF;
  v_n := (length(v_src) - length(replace(v_src, v_r1, ''))) / length(v_r1);
  IF v_n <> 1 THEN RAISE EXCEPTION '0196: reset_fleet 0194 predicate anchor occurs % times, expected 1', v_n; END IF;
  v_src := replace(v_src, v_r1,
       v_r1
    || E'\n  -- 0196: the chargers no stall points at carry the last run''s heartbeat and fault\n'
    || E'  -- stamps too, and the fingerprint hashes every charger of the depot.\n'
    || E'  UPDATE public.ottoq_ocpp_chargers c\n'
    || E'     SET last_fault_at = NULL, last_heartbeat_at = COALESCE(p_as_of, now()) /* 0196 */\n'
    || E'   WHERE c.depot_id = p_depot_id\n'
    || E'     AND c.charger_id NOT IN (SELECT s.ocpp_charger_id FROM public.stalls s\n'
    || E'                              WHERE s.depot_id = p_depot_id AND s.ocpp_charger_id IS NOT NULL)\n'
    || E'     AND (c.last_fault_at IS NOT NULL\n'
    || E'          OR c.last_heartbeat_at IS DISTINCT FROM COALESCE(p_as_of, now()));');
  EXECUTE v_src;
END
$mig$;

DO $assert$
DECLARE
  v_src text; v_n int; v_m int;
  v_a14 text; v_b14 text; v_a15 text; v_b15 text;
  v_probe_depot uuid; v_probe_charger uuid; v_dirty int; v_total int;
  v_keys text[];
BEGIN
  -- A1. Shapes. advance_tick: the two clears are the first statements after
  --     BEGIN and precede the world call; reset_fleet: the unlinked-charger
  --     UPDATE sits right after the 0194 predicate.
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_advance_tick';
  IF v_src !~ 'set_config\(''ottoq\.reassign_ok'', '''', true\);\s*PERFORM set_config\(''ottoq\.skip_wash_bump'', '''', true\); /\* 0196 \*/\s*SELECT \* INTO w FROM ottoq_sim_advance_tick_world\(p_sim_run_id\);' THEN
    RAISE EXCEPTION '0196 A1 FAILED: the two clears do not immediately precede the world call';
  END IF;
  v_n := (length(v_src) - length(replace(v_src, '/* 0196 */', ''))) / length('/* 0196 */');
  IF v_n <> 1 THEN RAISE EXCEPTION '0196 A1 FAILED: advance_tick markers = %, expected 1', v_n; END IF;
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_tick_invariance_reset_fleet';
  v_n := (length(v_src) - length(replace(v_src, '/* 0196 */', ''))) / length('/* 0196 */');
  IF v_n <> 1 THEN RAISE EXCEPTION '0196 A1 FAILED: reset_fleet markers = %, expected 1', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, 'last_heartbeat_at', ''))) / length('last_heartbeat_at');
  IF v_n <> 4 THEN RAISE EXCEPTION '0196 A1 FAILED: reset_fleet heartbeat mentions = %, expected 4 (0194 SET + predicate, 0196 SET + predicate)', v_n; END IF;

  -- A2. THE CONVICTION IS IN THE ROWS: the two red pairs of busy_day/314159/12t
  --     (round 14 at 19:26 UTC, round 15 at 21:02 UTC) carry identical canons per
  --     arm position and different canons across positions.
  SELECT j->'arm_a'->>'h_cmd', j->'arm_b'->>'h_cmd' INTO v_a14, v_b14
    FROM (SELECT validation_notes::jsonb AS j FROM ottoq_sim_runs
           WHERE sim_run_id = 'ae0d8488-f245-4b6b-8f1a-de77a0362ba2') q;
  SELECT j->'arm_a'->>'h_cmd', j->'arm_b'->>'h_cmd' INTO v_a15, v_b15
    FROM (SELECT validation_notes::jsonb AS j FROM ottoq_sim_runs r
           WHERE r.started_at BETWEEN '2026-09-04 21:01+00' AND '2026-09-04 21:03+00'
             AND r.validation_notes ~ '^\s*\{' AND r.validation_notes::jsonb->>'seed' = '314159'
           ORDER BY r.started_at LIMIT 1) q;
  IF v_a14 IS NULL OR v_a15 IS NULL THEN RAISE EXCEPTION '0196 A2 FAILED: the two red pairs are not there to test against'; END IF;
  IF v_a14 <> v_a15 OR v_b14 <> v_b15 THEN
    RAISE EXCEPTION '0196 A2 FAILED: canons are not reproduced by arm position (A: % vs %, B: % vs %) - the premise is false', v_a14, v_a15, v_b14, v_b15;
  END IF;
  IF v_a14 = v_b14 THEN RAISE EXCEPTION '0196 A2 FAILED: the two arms agree - there is no divergence to explain'; END IF;
  RAISE NOTICE '0196 A2: rounds 14 and 15 reproduce the red pair''s canons by arm position (A %, B %)', left(v_a14,8), left(v_b14,8);

  -- A3. THE CLASS. Every custom ottoq.* setting a tick-path function writes
  --     with is_local => true is one of: cleared at tick start (this
  --     migration), sim_run_id (set by every driver before use), dryrun
  --     (set on and off around the MPC call), retention (purge worker, not
  --     the tick). A new one refuses this migration.
  SELECT array_agg(DISTINCT m[1] ORDER BY m[1]) INTO v_keys
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    CROSS JOIN LATERAL regexp_matches(pg_get_functiondef(p.oid), 'set_config\(''(ottoq\.[a-z_]+)''[^;]*, *true\)', 'g') m
   WHERE n.nspname IN ('public','twin','ottoq') AND p.prokind IN ('f','p');
  IF v_keys IS DISTINCT FROM ARRAY['ottoq.dryrun','ottoq.reassign_ok','ottoq.retention','ottoq.sim_run_id','ottoq.skip_wash_bump'] THEN
    RAISE EXCEPTION '0196 A3 FAILED: transaction-local ottoq.* settings are %, not the five this migration accounts for', v_keys;
  END IF;

  -- A4. Reset BEHAVIOUR on unlinked chargers, live rows, rolled back: the
  --     smallest non-flagship depot that HAS an unlinked charger.
  SELECT d.id INTO v_probe_depot
    FROM depots d
   WHERE d.id <> '11111111-1111-1111-1111-111111111111'
     AND EXISTS (SELECT 1 FROM ottoq_ocpp_chargers c WHERE c.depot_id = d.id
                    AND NOT EXISTS (SELECT 1 FROM stalls s WHERE s.ocpp_charger_id = c.charger_id))
   ORDER BY (SELECT count(*) FROM vehicles v WHERE v.home_depot_id = d.id), d.id
   LIMIT 1;
  IF v_probe_depot IS NULL THEN RAISE EXCEPTION '0196 A4 FAILED: no non-flagship depot with an unlinked charger to probe on'; END IF;
  SELECT c.charger_id INTO v_probe_charger FROM ottoq_ocpp_chargers c
   WHERE c.depot_id = v_probe_depot AND NOT EXISTS (SELECT 1 FROM stalls s WHERE s.ocpp_charger_id = c.charger_id)
   ORDER BY c.charger_id LIMIT 1;
  BEGIN
    UPDATE ottoq_ocpp_chargers SET last_fault_at = '2026-07-23 12:00:00+00', last_heartbeat_at = '2026-09-02 02:00:00+00'
     WHERE charger_id = v_probe_charger;
    PERFORM public.ottoq_tick_invariance_reset_fleet(v_probe_depot, 4242, '2026-09-01 02:00:00+00'::timestamptz);
    SELECT count(*) FILTER (WHERE c.last_fault_at IS NOT NULL
                               OR c.last_heartbeat_at IS DISTINCT FROM '2026-09-01 02:00:00+00'::timestamptz),
           count(*)
      INTO v_dirty, v_total
      FROM ottoq_ocpp_chargers c WHERE c.depot_id = v_probe_depot;
    RAISE EXCEPTION USING ERRCODE = 'P0196', MESSAGE = v_dirty::text || '/' || v_total::text;
  EXCEPTION WHEN SQLSTATE 'P0196' THEN
    v_dirty := split_part(SQLERRM, '/', 1)::int;
    v_total := split_part(SQLERRM, '/', 2)::int;
  END;
  IF v_total = 0 THEN RAISE EXCEPTION '0196 A4 FAILED: probe depot % has no chargers after all', v_probe_depot; END IF;
  IF v_dirty <> 0 THEN RAISE EXCEPTION '0196 A4 FAILED: % of % chargers on depot % still carry a fault_at or a foreign heartbeat after reset', v_dirty, v_total, v_probe_depot; END IF;
  RAISE NOTICE '0196 A4: reset on depot % canonicalised all %/% chargers, linked or not (probe rolled back)', v_probe_depot, v_total, v_total;

  RAISE NOTICE '0196: all assertions passed.';
END
$assert$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0196_two_flags_that_die_with_the_transaction_and_the_pair_is_one_transaction', TRUE,
  'Round 15 pair 1 (21:02 UTC, busy_day/314159/12t) stayed red after 0195 and reproduced round 14''s canons exactly by arm '
  'position (A cf74d080, B f2bd5208; swallowed 23505s 4/6 both times): the divergence is a deterministic function of being the '
  'second arm. ottoq_mark_reassign_granted appends every granted vehicle to the transaction-local setting ottoq.reassign_ok, '
  'ottoq_trg_reassignment_guard lets a listed vehicle vacate a mid-work bay unasked, and the pair runs both arms and every tick in '
  'one transaction, so the second arm inherits every grant the first arm stamped -- not a table, so no reset, fingerprint or residue '
  'sweep could see it. Same shape: twin.ottoq_sim_prime_deployment''s ottoq.skip_wash_bump stays ''1'' for every tick of both arms, '
  'so no certification run has ever bumped a wash cycle. Fix: public.ottoq_sim_advance_tick clears both settings as its first act, '
  'which production (one transaction per tick) cannot observe and the pair now matches. Also: 0194''s reset owned only the '
  'stall-linked chargers'' heartbeat/fault stamps; the five unlinked flagship chargers are hashed too and booted the first arm of '
  'round 15 with a different chargers.world; the reset now owns them as well (A4 proves it on live rows, rolled back). Not done: '
  'keying the grant by run (hardening). 0195''s predictions 1 and 3 were wrong; its order fix stands as correct but not causal. '
  'forces_recert=TRUE: busy_day/314159/12t must go green; every canon moves (wash cycles now bump in certification runs).',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

COMMIT;

-- =====================================================================
-- APPLIED 2026-09-05 01:37:04 UTC (8:37 PM CT on 09-04), first attempt,
-- after round 15 closed (seven pairs done, zero pair backends, no jobs).
-- The session that armed the 22:50 UTC check-in was disconnected until
-- 01:35 UTC; the round waited, nothing ran in between. All assertions
-- passed:
--   A1  the two clears are the first statements of advance_tick and
--       precede the world call; reset_fleet carries the 0196 UPDATE.
--   A2  rounds 14 and 15 reproduce the red pair's canons by arm
--       position (A cf74d080, B f2bd5208) and the arms differ.
--   A3  the transaction-local ottoq.* settings are exactly the five
--       accounted for (dryrun, reassign_ok, retention, sim_run_id,
--       skip_wash_bump).
--   A4  live reset on a depot with an unlinked charger, rolled back:
--       every charger, linked or not, left with fault_at NULL and
--       heartbeat = p_as_of.
--   lineage forces_recert = true.
-- Round 16 scheduled 01:38 UTC, the red column first.
--
-- =====================================================================
-- THE PREDICTION (published before round 16)
-- =====================================================================
-- 1. busy_day/314159/12t passes in round 16, both arms complete, with a
--    canon that is neither cf74d080 nor f2bd5208, and the swallowed-
--    23505 log count is the SAME in both arms.
-- 2. EVERY column's engine canon moves from round 15's value, including
--    the ones that were green -- wash cycles now bump in certification
--    runs, and washes reshape every schedule. A column whose canon does
--    NOT move is evidence against the skip_wash_bump half of this
--    migration and will be said so.
-- 3. Every arm of every round-16 pair boots with the same chargers.world
--    as every other arm of the same scenario, whatever ran before it.
-- 4. busy_day/171717/12t, run twice again, agrees with its twin on every
--    endst section (round 15 met this bar; it must survive the change).
-- =====================================================================
