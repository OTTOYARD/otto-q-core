-- 0255  G71 ANSWERED: 29 OF 39 REFUSALS ASKED FOR A STALL THAT WAS ALREADY HELD
--       WHEN THE PROPOSAL WAS MADE. THAT IS STALENESS, NOT CONTENTION.
--
-- G71 (db/checks/0250 §5, restated in 0251) said a refusal for `stall_occupied`
-- does not distinguish two very different things:
--   * CONTENTION -- the stall was free when proposed and someone took it before
--     the kernel disposed. Nobody is at fault; the depot is busy.
--   * STALENESS -- the stall was ALREADY taken when the proposer proposed it. The
--     proposer reasoned over an out-of-date frame, and the refusal is its own.
-- The two have opposite fixes, and until now the ledger could not tell them apart.
--
-- ══ 1. THE ANSWER ══════════════════════════════════════════════════════════
--
--   disposition_reason   refused   held when proposed   free when proposed
--   stall_reserved            26                   18                    8
--   stall_occupied            13                   11                    2
--   ------------------------------------------------------------------------
--   total                     39            29 (74%)             10 (26%)
--
-- **Three quarters of the refusals are the proposer being late, not the depot
-- being busy.** On `stall_occupied` specifically it is 11 of 13.
--
-- This is the charitable reading inverted. 0250 §2 observed that every refusal
-- landed on `l2`/`dcfc` at 87%/80% occupancy and concluded contention -- which was
-- the right conclusion from what was measurable THEN, and is now the minority
-- case. Scarcity is real and is not the dominant mechanism here.
--
-- ══ 2. WHY THIS IS G62 BITING, AND WHAT IT MEANS ═══════════════════════════
--
-- G62 measured the agent chain at a mean of 30,394 ms against a 30-second beat,
-- with 39% of calls exceeding one tick. A proposal that takes longer than a tick
-- to produce is a proposal about a world that has already moved. The refusals are
-- the arithmetic consequence.
--
-- So the fix is NOT more stalls, and NOT a smarter objective. It is one of:
--   (a) give the proposer a fresher frame (cut the chain latency below one tick);
--   (b) have it propose a RANKED SET the kernel can pick from, so one taken stall
--       does not waste the whole proposal;
--   (c) re-validate and re-target at dispose time rather than refusing outright.
-- (b) is the cheapest and the most robust to latency, and it is the propose/dispose
-- pattern CLAUDE.md already describes -- the proposer proposes, the solver
-- disposes. A single-stall proposal gives the disposer nothing to dispose over.
--
-- NOT BUILT HERE. This file measures; choosing among (a)/(b)/(c) is a design call.
--
-- ══ 3. TWO INDEPENDENT METHODS, BECAUSE ONE WOULD NOT BE ENOUGH ════════════
--
-- Method A (Q1) asks WHEN THE WINNING BOOKING WAS MADE, purely in wall clock:
-- `booking.booked_at < proposal.created_at` means the stall was claimed before the
-- proposal existed. 28 of 39 stale. Its weakness is that it does not check the
-- booking was still HELD -- a stall booked and released before the proposal would
-- be miscounted as stale.
--
-- Method B (Q2) closes that hole by asking WAS THE STALL HELD AT PROPOSE TIME,
-- using the booking's `during` range: `during @> <proposal created_at, in sim>`.
-- 29 of 39 stale.
--
-- **28 and 29 of 39. The two methods agree to within one row in aggregate**, which
-- is what makes the finding robust rather than an artifact of either query.
--
-- BUT NOT ROW FOR ROW, AND THE DIFFERENCE IS WORTH STATING RATHER THAN HIDING
-- BEHIND THE TOTAL: only **24** proposals are called stale by BOTH methods. Four
-- are stale to A alone and five to B alone. So the AGGREGATE is solid and the
-- PER-ROW classification is not fully concordant -- a proposal near a booking
-- boundary can fall either side depending on whether you ask "when was it
-- claimed" or "was it held". Quote the proportion; do not quote a verdict on an
-- individual proposal from either method alone.
--
-- ══ 4. THE CLOCK BRIDGE METHOD B NEEDS, AND THE DEFECT IT EXPOSED (G75) ════
--
-- Method B has to compare a proposal timestamp against a booking range, and they
-- are on DIFFERENT CLOCKS. Measured on run 92a6ac36:
--
--   proposal.created_at / disposed_at   WALL   (2026-09-20 00:23)
--   booking.booked_at                   WALL   (2026-09-20 00:23)
--   booking.booked_at_sim               SIM    (2026-09-19 16:12)
--   booking.during                      SIM    (2026-09-19 13:00 ->)
--   booking.released_at                 SIM    (2026-09-19 13:01 -> 16:15)
--
-- Because `ottoq_stall_bookings` carries BOTH clocks on the same row
-- (`booked_at` and `booked_at_sim`), the table is its own conversion table. Q2
-- uses the nearest-in-wall-time booking to convert a proposal's wall timestamp to
-- sim, then tests the range. That is exact to the resolution of the bridge rows,
-- and there are 1,200+ of them on a run.
--
-- **G75, found on the way, and it is a real trap.** `booked_at` is WALL and
-- `released_at` is SIM, on the same row, with names that read as a natural pair.
-- Measured: **1,202 of 1,202 released bookings have `released_at < booked_at`** --
-- a stall released before it was booked, in 100% of rows. Anyone computing hold
-- duration the obvious way gets a NEGATIVE number every time.
--
-- SEVERITY, CALIBRATED RATHER THAN ASSERTED: **latent, not live.** Measured, no
-- routine or view anywhere does `released_at - booked_at` arithmetic -- the two
-- functions that touch both columns (`ottoq_enact_space_assignment`,
-- `ottoq_record_enacted_booking`) only SET `released_at`. Duration is taken from
-- the `during` range, whose bounds are both SIM and therefore internally
-- consistent. So no number ships wrong today. It is a landmine for the next
-- person to write the obvious query -- which is exactly what this file was about
-- to do -- and it sits directly under 2.9's KPI #2
-- (`service_point_turns_per_point_per_day`) and KPI #5 (`p95_time_to_service`).
-- The fix is to stamp `released_at` on the wall clock to match `booked_at` and add
-- `released_at_sim` beside `booked_at_sim`, which is a migration, not a comment.
--
-- ══ 5. WHAT THIS DOES NOT ESTABLISH ════════════════════════════════════════
--
-- * It does not say the proposals were BAD. A stale proposal can still name the
--   right stall; it just names one that is gone. Quality needs an outcome
--   comparison, which is a different instrument.
-- * 10 of 39 refusals ARE genuine contention, and on a depot at 87%/80% charge
--   occupancy that number would grow if latency were fixed. Scarcity is still
--   real (0250) -- it is just not the dominant mechanism in the refusals.
-- * It is within-run only. `ottoq_external_proposals` is class `engine` and the
--   demo-run purge takes it, which is G72 and still open.
--
-- Nothing in this file changes engine state.
--
-- ── THE QUERIES ────────────────────────────────────────────────────────────

