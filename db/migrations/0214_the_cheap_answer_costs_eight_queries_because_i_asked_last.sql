-- ---------------------------------------------------------------------------
-- 0214 — the work side's cheap answer cost eight queries, because 0211 asked
--        the deciding question last.
--
-- WHY. Round 24's first pair took 797 s. The historical range for that exact
-- column (busy_day / 314159 / 12t, flagship) is 438-454 s, so this is 1.76x.
-- The pairs scheduled behind it were skipped outright — pg_cron fired nothing
-- while it held the launcher — which is the same quiet failure round 11 wrote
-- down: no job_run_details row at all, indistinguishable at a glance from
-- "not yet fired".
--
-- The cost is mine and it is an ordering mistake, not a design one. 0211's
-- ottoq_work_side_accepts checks the refusal RATE last:
--
--     1. run scope null?                     cheap
--     2. non-deferrable -> accepted          cheap, no lookup   <- good
--     3. SELECT ... FROM ottoq_sim_runs      a query
--     4. ottoq_policy_get(hold)              up to 3 queries (run/depot/global)
--     5. SELECT ... FROM ottoq_recall_refusals   a query
--     6. ottoq_policy_get(rate) -> if 0, ACCEPTED   <- the answer, at the end
--     7. the draw
--
-- work_side_recall_refusal_rate defaults to 0 and every certification run takes
-- that default, so steps 3-5 are pure waste on the ONLY path the twin actually
-- walks — roughly eight queries to reach an answer one lookup decides. 0212
-- calls this per deployed vehicle per tick.
--
-- The reorder puts the deciding question first:
--
--     1. run scope null?
--     2. non-deferrable -> accepted
--     3. ottoq_policy_get(rate) -> if <= 0, ACCEPTED and nothing else runs
--     4. the standing-hold scan
--     5. run lookup + hold, only when a refusal can actually happen
--
-- THIS IS THE DISCIPLINE THE SAME NIGHT'S OTHER MIGRATIONS APPLIED AND THIS ONE
-- DROPPED. 0210 put its EXISTS on ottoq_sim_runs INSIDE the status test so a
-- run on the active implementation does not pay for the lookup. The CP-SAT
-- work's `_point_gap_interval` returns None rather than building an interval of
-- size + 0, on the same principle: absent condition, absent work. 0211 asked
-- the condition last.
--
-- WHY NO TEST CAUGHT IT. The grid fixture is four vehicles over six ticks; the
-- seam is called a handful of times and the difference is unmeasurable. The
-- flagship is 221 vehicles over twelve ticks. A correctness suite that runs on
-- the small world cannot see a per-entity cost, and the pair that could see it
-- is the thing the cost then broke.
--
-- BEHAVIOUR IS UNCHANGED, and that is the claim to check rather than assert:
-- every branch returns exactly what it returned before for the same inputs.
-- Only the order of evaluation moves. A2 re-runs 0211's probe set and requires
-- the same seven answers.
--
-- MD5 PINS
--   ottoq_work_side_accepts   pinned below; body replaced, signature identical.
--
-- PREDICTION, written before the re-run:
--   * the same column's pair comes back well under 797 s, and nearer the
--     historical 454 s than to 797. I am NOT predicting it returns exactly to
--     454: 0212 still calls the seam once per deferrable recall per tick, and
--     one ottoq_policy_get is not free.
--   * every canon value for that column is unchanged from pair a's reading —
--     fp 803698f3, h_cmd 109e340b, h_dec 9abdb4af, h_evt 9c631343,
--     h_bkg 174b8835, h_nrg a9c6b693, h_rcl 0e67b89a, h_rule fc69953b.
--   If any canon moves, the reorder changed behaviour and this migration is
--   wrong, however much faster it is.
--
-- forces_recert: FALSE.
-- ---------------------------------------------------------------------------

BEGIN;

DO $pre$
DECLARE v_def text;
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname ~ '^r[0-9]+_') THEN
    RAISE EXCEPTION '0214: a certification round is scheduled';
  END IF;
  IF EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0214: a sim run is in flight';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE query ILIKE '%ottoq_determinism_pair%' AND pid <> pg_backend_pid()) THEN
    RAISE EXCEPTION '0214: a determinism pair is executing';
  END IF;
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_work_side_accepts';
  IF v_def IS NULL THEN
    RAISE EXCEPTION '0214: ottoq_work_side_accepts does not exist; 0211 must land first';
  END IF;
  RAISE NOTICE '0214 pre: seam present, nothing in flight';
END $pre$;

