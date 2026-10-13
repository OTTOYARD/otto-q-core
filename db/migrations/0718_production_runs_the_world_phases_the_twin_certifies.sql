-- migration-version: 20261013210801
-- migration-name:    production_runs_the_world_phases_the_twin_certifies
--
-- 0718  **Production's world step runs the three phases the certified world runs and it never did.** (G436; the
--        study's DC-3; CLAUDE.md rule 9.)
--
-- ══ §1 WHY (measured 2026-10-13, read-only, db/checks/0447) ══════════════════════════════════════════════════════════
--
--   A production session ticks through public.ottoq_cron_tick (job 10, every 2 minutes) -> twin.ottoq_world_advance(),
--   a hand-made copy whose own comment calls it a "mirror of advance_tick_world". Certification covers
--   public.ottoq_sim_advance_tick_world. Their callee sets, comment-stripped, differ by exactly three functions, all
--   present in the certified world and absent from production's:
--
--     ottoq.ottoq_owner_orders_tick        what an owner set for its own cars: charge limits, service orders, holds
--     twin.ottoq_arm_advance_cycles        the charging robot's mate and demate cycles
--     public.ottoq_release_expired_tethers the only function that ends a fast charger's demate tether
--
--   Nothing else calls the last two or the first (census in 0447 §1). What that means in a production session:
--
--   (a) FAST CHARGERS ARE NEVER HANDED BACK. twin.ottoq_sim_stop_charge_session ends a DCFC session by writing a demate
--       tether (robotic_tether_until = now + the demate time) and leaves the car pointing at the stall and the stall
--       occupied by the car, "until ottoq_release_expired_tethers frees it". Production never calls it. Once the tether
--       has expired the arm interlock lets the car move, but public.sync_stall_occupancy will not free the old stall
--       while NEW.robotic_tether_until IS NOT NULL and the tether names that stall, and nothing clears it. So each fast
--       charge leaves its charger held by a car that has left it. The twin depot has ten.
--   (b) AN OWNER'S ORDER IS NEVER APPLIED (rule 9). An owner's service order waits with pending_reconcile until the
--       owner-orders step attaches it to the car's visit. public.ottoq_owner_departure_blocked holds the car for that
--       step for at most 60 sim minutes, "so a tick step that kept failing could not keep a car forever". In production
--       the step never runs, so the car is held an hour and then may leave without the service its owner ordered, and
--       an owner's charge limit is never written to the car. ottoq_owner_settings holds 0 rows today: latent until the
--       first owner sets one, which is exactly when it matters.
--   (c) THE ARM NEVER MOVES. A mate opened when a DCFC session starts is never walked, so no registration is written.
--
--   Production has run 9 sessions, the longest 4,050 ticks in July, before the tether (0011-TETHER) or owner orders
--   (0605) existed; the three since are 0, 6 and 7 ticks. Nothing has measured it because nothing has run it.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   Three insertions into twin.ottoq_world_advance (md5-guarded on 3489fb1392073751df4f601d45dc7731), each placed where
--   the certified world has it and wrapped the way every production phase is (a hiccup never aborts the tick):
--     1. ottoq.ottoq_owner_orders_tick(run, v_now) before the visit atoms advance (0605's position);
--     2. twin.ottoq_arm_advance_cycles(run, v_now), sim feed only, first in the charge block (before the heartbeat
--        and the session reconcile, so a pending mate settles before anything can end the charge under it);
--     3. public.ottoq_release_expired_tethers(v_now) after the charger recovery and before the charger reconcile, so a
--        plug freed here is healed to Available in the same tick.
--   Nothing is removed or reordered. The gate rule stays production's own, target-aware one (the certified world's is a
--   hard 85% cut; making them one rule is the study's item 18 and forces recert). The release is global, exactly as the
--   certified world's call is: it ends every tether whose deadline has passed on the clock it is given.
--
--   V3 asserts parity: the certified world's callee set, comment-stripped, is contained in production's.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════
--
--   twin.ottoq_world_advance is called by public.ottoq_cron_tick and public.ottoq_production_start only, and it returns
--   at once unless a run_by = 'production_live' run is running. No pair, dial arm, sweep or demo run reaches it; the
--   certified world is not touched.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0718_pre';
--   DELETE FROM ottoq_cert_lineage WHERE name = '0718_production_runs_the_world_phases_the_twin_certifies'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0718 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the definition this file was written against, and no production session running under it ──
DO $premises$
DECLARE v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef('twin.ottoq_world_advance()'::regprocedure)) INTO v_md5;
  IF v_md5 IS DISTINCT FROM '3489fb1392073751df4f601d45dc7731' THEN
    RAISE EXCEPTION '0718 P1: twin.ottoq_world_advance is not the definition this file was written against (md5 %)', v_md5;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE run_by = 'production_live' AND status = 'running') THEN
    RAISE EXCEPTION '0718 P1: a production session is running; apply between sessions';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0718_pre', 'function', 'twin', 'ottoq_world_advance', pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p WHERE p.oid = 'twin.ottoq_world_advance()'::regprocedure;

