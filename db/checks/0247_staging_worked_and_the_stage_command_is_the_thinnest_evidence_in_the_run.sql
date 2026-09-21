-- ============================================================================
-- 0247 — STAGING WORKED. THE `stage` COMMAND IS THE THINNEST EVIDENCE IN THE
--        RUN, AND I ALMOST QUOTED IT AS THE STRONGEST.
-- ============================================================================
-- Measured 2026-09-14 23:0x UTC, read-only, against the completed UI-door twin
-- run 34ffb2d9-bcc6-4232-bbfc-d2c4d51e4ec5 (busy_day, seed 909090, 25 ticks).
-- Round 45 in flight on other depots; nothing here writes.
--
-- THE QUESTION: "has OTTO-Q worked fully for staging vehicles and orchestrating
-- them in OTTO-Twin?" The first number that came back looked like a clean yes,
-- and it is the one that does not survive reading its own assignment.
--
-- ── COMMANDS, BY TYPE AND OUTCOME ──────────────────────────────────────────
--
--   type              issued  executed  refused   reason codes
--   begin_charge         179        95       84   target_occupied 83, superseded 1
--   proceed_to_stall     168        64      104   vehicle_state_incompatible 46,
--                                                 target_occupied 33, superseded 25
--   stage                118       118        0   -- none
--   enter_service          3         3        0
--   enter_wash             1         1        0
--
-- "stage: 118 of 118 executed, zero refused" reads as the healthiest line in the
-- table. IT IS THE EMPTIEST. Read the executor,
-- twin.ottoq_sim_confirm_commands, and the two gates are:
--
--   IF v_rec.payload ? 'stall_id' THEN  ... sets v_stall_ok ...  END IF;
--
--   CASE v_rec.command_type
--     WHEN 'proceed_to_stall','begin_charge','enter_wash','enter_service' THEN
--       ... sets v_vehicle_ok ...
--
-- The occupancy gate fires on the PAYLOAD carrying a stall, not on the command
-- type. The state gate fires on a four-name list that does not include `stage`.
-- So measured on this run:
--
--   stage commands carrying a stall_id ............ 3 of 118
--   stage commands carrying none ................ 115 of 118
--
-- For those 115, BOTH gates are skipped, `v_stall_ok` and `v_vehicle_ok` keep
-- their `true` defaults, and the command is executed unconditionally. **115 of
-- 118 could not have been refused by any mechanism in that function.** A pass
-- rate over a population with no failure mode is not evidence of success; it is
-- the absence of a test. Fourth instance today of the same class (0216, 0231,
-- round 44's fp, the "0 of 117" baseline), and this one was inside a number I
-- was about to report as a result.
--
-- ── WHAT ACTUALLY PROVES STAGING WORKED, and it is the other ledger ─────────
--
--   staging bookings ................. 522, across 116 vehicles
--   ... state done ................... 170
--   ... state superseded ............... 2
--   ... remainder released
--   staging stalls at the depot ...... 113
--   occupied / reserved at end ......... 0 / 0   (clean teardown)
--   SPACE CONFLICTS ON STAGING ......... 0
--
-- Bookings run through `ottoq_stall_bookings` and its EXCLUDE constraint, which
-- makes an overlap physically impossible rather than merely checked. 522 claims,
-- 116 vehicles, zero conflicts, zero residue. THAT is the evidence staging
-- works, and it is strong. It just is not the command ledger.
--
-- ── WHERE THE REAL STRESS WAS: CHARGING, NOT STAGING ───────────────────────
--
--   stall_type   conflict_kind                resolution                    n
--   l2           assignment_refused_occupied  command_refused_preflight   107
--   dcfc         assignment_refused_occupied  command_refused_preflight     9
--   wash_bay     stale_claim_displaced        reality_outranks_plan         2
--   service_bay  stale_claim_displaced        reality_outranks_plan         1
--
-- 119 conflicts, ZERO of them on staging. Two distinct stories:
--
--   * 116 `assignment_refused_occupied` are the SAME events as the 116
--     `target_occupied` command refusals above, recorded in a second ledger.
--     The kernel assigned vehicles to charging stalls that were already taken
--     and the preflight refused every one. Nothing double-occupied. The net
--     held 116 times out of 116.
--
--   * 3 `stale_claim_displaced` / `reality_outranks_plan` are the calendar
--     losing to physical presence, which is CLAUDE.md's "assignment plus
--     verification" working exactly as designed: `space_conflict_ledger`
--     records every calendar claim overruled by reality.
--
-- THE EFFICIENCY READING, which is the honest bad news: of 347 stall-bearing
-- commands (begin_charge + proceed_to_stall), **116 were dispatched at an
-- occupied target — 33%.** Safe, caught, logged, and wasteful. This is live
-- evidence for two findings already open and not new here:
--   G56 (task #120) the kernel and the calendar disagree on who holds a charge place
--   G57 (task #121) the booking predicate has no time bound
--
-- ── THE ANSWER, STATED AT ITS ACTUAL STRENGTH ──────────────────────────────
-- Staging: YES, on the booking ledger — 522 claims, 116 vehicles, 0 conflicts,
-- 0 residue, under a constraint that makes overlap impossible. NO, on the
-- command ledger, where 115 of 118 passes were unfalsifiable.
-- Orchestration end to end: YES, it moved and nothing broke. NOT efficiently:
-- a third of stall commands went to occupied targets and were caught rather
-- than avoided.
-- ============================================================================

-- 1. Commands by type and outcome, with the reason codes.
SELECT c.command_type, c.status, COALESCE(c.reason_code,'(none)') AS reason_code, count(*) AS n
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id = '34ffb2d9-bcc6-4232-bbfc-d2c4d51e4ec5'
 GROUP BY 1,2,3 ORDER BY 1, 4 DESC;

-- 2. THE ONE THAT MATTERS: does the command carry the field its gate keys on?
--    A pass over a population the gate cannot see is not a pass.
SELECT c.command_type, count(*) AS n,
       count(*) FILTER (WHERE c.payload ? 'stall_id') AS carries_stall_id,
       count(*) FILTER (WHERE NOT (c.payload ? 'stall_id')) AS gate_cannot_see_it
  FROM public.ottoq_vehicle_commands c
 WHERE c.sim_run_id = '34ffb2d9-bcc6-4232-bbfc-d2c4d51e4ec5'
 GROUP BY 1 ORDER BY 2 DESC;

-- 3. The booking ledger -- the evidence that actually carries weight, because
--    ottoq_stall_bookings enforces non-overlap with an EXCLUDE constraint.
SELECT s.stall_type::text AS stall_type, count(*) AS bookings,
       count(DISTINCT b.vehicle_id) AS vehicles,
       count(*) FILTER (WHERE b.state::text='done')       AS done,
       count(*) FILTER (WHERE b.state::text='superseded') AS superseded
  FROM public.ottoq_stall_bookings b
  JOIN public.stalls s ON s.id = b.stall_id
 WHERE b.sim_run_id = '34ffb2d9-bcc6-4232-bbfc-d2c4d51e4ec5'
 GROUP BY 1 ORDER BY 2 DESC;

-- 4. Where reality overruled the plan, and where it never had to.
SELECT scl.stall_type::text, scl.conflict_kind::text, scl.resolution::text, count(*) AS n
  FROM public.space_conflict_ledger scl
 WHERE scl.sim_run_id = '34ffb2d9-bcc6-4232-bbfc-d2c4d51e4ec5'
 GROUP BY 1,2,3 ORDER BY 4 DESC;
