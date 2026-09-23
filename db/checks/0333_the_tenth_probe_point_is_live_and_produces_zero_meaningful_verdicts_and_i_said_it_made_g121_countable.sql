-- 0333  **`0422` wired the `task_completion` probe four hours ago and I wrote, in the migration header
--       and in CLAUDE.md, that it makes G121 "countable from the shield's own ledger." IT DOES NOT.
--       Measured on the first 1,230 evaluations: of the five codes declared at `task_completion`,
--       three abstain on 100% of calls, one produces a TAUTOLOGY, and the fifth resolves a stall that
--       the work never occupies. The tenth probe point currently produces ZERO meaningful verdicts.**
--
--       The probe is not the mistake — it is the instrument that made this visible, and it took four
--       hours rather than four months. The mistake is that I reported a result before reading one.
--
--       Measured 2026-09-22 13:50 UTC (08:50 CT), mid-sweep, 246 evaluations per code.
--
-- ══ §1 WHAT `ottoq_assert_task_completion_coverage()` SAYS, AND WHY IT IS NOT ENOUGH ══
--
--     rule_code                              evals  real_verdicts  abstentions  failed  verdict
--     ------------------------------------  -----  -------------  -----------  ------  ------------------------
--     HW.003.sensor_liveness                  246            246            0     102  "FIRING: real failures"
--     HW.006.physical_presence_verification   246             36          210      32  "FIRING: real failures"
--     SLA.003.max_visit_duration              246              0          246       0  "VACUOUS"
--     SM.002.task_transition_validity         246              0          246       0  "VACUOUS"
--     TW.002.overnight_staging                246              0          246       0  "VACUOUS"
--
-- `0419` built that function to stop abstentions being counted as protection, and it works: it caught
-- three of the five. **What it cannot catch is a verdict that is real and tautological**, and that is
-- exactly what the other two are. A counter that separates "abstained" from "judged" still has no
-- opinion on whether the judgement means anything.
--
-- ══ §2 HW.003 IS MEASURING HOW LONG THE ATOM TOOK ════════════════════════════
--
-- All 102 failures are one service, `perimeter_walkaround`, and the reason strings are
-- *"SOC sensor stale: 600/660/720/780/840/900 seconds old (threshold 300)"*. Differencing the reported
-- staleness against the atom's own measured duration, per service:
--
--     svc                    n    passed   mean stale_s   mean atom_s   stale - duration
--     --------------------  ---  -------  -------------  ------------  ----------------
--     perimeter_walkaround  102        0            740           742          **-2**
--     remote_diagnostics     14       14            300           300             0
--     sensor_clean            2        2            300           300             0
--     interior_tidy          12       12            260           240            20
--     interior_inspection    94       94            245           242             3
--     item_retrieval          4        4            240           240             0
--     triage_check           18       18            180           180             0
--
-- **The SoC reading is exactly as old as the work, for every service, to within 20 seconds.** HW.003 at
-- `task_completion` is not detecting a stale sensor; it is restating the atom's duration and comparing it
-- to a 300-second constant. **Every atom longer than five minutes fails by construction**, and
-- `perimeter_walkaround` (742 s declared 12 min) is the only service in the catalog that exceeds it —
-- which is the whole reason 102 of 102 failures carry one service name.
--
-- **So `0326` §6's sharpest line has its answer and it is not the one implied.** That line — *"the engine
-- checks sensor liveness before work begins and never after it finishes, and scores that as covered"* —
-- reads as a gap to close. Closed, the check measures duration. A freshness threshold evaluated at the
-- END of an operation is answering "was this operation shorter than the threshold", which is a question
-- nobody asked.
--
-- ══ §3 HW.006's FAILURES ARE NOT G121, AND THAT IS MY RETRACTION ═════════════
--
-- I wrote in `0422`'s header and in CLAUDE.md: *"What this buys is that the defect becomes COUNTABLE from
-- the shield's own ledger instead of from an ad-hoc census."* Measured, joining every evaluation that
-- resolved a stall back to `stalls`:
--
--     passed   stall_type    stall_status   stall has ANY vehicle   n    distinct stalls
--     ------  ------------  -------------  ----------------------  ---  ---------------
--     false    service_bay      available           **false**       70         3
--     true     service_bay      available           **false**        4         1
--
-- **Every resolvable case is a service-bay stall that is `available` and holds no vehicle at all** — and
-- that includes the four that PASSED, so even the passes are not evidence of presence. G121 is three
-- **`dcfc`** stalls each holding a live `current_vehicle_id` pointing at a vehicle that is physically in a
-- bay. These are a different stall type, a different pointer state, and a different defect.
--
-- **The mechanism, and it traces straight back to `0383`.** `perimeter_walkaround` is the one service
-- `0383` re-derived as `concurrency='exterior'` — *performed at the vehicle, `lane_stalls=NULL`* — so it
-- occupies no stall by design. But it still books one: **2,425 `purpose='service'` bookings across 3
-- service-bay stalls** carry `need_atom='perimeter_walkaround'`, and `0418`'s stall resolution is
-- `ottoq_stall_bookings.need_atom = svc`. So the probe faithfully finds a booking, hands HW.006 a stall
-- the work was never at, and HW.006 correctly reports the vehicle is not there. **Every layer behaved
-- correctly and the composition is meaningless.**
--
-- **AND 2,425 IS NOT THE NUMBER TO EXPECT, WHICH IS A SEPARATE FINDING AND POSSIBLY A BIGGER ONE.**
-- `0383` recorded the walkaround's own bookings as *"fourteen `purpose='service'` rows on two service-bay
-- stalls"*; that was point-in-time and the live figure is two orders of magnitude larger. Re-derived with
-- `0250`'s depot predicate, because the unscoped 3-stall count is exactly the number that rule forbids
-- reasoning from:
--
--     depot                    stall_type    bookings   stalls   runs   span (sim)
--     ----------------------  ------------  ---------  -------  -----  -------------------------
--     11111111-… (the twin)    service_bay    **2,353**     **2**    34   2026-08-30 -> 2026-09-22
--     aacd0bb0-… (fixture)     service_bay         72        1    16   2026-09-01 (one day)
--
-- **On the twin depot that is ~69 bookings per run against the site's TWO service bays, for a service
-- performed at the vehicle that needs no bay at all.** The twin has 2 service bays and 3 wash bays; the
-- service bay is among its scarcest resources.
--
-- **What is measured and what is not.** Measured: the bookings exist, they are on the twin depot's two
-- service bays, and the service that holds them is `lane_stalls=NULL`. **Not measured: whether they
-- displace real bay work.** A booking on a calendar is not contention until something else is refused
-- because of it, and `0250` is the standing reminder that inferring a capacity wall from a count on the
-- wrong predicate is how the last one went wrong. Filed as the next thing to measure, not as an impact.
--
-- ══ §4 THE HONEST NET RESULT OF `0422` ═══════════════════════════════════════
--
-- **Say:** *"`task_completion` is now probed, 1,230 evaluations on the first sweep. Of the five codes it
-- carries, three abstain on every call, HW.003's verdicts restate the atom's duration, and HW.006's
-- resolve a stall the work does not occupy. The probe is live and produces no meaningful verdict yet."*
--
-- **Do NOT say:** that HW.006 now fires on G121, that sensor liveness is failing on 41.5% of completions,
-- or that the tenth probe point improved coverage. The first is wrong (§3), the second is a tautology
-- (§2), and the third was already forbidden by `0326` §6 — a probe is not protection.
--
-- **And `0418` §2's design decision has now been arbitrated by data, against itself.** It considered
-- scoping the probe to atoms that genuinely occupy a stall and rejected it: *"Suppressing the probe when
-- there is no stall would also suppress `HW.003`, `SLA.003`, `SM.002` and `TW.002`, none of which need a
-- stall — and `HW.003` sensor liveness after completion is one of the gaps `0326` §6(b) identified as
-- real. Scoping the probe to fix HW.006's vacuity would throw away four working checks to spare one rule
-- an honest abstention."* **There were no four working checks.** Three abstain always and the fourth is
-- tautological. The reasoning was sound in form and empty in fact, and only wiring it could show that.
--
-- ══ §5 WHAT TO FIX, IN THE ORDER THE EVIDENCE SUPPORTS ═══════════════════════
--
--   1. **Stop resolving a stall for atoms whose service is vehicle-side.** `service_cadence_policy` already
--      carries `lane_stalls=NULL` for `exterior` services (`0383`), so the predicate exists. HW.006 then
--      abstains honestly on the walkaround instead of failing it against a bay it was never in.
--   2. **Do not evaluate HW.003 at `task_completion`** — or give it a basis other than a wall-clock
--      freshness constant. As wired it cannot express anything except "this atom ran longer than 300 s."
--   3. **The three abstainers need context the probe does not carry** (`SLA.003` a visit start, `SM.002`
--      a from/to task state, `TW.002` a schedule window). Each is a separate decision about whether the
--      rule belongs at this probe at all, and `0326` §6's test applies to each: does the engine perform
--      the action the rule is judging?
--   4. **G121 still needs its own instrument.** Nothing here counts it, and the census in `0326` §2
--      remains the only measurement of it.
--
-- **None of this argues for reverting `0422`.** An instrument that reports "nothing meaningful yet" in
-- four hours is worth more than a declaration gap that sat unmeasured for the engine's whole life. The
-- defect was in the sentence I wrote about it, not in the wiring.

