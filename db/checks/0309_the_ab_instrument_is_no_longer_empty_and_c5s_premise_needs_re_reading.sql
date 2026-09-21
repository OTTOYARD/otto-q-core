-- 0309  **C5's GOVERNING PREMISE IS STALE, AND I REPEATED IT TO CHASE THIS MORNING.** CLAUDE.md's
--       Phase C5 is written around `db/checks/0145`'s finding that `ottoq_ab_runs` is "a
--       well-shaped EMPTY instrument" with one policy, one seed, and **no function anywhere in
--       the database writing it**. Measured today: **two writers, three policies, nine seeds, and
--       four genuinely paired groups.** The A/B gap is real but it is NOT where the brief says.
--
-- Read-only. Measured 2026-09-21 16:4x UTC (11:4x CT). Found while closing G111, which surfaced
-- `public.ottoq_ab_pair` as a caller of the fleet reset — a function C5's text does not mention.
--
-- ══ 1. WHAT 0145 SAID, AND WHAT IS TRUE NOW ════════════════════════════════
--
--                              0145 (2026-09-08)        today
--   rows                       68                       **91**
--   distinct policies          **1** (`otto_q`)         **3** (`fifo`, `greedy`, `otto_q`)
--   distinct seeds             **1**                    **9**
--   groups with >1 policy      **0** (31 singletons)    **4**
--   functions writing it       **NONE**                 **`ottoq_ab_write_score`,
--                                                         `ottoq_score_run`**
--
-- And the pair rig C5 calls "the one genuinely new thing to build" **exists**:
--
--   public.ottoq_ab_pair(p_seed bigint, p_ticks int, p_scenario text, p_depot uuid,
--                        p_sim_start timestamptz, p_arm_budget_s int,
--                        **p_seat_a text, p_seat_b text**)
--
-- Two named seats. That is precisely the `p_policy` parameterisation C5 asks for, and it calls
-- `ottoq_tick_invariance_reset_fleet` between arms exactly as `ottoq_determinism_pair` does — so
-- the CRN discipline C5 insists on is inherited rather than reinvented.
--
-- **0145 WAS RIGHT WHEN WRITTEN.** This is not a retraction of it; it is a statement that
-- thirteen days of build have overtaken it, and that the brief was never updated. The failure is
-- the one Part 3 keeps recording about ROW COUNTS — a file quoted past its evidence — arriving
-- this time in a PLANNING premise rather than a metric.
--
-- ══ 2. THE FOUR PAIRED GROUPS, WHICH ARE THE WHOLE OF IT ═══════════════════
--
--   ab_group_id  arms  policies        seeds  scen  ticks  scored (UTC)  safety_viol  throughput
--   1e683534        4  fifo,otto_q        1     1      1   2026-09-13         24        15.67
--   c7f1ae81        2  greedy,otto_q      1     1      1   2026-09-12         12        15.59
--   f686efa4        2  fifo,otto_q        1     1      1   2026-09-12          0         0.67
--   02310000        2  fifo,otto_q        1     1      1   2026-09-08          3        13.00
--
-- **So paired comparisons exist and have been scored.** What they are not is a result:
--
--   * **One seed per group, one scenario, one tick count.** No replication, so no group can
--     distinguish a policy effect from a draw. C5's own text calls CRN pairing "the statistical
--     spine of every future claim"; a spine of n=1 carries nothing.
--   * **No PAIRED group scored since 2026-09-13** — eight days. (The query below prints the
--     TABLE's max, **2026-09-15 18:47 UTC**, which is a singleton row and not a pair; the two
--     numbers are not in conflict and neither should be quoted for the other.) That predates
--     the clock fix (`0396`),
--     the whole agent→CP-SAT chain, and `0308` §8's granularity finding. Every one of those
--     changes the world these were scored in.
--   * **`safety_violations` is non-zero and VARIES across groups (24, 12, 0, 3).** That is
--     `0146` visible in the data: the baselines do not pay the L1 shield, so `throughput_per_hr`
--     is not comparable between arms. A greedy arm that checks nothing will out-throughput one
--     that checks everything, and the number will be arithmetically correct and worthless.
--
-- ══ 3. AND `0308` §8 ADDS A CONSTRAINT NOBODY HAD WHEN THESE WERE SCORED ═══
--
-- The `begin_charge` confirm chain costs exactly one tick, and tick granularity is not a constant:
-- `cert_harness` 30 sim-minutes, `production_live` 2 minutes, `operator_demo` 29 seconds. **An
-- A/B pair run at a coarse granularity measures the tick, not the policy** — charge bookings
-- shorter than a tick cannot complete regardless of which policy booked them. Whatever the four
-- groups above ran at, it must be established before their throughput figures mean anything, and
-- it is not recorded in `ottoq_ab_runs` (there is no per-tick column; `ticks` is a count).
--
-- ══ 4. SO THE GAP IS REAL, AND IT IS A DIFFERENT GAP ═══════════════════════
--
-- **What I told Chase this morning** — *"the A/B gap remains: no KPI improvement is claimed or
-- claimable"* — is **true as a statement about KPIs and understated as a statement about
-- readiness.** The instrument, the writers, the two-seat pair rig and the CRN inheritance are all
-- built. What is missing is narrower and more tractable than "build the A/B rig":
--
--   1. **Replication.** Many seeds per group, not one.
--   2. **Freshness.** Re-run on the current engine; the existing rows predate four material changes.
--   3. **`0146`'s shield decision, still unresolved and still the hard one.** Either route every
--      arm through the same L1 evaluation, or publish safety and throughput only ever together
--      and relabel the baselines as *dispatch with no safety layer*. **This is a product
--      decision, not an engineering task**, and it has been open since 2026-09-08.
--   4. **A granularity that lets a booking outlive a tick** (`0308` §8f), recorded with the run.
--
-- **NOT CLAIMED:** that any of the four groups shows a policy effect. They cannot — n=1 each.
-- **NOT DONE:** re-running them. That needs the granularity decision first, or it repeats the
-- measurement at whatever tick size happens to be configured.

