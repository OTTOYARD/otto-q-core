-- migration-version: PENDING
-- migration-name:    the_order_built_from_the_newest_board_stands_and_an_outranked_order_never_does
--
-- 0706  **The agent's charge order that stands is the one built from the newest board, not the last one to arrive; an
--        order outranked never stands, and which order replaced which can now be read.** (The study's item F, second
--        half; the first half, the check's seed, was made by 0712 and is not touched here.)
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_agent_charge_order_live picks the agent order the kernel follows. Since 0614 it has taken the taken
--   order (accepted or partial) with the highest order_id that is younger than the ttl: the last to ARRIVE. An agent
--   pass reads a board at one tick and records its order several ticks later (0 to 21 ticks: recorded_tick minus
--   board_tick, over all 839 orders read before 18:05 UTC and all 849 at 18:38 UTC, 2026-10-13), and passes overlap.
--   So a pass that started earlier and finished later beats a fresher one: its order, built from the older board,
--   becomes the order the kernel follows, and stays until its own ttl runs out.
--
--   Measured on the live engine, read-only, 2026-10-13, ending 18:38:16 UTC (1:38 PM CT, read from the database
--   clock), db/checks/0443 (1)-(3):
--     - 19 of 839 orders arrived out of board order (a lower board tick than an order recorded before them on the run);
--       8 of those were taken by the check, every one before 0620 (order ids 11, 39, 45, 74, 176, 178, 186, 209, on
--       runs 0bbdcc07 and 089f46bd). None of the 483 orders checked since 0620 has arrived outranked;
--     - replayed tick by tick over the runs that recorded orders (7,583 run-ticks between 18:14 and 18:30 UTC, 2,713
--       with an order standing; the same counts at 18:38 over 7,932): 0614's rule stood the stale order on 77 where this
--       file's stands another or none, on the same two runs (74 while the fresher order was still young, 3 after it
--       had expired);
--     - recorded_tick never goes back as order_id rises within a run (0 of 839), so arrival order is order_id order.
--
--   The defect is rare and old, and that is not why it is fixed. It is fixed because the check's verdict on an order
--   is now repeatable (0712), and a repeatable verdict on an order that then does not stand, or a stale order that
--   stands over a fresher one the check also took, still makes a replay of the same world come out differently with
--   nothing but the agents' latency changed.
--
--   THE ITEM'S OTHER HALF, AND WHY THIS FILE DOES NOT BUILD IT. The item asked for the check's seed to become
--   random_seed : board tick : md5(order content). 0712 (applied 2026-10-13 18:19:32 UTC, 1:19 PM CT, while this file
--   was being written) already seeds it 'world:' || random_seed || ':' || recorded tick. The premise "the seed is built
--   from sim_run_id || tick || chain_id" was true when the item was written and false when this file was finished, so
--   the seed is left as 0712 made it, and the two differences are recommended against rather than built:
--     - the order's content in the seed: every candidate order at one tick would draw its own futures. Without it they
--       share them (common random numbers across candidates, 0712 §1 b), and an agent cannot draw new futures by
--       reordering cars that change nothing;
--     - the board tick in the seed: the check reads the world at the tick it records the order (sim_clock_current),
--       not at the board's; the board tick is supplied by the caller. 0712 keys on the tick whose world it reads.
--   What the seed does and does not buy, measured the same afternoon on the 8 orders the check took since 0620,
--   replayed from their snapshots (db/checks/0443 (4)): with the stored seed, today's functions reproduce all 8
--   recorded verdicts, futures won for futures won. With only the run id in the old seed changed, 5 of the 8 flip to
--   refused (382, 385, 479, 717, 757). Under 0712's seed, 4 of the 8 would be refused (382, 479, 717, 757). The seed
--   makes a verdict repeatable; near the bar of 10 futures in 12 it does not make it robust (0712 §1 says the same).
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_agent_charge_order_live (md5 c1c0eb65, as 0614 left it), replaced whole. The taken orders recorded
--       by the tick are ranked by LEAST(board_tick, recorded_tick) DESC, then order_id DESC; the first stands while it
--       is younger than the ttl, and otherwise nothing stands: the kernel's own order holds.
--         - LEAST, not board_tick: a board cannot be newer than the tick its order was recorded at. board_tick is the
--           caller's (the edge function passes the board's tick), and one order claiming a board from the future would
--           otherwise outrank every later order on the run. A NULL board_tick (none today) ranks by its recorded tick,
--           which is 0614's rule for that order.
--         - "the first, or nothing", not "the first among those younger than the ttl": an order outranked by a fresher
--           one must not come back when the fresher one expires. Its board is older still than one the ttl has just
--           called too old. Ranking only the orders inside the ttl (the item's literal ORDER BY) would have stood such
--           an order on 3 of the 7,583 run-ticks replayed.
--       Where no order arrives out of board order, this is 0614's rule exactly (the newest board is the latest arrival).
--
--   (b) public.ottoq_agent_charge_order_succession, a view: for every taken order, whether it stood when it arrived,
--       the order that outranked it if it did not (outranked_by), and the order that replaced it if it did
--       (superseded_by). The item asked for superseded_by to be RECORDED on the order row it replaces. That row
--       cannot be written: ottoq_agent_charge_orders is append-only (ottoq_agent_charge_orders_append_only_trg refuses
--       every UPDATE and DELETE unless a session unlocks it), it is evidence, and the grader reads it. Writing a link on
--       the NEW row instead would need the door (ottoq_agent_charge_order_record, which 0712 has just replaced) and a
--       lock against two passes on one run recording at once. The succession is a pure function of rows that never
--       change, so it is derived, by the same ranking as (a), and is the same answer at every reading. No column is
--       added, so nothing needs registering in ottoq_run_scope_registry. security_invoker; SELECT as the table's.
--
--   Not changed: the door, the seed (0712), the check, the grader (it reads the snapshot's stored seed), the decide
--   path's use of the live order, and what the agent's board shows as its last order (ottoq_run_learning reports the
--   last order recorded, of any status: a person reading the board should know that is not always the one standing).
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════════
--
--   The live order is read only when the run's agent_charge_order dial is 1 (ottoq_decide_tick, ottoq_depot_queue,
--   ottoq_run_learning all gate on it). It is 0 by default (catalog default 0, no global or depot row), and on every
--   one of the 126 certification-harness runs and 85 A/B-harness runs in ottoq_sim_runs it reads 0, with no charge
--   order recorded on any of them (read 2026-10-13 between 18:05 and 18:14 UTC). The only runs with it on are operator
--   demos (16) and one production session. So no certified arm and no dial arm reads the function this file changes,
--   and no atom hashes the view.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the definition in ottoq_schema_snapshots WHERE label = '0706_pre' AND object_name =
--   'ottoq_agent_charge_order_live'; DROP VIEW public.ottoq_agent_charge_order_succession (nothing reads it);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0706_the_order_built_from_the_newest_board_stands_and_an_outranked_order_never_does'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight (a pair, the recertification runner, a dial pair or a throughput sweep) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0706 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
DECLARE v_md5 text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0706_the_order_built_from_the_newest_board_stands_and_an_outranked_order_never_does') THEN
    RAISE EXCEPTION '0706 P1: already applied';
  END IF;
  v_md5 := md5(pg_get_functiondef(to_regprocedure('public.ottoq_agent_charge_order_live(uuid,bigint)')));
  IF v_md5 IS DISTINCT FROM 'c1c0eb65fb40162c78966598526f51e3' THEN
    RAISE EXCEPTION '0706 P1: ottoq_agent_charge_order_live is not the definition 0614 left, which this file replaces (md5 %)', v_md5;
  END IF;
  IF to_regclass('public.ottoq_agent_charge_order_succession') IS NOT NULL THEN
    RAISE EXCEPTION '0706 P1: the succession view already exists';
  END IF;
  -- the ranking reads these two columns as 0614 made them
  IF (SELECT string_agg(column_name || ':' || data_type || ':' || is_nullable, ',' ORDER BY column_name)
        FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'ottoq_agent_charge_orders'
         AND column_name IN ('board_tick', 'recorded_tick'))
     IS DISTINCT FROM 'board_tick:bigint:YES,recorded_tick:bigint:NO' THEN
    RAISE EXCEPTION '0706 P1: board_tick / recorded_tick are not the columns this file ranks by';
  END IF;
  -- the premise that the replaced row cannot be written, which is why (b) is a view
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
                  WHERE t.tgrelid = 'public.ottoq_agent_charge_orders'::regclass AND NOT t.tgisinternal
                    AND (t.tgtype & 16) > 0                                   -- fires on UPDATE
                    AND p.prosrc ILIKE '%append-only%' AND p.prosrc ILIKE '%RAISE EXCEPTION%') THEN
    RAISE EXCEPTION '0706 P1: ottoq_agent_charge_orders is not append-only; this file''s premise for a view is wrong';
  END IF;
  -- the probes below use negative order ids and two run ids nothing else uses
  IF EXISTS (SELECT 1 FROM public.ottoq_agent_charge_orders
              WHERE order_id <= 0
                 OR sim_run_id IN ('f0706000-0000-4000-8000-000000000001', 'f0706000-0000-4000-8000-000000000002'))
     OR EXISTS (SELECT 1 FROM public.ottoq_sim_runs
                 WHERE sim_run_id IN ('f0706000-0000-4000-8000-000000000001', 'f0706000-0000-4000-8000-000000000002'))
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params
                 WHERE scope_type = 'run'
                   AND scope_id IN ('f0706000-0000-4000-8000-000000000001', 'f0706000-0000-4000-8000-000000000002')) THEN
    RAISE EXCEPTION '0706 P1: the probe''s order ids or run ids are in use';
  END IF;
  -- a run with the agent's order on would change rule mid-run
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
              WHERE r.status IN ('running', 'paused')
                AND COALESCE(public.ottoq_policy_get(r.sim_run_id, 'agent_charge_order', 0), 0) >= 1) THEN
    RAISE EXCEPTION '0706 P1: a run with agent_charge_order on is live; which order stands would change mid-run';
  END IF;
