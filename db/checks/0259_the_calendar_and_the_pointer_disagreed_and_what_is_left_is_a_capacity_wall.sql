-- 0259  THE CALENDAR AND THE RESERVATION POINTER DISAGREED ABOUT THE SAME STALL,
--       AND WHAT IS LEFT AFTER FIXING THAT IS A CAPACITY WALL, NOT A DEFECT.
--
-- Read-only. The before-picture for migration 0369 (G84), the reservation census
-- that frames it, and the state of the intelligence layer re-derived per CLAUDE.md
-- rule 6. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), live
-- run `5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10` (busy_day, seed 777777, speed 8.0).
--
-- Third of three. 0367 put the reservation reclaimer on the path the live engine
-- actually calls (G82). 0368 stopped the reroute searching the scarcest stall type
-- for vehicles that wanted the most plentiful one (G83). Only with both of those
-- in place did the remaining refusals become legible, and what they said is here.
--
-- ══ 1. THE ESCALATION THAT FINALLY NAMED ITS OWN CAUSE ══════════════════════
--
-- 0368 added `wanted_stall_type`, `stall_type_source` and `candidates_seen` to
-- every `no_capacity` escalation. Read immediately afterwards on this run:
--
--   escalated no_capacity | wanted dcfc | source payload | candidates_seen 2 | x3
--   escalated no_capacity | wanted l2   | source payload | candidates_seen 4 | x2
--   escalated no_capacity | wanted l2   | source payload | candidates_seen 2 | x1
--
-- `candidates_seen` is the number of stalls the walk examined -- stalls
-- `ottoq_stall_free_between` returned, so CALENDAR-FREE -- and on which
-- `ottoq_reserve_stall` then refused. Two to four legal moves per escalation,
-- refused by the pointer, with the calendar saying yes.
--
-- The reactor's own comment has always said the pointer is "the scarcer gate". The
-- size of the gap had never been counted. Q1 counts it.

WITH r AS (
  SELECT sim_run_id, COALESCE(sim_clock_current, sim_clock_start) AS clk
    FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND status = 'running'
   ORDER BY started_at DESC LIMIT 1
)
SELECT z.stall_type,
       count(*)                                             AS reserved_empty_unexpired,
       count(*) FILTER (WHERE z.holder_elsewhere)            AS holder_in_another_stall,
       --: THE RELEASABLE CLASS. The holder cannot occupy two stalls at once and
       --: the calendar records no intent for this one.
       count(*) FILTER (WHERE z.holder_elsewhere AND NOT z.calendar_backed)
                                                            AS unbacked_orphan,
       --: AND THE CLASS THAT MUST SURVIVE. Charge now, staging place when done, is
       --: a real forward plan. Releasing on holder_elsewhere alone destroys these.
       count(*) FILTER (WHERE z.holder_elsewhere AND z.calendar_backed)
                                                            AS calendar_backed_plan
  FROM (
    SELECT s.stall_type::text AS stall_type,
           EXISTS (SELECT 1 FROM public.stalls s_in
                    WHERE s_in.current_vehicle_id = s.reserved_by
                      AND s_in.id <> s.id)                              AS holder_elsewhere,
           EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                    WHERE b.sim_run_id = (SELECT sim_run_id FROM r)
                      AND b.stall_id   = s.id
                      AND b.vehicle_id = s.reserved_by
                      AND b.state IN ('held','active'))                 AS calendar_backed
      FROM public.stalls s
     WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
       AND s.reserved_by IS NOT NULL
       AND s.current_vehicle_id IS NULL
       AND s.reservation_expires_at >= (SELECT clk FROM r)) z
 GROUP BY z.stall_type
 ORDER BY z.stall_type;

