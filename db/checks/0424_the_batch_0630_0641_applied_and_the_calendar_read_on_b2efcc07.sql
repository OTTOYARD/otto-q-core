-- 0424  **The batch 0630-0641 applied, agent v27 deployed, and the calendar read on b2efcc07 before its next run.**
--        Twelve migrations went onto the live engine between 5:09 and 5:46 AM CT on 2026-10-09, in order, each sent as
--        committed and each stored byte for byte. The agent that proposes the charge order was redeployed with the
--        prompt that reads what 0640 and 0641 put on its board. Then the check's own replay of b2efcc07 was run again on
--        the live functions: with the calendar's holds it places a car's plug-in 7.34 minutes from when it really
--        plugged in, where it was 12.19 without them, exactly the rehearsal 0639 was built on; on the run's latest 40
--        orders, 3.31 against 11.97. What is left after the holds is the kind of charger the replay picks, and a
--        handful of low-battery cars the kernel left waiting for hours (G384).
--
--        Written 2026-10-09, 6:00-6:20 AM CT. Read-only. Twin depot 11111111-…. One run: single readings, not ranges.
--
-- ══ §1 THE APPLIES (reproduce: (1)) ══
--
--   Each file was sent through the MCP connector's apply_migration exactly as committed with `PENDING`, minus its
--   final newline, and read back from supabase_migrations.schema_migrations: the stored statement's md5, characters
--   and bytes equal the file's on every one. Every P0, P1 and V block passed inside its own transaction.
--
--     0630  20261009100905   5:09 AM CT   c35804f9   51,968 / 54,408   the grader reads a run's stop as the stop (G372)
--     0631  20261009101257   5:12 AM CT   82c06d59   53,548 / 55,285   a fault owns the charge it cut (G373)
--     0632  20261009101743   5:17 AM CT   a552ea72   62,694 / 64,675   the charge clock reads the air (G374)
--     0633  20261009102050   5:20 AM CT   46c9cab2   41,773 / 43,861   the arrival spread by horizon (G371)
--     0634  20261009102518   5:25 AM CT   ec9a0802   32,607 / 34,111   a drain timed from a dispatch seen (G376)
--     0635  20261009103141   5:31 AM CT   4cb35858   54,659 / 56,771   the futures take chargers down (G364)
--     0636  20261009103417   5:34 AM CT   a9ce33c9   38,406 / 40,220   the clock's spread by kind and length (G362)
--     0637  20261009103821   5:38 AM CT   caf12447   17,787 / 19,299   the latest usable return model (G377)
--     0638  20261009104044   5:40 AM CT   cec36bbf   31,416 / 33,146   the self-review remembers (G369, G375)
--     0639  20261009104324   5:43 AM CT   fab61d96   37,558 / 39,188   the futures hold the calendar's chargers (G380)
--     0640  20261009104502   5:45 AM CT   517c7f7b   13,822 / 14,872   the agent sees the holds (G381)
--     0641  20261009104632   5:46 AM CT   b6faa416   15,245 / 16,301   the agent sees the kernel's plan (G382)
--
--   Two applies did not go at the first send, and neither changed anything it should not have. 0635's first send at
--   5:28 AM CT met a sweep arm and its P0 refused it; nothing was applied, and the resend at 5:31 went through between
--   arms. 0636 outlived the connector's 60-second client timeout (it refits the charge clock twice and once more out of
--   sample); the server kept going and committed at about 5:36 AM CT, read back from schema_migrations and the lineage
--   before anything else was sent.
--
-- ══ §2 WHAT THE REFITS READ (reproduce: (2)) ══
--
--   return_v1 estimate 12 (0634): usable, forecast_v 2; the depot's drain 0.7269%/min (log spread 0.0662) from 1,141
--     timed reserve returns, 376 left out because their dispatch began before their run did; other calls home 0.1103
--     an hour of work; Zoox 0.6533, Waymo 0.7269, Tesla 0.7592. Its arrival spread is 0633's (floor 0.2492, walk
--     0.00471, drift 0.0010664, 9 bins, 100 returns, 3,658 forecasts, 133 orders, 1 run) until orders made at forecast 2
--     are graded.
--   charge_fault_v1 fit 1 (0635): fast chargers 0.1165 faults an hour of charging (179 faults, 87 repairs; repair median
--     30 minutes, p90 175.4, longest 626), L2 0.0422 (210, 100; 57, 348.2, 714), 44 fine-tick runs.
--   charge_time_v2 fit 5 (0636): the spread is scaled x1.2828 on fast chargers (1.4109, 1.2888, 1.3906, 1.2926 by length,
--     on 122, 121, 65 and 363 charges) and x1.0009 on L2 (1.0903, 1.0121, 0.9046, 0.8569 on 866, 325, 543 and 228);
--     inside the 80% band on the fit's own charges, fast 68.3% -> 79.9% (671 in 16 runs), L2 79.7% -> 80.0% (1,962 in
--     36). In sample: the audit grades it on the charges that come after the fit once there are 30.
--   The nightly jobs refit all three at 11:20-11:24 UTC (6:20-6:24 AM CT) every day from now; 0635 added the third.
--
-- ══ §3 THE CALENDAR'S HOLDS IN THE CHECK'S OWN REPLAY (G380, 0639; reproduce: (3)) ══
--
--   The replay is the check's simulator given everything that really happened after an order (arrivals, cars that
--   appeared, charge times, charges under way, faults), so what it still gets wrong is what the simulator does not
--   model. b2efcc07's graded orders whose window ran to its end:
--
--                                     orders   mean miss, min    cars at the depot   cars coming home   compared   missed   invented
--     all 87, without the holds          87        12.19          16.69 (bias -9.41)        6.99            2,093      451       576
--     all 87, with them                  87         7.34           8.35 (bias -6.70)        5.95            2,297      247       403
--     latest 40, without                 40        11.97          18.09                     4.35              696      197       213
--     latest 40, with                    40         3.31           3.85                     2.39              842       51        72
--
--   The 87 read exactly what 0639 §1(c) rehearsed on temporary copies before it was written (the same seven figures,
--   1,913 holds read and 463 on cars the futures do not model), so the live functions are the rehearsed ones. The
--   later orders gain more because the calendar is fuller later in a busy day: 1,148 holds read over the latest 40
--   orders against 1,913 over all 87.
--
-- ══ §4 WHAT IS LEFT, AND A FINDING ABOUT THE KERNEL (G384; reproduce: (4), (5)) ══
--
--   With the holds, by how each car's plug-in compares (all 87 orders):
--
--                         compared on the same kind    on the other kind          missed   invented
--     cars at the depot   1,088, 6.62 min (bias -4.96)  236, 16.33 min (-14.74)       40       324
--     cars coming home      710, 3.28 min (-1.04)       263, 13.16 min (+6.78)       207        79
--
--   (a) The kind of charger. The 499 plug-ins the replay puts on the other kind are 22% of those compared and 43% of the
--       summed miss (7,315 of 16,849 minutes); 120 of the 236 at the depot are cars at 80% or more. The kernel's own
--       stall pick, beyond the kind, is the next thing the simulator should copy.
--   (b) The 324 invented plug-ins at the depot are mostly seven cars. 261 are cars under 45% whom the replay seats about
--       75 minutes into the window and who in reality did not plug in inside it: six cars on temp holds and one on a
--       perimeter hold, with no charge booking. They were at the gate when the run began and waited: Zoox-002 (33%)
--       from 13:00 to 16:14, Zoox-003 to 16:21, Waymo-AV-028 to 16:23, Waymo-AV-003 to 15:28, Zoox-AV-089 to 15:30, and
--       Tesla-AV-060 and Tesla-RT-002 never plugged in before the run stopped at 17:00. Over all 13 boot cars under 45%:
--       a mean 98.4 minutes from the gate to a charger (median 88.3, the longest 203), 5 over an hour, 3 never seated.
--   (c) Why. Zoox-002 stood 11th to 25th in a line of 18 to 33 cars for its first 50 minutes with at most two chargers
--       free at a time. The kernel ranks the line by wait over charge still owed, so a car that owes a lot rises
--       slowly. The fairness floor that exists (agent_charge_order_pin_wait_min, 90 minutes) applies only while an
--       agent's order is in force, and 127 of the run's 136 orders were the kernel's own. The check that takes an
--       agent's order cannot reward a fairer one either: after on-time readiness and lateness it ranks futures by the
--       summed minutes in the depot, which shortest-first minimises. Rule 9 allows queueing; it names better ordering
--       of who is served next as the answer to site pressure, and this is the ordering failing a 33% car for three
--       hours. Filed as G384: a fairness floor in the kernel's own order, and a contract-wait term in the check.
--   (d) The waits of cars that returned during the run are not banded by battery here: the battery on the state
--       event before a car reaches the gate is stale (it can be its battery at dispatch). Seated returning cars waited a
--       median 11.7 minutes, a mean 38.3, 15 of them over an hour.
--
-- ══ §5 AGENT v27 ══
--
--   ottoq-orchestrator-agent v39, deployed 2026-10-09 10:52 UTC (5:52 AM CT) through the MCP connector, verify_jwt true,
--   read back with get_edge_function: all five files byte-identical to the repo (index.ts c5c5abf1,
--   _shared/agent_charge_order.ts 0504f0c4, and the unchanged agent_model_call 222f9136, agent_solver_chain 7fae9d72,
--   agent_dial_discipline e4944c72; sha256 prefixes). v38 was byte-identical to its manifest entry when read back
--   first. Edge-functions manifest footnote 8.
--
-- ══ §6 NEXT ══
--
--   The armed busy_day run on b2efcc07's seed, through the operator's start door (which purges nothing), to read the new
--   stack on a live line: the holds and the faults in the futures, the spread, the drain, and the agent reading the
--   kernel's plan. Then G384.

