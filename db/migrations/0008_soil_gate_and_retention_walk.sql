-- migration-version: PENDING
-- migration-name:    soil_gate_and_retention_walk

-- ============================================================================
-- 0008_soil_gate_and_retention_walk.sql
--
-- THE SHORT VERSION, IN PLAIN LANGUAGE
--
-- Two separate bugs, one disease: something reports success while doing nothing,
-- or while doing the wrong thing.
--
--   (1) THE DEPOT IS TELLING ITSELF CARS ARE CLEAN WHEN THEY ARE NOT.
--       0005 made every finished job copy a number called `soil_index` into the
--       column the depot actually grades cleanliness on. Those are two different
--       measurements: `soil_index` tracks SENSOR grime, the other column is BODY
--       dirt, and the depot calls a car "needs a wash" at 0.45. In practice the
--       sensor number sits far below that -- across the whole fleet today its
--       highest value is 0.33 -- so the copy pushes cars toward "clean", and it has:
--       every car it touched ended up graded clean, with no wash bay involved.
--       Eleven cars are sitting in that state right now. It can also go the other
--       way and invent a wash a car does not need (0005's own test recorded exactly
--       that). Either way, an inspection is rewriting a grade it never measured.
--       Same file also let a routine maintenance job wipe a car's fault list. A PM
--       is not a repair; it must not be allowed to claim it fixed something.
--
--   (2) THE NIGHTLY CLEAN-UP QUITS EARLY AND LEAVES OLD DATA BEHIND.
--       0006 got the event purge deleting for the first time ever -- real progress.
--       But it walks the table in ID order and then decides "everything from here on
--       is recent, I'm done." That decision is only sound if newer ID always means
--       newer timestamp. In this system it does not: the clock on an event is the
--       SIM clock, and every run starts at a random time of day, so a run whose
--       clock sits behind the last one writes old-looking rows with brand-new IDs.
--       The purge sees one recent row, concludes it has caught up, and stops -- with
--       genuinely old rows still sitting in front of it. This file makes the walk
--       follow the clock instead of the ID, which is the only order in which it
--       cannot miss anything.
--
-- Nothing about how OTTO-Q makes decisions changes in this file. No orchestration,
-- no LP, no cuOpt, no approval gate, no tick behaviour.
--
-- ============================================================================
-- PREMISE VERIFICATION -- MEASURED LIVE ON gxdrcyphqjzjsuhxuqtg, 2026-08-05,
-- READ-ONLY, BEFORE A SINGLE LINE OF THIS FILE WAS WRITTEN. 0 runs `running`.
--
-- I was handed three premises. TWO HOLD AS STATED. ONE IS HALF WRONG and I correct
-- it below rather than inherit it -- the correction makes the defect worse, not
-- smaller, and it changes what the fix is allowed to rest on. I state my own
-- denominators throughout and never adopt one I cannot reproduce.
--
--   PREMISE A -- "soil_index is STRUCTURALLY capped well below the 0.45 wash band."
--   ⚠️ HALF RIGHT, AND I AM CORRECTING THE HALF THAT IS WRONG, BECAUSE A WRONG
--      PREMISE POISONS A FIX EVEN WHEN IT POINTS AT THE RIGHT LINE OF CODE.
--
--   THE MEASUREMENT HOLDS:
--       SELECT count(*), min(soil_index), max(soil_index), avg(soil_index),
--              count(*) FILTER (WHERE soil_index >= 0.45)
--         FROM public.ottoq_vehicle_wear;
--       -> n = 207 rows | min 0.0000 | max 0.3303 | avg 0.0880 | >= 0.45 : 0
--   Not one row in the wear ledger is at or above the LOWEST wash band. The brief
--   said "measured max 0.3774 across 116 rows"; I measure 0.3303 across 207 rows.
--   Different denominator, same finding.
--
--   THE WORD "STRUCTURALLY" IS WRONG. There is no cap at ~0.30. Quoted verbatim from
--   the live twin.ottoq_sim_advance_wear_counters, which is what accrues the column:
--       LEAST(1.0, GREATEST(0, c.km_tick * v_soil_rate * c.veh_soil_scalar
--                              * (1 + v_precip * v_precip_coup)))
--   The clamp is at 1.0 -- the SAME 0..1 range as exterior_soil_level. 0.33 is an
--   EMPIRICAL ceiling produced by today's soil rate, run lengths and rainfall, not a
--   structural one. Turn up the rate or run through a storm and it will cross 0.45.
--   0005's own applied-commit smoke test recorded exactly that: an INSPECTION moving
--   exterior_soil_level 0.199 -> 0.480, i.e. the copy RAISING a car over the wash
--   band on the strength of a sensor counter.
--
--   WHY THIS MAKES THE DEFECT WORSE, NOT SMALLER. If the copy were a proven one-way
--   ratchet toward `ok`, it would be one bug with one direction. It is not: it is a
--   grade being overwritten by a measurement of a different thing, and the direction
--   of the error depends on weather and mileage. It can hide a dirty car AND it can
--   send a clean one to a wash bay. The measured evidence today happens to be all in
--   the first direction (11 of 11, below), which is the dangerous one, but the fix
--   must not rest on that number holding. It rests on the two columns measuring
--   different things -- which is true regardless of their ranges.
--
--   The destination column tells the other half of the story:
--       SELECT count(*), min, max, avg,
--              count(*) FILTER (WHERE exterior_soil_level >= 0.45)  -- etc.
--         FROM public.vehicle_need_profile;
--       -> n = 116 | min 0.0000 | max 1.0000 | avg 0.4177
--          >= 0.45 : 48   >= 0.65 : 28   >= 0.85 : 16
--   So the destination genuinely uses the full 0..1 range and 48 of 116 vehicles
--   are at or above the first wash band. The source cannot reach 0.45. A copy from
--   one to the other is a one-way ratchet toward "clean". That is the defect.
--
--   PREMISE B -- "the needs card bands exterior_soil_level at 0.45 / 0.65 / 0.85."
--   CONFIRMED, quoted verbatim from the LIVE
--   pg_get_viewdef('public.ottoq_vehicle_needs_card'):
--       ottoq_urgency_max(ottoq_service_urgency('exterior_wash'::text, c.wash_ratio),
--           CASE
--               WHEN c.exterior_soil_level >= 0.85 THEN 'overdue'::text
--               WHEN c.exterior_soil_level >= 0.65 THEN 'due'::text
--               WHEN c.exterior_soil_level >= 0.45 THEN 'due_soon'::text
--               ELSE 'ok'::text
--           END) AS wash_urgency,
--
--   PREMISE C -- "event_seq order is not occurred_at order."
--   CONFIRMED.
--       WITH e AS (SELECT event_seq, occurred_at,
--                         lag(occurred_at) OVER (ORDER BY event_seq) prev_ts
--                    FROM public.ottoq_events)
--       SELECT count(*), count(*) FILTER (WHERE occurred_at < prev_ts) FROM e
--        WHERE prev_ts IS NOT NULL;
--       -> 23,697 adjacent pairs | 18 inversions
--   18 of 23,697 = 0.076%. That is a SMALL number and it is the WRONG number to
--   reassure yourself with. The early exit does not need many inversions to fire --
--   it needs ONE row with a recent timestamp inside a batch that deleted nothing.
--   A rare inversion is not a rare failure; it is a rare cause of a total stop.
--
--   THE LAUNDERING, MEASURED DIRECTLY -- this is the finding the brief predicted
--   and I confirm it on today's data rather than inheriting it:
--       SELECT count(*),
--              count(*) FILTER (WHERE p.exterior_soil_level = round(w.soil_index,3)),
--              count(*) FILTER (WHERE p.exterior_soil_level = round(w.soil_index,3)
--                                 AND p.exterior_soil_level < 0.45)
--         FROM public.vehicle_need_profile p
--         JOIN public.ottoq_vehicle_wear w USING (vehicle_id);
--       -> 207 profile x wear pairs | 11 now carry the copied value | 11 of those 11
--          are below 0.45, i.e. graded `ok` on the body-soil half of wash_urgency.
--   11 of 11. Every single vehicle the copy touched was moved into `ok`. Not most.
--   All. There is no case on this database where the copy raised a grade, because
--   there is no value it could have supplied that would.
--
--   AND WHO ELSE WRITES THE COLUMN -- only two routines in public/ottoq/twin
--   mention exterior_soil_level at all:
--       public.ottoq_seed_vehicle_need_profiles/1   (writes it once, at boot)
--       public.ottoq_wear_mark_serviced/4           (this file's target)
--   So body soil does not accrue during a run. Stated plainly as GAP 1 below --
--   it is a real gap, it is NOT what this file fixes, and "but the copy was our
--   accrual mechanism" would be the wrong reason to keep it: what the copy accrues
--   is SENSOR grime, dressed up as body dirt. Keeping a wrong measurement because
--   it moves is worse than having an honest one that does not.
--
-- ============================================================================
-- FIX (1) -- THE SOIL COPY AND THE TWO FAULT CLEARS
--
-- ── EXACT BEFORE / AFTER ────────────────────────────────────────────────────
-- Quoted from the live body of public.ottoq_wear_mark_serviced (md5
-- d10f848b66b204b539805869034cb456), which is byte-identical to what 0005 §2
-- shipped. Three lines change. Everything else in the function is untouched,
-- including the whole of PART 1 and the whole of 0005 §3's wiring.
--
--   BEFORE:
--       exterior_soil_level = COALESCE(round(v_soil, 3), p.exterior_soil_level),
--   AFTER:
--       exterior_soil_level = CASE WHEN p_service = 'exterior_wash'
--                           THEN COALESCE(round(v_soil, 3), 0)
--                           ELSE p.exterior_soil_level END,
--
--   BEFORE:
--       open_fault_codes = CASE WHEN p_service IN ('fault_repair','mechanical_pm')
--                           THEN '{}'::text[] ELSE p.open_fault_codes END,
--       worst_fault_severity = CASE WHEN p_service IN ('fault_repair','mechanical_pm')
--                           THEN 99 ELSE p.worst_fault_severity END,
--   AFTER:
--       open_fault_codes = CASE WHEN p_service = 'fault_repair'
--                           THEN '{}'::text[] ELSE p.open_fault_codes END,
--       worst_fault_severity = CASE WHEN p_service = 'fault_repair'
--                           THEN 99 ELSE p.worst_fault_severity END,
--
-- ── JUDGEMENT CALL 1: SHOULD A WASH RESET BODY SOIL AT ALL? YES. ────────────
-- ⭐ DECIDED: an `exterior_wash` completion resets exterior_soil_level. Every
--    other service leaves it exactly as it found it.
--
-- The brief is right that the idea of resetting is not the bug. A wash bay exists
-- to remove body soil; a depot whose ledger cannot record that a car got washed is
-- a depot that will wash the same car forever. Deleting the write outright would
-- trade a false-clean bug for a never-clean bug, and 0004/0005 exist precisely
-- because "the completion updates one place and the decision reads another" is the
-- disease this repo keeps catching.
--
-- What was wrong was the SOURCE and the SCOPE, not the act:
--   * SOURCE. `soil_index` measures sensor grime. `exterior_soil_level` measures
--     body dirt. 0005's CORRECTION B argued they are "the same column on the same
--     scale" because the seeder projects one from the other at boot. The seeder does
--     do that -- and it is still not a licence to project it at every completion,
--     because at boot the two are equal by construction and afterwards they diverge:
--     one is accrued by twin physics as sensor grime, the other holds the body-soil
--     severity the card grades on. Both are clamped to 0..1, so this is NOT a range
--     mismatch you can fix with a scale factor -- they are different QUANTITIES that
--     happen to share a range. Measured today: source max 0.3303 against a 0.45 band
--     floor, so in practice it grades cars clean; 0005's smoke test caught it going
--     the other way too. A projection whose direction of error depends on the weather
--     is not a projection.
--   * SCOPE. It fired on EVERY service. 0005 §3 then widened the callers enormously
--     -- inspections, tidies, item retrievals, remote diagnostics all now route
--     through here. So the write went from "a bay exit" to "almost every completion
--     in the depot", which is why 11 vehicles were laundered inside a single run.
--     An inspection OBSERVES a car. It must not wash it. 0005's own comment says
--     "an inspection observes" one line above a write that made it wash.
--
-- Why `COALESCE(round(v_soil, 3), 0)` and not a bare 0:
--   PART 1 has already set soil_index := 0 for exterior_wash by the time v_soil is
--   read, so in the sim this expression IS 0 and lineage is preserved -- the value
--   still comes from the ledger, not from me. In production there is no wear row,
--   v_soil is NULL, and the COALESCE supplies 0. That is deliberate and it is the
--   only place in this function where a literal fills in for a missing wear row:
--   a real OEM reporting "exterior_wash complete" is asserting the body is clean,
--   and leaving the column at its stale pre-wash value would put the car straight
--   back in the wash queue. 0 is the column's own clean floor, not a tuned number.
--
-- What this deliberately does NOT do: it does not zero body soil on `sensor_clean`
-- or `interior_deep_clean`, even though PART 1 zeroes soil_index on both. Washing a
-- sensor does not wash the body and vacuuming a cabin does not wash the body.
-- 0005 recorded that disagreement as its GAP 1 and then let the copy enact it
-- anyway. Here the two ledgers are allowed to differ on that point, in the safe
-- direction, and the reason is written down (GAP 2).
--
-- ── JUDGEMENT CALL 2: `mechanical_pm` NO LONGER CLEARS FAULTS. ──────────────
-- ⭐ DECIDED: only `fault_repair` clears the profile's fault columns.
--
-- `open_fault_codes := '{}'` and `worst_fault_severity := 99` together mean "this
-- vehicle has nothing wrong with it" -- 99 lands on the card's ELSE branch and
-- grades fault_urgency `ok`. A fault_repair has earned that statement. A scheduled
-- preventive-maintenance job has not: it is booked on mileage, it happens whether or
-- not a fault exists, and it repairs whatever is on the PM sheet -- not whatever
-- DTC happened to be open. Letting a PM wipe the fault list is the same shape as the
-- soil copy: a job that did not do the work reporting that the work is done. It also
-- inverts the founder's standing rule that a vehicle must never leave the depot with
-- outstanding work, because the outstanding work becomes invisible rather than done.
--
-- Honest consequence, stated rather than buried: PART 1 still zeroes the WEAR
-- ledger's open_dtc_count / worst_open_dtc_rank on `mechanical_pm`. That is
-- pre-0005, certified behaviour and this file does not retune it. So the two
-- ledgers now disagree about a PM. I am choosing that divergence knowingly and in
-- one direction only -- the profile (which the card reads, and which is the
-- PRODUCTION surface) keeps reporting the fault; the run-scoped sim physics forgets
-- it. If they must ever agree again, the correct move is to take 'mechanical_pm'
-- out of PART 1's fault clear too, which is a behaviour change and needs the
-- founder. Recorded as GAP 3.
--
-- ── WHAT IS PRESERVED, EXPLICITLY ───────────────────────────────────────────
--   * 0005 §3, the inspection/non-bay completion wiring in
--     twin.ottoq_sim_advance_visit_atoms -- NOT TOUCHED. It is load-bearing and it
--     is what makes the date resets, cabin, software, items and odometer credit the
--     ~132 non-bay completions per run that used to credit nothing. This file only
--     changes WHAT that wiring is allowed to claim, never whether it fires.
--   * PART 1 of ottoq_wear_mark_serviced -- byte-for-byte unchanged.
--   * Every date reset, the cabin rule, the software copy, the item flag, the
--     odometer advance and the 0004 watermark fence -- byte-for-byte unchanged.
--   * Idempotency: all three changed writes remain absolute assignments inside a
--     CASE. Re-running a completion lands on the same value, forever.
--   * Totality: every unmapped service code still falls through every CASE and
--     changes nothing. Gating a branch cannot introduce a leg_type-style abort,
--     because no branch RAISEs.
--   * The EXCEPTION wrapper: PART 2 still fails safely with a named WARNING and
--     leaves PART 1 standing, so this function still cannot abort decide_tick.
--
-- ── WHAT THIS COSTS ─────────────────────────────────────────────────────────
-- 0005's §6 verification asserted that exterior_soil_level tracks soil_index after
-- a completion. That assertion is now deliberately false, and the correct
-- replacement check is in §4 below. Anyone re-running 0005's verification query
-- will see it "fail"; it is not a regression, it is this file.
--
-- ============================================================================
-- FIX (2) -- MAKE THE RETENTION WALK REACH OLD ROWS
--
-- ── EXACT BEFORE / AFTER ────────────────────────────────────────────────────
-- Quoted from the live 4-argument public.ottoq_retention_purge_worker (md5
-- 815c91faf7b57fc7cd7ed906b8cfca3a), as 0006 §7 shipped it.
--
--   BEFORE -- the walk is ordered by event_seq and the delete is predicated on
--   occurred_at, i.e. two different orders:
--       SELECT COALESCE(min(event_seq), 0) INTO v_seq FROM public.ottoq_events;
--       ...
--         SELECT max(w.event_seq), max(w.occurred_at)
--           INTO v_batch_hi, v_batch_ts
--           FROM (SELECT event_seq, occurred_at
--                   FROM public.ottoq_events
--                  WHERE event_seq >= v_seq
--                  ORDER BY event_seq
--                  LIMIT p_micro_batch) w;
--         DELETE FROM public.ottoq_events e
--          WHERE e.event_seq >= v_seq
--            AND e.event_seq <= v_batch_hi
--            AND e.occurred_at < v_cut
--            AND (e.sim_run_id IS NULL OR NOT (e.sim_run_id = ANY (v_live)));
--       ...
--         -- We have walked into the keep window and stopped deleting. Done for tonight.
--         IF v_n = 0 AND v_batch_ts >= v_cut THEN
--           PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'ottoq-retention-backlog';
--           UPDATE public.ottoq_retention_state
--              SET pass_deleted = 0, updated_at = now() WHERE table_name = 'ottoq_events';
--           COMMIT;
--           EXIT;
--         END IF;
--
--   AFTER -- the walk is ordered by occurred_at, which is the same column the
--   delete is predicated on, so there is no stopping rule left to get wrong:
--       v_from := '-infinity'::timestamptz;
--       ...
--         -- pick the window's upper TIMESTAMP by reading p_micro_batch index entries
--         SELECT max(w.occurred_at) INTO v_batch_ts
--           FROM (SELECT e.occurred_at
--                   FROM public.ottoq_events e
--                  WHERE e.occurred_at >= v_from AND e.occurred_at < v_cut
--                  ORDER BY e.occurred_at
--                  LIMIT p_micro_batch) w;
--
--         -- nothing older than the cut is left. The ONLY exit that means "done".
--         IF v_batch_ts IS NULL THEN v_drained := true; COMMIT; EXIT; END IF;
--
--         -- delete the whole CLOSED TIME RANGE, so a timestamp group is never split
--         DELETE FROM public.ottoq_events e
--          WHERE e.occurred_at >= v_from
--            AND e.occurred_at <= v_batch_ts
--            AND e.occurred_at <  v_cut
--            AND (e.sim_run_id IS NULL OR NOT (e.sim_run_id = ANY (v_live)));
--
--         v_from := v_batch_ts + interval '1 microsecond';   -- strictly increasing
--
--   The window is a range of TIME, not a count of rows. That detail is load-bearing:
--   many events share one occurred_at (it is the sim clock, and one tick writes
--   60-120 events at the same value), so a row-count window could cut a timestamp
--   group in half and the watermark would step over the remainder. A closed time
--   range cannot. Terminates because v_from strictly increases; exact because the
--   scan order and the delete predicate are the same column.
--
-- ── JUDGEMENT CALL 3: I ADD THE BTREE ON occurred_at. ───────────────────────
-- ⭐ DECIDED: add `ottoq_events_occurred_at_retention_idx` (plain btree on
--    occurred_at) and re-order the walk by that column. The early exit disappears
--    as a consequence, not as the fix.
--
-- The choice I was given was "drop the early exit" OR "index occurred_at". I want
-- to be precise about why those are not equally good, because the early exit is a
-- symptom and not the disease.
--
--   THE DISEASE is that the walk is ordered by one column and the delete is
--   predicated on another. Any such walk needs a stopping rule that GUESSES how the
--   two orders relate. `event_seq >= occurred_at order` is that guess, and it is
--   measurably false (18 inversions). Fix the ordering and there is nothing left to
--   guess: the loop stops when there are no candidates older than the cut, which is
--   not an inference, it is the definition of finished.
--
--   DROPPING THE EARLY EXIT ALONE IS A PARTIAL FIX -- and it fails in exactly the
--   way this file is here to stop. The 0006 walk always restarts at
--   min(event_seq) and persists no resume point that survives a budget-exhausted
--   pass (cursor_block is written, but never read back). Today's 23,698 rows sweep
--   in ~12 batches and nobody notices. At the 9,000,000-row scale this system
--   actually reached, a full seq sweep does not fit in p_time_budget_s = 90, so
--   every night the walk would re-chew the same already-clean prefix, run out of
--   budget, and never reach the tail -- while reporting rows deleted. That is
--   "reports success while doing nothing", relocated. It would need a resume
--   mechanism bolted on, and a seq-ordered resume mechanism re-inherits the same
--   false assumption.
--
--   THE OCCURRED_AT WALK IS SELF-RESUMING WITH NO STATE AT ALL. Each night it
--   starts at the oldest surviving row older than the cut. If last night ran out of
--   budget, the rows it deleted are gone, so tonight starts precisely where last
--   night stopped -- no cursor, nothing to corrupt, nothing to strand.
--
--   WHY NOT THE BRIN THAT ALREADY EXISTS (ottoq_events_keep_occurred_at_idx1, 24 kB).
--   A BRIN summarises min/max per block range over PHYSICAL (insert) order. It is
--   only useful while physical order correlates with occurred_at -- which is the
--   precise assumption that just failed. It also cannot drive an ordered scan, and a
--   block range that straddles a purge boundary keeps a stale old minimum until it
--   is re-summarised, so the "is anything left?" probe re-reads dead blocks. It stays
--   (we never drop) and it remains fine for analytics range scans. It is the wrong
--   instrument for an exact, ordered, resumable delete.
--
-- ── WHAT THE INDEX COSTS. MEASURED, NOT ASSERTED. ───────────────────────────
-- An index is write cost on the hottest table in the system, so here is the bill.
--
--   SIZE. Live today: ottoq_events = 23,698 rows, 19 MB heap, 4,424 kB across 10
--   indexes. The closest analogue is the existing UNIQUE btree on event_seq -- also
--   an 8-byte key -- at 552 kB for those 23,698 rows = 23.9 bytes/row. Expect the
--   same shape:
--       ~ +570 kB at today's size   (+0.17% of the 330 MB database)
--       ~ +24 MB per million rows
--       ~ +2.9% on top of an ~840 B/row heap row
--
--   WRITE TIME. The table goes from 10 indexes to 11, so per-event index
--   maintenance rises by roughly 1/10 -- about +10% of the index share of an
--   insert, not +10% of the tick. It is the cheapest kind of btree insert
--   available: 99.92% of adjacent inserts are already in occurred_at order, so
--   essentially every new entry lands on the rightmost leaf page, hot in cache,
--   with no random page fetches and no splits away from the right edge. At the
--   protected write rate (~960 B/event, ~3.9 MB/real-min, i.e. ~4,000 events per
--   real-minute) that is tens of microseconds per event.
--
--   THE HONEST COUNTER-ARGUMENT. Index maintenance on THIS EXACT TABLE was the
--   root cause of the 7-22 s tick, back when it was 7.6 GB with 18 indexes, 8 of
--   them never scanned. Adding an 11th cuts against that recovery and I am not
--   going to pretend otherwise. Three things make it acceptable now: the table is
--   19 MB and not 7.6 GB; the index count is already down from 18 to 10; and this
--   index is the thing that KEEPS the table small, so it pays its own rent. It is
--   also the only one of the 11 whose job is to make a delete cheap rather than a
--   read.
--
--   THE EXIT IF IT HURTS. If the tick regresses past the protected ~3.7 s, this
--   index is the first suspect and it can be dropped without breaking correctness --
--   the walk stays exact, it just plans a bitmap or sequential scan instead. The
--   correctness lives in the ORDER BY, not in the index.
--
--   BUILD COST / LOCKING. Plain CREATE INDEX IF NOT EXISTS, not CONCURRENTLY,
--   because CONCURRENTLY cannot run inside a transaction block and this file is
--   applied as one script. On 23,698 rows that is milliseconds. It takes SHARE on
--   ottoq_events for that instant, which blocks writes -- so `SET lock_timeout` at
--   the top makes this file fail fast rather than queue behind a live tick. Apply
--   it with the engine idle (0 runs `running` at the time of writing).
--
-- ── WHAT ELSE MOVES IN THE WORKER, AND WHAT DOES NOT ────────────────────────
--   * The end-of-pass housekeeping (unschedule 'ottoq-retention-backlog', reset
--     pass_deleted) moves from the guessed early exit to the real end of the pass --
--     v_batch_ts IS NULL, i.e. genuinely nothing left older than the cut. Strictly
--     more correct: 0006 could unschedule the backlog job while a backlog remained.
--   * Protected rows cannot stall the walk. Rows belonging to a `running` or
--     production_live run sit inside the window but are excluded from the DELETE,
--     and the watermark advances past them regardless, so they are skipped rather
--     than retried forever. The watermark moves on every single iteration, so no
--     arrangement of protected rows can produce an infinite loop.
--   * occurred_at is NOT NULL (verified in information_schema, default now()), so
--     the `occurred_at < v_cut` predicate cannot leave a class of immortal rows the
--     way it would on a nullable column. Same property the 0006 walk relied on.
--   * ottoq_retention_state.cursor_block is a bigint and is WRITTEN, never read
--     back by anything that makes a decision (confirmed: only ottoq_purge_prior_runs
--     mentions the table, and only to list it as protected). It now carries the
--     walk's time watermark as epoch seconds so the pass stays observable. The
--     column is not dropped and not repurposed away.
--   * UNCHANGED: the policy-row override ('7 days', day_aligned), the day-aligned
--     cut, the protected-run exclusion, the per-iteration COMMIT, the
--     `ottoq.retention` flag re-armed every transaction (COMMIT clears it), the
--     advisory lock, the time budget, the anchor cleanup, and the two small-table
--     loops. The 3-argument overload is not touched. Nothing is dropped.
--   * This procedure is called only by cron job 11. It is not reachable from
--     decide_tick and cannot abort it.
--
-- ============================================================================
-- SCOPE -- WHAT THIS FILE DOES NOT DO
--   * No orchestration, LP, CSR build, cuOpt parse path, Gate B, verify_jwt or
--     decision behaviour is touched. No stall/bay assignment changes.
--   * trg_ottoq_auto_incident_report stays DISABLED. Not re-enabled, not mentioned
--     to Postgres at all.
--   * ottoq_apply_need_escalation stays at 0 callers. Not enabled.
--   * Nothing is DROPped -- no table, no column, no function, no index. No
--     VACUUM FULL. No data migration: the 11 already-laundered profiles are left
--     as they are (see GAP 4).
--   * Retention still cannot touch ottoq_run_archives, ottoq_sim_runs, the phase*/
--     fwd*/proof evidence tables, any non-ottoq-prefixed table, or the current run.
--
-- BLAST RADIUS
--   One function replaced (public.ottoq_wear_mark_serviced, 2 callers, both
--   PERFORM, return contract preserved), one procedure replaced (the 4-arg
--   public.ottoq_retention_purge_worker, 1 caller: cron job 11). ROUTINE COUNT
--   UNCHANGED -- nothing created, nothing dropped, so no name needs justifying
--   against db/baseline/functions_public.sql. ONE INDEX ADDED on ottoq_events;
--   that is a genuine schema delta and check-drift should show exactly it.
-- ============================================================================


-- Fail fast rather than queue behind a live tick: the CREATE INDEX below takes
-- SHARE on ottoq_events for an instant.
SET lock_timeout = '5s';
SET statement_timeout = '600s';


-- ============================================================================
-- §1  SNAPSHOT, THEN GUARD  (house rule 1)
--
-- Recover any pre-image later with:
--   SELECT definition FROM public.ottoq_schema_snapshots
--    WHERE label = '0008_soil_gate_and_retention_walk_pre' AND object_name = '<fn>';
-- ============================================================================
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0008_soil_gate_and_retention_walk_pre',
       CASE p.prokind WHEN 'p' THEN 'procedure' ELSE 'function' END,
       n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_wear_mark_serviced',
                     'ottoq_retention_purge_worker');