-- Q1  METHOD A: when was the stall claimed, relative to the proposal? Wall clock
--     throughout, so no conversion is involved and nothing can go wrong in the
--     bridge. Weaker (it does not test "still held") and independent, which is
--     the point of running both.
WITH ref AS (
  SELECT p.proposal_id, p.sim_run_id, (p.proposal->>'stall_id')::uuid AS stall_id,
         p.created_at, p.disposed_at, p.disposition_reason
    FROM public.ottoq_external_proposals p
   WHERE p.status = 'refused' AND p.proposal ? 'stall_id'),
win AS (
  SELECT r.proposal_id, r.disposition_reason,
         min(b.booked_at) FILTER (WHERE b.booked_at <  r.created_at)   AS claimed_before_propose,
         min(b.booked_at) FILTER (WHERE b.booked_at >= r.created_at
                                    AND b.booked_at <= r.disposed_at)  AS claimed_during_window
    FROM ref r
    LEFT JOIN public.ottoq_stall_bookings b
           ON b.stall_id = r.stall_id AND b.sim_run_id = r.sim_run_id
   GROUP BY 1, 2)
SELECT disposition_reason,
       count(*)                                                              AS refused,
       count(*) FILTER (WHERE claimed_during_window IS NOT NULL)              AS contention,
       count(*) FILTER (WHERE claimed_during_window IS NULL
                          AND claimed_before_propose IS NOT NULL)             AS stale_frame,
       count(*) FILTER (WHERE claimed_during_window IS NULL
                          AND claimed_before_propose IS NULL)                 AS no_booking_found
  FROM win
 GROUP BY 1
 ORDER BY refused DESC;

-- Q2  METHOD B: was the stall HELD at the moment of proposal? Uses the `during`
--     range, which is the authoritative record (it is the column the EXCLUDE
--     constraint enforces). Needs the wall->sim bridge described in §4.
WITH bridge AS (
  --: ottoq_stall_bookings carries BOTH clocks on one row, so it converts between
  --: them. 1,200+ rows per run makes the nearest-neighbour exact enough.
  SELECT booked_at AS wall, booked_at_sim AS sim
    FROM public.ottoq_stall_bookings
   WHERE booked_at IS NOT NULL AND booked_at_sim IS NOT NULL),
