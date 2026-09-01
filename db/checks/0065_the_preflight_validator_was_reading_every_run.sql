-- 0065: the pre-flight validator was reading every run's calendar
--
-- The busy_day 424242/12t canon step, open since db/checks/0063 section 12, is explained.
-- It is an ENGINE defect -- the first of this round. 0139 through 0144 were all instrument.
--
-- ============================================================================
-- 1. THE DEFECT
-- ============================================================================
--
-- ottoq.ottoq_validate_assignment is the pre-flight check ottoq_emit_vehicle_command runs
-- before every vehicle command. Its final branch asked whether the target stall was already
-- spoken for on the forward calendar:
--
--     SELECT b.vehicle_id INTO v_cal_conflict FROM ottoq_stall_bookings b
--      WHERE b.stall_id = p_stall_id AND b.state IN ('held','active','done','interrupted')
--        AND b.vehicle_id <> p_vehicle_id AND b.during @> p_clock
--      LIMIT 1;
--
-- No sim_run_id predicate. It read EVERY run's bookings. Measured across public, ottoq and
-- twin: of all functions touching ottoq_stall_bookings, this was the ONLY one whose body
-- never mentions sim_run_id at all -- the unique run-scope hole in the database, sitting in
-- the causal path of every proceed_to_stall command.

SELECT count(*) AS fns_touching_bookings_with_no_run_scope, string_agg(fn,', ') AS which
FROM (SELECT n.nspname||'.'||p.proname AS fn
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        CROSS JOIN LATERAL (SELECT pg_get_functiondef(p.oid) AS d) x
       WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind='f'
         AND p.proname NOT LIKE 'ottoq_fn_backup%'
         AND d LIKE '%ottoq_stall_bookings%' AND d NOT LIKE '%sim_run_id%') y;
--   before 0145: 1, ottoq.ottoq_validate_assignment

-- ============================================================================
-- 2. HOW IT PRODUCED THE STEP
-- ============================================================================
--
-- Both arms emitted a BYTE-IDENTICAL command at sim 07:30 (tick 11): vehicle
-- a1111111-0001-0001-0001-000000000006, proceed_to_stall, stall
-- e0f2bf3a-04ca-48c7-81db-56a1217355b7, payload {"new_state":"staged_awaiting_service"}.
-- The payload IS the transition -- twin.ottoq_sim_confirm_commands applies payload.new_state
-- on the following tick. ottoq_decide_tick contains no UPDATE vehicles at all (0039 moved the
-- state write into the twin), and this emit path writes no ottoq_decisions row of its own,
-- which is why a decisions diff could never see the cause.
--
--   OLD 55b69698 (armed 08-31 23:41)  status executed, reason_code NULL, executed_at 08:00
--   NEW d2923358 (armed 09-01 02:28)  status refused, target_occupied,
--                                     confirmed_by otto_q_preflight,
--                                     "calendar booking held by b9ef130e-..."
--
-- OLD's command reached the twin and moved the vehicle arrived_at_gate ->
-- staged_awaiting_service; the next tick promoted it ready. NEW's was refused at emission and
-- never reached the twin, so the vehicle stayed at the gate and took a perimeter_hold. Every
-- other difference between those runs -- the stall rotation, the 240-minute hold, the
-- displaced vehicle, the added and removed bookings -- is downstream of this one refusal.
--
-- THE BLOCKERS ARE 100% FOREIGN. Twelve bookings cover that stall at 07:30 and NOT ONE
-- belongs to either arm:

SELECT b.sim_run_id::text AS booking_run,
       (b.sim_run_id IN ('55b69698-4d5c-4ce9-b7da-b3028869fd67',
                         'd2923358-cbc3-4430-b359-27b69d2caa89')) AS belongs_to_either_arm,
       to_char(r.started_at AT TIME ZONE 'UTC','MM-DD HH24:MI') AS that_run_armed
FROM public.ottoq_stall_bookings b
LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = b.sim_run_id
WHERE b.stall_id='e0f2bf3a-04ca-48c7-81db-56a1217355b7'
  AND b.state IN ('held','active','done','interrupted')
  AND b.vehicle_id <> 'a1111111-0001-0001-0001-000000000006'
  AND b.during @> '2026-09-01 07:30:00+00'::timestamptz