SELECT 'rows'                AS metric, count(*)::text                                  AS value FROM public.ottoq_ab_runs
UNION ALL SELECT 'policies',  string_agg(DISTINCT policy, ', ')                                  FROM public.ottoq_ab_runs
UNION ALL SELECT 'seeds',     count(DISTINCT seed)::text                                         FROM public.ottoq_ab_runs
UNION ALL SELECT 'paired groups (>1 policy)',
       (SELECT count(*)::text FROM (SELECT ab_group_id FROM public.ottoq_ab_runs
                                     GROUP BY 1 HAVING count(DISTINCT policy) > 1) g)
UNION ALL SELECT 'writers',
       COALESCE((SELECT string_agg(n.nspname||'.'||p.proname, ', ' ORDER BY p.proname)
                   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                  WHERE p.prosrc ~* 'INSERT\s+INTO\s+(public\.)?ottoq_ab_runs'
                     OR p.prosrc ~* 'UPDATE\s+(public\.)?ottoq_ab_runs'), '(none)')
UNION ALL SELECT 'last scored', COALESCE(max(scored_at)::text, '(never)')                FROM public.ottoq_ab_runs;

-- OPEN-ITEM: CLAUDE.md Phase C5 is written around 0145's finding that ottoq_ab_runs is an empty instrument with one policy, one seed and NO writer. That is stale: measured 2026-09-21 it holds 91 rows across 3 policies (fifo, greedy, otto_q) and 9 seeds, with two writers (ottoq_ab_write_score, ottoq_score_run) and FOUR genuinely paired groups, and public.ottoq_ab_pair already takes p_seat_a/p_seat_b -- the policy parameterisation C5 calls "the one genuinely new thing to build". 0145 was right when written; thirteen days of build overtook it and the brief was never updated. The gap is REAL but different and narrower: (1) one seed per group, so no group can separate a policy effect from a draw; (2) nothing scored since 2026-09-13, predating 0396's clock fix, the agent chain and 0308 §8; (3) 0146's shield decision STILL UNRESOLVED and still a product decision -- safety_violations vary 24/12/0/3 across groups, which is the baselines not paying the shield, visible in the data; (4) 0308 §8's granularity constraint, which did not exist when these were scored and which ottoq_ab_runs has no column to record. Do NOT re-run the pairs before the granularity and shield decisions, or the measurement repeats at whatever tick size happens to be configured. Tracked as G113.