DO $guard$
DECLARE
  v_src text;
  v_n   int;
BEGIN
  -- ---- public.ottoq_wear_mark_serviced ---------------------------------------
  -- Exactly one signature, and it must still be the 0005 body this file reasoned
  -- about -- md5 d10f848b66b204b539805869034cb456, read live 2026-08-05.
  SELECT count(*), min(md5(pg_get_functiondef(p.oid)))
    INTO v_n, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_wear_mark_serviced';
  IF v_n = 0 THEN
    RAISE EXCEPTION 'GUARD: public.ottoq_wear_mark_serviced does not exist. This migration expected to REPLACE it, not create it. Nothing has been changed.';
  ELSIF v_n > 1 THEN
    RAISE EXCEPTION 'GUARD: public.ottoq_wear_mark_serviced has % overloads; this file assumes exactly one (uuid, uuid, text, timestamptz). Nothing has been changed.', v_n;
  ELSIF v_src <> 'd10f848b66b204b539805869034cb456' THEN
    RAISE EXCEPTION 'GUARD: public.ottoq_wear_mark_serviced is md5 % , not the 0005 body (d10f848b66b204b539805869034cb456) this migration quotes line-by-line. Someone changed it outside this repo. Re-read the live body, re-base, re-run. Nothing has been changed.', v_src;
  END IF;

  -- Belt and braces on the two defects themselves, so a future re-base cannot
  -- silently "fix" a bug that is no longer there.
  SELECT min(pg_get_functiondef(p.oid)) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_wear_mark_serviced';
  IF v_src NOT LIKE '%exterior_soil_level = COALESCE(round(v_soil, 3), p.exterior_soil_level)%' THEN
    RAISE EXCEPTION 'GUARD: the unconditional soil copy this migration removes is not present in the live body. Nothing has been changed.';
  END IF;
  IF v_src NOT LIKE '%open_fault_codes = CASE WHEN p_service IN (''fault_repair'',''mechanical_pm'')%' THEN
    RAISE EXCEPTION 'GUARD: the two-service fault clear this migration narrows is not present in the live body. Nothing has been changed.';
  END IF;

  -- ---- ottoq_retention_purge_worker (the 4-argument overload cron 11 calls) ---
  -- Two overloads are EXPECTED (3-arg and 4-arg). Only the 4-arg is replaced; the
  -- 3-arg is left exactly as it is -- we never drop.
  SELECT count(*), min(md5(pg_get_functiondef(p.oid)))
    INTO v_n, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_worker'
     AND pg_get_function_identity_arguments(p.oid) LIKE '%text[]%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'GUARD: expected exactly one 4-argument ottoq_retention_purge_worker (with the text[] table list); found %. Nothing has been changed.', v_n;
  ELSIF v_src <> '815c91faf7b57fc7cd7ed906b8cfca3a' THEN
    RAISE EXCEPTION 'GUARD: the 4-arg ottoq_retention_purge_worker is md5 % , not the 0006 §7 body (815c91faf7b57fc7cd7ed906b8cfca3a) this migration quotes. Someone changed it outside this repo. Re-read the live body, re-base, re-run. Nothing has been changed.', v_src;
  END IF;

  SELECT min(pg_get_functiondef(p.oid)) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_worker'
     AND pg_get_function_identity_arguments(p.oid) LIKE '%text[]%';
  IF v_src NOT LIKE '%IF v_n = 0 AND v_batch_ts >= v_cut THEN%' THEN
    RAISE EXCEPTION 'GUARD: the early exit this migration removes is not present in the live 4-arg worker. Nothing has been changed.';
  END IF;

  RAISE NOTICE 'GUARD: both replacement targets match what 0008 reasoned about.';