-- (1) the applies, as stored
SELECT s.version, s.name, md5(s.statements[1]) AS stmt_md5, length(s.statements[1]) AS chars, octet_length(s.statements[1]) AS bytes,
       l.classified_at AS lineage
  FROM supabase_migrations.schema_migrations s
  LEFT JOIN public.ottoq_cert_lineage l ON l.name LIKE '06%' AND l.name LIKE '%' || s.name
 WHERE s.version BETWEEN '20261009100000' AND '20261009105959' ORDER BY s.version;

-- (2) the three learned models as the check reads them
SELECT public.ottoq_return_model('11111111-1111-1111-1111-111111111111') #> '{params}' - 'drain_by' - 'dwell' AS return_v1,
       public.ottoq_charge_fault_model('11111111-1111-1111-1111-111111111111') AS faults,
       public.ottoq_charge_clock_model('11111111-1111-1111-1111-111111111111') #> '{params,spread}' AS clock_spread;

-- (3) the replay with and without the calendar's holds (drop the LIMIT for all 87)
WITH run AS (SELECT sim_run_id AS run FROM public.ottoq_sim_runs WHERE sim_run_id = 'b2efcc07-e47e-40e2-9411-907e913a3976'),
ord AS (
  SELECT s.order_id, s.sim_clock, s.state, s.seed, s.agent_order, h.taken, h.realized
    FROM public.ottoq_charge_order_grades h JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id, run
   WHERE h.sim_run_id = run.run AND h.observed_min >= h.window_min - 1
   ORDER BY h.order_id DESC LIMIT 40
), rep AS (
  SELECT o.order_id, o.realized,
         public.ottoq_charge_line_schedule(f.full - 'holds', CASE WHEN o.taken THEN o.agent_order END, 0, o.seed, true) AS r0,
         public.ottoq_charge_line_schedule((f.full - 'holds') || jsonb_build_object('holds', public.ottoq_charge_line_holds(run.run, o.sim_clock, 480)),
                                           CASE WHEN o.taken THEN o.agent_order END, 0, o.seed, true) AS r1
    FROM ord o CROSS JOIN run
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_line_realize(o.state, o.realized,
                                 ARRAY['arrivals', 'appeared', 'charge_times', 'running', 'faults']) AS full) f
), act AS (
  SELECT r.order_id, c.key AS id, (c.value ->> 's0')::numeric AS s0, (r.realized ->> 'observed_min')::numeric AS w, 'depot' AS src
    FROM rep r, jsonb_each(COALESCE(r.realized -> 'cars', '{}'::jsonb)) c
  UNION ALL
  SELECT r.order_id, c.key, (c.value ->> 's0')::numeric, (r.realized ->> 'observed_min')::numeric, 'inbound'
    FROM rep r, jsonb_each(COALESCE(r.realized -> 'inbound', '{}'::jsonb)) c WHERE COALESCE((c.value ->> 'arrived')::boolean, false)
  UNION ALL
  SELECT r.order_id, x.value ->> 'id', (x.value ->> 's0')::numeric, (r.realized ->> 'observed_min')::numeric, 'inbound'
    FROM rep r, jsonb_array_elements(COALESCE(r.realized -> 'appeared', '[]'::jsonb)) x WHERE x.value ->> 'how' = 'returned'
), j AS (
  SELECT a.src, a.s0 AS act,
         (SELECT CASE WHEN (y.value ->> 's0')::numeric < a.w THEN (y.value ->> 's0')::numeric END
            FROM rep r, jsonb_array_elements(r.r0 -> 'seats') y WHERE r.order_id = a.order_id AND y.value ->> 'id' = a.id LIMIT 1) AS p0,
         (SELECT CASE WHEN (y.value ->> 's0')::numeric < a.w THEN (y.value ->> 's0')::numeric END
            FROM rep r, jsonb_array_elements(r.r1 -> 'seats') y WHERE r.order_id = a.order_id AND y.value ->> 'id' = a.id LIMIT 1) AS p1
    FROM act a
)
SELECT (SELECT count(*) FROM rep) AS orders,
       round(avg(abs(p0 - act)) FILTER (WHERE act IS NOT NULL AND p0 IS NOT NULL), 2) AS miss_without,
       round(avg(abs(p1 - act)) FILTER (WHERE act IS NOT NULL AND p1 IS NOT NULL), 2) AS miss_with,
       round(avg(abs(p0 - act)) FILTER (WHERE src = 'depot' AND act IS NOT NULL AND p0 IS NOT NULL), 2) AS depot_without,
       round(avg(abs(p1 - act)) FILTER (WHERE src = 'depot' AND act IS NOT NULL AND p1 IS NOT NULL), 2) AS depot_with,
       round(avg(abs(p0 - act)) FILTER (WHERE src = 'inbound' AND act IS NOT NULL AND p0 IS NOT NULL), 2) AS home_without,
       round(avg(abs(p1 - act)) FILTER (WHERE src = 'inbound' AND act IS NOT NULL AND p1 IS NOT NULL), 2) AS home_with,
       count(*) FILTER (WHERE act IS NOT NULL AND p0 IS NOT NULL) AS compared_without, count(*) FILTER (WHERE act IS NOT NULL AND p1 IS NOT NULL) AS compared_with,
       count(*) FILTER (WHERE act IS NOT NULL AND p0 IS NULL) AS missed_without, count(*) FILTER (WHERE act IS NOT NULL AND p1 IS NULL) AS missed_with,
       count(*) FILTER (WHERE act IS NULL AND p0 IS NOT NULL) AS invented_without, count(*) FILTER (WHERE act IS NULL AND p1 IS NOT NULL) AS invented_with,
       (SELECT sum((r1 ->> 'holds')::int) FROM rep) AS holds, (SELECT sum((r1 ->> 'holds_unmodelled')::int) FROM rep) AS holds_unmodelled
  FROM j;