-- Measured at 38 sim-minutes, before 0369:
--
--   l2        4 reserved-empty unexpired,  3 holder-elsewhere,  1 unbacked, 2 backed
--   staging  46 reserved-empty unexpired, 33 holder-elsewhere, 20 unbacked, 13 backed
--   ------------------------------------------------------------------------
--   total    50                            36                  21         15
--
-- And after 0369, on the same query, same run, one tick later -- which is the
-- shape a correct fix makes rather than a smaller total:
--
--   dcfc      1 reserved-empty unexpired,  1 holder-elsewhere,  0 unbacked, 1 backed
--   l2        6 reserved-empty unexpired,  4 holder-elsewhere,  0 unbacked, 4 backed
--   staging  14 reserved-empty unexpired,  1 holder-elsewhere,  0 unbacked, 1 backed
--   ------------------------------------------------------------------------
--   total    21                            6                   0          6
--
-- **`unbacked_orphan` is 0 in every stall type, and all six calendar-backed plans
-- survive untouched.** The class the reclaimer was given is empty because it is
-- being reclaimed each tick; the class it must never touch is intact. Those two
-- facts together are the fix -- either one alone would be consistent with a bug.
--
-- **Releasing on "the holder is elsewhere" alone would have destroyed fifteen
-- legitimate forward plans.** That is why 0369 is a separate migration with the
-- booking test at its centre rather than a wider predicate bolted onto 0367, and
-- why its P9 refuses to ship without `b.state IN ('held','active')` in the body.
--
-- The hierarchy this encodes, stated because it is a design decision and not an
-- implementation detail: **the calendar is the authority on intent; the
-- reservation pointer is a lock.** A lock with no intent behind it is garbage. A
-- lock with intent behind it is untouchable. That is CLAUDE.md rule 6's
-- "assignment plus verification" pair read in the direction nobody had read it.
--
-- ══ 2. THE CENSUS, AND THE WALL IT SHOWS ════════════════════════════════════
--
-- Before 0369, at 38 sim-minutes:
--
--   type          total  reserved  occupied  reserved-empty   TTL range
--   dcfc             10        10         8               2   1h flat
--   l2               30        27        24               3   40m - 1h
--   staging         113       101        60              41   30m - 7h14m
--   service_bay       2         2         2               0   15m
--   wash_bay          3         0         0               0   --
--
-- One tick after 0369: staging reserved 101 -> 88, unclaimed staging 12 -> 25,
-- total unclaimed stalls across the depot ~7 -> 32.
--
-- WHAT REMAINS IS NOT A DEFECT. All 10 DCFC stalls claimed with 8 physically
-- occupied; 28 of 30 L2 claimed with 25 occupied. **Thirty-three of forty charge
-- stalls hold a vehicle.** That is a capacity wall, it is the correct answer to
-- Chase's actual question -- how many vehicles this depot can stage, sort and
-- orchestrate at once -- and it is a number rather than a bug. It also agrees with
-- `0250`, which retracted a "no capacity wall" conclusion drawn from an unscoped
-- census; this one carries the depot predicate rule 8 requires.
--
-- TWO THINGS IN THAT TABLE THAT ARE NOT YET EXPLAINED, and are named rather than
-- theorised:
--   (a) staging reservation TTLs reach **7h14m** while the stall stands empty. For
--       an overnight L2 plan that may be correct; nothing establishes that here.
--       13 stalls carried an expiry more than four hours out.
--   (b) **wash_bay: 3 stalls, 0 reserved, 0 occupied.** `exterior_wash` is the one
--       code that `service_cadence_policy` and `service_definitions` share
--       (`0178`), so the service is declared in both catalogues and the bays did
--       nothing for the first 38 sim-minutes of a busy_day run. Needs its own
--       check before anything is concluded -- a wash cadence measured in days
--       would explain it completely.

SELECT s.stall_type::text AS stall_type,
       count(*)                                                        AS total,
       count(*) FILTER (WHERE s.reserved_by IS NOT NULL)               AS reserved,
       count(*) FILTER (WHERE s.current_vehicle_id IS NOT NULL)        AS occupied,
       count(*) FILTER (WHERE s.reserved_by IS NOT NULL
                          AND s.current_vehicle_id IS NULL)            AS reserved_empty,
       count(*) FILTER (WHERE s.reserved_by IS NULL
                          AND s.current_vehicle_id IS NULL
                          AND s.status = 'available')                  AS unclaimed,
       min(s.reservation_expires_at - s.reserved_at)                   AS min_ttl,
       max(s.reservation_expires_at - s.reserved_at)                   AS max_ttl
  FROM public.stalls s
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY 1 ORDER BY 1;

-- ══ 3. WHAT THE THREE MIGRATIONS DID TO THE LOOP ════════════════════════════
--
-- Baseline, run `3fb415d8`, whole life, none of the three live:
--   393 escalations / 1,245 ticks = **0.316 per tick**
--
-- Run `5b37ee46`, the four sampler readings after all three were live
-- (0367 from tick 1, 0368 at ~tick 80, 0369 at ~tick 190):
--
--   04:15:05  tick 134  esc 43  unclaimed 16/1   rerouted 5
--   04:16:06  tick 155  esc 44  unclaimed 29/2   rerouted 5
--   04:17:06  tick 176  esc 45  unclaimed 32/4   rerouted 6
--   04:18:07  tick 197  esc 49  unclaimed 46/4   rerouted 6
--
--   marginal rate over that window: (49-43)/(197-134) = **0.095 per tick**
--   `reservation_reclaim_blocked` events: **0** throughout -- no deadlock, no silence
--   release-eligible reservations: **0-1** throughout -- the reclaimer keeps up
--
-- READ THAT AS A WINDOW, NOT A VERDICT. 0.095 against 0.316 is a 3.3x reduction on
-- 63 ticks of one run, and the cumulative figure for this run (49/197 = 0.249)
-- still carries its own pre-0368 early phase. The claim this file supports is
-- "the marginal rate fell sharply and the unclaimed pool is growing", not a
-- headline multiple. Q3 is the comparison to re-run at completion.

