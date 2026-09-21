-- 0307  **SM.006 HAS A CALLER.** G96 step 2 is done: `db/migrations/0399` (applied
--       `20260921122812`) gives `ottoq_bess_units` the first trigger it has ever had, and the
--       BESS state machine is evaluated for the first time since the rule was written. **And the
--       first thing the probe found is a population my before-measurement could not have shown —
--       a BESS state change with no active run, which fails the role gate.**
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), except where a
-- count is explicitly about the probe's own output, which is not depot-predicated because the
-- recert sweep also exercises the grid fixture (see §4).
-- Measured 2026-09-21 12:29–12:33 UTC (07:29–07:33 CT).
--
-- ══ 1. IT FIRED, IMMEDIATELY, AND WITHOUT ANY HELP FROM ME ═════════════════
--
-- `0399` sets `forces_recert TRUE`, which started `ottoq_recert_runner` on its own. That sweep
-- runs determinism PAIRS, each of which drives the battery, so within three minutes of the
-- migration applying:
--
--   evaluations at `bess_state_change`     **20**
--   passed / failed                        **19 / 1**
--   distinct sim runs                      **6**
--   window                                 12:29:00 → 12:31:00 UTC
--
-- **That is a better functional test than the one I was writing when it happened.** My own probe
-- — a hand-driven `standby → charging → discharging` on `NASH-BESS-01`, meant to be rolled back —
-- blocked on a row lock held by the recert runner and was cancelled. The sweep had already
-- exercised the trigger across six runs and two scenarios. The lesson is small and worth keeping:
-- **when a change starts the machinery that would test it, watch the machinery rather than
-- racing it.**
--
-- ══ 2. THE BEFORE-MEASUREMENT HELD FOR IN-RUN TRANSITIONS, AND MISSED A WHOLE POPULATION ══
--
-- `0399` §1 predicted 6 of 6 transition shapes passing, derived from every transition in
-- `bess_snapshots` at this depot (28,735 of them). Measured after:
--
--   in a run?   actor          transition               passed   n
--   ───────────────────────────────────────────────────────────────
--   yes         ottoq_engine   standby → charging       true     10
--   yes         ottoq_engine   charging → standby       true      9
--   **no        unknown        charging → standby       FALSE     1**
--
-- **19 of 19 in-run transitions pass exactly as predicted. The one failure is not a
-- state-machine violation at all** — its reason reads *"actor unknown not authorized for bess
-- transition charging → standby"*, and the same transition passes nine times in the rows above
-- it. It failed the **role gate**, on a transition that occurred with `sim_run_id NULL`.
--
-- **WHY THE PREDICTION COULD NOT HAVE CAUGHT IT, which is the transferable part.** §1 was derived
-- from `bess_snapshots`, and **snapshots are written by the TICK**. A transition performed by
-- setup or teardown — one of the arm/reset writers, between pairs, before a run is `running` —
-- never lands in that series. So the history I measured is a history of *in-run* transitions, and
-- a trigger on the TABLE sees every writer, including the nine `0399` §2 lists that the tick is
-- not. **A probe placed on a table has a wider population than any history written by one of that
-- table's writers**, and a before-measurement taken from the narrower one will always look
-- cleaner than the after. That is the same shape as `0292` (an instrument pointed at one path,
-- read as covering all of them) arriving from the opposite direction.
--
-- ══ 3. AND IT IS EXACTLY THE TRAP `0399` §5 NAMED, FROM A DIRECTION I DID NOT PREDICT ══
--
-- `0399` §5 records that `→ fault` is the one transition the `ottoq_engine` attribution would
-- refuse, and says the right answer would be for the faulting writer to set `ottoq.actor_type`
-- rather than for the matrix to widen. **The mechanism is the one that fired; the transition is
-- not.** The attribution reads:
--
--     IF v_actor_type = 'unknown' AND v_run IS NOT NULL THEN v_actor_type := 'ottoq_engine';
--
-- — deliberately conditional on a run, following `0387`, because outside a run the actor
-- genuinely is unidentified and inventing one would be worse than admitting none. So a write
-- made when `ottoq.ottoq_active_sim_run_id()` returns NULL keeps `unknown`, and **no bess row in
-- `ottoq_state_transitions` admits `unknown`** (`0387` measured 0 of 82 across all entity kinds).
--
-- **THE PROBE IS TELLING THE TRUTH.** Something changed a battery's power state and nothing in
-- the database can say what. That is a finding about attribution, not about legality, and the
-- honest options are two:
--
--   (a) the writer sets `ottoq.actor_type` around its write — the `0399` §5 answer, correct and
--       narrow, and it needs the writer identified first (ten functions UPDATE this table; the
--       failing row is 12:30:00 UTC with `sim_run_id NULL`, which points at the arm/reset family
--       rather than at `twin.ottoq_sim_bess_step`);
--   (b) nothing changes, and the row stands as the record that an unattributed state change
--       happened — which is what a MEASURE-ONLY probe is for.
--
-- **WHAT MUST NOT HAPPEN is widening the matrix to admit `unknown`.** That would make the rule
-- pass by deleting the question, and it is `0231`'s defect in rule form: a declaration arranged
-- so the mechanism it describes can never disagree with it.
--
-- **AND IT IS A PROMOTION BLOCKER, WHICH IS PRECISELY WHY IT WAS WIRED MEASURE-ONLY.** SM.006 is
-- `critical`/`enforcement='block'`. Promoted today, it would refuse whatever that 12:30:00 writer
-- was doing. Nothing was blocked — the probe reads and logs, and `0399` never reads `would_block`
-- — so 2.9a's doctrine earned its keep on the first run: MEASURED first, ENFORCED only after a
-- flagship round, and the round found something in three minutes.

