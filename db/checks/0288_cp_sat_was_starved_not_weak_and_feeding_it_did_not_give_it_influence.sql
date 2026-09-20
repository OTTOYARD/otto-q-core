-- 0288  CP-SAT WAS STARVED, NOT WEAK — PLANNING FIRES WENT FROM 3% TO 64% AND VEHICLES
--       PLANNED FROM 14 TO 383 WHEN THE MORNING RETURN WAVE ARRIVED. AND FEEDING IT DID
--       NOT GIVE IT INFLUENCE: **12 OF 610 PROPOSALS ENACTED, 2.0%**, BECAUSE THE LOCAL
--       DECIDE PATH DECIDES THE SAME VEHICLE WITHIN A TICK.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), completed run
-- `c8f678fb-a04a-4c18-a937-9b93673f3fe9` (busy_day, seed **100020**, 1,224 ticks, sim
-- 00:35 -> 09:37 CT, ended by `run_governor: reached the 540 sim-minute ceiling`). Everything
-- below is `class='engine'` and purges with the run; the fire log and disposition ledger are
-- the durable witnesses.
--
-- ══ 1. WHY THIS SEED, AND WHY THE CONTRAST IS WITHIN ONE RUN ════════════════
--
-- `0282` §3 measured CP-SAT idle on 82 of 93 fires because every serviceable vehicle was
-- already plugged in and `arrived_at_gate` was **zero for the entire window**. That was run
-- 1efeb1cd, seed 101959, whose sim start is 20:00 CT — and the governor's 540-sim-minute
-- ceiling means such a run **can never reach the 06:00 CT morning return wave**. The night
-- figures were therefore a measurement of a trough with no way to tell whether they were also
-- a ceiling.
--
-- Start time is a pure function of the seed:
--   `date_trunc('day', sim_clock_start) + make_interval(mins => abs(hashtext(seed::text)) % 1440)`
-- so a seed can be CHOSEN for its window. Seed **100020** gives offset 335 -> 05:35 UTC =
-- **00:35 CT**, and 00:35 + 540 min = **09:35 CT**. That single run therefore contains the
-- night tail AND the whole morning wave, which makes the comparison below a **within-run**
-- one: same seed, same engine, same descriptor logic, same proposer build. **The only thing
-- that differs between the two rows is how many vehicles wanted a stall.**
--
--   window                        fires  planning   vehicles   rows      planned/    serviceable
--                                        fires      planned    submitted planning fire  max
--   night tail  (00:35-06:00 CT)    258     8 (3.1%)      14        20      1.75         14
--   morning wave (06:00-09:37 CT)   106    68 (64.2%)   **383**  **590**  **5.63**     **60**
--
-- **Planning fires went from 3.1% to 64.2% and vehicles planned from 14 to 383 — a 27x
-- increase on 41% as many fires.** The arrival population at 04:59 CT read `arrived_at_gate`
-- **0** and `staged_awaiting_service` **1**; by 07:09 CT it read **5** and **19**. So
-- `0282`'s night figures were a trough, and the proposer does the work when there is work.

