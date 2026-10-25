-- 0473  **Run 763734d4, the first run with 0780-0782 and 0784 on, read in its first sim hour: rule 9 held on every
--        departure; the charge line equals its rank and no owner's cars changed places; at the boot every bay took a car
--        that still owed a charge, where the run before left both service bays empty; and the owner guard refused 10 of
--        the agent's 30 charge orders, none of which would have cleared the futures bar without it.**
--        -> G500 (not yet tested by the run), G501, G502, G504 (seen working, rule 12); G503 waits on agent v31's deploy.
--        Chase, 2026-10-25: "Run started", after pasting 0781-0784 with the four dials on at the twin depot under his
--        name (17:01:29 UTC, 12:01 PM CT).
--        Run 763734d4-17dc-4f77-9cd6-effdd0bcafd0: busy_day at the twin depot (rule 8), seed 5923901848364930217, live
--        playback at 3x, started 2026-10-25 18:49:54 UTC (1:49 PM CT) by operator_demo. Read against
--        gxdrcyphqjzjsuhxuqtg, read-only, between 18:51:27 and 19:13:32 UTC (1:51 and 2:13 PM CT), from sim 13:04 to
--        sim 14:08. Every figure names the moment it was read; the run was still going at the last read. One run, its
--        first sim hour: single readings, not ranges.
--
-- ══ §1 RULE 9 HELD (reproduce: (1)) ═════════════════════════════════════════════════════════════════════════════════════
--
--   By sim 13:50 (19:06:48 UTC), 18 cars had left since the run began, none below its target less one (the lowest at
--   99%). 16 left from a visit, and none of those with a required service open. By sim 14:08 (19:13:02 UTC), 43 had
--   left, 41 from a visit: still none below target less one (the lowest 99%) and none with a required service open.
--
-- ══ §2 THE LINE SERVES BY ITS RANK, AND EACH OWNER KEEPS ITS PLACES (G501, 0781; reproduce: (2), (3)) ══════════════════
--
--   Every charge-seat decision carries the rank 0781 computes: 145 of 145 at sim 13:04 (18:51:27 UTC), 1,525 of 1,525 at
--   sim 13:50 (19:06:36 UTC), 2,064 of 2,064 at sim 14:08 (19:12:44 UTC). By then 90 had seated a car (the rest found no
--   post free), 14 of them a car that was yielding its place (exit_key 1). A car whose turn in the bays is far off yields only until that turn
--   comes near, and is then seated; yielding delays it and does not strand it.
--   The live line, read against its own keys:
--     sim 13:06 (18:51:57 UTC)  37 cars waiting (Waymo Nashville 18, Tesla Robotaxi TN 10, Zoox Southeast 9). The
--                               kernel's order equalled the rank for every car. 2 were yielding and 11 had moved, every
--                               move within one owner's cars. No owner's set of places changed, and no yielding car stood
--                               ahead of a car of its own owner's that it yields to.
--     sim 13:50 (19:06:43 UTC)  14 waiting (Waymo Nashville 13, Zoox Southeast 1). Order equal to the rank, 2 yielding,
--                               none moved, no owner's places changed. The longest wait 50 minutes, the lowest battery
--                               13%.
--
-- ══ §3 AT THE BOOT EVERY BAY TOOK A CAR THAT STILL OWED A CHARGE (G502, 0782; reproduce: (4)) ═══════════════════════════
--
--   At 13:00:39, 39 sim seconds into the run, 0782 seated both service bays and all three wash bays with cars that still
--   owed a charge, each under its rule (no post free for the car, its battery not critical): 5ea53696 and 12cb06f0
--   (Waymo Nashville) on NASH-SVC-01 and -02 for 40-minute services; 9be45c35 (Tesla Robotaxi TN) and
--   a1111111-0001-0001-0001-000000000003 (Waymo Nashville; several fixture cars share that prefix) for details; and
--   380f0f38 (Tesla Robotaxi TN) for a wash and then a detail. By sim 13:57 (19:09:14 UTC)
--   each service bay had stood empty 1.0 minute in 57.7 sim minutes, and each wash bay 0.7. On 78c0624c (0470 §4) the
--   service bays stood empty 13:00-13:24:54 and 13:00-13:14:52 with no candidate, because every car needing a bay also
--   needed a charge and every post was taken. The seeds differ, so this compares the boot's shape, not a measured
--   difference.
--   Three of the five left at 100%, charged after their bays: 9be45c35 at sim 14:00:29, 380f0f38 at 14:00:56 and
--   a1111111-0001-0001-0001-000000000003 at 14:01:21 (read 19:13:19 UTC). The other two (12cb06f0 at 92%, 5ea53696 at
--   94%) were staged for a further service they owe; the departure test holds them until they are at target (rule 9).
--   Seven bay seats ahead of a charge in all by sim 14:08 (19:12:44 UTC), every one enacted.
--
-- ══ §4 HOLDS RELEASED FOR A CHARGE: NONE, AND TOO EARLY TO SAY (G500, 0780; reproduce: (2)) ═════════════════════════════
--
--   No reconcile action was blocked by 'charging' by sim 13:50 (19:06:36 UTC). On 78c0624c the holds 0470 §2 (b) read
--   began between 17:41 and 22:24, so this read says nothing about 0780 yet; the run's evening does.
--
-- ══ §5 THE OWNER GUARD REFUSED 10 OF 30, AND CHANGED NO OUTCOME YET (G504, 0784; reproduce: (2), (5)) ══════════════════
--
--   By sim 13:50 (19:06:36 UTC) the agent had sent 20 charge orders, and the check judged every one per owner ('owners'
--   on all 20). 2 were the kernel's own order. 11 were worse on the depot's totals in the expected future. 7 were level
--   or better on the totals but worse for one owner or two, and were refused 'worse_for_an_owner'. None was taken.
--   Each of the 7 won 4 to 7 of its 12 futures, against the 10 the bar needs (win_frac 0.8), so each would have been
--   refused without the guard too. The guard has changed no outcome on this run yet; what it adds is who would have
--   paid. Minutes past the contract's queue wait, the term that decided six of the seven for every owner, by order:
--
--     order  sim    futures won  Tesla Robotaxi TN  Waymo Nashville  Zoox Southeast
--     1884   13:05  5 of 12           +2.10             -13.07            -2.44
--     1887   13:10  6 of 12           +0.03             +18.18           -25.40     (Tesla judged on minutes in the depot,
--                                                                                     -14.17)
--     1889   13:14  7 of 12           +5.79              -5.81            -1.62
--     1895   13:27  5 of 12           +2.83             -21.88            +5.80
--     1896   13:29  4 of 12           +2.77             -35.94           +15.18
--     1897   13:30  5 of 12           +1.72             -43.61            +9.55
--     1898   13:33  7 of 12           -3.12             -15.04           +14.90
--
--   Six of the seven would have had Tesla Robotaxi TN's cars (five orders) or Zoox Southeast's (four) wait longer past
--   their contract so that Waymo Nashville's waited less; Waymo had 18 of the 37 cars in line at sim 13:06 and 13 of 14
--   at 13:50. The seventh did the reverse. This is the trade CLAUDE.md rule 14 rules out: a site total is not a reason to
--   move one owner's car behind another's.
--   By sim 14:08 (19:13:32 UTC) there were 30 orders, every one judged per owner: 6 the kernel's own, 14 worse on the
--   totals, 10 worse for an owner, none taken. The three new owner refusals (1907, 1910 and 1912) won 7, 7 and 8 of their
--   12 futures, short of the bar too. In 9 of the 10, Waymo Nashville's cars would have waited less past their contract,
--   and Tesla Robotaxi TN's (six orders) or Zoox Southeast's (seven) longer; the largest, 1910, -90.57 minutes for Waymo
--   against +72.00 for Zoox and +11.32 for Tesla.
--
-- ══ §6 THE AGENT IS STILL v30 (G503 waits on the deploy) ═══════════════════════════════════════════════════════════════
--
--   32 agent passes by 19:12:44 UTC, every one v30. v31, which reads 0783's 'constraint', waits on a session whose
--   connector can deploy (the live v42 is byte-identical to the repo's v30, read with get_edge_function at 18:54-18:56
--   UTC). At sim 13:21 (18:57:02 UTC) public.ottoq_depot_constraint read "The service bays are the wall: 5.04 hours of
--   work queued for 2 of them, 10 cars waiting", while by 18:57:33 UTC v30's 9 passes had written 27 directives, all
--   naming chargers and none the bays. That is G503's finding (0470 §5), on this run.
--
-- ══ §7 NEXT ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   One more read near the run's end (its 240-minute cap is set to stop it about 5:49 PM CT): rule 9 over the day,
--   0780's holds in the evening, the bays and the line under the evening return, and the guard over the day's orders,
--   with v31's read apart if it is deployed during the run.

