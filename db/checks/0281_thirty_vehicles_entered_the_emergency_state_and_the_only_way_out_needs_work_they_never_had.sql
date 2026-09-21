-- 0281  G95: THIRTY VEHICLES ENTERED `emergency_staged` ON ONE RUN AND NONE LEFT IT. THE
--       EXIT EXISTS AND RUNS — IT IS CONDITIONED ON INTERRUPTED WORK, AND TWENTY-NINE OF
--       THE THIRTY HAD NONE.
--
-- Read-only. MEASURED, NOT FIXED. Scope: twin depot 11111111-1111-1111-1111-111111111111
-- (rule 8), completed demo run `562bf027-6c74-4cb1-9d96-722af13b2fcc` (busy_day, seed
-- 777777, 1,241 ticks, 620 decision snapshots). Snapshot frames and visits are
-- `class='engine'` and purge with the run.
--
-- ══ 1. THE MEASUREMENT ═════════════════════════════════════════════════════
--
--   vehicles that entered `emergency_staged`        **30**   (of 116 homed = 26%)
--   still in it at their last observed tick         **30**
--   that ever left it during the run                **0**
--   mean ticks held                                 **243** of 620
--   max ticks held                                  **379**
--
-- `emergency_staged` also appears in **no** admission list in
-- `twin.ottoq_sim_advance_visit_atoms`, so while a vehicle is there no in-place atom can be
-- started for it either. It is a full stop, not a slow lane.
--
-- ══ 2. THE CAUSE, AND TWO HYPOTHESES I FORMED AND DISPROVED FIRST ═══════════
--
-- **Disproved (a): "the exit is human-only and the twin has no humans."** The declared
-- machine does say so — `ottoq_state_transitions` permits `emergency_staged → out_of_service`
-- and `→ staged_awaiting_service` to `command_center_operator` and `depot_supervisor` only,
-- **not** to `ottoq_engine`, while entry from `arrived_at_gate`/`staged_for_departure` IS
-- permitted to `ottoq_engine`. A state the engine may enter and only a human may leave is a
-- real asymmetry and worth knowing. It is not the cause: the actual exit is
-- `ottoq.ottoq_readmit_resumed_visits`, which exists, has callers, and runs.
--
-- **Disproved (b): "the approval gate is permanently closed."** `ottoq_ops_approvals` holds
-- 1,792 `declined` and 203 `expired` and **zero** `approved`, which reads like a 0% grant
-- rate. It is not one. **81 approvals were granted** — every one carries
-- `payload->>'expired_from' = 'approved'` with `expired_reason='run_ended'`, because
-- `ottoq_sim_release_depot` deliberately expires them at teardown. Migration `0097`'s own
-- words: *"no approval outlives its run. Readers filter on vehicle/type/status only, so a
-- surviving 'approved' row is readable by the NEXT run's gates — the tick-2 divergence
-- channel of the 0046 determinism pair. Prior status kept in payload."* The provenance was
-- in the row the whole time; reading `status` alone and stopping is the same error as
-- reading a roster as an occupancy census. And the 1,717 dominant declines are
-- `gate_reason='automated_reassignment'` meeting the zone-C allowlist, which is deliberate
-- policy — reroute is forbidden unless something is actually wrong.
--
-- **THE ACTUAL CAUSE.** `ottoq_readmit_resumed_visits` selects a vehicle only when ALL of:
--
--   vh.current_state = 'emergency_staged'
--   vh.config->'exception'->>'status' = 'retrieved_staged'
--   an OPEN visit with  n.meta ? 'reopen'   -- "proves this visit was actually cut short"
--   that visit still has atoms not done/cancelled
--
-- Of the 30: **1 ever had a visit carrying `meta ? 'reopen'`.** The readmission path is for
-- *"a vehicle resuming ITS OWN interrupted work"* — its own comment says so — and 29 of the
-- 30 had no interrupted work to resume. **So the exit is not broken; it does not apply.** A
-- vehicle that reaches `emergency_staged` without work in flight has no route back at all.

