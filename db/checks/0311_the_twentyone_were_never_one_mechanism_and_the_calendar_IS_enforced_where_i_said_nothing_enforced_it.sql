-- 0311  **G112's LAST OPEN ITEM CLOSED, AND IT CLOSES BY SPLITTING IN TWO — plus a RETRACTION of a
--       sentence I wrote in `0310` four hours ago.** `0308` §8 found that the `begin_charge` confirm
--       chain costs exactly one tick and left "the 21 of 74 the lag does not explain" as explicitly
--       unexplained, with the note that *"a mechanism covering 72% is a mechanism, not the whole
--       story."* It is not one story. The residue is **two independent mechanisms**, and the second
--       one — command REFUSAL — was never counted anywhere in this repo.
--
--       **And the refusals prove the calendar IS enforced, at a layer I claimed enforced nothing.**
--
-- Read-only. Measured 2026-09-21 ~17:1x UTC (12:1x CT) on run `b4d5f76d` — the same 48-tick
-- `cert_harness` run `0308` §8 used, so this is comparable to it by construction.
--
-- ══ 1. ALL 183 OCCUPIED CHARGE TURNS, DECOMPOSED. THE ROWS SUM. ════════════
--
-- Charge bookings (`dcfc`/`l2`, state `done`/`interrupted`) joined to their `begin_charge` command:
--
--   cmd_status   had_session    n    avg_win   issue_delay   budget_left   lag
--   (none)          true        2     42.6        —             —           —
--   executed        true       94     70.8       0.8          70.0        30.0
--   refused         true       10     75.9       2.5          73.4         —
--   executed       false       65     26.3       6.3          20.1        30.0
--   refused        false       12     50.5       0.0          50.5         —
--                                   ───
--                                   183   = 2 + 94 + 10 + 65 + 12
--
-- All minutes. `issue_delay` = `issued_at − lower(during)`; `budget_left` = `upper(during) −
-- issued_at`; `lag` = `executed_at − issued_at`.
--
-- ══ 2. MECHANISM ONE, SHARPENED: THE PREDICATE IS *BUDGET LEFT*, NOT ═══════
--       WINDOW LENGTH. `0308` §8 NAMED THE WRONG VARIABLE.
--
-- §8 said a booking fails when "its window is shorter than the lag", and quoted average windows of
-- 70.8 min with a session against 28.4 without. That correlates, and it is not the mechanism,
-- because a command is not issued at the window's start. The variable that actually decides is
-- **how much window remains once the command exists**:
--
--   executed + session       budget_left **70.0** min   against a lag of 30.0  → survives
--   executed + no session    budget_left **20.1** min   against a lag of 30.0  → cannot
--
-- and the issue delay is what separates them — **0.8 min** for the group that charged against
-- **6.3 min** for the group that did not. Window length hides that term. **The clean statement:** a
-- charge turn completes iff `upper(during) − issued_at > 30 min`, the lag being invariant at
-- exactly one tick in all 159 executed cases.
--
-- **AND ONE ROW REFUTES THE OLD PREDICATE OUTRIGHT**, which is why it is worth replacing rather
-- than softening: a booking with a **15-minute window did get a session** (§1's `executed/true`
-- group has a minimum window of 00:15:00 at the type level). Under "window shorter than the lag
-- cannot complete" that row is impossible. Under "budget left" it is ordinary.
--
-- ══ 3. MECHANISM TWO, WHICH NOTHING IN THIS REPO HAD COUNTED: REFUSAL ═════
--
-- **22 of 183 charge turns (12%) had their `begin_charge` REFUSED**, and `0308` §8's clock
-- explanation has nothing to say about any of them — a refused command never executes, so it has no
-- lag to lose. Reason codes:
--
--   target_occupied   16   (8 with a session anyway, 8 without)
--   superseded         6   (2 with a session anyway, 4 without)
--
-- **Refusal is NOT automatically fatal: 10 of the 22 vehicles charged regardless**, on a later
-- command or another path. So the honest split of the lost turns is 8 from `target_occupied`, 4 from
-- `superseded`, and the rest of the no-session population is mechanism one.
--
-- ══ 4. AND HERE IS THE RETRACTION — `0310` §1 IS WRONG ABOUT WHAT CONTAINS ═
--       A POINTER/CALENDAR COLLISION, AND `target_occupied` IS THE PROOF.
--
-- `0310` §1 ends: *"What nothing contains is pointer-versus-CALENDAR: a stall booked for vehicle B
-- at T+10 can be pointer-reserved for vehicle A now."* **The first clause is false.** The refusal
-- detail is not generic — it reads, verbatim from the rows:
--
--   code   target_occupied
--   detail **"calendar booking held by 37aee690-ce21-4aed-b9c1-12ff83521fa9"**
--
-- Emitted by **`ottoq.ottoq_validate_assignment`**, which reads the calendar with the **same state
-- set the EXCLUDE constraint uses** and refuses the assignment:
--
--   SELECT b.vehicle_id INTO v_cal_conflict FROM ottoq_stall_bookings b
--    WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = p_stall_id
--      AND b.state IN ('held','active','done','interrupted')
--      AND b.vehicle_id <> p_vehicle_id AND b.during @> p_clock
--   …
--   IF v_cal_conflict IS NOT NULL THEN
--     RETURN jsonb_build_object('ok',false,'code','target_occupied',
--            'detail','calendar booking held by '||v_cal_conflict, …);
--
-- **So pointer-versus-calendar IS contained — at the command-VALIDATION layer rather than at the
-- picker — and it fired 16 times on this one 48-tick run.** That is CLAUDE.md rule 6's *"assignment
-- plus verification, always"* working exactly as designed: the picker proposes, the validator
-- checks physical and calendar reality, and a conflict is refused with the conflicting booking
-- named. I read `ottoq_validate_assignment`'s NAME in `0310` §2's own list of the seven callers of
-- `ottoq_stall_free_between` and never opened it.
--
-- **WHICH DEMOTES G114 ITEM (a) FROM A SAFETY FIX TO A THROUGHPUT FIX, and that must be said as
-- plainly as the finding was.** The fault reroute's missing calendar gate does not let two vehicles
-- physically share a stall; it lets the engine *offer* a stall that will then be refused
-- downstream. The cost is a **wasted assignment and a lost charge turn**, not a collision.
-- `db/migrations/0400` is still correct and still worth applying — catching a conflict before
-- committing to it beats catching it after — but it buys throughput and clarity, not safety, and
-- nothing in it should be described as closing a safety hole.
--
-- **Third time in one day on this one sentence's neighbourhood**: `0310` §1 retracted `0308` §2's
-- EXCLUDE-constraint claim, `0310` §1a retracted my own regex, and this retracts `0310` §1's
-- replacement for the first. The pattern is consistent and worth naming: **each error was an
-- assertion about what does NOT exist, made from having looked in one place.** A negative claim over
-- a 400-function schema needs a census, not a reading.
--
-- ══ 5. TWO SMALLER THINGS, ONE OF WHICH CORROBORATES `0400` ════════════════
--
-- **(a) `ottoq_validate_assignment` encodes `0400`'s NULL-run argument independently.** It branches:
-- `IF p_sim_run_id IS NULL THEN … WHERE b.sim_run_id IS NULL …`. Since `ottoq_stall_bookings.sim_run_id`
-- is **NOT NULL** (`0` of `15,890`), that branch can never match a row — it is unreachable in
-- effect. Written defensively for sargability (`db/checks/0127`), it is a second function reaching
-- the same conclusion `0400`'s header argues: a NULL run has no bookings to conflict with. Two
-- independent encodings of one assumption is the kind of agreement worth recording.
--
-- **(b) 2 of 183 turns had a session with NO `begin_charge` command in the window at all.** Some
-- other path opened them. Small, real, and NOT explained here rather than folded into either
-- mechanism.
--
-- ══ 6. POPULATION RECONCILIATION, BECAUSE MY COUNTS DIFFER FROM §8's ══════
--
-- `0308` §8 reported 109 with a session and 74 without, splitting 53/21 on window-versus-lag. This
-- file reads **106 with / 77 without**, splitting 54/23. The total is 183 in both. The difference is
-- predicate, not data: this file restricts to `state IN ('done','interrupted')` and tests session
-- OVERLAP with the booking window (`started_at < win_end AND COALESCE(ended_at, win_end) >
-- win_start`), where §8 matched more loosely. **Neither is wrong and the conclusions are unaffected
-- — both mechanisms are far larger than the ±3 — but the numbers are not interchangeable and should
-- not be quoted across the two files.**
--
-- **NOT CLAIMED:** that any of this affects a production or operator run. `0308` §8 measured tick
-- granularity at 29 s for `operator_demo` against 30 min here, and mechanism one scales with the
-- tick. Mechanism two does not obviously scale with anything and is **unmeasured outside this run.**