END
$guard$;

-- The shape the new retention walk rests on. Cheaper to fail here with a sentence
-- than inside a cron job with a 42703.
DO $shape$
DECLARE v_missing text[];
BEGIN
  SELECT array_agg(c) INTO v_missing FROM unnest(ARRAY[
      'occurred_at','sim_run_id']) c
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema='public' AND table_name='ottoq_events'
                        AND column_name = c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'GUARD: ottoq_events is missing %. Nothing has been changed.', v_missing;
  END IF;

  -- The new walk relies on occurred_at being NOT NULL: `occurred_at < v_cut` would
  -- silently make NULL-stamped rows immortal. Verified live 2026-08-05 (default now()).
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='ottoq_events'
                AND column_name='occurred_at' AND is_nullable='YES') THEN
    RAISE EXCEPTION 'GUARD: ottoq_events.occurred_at is nullable; the retention walk would leave NULL-stamped rows behind forever. Nothing has been changed.';
  END IF;

  -- The columns FIX (1) writes.
  SELECT array_agg(c) INTO v_missing FROM unnest(ARRAY[
      'exterior_soil_level','open_fault_codes','worst_fault_severity']) c
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema='public' AND table_name='vehicle_need_profile'
                        AND column_name = c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'GUARD: vehicle_need_profile is missing %. Nothing has been changed.', v_missing;
  END IF;

  RAISE NOTICE 'GUARD: ottoq_events and vehicle_need_profile shapes confirmed.';
