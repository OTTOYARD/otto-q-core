-- 0326  **Three of the twin depot's ten DCFC stalls read `status='available'` while still pointing at a
--       vehicle that is physically in a bay. No sweeper in the engine will ever clear them — both
--       candidate sweepers exclude non-bay stalls BY EXPLICIT DESIGN. And `HW.006`, one of the six
--       declared rules that has never been probed, is precisely the rule written to detect this.**
--
--       Found while working the standing rules mandate — "every known rule present and firing" — which
--       is why the census correction in §6 is here rather than in its own file: the same walk produced
--       both.
--
--       **No migration.** §7 says why, and the reason is that the fix is a design decision someone
--       deliberately made in the other direction.
--
--       Measured on the twin depot `11111111-…` at 2026-09-22 07:16–07:17 UTC (02:16 CT), live run.
--
-- ══ §1 FIRST, THE TRAP I ALMOST PUBLISHED — NINTH INSTANCE OF THE CLOCK-DOMAIN
--       CLASS, AND THE MOST DRAMATIC ONE YET ═══════════════════════════════════
--
-- `ottoq_stall_bookings.during` is a `tstzrange` in **SIM** time. `now()` is **REAL** time. On this run
-- they are **four hours apart** (real 07:16:41, sim 11:25:08). The proof that `during` is sim and not
-- real is exact rather than inferred: for `temp_hold`, `charge_l2` and `charge_dcfc`,
-- `min(lower(during))` equals `min(booked_at_sim)` **to the microsecond**, while `booked_at` is hours off.
--
-- What that does to a calendar-availability census:
--
--     stall type     stalls   calendar-free, SIM (right)   calendar-free, now() (WRONG)
--     -----------    ------   --------------------------   ----------------------------
--     dcfc               10                            2                             10
--     l2                 30                            4                             30
--     staging           113                           54                            113
--     service_bay         2                            0                              2
--     wash_bay            3                            3                              3
--
-- **Computed against `now()`, every stall type reads 100% free — the query reports an empty depot on a
-- run with 116 vehicles in it.** This is not a number shifted by a few percent; it is a gate that
-- silently answers "yes" to everything. A capacity conclusion drawn from it would be the `0250` class of
-- error all over again, and I had the wrong figure (`dcfc_calendar_free = 10`) in hand and was reasoning
-- from it before checking which clock `during` lives in.
--
-- **AND I CHECKED WHETHER CLAUDE.md PART 3 SHARES THIS BUG. IT DOES NOT, and the proof is its own L2
-- number.** Part 3 records *"DCFC read 0 pointer-free against 10 calendar-free, L2 read 3 against 1, and
-- staging read 59 against 12."* Had that calendar column been computed with `now()`, L2 would have read
-- **30** calendar-free, not 1. So Part 3's measurement was in the right clock; its values differ from
-- mine only because it is a different moment. **Stating this explicitly because the tempting write-up
-- was "Part 3 made this mistake too", and it is false.**
--
-- ══ §2 THE DEFECT: THREE FAST CHARGERS HELD BY VEHICLES THAT LEFT ═════════════
--
-- Exactly three stalls in the entire twin depot carry `status='available'` **and** a non-NULL
-- `current_vehicle_id`. All three are `dcfc`. All three point at a vehicle that is in a bay:
--
--     stall_id    type   status      pointer  reserved_by  pointed vehicle's state  live bookings (sim)
--     ---------   ----   ---------   -------  -----------  -----------------------  -------------------
--     364caf8d…   dcfc   available   set      set          in_detail_bay            0
--     3a7310ac…   dcfc   available   set      set          in_service_bay           0
--     9753cfd9…   dcfc   available   set      set          in_detail_bay            0
--
-- Every other stall type is internally consistent — pointer set if and only if `status='occupied'`:
-- dcfc 7 occupied/7 pointed, l2 30/30, staging 56/56, and the five bays 0/0. **So this is not a general
-- pointer-hygiene problem. It is one transition, on one stall type, leaking three rows.**
--
-- It is **persistent, not a momentary race**: measured 3 at 07:16:15, 3 at 07:16:41, 3 at 07:17:27,
-- across ticks that fire every 30 seconds.
--
-- **The cost is exactly the scarce resource.** `gate1_pointer_free` for dcfc is **0 of 10**, and three of
-- those ten are held by nobody. CLAUDE.md Part 3 records DCFC at 87% occupancy and `0250` records that
-- every refused proposal on a live run was asking for one of the two charge stall types. **A stale
-- pointer on 30% of the depot's fast-charging capacity is material to that, not cosmetic.**
--
-- ══ §3 AND NOTHING WILL CLEAR IT, BECAUSE BOTH SWEEPERS EXCLUDE IT ON PURPOSE ══
--
-- Two functions could plausibly reconcile a stale pointer, and each rules itself out in its own comment:
--
--   1. **`ottoq.ottoq_release_vacated_spaces` phase (b)** hard-frees a stall whose occupant no longer
--      claims it — clearing `current_vehicle_id`, `reserved_by`, `reservation_expires_at` and `status`,
--      which is exactly the repair needed. Its predicate is
--      `s.stall_type IN ('wash_bay','service_bay')` and its comment reads **"Never dcfc/l2/staging."**
--      The 0329 note lower in the same function confirms it: *"Everything above this line is bay-only by
--      design and that design is right."*
--   2. **`ottoq.ottoq_release_departed_spaces` (0329)** is the one built for "the other 153 stalls" — and
--      it is **calendar-only** by its own comment and its catalog description (*"retires a dcfc/l2/staging
--      calendar CLAIM"*). A calendar retirement cannot clear a pointer, so it could not fix this even if
--      it ran. **And it does not run:** `space_departure_release_enabled` has catalog default **0**, and
--      the single stored row anywhere in `ottoq_policy_params` is **run-scoped to `39c7400a`, set
--      2026-09-15** — a run long since purged. On the live run the dial resolves to 0 and the sweeper is
--      inert.
--
-- **So the finding is not "a sweeper is broken".** It is that the pointer on a non-bay stall is cleared
-- only by whatever set it, on the normal path, and there is no reconciler behind that path. When the
-- normal path misses — as it does on the charger→bay move — the row stays wrong forever. **That is a
-- deliberate design decision meeting an unhandled transition, which is why §7 does not "fix" it.**
--
-- ══ §4 THE BAYS FAIL THE OPPOSITE WAY, WHICH IS THE POINT ═════════════════════
--
--     stall type     pointer-free   calendar-free (sim)
--     -----------    ------------   -------------------
--     dcfc              0 of 10              2 of 10      <- pointer is the PESSIMISTIC gate
--     service_bay        2 of 2               0 of 2      <- calendar is the PESSIMISTIC gate
--
-- **Perfectly inverted on the same reading.** The service bays hold `purpose='service'` bookings in
-- state `held` with `current_vehicle_id IS NULL` — a calendar claim with nobody in the bay — while the
-- fast chargers hold a pointer with nobody in the stall. This is a fresh, sharper instance of CLAUDE.md
-- Part 3's rule that **neither of the first two gates dominates**: quote either alone and some stall type
-- makes you look generous. Here, quoting the pointer makes the bays look free and quoting the calendar
-- makes the chargers look free, **in the same query, at the same instant.**
--
-- (The `held`-and-empty service bookings are `perimeter_walkaround` atoms — see §5's note. Whether a
-- walkaround should book a bay at all is `0383`'s question, not this file's.)
--
-- ══ §5 THE RULE THAT WOULD HAVE CAUGHT §2 HAS NEVER BEEN ASKED ════════════════
--
-- `HW.006.physical_presence_verification` — `critical`, `enforcement='block'` — reads
-- `stalls.current_vehicle_id` for the context's stall and returns
--
--     FALSE, 'system state mismatch: stall does not record this vehicle as present',
--     suggested_action = 'reconcile_state_or_dispatch_tech_check'
--
-- when it disagrees with the context's vehicle. **That is §2, named, with the repair prescribed.** The
-- rule is declared, its evaluator exists and compiles, and it has **zero evaluations, ever**, because its
-- only declared action context is `task_completion` and **nothing in the engine probes `task_completion`.**
--
-- **This is the strongest argument the rules mandate has produced.** Not "a rule is unwired" as hygiene —
-- a live, persistent, capacity-relevant defect sitting unreported in the database, which a rule already
-- written for it would have flagged on its first evaluation. It is `G120`'s defect class (*a rule reads
-- green because it was never asked*) with a consequence attached.
--
-- ══ §6 AND THE COVERAGE CENSUS IS STALE IN OUR FAVOUR, WITH TWO FRAMES TO RETIRE ═
--
-- CLAUDE.md 2.5 says **"twenty-one of thirty declared rules, at six decision points"**, then carries
-- `0321`'s correction to **nine** probe points while leaving the 21 and the phrase *"the nine unevaluated
-- codes are the same nine"* standing. **Those two statements contradict each other inside one paragraph.**
-- Measured today over all 30 active codes:
--
--     evaluated:   24 of 30, at nine probe points
--     unevaluated:  6 — HW.006 (critical), SM.004 (critical), SM.005 (critical),
--                       SLA.002 (warning), TW.002 (info), TW.004 (info)
--
-- `SM.001`, `SM.003` and `SM.006` are **no longer unevaluated** — they are the one code each carried by
-- the three row-level triggers `0321` discovered (947, 924 and 14 evaluations). `0321` found the probes
-- and did not propagate the arithmetic. **So it is twenty-four of thirty at nine points, and THREE of the
-- unevaluated are critical, not six.** This moves in the flattering direction, which is the direction to
-- state most carefully.
--
-- **Two frames to retire, both of which made the gap look different than it is.**
--
-- **(a) "The other nine have evaluator functions that exist and are callable, and no caller" is an
-- artifact of how the shield dispatches.** Grepping every function body for an evaluator's name returns
-- **zero callers for SM.001, SM.003 and SM.006 too** — and those three fire thousands of times. The
-- shield reads `evaluator_function` out of `ottoq_rules` and invokes it with dynamic SQL via
-- `ottoq_evaluate_rule_core`, so the name never appears in any caller's source. **A static search for
-- callers can never find a rule's wiring**, and "no caller" was measuring the search, not the engine.
--
-- **(b) The right unit is the (code, context) PAIR, and on that unit coverage is 49%, not 80%.**
-- `ottoq_shield_probe` selects `WHERE p_action_context = ANY(r.applies_to_actions)`, so a rule is
-- protecting a decision only where a probe exists for a context it declares. Measured:
--
--     declared action contexts                              31
--     probed action contexts                                 9
--     declared and NEVER probed                             22
--     probed but declared by no rule                          0   <- no orphan probes; every probe is real
--
--     declared (code, context) pairs                        69
--     pairs actually probed                                 34   <- 49%
--     pairs with no probe                                   35
--
-- **"24 of 30 codes evaluated" is 80%. The same shield on the pair unit is 49%.** The code-level count
-- nearly doubles the apparent coverage, because a code scores as "evaluated" if **any one** of its
-- contexts is probed — so a rule declaring five contexts and probed at one counts as fully wired.
-- **This is the number CLAUDE.md 2.5's caveat — "21 of 30 is a wiring count, not a protection count" —
-- was reaching for without one.** Quote 34 of 69.
--
-- **And `task_completion` alone is declared by FIVE codes, not the two the six-code framing implies:**
-- `HW.003.sensor_liveness`, `HW.006.physical_presence_verification`, `SLA.003.max_visit_duration`,
-- `SM.002.task_transition_validity` and `TW.002.overnight_staging`. Three of those five (HW.003, SLA.003,
-- SM.002) are counted as *evaluated* because they fire at `task_start` or `redeployment` — **so the
-- engine checks sensor liveness before work starts and never after it finishes, and counts that as
-- covered.** The six-unevaluated-codes framing conceals this entirely: it can only see a code with no
-- probe at all, never a code missing one of the probes it asked for.
--
-- The other 21 unprobed contexts follow the same shape — `oem_acceptance` and `release` (four SLA codes
-- each, all evaluated elsewhere at `redeployment`), `power_increase` (three EN codes), `schedule_creation`,
-- `task_state_change`, `visit_progress_check`, `bess_charge`/`bess_discharge`, `arrival`/`queue_admission`,
-- `progression_decision_insert`, `post_redeployment_staging`, `cost_advisory`/`schedule_optimization`,
-- and SM.004's seven human/role actions. **Not one is probed anywhere.**
--
-- **One further property worth recording, because it de-risks the whole build:** `ottoq_shield_probe`
-- **does not block.** It returns a `would_block` column and leaves enforcement entirely to its caller.
-- So adding a probe is inherently a MEASURED change in CLAUDE.md 2.9a's sense — a new probe cannot wedge
-- the engine unless its caller chooses to act on `would_block`.
--
-- ══ §7 WHAT I DID NOT BUILD, AND WHY EACH ONE WAS DECLINED ════════════════════
--
-- **(a) I did not extend the sweeper to dcfc.** The exclusion is not an oversight to correct — it is
-- written twice, in two functions, in comments that argue for it (*"Never dcfc/l2/staging"*, *"that design
-- is right"*), and 0329 built the non-bay sweeper calendar-only on purpose. Hard-freeing a `dcfc` pointer
-- from a sweep could race the charge-session path that legitimately owns that column. **Reversing a
-- deliberate design decision on an unattended night, against a function inside the tick, is exactly the
-- change `0415` §5 declined to make to the solver path.** The safe repair is narrower and belongs with
-- whoever owns the charger→bay move: clear the charger pointer at the point the vehicle enters a bay.
--
-- **(b) I did not add the `task_completion` probe, though it was the plan when I started.** Dry-run
-- against the ten atoms in progress at 07:16, using `ottoq_stall_bookings.need_atom` to find each atom's
-- stall: **2 would FAIL HW.006 and 8 would pass on "insufficient context for presence verification"** —
-- because `cabin` and `exterior` atoms have no service stall at all. Per `0383`, `exterior` work is
-- performed **at the vehicle** with `lane_stalls=NULL`. **So HW.006 as written assumes every completion
-- happens AT A STALL, and most of this engine's work does not.** Wiring it naively would produce 80%
-- vacuous passes — a rule reading green because it could not look, which is G120 wearing a different
-- coat — plus failures on atoms the rule has no business judging. The probe must be scoped to atoms that
-- genuinely occupy a stall (`bay` concurrency, and the charge sessions) and that scoping is a decision
-- about the work model, not a wiring task.
--
-- **(c) I did not touch SM.005's context.** `progression_decision_insert` would probe
-- `public.progression_decisions`, which holds **1 row**. A probe there would gate a table nobody writes
-- and report green forever — building G120 deliberately.
--
-- The honest status: *the pointer gate is holding three fast chargers for vehicles that are in bays; no
-- reconciler covers non-bay stalls by design; the rule that names this defect exactly has never been
-- probed because nothing probes `task_completion`, which five codes declare; and the shield's coverage
-- is 34 of 69 declared (code, context) pairs — 49% — against the 24-of-30 code count's 80%.*

\echo '=== 0326 §1 — the clock domain: during is SIM, now() is REAL, and the wrong one says the depot is empty ==='
WITH simnow AS (SELECT max(sim_clock_at) AS t FROM public.ottoq_events)
SELECT s.stall_type::text AS stall_type, count(*) AS stalls,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b, simnow
                                           WHERE b.stall_id=s.id
                                             AND b.state IN ('held','active','done','interrupted')
                                             AND b.during @> simnow.t))  AS calendar_free_SIM_right,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                                           WHERE b.stall_id=s.id
                                             AND b.state IN ('held','active','done','interrupted')
                                             AND b.during @> now()))     AS calendar_free_REAL_wrong,
       count(*) FILTER (WHERE s.current_vehicle_id IS NULL AND s.reserved_by IS NULL
                          AND s.status='available')                      AS pointer_free
  FROM public.stalls s
 WHERE s.depot_id='11111111-1111-1111-1111-111111111111'
 GROUP BY 1 ORDER BY 1;