WITH bk AS (
  SELECT b.booking_id, b.stall_id, b.vehicle_id,
         lower(b.during) AS win_start, upper(b.during) AS win_end
    FROM public.ottoq_stall_bookings b
    JOIN public.stalls s ON s.id = b.stall_id
   WHERE b.sim_run_id = 'b4d5f76d-7645-4392-943a-d4806f508297'
     AND s.stall_type::text IN ('dcfc','l2')
     AND b.state IN ('done','interrupted')
), sess AS (
  SELECT bk.*, EXISTS (
    SELECT 1 FROM public.ocpp_sessions os
     WHERE os.stall_id = bk.stall_id AND os.vehicle_id = bk.vehicle_id
       AND os.started_at < bk.win_end
       AND COALESCE(os.ended_at, bk.win_end) > bk.win_start) AS had_session
    FROM bk
), cmd AS (
  SELECT s2.*, c.status AS cmd_status, c.reason_code, c.issued_at, c.executed_at
    FROM sess s2
    LEFT JOIN LATERAL (
      SELECT * FROM public.ottoq_vehicle_commands vc
       WHERE vc.sim_run_id = 'b4d5f76d-7645-4392-943a-d4806f508297'
         AND vc.vehicle_id = s2.vehicle_id
         AND vc.command_type = 'begin_charge'
         AND vc.issued_at >= s2.win_start - interval '5 minutes'
         AND vc.issued_at <  s2.win_end
       ORDER BY vc.issued_at LIMIT 1) c ON TRUE
)
SELECT COALESCE(cmd_status,'(none)')                                     AS cmd_status,
       COALESCE(reason_code,'-')                                        AS reason_code,
       had_session,
       count(*)                                                          AS n,
       round(avg(extract(epoch FROM (win_end - win_start)))/60.0, 1)      AS avg_win_min,
       round(avg(extract(epoch FROM (issued_at - win_start)))/60.0, 1)    AS avg_issue_delay_min,
       round(avg(extract(epoch FROM (win_end  - issued_at)))/60.0, 1)     AS avg_budget_left_min,
       round(avg(extract(epoch FROM (executed_at - issued_at)))/60.0, 1)  AS avg_lag_min
  FROM cmd
 GROUP BY 1,2,3
 ORDER BY 3 DESC, 1, 2;