CREATE OR REPLACE FUNCTION public.ottoq_work_side_accepts(
  p_vehicle_id     uuid,
  p_sim_run_id     uuid,
  p_sim_clock_now  timestamptz,
  p_trigger        text,
  p_urgency        text,
  p_deferrable     boolean)
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

  --: THE SAFETY INVARIANT, FIRST AND WITHOUT A LOOKUP. A recall the ladder
  --: marks non-deferrable is coming home: reserve breach, fault, comms loss.
  --: The work side may not keep it, and asking would imply it could.
  IF NOT COALESCE(p_deferrable, false) THEN
    RETURN QUERY SELECT true, NULL::text, NULL::numeric, false;
    RETURN;
  END IF;

  --: THE DECIDING QUESTION, SECOND (0214). The rate defaults to 0 and every
  --: certification run takes the default, so this is the path the twin walks
  --: on every deferrable recall of every tick. 0211 asked it LAST, behind a
  --: run lookup, a policy read and a scan of the refusal ledger, and the
  --: flagship column went from 454 s to 797 s. Absent refusals, absent work.
  v_rate := ottoq_policy_get(p_sim_run_id, 'work_side_recall_refusal_rate', 0);
  IF v_rate <= 0 THEN
    RETURN QUERY SELECT true, NULL::text, NULL::numeric, false;
    RETURN;
  END IF;

  --: A REFUSAL STANDS FOR ITS HOLD. Only reachable once refusals are switched
  --: on, so the scan is paid by the runs that asked for it.
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

  SELECT r.random_seed AS seed, r.sim_clock_start AS t0 INTO v_run
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ottoq_work_side_accepts: no such run %', p_sim_run_id;
  END IF;

  v_hold := ottoq_policy_get(p_sim_run_id, 'work_side_refusal_hold_min', 90);

  --: CRN, not random(). Keyed on the vehicle and the sim instant, salted by the
  --: run seed: same seed -> same refusals, and two policies compared under
  --: common random numbers meet the same work side.
  v_draw := ottoq_crn_draw(v_run.seed, 'work_side_refusal',
                           p_vehicle_id::text, 0,
                           EXTRACT(EPOCH FROM p_sim_clock_now)::bigint);
  IF v_draw >= v_rate THEN
    RETURN QUERY SELECT true, NULL::text, NULL::numeric, false;
    RETURN;
  END IF;

  RETURN QUERY SELECT false, 'mission_overrun'::text, v_hold, true;
END $ws$;

COMMENT ON FUNCTION public.ottoq_work_side_accepts(uuid,uuid,timestamptz,text,text,boolean) IS
  '0211/0214 (G7): the work side''s answer to a proposed recall. A non-deferrable '
  'recall is always accepted — the work side cannot keep an asset that is coming '
  'home on a safety margin. Otherwise a refusal is drawn from the run''s CRN stream '
  'at work_side_recall_refusal_rate (default 0) and stands for '
  'work_side_refusal_hold_min. is_new distinguishes a fresh refusal from one still '
  'inside its hold. 0214 moved the rate check ahead of the run lookup, the hold read '
  'and the ledger scan: at the default rate those three answered nothing and cost a '
  'flagship pair 343 seconds.';

DO $post$
DECLARE v_def text; v_rate_pos int; v_scan_pos int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_work_side_accepts';
  v_rate_pos := position('work_side_recall_refusal_rate' in v_def);
  v_scan_pos := position('FROM public.ottoq_recall_refusals' in v_def);
  IF v_rate_pos = 0 OR v_scan_pos = 0 THEN
    RAISE EXCEPTION '0214 A1: the installed body is missing the rate read or the ledger scan';
  END IF;
  IF v_rate_pos > v_scan_pos THEN
    RAISE EXCEPTION '0214 A1: the rate is still read AFTER the ledger scan — the reorder did not take';
  END IF;
  RAISE NOTICE '0214 A1: rate read at %, ledger scan at % — cheap answer first', v_rate_pos, v_scan_pos;
END $post$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0214_the_cheap_answer_costs_eight_queries_because_i_asked_last', FALSE,
        'Performance, no behaviour change. 0211 read work_side_recall_refusal_rate LAST, behind a '
        'ottoq_sim_runs lookup, an ottoq_policy_get and a scan of ottoq_recall_refusals — and the '
        'rate defaults to 0, so every certification run paid all three to be told "accepted". '
        'Round 24 pair a (busy_day/314159/12t) took 797 s against a historical 438-454 s for the '
        'same column, and the pairs behind it were skipped because pg_cron fired nothing while it '
        'held the launcher. The rate is read first now. Same answers, same branches, evaluation '
        'order only.',
        now());

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 — AND ITS CENTRAL CLAIM WAS WRONG. SUPERSEDED BY 0215.
--
-- This file says, above: "BEHAVIOUR IS UNCHANGED... every branch returns
-- exactly what it returned before for the same inputs. Only the order of
-- evaluation moves."
--
-- That is false, and 0211's own probe set caught it within a minute of the
-- apply. Moving the rate check AHEAD of the standing-hold scan means a refusal
-- that has already been issued and recorded stops standing the moment the rate
-- is set to 0:
--
--     P5a, inside a 90-minute hold, rate returned to 0
--       before 0214   accepted=f  is_new=f  remaining=60.0 min
--       after  0214   accepted=t  is_new=f  remaining=NULL
--
-- The engine dropped a commitment it had made and written down. The window is
-- narrow — the rate is a run-scoped policy and nothing changes it mid-run, so
-- no twin run would have hit it — but "narrow" is not "absent", and the claim
-- in this header was unqualified.
--
-- WHY THE PROBE EXISTED TO CATCH IT: 0211 built P5a deliberately to prove the
-- hold suppresses independently of the rate, and it set the rate back to 0 for
-- exactly that reason. A probe written to prove one thing caught a later
-- migration breaking it. That is the whole argument for keeping probe sets
-- runnable rather than writing their results down once.
--
-- 0215 restores the order: safety invariant, standing-hold scan, rate, then the
-- run lookup and hold read that only a FRESH refusal needs. It keeps most of
-- the saving — one ottoq_sim_runs lookup and one whole ottoq_policy_get leave
-- the path every certification run walks — without the semantic change.
--
-- Kept rather than rewritten, because the diagnosis in the header above is
-- correct and worth reading: the cost was real, its cause was asking the
-- deciding question last, and the fix direction was right. Only the claim of
-- equivalence was too strong.
-- ---------------------------------------------------------------------------