-- The REAL column reads every stall type 100% free. Ninth instance of the class; the first where the
-- wrong clock does not shift a number but empties a depot.

\echo '=== 0326 §1 — the proof that during is SIM: it equals booked_at_sim to the microsecond ==='
SELECT b.purpose, count(*) AS bookings,
       (min(lower(b.during)) = min(b.booked_at_sim)) AS during_lo_IS_booked_at_sim,
       (min(lower(b.during)) = min(b.booked_at))     AS during_lo_is_booked_at_real
  FROM public.ottoq_stall_bookings b
 WHERE b.state IN ('held','active') AND b.purpose IN ('temp_hold','charge_l2','charge_dcfc')
 GROUP BY 1 ORDER BY 1;

\echo '=== 0326 §2 — the three fast chargers held by vehicles that are in bays ==='
SELECT s.id AS stall_id, s.stall_type::text AS stall_type, s.status,
       s.current_vehicle_id IS NOT NULL AS pointer_set,
       s.reserved_by IS NOT NULL AS reserved_set,
       v.current_state AS pointed_vehicle_state
  FROM public.stalls s
  JOIN public.vehicles v ON v.id = s.current_vehicle_id
 WHERE s.depot_id='11111111-1111-1111-1111-111111111111'
   AND s.status='available'
 ORDER BY s.stall_type, s.id;
