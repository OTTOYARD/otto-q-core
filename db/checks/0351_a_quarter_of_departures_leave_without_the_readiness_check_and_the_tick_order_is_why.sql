-- 0351  **A quarter of the vehicles that leave the depot after a visit leave without their readiness
--       check — 24 of 93 on run `0682752c`, 26 of 106 on run `6a8a7029` — and it is not a rule, a
--       threshold or a bad input. It is the ORDER of three steps inside one tick.**
--
--       `readiness_check` is the one atom `ottoq.ottoq_derive_visit_needs` writes on every visit:
--       `must_do=true`, `deferrable=false`, `est_min=3`, `concurrency='gate'`, `predecessors=['*']` —
--       "confirms the vehicle is fit to leave". It is completed in exactly one place,
--       `twin.ottoq_sim_advance_visit_atoms`, and only while the vehicle is `staged_for_departure`.
--       The dispatcher (`ottoq.ottoq_plan_dispatch_tick`, phase `deploy_plan`) holds a vehicle that owes
--       any must-do atom **except** `readiness_check`, because that one is expected to happen in the
--       departure lane. And inside `twin.ottoq_world_advance` the visit-atom step runs **first** (call 1
--       of 27), service flow stages the vehicle at call 15, and dispatch runs **last** (call 27). So a
--       vehicle whose last service finishes this tick is staged and deployed before the one step that
--       performs its check has seen it staged. **All 23 staged departures without a check on `0682752c`
--       spent 0 ticks in `staged_for_departure`; the 69 that got theirs spent a mean of 1.06.**
--
--       Everything else on a departing visit was done first — 90/90 inspections, 58/58 charges, 13/13
--       washes. The check is the only must-do the dispatcher lets a vehicle leave without, and it is the
--       one whose whole purpose is to be the last word before it does.
--
--       Measured 2026-09-22 22:30–22:55 UTC (5:30–5:55 PM CT), twin depot `11111111-…` only, nothing in
--       flight. Runs: `0682752c-7082-4ece-97df-152a67f463f0` (busy_day, seed 1838167747826776069,
--       1,099 ticks) and `6a8a7029-e7c4-4521-a4f5-606e48e2a465` (busy_day, seed 920348, 1,142 ticks),
--       both engine-class and measured before any later run purged them. Fixed by `0431`.
--
-- ══ §0 HOW THIS WAS FOUND ════════════════════════════════════════════════════
--
-- Reading the orchestrator agent's own rationale on `0682752c`. It asked to cut `deploy_peak_fraction`
-- to 0.35–0.45 on 96 of its 106 writes to that dial — every one clamped to the 0.5 floor — citing
-- *"31 staged vehicles blocked by 169 pending service atoms (43 charge, 73 readiness…)"*. The agent's
-- lever was wrong (it was asking to hold vehicles back) and its count was inflated (§4), but it was
-- pointing at the departure lane, and the departure lane is where this is.
--
-- ══ §1 THE RATE, ON BOTH RUNS THAT SURVIVE ═════════════════════════════════
--
-- A post-visit departure is a dispatch preceded by a visit of that vehicle in the same run; its visit is
-- the latest one that arrived at or before the dispatch (both columns are SIM clock — checked, §5).

\echo '=== 0351 §1 — post-visit departures, and how many left without a done readiness check ==='
SELECT d.sim_run_id, count(*) AS post_visit_departures,
       count(*) FILTER (WHERE NOT (r.status = 'done' AND r.done_at <= d.dispatched_at)) AS without_readiness_check,
       round(100.0 * count(*) FILTER (WHERE NOT (r.status = 'done' AND r.done_at <= d.dispatched_at))
             / nullif(count(*), 0), 1) AS pct
  FROM public.ottoq_vehicle_dispatches d
  JOIN LATERAL (SELECT vn.visit_id, vn.atoms FROM public.ottoq_visit_needs vn
                 WHERE vn.vehicle_id = d.vehicle_id AND vn.sim_run_id = d.sim_run_id
                   AND vn.arrived_at <= d.dispatched_at
                 ORDER BY vn.arrived_at DESC LIMIT 1) vv ON true
  JOIN LATERAL (SELECT COALESCE(a->>'status','pending') AS status, (a->>'done_at')::timestamptz AS done_at
                  FROM jsonb_array_elements(vv.atoms) a WHERE a->>'svc' = 'readiness_check' LIMIT 1) r ON true
 GROUP BY 1 ORDER BY 2 DESC;
-- 6a8a7029  106  26  24.5
-- 0682752c   93  24  25.8

