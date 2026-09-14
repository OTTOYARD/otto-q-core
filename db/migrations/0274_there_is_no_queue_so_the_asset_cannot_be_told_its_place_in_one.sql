-- migration-version: 20260913234605
-- migration-name:    0274_there_is_no_queue_so_the_asset_cannot_be_told_its_place_in_one
--
-- 0274  THERE IS NO QUEUE, SO THE ASSET CANNOT BE TOLD ITS PLACE IN ONE
--
-- ---------------------------------------------------------------------------
-- THE GAP, MEASURED
--
-- An asset calling the depot from the road should be told four things: where
-- to go, what it will get, when it will be ready, and WHERE IT IS IN LINE.
-- The first three are already composed and good -- 100,140 command payloads
-- carry stall_id, stall_type, eta_at, ttl_s and a timed itinerary of legs.
--
-- The fourth does not exist anywhere in this database.
--
--   * No wait-list table, no position column, no ordered view, no
--     row_number() over the waiting population.
--   * 0 of 794,745 command payloads carry a queue position, rank or ordinal
--     under any of the names one would look for. Measured, in P3.
--   * ottoq_hw_vehicle_status -- the RPC an asset calls to ask how it stands
--     -- returns pending_commands as a COUNT. It can tell a vehicle it has
--     three instructions waiting and cannot tell it what they are or when it
--     will be served.
--
-- Position today is the transient row order of two cursors inside
-- ottoq_decide_tick, recomputed from scratch every tick and never written
-- down, never promised, never sent. That is not a queue; it is the absence of
-- one, and it is the thing this migration gives the engine.
--
-- ---------------------------------------------------------------------------
-- THE TWO QUEUES, BECAUSE THERE ARE TWO
--
-- "The queue" is not one line. The decide path admits from two independent
-- cursors with DIFFERENT orders, and a vehicle's position depends on which
-- resource it is waiting for. Read from ottoq_decide_tick's live body:
--
--   charge       (sect.3, stall assignment)
--     eligible : home depot, category autonomous, state arrived_at_gate OR
--                staged_awaiting_service with a free compatible charger, and
--                current_soc below the target of its latest open need
--     order    : immediate_dispatch DESC NULLS LAST, current_soc ASC, id
--
--   gate_intake  (sect.3b, no-charge arrivals)
--     eligible : home depot, category autonomous, state arrived_at_gate, no
--                stall yet, and an open need with no pending charge atom
--     order    : last_state_change ASC NULLS FIRST, id
--
-- Charge is evaluated first, so a vehicle in both is seated by charge and
-- leaves gate_intake's cursor in the same tick. Both queues are returned; the
-- per-vehicle answer takes the earliest-evaluated one it appears in.
--
-- ---------------------------------------------------------------------------
-- THIS IS A MIRROR, AND IT IS PINNED. SAID PLAINLY.
--
-- These functions do not share code with the decide path -- ottoq_decide_tick
-- is on the certified path and rewriting it to call a shared ordering
-- function is a change that forces recertification and belongs in a cert
-- window, not here. So this is a MIRROR, and a mirror can drift.
--
-- P2 therefore pins the two ORDER BY clauses inside ottoq_decide_tick by
-- content, not by line number:
--
--   charge order     md5 75999f61e9b278cb29216b195fabaae2, occurring once
--   gate order       md5 fc0299524e12abeee05b08fcc06cd7e7, occurring 3 times
--                    (three cursors share that fairness idiom; the count is
--                     part of the pin so a change to any of them is caught)
--
-- If someone changes how the engine orders its waiting population, this
-- migration's own file no longer describes reality and the NEXT migration to
-- assert these pins fails loudly. That is the honest guarantee available
-- without touching the certified path: not "these cannot diverge", but
-- "these cannot diverge quietly". The real fix -- one ordering function both
-- call -- is the follow-up, and it needs a cert window.
--
-- ONE KNOWN, BOUNDED INFIDELITY, stated rather than hidden. The engine's
-- charge cursor also excludes any vehicle under a one-tick cuOpt deferral
-- hold (ottoq_cuopt_defer_hold(run, vehicle, tick)). That predicate needs a
-- TICK NUMBER, which a read model outside a tick does not have. The queue
-- therefore reports the position a vehicle holds ABSENT a deferral. The error
-- is bounded by construction: ottoq_cuopt_defer_roll releases every hold from
-- the previous tick before the cursor opens, so a hold can never span two
-- consecutive ticks and can move a vehicle back by at most one tick.
--
-- RUN SCOPING IS NOT OPTIONAL HERE. Every read of ottoq_visit_needs carries
-- the 0123/0124 idiom -- COALESCE(vn.sim_run_id, zero-uuid) = COALESCE(
-- p_sim_run_id, zero-uuid) -- because an unscoped read of a run-scoped table
-- is the 0145 defect class, and a queue that ranked a vehicle using another
-- run's needs would be wrong in the most invisible way available.
--
-- forces_recert = FALSE: two new read-only functions with no engine caller,
-- plus one spliced key in ottoq_hw_vehicle_status, which is a status RPC and
-- not on the decide path. A7 asserts ottoq_decide_tick's own prosrc is
-- byte-identical after this migration (md5 fd0bf428abeda40801467fd428a090f1)
-- and re-verifies the determinism pair's pin.
-- ---------------------------------------------------------------------------