END $premises$;

-- ── snapshot: the definition as it stood ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0706_pre', 'function', 'public', 'ottoq_agent_charge_order_live', d.def, md5(d.def)
  FROM (SELECT pg_get_functiondef('public.ottoq_agent_charge_order_live(uuid,bigint)'::regprocedure) AS def) d;

-- ── the stored orders as they stand, to prove at the end that nothing here rewrote one ──
CREATE TEMP TABLE p0706_rows ON COMMIT DROP AS
SELECT max(order_id) AS max_id, count(*) AS n, md5(string_agg(to_jsonb(o)::text, E'\n' ORDER BY o.order_id)) AS digest
  FROM public.ottoq_agent_charge_orders o;

-- ── a probe: two synthetic runs' orders, read through the live function (and the view, once it exists), rolled back ──
CREATE TEMP TABLE p0706 (phase text PRIMARY KEY, r jsonb) ON COMMIT DROP;

CREATE FUNCTION pg_temp.p0706_who(p_live jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  -- the cars of a live order, by the letter their probe id ends in; '-' when nothing stands
  SELECT COALESCE(string_agg(right(k, 1), '' ORDER BY k), '-') FROM jsonb_object_keys(COALESCE(p_live, '{}'::jsonb)) k
$fn$;

CREATE FUNCTION pg_temp.p0706_probe(p_phase text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
  v_r1 uuid := 'f0706000-0000-4000-8000-000000000001';
  v_r2 uuid := 'f0706000-0000-4000-8000-000000000002';
  v_ttl bigint; v_r jsonb; v_msg text;
BEGIN
  -- no ottoq_sim_runs row and no run-scoped dial names either run (P1), so both read the global ttl
  v_ttl := GREATEST(1, COALESCE(public.ottoq_policy_get(v_r1, 'agent_charge_order_ttl_ticks', 15), 15))::bigint;
  BEGIN
    INSERT INTO public.ottoq_agent_charge_orders
      (order_id, sim_run_id, board_tick, recorded_tick, status, n_offered, n_accepted, cars, dropped, model, why)
    SELECT x.id, x.run, x.board, x.rec, x.status, 1, 1,
           jsonb_build_array(jsonb_build_object('vehicle_id', 'f0706000-0000-4000-8000-00000000000' || x.car,
                                                'rank', 1, 'kind', 'dcfc')),
           '[]'::jsonb, 'probe_0706', 'probe_0706'
      FROM (VALUES
        -- run 1: A is built from the board of tick 20 and recorded at 22; B, from the older board of tick 10, arrives
        -- after it (tick 23, a higher id); C, from the newest board, was refused by the check
        (-706006::bigint, v_r1, 20::bigint, 22::bigint, 'accepted', 'a'),
        (-706005, v_r1, 10, 23, 'accepted', 'b'),
        (-706004, v_r1, 30, 23, 'refused', 'c'),
        -- run 2: D says its board is from tick 1,000,000 but was recorded at 24; E is built from the board of tick 30
        (-706003, v_r2, 1000000, 24, 'accepted', 'd'),
        (-706002, v_r2, 30, 31, 'partial', 'e')) AS x(id, run, board, rec, status, car);
    v_r := jsonb_build_object(
      'r1_t21', pg_temp.p0706_who(public.ottoq_agent_charge_order_live(v_r1, 21)),
      'r1_t22', pg_temp.p0706_who(public.ottoq_agent_charge_order_live(v_r1, 22)),
      'r1_t23', pg_temp.p0706_who(public.ottoq_agent_charge_order_live(v_r1, 23)),
      'r1_a_expired', pg_temp.p0706_who(public.ottoq_agent_charge_order_live(v_r1, 22 + v_ttl + 1)),
      'r2_t24', pg_temp.p0706_who(public.ottoq_agent_charge_order_live(v_r2, 24)),
      'r2_t31', pg_temp.p0706_who(public.ottoq_agent_charge_order_live(v_r2, 31)),
      'ttl', v_ttl);
    IF to_regclass('public.ottoq_agent_charge_order_succession') IS NOT NULL THEN
      v_r := v_r || jsonb_build_object('succession', (
        SELECT jsonb_object_agg(s.order_id::text, jsonb_build_array(s.stood, s.outranked_by, s.superseded_by))
          FROM public.ottoq_agent_charge_order_succession s WHERE s.sim_run_id IN (v_r1, v_r2)));
    END IF;
    RAISE EXCEPTION 'P0706 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'P0706 PROBED' THEN RAISE EXCEPTION '0706 probe % failed: %', p_phase, v_msg; END IF;
  INSERT INTO p0706 VALUES (p_phase, v_r);
END $fn$;

-- ── P2: the defect, on 0614's function: B, built from the older board and arriving later, stands over A, and stays
--        standing after A has expired; with D present, E stands at 31 only because it arrived last ──
DO $p2$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.p0706_probe('before');
  SELECT r INTO v FROM p0706 WHERE phase = 'before';
  IF (v - 'ttl') IS DISTINCT FROM '{"r1_t21": "-", "r1_t22": "a", "r1_t23": "b", "r1_a_expired": "b",
                                    "r2_t24": "d", "r2_t31": "e"}'::jsonb THEN
    RAISE EXCEPTION '0706 P2: 0614''s live order did not behave as this file says it does: %', v;
  END IF;
END $p2$;

-- ══ (a) the order built from the newest board stands ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_agent_charge_order_live(p_sim_run_id uuid, p_tick bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0614: the agent's latest accepted charge order on this run that is no older than agent_charge_order_ttl_ticks at
  -- tick p_tick (and not recorded after it), as {vehicle_id: {rank, kind, order_id}}; '{}' when there is none.
  -- 0706: "latest" is the order built from the newest board, not the last to arrive. The orders taken on this run and
  -- recorded by p_tick are ranked by the tick of the board each was built from (never later than the tick it was
  -- recorded at, and that tick when the board's is not given), then by arrival; the first stands while it is younger
  -- than the ttl. An order outranked when it arrives never stands, and an order once outranked never stands again,
  -- even after the order that outranked it has expired: the kernel's own order holds until a fresher one arrives.
  -- public.ottoq_agent_charge_order_succession says, order by order, which stood and what replaced it.
  SELECT COALESCE((
    SELECT jsonb_object_agg(c ->> 'vehicle_id',
                            jsonb_build_object('rank', c -> 'rank', 'kind', c ->> 'kind', 'order_id', o.order_id))
      FROM (SELECT x.order_id, x.cars, x.recorded_tick FROM ottoq_agent_charge_orders x
             WHERE x.sim_run_id = p_sim_run_id AND x.status IN ('accepted', 'partial')
               AND x.recorded_tick <= p_tick
             ORDER BY LEAST(x.board_tick, x.recorded_tick) DESC, x.order_id DESC LIMIT 1) o
      CROSS JOIN LATERAL jsonb_array_elements(o.cars) c
     WHERE o.recorded_tick >= p_tick
                              - GREATEST(1, COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15))::bigint
       AND c ->> 'vehicle_id' IS NOT NULL), '{}'::jsonb)
$function$;

-- ══ (b) which order stood, and what replaced it ═════════════════════════════════════════════════════════════════════
CREATE VIEW public.ottoq_agent_charge_order_succession WITH (security_invoker = true) AS
SELECT o.order_id, o.sim_run_id, o.board_tick, o.recorded_tick,
       LEAST(o.board_tick, o.recorded_tick) AS board_key,
       (b.order_id IS NULL) AS stood,
       b.order_id AS outranked_by,
       CASE WHEN b.order_id IS NULL THEN s.order_id END AS superseded_by
  FROM public.ottoq_agent_charge_orders o
  -- the order that ranked first on the run when this one arrived, when it outranks this one
  LEFT JOIN LATERAL (SELECT p.order_id FROM public.ottoq_agent_charge_orders p
                      WHERE p.sim_run_id = o.sim_run_id AND p.status IN ('accepted', 'partial')
                        AND p.order_id < o.order_id
                        AND LEAST(p.board_tick, p.recorded_tick) > LEAST(o.board_tick, o.recorded_tick)
                      ORDER BY LEAST(p.board_tick, p.recorded_tick) DESC, p.order_id DESC LIMIT 1) b ON true
  -- the first order to arrive after this one that outranks it
  LEFT JOIN LATERAL (SELECT q.order_id FROM public.ottoq_agent_charge_orders q
                      WHERE q.sim_run_id = o.sim_run_id AND q.status IN ('accepted', 'partial')
                        AND q.order_id > o.order_id
                        AND LEAST(q.board_tick, q.recorded_tick) >= LEAST(o.board_tick, o.recorded_tick)
                      ORDER BY q.order_id LIMIT 1) s ON true
 WHERE o.status IN ('accepted', 'partial');

COMMENT ON VIEW public.ottoq_agent_charge_order_succession IS
  '0706: for every agent charge order the check took, whether it stood when it arrived, the order that outranked it if '
  'not (outranked_by), and the order that replaced it if so (superseded_by), ranked as ottoq_agent_charge_order_live '
  'ranks them: LEAST(board_tick, recorded_tick) DESC, then order_id DESC. Derived because the orders table is '
  'append-only: the replaced row cannot be written. A stood order may also have expired (its ttl) before it was '
  'superseded; this view does not read the ttl.';

REVOKE ALL ON public.ottoq_agent_charge_order_succession FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ottoq_agent_charge_order_succession TO authenticated, service_role;

-- ── V1: the probe again: A stands over B, nothing stands once A expires, D's claimed board ranks at its arrival,
--        the refused C never stands; and the view says the same ──
DO $v1$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.p0706_probe('after');
  SELECT r INTO v FROM p0706 WHERE phase = 'after';
  IF (v - 'ttl' - 'succession') IS DISTINCT FROM '{"r1_t21": "-", "r1_t22": "a", "r1_t23": "a", "r1_a_expired": "-",
                                                   "r2_t24": "d", "r2_t31": "e"}'::jsonb
     OR v -> 'succession' IS DISTINCT FROM
        '{"-706006": [true, null, null], "-706005": [false, -706006, null],
          "-706003": [true, null, -706002], "-706002": [true, null, null]}'::jsonb THEN
    RAISE EXCEPTION '0706 V1 FAILED: %', v;
  END IF;
  RAISE NOTICE '0706 V1 PASSED: before %, after %; all rolled back', (SELECT r FROM p0706 WHERE phase = 'before'), v;
