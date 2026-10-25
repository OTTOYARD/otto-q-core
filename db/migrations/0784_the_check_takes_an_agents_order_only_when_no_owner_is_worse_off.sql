-- migration-version: PENDING
-- migration-name:    the_check_takes_an_agents_order_only_when_no_owner_is_worse_off
--
-- 0784  **The kernel takes an agent's charge order only when no owner is worse off. The check judged an order by the
--       depot's totals, so it took orders that made one fleet's cars wait longer or finish later so another fleet's did
--       better; now each owner's cars are judged as the line is judged, and an order any owner would pay for is
--       refused.** (G504)
--       Chase, 2026-10-24: "all fleet owners will want their vehicle arriving to take precedence over any other vehicle
--       ... As long as you're not assuming others will be okay with their vehicle services/charges waiting for others in
--       a curteous way ... Remember, we don't own our own vehicles, we manage for others- and ideally multiple OEM's at
--       the same depot eventually. So always base decisions off of that framing." (CLAUDE.md rule 14.)
--       The kernel's own order is the neutral one, owner-blind (rule 14); an agent's order departs from it, and the check
--       is what decides whether it may. Rule 9 is untouched: no charge is shortened and no service skipped or deferred.
--
-- ══ §1 WHY, MEASURED (read-only; db/checks/0472 reproduces every figure) ════════════════════════════════════════════
--
--   At the twin depot in the ten days to 2026-10-25 00:00 UTC (7:00 PM CT on 2026-10-24) the check judged 976 agent
--   charge orders: 723 were the kernel's own order and 29 were taken (accepted or partial, 'wins_most_futures'), on six
--   runs, between 2026-10-20 21:08 and 2026-10-24 04:07 UTC. Each taken order was replayed from its own snapshot (the
--   state, the order and the seed the check read) on the live simulator, in the check's expected future, each owner's
--   cars summed as the check sums the line. The replay is the check's: all 29 were judged by today's code (md5
--   f5e7e90a, read at 7:08 PM CT), and its sums equal the check's own recorded totals (minutes past contract wait over
--   both visits to 0.1 minute on the six orders compared, minutes in the depot on five of six). Read at 6:56 PM CT
--   (23:56:18 UTC):
--
--   (a) 23 of the 29 left at least one owner worse off, by the check's own terms in its own order and with its own
--       margins (cars ready by their due time, then minutes late, then minutes past the contract's queue wait, then
--       minutes in the depot). 18 of the 23 on lateness or contract wait, the terms that decided them; 5 on minutes in
--       the depot alone (those five are approximate: the replay leaves out returns not seated inside the horizon).
--   (b) The largest: order 948 put 328 more minutes past contract wait on Tesla Robotaxi TN's cars while Waymo
--       Nashville's and Zoox Southeast's waited 84 and 549 fewer; order 1376, 89 more on Waymo's while Tesla's and Zoox's
--       waited 50 and 74 fewer; order 921 made Tesla's cars 82 minutes later in all so Zoox's were 148 earlier.
--   (c) 6 of the 29 left no owner worse: the guard would have taken them.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) One dial, a person's (rule 10): agent_charge_order_owner_guard (0..1, default 0).
--   (b) ottoq_charge_line_state: with the dial at 1, 'owner_guard': true and every car's owner ('owners',
--       vehicles.fleet_operator_id, as 0781 carries them when its key is on).
--   (c) ottoq_charge_line_schedule: with the state's owner_guard, 'by_owner': per owner ('none' for a car of no fleet)
--       the sums the line carries, by the same formulas: on_time, late_sum, flow_sum and breach_sum, and with the
--       outflow flow2_sum and breach2_sum. Each total is the sum of its owners' (to rounding).
--   (d) ottoq_charge_order_verdict_v2: when both sides of the expected future carry by_owner, each owner's two sides
--       are compared by ottoq_charge_line_compare (the line's terms and margins; an owner absent from one side counts
--       zeros there), and an order that leaves any owner worse is refused, reason 'worse_for_an_owner', after the
--       expected-future checks and before the count of futures won. 'owners' (each owner's cmp, by and differences) and
--       'owners_worse' say how each fared. Without by_owner on both sides, the verdict is 0620's exactly, so every stored
--       snapshot replays to the verdict it was given.
--   (e) The agent's board: 'check' carries owner_guard: true with the dial on.
--   Not changed: the rollout, the futures, the comparison of the line, the bar of futures won (win_frac), the kernel's
--   own order, any charge or service.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, no run running. P1 0781 applied; the four bodies are the ones this file was written against
--   (md5); the dial does not exist. Pre-images under '0784_pre'. Each anchor matches once. V1 each patched body is its
--   pre-image with its anchor replaced. V2 at the default, on the latest twin-depot run at its last clock: the state,
--   the board and the expected future (the simulator at scenario 0 on that state, its seats included) read value for
--   value as before, and the verdict on the latest checked order's rollout (two futures) is the one the pre-image
--   gives. V3: on constructed rollouts the verdict refuses an order one owner would pay for and takes it when no owner
--   pays; and in a sub-block that rolls back, with the dial at 1 on that run, the state carries the guard and every
--   car's owner, and each of the expected future's totals is the sum of its owners'. Executed in full by
--   tests/test_owner_guard_sql.py on the miniature depot carried through 0642 and 0781.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: at the default no state, sum, verdict or board changes, and no
--   certification arm, canon cell or dial experiment checks an agent order. Rule 12 has the switch go on at depot scope
--   under the deciding person's name, with one demo run to show it working.
--
-- ══ §5 WHAT THE REHEARSAL IS AND IS NOT ═══════════════════════════════════════════════════════════════════════════════
--
--   It replays the check's expected future with today's simulator from each order's snapshot; it does not rerun the
--   sampled futures each order also had to win. The guard judges the expected future only: an order that costs an
--   owner only in sampled futures is still taken. The hindsight grader (0621) still grades the check on the depot's
--   totals, so it will count some of the guard's refusals as wrong; grading per owner is not built here. Six runs of
--   one depot: single readings, not ranges.
--
-- ROLLBACK: EXECUTE every `definition` in ottoq_schema_snapshots WHERE label = '0784_pre' AND object_kind = 'function';
--   DELETE FROM public.ottoq_policy_params WHERE param_key = 'agent_charge_order_owner_guard'; DELETE FROM
--   public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_owner_guard'; DELETE FROM
--   public.ottoq_cert_lineage WHERE name = '0784_the_check_takes_an_agents_order_only_when_no_owner_is_worse_off'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight, no run running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0784 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0784 P0: a run is running; the check''s state, simulator and verdict would change mid-run. Apply between runs';
  END IF;
END $inflight$;

-- ── P1: 0781 is applied; every body is the one this file was written against; the dial does not exist ──
DO $premises$
DECLARE r record;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0784_the_check_takes_an_agents_order_only_when_no_owner_is_worse_off') THEN
    RAISE EXCEPTION '0784 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0781_the_charge_line_serves_first_the_cars_a_charge_sends_home') THEN
    RAISE EXCEPTION '0784 P1: 0781 is not applied; apply it first';
  END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 'c87de055e62f61b282bdb796f5cc53b6', 'the check''s state (after 0781)'),
      ('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', '4b40a03a7ac3383f654fdc104bcd6bbe', 'the check''s simulator (after 0781)'),
      ('public.ottoq_charge_order_verdict_v2(jsonb,numeric)', '394b3dc25ba60e8eccaa49f20474688c', 'the verdict (0620)'),
      ('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', '2233be29c1338eeed76e9ae94c129273', 'the agent''s board (after 0781)')) AS t(fn, want, what)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.fn)) IS DISTINCT FROM r.want THEN
      RAISE EXCEPTION '0784 P1: % (%) is not the body this file patches (md5 %)', r.what, r.fn, left(r.want, 8);
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_owner_guard') THEN
    RAISE EXCEPTION '0784 P1: the dial already exists';
  END IF;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0784_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure,
                 'public.ottoq_charge_order_verdict_v2(jsonb,numeric)'::regprocedure,
                 'public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure);