SELECT (sim_run_id IS NOT NULL)                                           AS in_a_run,
       context->>'actor_type'                                             AS actor,
       (context->>'from_state')||' -> '||(context->>'to_state')           AS transition,
       passed,
       count(*)                                                           AS n
  FROM public.ottoq_rule_evaluations
 WHERE action_context = 'bess_state_change'
 GROUP BY 1,2,3,4 ORDER BY 1,3;

SELECT evaluated_at, rule_code, passed, reason, context
  FROM public.ottoq_rule_evaluations
 WHERE action_context = 'bess_state_change' AND NOT passed
 ORDER BY evaluated_at DESC LIMIT 5;

-- ══ 4. THE RECERT SWEEP, WHICH IS ALSO THE PROOF THE NEW WRITER IS DETERMINISTIC ══
--
-- `0399`'s `forces_recert TRUE` was justified narrowly: the rules atom is one of the fourteen,
-- and a NEW WRITER into an enforced atom must be proven to write identically in BOTH arms before
-- the canon rests on it. The sweep is that proof, and it is passing as it goes — at 12:31 UTC,
-- **3 of 9 columns re-certified, outcome `passed`, `satisfies_floor` true**, the remaining six
-- correctly marked *"stale: predates the recert floor"*:
--
--   busy_day/171717/12t   12:31:00  passed  current
--   grid_smoke/424242/6t  12:30:00  passed  current
--   grid_smoke/239001/6t  12:29:00  passed  current
--   ...six more from 03:25–03:49 UTC, stale and queued
--
-- Note the grid fixture is one of the two columns exercising the `0132` site power gate, so the
-- BESS is driven hard there — which is why the probe's first evidence arrived from it. It is also
-- why the evaluation counts in §1–§2 are NOT depot-scoped: rule 8 governs what we TEST AGAINST,
-- and this section is measuring the certification apparatus rather than the depot.
--
-- **THE COST, STATED BECAUSE `0397` WAS CAUGHT OUT BY EXACTLY THIS.** All nine columns were
-- `current` and satisfying floor at 03:19–03:49 UTC, so the floor had fully drained and this
-- migration costs **nine** re-certifications, not zero. `0397` §1b called a half-drained floor a
-- free window and was wrong by five. A window that is draining is not a window; a drained one is
-- not either. Batching `forces_recert` changes is free only when they land TOGETHER, before the
-- sweep starts clearing.

SELECT scenario, seed, ticks, status, satisfies_floor, outcome, certified_at
  FROM public.ottoq_determinism_canon ORDER BY certified_at DESC NULLS LAST;