WITH em AS (
  SELECT DISTINCT (e->>'id')::uuid AS vid
    FROM public.ottoq_decision_snapshots s
   CROSS JOIN LATERAL jsonb_array_elements(s.frame->'vehicles') e
   WHERE s.sim_run_id = '562bf027-6c74-4cb1-9d96-722af13b2fcc'
     AND e->>'state' = 'emergency_staged'
)
SELECT count(*) AS vehicles_ever_emergency,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_visit_needs n
          WHERE n.vehicle_id = v.id AND n.meta ? 'reopen'
            AND n.sim_run_id = '562bf027-6c74-4cb1-9d96-722af13b2fcc')) AS had_reopened_visit,
       'the readmission gate requires a reopened visit; 29 of 30 never had one' AS finding
  FROM em JOIN public.vehicles v ON v.id = em.vid;

SELECT 'INTO' AS direction, from_state AS other_state, allowed_actor_types
  FROM public.ottoq_state_transitions
 WHERE entity_kind='vehicle' AND status='active' AND to_state='emergency_staged'
UNION ALL
SELECT 'OUT OF', to_state, allowed_actor_types
  FROM public.ottoq_state_transitions
 WHERE entity_kind='vehicle' AND status='active' AND from_state='emergency_staged'
 ORDER BY 1, 2;

SELECT status,
       COALESCE(payload->>'expired_from','(not set)')   AS expired_from,
       COALESCE(payload->>'expired_reason','(not set)') AS expired_reason,
       count(*) AS n
  FROM public.ottoq_ops_approvals
 WHERE payload->'decision'->>'verdict' = 'approved'
 GROUP BY 1,2,3 ORDER BY 4 DESC;

-- ══ 3. WHAT IS NOT ESTABLISHED, SAID PLAINLY ═══════════════════════════════
--
-- * **How the 30 entered.** `twin.ottoq_sim_vehicle_exception_handler` sets
--   `emergency_staged` from `tow_requested` on successful tow retrieval, together with
--   `config.exception.status='retrieved_staged'`. `tow_requested → emergency_staged` is NOT
--   a declared transition (declared entries are from `arrived_at_gate` and
--   `staged_for_departure`), so this is likely another G94 instance — but the SM.001 probe
--   only began logging after `0387`, and the shadow window so far covers short recert pairs
--   rather than a demo run, so it has not yet observed this transition. **Unverified.**
-- * **Their exception status during the run.** All 30 now read no `config->'exception'` block
--   at all, but that is measured AFTER teardown and teardown may clear it. The 1-of-30
--   reopened-visit figure is NOT a teardown artifact — visits are superseded, not deleted,
--   and the count is scoped to the run's own `sim_run_id`.
-- * **Whether 26% is typical.** One run, one scenario, one seed.
--
-- ══ 4. WHY THIS IS NOT FIXED HERE ══════════════════════════════════════════
--
-- Giving these vehicles a route back is a product decision, not a repair, and there are at
-- least three different answers with different meanings:
--
--   (a) **Readmit without interrupted work** — widen `ottoq_readmit_resumed_visits` to admit
--       a vehicle whose exception is resolved even when no visit was cut short. Changes what
--       "resume" means: the function's whole doctrine is that finishing the plan you already
--       had is not a change of plan, and this would make it also a re-entry path.
--   (b) **Simulate the operator** — the twin already simulates its technicians, so it could
--       simulate the `command_center_operator` the declared machine names as the exit actor.
--       Faithful, and it makes the twin assert a human action nobody took.
--   (c) **Send them to `out_of_service`** — the other declared exit. Honest about a broken
--       vehicle, and it removes them from the fleet rather than returning them.
--
-- Which is right depends on what `emergency_staged` is meant to mean, and that is Chase's
-- call. **Tracked as G95, open.**
--
-- ══ 5. AND ONE NEAR-MISS WORTH RECORDING ═══════════════════════════════════
--
-- `ottoq_emergency_clear(uuid,text,text,text)` has **zero callers anywhere** — not in the
-- database, not in any UI, not in any edge function, not in field-ops; it appears only in the
-- baseline and in `0198`, which created it. That looked like a fourth "exists and never
-- called" and it is **not relevant to this finding**: it clears depot-level rows in
-- `ottoq_emergency_invocations` and never touches a vehicle's state. Another shared-word
-- trap, the same shape as `perimeter_hold` versus `perimeter_walkaround` in `0277`. Whether
-- a depot emergency protocol with no caller matters is a separate question, not this one.