-- ── V2's before: the readers at the default, on the latest twin-depot run at its last clock, and the verdict on the
--    latest checked order's rollout ──
CREATE TEMP TABLE _0784_before ON COMMIT DROP AS
WITH r AS (
  SELECT sim_run_id, depot_id, sim_clock_current AS clock FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND sim_clock_current IS NOT NULL
   ORDER BY started_at DESC NULLS LAST LIMIT 1)
SELECT r.sim_run_id, r.depot_id, r.clock,
       public.ottoq_charge_line_state(r.sim_run_id, r.depot_id, r.clock) AS state,
       public.ottoq_agent_charge_queue_board(r.sim_run_id, r.depot_id, r.clock) AS board
  FROM r;
ALTER TABLE _0784_before ADD COLUMN sums jsonb;
UPDATE _0784_before SET sums = public.ottoq_charge_line_schedule(state, NULL, 0, 'v2', true);

CREATE TEMP TABLE _0784_rollout ON COMMIT DROP AS
SELECT s.order_id, s.win_frac, public.ottoq_charge_line_rollout(s.state, s.agent_order, 2, s.seed) AS rollout
  FROM public.ottoq_charge_order_snapshots s
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
 ORDER BY s.order_id DESC LIMIT 1;
ALTER TABLE _0784_rollout ADD COLUMN verdict jsonb;
UPDATE _0784_rollout SET verdict = public.ottoq_charge_order_verdict_v2(rollout, win_frac);

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('agent_charge_order_owner_guard',
        '0784 (G504): 1 = the kernel takes an agent''s charge order only when no owner is worse off in the check''s '
        'expected future: each owner''s cars (vehicles.fleet_operator_id) are judged as the line is judged (cars ready '
        'by their due time, then minutes late, then minutes past the contract''s queue wait, then minutes in the depot, '
        'the same margins), and an order any owner would pay for is refused (''worse_for_an_owner''), whatever the depot '
        'as a whole gains. We manage each car for its owner (CLAUDE.md rule 14). 0 = 0620''s verdict. A person''s dial, '
        'never the agent''s (rule 10).',
        0, 0, 1, 'public.ottoq_charge_line_state, public.ottoq_charge_line_schedule, public.ottoq_charge_order_verdict_v2, '
                 'public.ottoq_agent_charge_queue_board', false);