-- ══ 5. WHERE G44 STANDS NOW ════════════════════════════════════════════════
--
-- **24 of 30 declared rules, at NINE probe points** — `bess_state_change` joins `task_start`,
-- `stall_assignment`, `charge_session_start`, `redeployment`, `policy_write`, `bess_dispatch`,
-- `vehicle_state_change` and `stall_state_change`. `0273`'s caveat travels with the number and is
-- not optional: **evaluated is a WIRING count, not a protection count**, and this file is a fresh
-- demonstration of the gap between them — SM.006 is now wired, is `critical`/`block`, and binds
-- nothing, because `0399` deliberately does not read `would_block`.
--
-- Six codes remain unevaluated, three of them `critical`: HW.006 (physical presence at
-- completion), SM.004 (role gating), SM.005 (audit note on override), SLA.002, TW.002, TW.004.
-- `0387` §5 gives the reason for each and none has changed: HW.006 and SLA.002 need probe points
-- that do not exist (task completion, arrival); SM.004 gates actions the twin may never perform,
-- and wiring a probe for an action nobody takes would be another "exists and never called";
-- SM.005 wants a trigger on the decision ledger and its population may be zero, which must be
-- established before it is measured.

SELECT r.rule_code, r.severity, r.enforcement,
       (SELECT count(*) FROM public.ottoq_rule_evaluations e WHERE e.rule_code = r.rule_code) AS evaluations
  FROM public.ottoq_rules r
 WHERE r.status = 'active'
 ORDER BY (SELECT count(*) FROM public.ottoq_rule_evaluations e WHERE e.rule_code = r.rule_code), r.rule_code;

-- OPEN-ITEM: SM.006's first three minutes found a BESS state change with sim_run_id NULL and actor 'unknown', which fails the role gate -- 19 of 19 in-run transitions pass under ottoq_engine and this one does not, because 0399's attribution deliberately refuses to invent an actor outside a run and no bess transition admits 'unknown'. The probe is telling the truth: something changed a battery's power state and nothing can say what. The writer is not yet identified (ten functions UPDATE ottoq_bess_units; the row's 12:30:00 UTC timestamp with no run points at the arm/reset family, not the tick). Until it is, SM.006 cannot be promoted from MEASURE-ONLY to block, because promotion would refuse that writer. Widening the matrix to admit 'unknown' is forbidden -- it would make the rule pass by deleting the question. Tracked as G111.