-- (1) rule 9 on every departure since the run began: below target less one, and required work open on its visit
WITH r(id) AS (VALUES ('763734d4-17dc-4f77-9cd6-effdd0bcafd0'::uuid)),
d AS (SELECT dispatch_id, vehicle_id, dispatched_at, soc_at_dispatch_pct FROM public.ottoq_vehicle_dispatches
       WHERE sim_run_id = (SELECT id FROM r)
         AND dispatched_at >= (SELECT sim_clock_start FROM public.ottoq_sim_runs WHERE sim_run_id = (SELECT id FROM r))),
dv AS (SELECT d.*, v.atoms FROM d LEFT JOIN LATERAL (
         SELECT vn.atoms FROM public.ottoq_visit_needs vn WHERE vn.sim_run_id = (SELECT id FROM r)
            AND vn.vehicle_id = d.vehicle_id AND vn.arrived_at <= d.dispatched_at ORDER BY vn.arrived_at DESC LIMIT 1) v ON true)
SELECT now() AS read_at, count(*) AS departures,
       count(*) FILTER (WHERE dv.soc_at_dispatch_pct
                              < public.ottoq_effective_target_soc_at(dv.vehicle_id, dv.dispatched_at) - 1) AS below_target_less_one,
       min(dv.soc_at_dispatch_pct) AS lowest_soc,
       count(*) FILTER (WHERE dv.atoms IS NOT NULL) AS from_a_visit,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(dv.atoms, '[]'::jsonb)) a
          WHERE COALESCE(a ->> 'must_do', 'false') = 'true' AND COALESCE(a ->> 'status', 'pending') <> 'done'
            AND NOT (a ->> 'status' = 'cancelled' AND COALESCE(a ->> 'cleared_by_triage', 'false') = 'true'))) AS left_with_required_open
  FROM dv;