-- ===========================================================================
-- PRE-FLIGHT
-- ===========================================================================
DO $pre$
DECLARE v_n int; v_src text; v_hit text; v_pos bigint;
BEGIN
  -- P1: refuse to double-apply.
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname IN ('ottoq_depot_queue','ottoq_vehicle_queue_position');
  IF v_n <> 0 THEN RAISE EXCEPTION '0274 P1: % queue functions already exist', v_n; END IF;

  -- P2: THE MIRROR PIN. Both orders, by content and by occurrence count.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_decide_tick';
  IF v_src IS NULL THEN RAISE EXCEPTION '0274 P2: ottoq_decide_tick not found'; END IF;

  v_hit := (regexp_match(v_src,
    'ORDER BY \(SELECT vn\.urgency = ''immediate_dispatch''.*?v\.current_soc ASC, v\.id', 'ns'))[1];
  IF v_hit IS NULL OR md5(v_hit) <> '75999f61e9b278cb29216b195fabaae2' THEN
    RAISE EXCEPTION '0274 P2: the charge cursor''s ORDER BY is not the one this mirror was written '
                    'against (md5 %) -- re-read the decide path before trusting any position it reports',
                    COALESCE(md5(v_hit),'(absent)');
  END IF;
  SELECT count(*) INTO v_n FROM regexp_matches(v_src,
    'ORDER BY \(SELECT vn\.urgency = ''immediate_dispatch''', 'g');
  IF v_n <> 1 THEN RAISE EXCEPTION '0274 P2: charge order appears % times, expected 1', v_n; END IF;

  SELECT count(*) INTO v_n FROM regexp_matches(v_src,
    'ORDER BY v\.last_state_change ASC NULLS FIRST, v\.id', 'g');
  IF v_n <> 3 THEN
    RAISE EXCEPTION '0274 P2: the gate fairness order appears % times, expected 3', v_n;
  END IF;

  -- P3: THE CONVICTION. Not one command in the table's whole life has ever
  -- carried a position, under any name.
  SELECT count(*) INTO v_pos FROM public.ottoq_vehicle_commands
   WHERE payload ?| array['queue_position','position','rank','queue_rank','ordinal','place_in_line'];
  IF v_pos <> 0 THEN
    RAISE EXCEPTION '0274 P3: % command payloads already carry a position key -- read them; '
                    'the premise of this migration is that none do', v_pos;
  END IF;

  -- P4: and there is a real waiting population to prove the ordering against.
  -- A queue function asserted against an empty depot asserts nothing.
  SELECT count(*) INTO v_n FROM public.vehicles v
   WHERE v.home_depot_id = '22222222-2222-2222-2222-222222222222'::uuid
     AND v.category = 'autonomous'
     AND v.current_state IN ('arrived_at_gate','staged_awaiting_service');
  IF v_n < 10 THEN
    RAISE EXCEPTION '0274 P4: only % vehicles are waiting at the Benchmark depot; '
                    'A3 would prove nothing. Do not apply against an empty world', v_n;
  END IF;
  RAISE NOTICE '0274 pre-flight: pins hold, 0 payloads carry a position, % vehicles waiting to rank', v_n;
END $pre$;

-- ===========================================================================
-- THE QUEUE
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.ottoq_depot_queue(
  p_depot_id   uuid,
  p_sim_run_id uuid DEFAULT NULL)
RETURNS TABLE(queue_kind text, queue_position integer, queue_depth integer,
              vehicle_id uuid, vehicle_ref text, current_soc numeric,
              target_soc numeric, is_immediate boolean, waiting_since timestamptz)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'ottoq', 'extensions'