END $v1$;

-- ── V2: the definitions as written ──
DO $v2$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_agent_charge_order_live(uuid,bigint)'::regprocedure))
       <> 'bf57d4ed10f79cf555f3bb2350b82770' THEN
    RAISE EXCEPTION '0706 V2 FAILED: the live order function is not as written (md5 %)',
      md5(pg_get_functiondef('public.ottoq_agent_charge_order_live(uuid,bigint)'::regprocedure));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class c
                  WHERE c.oid = 'public.ottoq_agent_charge_order_succession'::regclass AND c.relkind = 'v'
                    AND 'security_invoker=true' = ANY (c.reloptions)) THEN
    RAISE EXCEPTION '0706 V2 FAILED: the succession view is not a security_invoker view';
  END IF;
END $v2$;

-- ── V3: on the engine's own orders: every order the view says stood is the live order at the tick it was recorded
--        (unless an order recorded at that same tick replaced it), and no order it says was outranked ever is ──
CREATE FUNCTION pg_temp.p0706_live_id(p_run uuid, p_tick bigint) RETURNS bigint LANGUAGE sql STABLE AS $fn$
  -- the order_id the live function answers at the tick (every car of a live order carries it), NULL when none stands
  SELECT max((e.value ->> 'order_id')::bigint) FROM jsonb_each(public.ottoq_agent_charge_order_live(p_run, p_tick)) e