-- Three rows, all dcfc, all pointing into a bay. Every other stall type has pointer set iff occupied.

\echo '=== 0326 §3 — neither sweeper can reach a dcfc pointer, and each says so itself ==='
SELECT n.nspname||'.'||p.proname AS sweeper,
       (regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g')
          LIKE '%wash_bay%')                              AS scoped_to_bays,
       (regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g')
          LIKE '%current_vehicle_id = NULL%')             AS can_clear_a_pointer
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='ottoq'
   AND p.proname IN ('ottoq_release_vacated_spaces','ottoq_release_departed_spaces')
 ORDER BY 1;

\echo '=== 0326 §3 — and 0329s sweeper is inert: its only stored row belongs to a purged run ==='
SELECT c.param_key, c.default_value AS catalog_default,
       p.scope_type, p.scope_id, p.param_value, p.updated_at,
       EXISTS (SELECT 1 FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p.scope_id) AS that_run_still_exists
  FROM public.ottoq_policy_param_catalog c
  LEFT JOIN public.ottoq_policy_params p ON p.param_key = c.param_key
 WHERE c.param_key = 'space_departure_release_enabled';

\echo '=== 0326 §6 — the real census: 24 of 30 evaluated at nine probe points ==='
WITH codes AS (SELECT DISTINCT rule_code, severity FROM public.ottoq_rules WHERE status='active'),
     ev AS (SELECT rule_code, count(DISTINCT action_context) probes, count(*) n
              FROM public.ottoq_rule_evaluations GROUP BY 1)
