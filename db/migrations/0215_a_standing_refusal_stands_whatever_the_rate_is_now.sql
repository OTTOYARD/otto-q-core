-- ---------------------------------------------------------------------------
-- 0215 — a standing refusal stands, whatever the rate is now. Corrects 0214.
--
-- 0214 was right about the cost and wrong about the equivalence. Its diagnosis
-- holds: ottoq_work_side_accepts read work_side_recall_refusal_rate LAST,
-- behind a ottoq_sim_runs lookup, an ottoq_policy_get and a scan of
-- ottoq_recall_refusals, and the rate defaults to 0, so every certification run
-- paid all three to be told "accepted". Round 24's first pair took 797 s
-- against a historical 438-454 s for the same column.
--
-- Its fix went one step too far. Putting the rate ahead of the standing-hold
-- scan means a refusal already issued and recorded stops standing as soon as
-- refusals are disabled. 0211's probe P5a exists precisely to prove the hold
-- suppresses INDEPENDENTLY of the rate — it sets the rate back to 0 for that
-- reason — and it went from `accepted=f, remaining=60.0` to `accepted=t,
-- remaining=NULL`. The engine abandoning a commitment it had written down.
--
-- THE ORDER THAT IS BOTH CORRECT AND CHEAP:
--
--   1. safety invariant       non-deferrable -> accepted, no lookup at all
--   2. standing-hold scan     one index probe on
--                             (sim_run_id, vehicle_id, refused_at_sim DESC);
--                             on a run that has never refused it returns
--                             nothing and costs almost nothing
--   3. the rate               the exit every certification run takes
--   4. run lookup + hold read + CRN draw   only when a FRESH refusal is possible
--
-- Steps 2 and 3 are the only cost at the default rate: one index probe and one
-- ottoq_policy_get. 0211 charged a ottoq_sim_runs lookup and a SECOND
-- ottoq_policy_get on top of those, and both answered nothing.
--
-- THE GENERAL RULE, worth stating because this is the second time tonight it
-- decided a design: absent condition, absent work — but the condition has to be
-- the one that actually decides. 0210 got it right (the EXISTS on
-- ottoq_sim_runs sits INSIDE the status test). The CP-SAT work got it right
-- (`_point_gap_interval` returns None rather than an interval of size + 0).
-- 0211 asked the deciding question last; 0214 moved it first and stepped over a
-- question that had to be asked earlier still.
--
-- PROBE, all eight answers identical to 0211's originals:
--   P1  rate 0, deferrable                   accepted, is_new f
--   P2  rate 1, deferrable                   refused, mission_overrun, 90, is_new t
--   P3  rate 1, NON-deferrable               accepted            <- safety invariant
--   P4  rate 1.0 refused 4/4; rate 0.5 refused 2/4
--   P5a inside the hold, rate back to 0      refused, is_new f, 60.0 min remaining
--   P5b after the hold                       accepted
--   P6  UPDATE                               refused, append-only
--
-- forces_recert: FALSE.

BEGIN;

CREATE OR REPLACE FUNCTION public.ottoq_work_side_accepts(
  p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamptz,
  p_trigger text, p_urgency text, p_deferrable boolean)
RETURNS TABLE(accepted boolean, reason_code text, retry_after_min numeric, is_new boolean)
LANGUAGE plpgsql STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $ws$
DECLARE
  v_run record; v_rate numeric; v_hold numeric; v_draw double precision; v_prior record;
BEGIN
  IF p_sim_run_id IS NULL THEN
    RAISE EXCEPTION 'ottoq_work_side_accepts requires a run scope';
  END IF;

  --: 1. THE SAFETY INVARIANT, first and without a lookup.
  IF NOT COALESCE(p_deferrable, false) THEN
    RETURN QUERY SELECT true, NULL::text, NULL::numeric, false;
    RETURN;
  END IF;

  --: 2. A STANDING REFUSAL STANDS, WHATEVER THE RATE IS NOW (0215).
  SELECT f.reason_code AS rc, f.refused_at_sim AS at, f.retry_after_min AS hold INTO v_prior
    FROM public.ottoq_recall_refusals f
   WHERE f.sim_run_id = p_sim_run_id AND f.vehicle_id = p_vehicle_id
     AND p_sim_clock_now < f.refused_at_sim + make_interval(mins => f.retry_after_min::int)
   ORDER BY f.refused_at_sim DESC LIMIT 1;
  IF FOUND THEN
    RETURN QUERY SELECT false, v_prior.rc,
                        EXTRACT(EPOCH FROM (v_prior.at + make_interval(mins => v_prior.hold::int)
                                            - p_sim_clock_now)) / 60.0,
                        false;
    RETURN;
  END IF;

  --: 3. THE RATE — the exit every certification run takes.
  v_rate := ottoq_policy_get(p_sim_run_id, 'work_side_recall_refusal_rate', 0);
  IF v_rate <= 0 THEN
    RETURN QUERY SELECT true, NULL::text, NULL::numeric, false;
    RETURN;
  END IF;

  --: 4. Only reachable when refusals are switched on.
  SELECT r.random_seed AS seed, r.sim_clock_start AS t0 INTO v_run
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ottoq_work_side_accepts: no such run %', p_sim_run_id;
  END IF;
  v_hold := ottoq_policy_get(p_sim_run_id, 'work_side_refusal_hold_min', 90);

  v_draw := ottoq_crn_draw(v_run.seed, 'work_side_refusal', p_vehicle_id::text, 0,
                           EXTRACT(EPOCH FROM p_sim_clock_now)::bigint);
  IF v_draw >= v_rate THEN
    RETURN QUERY SELECT true, NULL::text, NULL::numeric, false;
    RETURN;
  END IF;

  RETURN QUERY SELECT false, 'mission_overrun'::text, v_hold, true;