-- (2) the four changes in one read: charge seats and their rank (0781), bay seats ahead of a charge (0782), reconcile
--     actions blocked by a charge (0780), and the agent's orders by the check's reason (0784)
WITH r AS (SELECT '763734d4-17dc-4f77-9cd6-effdd0bcafd0'::uuid AS run)
SELECT now() AS read_at,
  (SELECT jsonb_build_object('status', x.status, 'sim', x.sim_clock_current, 'ticks', x.tick_count)
     FROM public.ottoq_sim_runs x, r WHERE x.sim_run_id = r.run) AS run,
  (SELECT jsonb_build_object('charge_seats', count(*),
            'with_rank', count(*) FILTER (WHERE d.context_frame #> '{charge_order,exit_rank}' IS NOT NULL),
            'by_exit_key_and_outcome', (SELECT jsonb_object_agg(z.k, z.n) FROM (
                SELECT (d2.context_frame #>> '{charge_order,exit_key}') || ':' || d2.outcome_status AS k, count(*) AS n
                  FROM public.ottoq_decisions d2, r r2
                 WHERE d2.sim_run_id = r2.run AND d2.action_context = 'stall_assignment' AND d2.context_frame ? 'charge_order'
                 GROUP BY 1) z))
     FROM public.ottoq_decisions d, r
    WHERE d.sim_run_id = r.run AND d.action_context = 'stall_assignment' AND d.context_frame ? 'charge_order') AS charge,
  (SELECT jsonb_build_object('bay_seats', count(*), 'before_charge', count(*) FILTER (WHERE d.context_frame ? 'bay_before_charge'),
            'enacted_before_charge', count(*) FILTER (WHERE d.context_frame ? 'bay_before_charge' AND d.outcome_status LIKE 'enact%'))
     FROM public.ottoq_decisions d, r
    WHERE d.sim_run_id = r.run AND d.action_context = 'task_start' AND d.context_frame ? 'purpose') AS bays,
  (SELECT count(*) FROM public.bay_reservation_reconcile_2026_08_02 rc, r
    WHERE rc.sim_run_id = r.run AND rc.blocked_by LIKE 'charging%') AS reconcile_blocked_by_charging,
  (SELECT jsonb_object_agg(x.reason, x.n) FROM (SELECT COALESCE(o.projection ->> 'reason', o.status) AS reason, count(*) AS n
      FROM public.ottoq_agent_charge_orders o, r WHERE o.sim_run_id = r.run GROUP BY 1) x) AS agent_orders,
  (SELECT count(*) FROM public.ottoq_agent_charge_orders o, r
    WHERE o.sim_run_id = r.run AND o.projection ? 'owners') AS orders_judged_per_owner,
  (SELECT jsonb_object_agg(p.agent_version, p.n) FROM (SELECT agent_version, count(*) AS n FROM public.ottoq_agent_pass_evidence e, r
      WHERE e.sim_run_id = r.run GROUP BY 1) p) AS passes_by_version;

-- (3) the live line against its own keys: is the kernel's order the rank, what moved, and did any owner's set of places
--     change (r0 is the order without 0781's exchange)
WITH r AS (SELECT x.sim_run_id AS run, x.depot_id AS depot, x.sim_clock_current AS clock FROM public.ottoq_sim_runs x
            WHERE x.sim_run_id = '763734d4-17dc-4f77-9cd6-effdd0bcafd0'),
k AS (SELECT ko.vehicle_id, ko.kernel_pos, ko.immediate, ko.wait_min, ko.gap, ko.soc, ok.floor_key, ok.minutes_key,
             ok.exit_key, ok.exit_rank, v.fleet_operator_id AS op
        FROM r, public.ottoq_charge_queue_kernel_order(r.run, r.depot, r.clock) ko
        JOIN public.ottoq_charge_order_keys((SELECT run FROM r), (SELECT depot FROM r), (SELECT clock FROM r)) ok
          ON ok.vehicle_id = ko.vehicle_id
        JOIN public.vehicles v ON v.id = ko.vehicle_id),
z AS (SELECT k.*, (row_number() OVER (ORDER BY k.immediate DESC, k.floor_key DESC NULLS LAST, k.minutes_key DESC NULLS LAST,
                                              (k.wait_min + k.gap) / k.gap DESC NULLS LAST, k.soc ASC, k.vehicle_id))::int AS r0
        FROM k)
SELECT now() AS read_at, (SELECT clock FROM r) AS sim_clock, count(*) AS cars_in_line,
       count(*) FILTER (WHERE z.kernel_pos IS DISTINCT FROM z.exit_rank) AS pos_not_rank,
       count(*) FILTER (WHERE z.exit_key = 1) AS yielding,
       count(*) FILTER (WHERE z.kernel_pos <> z.r0) AS moved,
       (SELECT count(*) FROM (SELECT op, array_agg(kernel_pos ORDER BY kernel_pos) AS a, array_agg(r0 ORDER BY r0) AS b
                                FROM z GROUP BY op) q
         WHERE q.a IS DISTINCT FROM q.b) AS owners_whose_places_changed,
       (SELECT count(*) FROM z a JOIN z c ON c.op IS NOT DISTINCT FROM a.op AND c.kernel_pos > a.kernel_pos
         WHERE NOT a.immediate AND NOT c.immediate AND a.floor_key IS NULL AND c.floor_key IS NULL
           AND a.exit_key = 1 AND COALESCE(c.exit_key, 0) = 0) AS yielder_ahead_of_own_exit_car,
       (SELECT jsonb_object_agg(COALESCE(fo.name, 'none'), q.n) FROM (SELECT op, count(*) AS n FROM z GROUP BY op) q
          LEFT JOIN public.fleet_operators fo ON fo.id = q.op) AS cars_by_owner,
       round(max(z.wait_min)) AS longest_wait_min, min(round(z.soc)) AS lowest_soc_in_line
  FROM z;

-- (4) the bays at the boot: each bay's first seat and its idle minutes so far, then the seats of the first 20 minutes and
--     whether 0782 made them ahead of the car's charge
WITH r AS (SELECT sim_run_id AS run, sim_clock_start AS t0, sim_clock_current AS tn FROM public.ottoq_sim_runs
            WHERE sim_run_id = '763734d4-17dc-4f77-9cd6-effdd0bcafd0'),
bays AS (SELECT s.id, s.stall_code, s.stall_type::text AS kind FROM public.stalls s
          WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.stall_type::text IN ('service_bay', 'wash_bay')),
seats AS (SELECT b.stall_id, b.during * tstzrange(r.t0, r.tn) AS w FROM public.ottoq_stall_bookings b, r
           WHERE b.sim_run_id = r.run AND b.state IN ('active', 'done', 'interrupted') AND b.during && tstzrange(r.t0, r.tn))
SELECT now() AS read_at, (SELECT tn FROM r) AS sim_now, bays.kind, bays.stall_code,
       to_char(min(lower(seats.w)), 'HH24:MI:SS') AS first_seat, count(seats.*) AS seats,
       round(extract(epoch FROM (SELECT tn - t0 FROM r)) / 60.0
             - COALESCE((SELECT sum(extract(epoch FROM upper(x) - lower(x))) FROM unnest(range_agg(seats.w)) x), 0) / 60.0, 1)
         AS idle_min_so_far
  FROM bays LEFT JOIN seats ON seats.stall_id = bays.id
 GROUP BY bays.kind, bays.stall_code ORDER BY bays.kind, bays.stall_code;

WITH r AS (SELECT sim_run_id AS run, sim_clock_start AS t0 FROM public.ottoq_sim_runs
            WHERE sim_run_id = '763734d4-17dc-4f77-9cd6-effdd0bcafd0'),
bbc AS (SELECT DISTINCT d.entity_id AS vehicle_id, d.context_frame ->> 'purpose' AS purpose FROM public.ottoq_decisions d, r
         WHERE d.sim_run_id = r.run AND d.action_context = 'task_start' AND d.context_frame ? 'bay_before_charge'
           AND d.outcome_status LIKE 'enact%')
SELECT s.stall_code, b.purpose, b.state, left(b.vehicle_id::text, 8) AS car,
       (SELECT fo.name FROM public.vehicles v JOIN public.fleet_operators fo ON fo.id = v.fleet_operator_id
         WHERE v.id = b.vehicle_id) AS owner,
       to_char(lower(b.during), 'HH24:MI:SS') AS t0, to_char(upper(b.during), 'HH24:MI:SS') AS t1,
       EXISTS (SELECT 1 FROM bbc WHERE bbc.vehicle_id = b.vehicle_id AND bbc.purpose = b.purpose) AS bay_before_charge,
       (SELECT v.current_state FROM public.vehicles v WHERE v.id = b.vehicle_id) AS state_now,
       (SELECT round(v.current_soc) FROM public.vehicles v WHERE v.id = b.vehicle_id) AS soc_now
  FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id = b.stall_id, r
 WHERE b.sim_run_id = r.run AND s.depot_id = '11111111-1111-1111-1111-111111111111'
   AND s.stall_type::text IN ('service_bay', 'wash_bay') AND b.state IN ('active', 'done', 'interrupted')
   AND lower(b.during) < r.t0 + interval '20 minutes'
 ORDER BY s.stall_code, lower(b.during);

-- (5) the orders the guard refused, each owner's comparison and differences, and the futures each won
SELECT o.order_id, to_char(o.sim_clock, 'HH24:MI') AS sim, o.projection ->> 'wins' AS wins,
       o.projection ->> 'futures' AS futures, o.projection ->> 'need' AS need, o.projection ->> 'win_frac' AS win_frac,
       (SELECT string_agg(COALESCE(fo.name, e.key) || ' cmp ' || (e.value ->> 'cmp') || ' by ' || (e.value ->> 'by')
                          || ' late ' || (e.value ->> 'd_late') || ' breach ' || (e.value ->> 'd_breach')
                          || ' flow ' || (e.value ->> 'd_flow'), ' | ' ORDER BY COALESCE(fo.name, e.key))
          FROM jsonb_each(o.projection -> 'owners') e LEFT JOIN public.fleet_operators fo ON fo.id::text = e.key) AS owners
  FROM public.ottoq_agent_charge_orders o
 WHERE o.sim_run_id = '763734d4-17dc-4f77-9cd6-effdd0bcafd0' AND o.projection ->> 'reason' = 'worse_for_an_owner'
 ORDER BY o.recorded_at;