END
$shape$;


-- ============================================================================
-- §2  FIX (1) — public.ottoq_wear_mark_serviced
--
-- Three lines change, all in PART 2. PART 1 is byte-for-byte the pre-image, and
-- so is every other write in PART 2. 0005 §3's wiring is not touched anywhere.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_wear_mark_serviced(p_vehicle_id uuid, p_sim_run_id uuid, p_service text, p_clock timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_wear_found boolean;
  v_drive_km   numeric;   -- ottoq_vehicle_wear.drive_km_total for this vehicle+run
  v_soil       numeric;   -- 0005: ottoq_vehicle_wear.soil_index, read AFTER part 1
BEGIN
  -- ══════════════ PART 1 — THE WEAR LEDGER (UNCHANGED, BYTE-FOR-BYTE) ══════════════
  UPDATE ottoq_vehicle_wear w SET
    soil_index = CASE WHEN p_service IN ('exterior_wash','sensor_clean','interior_deep_clean')
                      THEN 0 ELSE w.soil_index END,
    cabin_litter_events = CASE WHEN p_service IN ('interior_tidy','interior_deep_clean')
                      THEN 0 ELSE w.cabin_litter_events END,
    km_at_last_pm = CASE WHEN p_service = 'mechanical_pm'
                      THEN w.drive_km_total ELSE w.km_at_last_pm END,
    hours_at_last_calibration = CASE WHEN p_service = 'sensor_calibration'
                      THEN w.drive_hours_total ELSE w.hours_at_last_calibration END,
    calibrated_at = CASE WHEN p_service = 'sensor_calibration'
                      THEN p_clock ELSE w.calibrated_at END,
    open_dtc_count = CASE WHEN p_service IN ('fault_repair','mechanical_pm')
                      THEN 0 ELSE w.open_dtc_count END,
    worst_open_dtc_rank = CASE WHEN p_service IN ('fault_repair','mechanical_pm')
                      THEN 99 ELSE w.worst_open_dtc_rank END,
    updated_at = now()
  WHERE w.vehicle_id = p_vehicle_id AND w.sim_run_id = p_sim_run_id;

  -- Captured HERE, before anything else can move FOUND. See the header note.
  v_wear_found := FOUND;

  -- ══════════════ PART 2 — 0004: THE SAME TRUTH, IN THE LEDGER THAT IS READ ══════════════
  -- ══════════════          0005: ...INCLUDING THE CONDITION IT IS GRADED ON ══════════════
  -- ══════════════          0008: ...BUT ONLY WHAT THE JOB ACTUALLY DID      ══════════════
  -- Self-silencing by design: a failure here warns by name and leaves PART 1 standing.
  BEGIN
    -- The run-scoped counters. NULL in production (no run, no wear row), which the
    -- arithmetic below treats as "credit nothing / change nothing" rather than an error.
    -- 0005: soil_index is read HERE, i.e. AFTER part 1, so it is already 0 for the three
    -- services that clean the vehicle and is the live accrued value for every other.
    SELECT w.drive_km_total, w.soil_index
      INTO v_drive_km, v_soil
      FROM ottoq_vehicle_wear w
     WHERE w.vehicle_id = p_vehicle_id
       AND w.sim_run_id = p_sim_run_id
     LIMIT 1;

    UPDATE public.vehicle_need_profile p SET
      -- ── scope (b) of 0004: ODOMETER, ADVANCED IDEMPOTENTLY ────────────────
      -- Credit only the part of drive_km_total not already credited. A watermark from
      -- a different run (or none) means "unknown" -> credit 0 and re-anchor. 0005 §4
      -- anchors it at boot so the FIRST completion of a run credits real km.
      odometer_km = COALESCE(p.odometer_km, 0) + GREATEST(0,
                      COALESCE(v_drive_km, 0)
                      - CASE WHEN p.wear_km_applied_run IS NOT DISTINCT FROM p_sim_run_id
                             THEN COALESCE(p.wear_km_applied, COALESCE(v_drive_km, 0))
                             ELSE COALESCE(v_drive_km, 0) END),

      -- ── scope (a) of 0004: LAST-DONE, PER SERVICE ─────────────────────────
      -- Every branch is an absolute assignment of an observed clock. No accumulator,
      -- no chosen constant, no interval arithmetic. Unmapped codes fall through the
      -- ELSE and change nothing.
      last_wash_at = CASE WHEN p_service = 'exterior_wash'
                          THEN p_clock ELSE p.last_wash_at END,
      last_deep_clean_at = CASE WHEN p_service = 'interior_deep_clean'
                          THEN p_clock ELSE p.last_deep_clean_at END,
      last_calibration_at = CASE WHEN p_service = 'sensor_calibration'
                          THEN p_clock ELSE p.last_calibration_at END,
      last_pm_at = CASE WHEN p_service = 'mechanical_pm'
                          THEN p_clock ELSE p.last_pm_at END,

      -- PM mileage mark. Takes the POST-advance lifetime odometer -- recomputing the
      -- same advance expression inline, because SET clauses all read the row's OLD
      -- values and p.odometer_km above is not visible here. NOT wear.km_at_last_pm:
      -- that column is run-scoped and would read as ~zero lifetime km. See 0004.
      km_at_last_pm = CASE WHEN p_service = 'mechanical_pm'
                          THEN COALESCE(p.odometer_km, 0) + GREATEST(0,
                                 COALESCE(v_drive_km, 0)
                                 - CASE WHEN p.wear_km_applied_run IS NOT DISTINCT FROM p_sim_run_id
                                        THEN COALESCE(p.wear_km_applied, COALESCE(v_drive_km, 0))
                                        ELSE COALESCE(v_drive_km, 0) END)
                          ELSE p.km_at_last_pm END,

      -- ══════════ 0005 scope (b): THE CONDITION COLUMNS THE CARD ALSO GRADES ON ══════════

      -- ⭐ 0008 FIX (1a) — EXTERIOR SOIL. GATED TO A GENUINE WASH.
      -- WAS (0005): an UNGATED copy of the rounded wear soil_index into this column.
      -- (The exact pre-image line is quoted in this file's header, not here -- §5's
      --  POST check greps the live body for it, so it must not appear inside it.)
      -- i.e. every completion of any kind overwrote the card's BODY-soil grade with a
      -- SENSOR-soil counter. Both are clamped 0..1, so they are different quantities
      -- sharing a range, not one quantity in two places. Measured 2026-08-05: source
      -- max 0.3303 across 207 wear rows, against a 0.45 band floor -- so in practice
      -- it grades cars clean, and it did, on 11 of 11 vehicles it touched. It can also
      -- run the other way (0005's applied-commit smoke: an inspection moving this
      -- column 0.199 -> 0.480, inventing a wash). Direction depends on rain and km.
      -- NOW: only an exterior wash may clear body soil, because only an exterior wash
      -- removes it. In the sim PART 1 has already zeroed soil_index for this service, so
      -- the value still comes from the ledger; in production there is no wear row and the
      -- COALESCE supplies 0, the column's own clean floor -- an OEM reporting
      -- "exterior_wash complete" is asserting the body is clean. Every other service,
      -- including every inspection, leaves the column untouched: observing a car is not
      -- washing it. Still an absolute assignment, so still idempotent.
      exterior_soil_level = CASE WHEN p_service = 'exterior_wash'
                          THEN COALESCE(round(v_soil, 3), 0)
                          ELSE p.exterior_soil_level END,

      -- CABIN. Only what the completed work can honestly claim. A deep clean restores the
      -- cabin outright; a tidy clears litter and therefore may only lift 'light_litter'.
      -- Labels are the seeder's own vocabulary -- none invented. Self-extinguishing, so
      -- re-running is a no-op and a cabin can never be walked backwards.
      cabin_condition = CASE
                          WHEN p_service = 'interior_deep_clean' THEN 'clean'
                          WHEN p_service = 'interior_tidy'
                               AND p.cabin_condition = 'light_litter' THEN 'clean'
                          ELSE p.cabin_condition END,

      -- ⭐ 0008 FIX (1b) — FAULTS. A PM IS NOT A REPAIR.
      -- WAS (0005): both columns cleared for p_service IN ('fault_repair','mechanical_pm').
      -- Clearing them says "this vehicle has nothing wrong with it" -- 99 lands on the
      -- card's ELSE 0.00 branch = fault_urgency `ok`. A fault_repair has earned that.
      -- A scheduled preventive-maintenance job has not: it is booked on mileage, it runs
      -- whether or not a DTC is open, and it fixes the PM sheet, not the fault. Letting it
      -- wipe the fault list is the same defect as the soil copy -- a job reporting work it
      -- did not do -- and it hides outstanding work instead of completing it.
      -- 99 (not 0) is retained for the one service that still clears: severity is a rank
      -- where LOWER is worse, so 0 would grade a repaired vehicle overdue forever.
      -- KNOWN DIVERGENCE, DELIBERATE: PART 1 still zeroes the run-scoped wear ledger's
      -- open_dtc_count / worst_open_dtc_rank on mechanical_pm. That is certified pre-0005
      -- behaviour and is not retuned here. The profile -- the PRODUCTION surface the card
      -- reads -- now errs toward reporting the fault. See GAP 3.
      open_fault_codes = CASE WHEN p_service = 'fault_repair'
                          THEN '{}'::text[] ELSE p.open_fault_codes END,
      worst_fault_severity = CASE WHEN p_service = 'fault_repair'
                          THEN 99 ELSE p.worst_fault_severity END,

      -- SOFTWARE. Copies a column already on this row; sw_behind is defined as the
      -- inequality of these two. COALESCE so a NULL target cannot blank a real version.
      software_version = CASE WHEN p_service = 'software_update'
                          THEN COALESCE(p.sw_target_version, p.software_version)
                          ELSE p.software_version END,

      -- ITEMS. The retrieval IS the reset. item_reported_at / item_description are left
      -- alone deliberately: they are the record that it was reported, not the open flag.
      item_retrieval_pending = CASE WHEN p_service = 'item_retrieval'
                          THEN false ELSE p.item_retrieval_pending END,

      -- ── the watermark itself (0004, unchanged) ────────────────────────────
      -- Monotone within a run; re-anchored on a run change.
      wear_km_applied = CASE WHEN p.wear_km_applied_run IS NOT DISTINCT FROM p_sim_run_id
                             THEN GREATEST(COALESCE(p.wear_km_applied, 0), COALESCE(v_drive_km, 0))
                             ELSE COALESCE(v_drive_km, 0) END,
      wear_km_applied_run = p_sim_run_id,

      updated_at = now()
    WHERE p.vehicle_id = p_vehicle_id;

  EXCEPTION WHEN OTHERS THEN
    -- House rule 4. Loud, named, non-fatal. The wear ledger write above survives.
    RAISE WARNING 'ottoq_wear_mark_serviced: vehicle_need_profile reset FAILED SAFELY for vehicle % service %: % %',
                  p_vehicle_id, p_service, SQLSTATE, SQLERRM;
  END;

  RETURN v_wear_found;