-- ══ §2 EVERY OTHER MUST-DO WAS DONE FIRST ═══════════════════════════════════
--
-- Completion is read in each writer's own vocabulary: most atoms write `done_at`, the charge closer writes
-- `status='done'` + `closed_at` and no `done_at`. **A first pass of this section read `done_at` alone and
-- reported 44 departures "with an open must-do charge"; every one of those vehicles left at or above its
-- target SoC (min 90%) and every one of those atoms reads `status='done'`. That was my query, not the
-- engine** — recorded so the next reader does not repeat it.

\echo '=== 0351 §2 — must-do atoms on departing visits, by service (run 0682752c) ==='
WITH disp AS (SELECT d.dispatch_id, d.vehicle_id, d.dispatched_at FROM public.ottoq_vehicle_dispatches d
               WHERE d.sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0'),
paired AS (SELECT d.*, vv.atoms FROM disp d
             JOIN LATERAL (SELECT vn.atoms FROM public.ottoq_visit_needs vn
                            WHERE vn.vehicle_id = d.vehicle_id AND vn.sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0'
                              AND vn.depot_id = '11111111-1111-1111-1111-111111111111'
                              AND vn.arrived_at <= d.dispatched_at
                            ORDER BY vn.arrived_at DESC LIMIT 1) vv ON true),
atoms AS (SELECT p.dispatched_at, a->>'svc' AS svc, (a->>'must_do')::boolean AS must_do, a->>'status' AS status,
                 COALESCE((a->>'done_at')::timestamptz, (a->>'closed_at')::timestamptz) AS finished_at
            FROM paired p, jsonb_array_elements(p.atoms) a)
SELECT svc,
       count(*) FILTER (WHERE must_do) AS must_do_on_departing_visits,
       count(*) FILTER (WHERE must_do AND status = 'done' AND (finished_at IS NULL OR finished_at <= dispatched_at)) AS done_before_departure,
       count(*) FILTER (WHERE must_do AND COALESCE(status,'pending') NOT IN ('done','cancelled','skipped','waived')) AS never_done
  FROM atoms GROUP BY 1 HAVING count(*) FILTER (WHERE must_do) > 0 ORDER BY 2 DESC;
-- readiness_check      93  69  24   <-- the only one
-- interior_inspection  90  90   0
-- charge               58  58   0
-- interior_tidy        17  15   0   (2 cancelled)
-- exterior_wash        13  13   0
-- triage_check          9   9   0
-- item_retrieval        8   8   0
-- sensor_clean          6   5   0   (1 cancelled)
-- interior_deep_clean   3   3   0

-- ══ §3 THE MECHANISM: STAGED AND DEPLOYED IN THE SAME TICK ═════════════════
--
-- `vehicle_state_log.created_at` is WALL clock; a row written at wall w is placed at the sim clock and tick
-- of the newest tick whose `real_started_at <= w + 1s` (`0350` §1). Departure = `staged_for_departure ->
-- deployed` within 3 sim-minutes of `dispatched_at`; staging = the latest transition INTO
-- `staged_for_departure` before it.

\echo '=== 0351 §3 — ticks spent in staged_for_departure, by whether the check ran (run 0682752c) ==='
WITH ticks AS (SELECT real_started_at, sim_clock_after, tick_seq FROM public.ottoq_tick_clock_log
                WHERE sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0'),
disp AS (SELECT d.dispatch_id, d.vehicle_id, d.dispatched_at FROM public.ottoq_vehicle_dispatches d
          WHERE d.sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0'),
paired AS (
  SELECT d.*, EXISTS (SELECT 1 FROM jsonb_array_elements(vv.atoms) a
                       WHERE a->>'svc' = 'readiness_check' AND a ? 'done_at'
                         AND (a->>'done_at')::timestamptz <= d.dispatched_at) AS readiness_done
    FROM disp d JOIN LATERAL (SELECT vn.atoms FROM public.ottoq_visit_needs vn
                               WHERE vn.vehicle_id = d.vehicle_id AND vn.sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0'
                                 AND vn.depot_id = '11111111-1111-1111-1111-111111111111'
                                 AND vn.arrived_at <= d.dispatched_at
                               ORDER BY vn.arrived_at DESC LIMIT 1) vv ON true),
vsl AS (
  SELECT v.vehicle_id, v.previous_state::text AS prev, v.new_state::text AS nxt, v.created_at,
         (SELECT max(t.tick_seq) FROM ticks t WHERE t.real_started_at <= v.created_at + interval '1 second') AS tick,
         (SELECT max(t.sim_clock_after) FROM ticks t WHERE t.real_started_at <= v.created_at + interval '1 second') AS sim_at
    FROM public.vehicle_state_log v
   WHERE v.depot_id = '11111111-1111-1111-1111-111111111111'
     AND v.created_at >= '2026-09-22 19:40:39+00' AND v.created_at < '2026-09-22 21:40:00+00')
SELECT p.readiness_done, count(*) AS staged_departures,
       count(*) FILTER (WHERE dep.tick = stg.tick) AS staged_and_deployed_same_tick,
       round(avg(dep.tick - stg.tick), 2) AS mean_ticks_staged
  FROM paired p
  JOIN LATERAL (SELECT * FROM vsl WHERE vsl.vehicle_id = p.vehicle_id AND vsl.prev = 'staged_for_departure'
                   AND vsl.nxt = 'deployed'
                   AND vsl.sim_at BETWEEN p.dispatched_at - interval '3 minutes' AND p.dispatched_at + interval '3 minutes'
                 ORDER BY vsl.created_at LIMIT 1) dep ON true
  JOIN LATERAL (SELECT * FROM vsl WHERE vsl.vehicle_id = p.vehicle_id AND vsl.nxt = 'staged_for_departure'
                   AND vsl.created_at <= dep.created_at ORDER BY vsl.created_at DESC LIMIT 1) stg ON true
 GROUP BY 1 ORDER BY 1;
-- false  23  23  0.00    <-- every one staged and deployed inside one tick
-- true   69  10  1.06
-- The 24th departure without a check left from `staged_awaiting_service` (svc_step 'ready'), a
-- dispatcher candidate state in which the check can never run at all. 1 of 93; see §6.
--
-- The order, from the source (`twin.ottoq_world_advance`, calls in order, comment-stripped):
--    1  ottoq_sim_advance_visit_atoms      <- the ONLY place readiness_check is completed
--   15  ottoq_sim_advance_service_flow     <- stages the vehicle when its services are done
--   27  ottoq_sim_decide_and_dispatch      <- ... -> twin.ottoq_sim_auto_dispatch_tick
--                                             -> ottoq.ottoq_plan_dispatch_tick('deploy_plan')
-- and the dispatcher's hold, verbatim:
--    AND NOT EXISTS (... must_do = true AND a->>'svc' <> 'readiness_check'
--                        AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'))

-- ══ §4 WHAT THE AGENT WAS COUNTING ═════════════════════════════════════════
--
-- `ottoq_agent_board.needs.pending_atoms` counts every `status='pending'` atom on an open visit. Every
-- vehicle in the depot carries a pending `readiness_check` until the moment it leaves — the check is last
-- by design — so "73 readiness pending" is roughly "73 vehicles are still in the depot", not a backlog.
-- The board has no way to say which pending atoms are eligible to start and which are waiting their turn,
-- and it presents run-cumulative leg and deviation counters as if they were current state. Both are the
-- agent's inputs, and both are addressed separately from this file.

-- ══ §5 CLOCKS, CHECKED BEFORE ANY COMPARISON ═══════════════════════════════
--
--   ottoq_vehicle_dispatches.dispatched_at   12:01:58 -> 22:03:15   SIM (run sim clock 13:00 -> ~22:15)
--   ottoq_visit_needs.arrived_at             13:00:00 -> 22:03:52   SIM
--   atoms done_at / started_at               13:03:14 -> 22:11:58   SIM
--   ottoq_visit_needs.created_at             19:41:00 -> 20:48:35   WALL
-- The 12:01 dispatches are prime deployments with no prior visit; §1's LATERAL join excludes them.

-- ══ §6 WHAT FOLLOWS ═════════════════════════════════════════════════════════
--
--   1. **`0431`** makes the dispatcher hold a vehicle in `staged_for_departure` until its check is done.
--      The check completes at the start of the next tick, so the cost is exactly one tick of dwell for the
--      quarter of departures that were being staged and deployed at once, and nothing for the rest — they
--      already waited. It can never strand a vehicle: the hold's predicate is the completion loop's own
--      (`status='pending'`, visit `open`/`in_progress`, same depot), and that loop has no LIMIT.
--   2. **`staged_awaiting_service -> deployed`** (1 of 93) is left as a measured residual. Holding it would
--      need the check to run in that state too, which means enforcing `predecessors=['*']` for the first
--      time — no function reads `predecessors` today. Separate change, separate evidence.
--   3. **`public.ottoq_assert_departure_readiness(run)`** (`0431`) is §1 as a standing instrument: the
--      departures that left without a done check. Expected empty from the first run after `0431`.