SELECT r.sim_run_id, r.status, r.tick_count,
       round(EXTRACT(epoch FROM (r.sim_clock_current - r.sim_clock_start))/60.0, 1) AS sim_minutes,
       (SELECT count(*) FROM public.ottoq_events e
         WHERE e.sim_run_id = r.sim_run_id
           AND e.event_type = 'ottoq.refusal_escalated')                            AS escalations,
       round((SELECT count(*) FROM public.ottoq_events e
               WHERE e.sim_run_id = r.sim_run_id
                 AND e.event_type = 'ottoq.refusal_escalated')::numeric
             / NULLIF(r.tick_count, 0), 4)                                          AS per_tick,
       (SELECT count(*) FROM public.ottoq_events e
         WHERE e.sim_run_id = r.sim_run_id
           AND e.event_type = 'ottoq.reservation_reclaim_blocked')                   AS reclaim_blocked
  FROM public.ottoq_sim_runs r
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
 ORDER BY r.started_at DESC LIMIT 4;

-- ══ 4. THE INTELLIGENCE LAYER, RE-DERIVED (CLAUDE.md rule 6) ════════════════
--
-- Never quoted from a previous file. Read from `ottoq_intelligence_ledger` at
-- 2026-09-20 04:19 UTC:
--
--   nvidia_cuopt     865 calls, 865 reaching NVIDIA (all 2xx), 851 answered,
--                    14 abstained, **3,889 proposals**, avg 2,783 ms,
--                    last call 2026-09-20 04:09:04
--   nvidia_nemotron  2,446 calls, 2,445 answered, **0 proposals** (by design --
--                    the agent emits an objective directive, never an assignment),
--                    avg **23,130 ms**, max **180,743 ms**,
--                    **629 of 2,446 calls (26%) longer than one 30-second tick**,
--                    **agent_calls_with_no_l1_rules = 2,446 of 2,446**,
--                    last call 2026-09-20 04:19:21
--   cpsat_service    49 calls, 41 enacted, 8 deferred_site_power_cap,
--                    avg 23 ms, max 42 ms, last call 2026-09-20 02:45:00
--
-- THREE THINGS THAT FOLLOW, AND ONE THAT DOES NOT.
--
-- (a) G62 STANDS AND THE COUNT HAS GROWN. 26% of agent calls exceed the beat they
--     are supposed to advise, and the mean latency is within a second of a whole
--     tick. An advisory agent cannot be a synchronous dependency of a 30-second
--     tick. Unchanged conclusion, larger sample.
--
-- (b) `agent_calls_with_no_l1_rules` IS STILL 100%, now 2,446 of 2,446. The one
--     path where an AI influences engine state remains the one path the L1 shield
--     does not gate. Countable only because 0340's ledger survives its run.
--
-- (c) CP-SAT IS THE FASTEST THING IN THIS TABLE BY THREE ORDERS OF MAGNITUDE --
--     23 ms mean against cuOpt's 2,783 and Nemotron's 23,130 -- and it has not
--     been called since 02:45 because its host is not running. 41 of 49 calls
--     enacted. That is the whole argument for the always-on container, in one row.
--
-- (d) WHAT DOES NOT FOLLOW: that cuOpt "went dark" after 04:09. Measured in the
--     gate log over the following ten minutes: `delegated_to_agent_chain` **116**,
--     `sql_gate_no_candidates` **33**, `first_refusal_arm` **29**,
--     `no_free_stalls_demand_present` **7**. The SQL gate stood down because the
--     edge agent chain owns the call under `edge:v26-agent-chain`, and demand was
--     low. A quiet proposer here is a gate decision, not an outage -- which is
--     exactly the distinction rule 6 exists to force, in both directions.

SELECT provider, role, calls, provider_status_2xx, answered, abstained, proposals,
       agent_calls_with_no_l1_rules, avg_latency_ms, max_latency_ms,
       calls_over_one_tick, last_call::text
  FROM public.ottoq_intelligence_ledger
 ORDER BY provider;

SELECT abstained_reason, count(*) AS n, max(called_at)::text AS last_seen
  FROM public.cuopt_invocation_log
 WHERE called_at > now() - interval '15 minutes'
 GROUP BY 1 ORDER BY 2 DESC;