ORDER BY r.started_at;
--   12 rows, belongs_to_either_arm = false on every one, from runs armed
--   00:46, 00:58, 03:08, 03:34, 09:40, 10:06. At OLD's arming none existed yet.
--
-- ============================================================================
-- 3. WHY THIS IS WORSE THAN A DETERMINISM BUG
-- ============================================================================
--
-- PROGRESSIVE. The conflict set grows monotonically as runs accumulate bookings.
-- Reproducibility does not break, it DECAYS -- and silently, because every refusal looks like
-- an ordinary occupancy check doing its job. Two of the twelve blockers came from the 09:40
-- and 10:06 pairs of this morning's own re-certification, so the matrix certified green at
-- 11:20 was already standing on a fuller calendar than the one it was certified against.
--
-- NOT CONFINED TO THE TWIN. ottoq_stall_bookings holds simulation and production rows
-- together, separated only by sim_run_id -- that co-existence is deliberate (CLAUDE.md 2.8,
-- "sim-generated and production rows co-exist in shared tables filtered by data_source ...
-- it is what makes sim and real telemetry indistinguishable to the metrics layer"). An
-- unscoped read therefore lets simulation bookings refuse PRODUCTION commands on stalls that
-- are physically free, and lets production bookings refuse simulation ones. That is a
-- correctness fault, not a reproducibility one.
--
-- IT HID FOR NINE TICKS. The same unscoped read also chose WHICH conflicting vehicle to name,
-- through a LIMIT 1 with no ORDER BY. reason_detail was already diverging between the arms
-- from tick 2 onward -- 9, 8, 6, 9, 20, 13, 13, 3, 2, 7 rows per tick -- with zero
-- behavioural effect, because only the text differed. It became visible only when the read
-- finally flipped a status instead of a string. A ledger field had been nondeterministic for
-- nine ticks and nothing in the harness noticed, because h_cmd hashes status and reason_code
-- but not reason_detail.
--
-- ============================================================================
-- 4. THE FIX (0145) AND ITS OWN PROOF
-- ============================================================================
--
-- Run-scope the calendar read with the 0020/0124 zero-uuid idiom, so a simulation sees only
-- its own bookings and production (NULL run) sees only production's. The validator gains
-- p_sim_run_id; ottoq_emit_vehicle_command -- its ONLY caller, verified -- passes the p_run it
-- already holds. The 4-argument arity is DROPPED, not left beside the new one: 0144 learned
-- that a defaulted parameter creates a second function and PL/pgSQL keeps resolving existing
-- calls to the old body, so the fix looks applied and does nothing.
--
-- The LIMIT 1 also gains a total order -- ORDER BY lower(b.during), b.vehicle_id,
-- b.booking_id -- per the 0062/0063 discipline, content keys first and the unique id last.
--
-- The migration proves itself on the historical case rather than asking to be trusted. It
-- captures the verdict BEFORE changing anything and aborts if the defect does not reproduce,
-- so the proof can never be vacuous:
--
--   before (unscoped)          {"ok": false, "code": "target_occupied",
--                               "detail": "calendar booking held by b9ef130e-..."}
--   after, OLD arm's run id    {"ok": true}
--   after, NEW arm's run id    {"ok": true}
--   after, NULL (production)   {"ok": true}
--
-- Both arms now accept, because every blocker on that stall at that clock belongs to another
-- run. Production is unaffected by simulation rows.
--
-- ============================================================================
-- 5. STILL OPEN
-- ============================================================================
--
--   * db/checks/0050's CORRECTION banner STANDS. peak_site_kw does not reproduce; 0051 open.
--   * Task #47, normal_day 171717/12t: canon f24724eb held across six pairs over ten hours.
--     At a 1-in-4 deviation rate that happens about 18% of the time -- stronger than the
--     four-pair position, still not proof. Open.
--   * Whether reason_detail should be hashed by the harness at all. It went nondeterministic
--     for nine ticks unnoticed. Hashing it would have caught 0145 nine ticks earlier, at the
--     cost of a noisier verdict. Not decided here.