END;
$function$;


-- ============================================================================
-- §3  FIX (2a) — THE INDEX THE NEW WALK IS ORDERED BY
--
-- Plain btree, not CONCURRENTLY (cannot run in a transaction block), not partial
-- (a partial index on "old" rows would need a constant cut date and would be wrong
-- the next day), not covering (the walk needs event_id and sim_run_id, but a
-- 3-column INCLUDE would triple the write cost to save one heap fetch per row on a
-- delete that is going to touch the heap anyway).
--
-- Cost, restated at the point of the change: ~24 bytes/row (+570 kB today, ~24 MB
-- per million rows), 10 indexes -> 11 so ~+10% of an insert's index maintenance,
-- landing on the rightmost leaf page for 99.92% of inserts. Full reasoning and the
-- exit route are in the header.
-- ============================================================================
CREATE INDEX IF NOT EXISTS ottoq_events_occurred_at_retention_idx
    ON public.ottoq_events USING btree (occurred_at);

COMMENT ON INDEX public.ottoq_events_occurred_at_retention_idx IS
  '0008: ordered oldest-first scan for ottoq_retention_purge_worker. The retention '
  'walk MUST be ordered by the same column its DELETE is predicated on -- event_seq '
  'order is measurably not occurred_at order (18 inversions in 23,697 adjacent pairs, '
  '2026-08-05) because occurred_at is the SIM clock and runs start at a random time '
  'of day. Droppable: the walk stays exact without it, only slower.';


