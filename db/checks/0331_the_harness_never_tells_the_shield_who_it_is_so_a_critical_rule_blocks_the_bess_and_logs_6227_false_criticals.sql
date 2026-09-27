-- 0331  **`SM.001` fails on 23.2% of everything it judges — 6,298 of 27,144 evaluations, every one
--       `severity='critical'` — and 6,227 of those failures are the test harness booting and tearing down
--       a run. The same root cause makes `SM.006`, which enforces `block` rather than `shadow`, ACTUALLY
--       BLOCK 13 legitimate BESS transitions. The harness never sets `ottoq.actor_type`, so the shield
--       sees `actor=unknown` and refuses.**
--
--       Found while preparing the one-line `arrived_at_gate -> in_service_bay` declaration (G132) that
--       `0412` left behind. The census that was meant to confirm one missing transition found 21, then
--       separated into two populations that want opposite fixes.
--
--       Measured 2026-09-22 13:2x-13:3x UTC (08:2x CT) on the live ledger.
--
-- ══ §1 THE HEADLINE ══════════════════════════════════════════════════════════
--
--     rule                              evals    passed    failed   %fail  enforcement  severity
--     -------------------------------  -------  --------  --------  -----  -----------  --------
--     SM.001.vehicle_transition_valid   27,144    20,846   **6,298** 23.2%  shadow       critical
--     SM.003.stall_transition_validity  25,874    25,874         0    0.0%  shadow       critical
--     SM.006.bess_transition_validity      203       190    **13**   6.4%   **block**    critical
--
-- `0321` found these three probe points and counted them as coverage — *"44,117 evaluations between
-- them, more than `stall_assignment` and `charge_session_start` combined."* That was right, and it is
-- the wiring count again: **one of the three rules disagrees with the engine on a quarter of what it
-- sees, and nothing reads the disagreement**, because `shadow` means log-and-allow.
--
-- ══ §2 TWO POPULATIONS, AND THEY WANT OPPOSITE FIXES ═════════════════════════
--
-- Splitting SM.001's 6,298 failures on whether `offline` is one of the two states:
--
--     run-edge  (to or from `offline`)   **6,227**   98.9%
--     mid-run   (neither is `offline`)      **71**    1.1%
--
-- **The run-edge population is the harness, proven positionally rather than assumed.** Over every
-- `vehicle.state_changed` event carrying a `current_state` diff:
--
--     class         n       at the run's FIRST sim_clock    at its LAST
--     -----------  ------  ----------------------------   -----------
--     offline -> Y  3,197            3,164  (99.0%)               0
--     X -> offline  3,197                0                 3,164  (99.0%)
--     other        20,885               10                   646
--
-- Perfectly symmetric, perfectly edge-aligned, in both directions. Every run boots its fleet out of
-- `offline` on its first tick and returns it to `offline` on its last. **This is NOT `0329`'s
-- contamination** — that was a SoC-only write with no `current_state` in its diff, so it never appeared
-- in a transition census, and post-`0421` runs still show 1,408 of each. Checked, not assumed.
--
-- The writers, from source:
--   * boot     — `twin.ottoq_sim_prime_deployment` (writes `deployed` and `en_route_to_depot`)
--   * teardown — `public.ottoq_tick_invariance_reset_fleet` (writes `offline`, and the BESS `standby`)
--
-- **Neither sets `ottoq.actor_type`**, so the row trigger falls back to `'unknown'` and then — because a
-- run IS active during these writes — promotes it to `'ottoq_engine'` (the line is quoted in §3). So the
-- harness's lifecycle writes are recorded as **the ENGINE doing something the state machine forbids**,
-- and 6,227 critical failures accrue against a component that did not make them.
--
-- ══ §3 AND ON THE BESS IT IS NOT SHADOW, IT BLOCKS ═══════════════════════════
--
-- `SM.006` is `enforcement='block'`. Its 13 failures read, verbatim:
--
--     "actor unknown not authorized for bess transition charging → standby"      11   enforcement_taken=blocked
--     "actor unknown not authorized for bess transition discharging → standby"    2   enforcement_taken=blocked
--
-- **Both transitions ARE declared** — `charging -> standby` on trigger `stop_charge`, `discharging ->
-- standby` on `stop_discharge`, both allowing `bess_controller` and `ottoq_engine`. The identical
-- transitions pass 91 and 2 times respectively when the actor is `ottoq_engine`. **So this is the actor
-- check firing, not the transition catalog**, and the first reading of it — "two undeclared BESS
-- transitions" — was wrong; the catalog was read before the reason string was.
--
-- **And the discriminator is exact, which is better than the timing story I first wrote.** Partitioning
-- every `bess_state_change` evaluation on whether its row carries a run:
--
--     sim_run_id      actor          passed   n
--     -------------  -------------  -------  ----
--     NULL           unknown        false     13
--     not null       ottoq_engine   true     190
--
-- **13 of 13 blocked rows have `sim_run_id IS NULL`; 190 of 190 passing rows have a run.** No exceptions
-- either way, across both depots (11 on the `grid_smoke` fixture, 2 on the twin).
--
-- The cause is one line in the row trigger, and it is a fallback rather than an omission:
--
--     v_actor_type := COALESCE(NULLIF(current_setting('ottoq.actor_type', TRUE), ''), 'unknown');
--     v_run        := ottoq.ottoq_active_sim_run_id();
--     IF v_actor_type = 'unknown' AND v_run IS NOT NULL THEN
--       v_actor_type := 'ottoq_engine';                  -- <- all three triggers do this
--     END IF;
--
-- So **the shield's notion of who acted is derived from whether a run happens to be active**, not from
-- anything the caller said. When a run is active the harness is silently relabelled `ottoq_engine` (which
-- is why §2's 6,227 lifecycle failures are all attributed to the engine); when one is not, the same
-- caller reads `unknown` and a `block` rule refuses it. One missing `set_config` produces a
-- MISATTRIBUTION in one case and a BLOCK in the other, and which one you get depends on a cached GUC.
--
-- This is the first `block` enforcement observed actually firing in this engine, and what it blocks is
-- the harness resetting the battery. Nothing downstream is known to depend on that write succeeding, so
-- no damage is claimed — but a critical rule refusing a legitimate write is not a thing to leave in
-- place, and it is exactly the surface a real `bess_controller` would arrive on.
--
-- **What I checked and it is NOT true:** that `0421` made this systematic. The sentinel it added makes
-- `ottoq_active_sim_run_id()` return NULL during the reset, so in principle every arm should now take the
-- `unknown` branch. Measured, post-`0421` produced **2** such rows, not one per arm — because the trigger
-- only fires when the state actually CHANGES, and the twin depot's BESS is usually already `standby` at
-- reset. Predicting the count and then counting it is the only way that distinction surfaces.
--
-- ══ §4 THE 71 THAT ARE REAL ENGINE BEHAVIOUR ═════════════════════════════════
--
--     arrived_at_gate      -> in_detail_bay            22
--     arrived_at_gate      -> in_service_bay           17   <- G132, the one this census set out to find
--     charging_l2          -> staged_for_departure     14
--     staged_for_departure -> charge_complete_holding   10
--     staged_awaiting_service -> charge_complete_holding 4
--     charge_complete_holding -> in_service_bay          4
--
-- All six are ordinary depot operations and all six are `actor='ottoq_engine'`:
--
--   * **gate -> detail bay / service bay.** `0412` declared `arrived_at_gate -> in_wash_bay` with the
--     reasoning *"the gate could dispatch to a CHARGER but not to a BAY"* — and then declared only the
--     wash bay, leaving the other two bays with the identical omission. Immediate dispatch from the gate
--     is normal triage: a vehicle arriving with a known need goes straight to the bay rather than
--     queueing. This is the same finding `0412` made, one bay type short.
--   * **`charging_l2 -> staged_for_departure`.** `0412` declared `charge_complete_holding ->
--     staged_for_departure`; this is the same decision taken one step earlier, when a charging vehicle
--     with no outstanding atoms is called for departure before the charge completes.
--   * **`* -> charge_complete_holding` from staged states.** A vehicle already at target SoC being moved
--     into the post-charge holding pool without re-entering a charger.
--
-- ══ §5 THE FIX — AND I DESIGNED THE WRONG ONE FIRST, WHICH IS THE PART TO READ ═
--
-- **First design, rejected: invent a `twin_harness` actor**, set it in the two writers, declare the
-- lifecycle transitions for it alone, and keep `ottoq_engine` out so the shield still fails an engine
-- that powers a vehicle down mid-run. It is tidy, it preserves the rule's teeth, and it is wrong.
--
-- **It is wrong because of this repo's own doctrine.** `ottoyarddepot-sim/AGENTS.md`: *"The swap test is
-- the pitch: unplug the twin, plug in a real depot's telemetry, and OTTO-Q cannot tell the difference.
-- If you build a code path that only works because this is a simulation, you have broken the pitch."* A
-- `twin_harness` actor is a simulation-only branch in the SHIELD — the one layer that must be identical
-- in both worlds. And the catalog already disagrees with the tidy design: **`offline ->
-- arrived_at_gate`, `offline -> staged_awaiting_service` and `offline -> staged_for_departure` are
-- already declared, for `ottoq_engine`**, on triggers named `power_on_at_depot`, `seed_into_queue` and
-- `seed_ready`. Someone already decided boot is an engine action.
--
-- **And the physical reading settles it.** Every one of the 6,227 is a real-world event, not an artifact:
-- `charging_l2 -> offline` (448) is a charging vehicle losing power or comms; `tow_requested -> offline`
-- (1) is a towed vehicle powered down; `offline -> deployed` is a vehicle powering on already out on the
-- road, which is `0412`'s own phrasing. **A vehicle can power down from any state and power up into the
-- state it is physically in.** The catalog not admitting that is a gap in the catalog, not an artifact
-- of the harness — the harness merely exercises it 3,197 times per census, which is why it showed up
-- here first.
--
-- **The fix that survives both readings:**
--
--   1. **Declare power-down and power-up as ordinary transitions**, `allowed_actor_types =
--      {ottoq_engine, av_vehicle}`, triggers `power_down` and `power_on_into_state`, across every vehicle
--      state — not only the 15 pairs this census happened to observe, because the reset resets whatever
--      state a vehicle is in and next month's scenario will put it in a different one.
--   2. **Declare the six of §4 for `ottoq_engine`**, extending `0412`'s gate-dispatch reasoning to the
--      two bay types it stopped short of.
--   3. **Make the actor label independent of whether a run is active** (§3), so a `block` rule stops
--      refusing the BESS reset. This is the only part that changes what the engine is ALLOWED to do.
--
-- **What must NOT be claimed after the fix:** that SM.001's pass rate rising from 76.8% to ~100% is
-- coverage improving. It is the same shield, judged against a catalog that finally describes the system
-- it is judging. The genuine change in protection is (3) alone.
--
-- **And the residual to state plainly:** after (1), an engine that powers a vehicle down mid-run will no
-- longer fail SM.001. That is the price of not building a simulation-only actor, and it is the right
-- trade because SM.001 is `shadow` — it never blocked that write anyway — while the thing it *was*
-- doing, drowning 71 real findings in 6,227 false ones, is a live cost to anyone reading the ledger.

\echo '=== 0331 §1 — the three state-change rules, pass/fail, with their enforcement ==='
SELECT re.rule_code,
       count(*)                                    AS evaluations,
       count(*) FILTER (WHERE re.passed)           AS passed,
       count(*) FILTER (WHERE NOT re.passed)       AS failed,
       round(100.0*count(*) FILTER (WHERE NOT re.passed)/count(*),1) AS pct_failed,
       count(*) FILTER (WHERE NOT re.passed
             AND (re.context->>'to_state'='offline' OR re.context->>'from_state'='offline')) AS failed_run_edge,
       count(*) FILTER (WHERE NOT re.passed
             AND re.context->>'to_state'<>'offline' AND re.context->>'from_state'<>'offline') AS failed_mid_run,
       (SELECT r.enforcement FROM public.ottoq_rules r
         WHERE r.rule_code=re.rule_code AND r.status='active' LIMIT 1) AS enforcement,
       (SELECT r.severity    FROM public.ottoq_rules r
         WHERE r.rule_code=re.rule_code AND r.status='active' LIMIT 1) AS severity
  FROM public.ottoq_rule_evaluations re
 WHERE re.action_context IN ('vehicle_state_change','stall_state_change','bess_state_change')
 GROUP BY re.rule_code ORDER BY evaluations DESC;
-- SM.001 27,144 / 6,298 failed (23.2%), of which 6,227 run-edge and 71 mid-run. SM.003 clean.
-- SM.006 203 / 13 failed, and its enforcement column is the one to read: `block`.

\echo '=== 0331 §2 — the run-edge population IS the harness: 99% at a run boundary, both directions ==='
WITH e AS (
  SELECT e.sim_run_id, e.sim_clock_at,
         e.payload->'diff'->'current_state'->>'from' AS f,
         e.payload->'diff'->'current_state'->>'to'   AS t,
         min(e.sim_clock_at) OVER (PARTITION BY e.sim_run_id) AS run_first,
         max(e.sim_clock_at) OVER (PARTITION BY e.sim_run_id) AS run_last
    FROM public.ottoq_events e
   WHERE e.event_type='vehicle.state_changed' AND e.payload->'diff' ? 'current_state'
)
SELECT CASE WHEN t='offline' THEN 'X -> offline'
            WHEN f='offline' THEN 'offline -> Y' ELSE 'other' END AS klass,
       count(*) AS n,
       count(*) FILTER (WHERE sim_clock_at = run_first) AS at_run_first_tick,
       count(*) FILTER (WHERE sim_clock_at = run_last)  AS at_run_last_tick
  FROM e GROUP BY 1 ORDER BY 1;
-- offline->Y: 3,197 / 3,164 at first / 0 at last.  X->offline: 3,197 / 0 / 3,164.  Symmetric and
-- edge-aligned in both directions -- a boot and a teardown, not engine behaviour.

\echo '=== 0331 §2b — and it is NOT 0329s contamination: post-0421 runs still carry both ==='
WITH r AS (SELECT sim_run_id, (started_at > '2026-09-22 12:56:37+00') AS post_0421 FROM public.ottoq_sim_runs),
     e AS (SELECT sim_run_id,
                  payload->'diff'->'current_state'->>'from' f,
                  payload->'diff'->'current_state'->>'to'   t
             FROM public.ottoq_events
            WHERE event_type='vehicle.state_changed' AND payload->'diff' ? 'current_state')
SELECT r.post_0421, count(DISTINCT r.sim_run_id) AS runs,
       count(*) FILTER (WHERE e.t='offline') AS x_to_offline,
       count(*) FILTER (WHERE e.f='offline') AS offline_to_y
  FROM r JOIN e ON e.sim_run_id = r.sim_run_id GROUP BY 1 ORDER BY 1;
-- 1,408 of each on post-0421 runs. 0421 removed a SoC-only write with NO current_state in its diff,
-- which is why it never showed up in a transition census at all (0329 §2).

\echo '=== 0331 §3 — SM.006 blocks on the ACTOR, not the catalog. Read the reason, not the table ==='
SELECT re.passed, re.reason, re.enforcement_taken, re.context->>'actor_type' AS actor, count(*) n
  FROM public.ottoq_rule_evaluations re
 WHERE re.action_context='bess_state_change'
 GROUP BY 1,2,3,4 ORDER BY n DESC;
-- "charging → standby" appears TWICE: 91 times allowed as ottoq_engine, 11 times BLOCKED as unknown.
-- The transition is declared. The actor is not. My first reading called these two undeclared BESS
-- transitions -- the catalog was read before the reason string was.

\echo '=== 0331 §3b — the declaration proving the transition is legal, so the actor is the whole cause ==='
SELECT from_state, to_state, trigger_event, allowed_actor_types, status
  FROM public.ottoq_state_transitions
 WHERE entity_kind='bess' AND to_state='standby' AND from_state IN ('charging','discharging')
 ORDER BY from_state;
-- Both active, both allowing bess_controller and ottoq_engine. Neither allows `unknown`, and nothing
-- in the reset path ever sets ottoq.actor_type.

\echo '=== 0331 §3c — the discriminator, with no exceptions in either direction ==='
SELECT (re.sim_run_id IS NULL) AS run_is_null, re.context->>'actor_type' AS actor, re.passed,
       count(*) n, count(DISTINCT re.depot_id) AS depots
  FROM public.ottoq_rule_evaluations re
 WHERE re.action_context='bess_state_change'
 GROUP BY 1,2,3 ORDER BY 1,3;
-- NULL run -> unknown -> blocked, 13 of 13. Run present -> ottoq_engine -> allowed, 190 of 190.
-- The shield's idea of WHO acted is derived from whether a run is active, not from what the caller said.

\echo '=== 0331 §3d — and all three row triggers share that promotion, so it is a pattern not a slip ==='
WITH s AS (
  SELECT p.proname,
         regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname IN ('ottoq_vehicles_state_change','ottoq_stalls_state_change','ottoq_bess_units_state_change')
)
SELECT proname,
       (position('current_setting(''ottoq.actor_type''' in src) > 0) AS reads_actor_guc,
       (src ~ 'v_actor_type\s*:=\s*''ottoq_engine''')                AS promotes_unknown_to_engine
  FROM s ORDER BY proname;
-- true/true for all three. The promotion is deliberate and consistent; what is missing is any caller
-- that declines it by saying who it actually is.

\echo '=== 0331 §4 — the 71 that are real engine behaviour and want declaring ==='
SELECT re.rule_code,
       (re.context->>'from_state')||' -> '||(re.context->>'to_state') AS transition,
       re.context->>'actor_type' AS actor, count(*) n
  FROM public.ottoq_rule_evaluations re
 WHERE re.action_context='vehicle_state_change' AND NOT re.passed
   AND re.context->>'to_state' <> 'offline' AND re.context->>'from_state' <> 'offline'
 GROUP BY 1,2,3 ORDER BY n DESC;
-- Six transitions, all actor=ottoq_engine. Two of them are 0412's own finding one bay type short:
-- it declared arrived_at_gate -> in_wash_bay and left in_detail_bay and in_service_bay undeclared.

\echo '=== 0331 §5 — the harness writers, from source, comment-stripped ==='
WITH s AS (
  SELECT n.nspname||'.'||p.proname AS fn,
         regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE (n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet')
      OR (n.nspname='twin'   AND p.proname='ottoq_sim_prime_deployment')
)
SELECT fn,
       (position('ottoq.actor_type' in src) > 0)             AS sets_the_actor_guc,
       (src ~ 'current_state\s*=\s*''offline''')             AS writes_offline,
       (src ~ 'current_state\s*=\s*''deployed''')            AS writes_deployed,
       (src ~ 'current_state\s*=\s*''standby''')             AS writes_bess_standby
  FROM s ORDER BY fn;
-- sets_the_actor_guc is FALSE for both. That single column is the entire finding.