ref AS (
  SELECT p.proposal_id, p.sim_run_id, (p.proposal->>'stall_id')::uuid AS stall_id,
         p.disposition_reason,
         (SELECT b.sim + (p.created_at - b.wall)
            FROM bridge b
           ORDER BY abs(extract(epoch FROM (b.wall - p.created_at)))
           LIMIT 1) AS created_at_sim
    FROM public.ottoq_external_proposals p
   WHERE p.status = 'refused' AND p.proposal ? 'stall_id')
SELECT r.disposition_reason,
       count(*) AS refused,
       count(*) FILTER (WHERE EXISTS (
         SELECT 1 FROM public.ottoq_stall_bookings b
          WHERE b.stall_id = r.stall_id AND b.sim_run_id = r.sim_run_id
            AND b.during @> r.created_at_sim))     AS stall_held_when_proposed,
       count(*) FILTER (WHERE NOT EXISTS (
         SELECT 1 FROM public.ottoq_stall_bookings b
          WHERE b.stall_id = r.stall_id AND b.sim_run_id = r.sim_run_id
            AND b.during @> r.created_at_sim))     AS stall_free_when_proposed
  FROM ref r
 GROUP BY 1
 ORDER BY refused DESC;

-- Q3  §3's corroboration as one row. Method A here uses Q1's EXACT definition --
--     a booking before the proposal AND none during the window. An earlier draft
--     used a bare EXISTS without the second clause and reported 33 against B's 29,
--     which is not a disagreement between methods but between two different
--     definitions of method A. Apples to apples it is 28 against 29.
WITH bridge AS (
  SELECT booked_at AS wall, booked_at_sim AS sim FROM public.ottoq_stall_bookings
   WHERE booked_at IS NOT NULL AND booked_at_sim IS NOT NULL),
ref AS (
  SELECT p.proposal_id, p.sim_run_id, (p.proposal->>'stall_id')::uuid AS stall_id,
         p.created_at, p.disposed_at,
         (SELECT b.sim + (p.created_at - b.wall) FROM bridge b
           ORDER BY abs(extract(epoch FROM (b.wall - p.created_at))) LIMIT 1) AS created_at_sim
    FROM public.ottoq_external_proposals p
   WHERE p.status = 'refused' AND p.proposal ? 'stall_id'),
cls AS (
  SELECT (EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                   WHERE b.stall_id=r.stall_id AND b.sim_run_id=r.sim_run_id
                     AND b.booked_at < r.created_at)
          AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                           WHERE b.stall_id=r.stall_id AND b.sim_run_id=r.sim_run_id
                             AND b.booked_at >= r.created_at
                             AND b.booked_at <= r.disposed_at))        AS stale_a,
         EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                  WHERE b.stall_id=r.stall_id AND b.sim_run_id=r.sim_run_id
                    AND b.during @> r.created_at_sim)                   AS stale_b
    FROM ref r)
SELECT count(*)                                              AS refused_total,
       count(*) FILTER (WHERE stale_a)                        AS method_a_stale,
       count(*) FILTER (WHERE stale_b)                        AS method_b_stale,
       abs(count(*) FILTER (WHERE stale_a)
         - count(*) FILTER (WHERE stale_b))                   AS aggregate_delta,
       count(*) FILTER (WHERE stale_a AND stale_b)            AS both_call_it_stale,
       abs(count(*) FILTER (WHERE stale_a)
         - count(*) FILTER (WHERE stale_b)) <= 2              AS methods_agree_in_aggregate
  FROM cls;

-- Q4  G75: the mixed-clock columns, and the impossible ordering they produce.
--     `released_before_booked` must be 0 in any sane table; it is 100% of rows.
SELECT count(*)                                                AS released_rows,
       min(booked_at)   AS booked_min,   max(booked_at)   AS booked_max,
       min(released_at) AS released_min, max(released_at) AS released_max,
       count(*) FILTER (WHERE released_at < booked_at)          AS released_before_booked,
       count(*) FILTER (WHERE released_at < booked_at) = count(*)
                                                                AS every_single_row_is_impossible
  FROM public.ottoq_stall_bookings
 WHERE released_at IS NOT NULL;

-- Q5  G75's severity, calibrated rather than asserted: nothing computes a
--     duration across the two columns, so no number ships wrong today. If this
--     ever returns a row, the finding has gone from latent to live.
SELECT n.nspname || '.' || p.proname AS does_duration_math_across_the_two_clocks
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g')
         ~* '(released_at\s*-\s*booked_at|booked_at\s*-\s*released_at|age\s*\(\s*released_at)'
 ORDER BY 1;