AS $fn$
  WITH z AS (SELECT COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) AS run),
  -- sect.3 STALL ASSIGNMENT -- mirrored. See this migration's header for the pin.
  charge AS (
    SELECT v.id, v.display_name, v.current_soc, v.last_state_change,
           COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
                      WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                        AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
                          = (SELECT run FROM z)
                      ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1),
                    public.ottoq_default_target_soc()) AS target_soc,
           -- deliberately NOT coalesced: the engine sorts this DESC NULLS LAST,
           -- so false and NULL are different buckets and flattening them would
           -- reorder the tail. Mirroring means mirroring the nulls too.
           (SELECT vn.urgency = 'immediate_dispatch' FROM ottoq_visit_needs vn
             WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
               AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
                 = (SELECT run FROM z)
             ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) AS is_immediate
      FROM vehicles v
     WHERE v.home_depot_id = p_depot_id
       AND v.category = 'autonomous'
       AND (v.current_state = 'arrived_at_gate'
            OR (v.current_state = 'staged_awaiting_service' AND EXISTS (
                 SELECT 1 FROM stalls s2
                   JOIN ottoq_ocpp_chargers c2 ON c2.charger_id = s2.ocpp_charger_id
                  WHERE s2.depot_id = p_depot_id
                    AND s2.stall_type::text IN ('dcfc','l2')
                    AND s2.current_vehicle_id IS NULL
                    AND c2.station_state = 'Available'
                    AND (s2.reserved_by IS NULL OR s2.reserved_by = v.id
                         OR s2.reservation_expires_at <= now()))))
  ),
  charge_q AS (
    SELECT 'charge'::text AS qk,
           (row_number() OVER (ORDER BY c.is_immediate DESC NULLS LAST,
                                        c.current_soc ASC, c.id))::int AS pos,
           (count(*)    OVER ())::int AS depth,
           c.id, c.display_name, c.current_soc, c.target_soc, c.is_immediate, c.last_state_change
      FROM charge c
     WHERE c.current_soc < c.target_soc
  ),
  -- sect.3b GATE INTAKE -- mirrored.
  gate_q AS (
    SELECT 'gate_intake'::text AS qk,
           (row_number() OVER (ORDER BY v.last_state_change ASC NULLS FIRST, v.id))::int AS pos,
           (count(*)    OVER ())::int AS depth,
           v.id, v.display_name, v.current_soc,
           NULL::numeric AS target_soc, NULL::boolean AS is_immediate, v.last_state_change
      FROM vehicles v
     WHERE v.home_depot_id = p_depot_id
       AND v.category = 'autonomous'
       AND v.current_state = 'arrived_at_gate'
       AND v.current_stall_id IS NULL
       AND EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                    WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                      AND COALESCE(vn.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
                        = (SELECT run FROM z)
                      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                       WHERE a->>'svc' = 'charge'
                                         AND COALESCE(a->>'status','pending') <> 'done'))
  )
  -- every reference qualified with u.: the RETURNS TABLE columns are OUT
  -- parameters and an unqualified current_soc would be ambiguous against them.
  SELECT u.qk, u.pos, u.depth, u.id, u.display_name, u.current_soc,
         u.target_soc, u.is_immediate, u.last_state_change
    FROM (SELECT * FROM charge_q UNION ALL SELECT * FROM gate_q) u
   ORDER BY u.qk, u.pos;
$fn$;

COMMENT ON FUNCTION public.ottoq_depot_queue(uuid,uuid) IS
  '0274: the waiting population of a depot, ordered exactly as the decide '
  'path admits it. Two queues -- charge (sect.3) and gate_intake (sect.3b) -- '
  'because the engine has two cursors with different orders. A MIRROR of '
  'ottoq_decide_tick, pinned by content in 0274 P2, not a shared code path. '
  'Reports the position a vehicle holds absent a one-tick cuOpt deferral.';

