-- 0443  **The agent's charge order that stood was the last to arrive, not the one built from the newest board; and the
--        check's seed, now drawn from the world (0712), makes a verdict repeatable, not robust.** (Study item F; fixed
--        by 0706 for the order that stands; the seed half was made by 0712.) Measured 2026-10-13, read-only, against
--        otto-q-core (gxdrcyphqjzjsuhxuqtg), in a window whose first clock read was 18:05:16 UTC and last 18:38:16 UTC
--        (1:05-1:38 PM CT, both read from the database clock); the first counts of (1) and (2) were read before
--        18:05:16 and re-read at 18:38.
--
--   A CAUTION ABOUT THE WINDOW. Run 57188f55 (operator_demo, agent_charge_order on, random_seed 305838298283560562,
--   the seed of 176b2912) started at 18:08:54 UTC, inside this window. The replays of §2 are CPU-heavy (one rollout of
--   twelve futures each side is 1 to 25 seconds); three ran in parallel, and one ran on to the 2-minute statement
--   timeout, between 18:05:16 and 18:14:07 UTC, then one at a time until 18:30:12. The twin's live playback ties a tick's sim length to the database's load (CLAUDE.md 2.5, 0416), so
--   that run's first twenty minutes ran on a busier database than its pair. Nothing was written.
--
-- ══ §1 WHICH ORDER STOOD (reproduce (1)-(3)) ════════════════════════════════════════════════════════════════════════
--
--   0614's ottoq_agent_charge_order_live took the taken (accepted or partial) order with the highest order_id younger
--   than the ttl: the last to arrive. Over all 839 orders on 15 runs, read before 18:05:16 UTC:
--     - board_tick is never NULL and never later than recorded_tick; the lag recorded - board runs 0 to 21 ticks;
--     - 19 orders arrived with a lower board tick than an order recorded before them on the run; 8 of them were taken
--       (order ids 11, 39, 45, 74, 176, 178, 186, 209, runs 0bbdcc07 and 089f46bd, all before 0620). None of the 483
--       orders checked since 0620 arrived outranked;
--     - replayed tick by tick (every tick from a run's first order to its last plus the ttl: 7,583 run-ticks between
--       18:14:07 and 18:30:12 UTC, 7,932 at 18:38:16 as the live run grew, 2,713 with an order standing both times): the order 0614 stood
--       differs from the one 0706 stands on 77 run-ticks on those two runs;
--       ranking only the orders inside the ttl (the item's literal ORDER BY board_tick DESC, order_id DESC) would differ
--       from 0614 on 74 and from 0706 on 3, the 3 being an outranked order coming back after the fresher one expired;
--     - recorded_tick never goes back as order_id rises within a run (0 of 839): arrival order is order_id order.
--
-- ══ §2 THE SEED (reproduce (4)) ═════════════════════════════════════════════════════════════════════════════════════
--
--   When this file began, the check's seed was sim_run_id : tick : chain_id (0620). 0712 replaced it at 18:19:32 UTC
--   with 'world:' || random_seed || ':' || recorded tick, so the item's premise was false by the time 0706 was written,
--   and 0706 does not touch the seed. Replayed from the 483 post-0620 snapshots with today's functions
--   (ottoq_charge_order_verdict_v2(ottoq_charge_line_rollout(state, agent_order, futures, <seed>), win_frac)):
--     - with the STORED seed, today's functions reproduce the recorded verdict on every order replayed with it (28 of
--       28: take or refuse, and futures won, all equal). Code drift since 0620 moves none of them;
--     - with only the run id in the old seed changed (a fake id): the verdict flips on 6 of 28 heavy orders replayed,
--       5 of the 8 takes to refused (382, 385, 479, 717, 757) and one refusal to a take (364). This is the study's
--       finding, reproduced: 382 10 -> 8 futures won, 385 11 -> 9;
--     - under 0712's seed (world:random_seed:recorded tick), on the 8 takes: 4 stay taken (385, 467, 604, 793) and 4
--       would be refused (382 8 won, 479 6, 717 3, 757 8);
--     - under the item's proposed seed (random_seed : recorded tick : md5 of the order's cars and kinds in rank order):
--       5 of 8 takes stay, 3 refused (382, 479, 717); of 29 refusals replayed, 3 become takes (364, 468, 606); the 401
--       orders the check found the same as the kernel's all stay the same. With the board tick in place of the
--       recorded tick: 4 of 8 takes stay.
--   BOUNDED: 37 of the 82 orders the check did not find the same as the kernel's were replayed under the item's seed
--   (all 8 takes and 29 refusals: the first 20 by order id, and the 9 later ones with 8 or 9 futures won); 28 of those
--   37 also under the stored seed and the old seed with a fake run id, and the 8 takes under 0712's. The other 45 were
--   not run, to keep the load off the live run above: 22 refusals with 7 or fewer futures won, and 23 "worse in the
--   expected future" after order 418. The 401 "same as the kernel" orders were all replayed, under the item's seed.
--   The study's "41 of 416 post-0620 orders are seed-sensitive" was not re-derived (it needs all 82).
--
--   What it means: a fixed seed makes the verdict repeatable. It does not make it robust: near the bar (10 of 12
--   futures) the verdict is the draw's, and 4 of the 8 orders the check took would not have been taken under another
--   equally valid draw. 0712 §1 says the same; this is the count.
--
--   Two things found on the way, for a person:
--     a. 0712's header says "a run with no random_seed (a production session) falls back to its id". On the engine
--        ottoq_sim_runs.random_seed is bigint NOT NULL DEFAULT 42, so no run lacks one: the fallback never fires, and
--        every production session that did not set a seed draws 'world:42:<tick>' (production run c4ee1572 carries
--        42). Harmless for the check (each session's state differs), but the sentence is not true of the engine; the
--        scratch stub's column is nullable, which is why 0712's test could exercise it.
--     b. "The expected future draws nothing" (tests/test_agent_arbiter_sql.py, 0620) has not been true since 0623/0624:
--        ottoq_charge_line_schedule orders the expected future's stratified dwell, call-home and drain draws by
--        md5(seed || ':' || car || ':dwell' / ':other' / ':drain'). Measured: orders 479 and 717 are taken with their
--        stored seed and "worse in the expected future" under another seed. The expected future is a function of the
--        seed whenever the state carries returning cars.
--
-- ══ §3 WHAT 0706 CHANGES, AND HOW TO SEE IT WORKED (the post-apply checks: (5)-(9), each with what it must return) ══
--
--   ottoq_agent_charge_order_live ranks the taken orders recorded by the tick by LEAST(board_tick, recorded_tick) DESC,
--   then order_id DESC, and the first stands while younger than the ttl; otherwise nothing stands. The view
--   ottoq_agent_charge_order_succession says for each taken order whether it stood, what outranked it, what replaced it.
--
-- ══ REPRODUCE (read-only) ══

-- (1) the lag, and orders that arrived behind a fresher board (before 18:05:16 UTC: 839 orders, 0 null boards, 0 boards after
--     their recorded tick, lag 0-21, 19 out of board order, 8 of them taken: 11,39,45,74,176,178,186,209; the same at
--     18:38:07 UTC over 849 orders)
WITH o AS (SELECT o.*, max(board_tick) OVER (PARTITION BY sim_run_id ORDER BY order_id
                                             ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS max_prev_board
             FROM public.ottoq_agent_charge_orders o)
SELECT count(*) AS orders, count(*) FILTER (WHERE board_tick IS NULL) AS null_board,
       count(*) FILTER (WHERE board_tick > recorded_tick) AS board_after_recorded,
       min(recorded_tick - board_tick) AS min_lag, max(recorded_tick - board_tick) AS max_lag,
       count(*) FILTER (WHERE board_tick < max_prev_board) AS out_of_board_order,
       count(*) FILTER (WHERE board_tick < max_prev_board AND status IN ('accepted', 'partial')) AS taken_out_of_order,
       string_agg(order_id::text, ',' ORDER BY order_id)
         FILTER (WHERE board_tick < max_prev_board AND status IN ('accepted', 'partial')) AS taken_ids
  FROM o;

-- (2) tick by tick: 0614's rule, the literal ORDER BY, and 0706's rule, inlined so they can be compared before and
--     after the apply (between 18:14:07 and 18:30:12 UTC: 7,583 run-ticks; at 18:38:16 UTC: 7,932; both times
--     old_vs_new 77, old_vs_lit 74, lit_vs_new 3, runs 089f46bd and 0bbdcc07)
WITH runs AS (SELECT sim_run_id, min(recorded_tick) t0, max(recorded_tick) t1,
                     GREATEST(1, COALESCE(public.ottoq_policy_get(sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15))::bigint ttl
                FROM public.ottoq_agent_charge_orders GROUP BY 1),
ticks AS (SELECT r.sim_run_id, r.ttl, t FROM runs r, generate_series(r.t0, r.t1 + r.ttl) t),
live AS (
  SELECT k.sim_run_id, k.t,
    (SELECT x.order_id FROM public.ottoq_agent_charge_orders x
      WHERE x.sim_run_id = k.sim_run_id AND x.status IN ('accepted', 'partial') AND x.recorded_tick <= k.t
        AND x.recorded_tick >= k.t - k.ttl ORDER BY x.order_id DESC LIMIT 1) AS old_id,
    (SELECT x.order_id FROM public.ottoq_agent_charge_orders x
      WHERE x.sim_run_id = k.sim_run_id AND x.status IN ('accepted', 'partial') AND x.recorded_tick <= k.t
        AND x.recorded_tick >= k.t - k.ttl ORDER BY x.board_tick DESC NULLS LAST, x.order_id DESC LIMIT 1) AS lit_id,
    (SELECT CASE WHEN y.recorded_tick >= k.t - k.ttl THEN y.order_id END
       FROM (SELECT x.order_id, x.recorded_tick FROM public.ottoq_agent_charge_orders x
              WHERE x.sim_run_id = k.sim_run_id AND x.status IN ('accepted', 'partial') AND x.recorded_tick <= k.t
              ORDER BY LEAST(x.board_tick, x.recorded_tick) DESC, x.order_id DESC LIMIT 1) y) AS new_id
    FROM ticks k)
SELECT count(*) AS run_ticks, count(*) FILTER (WHERE old_id IS NOT NULL) AS with_an_order,
       count(*) FILTER (WHERE old_id IS DISTINCT FROM new_id) AS old_vs_new,
       count(*) FILTER (WHERE old_id IS DISTINCT FROM lit_id) AS old_vs_lit,
       count(*) FILTER (WHERE lit_id IS DISTINCT FROM new_id) AS lit_vs_new,
       string_agg(DISTINCT left(sim_run_id::text, 8), ',') FILTER (WHERE old_id IS DISTINCT FROM new_id) AS runs
  FROM live;

-- (3) arrival order is order_id order (must return 0)
SELECT count(*) AS recorded_tick_goes_back
  FROM (SELECT recorded_tick < lag(recorded_tick) OVER (PARTITION BY sim_run_id ORDER BY order_id) AS back
          FROM public.ottoq_agent_charge_orders) z WHERE back;

-- (4) one replay, for one order at a time (HEAVY: 1-25 s per rollout; never in a loop over all orders while a run is
--     live). a = the stored seed, b1 = the old seed with a fake run id, w = 0712's seed. Order 382, between 18:05:16
--     and 18:30:12 UTC: a taken 10 won, b1 refused 8 won, w refused 8 won. (Another fake id, ...0001, gave 4 won at
--     18:05:16: the old seed's verdict moves with whatever id is put in it.)
SELECT s.order_id, o.projection ->> 'take' AS recorded_take, o.projection ->> 'wins' AS recorded_wins,
       public.ottoq_charge_order_verdict_v2(public.ottoq_charge_line_rollout(s.state, s.agent_order, s.futures, s.seed),
                                            s.win_frac) - 'per' - 'first' - 'kernel' - 'agent' AS a,
       public.ottoq_charge_order_verdict_v2(public.ottoq_charge_line_rollout(s.state, s.agent_order, s.futures,
                                              replace(s.seed, s.sim_run_id::text, '00000000-0000-0000-0000-0000000000a1')),
                                            s.win_frac) - 'per' - 'first' - 'kernel' - 'agent' AS b1,
       public.ottoq_charge_order_verdict_v2(public.ottoq_charge_line_rollout(s.state, s.agent_order, s.futures,
                                              'world:' || r.random_seed::text || ':' || o.recorded_tick),
                                            s.win_frac) - 'per' - 'first' - 'kernel' - 'agent' AS w
  FROM public.ottoq_charge_order_snapshots s
  JOIN public.ottoq_agent_charge_orders o USING (order_id)
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = s.sim_run_id
 WHERE s.order_id = 382;

-- ── AFTER 0706 IS APPLIED ──

-- (5) the definitions and the classification. Must return: bf57d4ed10f79cf555f3bb2350b82770 | v |
--     {security_invoker=true} | f | t | false false
SELECT md5(pg_get_functiondef('public.ottoq_agent_charge_order_live(uuid,bigint)'::regprocedure)) AS live_md5,
       c.relkind, c.reloptions,
       has_table_privilege('anon', c.oid, 'SELECT') AS anon_reads_the_view,
       has_table_privilege('authenticated', c.oid, 'SELECT') AS authenticated_reads_the_view,
       (SELECT forces_recert::text || ' ' || forces_dial_restart::text FROM public.ottoq_cert_lineage
         WHERE name = '0706_the_order_built_from_the_newest_board_stands_and_an_outranked_order_never_does') AS lineage
  FROM pg_class c WHERE c.oid = 'public.ottoq_agent_charge_order_succession'::regclass;

-- (6) the deployed function is the rule: at every run-tick of (2) it answers what 0706's inlined rule answers.
--     Must return mismatches = 0 (and run_ticks = (2)'s, old_vs_new = (2)'s)
WITH runs AS (SELECT sim_run_id, min(recorded_tick) t0, max(recorded_tick) t1,
                     GREATEST(1, COALESCE(public.ottoq_policy_get(sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15))::bigint ttl
                FROM public.ottoq_agent_charge_orders GROUP BY 1),
ticks AS (SELECT r.sim_run_id, r.ttl, t FROM runs r, generate_series(r.t0, r.t1 + r.ttl) t),
live AS (
  SELECT k.sim_run_id, k.t,
    (SELECT max((e.value ->> 'order_id')::bigint)
       FROM jsonb_each(public.ottoq_agent_charge_order_live(k.sim_run_id, k.t)) e) AS deployed_id,
    (SELECT CASE WHEN y.recorded_tick >= k.t - k.ttl THEN y.order_id END
       FROM (SELECT x.order_id, x.recorded_tick FROM public.ottoq_agent_charge_orders x
              WHERE x.sim_run_id = k.sim_run_id AND x.status IN ('accepted', 'partial') AND x.recorded_tick <= k.t
              ORDER BY LEAST(x.board_tick, x.recorded_tick) DESC, x.order_id DESC LIMIT 1) y) AS rule_id,
    (SELECT x.order_id FROM public.ottoq_agent_charge_orders x
      WHERE x.sim_run_id = k.sim_run_id AND x.status IN ('accepted', 'partial') AND x.recorded_tick <= k.t
        AND x.recorded_tick >= k.t - k.ttl ORDER BY x.order_id DESC LIMIT 1) AS old_id
    FROM ticks k)
SELECT count(*) AS run_ticks, count(*) FILTER (WHERE deployed_id IS DISTINCT FROM rule_id) AS mismatches,
       count(*) FILTER (WHERE old_id IS DISTINCT FROM deployed_id) AS old_vs_new
  FROM live;

-- (7) the view: every taken order is stood or outranked, never both; the 8 historical outranked orders are there.
--     Must return taken = stood + outranked, both_or_neither = 0, and historical_outranked = {11,39,45,74,176,178,186,209}
--     (more ids only if a later order arrived behind a fresher board)
SELECT count(*) AS taken, count(*) FILTER (WHERE stood) AS stood, count(*) FILTER (WHERE NOT stood) AS outranked,
       count(*) FILTER (WHERE (outranked_by IS NULL) <> stood OR (NOT stood AND superseded_by IS NOT NULL)) AS both_or_neither,
       array_agg(order_id ORDER BY order_id) FILTER (WHERE NOT stood) AS historical_outranked
  FROM public.ottoq_agent_charge_order_succession;

-- (8) the view and the function agree: a stood order is the live order at the tick it was recorded (unless one recorded
--     at that same tick replaced it), an outranked one never is. Must return 0 | 0
SELECT count(*) FILTER (WHERE s.stood
                          AND NOT EXISTS (SELECT 1 FROM public.ottoq_agent_charge_orders n
                                           WHERE n.order_id = s.superseded_by AND n.recorded_tick = s.recorded_tick)
                          AND (SELECT max((e.value ->> 'order_id')::bigint)
                                 FROM jsonb_each(public.ottoq_agent_charge_order_live(s.sim_run_id, s.recorded_tick)) e)
                              IS DISTINCT FROM s.order_id) AS stood_but_not_live,
       count(*) FILTER (WHERE NOT s.stood
                          AND (SELECT max((e.value ->> 'order_id')::bigint)
                                 FROM jsonb_each(public.ottoq_agent_charge_order_live(s.sim_run_id, s.recorded_tick)) e)
                              = s.order_id) AS outranked_but_live
  FROM public.ottoq_agent_charge_order_succession s;

-- (9) nothing was rewritten and no probe row survived; and every snapshot taken since 0712 carries 0712's seed.
--     Must return 0 | 0 | 0 (since_0712 is however many orders have been checked since 18:19:32 UTC)
SELECT (SELECT count(*) FROM public.ottoq_agent_charge_orders WHERE order_id <= 0 OR model = 'probe_0706') AS probe_rows,
       (SELECT count(*) FROM public.ottoq_charge_order_snapshots s
          JOIN public.ottoq_agent_charge_orders o USING (order_id) JOIN public.ottoq_sim_runs r ON r.sim_run_id = s.sim_run_id
         WHERE s.recorded_at >= '2026-10-13 18:19:32.086453+00'
           AND s.seed IS DISTINCT FROM 'world:' || r.random_seed::text || ':' || o.recorded_tick) AS seed_not_0712s,
       (SELECT count(*) FROM public.ottoq_charge_order_snapshots s
         WHERE s.recorded_at >= '2026-10-13 18:19:32.086453+00' AND strpos(s.seed, s.sim_run_id::text) > 0) AS seed_names_its_run,
       (SELECT count(*) FROM public.ottoq_charge_order_snapshots s
         WHERE s.recorded_at >= '2026-10-13 18:19:32.086453+00') AS since_0712;