-- ============================================================================
-- §4  FIX (2b) — public.ottoq_retention_purge_worker (4-argument overload)
--
-- Only the ottoq_events walk changes. Policy override, day-aligned cut, protected
-- runs, per-iteration COMMIT, the re-armed ottoq.retention flag, the advisory lock,
-- the time budget, the anchor cleanup and the two small-table loops are all as 0006
-- shipped them. The 3-argument overload is untouched.
--
-- NOTE ON STRUCTURE: this procedure COMMITs per iteration, so it cannot be wrapped
-- in a plpgsql EXCEPTION block (a block with a handler may not COMMIT). It is called
-- only by cron job 11, never from decide_tick, so a failure here cannot abort a tick.
-- ============================================================================
CREATE OR REPLACE PROCEDURE public.ottoq_retention_purge_worker(
  IN p_time_budget_s integer DEFAULT 60,
  IN p_micro_batch   integer DEFAULT 2000,
  IN p_keep          interval DEFAULT '48:00:00'::interval,
  IN p_tables        text[] DEFAULT ARRAY['ottoq_events'::text])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  v_keep      interval;
  v_aligned   boolean;
  v_cut       timestamptz;
  v_t0        timestamptz := clock_timestamp();
  v_n         bigint;
  v_total     bigint := 0;
  v_from      timestamptz;
  v_batch_ts  timestamptz;
  v_drained   boolean := false;
  v_live      uuid[];