-- ══════════════════════════════════════════════════════════════════════════════
-- ══ 6. G111's WRITER IS IDENTIFIED (2026-09-21 16:2x UTC / 11:2x CT), AND THE
--       FIX IS DELIBERATELY NOT APPLIED YET. The reason is arithmetic.
-- ══════════════════════════════════════════════════════════════════════════════
--
-- §3 named the arm/reset family as the suspect. It is **`public.ottoq_tick_invariance_reset_fleet`**,
-- and three facts converge on it:
--
--   * **Timing.** The single failing evaluation is at **12:30:00.178**, and two cert runs
--     (`c951e4b2`, `1cf2c17a`) carry `started_at = ended_at = 12:30:00` — the pair boundary, the
--     one moment `ottoq.ottoq_active_sim_run_id()` returns NULL.
--   * **The write.** Of the three functions that write `standby` into `ottoq_bess_units`, this is
--     the only fixture reset, and its own comment states the intent:
--     *"0397 / G96. WAS 'idle' … The fixture reset must leave the BESS in a state the transition
--     matrix recognises, or the first commanded change out of it is unrepresentable."*
--     `current_state = 'standby'` — which from `charging` is exactly the observed transition.
--   * **The callers.** `ottoq_determinism_pair`, `ottoq_ab_pair`, `ottoq_determinism_pair_replay`,
--     `ottoq_tick_invariance_arm` — the pair rig, i.e. precisely what the `0399` recert sweep runs.
--
-- And **none of the three `standby` writers sets `ottoq.actor_type`**, nor calls
-- `ottoq_active_sim_run_id`. So the probe sees `unknown`, no `bess` transition admits `unknown`
-- (`0387`: 0 of 82), and the role gate fails. **The probe is right, and the rate fits**: one such
-- write per boundary against 92 evaluations, which is why this is a single event rather than a
-- pattern.
--
-- ══ 6a. WHY IT IS NOT FIXED IN THIS PASS, AND THE NUMBER IS THE ARGUMENT ════
--
-- The fix is one line — have that writer set `ottoq.actor_type` around its BESS update, per
-- `0399` §5. But the probe's logged `context` is part of `ottoq_rule_evaluations`, and **the rules
-- atom is one of the fourteen**. Changing what that row records moves the atom, so the change is
-- `forces_recert` **TRUE** and costs **nine re-certifications** — to alter one evaluation row
-- written by a test fixture, on a MEASURE-ONLY probe that blocks nothing.
--
-- **And `0397` §1b is explicit about the batching rule:** forces_recert changes are free only when
-- they land TOGETHER, before the sweep starts clearing. The canon drained at 12:58 today. A
-- granularity decision on G112 (`0308` §8f) would itself force a recert, and if it is taken this
-- change rides with it for nothing. Spending nine pairs now, and nine again later, is the exact
-- mistake `0397` recorded against itself.
--
-- **So: identified, recorded, and queued to batch.** Not deferred for lack of a fix — deferred
-- because landing it alone costs more than it is worth and landing it with G112 costs nothing.
--
-- ══ 6b. AND THE ACTOR TO USE IS A REAL QUESTION, NOT A BLANK TO FILL ═══════
--
-- Three options, and the wrong one is available and tempting:
--   (a) `ottoq_engine` — matches `0387`'s vehicle/stall precedent and passes the gate, but it is
--       **not true**: a certification fixture resetting the world is not the engine deciding.
--   (b) a new declared actor (`cert_harness`) added to the `bess` matrix rows — honest, and it
--       widens the matrix for a fixture, which is adjacent to the `0231` move this repo forbids.
--   (c) leave it — the row stands as a true record that a fixture wrote engine state with no
--       attribution, on a probe that blocks nothing.
--
-- (a) is the one to be careful about. It would make the finding disappear by asserting something
-- false, which is how a rule stops being able to disagree with the mechanism it describes.
--
-- **AND ONE THING WORTH NOTING IN PASSING, because C5 has been planned around its absence:**
-- `public.ottoq_ab_pair` EXISTS and calls this same reset. `db/checks/0145` established that
-- `ottoq_ab_runs` is an empty instrument with no writer; whether `ottoq_ab_pair` is the missing
-- writer or another well-shaped shell is not established here and is not assumed.

SELECT 'writer'  AS what, 'public.ottoq_tick_invariance_reset_fleet' AS detail
UNION ALL
SELECT 'callers', string_agg(n.nspname||'.'||p.proname, ', ' ORDER BY p.proname)
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.prosrc ~* 'ottoq_tick_invariance_reset_fleet' AND p.proname <> 'ottoq_tick_invariance_reset_fleet'
UNION ALL
SELECT 'standby writers that set ottoq.actor_type',
       COALESCE(string_agg(n.nspname||'.'||p.proname, ', '), '(none -- that is the finding)')
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE p.prosrc ~* 'UPDATE\s+(public\.)?ottoq_bess_units' AND p.prosrc ~* 'standby'
   AND p.prosrc ~* 'ottoq\.actor_type';

-- OPEN-ITEM: G111's writer is IDENTIFIED as public.ottoq_tick_invariance_reset_fleet -- the fixture reset called by ottoq_determinism_pair / ottoq_ab_pair / ottoq_determinism_pair_replay / ottoq_tick_invariance_arm, which sets the BESS to 'standby' at the pair boundary where ottoq_active_sim_run_id() is NULL, and sets no ottoq.actor_type. None of the three standby writers sets it. The one-line fix is NOT applied in this pass on purpose: the probe's logged context lives in ottoq_rule_evaluations, the rules atom is one of the fourteen, so the change is forces_recert TRUE and costs NINE re-certifications to alter one row written by a test fixture on a measure-only probe. 0397 §1b's rule says batch it -- a G112 granularity decision would force a recert anyway and this rides along for nothing. Also unresolved and NOT a blank to fill: which actor to claim. 'ottoq_engine' passes the gate but is false (a cert fixture is not the engine deciding) and would make the finding vanish by asserting something untrue. Tracked as G111.