\echo '=== 0333 §1 — the coverage function, and the class it cannot see ==='
SELECT * FROM public.ottoq_assert_task_completion_coverage();
-- It separates abstention from verdict, which is what 0419 built it for, and it has no opinion on
-- whether a verdict is tautological. HW.003 and HW.006 both read "FIRING: real failures present".

\echo '=== 0333 §2 — HW.003 staleness EQUALS the atom duration, every service ==='
WITH ev AS (
  SELECT context->>'svc' AS svc,
         (regexp_match(reason,'(\d+) seconds old'))[1]::int AS stale_s,
         passed
    FROM public.ottoq_rule_evaluations
   WHERE action_context='task_completion' AND rule_code='HW.003.sensor_liveness'
), dur AS (
  SELECT a->>'svc' AS svc,
         round(avg(EXTRACT(epoch FROM (a->>'ends_at')::timestamptz - (a->>'started_at')::timestamptz))) AS atom_secs
    FROM public.ottoq_visit_needs vn CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
   WHERE a ? 'started_at' AND a ? 'ends_at'
   GROUP BY 1
)
SELECT ev.svc, count(*) AS n, count(*) FILTER (WHERE ev.passed) AS passed,
       round(avg(ev.stale_s)) AS mean_stale_s, dur.atom_secs AS mean_atom_secs,
       round(avg(ev.stale_s)) - dur.atom_secs AS stale_minus_duration
  FROM ev LEFT JOIN dur ON dur.svc = ev.svc
 GROUP BY ev.svc, dur.atom_secs ORDER BY mean_stale_s DESC NULLS LAST;