SELECT count(*) AS active_codes,
       count(e.rule_code) AS evaluated,
       count(*) - count(e.rule_code) AS unevaluated,
       count(*) FILTER (WHERE e.rule_code IS NULL AND c.severity IN ('critical','safety_critical'))
         AS unevaluated_and_critical,
       (SELECT count(DISTINCT action_context) FROM public.ottoq_rule_evaluations) AS probe_points
  FROM codes c LEFT JOIN ev e ON e.rule_code = c.rule_code;
-- 30 / 24 / 6 / 3 / 9. CLAUDE.md 2.5's "twenty-one of thirty at six" is stale in our favour, and its
-- claim that the unevaluated nine "are the same nine" contradicts 0321's own nine-probe correction
-- sitting two sentences later.

\echo '=== 0326 §6(a) — why "evaluator exists, no caller" was measuring the search, not the engine ==='
SELECT r.rule_code, r.evaluator_function,
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname IN ('public','twin','ottoq') AND p.proname <> r.evaluator_function
           AND regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g')
               LIKE '%'||r.evaluator_function||'%')                       AS static_callers,
       COALESCE((SELECT count(*) FROM public.ottoq_rule_evaluations e
                  WHERE e.rule_code = r.rule_code), 0)                    AS actual_evaluations
  FROM public.ottoq_rules r
 WHERE r.status='active'
   AND r.rule_code IN ('SM.001.vehicle_transition_validity','SM.003.stall_transition_validity',
                       'SM.006.bess_transition_validity','HW.006.physical_presence_verification')
 ORDER BY actual_evaluations DESC;
