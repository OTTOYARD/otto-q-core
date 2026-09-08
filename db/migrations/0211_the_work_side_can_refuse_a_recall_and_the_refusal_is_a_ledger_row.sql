-- migration-version: APPLIED-NO-LEDGER-ROW
-- migration-name:    the_work_side_can_refuse_a_recall_and_the_refusal_is_a_ledger_row
-- (applied through execute_sql, which writes no supabase_migrations row; the
--  file's own APPLIED footer is the record. See task G18.)
-- ---------------------------------------------------------------------------
-- 0211 — the work side gets a voice, and its refusal is a row.
--
-- WHY (G7; CLAUDE.md 2.7 and C9): "Work-side refusal (mission overrun) is a
-- first-class event triggering re-solve, never an error."
--
-- It is not, in the database. Traced 2026-09-08:
--
--   twin.ottoq_sim_advance_deployed_telemetry is the ONLY consumer of the
--   recall decision in the tick. It emits telemetry, calls
--   ottoq_evaluate_return_need, and on should_return goes straight into the
--   RETURN HANDSHAKE: ottoq_return_eta_minutes, ottoq_book_appointment, then
--   UPDATE ottoq_vehicle_dispatches SET status = 'returning'.
--
-- Nowhere in that sequence is the work side asked. OTTO-Q decides an asset is
-- coming home and books the stall; the system that owns the mission has no
-- veto. The interface CLAUDE.md calls "the single interface between the worlds"
-- runs in one direction only.
--
-- Two corroborating readings, both taken rather than assumed:
--   * ottoq_event_types_catalog has carried `recall_issued` and `recall_refused`
--     since migration 0045 (2026-08-19), described as "Canonical: the work side
--     refused a recall — first-class, triggers re-solve (C9)". Emitted count for
--     both: ZERO. So are move_start, move_end and touch_event: five canonical
--     types registered and never once written.
--   * ottoq_variability_catalog has six domains — energy_grid, environment,
--     fleet_demand, operations, reliability, vehicle — and no work_side. The
--     twin can vary the weather, the grid, the staff and the vehicles. It cannot
--     vary whether the mission lets the asset go.
--
-- WHAT THIS MIGRATION DOES. The seam and the ledger, nothing wired yet:
--   A1  ottoq_recall_refusals, append-only, run-scoped, one row per refusal,
--       bound to the ottoq_recall_decisions row it refuses.
--   A2  the reason vocabulary, as a CHECK rather than a convention.
--   A3  two policy parameters, catalogued: the refusal rate and the retry hold.
--   A4  ottoq_work_side_accepts(), the seam the tick will call.
--   A5  the run-scope registry entry, or the purge check would rightly refuse.
-- Migration 0212 wires it into the tick. They ship together; 0211 alone is a
-- capability nothing calls, which is the defect class this build keeps finding,
-- and it is split only so the hot-path rewrite carries its own proof.
--
-- THE SAFETY INVARIANT, and it is the whole reason this is not just a flag:
-- A NON-DEFERRABLE RECALL IS NOT REFUSABLE. The rung ladder marks a recall
-- deferrable or not; reserve breaches and faults are not. The work side may
-- keep an asset that merely needs a wash. It may not keep one that is coming
-- home on a safety margin. `ottoq_work_side_accepts` returns accepted = true
-- for those without consulting anything, and A4's probe proves a refusal rate
-- of 1.0 does not move them.
--
-- DETERMINISM. The draw is ottoq_crn_draw(run_seed, 'work_side_refusal',
-- vehicle, 0, sim-epoch) — the same common-random-number primitive the rest of
-- the twin uses, IMMUTABLE and hash-based. Same seed, same refusals; different
-- seeds, different worlds; and two policies compared under CRN see the SAME
-- work-side behaviour, which is what makes the comparison mean anything. A
-- refusal drawn from random() would have destroyed the reproducibility this
-- whole codebase exists to defend.
--
-- NEUTRAL BY DEFAULT. work_side_recall_refusal_rate defaults to 0. Nothing
-- refuses until a run asks for it, so no certified column can move.
--
-- forces_recert: FALSE. Additive only — a table, a function, two catalog rows,
-- one registry row. Nothing in the decide path calls any of it yet.
-- ---------------------------------------------------------------------------

BEGIN;

DO $pre$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname ~ '^r[0-9]+_') THEN
    RAISE EXCEPTION '0211: a certification round is scheduled';
  END IF;
  IF EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0211: a sim run is in flight';
  END IF;
  IF to_regclass('public.ottoq_recall_refusals') IS NOT NULL THEN
    RAISE EXCEPTION '0211: ottoq_recall_refusals already exists';
  END IF;
  IF to_regclass('public.ottoq_recall_decisions') IS NULL THEN
    RAISE EXCEPTION '0211: ottoq_recall_decisions is missing; 0206 must land first';
  END IF;
  RAISE NOTICE '0211 pre: nothing in flight, the ledger to bind to exists, the new one does not';