-- ── (b)-(e): the anchored replacements ──
CREATE TEMP TABLE _0784_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0784_patch VALUES
  -- (b) the state says the check judges each owner, and carries every car's owner
  (1, 'public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o1$                    FROM vehicles ov WHERE ov.home_depot_id = p_depot_id AND ov.category = 'autonomous'));
  END IF;
$o1$,
   $n1$                    FROM vehicles ov WHERE ov.home_depot_id = p_depot_id AND ov.category = 'autonomous'));
  END IF;
  -- 0784 (G504): with agent_charge_order_owner_guard at 1 the check judges each owner on its own cars: the state says so,
  -- and carries every car's owner (as 0781's key does when it is on)
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_owner_guard', 0), 0) >= 1 THEN
    v_state := v_state || jsonb_build_object('owner_guard', true)
               || CASE WHEN v_state ? 'owners' THEN '{}'::jsonb
                       ELSE jsonb_build_object('owners',
                              (SELECT COALESCE(jsonb_object_agg(ov.id::text, ov.fleet_operator_id), '{}'::jsonb)
                                 FROM vehicles ov WHERE ov.home_depot_id = p_depot_id AND ov.category = 'autonomous')) END;
  END IF;
$n1$),
  -- (c) the simulator sums each owner's cars as it sums the line
  (2, 'public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure,
   $o2$  IF jsonb_typeof(p_state -> 'holds') = 'array' THEN                                               -- 0639
    v_out := v_out || jsonb_build_object('holds', nh, 'holds_unmodelled', h_un);
  END IF;
$o2$,
   $n2$  IF COALESCE((p_state ->> 'owner_guard')::boolean, false) THEN                                    -- 0784 (G504)
    -- each owner's cars (the state's owners; 'none' for a car of no fleet), summed exactly as the line is summed above:
    -- the cars here now and coming home, then their next visits. The check judges each owner on its own sums.
    SELECT v_out || jsonb_build_object('by_owner', COALESCE(jsonb_object_agg(q.op, q.j), '{}'::jsonb))
      INTO v_out
      FROM (SELECT COALESCE(f.op, r.op) AS op,
                   jsonb_build_object('on_time', COALESCE(f.on_time, 0),
                                      'late_sum', round(COALESCE(f.late, 0)::numeric, 2),
                                      'flow_sum', round(COALESCE(f.flow, 0)::numeric, 2))
                   || CASE WHEN o_on THEN jsonb_build_object('flow2_sum', round((COALESCE(f.flow, 0) + COALESCE(r.flow, 0))::numeric, 2))
                           ELSE '{}'::jsonb END
                   || CASE WHEN v_keys THEN jsonb_build_object('breach_sum', round(COALESCE(f.breach, 0)::numeric, 2))
                           ELSE '{}'::jsonb END
                   || CASE WHEN v_keys AND o_on
                           THEN jsonb_build_object('breach2_sum', round((COALESCE(f.breach, 0) + COALESCE(r.breach, 0))::numeric, 2))
                           ELSE '{}'::jsonb END AS j
              FROM (SELECT COALESCE(v_own ->> c_id[z.i], 'none') AS op,
                           count(*) FILTER (WHERE c_due[z.i] IS NOT NULL AND c_ready[z.i] IS NOT NULL
                                              AND c_ready[z.i] <= c_due[z.i]) AS on_time,
                           COALESCE(sum(GREATEST(COALESCE(c_ready[z.i], v_hor + LEAST(c_md[z.i], c_ml[z.i])) - c_due[z.i], 0))
                                    FILTER (WHERE c_due[z.i] IS NOT NULL), 0) AS late,
                           COALESCE(sum(COALESCE(c_ready[z.i], v_hor + LEAST(c_md[z.i], c_ml[z.i])) - c_av[z.i]), 0) AS flow,
                           COALESCE(sum(GREATEST(c_w0[z.i] + COALESCE(c_s0[z.i], v_hor) - c_av[z.i] - c_mw[z.i], 0))
                                    FILTER (WHERE c_mw[z.i] IS NOT NULL), 0) AS breach
                      FROM generate_subscripts(c_ready, 1) AS z(i) WHERE z.i <= n0 GROUP BY 1) f
              FULL JOIN (SELECT COALESCE(v_own ->> c_id[z.i], 'none') AS op,
                                COALESCE(sum(CASE WHEN c_vk[z.i] = 2 THEN LEAST(c_md[z.i], c_ml[z.i])
                                                  ELSE COALESCE(c_ready[z.i], v_hor + LEAST(c_md[z.i], c_ml[z.i])) - c_av[z.i] END)
                                         FILTER (WHERE NOT c_void[z.i]), 0) AS flow,
                                COALESCE(sum(GREATEST(COALESCE(c_s0[z.i], v_hor) - c_av[z.i] - c_mw[z.i], 0))
                                         FILTER (WHERE c_mw[z.i] IS NOT NULL AND NOT c_void[z.i] AND c_vk[z.i] = 1), 0) AS breach
                           FROM generate_series(n0 + 1, GREATEST(n, n0)) AS z(i)
                          WHERE o_on AND z.i > n0 AND c_vk[z.i] > 0 GROUP BY 1) r ON r.op = f.op) q;
  END IF;
  IF jsonb_typeof(p_state -> 'holds') = 'array' THEN                                               -- 0639
    v_out := v_out || jsonb_build_object('holds', nh, 'holds_unmodelled', h_un);
  END IF;