$fn$;

DO $v3$
DECLARE v_taken int; v_stood int; v_outranked int; v_bad_stood int; v_bad_out int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE s.stood), count(*) FILTER (WHERE NOT s.stood),
         count(*) FILTER (WHERE s.stood
                            AND NOT EXISTS (SELECT 1 FROM public.ottoq_agent_charge_orders n
                                             WHERE n.order_id = s.superseded_by AND n.recorded_tick = s.recorded_tick)
                            AND pg_temp.p0706_live_id(s.sim_run_id, s.recorded_tick) IS DISTINCT FROM s.order_id),
         count(*) FILTER (WHERE NOT s.stood
                            AND pg_temp.p0706_live_id(s.sim_run_id, s.recorded_tick) = s.order_id)
    INTO v_taken, v_stood, v_outranked, v_bad_stood, v_bad_out
    FROM public.ottoq_agent_charge_order_succession s;
  IF v_stood + v_outranked <> v_taken OR v_bad_stood <> 0 OR v_bad_out <> 0 THEN
    RAISE EXCEPTION '0706 V3 FAILED: % taken, % stood, % outranked; % stood orders not live at their tick, % outranked live',
      v_taken, v_stood, v_outranked, v_bad_stood, v_bad_out;
  END IF;
  RAISE NOTICE '0706 V3 PASSED: % taken orders on the engine, % stood, % outranked; the live function agrees with the view on all',
    v_taken, v_stood, v_outranked;