-- stale_minus_duration: -2, 0, 0, 20, 3, 0, 0 across seven services. The reading is exactly as old as
-- the work. Only perimeter_walkaround (742 s) exceeds the 300 s threshold, which is why every failure
-- carries that one service name.

\echo '=== 0333 §3 — HW.006 resolves a stall that holds nobody. This is NOT G121 ==='
WITH e AS (
  SELECT (context->>'stall_id')::uuid AS stall_id, context->>'svc' AS svc,
         (context->>'vehicle_id')::uuid AS vehicle_id, passed
    FROM public.ottoq_rule_evaluations
   WHERE action_context='task_completion' AND rule_code='HW.006.physical_presence_verification'
     AND context ? 'stall_id'
)
SELECT e.passed, s.stall_type, s.status AS stall_status,
       (s.current_vehicle_id IS NOT NULL)   AS stall_has_ANY_vehicle,
       (s.current_vehicle_id = e.vehicle_id) AS stall_holds_THIS_vehicle,
       count(*) AS n, count(DISTINCT e.stall_id) AS distinct_stalls,
       count(DISTINCT e.svc) AS distinct_svc
  FROM e JOIN public.stalls s ON s.id = e.stall_id
 GROUP BY 1,2,3,4,5 ORDER BY n DESC;
-- All service_bay, all `available`, all holding no vehicle -- including the rows that PASSED, so the
-- passes are not evidence of presence either. G121 is three DCFC stalls holding a live current_vehicle_id.
-- Different stall type, different pointer state, different defect.

\echo '=== 0333 §3b — the mechanism, DEPOT-SCOPED per rule 8 / 0250 ==='
SELECT s.depot_id, s.stall_type, count(*) AS bookings, count(DISTINCT b.stall_id) AS stalls,
       count(DISTINCT b.sim_run_id) AS runs,
       round(count(*)::numeric / NULLIF(count(DISTINCT b.sim_run_id),0)) AS bookings_per_run,
       min(lower(b.during)) AS first_sim, max(upper(b.during)) AS last_sim
  FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id=b.stall_id
 WHERE b.need_atom = 'perimeter_walkaround'
 GROUP BY 1,2 ORDER BY bookings DESC;
-- Twin depot: 2,353 bookings on 2 service bays across 34 runs (~69/run). perimeter_walkaround is
-- concurrency='exterior' with lane_stalls=NULL -- performed AT THE VEHICLE -- so it needs no bay and
-- books one anyway. 0418 resolves the stall by need_atom = svc, finds one of these, and HW.006 correctly
-- reports the vehicle is not in it. Every layer behaved correctly; the composition is meaningless.
-- The unscoped version of this query reports "3 stalls" and is the shape 0250 forbids reasoning from.