-- static_callers is 0 for all four. Three of them fire thousands of times. The shield dispatches the
-- evaluator by name out of ottoq_rules with dynamic SQL, so no caller's source ever contains it.

\echo '=== 0326 §6(b) — the right unit: 34 of 69 (code, context) pairs probed, not 24 of 30 codes ==='
WITH declared AS (
  SELECT DISTINCT unnest(r.applies_to_actions) AS ctx FROM public.ottoq_rules r WHERE r.status='active'
), probed AS (SELECT DISTINCT action_context AS ctx FROM public.ottoq_rule_evaluations),
pairs AS (
  SELECT DISTINCT r.rule_code, unnest(r.applies_to_actions) AS ctx
    FROM public.ottoq_rules r WHERE r.status='active'
)
SELECT (SELECT count(*) FROM declared) AS declared_contexts,
       (SELECT count(*) FROM probed)   AS probed_contexts,
       (SELECT count(*) FROM declared d WHERE NOT EXISTS (SELECT 1 FROM probed p WHERE p.ctx=d.ctx))
         AS declared_but_never_probed,
       (SELECT count(*) FROM probed p WHERE NOT EXISTS (SELECT 1 FROM declared d WHERE d.ctx=p.ctx))
         AS probed_but_declared_by_no_rule,
       (SELECT count(*) FROM pairs) AS code_context_pairs,
       (SELECT count(*) FROM pairs x WHERE EXISTS (SELECT 1 FROM probed p WHERE p.ctx=x.ctx))
         AS pairs_probed;