-- OPEN-ITEM: G112's residue is CLOSED as two mechanisms, and G114 is CORRECTED. On run b4d5f76d all 183 occupied charge turns decompose with no remainder: 2 had a session with no begin_charge command at all, 94 executed and charged, 65 executed and did not, 10 were refused and charged anyway, 12 were refused and did not. MECHANISM ONE is 0308 §8's one-tick confirm lag but the predicate it named is wrong -- the deciding variable is BUDGET LEFT (upper(during) - issued_at), 70.0 min for the group that charged against 20.1 for the group that did not, with issue delay 0.8 vs 6.3 min being the term window-length hides; a 15-minute-window booking DID charge, which the old "window shorter than the lag" predicate calls impossible. MECHANISM TWO was never counted in this repo: 22 of 183 (12%) had begin_charge REFUSED -- target_occupied 16, superseded 6 -- and refusal is not fatal, since 10 of the 22 charged regardless, so the lost turns are 8 + 4. AND MECHANISM TWO RETRACTS 0310 §1's claim that "what nothing contains is pointer-versus-CALENDAR": target_occupied's detail reads "calendar booking held by <vehicle>", emitted by ottoq.ottoq_validate_assignment, which reads ottoq_stall_bookings with the same state set as the EXCLUDE constraint and refused 16 times on this run -- rule 6's "assignment plus verification" working as designed, in a function whose NAME I listed in 0310 §2 and never opened. THAT DEMOTES G114 item (a) from a safety fix to a THROUGHPUT fix: the fault reroute's missing calendar gate cannot make two vehicles share a stall, it makes the engine offer a stall that is then refused downstream, costing a wasted assignment and a lost charge turn. db/migrations/0400 remains correct and worth applying, but must not be described as closing a safety hole. Third retraction in one day in this area, and all three were negative claims about what does not exist, made from looking in one place. Remaining genuinely open: the 2 sessions with no command, and whether mechanism two occurs at operator_demo granularity (unmeasured outside this run). Tracked as G112 and G114.