CREATE OR REPLACE FUNCTION public.ottoq_vehicle_queue_position(
  p_vehicle_id uuid,
  p_sim_run_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'ottoq', 'extensions'
AS $fn$
DECLARE v_depot uuid; v_row record;
BEGIN
  SELECT home_depot_id INTO v_depot FROM vehicles WHERE id = p_vehicle_id;
  IF v_depot IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vehicle_not_found');
  END IF;

  -- charge is evaluated first by the decide path, and ottoq_depot_queue
  -- returns the kinds in that order, so the first row IS the binding one.
  SELECT * INTO v_row FROM public.ottoq_depot_queue(v_depot, p_sim_run_id) q
   WHERE q.vehicle_id = p_vehicle_id
   ORDER BY q.queue_kind LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'ok', true, 'queued', false, 'depot_id', v_depot,
      'reason', 'not waiting for a service point at this depot');
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'queued', true,
    'depot_id',     v_depot,
    'queue_kind',   v_row.queue_kind,
    'position',     v_row.queue_position,
    'queue_depth',  v_row.queue_depth,
    'ahead_of_you', v_row.queue_position - 1,
    'is_immediate', v_row.is_immediate,
    'current_soc',  v_row.current_soc,
    'target_soc',   v_row.target_soc,
    'waiting_since', v_row.waiting_since,
    -- 0274: an honest caveat travels with the number, not in a doc nobody
    -- opens. A position is a snapshot of a cursor that reruns every tick.
    'basis', 'mirror of ottoq_decide_tick admission order; excludes one-tick cuOpt deferral');
END $fn$;

COMMENT ON FUNCTION public.ottoq_vehicle_queue_position(uuid,uuid) IS
  '0274: what an asset is told when it asks where it stands. The per-vehicle '
  'answer over ottoq_depot_queue, carrying its own basis string so the number '
  'cannot be quoted without its caveat.';