BEGIN
  -- forward-compatible resolution without a SET clause (see migration notes):
  -- a routine with SET cannot COMMIT, and this procedure commits per iteration.
  PERFORM set_config('search_path', 'twin, ottoq, public, extensions', false);

  IF NOT pg_try_advisory_lock(hashtext('ottoq_retention_purge')) THEN
    RAISE NOTICE 'retention purge already running - skipped';
    RETURN;
  END IF;

  -- (2) policy wins over the caller's argument; fall back to it if no row.
  SELECT keep_interval, day_aligned INTO v_keep, v_aligned
    FROM public.ottoq_retention_policy WHERE policy_key = 'events' AND enabled;
  v_keep    := COALESCE(v_keep, p_keep);
  v_aligned := COALESCE(v_aligned, true);

  -- (3) day-aligned cut: delete only COMPLETE days older than the window.
  v_cut := now() - v_keep;
  IF v_aligned THEN
    v_cut := date_trunc('day', v_cut AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  END IF;

  -- (4) runs whose data may never be touched.
  SELECT COALESCE(array_agg(sim_run_id), '{}'::uuid[]) INTO v_live
    FROM public.ottoq_sim_runs
   WHERE status = 'running' OR COALESCE(run_by, '') = 'production_live';

  RAISE NOTICE 'retention purge: keep %, cut %, % protected run(s)',
               v_keep, v_cut, cardinality(v_live);

  -- ---------------------------------------------------------------------------
  -- EVENTS: oldest-first walk ordered by occurred_at — THE SAME COLUMN THE DELETE
  -- IS PREDICATED ON.
  --
  -- 0006 walked this table in event_seq order and stopped when a batch deleted
  -- nothing and its newest timestamp was inside the keep window. That stopping rule
  -- is an inference: "seq order is time order". It is false here -- occurred_at is
  -- the SIM clock and runs start at a random time of day, so a run whose clock sits
  -- behind the previous one writes old-timestamped rows at high event_seq. Measured
  -- 2026-08-05: 18 inversions in 23,697 adjacent pairs. Demonstrated end-to-end: with
  -- a 30-day-old row present and the real 7-day policy, the old worker processed one
  -- window, deleted 0, exited, and left the old row in place.
  --
  -- Ordering by occurred_at removes the inference entirely. There is nothing to
  -- guess: the loop ends when there are no rows older than the cut, which is the
  -- definition of finished rather than a proxy for it. It also needs no cursor --
  -- deleted rows are gone, so the next call naturally resumes at the oldest
  -- survivor. A pass cut short by the time budget costs nothing but time.
  -- ---------------------------------------------------------------------------
  IF 'ottoq_events' = ANY (p_tables) THEN
    v_from := '-infinity'::timestamptz;   -- start at the left edge of the index

    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);  -- re-arm each txn (COMMIT resets it)

      -- STEP 1 — pick this window's UPPER TIMESTAMP by reading exactly
      -- p_micro_batch index entries. This is a bounded, ordered slice of
      -- ottoq_events_occurred_at_retention_idx: O(batch), never O(heap).
      SELECT max(w.occurred_at) INTO v_batch_ts
        FROM (SELECT e.occurred_at
                FROM public.ottoq_events e
               WHERE e.occurred_at >= v_from
                 AND e.occurred_at <  v_cut
               ORDER BY e.occurred_at
               LIMIT p_micro_batch) w;

      -- No row at all older than the cut. That is not an inference about ordering --
      -- there is simply nothing left. THE ONLY EXIT THAT MEANS "DONE".
      IF v_batch_ts IS NULL THEN
        v_drained := true;
        COMMIT;
        EXIT;
      END IF;

      -- STEP 2 — delete the whole CLOSED TIMESTAMP RANGE [v_from, v_batch_ts].
      -- The window is a range of TIME, not a count of rows, and that is deliberate:
      -- it guarantees every row sharing v_batch_ts is inside this delete even if the
      -- LIMIT above cut the group in half. Without that, advancing the watermark past
      -- v_batch_ts could step over a deletable row that happened to share a
      -- microsecond with p_micro_batch protected ones. Many events DO share one
      -- occurred_at here -- it is the sim clock, and a tick writes 60-120 events at
      -- the same value -- so this is a real case, not a theoretical one.
      -- The window is therefore at most p_micro_batch plus the tail of one timestamp
      -- group; a group is bounded by one tick's event count, well under the batch.
      DELETE FROM public.ottoq_events e
       WHERE e.occurred_at >= v_from
         AND e.occurred_at <= v_batch_ts
         AND e.occurred_at <  v_cut
         AND (e.sim_run_id IS NULL OR NOT (e.sim_run_id = ANY (v_live)));
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;

      -- STEP 3 — advance. Everything at or below v_batch_ts and older than the cut
      -- has now been deleted or is protected, so stepping one microsecond past it
      -- (timestamptz resolution) cannot skip anything. v_from strictly increases
      -- every iteration, so the walk always terminates.
      v_from := v_batch_ts + interval '1 microsecond';

      -- Observability only. cursor_block is a bigint that nothing reads back to make
      -- a decision; it now carries the walk's time watermark as epoch seconds so a
      -- human can see where the pass got to. Never dropped, never repurposed away.
      UPDATE public.ottoq_retention_state
         SET cursor_block = floor(extract(epoch FROM v_from))::bigint,
             pass_deleted = pass_deleted + v_n,
             updated_at   = now()
       WHERE table_name = 'ottoq_events';
      IF NOT FOUND THEN
        INSERT INTO public.ottoq_retention_state (table_name, cursor_block, pass_deleted, updated_at)
        VALUES ('ottoq_events', floor(extract(epoch FROM v_from))::bigint, v_n, now())
        ON CONFLICT (table_name) DO NOTHING;
      END IF;

      COMMIT;  -- each window's work is permanent regardless of later failures
    END LOOP;

    -- End-of-pass housekeeping, moved here from 0006's early exit. It now fires only
    -- when the backlog is GENUINELY drained; the old placement could unschedule the
    -- backlog job while old rows remained, which is the whole bug in miniature.
    IF v_drained THEN
      PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'ottoq-retention-backlog';
      UPDATE public.ottoq_retention_state
         SET pass_deleted = 0, updated_at = now() WHERE table_name = 'ottoq_events';
      COMMIT;
    ELSE
      RAISE NOTICE 'retention purge: events pass stopped on the % s budget with work remaining; the next call resumes at the oldest survivor.', p_time_budget_s;
    END IF;

    -- Anchors follow their day. Because the cut is day-aligned, every event that
    -- could have folded onto one of these anchors has already gone.
    PERFORM set_config('ottoq.retention', 'on', true);
    DELETE FROM public.ottoq_event_state_anchor
     WHERE anchor_day < (v_cut AT TIME ZONE 'UTC')::date
       AND (sim_run_id IS NULL OR NOT (sim_run_id = ANY (v_live)));
    COMMIT;
  END IF;

  -- ---------------------------------------------------------------------------
  -- The two small tables. Same batching, same budget, unchanged from 0006 -- both
  -- already walk by their own timestamp column, so neither had the defect.
  -- ---------------------------------------------------------------------------
  IF 'ottoq_rule_evaluations' = ANY (p_tables) THEN
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);
      DELETE FROM public.ottoq_rule_evaluations WHERE evaluation_id IN (
        SELECT evaluation_id FROM public.ottoq_rule_evaluations
         WHERE evaluated_at < v_cut LIMIT p_micro_batch);
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
      COMMIT;
      EXIT WHEN v_n = 0;
    END LOOP;
  END IF;

  IF 'ottoq_incident_reports' = ANY (p_tables) THEN
    LOOP
      EXIT WHEN clock_timestamp() > v_t0 + make_interval(secs => p_time_budget_s);
      PERFORM set_config('ottoq.retention', 'on', true);
      DELETE FROM public.ottoq_incident_reports WHERE incident_report_id IN (
        SELECT incident_report_id FROM public.ottoq_incident_reports
         WHERE triggered_at < v_cut LIMIT p_micro_batch);
      GET DIAGNOSTICS v_n = ROW_COUNT;
      v_total := v_total + v_n;
      COMMIT;
      EXIT WHEN v_n = 0;
    END LOOP;
  END IF;

  RAISE NOTICE 'retention purge: % rows deleted this call', v_total;
  PERFORM pg_advisory_unlock(hashtext('ottoq_retention_purge'));
END;
$procedure$;

-- Make sure the cursor row the walk reports through exists.
INSERT INTO public.ottoq_retention_state (table_name, cursor_block, pass_deleted, updated_at)
VALUES ('ottoq_events', 0, 0, now())
ON CONFLICT (table_name) DO NOTHING;


-- ============================================================================
-- §5  POST-SNAPSHOTS
-- ============================================================================
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0008_soil_gate_and_retention_walk_post',
       CASE p.prokind WHEN 'p' THEN 'procedure' ELSE 'function' END,
       n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_wear_mark_serviced',
                     'ottoq_retention_purge_worker');

-- Post-condition: prove the two defects are gone from the live bodies, and that
-- nothing was dropped. Fails the migration if any of it is untrue.
DO $post$
DECLARE
  v_src text;
  v_n   int;
BEGIN
  SELECT min(pg_get_functiondef(p.oid)) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_wear_mark_serviced';
  IF v_src LIKE '%exterior_soil_level = COALESCE(round(v_soil, 3), p.exterior_soil_level)%' THEN
    RAISE EXCEPTION 'POST: the unconditional soil copy is still live. §2 did not take.';
  END IF;
  IF v_src LIKE '%open_fault_codes = CASE WHEN p_service IN (%' THEN
    RAISE EXCEPTION 'POST: the two-service fault clear is still live. §2 did not take.';
  END IF;
  IF v_src NOT LIKE '%exterior_soil_level = CASE WHEN p_service = ''exterior_wash''%' THEN
    RAISE EXCEPTION 'POST: the gated wash reset is not present. §2 did not take.';
  END IF;

  SELECT min(pg_get_functiondef(p.oid)) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_worker'
     AND pg_get_function_identity_arguments(p.oid) LIKE '%text[]%';
  IF v_src LIKE '%IF v_n = 0 AND v_batch_ts >= v_cut THEN%' THEN
    RAISE EXCEPTION 'POST: the early exit is still live. §4 did not take.';
  END IF;
  IF v_src NOT LIKE '%ORDER BY e.occurred_at%' THEN
    RAISE EXCEPTION 'POST: the occurred_at-ordered walk is not present. §4 did not take.';
  END IF;

  -- Both overloads still present -- we never drop.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_retention_purge_worker';
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'POST: expected both ottoq_retention_purge_worker overloads to survive; found %.', v_n;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = 'ottoq_events_occurred_at_retention_idx') THEN
    RAISE EXCEPTION 'POST: ottoq_events_occurred_at_retention_idx was not created. §3 did not take.';
  END IF;

  RAISE NOTICE 'POST: both fixes are live, both overloads survive, the index exists.';
END
$post$;