-- 31 / 9 / 22 / 0 / 69 / 34. Zero orphan probes, so every probe is one a rule asked for. 34 of 69 is
-- 49%; the code-level "24 of 30" reads 80% for the same shield.

\echo '=== 0326 §6(b) — every declared context nobody probes, and what waits on it ==='
WITH declared AS (
  SELECT DISTINCT unnest(r.applies_to_actions) AS action_context, r.rule_code, r.severity
    FROM public.ottoq_rules r WHERE r.status='active'
), probed AS (SELECT DISTINCT action_context FROM public.ottoq_rule_evaluations)
SELECT d.action_context,
       count(*) AS codes_declaring_it,
       string_agg(d.rule_code, ', ' ORDER BY d.rule_code) AS codes_waiting_on_it,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ottoq_rule_evaluations e
                                       WHERE e.rule_code = d.rule_code))
         AS of_which_counted_as_evaluated_elsewhere
  FROM declared d LEFT JOIN probed p ON p.action_context = d.action_context
 WHERE p.action_context IS NULL
 GROUP BY 1 ORDER BY codes_declaring_it DESC, 1;
-- task_completion tops it with FIVE codes, three of them scoring as "evaluated" because they fire at
-- task_start -- so sensor liveness is checked before work begins and never after it ends. That column
-- is what the six-unevaluated-codes framing cannot see.

\echo '=== 0326 §7(b) — the dry run that stopped me wiring task_completion tonight ==='
WITH ip AS (
  SELECT vn.vehicle_id, a->>'svc' AS svc, a->>'concurrency' AS conc
    FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
   WHERE vn.status IN ('open','in_progress') AND a->>'status'='in_progress'
), j AS (
  SELECT ip.*, b.stall_id, s.current_vehicle_id
    FROM ip
    LEFT JOIN LATERAL (SELECT bk.stall_id FROM public.ottoq_stall_bookings bk
                        WHERE bk.vehicle_id = ip.vehicle_id AND bk.need_atom = ip.svc
                          AND bk.state IN ('held','active')
                        ORDER BY lower(bk.during) DESC LIMIT 1) b ON true
    LEFT JOIN public.stalls s ON s.id = b.stall_id
)
SELECT conc, count(*) AS in_progress_atoms,
       count(*) FILTER (WHERE stall_id IS NULL)                                   AS would_pass_VACUOUSLY,
       count(*) FILTER (WHERE stall_id IS NOT NULL AND current_vehicle_id = vehicle_id) AS would_pass,
       count(*) FILTER (WHERE stall_id IS NOT NULL AND current_vehicle_id IS DISTINCT FROM vehicle_id)
         AS would_fail
  FROM j GROUP BY conc ORDER BY in_progress_atoms DESC;
-- cabin and exterior atoms have no service stall (0383: exterior work happens AT THE VEHICLE,
-- lane_stalls=NULL), so HW.006 returns "insufficient context" and PASSES. A rule that passes because it
-- could not look is G120 in a different coat.