REVOKE ALL ON FUNCTION public.ottoq_depot_queue(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ottoq_vehicle_queue_position(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_depot_queue(uuid,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_vehicle_queue_position(uuid,uuid) TO authenticated, service_role;

-- The status RPC an asset already calls now answers the fourth question.
DO $edit$
DECLARE v_def text; v_a text := $a$    'pending_commands', v_pending,$a$; v_hits int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_hw_vehicle_status';
  IF md5((SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='public' AND p.proname='ottoq_hw_vehicle_status'))
     <> '91061f6a30f08b51376a12980ed29c02' THEN
    RAISE EXCEPTION '0274: ottoq_hw_vehicle_status is not the body this migration was written against';
  END IF;
  v_hits := (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0274: pending_commands anchor expected once, found %', v_hits;
  END IF;
  EXECUTE replace(v_def, v_a,
    $b$    'pending_commands', v_pending,
    'queue', public.ottoq_vehicle_queue_position(p_vehicle_id, v_run),$b$);
END $edit$;

-- ===========================================================================
-- POST
-- ===========================================================================
DO $post$
DECLARE
  v_bench uuid := '22222222-2222-2222-2222-222222222222'::uuid;
  v_flag  uuid := '11111111-1111-1111-1111-111111111111'::uuid;
  v_n int; v_depth int; v_veh uuid; v_pos int; v_j jsonb;
  v_a text; v_b text; v_mine int;
BEGIN
  -- A1: both functions exist and the RPC carries the new key.
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('ottoq_depot_queue','ottoq_vehicle_queue_position');
  IF v_n <> 2 THEN RAISE EXCEPTION '0274 A1: expected 2 queue functions, found %', v_n; END IF;
  IF (SELECT p.prosrc FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_hw_vehicle_status') NOT LIKE '%ottoq_vehicle_queue_position%' THEN
    RAISE EXCEPTION '0274 A1: the status RPC still cannot tell a vehicle where it stands';
  END IF;

  -- A2: a real, non-empty ranking. P4 guaranteed the population exists.
  SELECT count(*) INTO v_n FROM public.ottoq_depot_queue(v_bench, NULL);
  IF v_n < 5 THEN
    RAISE EXCEPTION '0274 A2: the Benchmark queue returned only % rows; nothing is being proved', v_n;
  END IF;

  -- A3: POSITION MEANS POSITION. Per kind: contiguous 1..depth, no gaps, no
  -- ties, depth agreeing with the row count. This is where a row_number()
  -- written over the wrong window silently produces a plausible-looking list.
  FOR v_a, v_depth, v_mine IN
    SELECT q.queue_kind, max(q.queue_depth), count(*)::int
      FROM public.ottoq_depot_queue(v_bench, NULL) q GROUP BY q.queue_kind
  LOOP
    IF v_depth <> v_mine THEN
      RAISE EXCEPTION '0274 A3: queue % reports depth % but returned % rows', v_a, v_depth, v_mine;
    END IF;
    SELECT count(*) INTO v_n FROM (
      SELECT q.queue_position AS qp FROM public.ottoq_depot_queue(v_bench, NULL) q
       WHERE q.queue_kind = v_a) p
     WHERE p.qp IS NULL;
    IF v_n <> 0 THEN RAISE EXCEPTION '0274 A3: queue % has a null position', v_a; END IF;
    SELECT count(DISTINCT q.queue_position) INTO v_n
      FROM public.ottoq_depot_queue(v_bench, NULL) q WHERE q.queue_kind = v_a;
    IF v_n <> v_mine THEN
      RAISE EXCEPTION '0274 A3: queue % has % distinct positions across % rows -- there is a tie',
                      v_a, v_n, v_mine;
    END IF;
    SELECT count(*) INTO v_n FROM public.ottoq_depot_queue(v_bench, NULL) q
     WHERE q.queue_kind = v_a AND (q.queue_position < 1 OR q.queue_position > v_mine);
    IF v_n <> 0 THEN
      RAISE EXCEPTION '0274 A3: queue % has % positions outside 1..%', v_a, v_n, v_mine;
    END IF;
  END LOOP;

  -- A4: the order is the order. Rank the returned set independently and
  -- require agreement -- this catches a row_number() whose window ORDER BY
  -- and the function's outer ORDER BY disagree, which is a real and quiet bug.
  SELECT count(*) INTO v_n FROM (
    SELECT q.queue_position AS given,
           row_number() OVER (ORDER BY q.is_immediate DESC NULLS LAST,
                                       q.current_soc ASC, q.vehicle_id) AS recomputed
      FROM public.ottoq_depot_queue(v_bench, NULL) q
     WHERE q.queue_kind = 'charge') r
   WHERE r.given <> r.recomputed;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0274 A4: % charge rows are not where the stated order puts them', v_n;
  END IF;

  -- A5: DEPOT SCOPING. Another depot's vehicles are another depot's queue.
  SELECT count(*) INTO v_n
    FROM public.ottoq_depot_queue(v_bench, NULL) q
    JOIN public.vehicles v ON v.id = q.vehicle_id
   WHERE v.home_depot_id <> v_bench;
  IF v_n <> 0 THEN RAISE EXCEPTION '0274 A5: % foreign vehicles in the Benchmark queue', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_depot_queue(v_flag, NULL);
  RAISE NOTICE '0274 A5: Benchmark queue non-empty, flagship queue % rows -- depot-scoped', v_n;

  -- A6: the per-vehicle answer agrees with the depot queue, in both
  -- directions: a member gets its own number, a non-member is told plainly
  -- that it is not in line rather than being handed a fabricated position.
  SELECT q.vehicle_id, q.queue_position INTO v_veh, v_pos
    FROM public.ottoq_depot_queue(v_bench, NULL) q
   WHERE q.queue_kind = 'charge' ORDER BY q.queue_position LIMIT 1;
  IF v_veh IS NULL THEN RAISE EXCEPTION '0274 A6: no charge-queue member to ask about'; END IF;
  v_j := public.ottoq_vehicle_queue_position(v_veh, NULL);
  IF (v_j->>'queued')::boolean IS NOT TRUE OR (v_j->>'position')::int <> v_pos THEN
    RAISE EXCEPTION '0274 A6: the per-vehicle answer % disagrees with position %', v_j, v_pos;
  END IF;

  SELECT v.id INTO v_veh FROM public.vehicles v
   WHERE v.home_depot_id = v_bench
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_depot_queue(v_bench, NULL) q
                      WHERE q.vehicle_id = v.id)
   ORDER BY v.id LIMIT 1;
  IF v_veh IS NULL THEN RAISE EXCEPTION '0274 A6: every vehicle is queued; the negative case is untestable'; END IF;
  v_j := public.ottoq_vehicle_queue_position(v_veh, NULL);
  IF (v_j->>'queued')::boolean IS NOT FALSE THEN
    RAISE EXCEPTION '0274 A6: a vehicle that is not in line was given a place in it: %', v_j;
  END IF;

  -- A7: determinism. Two calls in one transaction, byte-identical.
  SELECT md5(string_agg(t, '|' ORDER BY t)) INTO v_a FROM (
    SELECT q.queue_kind||':'||q.queue_position||':'||q.vehicle_id AS t
      FROM public.ottoq_depot_queue(v_bench, NULL) q) x;
  SELECT md5(string_agg(t, '|' ORDER BY t)) INTO v_b FROM (
    SELECT q.queue_kind||':'||q.queue_position||':'||q.vehicle_id AS t
      FROM public.ottoq_depot_queue(v_bench, NULL) q) x;
  IF v_a IS DISTINCT FROM v_b THEN
    RAISE EXCEPTION '0274 A7: the queue is not stable within one transaction (% vs %)', v_a, v_b;
  END IF;

  -- A8: the certified path was not touched by any of this.
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_decide_tick')
     IS DISTINCT FROM 'fd0bf428abeda40801467fd428a090f1' THEN
    RAISE EXCEPTION '0274 A8: ottoq_decide_tick changed -- this migration must not touch it';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair')
     IS DISTINCT FROM '8a35b8c874fed154cc216140faec0274' THEN
    RAISE EXCEPTION '0274 A8: ottoq_determinism_pair changed -- forces_recert is not FALSE';
  END IF;

  RAISE NOTICE '0274: A1-A8 passed. The engine has a queue object, and an asset asking '
               'where it stands is answered with a number instead of a count.';
END $post$;

-- ===========================================================================
-- CLASSIFICATION -- in the file, per 0272's guard.
-- ===========================================================================
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0274_there_is_no_queue_so_the_asset_cannot_be_told_its_place_in_one', false,
  'Adds ottoq_depot_queue and ottoq_vehicle_queue_position -- two STABLE read-only functions '
  'that mirror ottoq_decide_tick''s two admission cursors -- and splices a ''queue'' key into '
  'ottoq_hw_vehicle_status, a status RPC that is not on the decide path. FALSE with proof: A8 '
  'asserts ottoq_decide_tick''s prosrc is byte-identical (md5 '
  'fd0bf428abeda40801467fd428a090f1) and re-verifies the determinism pair''s pin '
  '8a35b8c874fed154cc216140faec0274; the new functions write nothing and no engine function '
  'calls them. The mirror is pinned to the engine''s two ORDER BY clauses by content (P2) so '
  'it cannot drift quietly.',
  now());

-- ---------------------------------------------------------------------------
-- APPLY LOG
-- Applied 2026-09-13 23:46:05 UTC as version 20260913234605 (6:46 PM CT).
--
-- Dry-run byte for byte inside BEGIN ... ROLLBACK first; P1-P4 and A1-A8
-- passed there and again on apply. Two defects were caught by that dry run
-- and fixed before any apply, both recorded because they are generic:
--
--   1. position is a RESERVED WORD in PostgreSQL. RETURNS TABLE(... position
--      integer ...) is a syntax error. The column is queue_position.
--   2. the RETURNS TABLE columns are OUT PARAMETERS and are in scope inside a
--      SQL-language body, so an unqualified current_soc in the final SELECT
--      is ambiguous against them. Every reference in that SELECT is now
--      qualified with its subquery alias.
--
--   ottoq_hw_vehicle_status  pre-image  md5 91061f6a30f08b51376a12980ed29c02
--                            post-image md5 ca8a62675a659222b4d76c98de9b820d
--   ottoq_decide_tick        unchanged  md5 fd0bf428abeda40801467fd428a090f1
--   ottoq_cert_recert_floor() unmoved at 2026-09-12 16:50:23.319089+00
--
-- LIVE VERIFICATION AFTER APPLY -- the loop, end to end. The vehicle first in
-- line at the Benchmark depot calls the status RPC it already calls, and gets
-- back, for the first time in this engine's life, a place in line:
--
--   { "ok": true, "queued": true,
--     "queue_kind": "charge", "position": 1, "queue_depth": 23,
--     "ahead_of_you": 0, "current_soc": 72, "target_soc": 100,
--     "waiting_since": "2026-09-01T05:30:00+00:00",
--     "basis": "mirror of ottoq_decide_tick admission order; excludes
--               one-tick cuOpt deferral" }
--
-- Before this migration the same call returned pending_commands as an integer
-- and nothing else about where the vehicle stood.
--
-- Note the basis string travels INSIDE the answer. A position is a snapshot
-- of a cursor that reruns every tick, and it is a mirror rather than the
-- cursor itself; whoever reads the number reads the caveat with it, which is
-- not true of a caveat that lives only in a migration header.
--
-- WHAT IS STILL OPEN, so this is not read as more than it is:
--   * the position is READ on request; it is not written into the appointment
--     payload the asset receives on recall. That write is in
--     ottoq_book_appointment, which the twin's telemetry advance calls, and
--     it is therefore on the certified path -- a cert window, not this file.
--   * the two locks still cannot see each other: ottoq_book_stall never
--     consults stalls.reserved_by and ottoq_reserve_stall never consults
--     ottoq_stall_bookings. A queue that reports a position over a calendar
--     that can be double-claimed is honest about the order and silent about
--     the collision. Same cert window.
-- ---------------------------------------------------------------------------