END $pre$;

-- A1 + A2. THE LEDGER ------------------------------------------------------
CREATE TABLE public.ottoq_recall_refusals (
  refusal_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  refusal_seq       bigint GENERATED ALWAYS AS IDENTITY,
  --: the decision being refused. NO ACTION, like ottoq_recall_decisions' own
  --: FK: a refusal is evidence and must not vanish because something upstream
  --: was purged; the purge order is the run-scope registry's business.
  recall_id         uuid NOT NULL REFERENCES public.ottoq_recall_decisions(recall_id)
                      ON DELETE NO ACTION,
  sim_run_id        uuid NOT NULL,
  vehicle_id        uuid NOT NULL,
  depot_id          uuid,
  refused_at_sim    timestamptz NOT NULL,
  refused_at        timestamptz NOT NULL DEFAULT now(),
  --: who refused. The work side is a separate system; its identity is not
  --: OTTO-Q's to assume, so it is recorded and never defaulted to a person.
  refused_by        text NOT NULL,
  --: A CHECK, not a convention. An unconstrained reason column is how
  --: `no_capacity` came to be written nowhere and read everywhere (L-11).
  reason_code       text NOT NULL CHECK (reason_code IN (
                      'mission_overrun',     -- the mission is still running
                      'passenger_onboard',   -- a rider is aboard
                      'safety_hold',          -- the work side holds it for safety
                      'operator_override',    -- a human said no
                      'unreachable')),        -- the work side did not answer
  --: how long OTTO-Q must not re-ask. Bounded below so a refusal cannot be a
  --: no-op that re-fires every tick, and above so it cannot strand an asset.
  retry_after_min   numeric NOT NULL CHECK (retry_after_min > 0 AND retry_after_min <= 720),
  --: what OTTO-Q wanted, kept beside the refusal so the pair reads on its own
  recall_trigger    text,
  recall_urgency    text,
  was_deferrable    boolean,
  evidence          jsonb NOT NULL DEFAULT '{}'::jsonb,
  content_hash      text NOT NULL,
  data_source       text NOT NULL DEFAULT 'twin'
);

COMMENT ON TABLE public.ottoq_recall_refusals IS
  '0211 (G7): one row per work-side refusal of a recall. CLAUDE.md 2.7 — a '
  'refusal is a first-class event that triggers re-solve, never an error. '
  'Append-only. A non-deferrable recall is never refusable; see '
  'ottoq_work_side_accepts.';

CREATE INDEX ottoq_recall_refusals_run_idx     ON public.ottoq_recall_refusals (sim_run_id, refused_at_sim);
CREATE INDEX ottoq_recall_refusals_vehicle_idx ON public.ottoq_recall_refusals (sim_run_id, vehicle_id, refused_at_sim DESC);
CREATE INDEX ottoq_recall_refusals_recall_idx  ON public.ottoq_recall_refusals (recall_id);

-- A3. APPEND-ONLY ----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_recall_refusals_append_only()
RETURNS trigger LANGUAGE plpgsql AS $ao$
BEGIN
  RAISE EXCEPTION 'ottoq_recall_refusals is append-only (attempted %)', TG_OP;
END $ao$;

CREATE TRIGGER ottoq_recall_refusals_no_update
  BEFORE UPDATE OR DELETE ON public.ottoq_recall_refusals
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_recall_refusals_append_only();

-- A4. THE POLICY PARAMETERS, CATALOGUED -------------------------------------
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects)
VALUES
 ('work_side_recall_refusal_rate',
  'Probability in [0,1] that the work side refuses a DEFERRABLE recall, drawn '
  'from the run''s CRN stream so it is reproducible under seed. 0 = the work '
  'side never refuses, which is the behaviour before 0211/0212 and the default. '
  'A non-deferrable recall is never refusable at any rate.',
  0, 0, 1,
  'ottoq_work_side_accepts -> twin.ottoq_sim_advance_deployed_telemetry; whether a recall books a stall'),
 ('work_side_refusal_hold_min',
  'Minutes OTTO-Q holds off re-asking after a refusal. The refusal stands for '
  'this long; the asset stays deployed and the next tick re-solves around it.',
  90, 1, 720,
  'ottoq_work_side_accepts; how long one refusal suppresses the recall');