WITH t AS (
  SELECT f.tick_seq, f.status, f.n_planned, f.n_submitted,
         (f.fire->>'n_in_serviceable_state')::int AS serv,
         --: the fire log carries no sim_clock, so map each fire to the snapshot at or before
         --: its tick. 06:00 CT is 11:00 UTC.
         (SELECT s.sim_clock FROM public.ottoq_decision_snapshots s
           WHERE s.sim_run_id = f.sim_run_id AND s.tick_seq <= f.tick_seq
           ORDER BY s.tick_seq DESC LIMIT 1) AS sim_clock
    FROM public.ottoq_proposer_fire_log f
   WHERE f.sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9')
SELECT CASE WHEN sim_clock IS NULL THEN 'unmapped'
            WHEN sim_clock < '2026-09-20 11:00:00+00' THEN '1 night tail  (00:35-06:00 CT)'
            ELSE '2 morning wave (06:00-09:37 CT)' END AS window,
       count(*) AS fires,
       count(*) FILTER (WHERE status = 'submitted') AS planning_fires,
       sum(n_planned) AS vehicles_planned,
       sum(n_submitted) AS rows_submitted,
       round(sum(n_planned)::numeric
             / NULLIF(count(*) FILTER (WHERE status = 'submitted'), 0), 2) AS planned_per_planning_fire,
       max(serv) AS serviceable_max
  FROM t GROUP BY 1 ORDER BY 1;

-- ══ 2. AND THE BOTTLENECK MOVED RATHER THAN CLEARED ════════════════════════
--
-- Over the whole run, `forward_lex` submitted **610** proposals across **56** vehicles —
-- **10.89 per vehicle** — and the kernel enacted **12**:
--
--   superseded  entity_decided_by_other_proposal   **539   88.4%**
--   superseded  newer_proposal_same_entity            20    3.3%
--   refused     proposer_abstained                    20    3.3%
--   refused     stall_reserved                        16    2.6%
--   **enacted   enacted_by_kernel                     12    2.0%**
--   expired     run_finalized                          3    0.5%
--
-- **Who supersedes them is settled, not guessed.** The other external proposers put **9
-- rows total** on this run (`greedy_constrained` 4, `ottoq_service_priority` 5), so they
-- cannot account for 539 supersessions. Testing the local path directly: **538 of the 559
-- superseded rows (96.2%) have a local decide-path `stall_assignment` decision for the same
-- vehicle at the same tick or the next one.**
--
-- So the honest sentence, and it is the one to quote: **CP-SAT is no longer starved, it is
-- out-voted.** It is the declared rank-0 proposer in `ottoq_proposer_precedence` with
-- `holds_tick = true` and `greedy_yields = true`, it plans 383 vehicles in three sim-hours,
-- and 2% of that reaches the calendar. This is `db/checks/0184`'s tie-break finding
-- (*"a forward_lex row is heard but LOSES the tie-break to the local path's regenerated row
-- by created_at"*) and `0255`'s supersession dominance, both at volume for the first time.
--
-- **10.89 proposals per vehicle is the second half of the same mechanism.** A vehicle planned
-- at tick T is superseded, so it is no longer carrying a live `holds_tick` proposal, so
-- `vehicle_is_held` admits it again and the next fire re-plans it. That is G60/`0292`'s
-- churn — *"the proposer overwriting its own pending plans about a tick after making them"* —
-- except the overwriting is now mostly done TO it rather than BY it.

SELECT status, disposition_reason, count(*) AS n,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
  FROM public.ottoq_external_proposals
 WHERE sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9' AND source = 'forward_lex'
 GROUP BY 1, 2 ORDER BY n DESC;

WITH fl AS (
  SELECT entity_id::uuid AS vid, tick_seq, status
    FROM public.ottoq_external_proposals
   WHERE sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9' AND source = 'forward_lex')
SELECT count(*) AS proposals, count(DISTINCT vid) AS vehicles,
       round(count(*)::numeric / NULLIF(count(DISTINCT vid), 0), 2) AS proposals_per_vehicle,
       count(*) FILTER (WHERE status = 'superseded') AS superseded,
       count(*) FILTER (WHERE status = 'superseded' AND EXISTS (
         SELECT 1 FROM public.ottoq_decisions d
          WHERE d.sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9'
            AND d.entity_id = fl.vid AND d.action_context = 'stall_assignment'
            AND d.tick_seq BETWEEN fl.tick_seq AND fl.tick_seq + 1)) AS sup_with_local_decision,
       (SELECT count(*) FROM public.ottoq_external_proposals
         WHERE sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9'
           AND source <> 'forward_lex') AS all_other_proposer_rows
  FROM fl;

-- ══ 3. THE CAPACITY WALL, WHICH IS THE ANSWER CHASE ACTUALLY ASKED FOR ══════
--
-- Rule 8's stated goal is depth: prove OTTO-Q functions on this one depot, then find how many
-- vehicles it can stage, sort and orchestrate at once. **The morning wave is the first run
-- where the depot visibly fails to keep up**, and two KPIs say so:
--
--                                    night run 1efeb1cd    wave run c8f678fb
--   p95_time_to_service_min                   **2.7**            **39.6**
--   returns_unserved                            **0**              **11**
--   service_point_turns_per_point_per_day       2.48               3.56
--   asset_hours_available_per_day             102.51              57.89
--   peak_site_kw                                1309              572.5
--
-- **p95 time-to-service is 14.7x the night figure and eleven returns went unserved.** Those
-- are the numbers that answer the capacity question, and they only appear when the arrival
-- wave exists — which is exactly why every prior measurement of this depot looked comfortable.
-- Throughput rises (3.56 turns/point/day against 2.48) while readiness falls (57.89
-- asset-hours against 102.51) and the queue lengthens: the depot is working harder and still
-- losing ground.
--
-- **What this does NOT say.** It does not say CP-SAT would fix it, or that the local path
-- causes it. A 2%-enacted proposer cannot be credited or blamed for either KPI, which is
-- precisely why §2 matters: until CP-SAT's plans survive disposal, this depot's capacity is a
-- measurement of the LOCAL path under load and nothing else. Pricing the difference needs
-- C5's CRN-paired A/B with the L1 shield held constant (`db/checks/0146`), which does not
-- exist yet.

SELECT (public.ottoq_kpi_five('c8f678fb-a04a-4c18-a937-9b93673f3fe9')->'kpis') -> 'p95_time_to_service_min' AS p95,
       (public.ottoq_kpi_five('c8f678fb-a04a-4c18-a937-9b93673f3fe9')->'kpis') -> 'returns_unserved' AS returns_unserved,
       (public.ottoq_kpi_five('c8f678fb-a04a-4c18-a937-9b93673f3fe9')->'kpis') -> 'service_point_turns_per_point_per_day' AS turns,
       (public.ottoq_kpi_five('c8f678fb-a04a-4c18-a937-9b93673f3fe9')->'kpis') -> 'asset_hours_available_per_day' AS asset_hours,
       (public.ottoq_kpi_five('c8f678fb-a04a-4c18-a937-9b93673f3fe9')->'kpis'->'provenance') -> 'not_reproducible' AS not_reproducible;

-- ══ 4. G97 REPRODUCES INDEPENDENTLY, ON A DIFFERENT SEED ═══════════════════
--
-- `0286` found KPI 4 counting the deterministic shield's own safe-default fallbacks as human
-- labour, measured on seed 101959. On seed 100020 it reproduces exactly: **touch_events 610 =
-- operator 78 + override 532**, so 87% of the published 1.091 is the shield again, and the
-- human-attributable figure is **78 / 559 = 0.140**. Two seeds, same asymmetry. That removes
-- the one caveat `0286` §5 carried — it is not a property of one run's mix.
--
-- ══ 5. WHAT IS NOT ESTABLISHED, AND THE ONE THING I REFUSED TO CLAIM ═══════
--
-- **I will not claim the one-tick hold is broken, and I checked before not claiming it.**
-- `forward_lex` carries `holds_tick = true`, and `proposer_hold_enabled = 1` was armed (7 of
-- 7 keys). The deferral machinery IS firing: `ottoq_cuopt_deferrals` recorded **62** holds on
-- this run (61 `clear` + 1 `armed`), every one both spent and cleared, across 62 vehicles and
-- ticks 1-1112. Sixty-two holds against ~610 proposals LOOKS like the hold covering a tenth
-- of them — but a hold may be armed once per vehicle-visit rather than once per proposal, and
-- I do not have that denominator. **A ratio without its denominator is the unit error `0284`
-- §3 and `0285` §1 both record; three times in one night is enough.** Whether the hold should
-- have prevented these 539 supersessions is the next measurement, not a conclusion here.
--
-- Also open: one run, one seed, one wave. And the night-vs-wave split maps fires to snapshots
-- by tick, so a fire between two snapshots inherits the earlier one's clock — immaterial at
-- this granularity (snapshots are per-tick) but stated rather than assumed.

SELECT state, count(*) AS holds, count(DISTINCT vehicle_id) AS vehicles,
       count(*) FILTER (WHERE spent_at_tick IS NOT NULL) AS spent,
       count(*) FILTER (WHERE cleared_at_tick IS NOT NULL) AS cleared,
       min(armed_at_tick) AS first_tick, max(armed_at_tick) AS last_tick
  FROM public.ottoq_cuopt_deferrals
 WHERE sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9'
 GROUP BY 1 ORDER BY holds DESC;

-- ══ 6. ADDENDUM — THE DENOMINATOR §5 REFUSED TO GUESS, AND IT IS A WIRING
--       GAP: THE RIGHT-OF-FIRST-REFUSAL IS ARMED BY THE DECIDER, NOT BY THE
--       DOOR ════════════════════════════════════════════════════════════════
--
-- §5 declined to call the one-tick hold broken on a bare 63-against-610 ratio. Here is the
-- denominator it was missing — hold coverage per proposal, asking whether a deferral row for
-- THAT vehicle spans THAT proposal's tick:
--
--   status       proposals   hold covered THIS tick   vehicle held at SOME tick
--   superseded        559          **14  (2.5%)**          414  (74.1%)
--   refused           36            1                      21
--   enacted           12            2                       9
--   expired            3            0                       0
--
-- **So the hold is armed for three quarters of these vehicles at some point in the run, and
-- almost never at the moment the proposal was made.** 2.5% coverage on the population it
-- would have to cover to matter.
--
-- **And the cause is one query, not a theory.** Neither door arms a hold:
--
--   ottoq_proposer_submit_batch       mentions first_refusal: NO   writes deferrals: NO
--   ottoq_submit_external_proposal    mentions first_refusal: NO   writes deferrals: NO
--   ottoq_cuopt_first_refusal_arm     mentions first_refusal: YES  writes deferrals: YES
--   ottoq_cuopt_defer_roll            —                            writes deferrals: YES
--   ottoq_decide_tick                 mentions first_refusal: YES  writes deferrals: NO
--
-- The hold is armed by `ottoq_decide_tick` through `ottoq_cuopt_first_refusal_arm`, on the
-- DECIDER's schedule and by the decider's criteria. **Submitting a proposal does not itself
-- buy a tick of protection.**
--
-- **Why that is coherent rather than careless, which is the part worth understanding.** The
-- mechanism's own name says `cuopt`, and the cuOpt path runs the other way round: the decide
-- tick itself initiates the cuOpt request, so the decider naturally arms the hold *before*
-- dispatching and the proposal comes back into a seat already reserved for it. The CP-SAT
-- bridge inverts that — an external process pushes a proposal through the door at an
-- arbitrary moment between ticks — and the hold was never adapted to that direction. A
-- proposal that lands at tick T+0.4 has no seat, and by tick T+1 the local path has decided
-- the entity. That is the 96.2% in §2, mechanically.
--
-- **NOT FIXED, and this one is a design decision rather than a repair.** Arming a hold from
-- the door would change WHEN the deterministic decide path is required to defer — it makes an
-- external proposer able to make the kernel wait. That is a change to what the local path is
-- allowed to do, on the tick path, affecting throughput, and it is exactly the class of
-- decision CLAUDE.md 2.5 reserves ("do not rip out a working propose/dispose pipeline") and
-- rule 6 puts on the product side. Three shapes it could take, with different meanings:
--
--   (a) **Arm at the door.** `ottoq_proposer_submit_batch` arms a one-tick hold per row for a
--       `holds_tick` source. Strongest, and it lets any external proposer stall the kernel.
--   (b) **Arm at the tick boundary for whatever is pending.** The decide tick, before
--       deciding, reads pending `holds_tick` proposals and arms holds for those entities.
--       Keeps arming with the decider, costs one extra read per tick, and cannot be abused
--       by submission timing.
--   (c) **Leave it and accept CP-SAT as advisory.** Honest, and it means the 2% enactment
--       rate is the designed outcome rather than a defect — in which case every claim about
--       CP-SAT's contribution must be quoted at 2%.
--
-- **(b) is what I would build**, because it preserves "the decider decides when to defer"
-- while closing the timing gap. It is not built here. **Recorded as the G98 follow-up.**

SELECT p.proname,
       (p.prosrc ILIKE '%first_refusal%') AS mentions_first_refusal,
       (p.prosrc ILIKE '%cuopt_deferrals%') AS writes_deferrals
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.proname IN ('ottoq_proposer_submit_batch', 'ottoq_submit_external_proposal',
                     'ottoq_cuopt_first_refusal_arm', 'ottoq_cuopt_defer_roll',
                     'ottoq_decide_tick')
 ORDER BY 1;

WITH fl AS (
  SELECT entity_id::uuid AS vid, tick_seq, status
    FROM public.ottoq_external_proposals
   WHERE sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9' AND source = 'forward_lex')
SELECT status, count(*) AS proposals,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_cuopt_deferrals df
          WHERE df.sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9'
            AND df.vehicle_id = fl.vid
            AND fl.tick_seq BETWEEN df.armed_at_tick
                                AND COALESCE(df.cleared_at_tick, df.armed_at_tick + 1)))
         AS hold_covered_this_tick,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_cuopt_deferrals df
          WHERE df.sim_run_id = 'c8f678fb-a04a-4c18-a937-9b93673f3fe9'
            AND df.vehicle_id = fl.vid)) AS vehicle_held_at_some_tick
  FROM fl GROUP BY 1 ORDER BY proposals DESC;