-- ── the three insertions, each anchor asserted to match exactly once ──
DO $sub$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_world_advance()'::regprocedure);
  v_a1 constant text := $a$  -- ===== PRE-TELEMETRY ORCHESTRATION (mirror of advance_tick_world) =====
$a$;
  v_n1 constant text := $n$  -- 0718 (G436): what an owner set for its own cars (charge limits, service orders, holds), applied before the
  -- visit atoms and the charges advance, as the certified world does (0605). Inert on a run no owner touched.
  BEGIN PERFORM ottoq.ottoq_owner_orders_tick(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance owner_orders: %', SQLERRM; END;

  -- ===== PRE-TELEMETRY ORCHESTRATION (mirror of advance_tick_world) =====
$n$;
  v_a2 constant text := $a$  IF v_feed_sim THEN
  BEGIN UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_now
$a$;
  v_n2 constant text := $n$  IF v_feed_sim THEN
  -- 0718 (G436): the arm moves first, as in the certified world, so a mate opened last tick settles (and writes its
  -- registration) before the charge block below can end the session under it.
  BEGIN PERFORM twin.ottoq_arm_advance_cycles(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance arm: %', SQLERRM; END;
  BEGIN UPDATE ottoq_ocpp_chargers SET last_heartbeat_at = v_now
$n$;
  v_a3 constant text := $a$  BEGIN PERFORM ottoq_reconcile_charger_states(v_run.depot_id);
$a$;
  v_n3 constant text := $n$  -- 0718 (G436): the single releaser of a fast charger's demate tether. Without it a DCFC stall stays held by a car
  -- that has left it (sync_stall_occupancy will not free a stall a tether still names). Before the charger reconcile,
  -- so a plug freed here is Available in the same tick, as in the certified world.
  BEGIN PERFORM public.ottoq_release_expired_tethers(v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance tether release: %', SQLERRM; END;
  BEGIN PERFORM ottoq_reconcile_charger_states(v_run.depot_id);
$n$;
BEGIN
  IF (length(v_def) - length(replace(v_def, v_a1, ''))) / length(v_a1) <> 1 THEN
    RAISE EXCEPTION '0718: anchor 1 (pre-telemetry) does not match exactly once';
  END IF;
  IF (length(v_def) - length(replace(v_def, v_a2, ''))) / length(v_a2) <> 1 THEN
    RAISE EXCEPTION '0718: anchor 2 (early heartbeat) does not match exactly once';
  END IF;
  IF (length(v_def) - length(replace(v_def, v_a3, ''))) / length(v_a3) <> 1 THEN
    RAISE EXCEPTION '0718: anchor 3 (charger reconcile) does not match exactly once';
  END IF;
  v_def := replace(replace(replace(v_def, v_a1, v_n1), v_a2, v_n2), v_a3, v_n3);
  EXECUTE v_def;
END $sub$;

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_world_advance()'::regprocedure);
  v_src text;
  v_missing text[];
  v_p1 int; v_p2 int; v_p3 int; v_q1 int; v_q2 int; v_q3 int;
BEGIN
  --: V1 each phase is called once, and where the certified world calls it
  v_src := regexp_replace(regexp_replace(v_def, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g');
  IF (SELECT count(*) FROM regexp_matches(v_src, 'ottoq_owner_orders_tick\s*\(', 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_src, 'ottoq_arm_advance_cycles\s*\(', 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_src, 'ottoq_release_expired_tethers\s*\(', 'g')) <> 1 THEN
    RAISE EXCEPTION '0718 V1 FAILED: a phase is not called exactly once';
  END IF;
  v_p1 := strpos(v_src, 'ottoq_owner_orders_tick(');      v_q1 := strpos(v_src, 'ottoq_sim_advance_visit_atoms(');
  v_p2 := strpos(v_src, 'ottoq_arm_advance_cycles(');     v_q2 := strpos(v_src, 'ottoq_sim_reconcile_charge_sessions(');
  v_p3 := strpos(v_src, 'ottoq_release_expired_tethers('); v_q3 := strpos(v_src, 'ottoq_reconcile_charger_states(');
  IF NOT (v_p1 < v_q1 AND v_p2 < v_q2 AND v_p3 < v_q3 AND v_p3 > strpos(v_src, 'ottoq_sim_recover_chargers(')) THEN
    RAISE EXCEPTION '0718 V1 FAILED: a phase is out of the certified order (% % % / % % %)', v_p1, v_p2, v_p3, v_q1, v_q2, v_q3;
  END IF;

  --: V2 nothing else moved: removing the three insertions gives back the snapshot byte for byte
  IF replace(replace(replace(v_def,
       $n$  -- 0718 (G436): what an owner set for its own cars (charge limits, service orders, holds), applied before the
  -- visit atoms and the charges advance, as the certified world does (0605). Inert on a run no owner touched.
  BEGIN PERFORM ottoq.ottoq_owner_orders_tick(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance owner_orders: %', SQLERRM; END;

$n$, ''),
       $n$  -- 0718 (G436): the arm moves first, as in the certified world, so a mate opened last tick settles (and writes its
  -- registration) before the charge block below can end the session under it.
  BEGIN PERFORM twin.ottoq_arm_advance_cycles(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance arm: %', SQLERRM; END;
$n$, ''),
       $n$  -- 0718 (G436): the single releaser of a fast charger's demate tether. Without it a DCFC stall stays held by a car
  -- that has left it (sync_stall_occupancy will not free a stall a tether still names). Before the charger reconcile,
  -- so a plug freed here is Available in the same tick, as in the certified world.
  BEGIN PERFORM public.ottoq_release_expired_tethers(v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance tether release: %', SQLERRM; END;
$n$, '')
     <> (SELECT s.definition FROM public.ottoq_schema_snapshots s
          WHERE s.label = '0718_pre' AND s.object_name = 'ottoq_world_advance' ORDER BY s.snapshot_id DESC LIMIT 1) THEN
    RAISE EXCEPTION '0718 V2 FAILED: the body changed by more than the three phases';
  END IF;

  --: V3 parity: every function the certified world calls, production's world step now calls too
  WITH f AS (
    SELECT p.oid, regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') AS src
      FROM pg_proc p WHERE p.oid IN ('twin.ottoq_world_advance()'::regprocedure,
                                     'public.ottoq_sim_advance_tick_world(uuid)'::regprocedure)),
  c AS (
    SELECT f.oid, lower(m[1]) AS callee
      FROM f, regexp_matches(f.src, '(?:[a-z_]+\.)?([a-z_][a-z0-9_]*)\s*\(', 'gi') m
     WHERE EXISTS (SELECT 1 FROM pg_proc q WHERE q.proname = lower(m[1])
                     AND q.pronamespace IN ('public'::regnamespace, 'twin'::regnamespace, 'ottoq'::regnamespace)))
  SELECT array_agg(DISTINCT c.callee ORDER BY c.callee) INTO v_missing
    FROM c WHERE c.oid = 'public.ottoq_sim_advance_tick_world(uuid)'::regprocedure
     AND c.callee NOT IN (SELECT c2.callee FROM c c2 WHERE c2.oid = 'twin.ottoq_world_advance()'::regprocedure);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0718 V3 FAILED: the certified world calls what production does not: %', v_missing;
  END IF;

  --: (V2 compares whole definitions, header included, so SECURITY DEFINER and the search_path are proven unchanged;
  --:  CREATE OR REPLACE keeps the grants, and this file grants nothing.)
  RAISE NOTICE '0718 V1-V3 PASSED';
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0718_production_runs_the_world_phases_the_twin_certifies', false, false,
  'G436: production''s world step (twin.ottoq_world_advance) never called the three phases the certified world calls: '
  'the owner-orders step (an owner''s service order would be held an hour and then dropped; rule 9), the arm cycles, '
  'and the tether release (each fast charge would leave its charger held by a car that has left it). Three insertions '
  'at the certified positions, md5-guarded, nothing else moved; V3 asserts the certified callee set is contained in '
  'production''s. Reached only while a production_live run is running, never by a pair, dial arm, sweep or demo run: '
  'FALSE/FALSE.',
  now());

COMMIT;