END $ws$;

-- A1. THE ORDER IS CHECKED, NOT DESCRIBED ------------------------------------
DO $post$
DECLARE v_def text; v_scan int; v_rate int; v_runq int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_work_side_accepts';
  v_scan := position('FROM public.ottoq_recall_refusals' in v_def);
  v_rate := position('work_side_recall_refusal_rate' in v_def);
  v_runq := position('FROM public.ottoq_sim_runs r' in v_def);
  IF NOT (v_scan < v_rate AND v_rate < v_runq) THEN
    RAISE EXCEPTION '0215 A1: order is scan=% rate=% runlookup=%; want scan < rate < runlookup',
                    v_scan, v_rate, v_runq;
  END IF;
  RAISE NOTICE '0215 A1: hold scan %, rate %, run lookup %', v_scan, v_rate, v_runq;
END $post$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0215_a_standing_refusal_stands_whatever_the_rate_is_now', FALSE,
        'CORRECTS 0214. 0214 claimed "same answers, evaluation order only" and that was false: '
        'moving the rate check ahead of the standing-hold scan meant a refusal already issued '
        'stopped standing as soon as refusals were disabled. 0214''s own probe set caught it '
        '(P5a accepted f -> t). Order is now: safety invariant, standing-hold scan, rate, then the '
        'run lookup and hold read that only a FRESH refusal needs.',
        now());

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 to gxdrcyphqjzjsuhxuqtg, immediately after 0214, which it
-- corrects. Verified after commit by re-running 0211's probe set in full:
--
--   P1  rate 0, deferrable        accepted=t is_new=f          (0211: t/f)
--   P2  rate 1, deferrable        accepted=f mission_overrun 90 is_new=t
--   P3  rate 1, NON-deferrable    accepted=t                   <- safety invariant
--   P4  rate 1.0  refused 4 / accepted 0        (0211: 4/0)
--       rate 0.5  refused 2 / accepted 2        (0211: 2/2)
--   P5a inside the hold, rate back to 0
--                                 accepted=f is_new=f remaining=60.0
--                                 (0211: f/f/60.0 — THE ONE 0214 BROKE)
--   P5b after the hold            accepted=t                   (0211: t)
--   P6  UPDATE                    refused, append-only         (0211: refused)
--
-- Eight of eight identical to 0211's originals. A1 passed: the installed body
-- orders the hold scan before the rate and the rate before the run lookup.
--
-- The speed claim is measured separately, by re-running the column that
-- exposed the cost (busy_day / 314159 / 12t, flagship). Pair a under 0211's
-- ordering took 797 s against a historical 438-454 s. Whatever the re-run
-- returns is recorded in db/canons/round24.md as a reading, not here as a
-- hope.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- CORRECTION 2026-09-08, appended after the re-measurement landed. The premise
-- of 0214 — and therefore the reason 0215 exists at all — was FALSE.
--
-- The re-run of busy_day / 314159 / 12t on the flagship took 801 s against the
-- 797 s it was compared with. 0215 saved nothing measurable, because there was
-- nothing to save.
--
-- The "historical 438-454 s" in 0214's header is a real number from a real
-- reading, but it is not this column's recent history. The full run-details
-- series for this exact column (db/canons/round24.md carries it in full) is:
--
--   09-01  389            09-05  545 681 697 744
--   09-02  308 ... 500    09-06  688 724 741 804 804
--   09-03  431 ... 614    09-07  643 758 822
--   09-04  512 652        09-08  797 801
--
-- Monotone drift over seven days on a fixed seed, tick count, scenario and
-- depot. 09-06 reached 804 s with none of 0209-0212 applied. There was no step
-- change when they landed and there is no regression to attribute to 0211.
--
-- So the honest ledger for this pair of migrations: 0214 chased a phantom and
-- broke a standing refusal doing it; 0215 restored the behaviour and is
-- correct on its own terms (its ordering IS the better one, and its A1 block
-- keeps it that way); together they are a behavioural no-op, which round 24's
-- two pairs prove atom by atom — seven canon values reproduced round 22 and
-- only h_rule moved, exactly as 0208 requires.
--
-- The rule I should have followed and did not: BEFORE attributing a slowdown to
-- a change, plot the metric's own history across the change. One query against
-- cron.job_run_details would have refuted the whole excursion in thirty
-- seconds. It is the same failure db/checks/0098 records — reasoning from a
-- remembered number instead of re-measuring — and this time the stale number
-- was one I wrote down myself four hours earlier.
--
-- What the excursion bought, which is why it is not a total loss: the duration
-- series above is the signature of accumulating table size, and following it
-- convicted the missing index on ottoq_stall_bookings.leg_id AND the
-- unordered LIMIT 1 in the SDR terminus that hides behind it. Both are in
-- 0216. See db/checks/0123.
-- ---------------------------------------------------------------------------