-- A5. THE SEAM -------------------------------------------------------------
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

  SELECT r.random_seed, r.sim_clock_start INTO v_run
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ottoq_work_side_accepts: no such run %', p_sim_run_id;
  END IF;

  v_hold := ottoq_policy_get(p_sim_run_id, 'work_side_refusal_hold_min', 90);

  --: A REFUSAL STANDS FOR ITS HOLD. Without this the same draw would be taken
  --: every tick and either re-refuse (a ledger full of duplicates) or flip to
  --: accept as the tick key moved, which would make a refusal meaningless.
  SELECT f.reason_code, f.refused_at_sim, f.retry_after_min INTO v_prior
    FROM public.ottoq_recall_refusals f
   WHERE f.sim_run_id = p_sim_run_id AND f.vehicle_id = p_vehicle_id
     AND p_sim_clock_now < f.refused_at_sim + make_interval(mins => f.retry_after_min::int)
   ORDER BY f.refused_at_sim DESC LIMIT 1;
  IF FOUND THEN
    RETURN QUERY SELECT false, v_prior.reason_code,
                        EXTRACT(EPOCH FROM (v_prior.refused_at_sim
                          + make_interval(mins => v_prior.retry_after_min::int)
                          - p_sim_clock_now)) / 60.0,
                        false;
    RETURN;
  END IF;

  v_rate := ottoq_policy_get(p_sim_run_id, 'work_side_recall_refusal_rate', 0);
  IF v_rate <= 0 THEN
    RETURN QUERY SELECT true, NULL::text, NULL::numeric, false;
    RETURN;
  END IF;

  --: CRN, not random(). Keyed on the vehicle and the sim instant, salted by the
  --: run seed: same seed -> same refusals, and two policies compared under
  --: common random numbers meet the same work side.
  v_draw := ottoq_crn_draw(v_run.random_seed, 'work_side_refusal',
                           p_vehicle_id::text, 0,
                           EXTRACT(EPOCH FROM p_sim_clock_now)::bigint);
  IF v_draw >= v_rate THEN
    RETURN QUERY SELECT true, NULL::text, NULL::numeric, false;
    RETURN;
  END IF;

  RETURN QUERY SELECT false, 'mission_overrun'::text, v_hold, true;
END $ws$;

COMMENT ON FUNCTION public.ottoq_work_side_accepts(uuid,uuid,timestamptz,text,text,boolean) IS
  '0211 (G7): the work side''s answer to a proposed recall. A non-deferrable '
  'recall is always accepted — the work side cannot keep an asset that is '
  'coming home on a safety margin. Otherwise a refusal is drawn from the run''s '
  'CRN stream at work_side_recall_refusal_rate (default 0) and stands for '
  'work_side_refusal_hold_min. is_new distinguishes a fresh refusal, which the '
  'caller records and emits, from one still inside its hold.';

-- A6. RUN SCOPE ------------------------------------------------------------
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note, registered_at)
VALUES ('public', 'ottoq_recall_refusals', 'sim_run_id', 'engine',
        '0211: a twin run''s work-side refusals die with the run; production '
        'refusals (data_source = production) are permanent, exactly as 0206 '
        'classified ottoq_recall_decisions.', now());

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 to gxdrcyphqjzjsuhxuqtg. Verified after commit:
--   ottoq_recall_refusals      created, append-only trigger live
--   ottoq_work_side_accepts    created
--   policy catalog             work_side_recall_refusal_rate (default 0),
--                              work_side_refusal_hold_min (default 90)
--   run-scope registry         ottoq_recall_refusals.sim_run_id, class engine
--
-- SEAM PROBES, one rolled-back transaction, all seven as designed:
--   P1  rate 0, deferrable          accepted
--   P2  rate 1, deferrable          refused, mission_overrun, hold 90, is_new
--   P3  rate 1, NON-deferrable      ACCEPTED  <- the safety invariant
--   P4  the same call twice         one distinct answer; 4 of 4 vehicles
--       refused at 1.0 and 2 of 4 at 0.5, so the rate is a rate
--   P5a inside the hold             refused, is_new false, 60 min remaining —
--       AND with the rate put back to 0, which is the point: the hold is what
--       suppresses, not the knob
--   P5b after the hold              accepted
--   P6  UPDATE                      refused, append-only
--
-- A NOTE ON P4's FIRST READING. It was written as "4 of 20 vehicles refused",
-- which reads like a broken rate. The grid fixture has four vehicles; the
-- LIMIT 20 never bound. Re-measured with the denominator counted rather than
-- assumed: 4 of 4 at rate 1.0, 2 of 4 at 0.5.
--
-- THE LINEAGE ROW WAS MISSING FROM THIS FILE and was inserted separately a few
-- minutes after the apply. Recorded here rather than quietly fixed: a migration
-- that does not register itself is invisible to the floor machinery.
-- ---------------------------------------------------------------------------