-- (4) what is left with the holds: same kind, other kind, missed, invented (the replay of (3) for all 87, with the
--     state's battery and immediate flag per car; see §4)
--     (as (3) without the LIMIT, then:)
--     SELECT src, CASE WHEN act IS NULL THEN 'invented' WHEN p1 IS NULL THEN 'missed' WHEN pk = k0 THEN 'same_kind'
--                      ELSE 'other_kind' END AS cls, count(*), round(avg(abs(p1 - act)), 2), round(avg(p1 - act), 2) ...

-- (5) the gate cars: from arriving at the gate to a charger, by battery, boot cars apart (§4(b))
WITH ev AS (
  SELECT e.entity_id AS v, e.sim_clock_at AS t,
         COALESCE(e.payload #>> '{diff,current_state,new}', e.payload #>> '{diff,current_state,to}', e.payload #>> '{new_state,current_state}') AS st,
         COALESCE((e.payload #>> '{diff,current_soc,new}')::numeric, (e.payload #>> '{diff,current_soc,to}')::numeric,
                  (e.payload #>> '{new_state,current_soc}')::numeric) AS soc
    FROM public.ottoq_events e
   WHERE e.sim_run_id = 'b2efcc07-e47e-40e2-9411-907e913a3976' AND e.event_type = 'vehicle.state_changed'
     AND e.payload::text LIKE '%current_state%'
), arr AS (
  SELECT ev.v, ev.t AS t_arr,
         (SELECT min(e2.t) FROM ev e2 WHERE e2.v = ev.v AND e2.t > ev.t AND e2.st IN ('charging_dcfc', 'charging_l2')) AS t_seat,
         (SELECT min(e2.t) FROM ev e2 WHERE e2.v = ev.v AND e2.t > ev.t AND e2.st = 'arrived_at_gate') AS t_next,
         (SELECT x.soc FROM ev x WHERE x.v = ev.v AND x.t <= ev.t AND x.soc IS NOT NULL ORDER BY x.t DESC LIMIT 1) AS soc
    FROM ev WHERE ev.st = 'arrived_at_gate'
)
SELECT CASE WHEN t_arr < '2026-10-08 13:01+00' THEN 'boot' ELSE 'returned' END AS who,
       CASE WHEN soc < 45 THEN 'under 45' WHEN soc < 80 THEN '45-80' ELSE '80 and over' END AS battery,
       count(*) AS arrivals,
       count(*) FILTER (WHERE t_seat IS NOT NULL AND (t_next IS NULL OR t_seat < t_next)) AS seated,
       round(avg(extract(epoch FROM t_seat - t_arr) / 60.0) FILTER (WHERE t_next IS NULL OR t_seat < t_next), 1) AS mean_wait_min,
       round(max(extract(epoch FROM t_seat - t_arr) / 60.0) FILTER (WHERE t_next IS NULL OR t_seat < t_next), 0) AS max_wait_min
  FROM arr GROUP BY 1, 2 ORDER BY 1, 2;