-- ============================================================================
-- §6  VERIFICATION — RUN THESE AFTER APPLYING. Copy the output into
--     MIGRATION_LOG.md. "Applied without error" is not "verified".
--
-- ── STATIC, RUN IMMEDIATELY, NO RUN REQUIRED ───────────────────────────────
--
-- V1. The defects are gone from the live bodies (this is also §5's POST block,
--     repeated here so a human can run it by hand):
--       SELECT p.proname,
--              pg_get_functiondef(p.oid) LIKE '%COALESCE(round(v_soil, 3), p.exterior_soil_level)%' AS soil_copy_still_there,
--              pg_get_functiondef(p.oid) LIKE '%IF v_n = 0 AND v_batch_ts >= v_cut THEN%'          AS early_exit_still_there
--         FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--        WHERE n.nspname='public'
--          AND p.proname IN ('ottoq_wear_mark_serviced','ottoq_retention_purge_worker');
--     EXPECT: both boolean columns false on every row.
--
-- V2. The index exists and costs what this file said it would:
--       SELECT pg_size_pretty(pg_relation_size('public.ottoq_events_occurred_at_retention_idx')),
--              (SELECT count(*) FROM public.ottoq_events) AS rows,
--              (SELECT count(*) FROM pg_index WHERE indrelid='public.ottoq_events'::regclass) AS n_indexes;
--     EXPECT: ~24 bytes/row (at 23,698 rows, roughly 560-600 kB), n_indexes = 11.
--     If bytes/row is far above 24, say so in the log rather than rounding it away.
--
-- V3. Nothing was dropped:
--       SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--        WHERE n.nspname='public';
--     EXPECT: identical to the pre-apply count. Two REPLACEs, zero creates, zero
--     drops. If it moved, diff the NAMES against db/baseline/functions_public.sql.
--
-- ── THE RETENTION FIX, PROVED THE WAY IT FAILED ────────────────────────────
--
-- V4. Reproduce the exact demonstration that exposed the bug, and watch it pass.
--     ⚠️ This INSERTS one synthetic old event and then deletes it. Do it with the
--     engine idle. The row is tagged so it is unmistakable.
--       -- (a) plant a 30-day-old row at the CURRENT high-water event_seq, which is
--       --     precisely the seq/time inversion the old walk could not see:
--       INSERT INTO public.ottoq_events (event_type, entity_type, entity_id, occurred_at, payload)
--       VALUES ('retention_probe_0008','vehicle', gen_random_uuid(),
--               now() - interval '30 days', '{"probe":"0008"}'::jsonb);
--       -- (b) count what is genuinely older than the policy cut:
--       SELECT count(*) FROM public.ottoq_events
--        WHERE occurred_at < date_trunc('day',(now()-interval '7 days') AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
--       -- EXPECT: >= 1.
--       -- (c) run the worker exactly as cron job 11 does:
--       CALL public.ottoq_retention_purge_worker(30, 2000, '7 days',
--            ARRAY['ottoq_events','ottoq_rule_evaluations','ottoq_incident_reports']);
--       -- (d) re-run (b).
--       -- EXPECT: 0.   OLD BEHAVIOUR: still 1, worker exited after one window.
--     This is the whole fix in one query pair. If (d) is not 0, stop and re-read.
--
-- V5. The walk terminates on a drained table instead of guessing:
--       CALL public.ottoq_retention_purge_worker(30, 2000, '7 days', ARRAY['ottoq_events']);
--     EXPECT in the NOTICEs: 'retention purge: 0 rows deleted this call', and NO
--     'stopped on the 30 s budget' notice -- i.e. it drained rather than timed out.
--     Then: SELECT * FROM public.ottoq_retention_state WHERE table_name='ottoq_events';
--     EXPECT pass_deleted = 0 (reset by the drained branch).
--
-- ── THE SOIL FIX, PROVED ON A RUN ──────────────────────────────────────────
--     ⚠️ BUDGET: ~3.9 MB/real-min. 4-6 real-minutes, then STOP. This is a
--        correctness fix, NOT an orchestration certification. Do not run 139 sim-min.
--     ⚠️ Starting a run purges the prior one. Preserve anything you need into a
--        NON-ottoq-prefixed table FIRST.
--     ⚠️ NEVER disable cron job 12.
--
-- V6. BEFORE the run, snapshot the graded fleet into a non-ottoq table (the name is
--     deliberately NOT ottoq-prefixed so no purge path can reach it):
--       CREATE TABLE IF NOT EXISTS proof0008_wash_before AS
--       SELECT vehicle_id, exterior_soil_level, last_wash_at, worst_fault_severity,
--              cardinality(open_fault_codes) AS n_faults
--         FROM public.vehicle_need_profile;
--
-- V7. AFTER the run stops -- THE HEADLINE CHECK. No vehicle may have had its body
--     soil lowered without an exterior wash to justify it. V6's snapshot must also
--     capture last_wash_at for this to be exact:
--       -- V6, revised:  ... SELECT vehicle_id, exterior_soil_level, last_wash_at,
--       --                          worst_fault_severity, cardinality(open_fault_codes) AS n_faults ...
--       SELECT count(*) AS soil_lowered,
--              count(*) FILTER (WHERE a.last_wash_at IS DISTINCT FROM b.last_wash_at)
--                       AS lowered_with_a_wash
--         FROM public.vehicle_need_profile a
--         JOIN proof0008_wash_before b USING (vehicle_id)
--        WHERE a.exterior_soil_level < b.exterior_soil_level;
--     EXPECT: soil_lowered = lowered_with_a_wash, i.e. EVERY reduction is explained
--     by a wash completion that moved last_wash_at, and 0 reductions if no vehicle
--     was washed. OLD BEHAVIOUR: one reduction per serviced vehicle, wash or no wash.
--     This single equality is the fix.
--
-- V8. The laundering signature is gone -- the profile no longer tracks the sensor
--     counter:
--       SELECT count(*) AS pairs,
--              count(*) FILTER (WHERE p.exterior_soil_level = round(w.soil_index,3)) AS still_copied
--         FROM public.vehicle_need_profile p JOIN public.ottoq_vehicle_wear w USING (vehicle_id);
--     PRE-FIX BASELINE, MEASURED 2026-08-05: 207 pairs, 11 copied, 11 of 11 below
--     0.45. EXPECT AFTER: `still_copied` does not grow with the number of
--     completions. It will not fall to 0 on its own -- the 11 already-laundered
--     rows are historical and this file does not rewrite data (GAP 4).
--
-- V9. A PM no longer wipes a fault list:
--       SELECT count(*) FROM public.vehicle_need_profile a
--         JOIN proof0008_wash_before b USING (vehicle_id)
--        WHERE b.n_faults > 0 AND cardinality(a.open_fault_codes) = 0;
--     EXPECT: only vehicles that completed a `fault_repair` in the run. Cross-check
--     against the run's done atoms for that service.
--
-- V10. 0005 §3 IS STILL DOING ITS JOB -- this file must not have broken the wiring
--      it was told to keep. Non-bay completions must still credit the ledger:
--       SELECT count(*) FROM public.vehicle_need_profile
--        WHERE updated_at > (SELECT started_at FROM public.ottoq_sim_runs
--                             ORDER BY started_at DESC LIMIT 1);
--      EXPECT: > 0, and of the same order as the previous run's figure. If this
--      collapses to 0, §2 broke something it was not supposed to touch.
--
-- V11. THE PROTECT LIST -- re-measure, do not regress: tick ~3.7 s; ~960 B/event
--      and ~3.9 MB/real-min; charging cut-short recovery; approvals 0 pending;
--      0 double-bookings; no starvation; phantoms 0; coverage 100%; emission
--      invariant 1.000; black box still produces a usable record; drift CLEAN.
--      The tick is the one this file could plausibly move (§3 adds an index to the
--      hottest table). Quote the measured number in the log either way.
--
-- ============================================================================
-- GAPS RECORDED, NOT FIXED HERE
--
-- GAP 1 -- BODY SOIL DOES NOT ACCRUE. Only two routines write
--   exterior_soil_level: the seeder (once, at boot) and this function (now, only on
--   a wash). So within a run a vehicle's body-soil grade can fall but never rise.
--   The card's other half, wash_ratio, IS time-based and does rise, so wash_urgency
--   is not frozen -- but the condition half is. This is the pre-0005 behaviour and
--   this file restores it deliberately. Anyone tempted to argue "but the copy WAS
--   our accrual, and it did rise sometimes" should note what it was accruing: sensor
--   grime, relabelled as body dirt, moving with rainfall on the sensor rather than
--   with dirt on the paint. A real fix means the twin accruing BODY soil (weather,
--   km, dwell) into its own column, on its own rate. That is a twin build and a
--   founder decision, and it is the right home for the number the card wants.
--
-- GAP 2 -- THE TWO LEDGERS NOW DISAGREE ON sensor_clean AND interior_deep_clean.
--   PART 1 zeroes soil_index for both; the profile's body-soil column no longer
--   follows. That is intentional -- washing a sensor is not washing the body -- and
--   it is 0005's own GAP 1 finally resolved rather than enacted. If it must be
--   reconciled, reconcile it in PART 1 (a behaviour change, founder call).
--
-- GAP 3 -- THE TWO LEDGERS NOW DISAGREE ON mechanical_pm AND FAULTS. PART 1 still
--   zeroes open_dtc_count / worst_open_dtc_rank on a PM. The profile no longer
--   clears its fault columns there. Chosen divergence, in the safe direction: the
--   production surface keeps reporting the fault. Reconcile by removing
--   'mechanical_pm' from PART 1's fault clear -- behaviour change, founder call.
--
-- GAP 4 -- THE 11 ALREADY-LAUNDERED PROFILES ARE NOT REPAIRED. Their real
--   pre-launder body-soil values were overwritten in place and are not recoverable
--   from anything on this database; the only honest reconstruction is a re-seed,
--   which would rewrite the whole fleet and destroy the ledger 0004/0005 built. A
--   run boot re-seeds profiles anyway, so this self-clears at the next boot. Do NOT
--   invent replacement values.
--
-- GAP 5 -- THE 3-ARGUMENT ottoq_retention_purge_worker STILL EXISTS AND STILL HAS
--   THE OLD SHAPE. Inherited from 0006's GAP 4, unchanged. Nothing calls it (cron
--   11 calls the 4-arg overload). We never drop, so it stays until someone decides
--   deliberately what to do with it. If anything ever starts calling it, it will
--   have the old defect.
-- ============================================================================