$n2$),
  -- (d) the verdict refuses an order that leaves any owner worse off
  (3, 'public.ottoq_charge_order_verdict_v2(jsonb,numeric)'::regprocedure,
   $o3$  -- 0620: take the agent's order only when it wins the expected future and at least ceil(win_frac x futures) of all.
  -- 'kernel' and 'agent' are the expected future's two sides, as 0618's projection carried them.
  SELECT jsonb_build_object(
           'take', x.take, 'reason', x.reason, 'futures', x.n, 'wins', x.w, 'ties', x.ti, 'losses', x.l, 'need', x.need,
           'win_frac', p_win_frac, 'expected', x.pcmp, 'expected_by', x.pby,
           'kernel', p_rollout #> '{point,kernel}', 'agent', p_rollout #> '{point,agent}',
           'first', p_rollout -> 'first', 'per', p_rollout -> 'per')
    FROM (SELECT s.n, s.w, s.ti, s.l, s.need, s.pcmp, s.pby,
                 (NOT s.same AND s.pcmp = 1 AND s.w >= s.need) AS take,
                 CASE WHEN s.n IS NULL THEN 'no_rollout'
                      WHEN s.same THEN 'same_as_kernel'
                      WHEN s.pcmp < 0 THEN 'worse_in_expected_future'
                      WHEN s.pcmp = 0 THEN 'no_better_in_expected_future'
                      WHEN s.w < s.need THEN 'not_enough_futures_won'
                      ELSE 'wins_most_futures' END AS reason
            FROM (SELECT (p_rollout ->> 'futures')::int AS n, COALESCE((p_rollout ->> 'wins')::int, 0) AS w,
                         COALESCE((p_rollout ->> 'ties')::int, 0) AS ti, COALESCE((p_rollout ->> 'losses')::int, 0) AS l,
                         COALESCE((p_rollout ->> 'same_first_seats')::boolean, false) AS same,
                         COALESCE((p_rollout #>> '{point,cmp}')::int, 0) AS pcmp, p_rollout #>> '{point,by}' AS pby,
                         ceil(COALESCE(p_win_frac, 0.8) * COALESCE((p_rollout ->> 'futures')::int, 1))::int AS need) s) x
$o3$,
   $n3$  -- 0620: take the agent's order only when it wins the expected future and at least ceil(win_frac x futures) of all.
  -- 'kernel' and 'agent' are the expected future's two sides, as 0618's projection carried them.
  -- 0784 (G504): and only when no owner is worse off in the expected future. When both sides carry by_owner (the
  -- state's owner_guard: ottoq_charge_line_state, ottoq_charge_line_schedule), each owner's cars are judged as the line
  -- is judged (ottoq_charge_line_compare on that owner's own sums; an owner absent from one side counts zeros there),
  -- and an order that leaves any owner worse is refused ('worse_for_an_owner'), whatever the depot as a whole gains:
  -- we manage each car for its owner (CLAUDE.md rule 14). 'owners' says how each owner fared and 'owners_worse' how
  -- many fared worse. Without by_owner on both sides, 0620's verdict exactly.
  SELECT jsonb_build_object(
           'take', x.take, 'reason', x.reason, 'futures', x.n, 'wins', x.w, 'ties', x.ti, 'losses', x.l, 'need', x.need,
           'win_frac', p_win_frac, 'expected', x.pcmp, 'expected_by', x.pby,
           'kernel', p_rollout #> '{point,kernel}', 'agent', p_rollout #> '{point,agent}',
           'first', p_rollout -> 'first', 'per', p_rollout -> 'per')
         || CASE WHEN x.owners IS NOT NULL THEN jsonb_build_object('owners', x.owners, 'owners_worse', x.ow)
                 ELSE '{}'::jsonb END                                                                     -- 0784
    FROM (SELECT s.n, s.w, s.ti, s.l, s.need, s.pcmp, s.pby, o.owners, COALESCE(o.ow, 0)::int AS ow,
                 (NOT s.same AND s.pcmp = 1 AND s.w >= s.need AND COALESCE(o.ow, 0) = 0) AS take,
                 CASE WHEN s.n IS NULL THEN 'no_rollout'
                      WHEN s.same THEN 'same_as_kernel'
                      WHEN s.pcmp < 0 THEN 'worse_in_expected_future'
                      WHEN s.pcmp = 0 THEN 'no_better_in_expected_future'
                      WHEN COALESCE(o.ow, 0) > 0 THEN 'worse_for_an_owner'                                     -- 0784
                      WHEN s.w < s.need THEN 'not_enough_futures_won'
                      ELSE 'wins_most_futures' END AS reason
            FROM (SELECT (p_rollout ->> 'futures')::int AS n, COALESCE((p_rollout ->> 'wins')::int, 0) AS w,
                         COALESCE((p_rollout ->> 'ties')::int, 0) AS ti, COALESCE((p_rollout ->> 'losses')::int, 0) AS l,
                         COALESCE((p_rollout ->> 'same_first_seats')::boolean, false) AS same,
                         COALESCE((p_rollout #>> '{point,cmp}')::int, 0) AS pcmp, p_rollout #>> '{point,by}' AS pby,
                         ceil(COALESCE(p_win_frac, 0.8) * COALESCE((p_rollout ->> 'futures')::int, 1))::int AS need) s
            -- 0784: each owner, its own two sides compared
            LEFT JOIN LATERAL (
              SELECT jsonb_object_agg(z.op, z.c - 'd_flow1' - 'd_out') AS owners,
                     count(*) FILTER (WHERE (z.c ->> 'cmp')::int < 0) AS ow
                FROM (SELECT u.op,
                             public.ottoq_charge_line_compare(
                               COALESCE(b.k -> u.op, (SELECT jsonb_object_agg(e.key, 0) FROM jsonb_each(b.a -> u.op) e)),
                               COALESCE(b.a -> u.op, (SELECT jsonb_object_agg(e.key, 0) FROM jsonb_each(b.k -> u.op) e))) AS c
                        FROM (SELECT p_rollout #> '{point,kernel,by_owner}' AS k, p_rollout #> '{point,agent,by_owner}' AS a) b
                        CROSS JOIN LATERAL (SELECT jsonb_object_keys(b.k) AS op UNION SELECT jsonb_object_keys(b.a)) u
                       WHERE jsonb_typeof(b.k) = 'object' AND jsonb_typeof(b.a) = 'object') z) o ON true) x
$n3$),
  -- (e) the agent's board says the check does
  (4, 'public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o4$                         FROM m WHERE COALESCE((m.rt ->> 'usable')::boolean, false))),
    'cars', COALESCE((SELECT jsonb_agg(cars.j ORDER BY cars.kernel_pos) FROM cars), '[]'::jsonb),
$o4$,
   $n4$                         FROM m WHERE COALESCE((m.rt ->> 'usable')::boolean, false)))
      -- 0784 (G504): and, with the owner guard on, that the check refuses an order leaving any operator worse off
      || CASE WHEN COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_owner_guard', 0), 0) >= 1
              THEN jsonb_build_object('owner_guard', true) ELSE '{}'::jsonb END,
    'cars', COALESCE((SELECT jsonb_agg(cars.j ORDER BY cars.kernel_pos) FROM cars), '[]'::jsonb),
$n4$);

DO $patch$
DECLARE f regprocedure; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0784_patch LOOP
    v_def := pg_get_functiondef(f);
    FOR p IN SELECT * FROM _0784_patch WHERE fn = f ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0784: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(f) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0784: % is not stored as patched', f;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each patched body is its pre-image with its anchor replaced ──
DO $v1$
DECLARE r record; p record; v_body text; v_n int := 0;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 'c87de055e62f61b282bdb796f5cc53b6'),
      ('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', '4b40a03a7ac3383f654fdc104bcd6bbe'),
      ('public.ottoq_charge_order_verdict_v2(jsonb,numeric)', '394b3dc25ba60e8eccaa49f20474688c'),
      ('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', '2233be29c1338eeed76e9ae94c129273')) AS t(fn, pre)
  LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = to_regprocedure(r.fn);
    FOR p IN SELECT * FROM _0784_patch WHERE fn = to_regprocedure(r.fn) ORDER BY seq DESC LOOP
      IF strpos(v_body, p.c_new) = 0 THEN
        RAISE EXCEPTION '0784 V1: % does not carry replacement %', r.fn, p.seq;
      END IF;
      v_body := replace(v_body, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_body) IS DISTINCT FROM r.pre THEN
      RAISE EXCEPTION '0784 V1: % less its replacement is not its pre-image (md5 %)', r.fn, md5(v_body);
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE '0784 V1: % bodies are their pre-images with their anchors replaced', v_n;
END $v1$;

-- ── V2: at the default the readers read as before, value for value, and so does the verdict ──
DO $v2$
DECLARE b record; o record; v_s jsonb; v_bd jsonb; v_sum jsonb; v_v jsonb;
BEGIN
  SELECT * INTO b FROM _0784_before;
  IF FOUND THEN
    v_s := public.ottoq_charge_line_state(b.sim_run_id, b.depot_id, b.clock);
    v_bd := public.ottoq_agent_charge_queue_board(b.sim_run_id, b.depot_id, b.clock);
    v_sum := public.ottoq_charge_line_schedule(b.state, NULL, 0, 'v2', true);
    IF v_s IS DISTINCT FROM b.state OR v_bd IS DISTINCT FROM b.board OR v_sum IS DISTINCT FROM b.sums THEN
      RAISE EXCEPTION '0784 V2: at the default a reader moved on run % at %: state %, board %, expected future %',
        b.sim_run_id, b.clock, v_s = b.state, v_bd = b.board, v_sum = b.sums;
    END IF;
    RAISE NOTICE '0784 V2: at the default, run % at %: the state, the board and the expected future read as before',
      left(b.sim_run_id::text, 8), b.clock;
  ELSE
    RAISE NOTICE '0784 V2: no twin-depot run to read; the tests execute it';
  END IF;
  SELECT * INTO o FROM _0784_rollout;
  IF FOUND THEN
    v_v := public.ottoq_charge_order_verdict_v2(o.rollout, o.win_frac);
    IF v_v IS DISTINCT FROM o.verdict THEN
      RAISE EXCEPTION '0784 V2: the verdict on order %''s rollout moved: % against %', o.order_id, v_v - 'per',
        o.verdict - 'per';
    END IF;
    RAISE NOTICE '0784 V2: the verdict on order %''s rollout is the one the pre-image gives (%)', o.order_id,
      o.verdict ->> 'reason';
  ELSE
    RAISE NOTICE '0784 V2: no checked order at the twin depot to replay; the tests execute the verdict';
  END IF;
END $v2$;

-- ── V3: the verdict refuses what an owner would pay for; with the dial at 1 the state and sums carry each owner ──
DO $v3$
DECLARE b record; v_found boolean; v_msg text := NULL; v_k jsonb; v_a jsonb; v_a2 jsonb; v_r jsonb; v_r2 jsonb; v_v jsonb;
        v_state jsonb; v_out jsonb; v_cars int; v_owners int := 0; v_bad text;
BEGIN
  -- an order the depot gains from (the expected future better, every future won) that makes fleet B's cars wait 10
  -- minutes more past contract so fleet A's wait 40 fewer: refused, where 0620's verdict takes it; with B's no worse,
  -- taken
  v_k := jsonb_build_object('on_time', 0, 'late_sum', 0, 'flow_sum', 300, 'breach_sum', 90, 'by_owner', jsonb_build_object(
           'A', jsonb_build_object('on_time', 0, 'late_sum', 0, 'flow_sum', 150, 'breach_sum', 60),
           'B', jsonb_build_object('on_time', 0, 'late_sum', 0, 'flow_sum', 150, 'breach_sum', 30)));
  v_a := jsonb_build_object('on_time', 0, 'late_sum', 0, 'flow_sum', 300, 'breach_sum', 60, 'by_owner', jsonb_build_object(
           'A', jsonb_build_object('on_time', 0, 'late_sum', 0, 'flow_sum', 140, 'breach_sum', 20),
           'B', jsonb_build_object('on_time', 0, 'late_sum', 0, 'flow_sum', 160, 'breach_sum', 40)));
  v_a2 := jsonb_build_object('on_time', 0, 'late_sum', 0, 'flow_sum', 290, 'breach_sum', 50, 'by_owner', jsonb_build_object(
            'A', jsonb_build_object('on_time', 0, 'late_sum', 0, 'flow_sum', 140, 'breach_sum', 20),
            'B', jsonb_build_object('on_time', 0, 'late_sum', 0, 'flow_sum', 150, 'breach_sum', 30)));
  v_r := jsonb_build_object('same_first_seats', false, 'futures', 12, 'wins', 12, 'ties', 0, 'losses', 0,
           'point', public.ottoq_charge_line_compare(v_k, v_a) || jsonb_build_object('kernel', v_k, 'agent', v_a),
           'first', '{}'::jsonb, 'per', '[]'::jsonb);
  v_r2 := jsonb_set(v_r, '{point}', public.ottoq_charge_line_compare(v_k, v_a2) || jsonb_build_object('kernel', v_k, 'agent', v_a2));
  v_v := public.ottoq_charge_order_verdict_v2(v_r, 0.8);
  IF v_v ->> 'reason' IS DISTINCT FROM 'worse_for_an_owner' OR COALESCE((v_v ->> 'take')::boolean, true)
     OR (v_v ->> 'owners_worse')::int IS DISTINCT FROM 1 OR (v_v #>> '{owners,B,cmp}')::int IS DISTINCT FROM -1
     OR (v_v #>> '{owners,A,cmp}')::int IS DISTINCT FROM 1 THEN
    v_msg := format('an order fleet B pays for is not refused: %s', v_v - 'per');
  END IF;
  v_v := public.ottoq_charge_order_verdict_v2(v_r #- '{point,kernel,by_owner}' #- '{point,agent,by_owner}', 0.8);
  IF v_msg IS NULL AND (v_v ? 'owners' OR v_v ->> 'reason' IS DISTINCT FROM 'wins_most_futures') THEN
    v_msg := format('without by_owner the verdict is not 0620''s: %s', v_v - 'per');
  END IF;
  v_v := public.ottoq_charge_order_verdict_v2(v_r2, 0.8);
  IF v_msg IS NULL AND (v_v ->> 'reason' IS DISTINCT FROM 'wins_most_futures' OR NOT COALESCE((v_v ->> 'take')::boolean, false)
                        OR (v_v ->> 'owners_worse')::int IS DISTINCT FROM 0) THEN
    v_msg := format('an order no fleet pays for is not taken: %s', v_v - 'per');
  END IF;

  SELECT * INTO b FROM _0784_before;
  v_found := FOUND;
  IF v_msg IS NULL AND v_found THEN
    BEGIN
      INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value)
      VALUES ('run', b.sim_run_id, 'agent_charge_order_owner_guard', 1);
      v_state := public.ottoq_charge_line_state(b.sim_run_id, b.depot_id, b.clock);
      SELECT count(*) INTO v_cars FROM vehicles v WHERE v.home_depot_id = b.depot_id AND v.category = 'autonomous';
      IF v_state ->> 'owner_guard' IS DISTINCT FROM 'true'
         OR (SELECT count(*) FROM jsonb_object_keys(COALESCE(v_state -> 'owners', '{}'::jsonb))) <> v_cars THEN
        v_msg := 'the state does not carry the guard and every car''s owner';
      END IF;
      v_out := public.ottoq_charge_line_schedule(v_state, NULL, 0, 'v3', false);
      SELECT count(*) INTO v_owners FROM jsonb_object_keys(COALESCE(v_out -> 'by_owner', '{}'::jsonb));
      SELECT string_agg(t.key, ', ') INTO v_bad
        FROM (SELECT k.key FROM (VALUES ('on_time'), ('late_sum'), ('flow_sum'), ('breach_sum'), ('flow2_sum'), ('breach2_sum')) k(key)
               WHERE v_out ? k.key
                 AND abs((v_out ->> k.key)::numeric
                         - COALESCE((SELECT sum((e.value ->> k.key)::numeric) FROM jsonb_each(v_out -> 'by_owner') e), 0))
                     > 0.01 * GREATEST(v_owners, 1)) t;
      IF v_msg IS NULL AND (v_owners = 0 OR v_bad IS NOT NULL) THEN
        v_msg := format('the expected future''s totals are not the sums of its %s owners'' (%s)', v_owners,
                        COALESCE(v_bad, 'no owners'));
      END IF;
      RAISE EXCEPTION USING ERRCODE = 'P0784', MESSAGE = 'v3 done';
    EXCEPTION WHEN SQLSTATE 'P0784' THEN
      NULL;   -- the dial row and anything read under it roll back here
    END;
  END IF;
  IF v_msg IS NOT NULL THEN
    RAISE EXCEPTION '0784 V3: %', v_msg;
  END IF;
  IF NOT v_found THEN
    RAISE NOTICE '0784 V3: the verdict refuses an order an owner would pay for, which 0620''s takes, and takes one no owner pays for; no twin-depot run to read (the tests execute the rest)';
  ELSE
    RAISE NOTICE '0784 V3: the verdict refuses an order an owner would pay for, which 0620''s takes, and takes one no owner pays for; with the dial at 1 on run % the state carries the guard and every car''s owner, and each of the expected future''s totals is the sum of its % owners''',
      left(b.sim_run_id::text, 8), v_owners;
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0784_the_check_takes_an_agents_order_only_when_no_owner_is_worse_off', false, false,
        'Dial agent_charge_order_owner_guard (default 0). At 1 the check''s state carries every car''s owner, its '
        'simulator sums each owner''s cars as it sums the line (by_owner), and the verdict refuses an agent''s charge order '
        'that leaves any owner worse off in the expected future (''worse_for_an_owner''); the board says so. V1: each body '
        'is its pre-image with its anchor replaced; V2: at the default the state, the board, the expected future and the '
        'verdict read as before. No certification arm, canon cell or dial experiment checks an agent order.',
        now());

COMMIT;