END $v3$;

-- ── V4: no stored order was rewritten, and no probe row outlived its rollback ──
DO $v4$
DECLARE v_before record; v_n bigint; v_digest text;
BEGIN
  SELECT * INTO v_before FROM p0706_rows;
  SELECT count(*), md5(string_agg(to_jsonb(o)::text, E'\n' ORDER BY o.order_id)) INTO v_n, v_digest
    FROM public.ottoq_agent_charge_orders o WHERE o.order_id <= COALESCE(v_before.max_id, 0) AND o.order_id > 0;
  IF v_n <> v_before.n OR v_digest IS DISTINCT FROM v_before.digest THEN
    RAISE EXCEPTION '0706 V4 FAILED: the stored orders changed (% rows, digest %; before % rows, %)',
      v_n, v_digest, v_before.n, v_before.digest;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_agent_charge_orders WHERE order_id <= 0 OR model = 'probe_0706') THEN
    RAISE EXCEPTION '0706 V4 FAILED: a probe order outlived its rollback';
  END IF;
END $v4$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0706_the_order_built_from_the_newest_board_stands_and_an_outranked_order_never_does', false, false,
  'Study item F, second half: ottoq_agent_charge_order_live ranks the taken orders by LEAST(board_tick, recorded_tick) '
  'then order_id, and the first stands while younger than the ttl (an outranked order never stands); 0614 took the '
  'last to arrive. New view ottoq_agent_charge_order_succession (stood, outranked_by, superseded_by). The seed half was '
  'made by 0712. The live order is read only with agent_charge_order on, which is 0 on every certification and A/B '
  'harness run: FALSE/FALSE.',
  now());

COMMIT;
