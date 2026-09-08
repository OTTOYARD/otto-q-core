-- ---------------------------------------------------------------------------
-- 0212 — the tick asks the work side, and a refusal re-solves instead of raising.
--
-- 0211 built the ledger and the seam. This wires it into the one place that
-- consumes a recall decision: twin.ottoq_sim_advance_deployed_telemetry.
--
-- BEFORE: emit telemetry -> ottoq_evaluate_return_need -> if should_return,
--   ottoq_return_eta_minutes, ottoq_book_appointment, UPDATE dispatches SET
--   status = 'returning'. The work side is never consulted.
--
-- AFTER: the same, with one question in front of the handshake. If the work
-- side refuses, `v_should_return` goes false and the EXISTING code does the
-- rest: no booking, no state flip, the asset stays deployed, and the next tick
-- evaluates it again. That last part is the re-solve, and it is why this is a
-- small change — the engine already knows how to leave an asset out and come
-- back to it. That branch is the deferrable-need-with-no-free-stall path the
-- function has always had; a refusal joins it rather than inventing a new one.
--
-- A REFUSAL IS NEVER AN ERROR. Nothing raises. CLAUDE.md 2.7 is explicit, and
-- the surrounding code agrees: the booking call is already wrapped so that "one
-- bad vehicle must never abort the whole telemetry step".
--
-- THE ACTOR IS `ottow_dispatcher`, AND THE REASON IS WORTH RECORDING. The
-- refusal is emitted as a `recall_refused` event, which needs an actor_type, and
-- ottoq_events CHECKs that column against a twenty-value vocabulary that has no
-- work_side. Rather than rewrite a CHECK on a 2.5M-row table inside this change,
-- the refusal is attributed to `ottow_dispatcher` — already in the vocabulary,
-- unused until now, and meaning exactly the work-side dispatcher. A
-- sector-neutral `work_side` actor is the better long-term name (the kernel is
-- not supposed to know it sits beside OTTO-W); adding it is a constraint
-- migration on the event table and belongs on its own.
--
-- `recall_refused` HAS BEEN REGISTERED SINCE 0045 AND EMITTED ZERO TIMES. So
-- have recall_issued, move_start, move_end and touch_event. This migration
-- makes exactly one of the five real. recall_issued is deliberately NOT emitted
-- here: it would fire on every recall in every run, moving h_evt on every
-- certified column at once, and that is a recert to schedule rather than a side
-- effect to discover.
--
-- ONE THING THIS ALMOST SHIPPED. The first draft read v_dispatch.home_depot_id.
-- The loop cursor is `SELECT d.*, ...` over ottoq_vehicle_dispatches joined to
-- vehicles, and it selects battery_capacity_kwh, current_soc, min_soc_threshold,
-- current_state, display_name, fleet_operator_id and a config scalar -- not the
-- home depot, which the dispatches table does not have at all. plpgsql compiles
-- a body lazily, so that would have installed cleanly and raised inside the tick
-- the first time a work side refused. The depot is a scalar subquery now, paid
-- only on the refusal path.
--
-- MD5 PINS
--   twin.ottoq_sim_advance_deployed_telemetry
--     7777fdcb1191ce5c8530ac73281bc03a -> pinned below after splicing
--
-- PREDICTION, before the pair runs:
--   * With work_side_recall_refusal_rate at its default 0, the grid_smoke
--     column reproduces the 2026-09-08 baseline EXACTLY:
--       fp d9ea88c5 · h_cmd e4158c95 · h_dec c37ba832 · h_evt 79fa107a
--       h_bkg 2c955357 · h_nrg beb1b391 · h_rcl f981b17b · h_rule d62d9672
--   * With the rate at 1.0 the pair still PASSES (both arms identical — the
--     draw is CRN, not random()) and the hashes MOVE (the world is different).
--   A pair that fails at rate 1.0 means the refusal path is nondeterministic
--   and this migration is wrong.
--
-- forces_recert: FALSE — at the default rate nothing refuses, and the
-- prediction above is the test of that claim rather than its assertion.
-- ---------------------------------------------------------------------------

BEGIN;

DO $pre$
DECLARE v_def text; v_n int; v_anchor text;
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname ~ '^r[0-9]+_') THEN
    RAISE EXCEPTION '0212: a certification round is scheduled';
  END IF;
  IF EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0212: a sim run is in flight';
  END IF;
  IF to_regclass('public.ottoq_recall_refusals') IS NULL THEN
    RAISE EXCEPTION '0212: 0211 must land first';
  END IF;

  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_deployed_telemetry';
  IF md5(v_def) <> '7777fdcb1191ce5c8530ac73281bc03a' THEN
    RAISE EXCEPTION '0212: the telemetry tick is not at the pinned 7777fdcb (found %)', md5(v_def);
  END IF;

  v_anchor := '    v_should_return := COALESCE(v_ret_should, false);';
  v_n := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0212: the decision anchor appears % times, not once', v_n;
  END IF;
  RAISE NOTICE '0212 pre: tick pinned, anchor unique, refusal ledger present, nothing in flight';
END $pre$;

DO $rw$
DECLARE v_def text; v_new text; v_anchor text; v_decl text; v_block text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_deployed_telemetry';

  v_decl := '  v_progress       NUMERIC;';
  v_new := replace(v_def, v_decl, v_decl || '
  v_ws             RECORD;    -- 0212: the work side''s answer
  v_recall_id      UUID;      -- 0212: the decision a refusal names');

  v_anchor := '    v_should_return := COALESCE(v_ret_should, false);';
  v_block := v_anchor || '

    -- 0212 (G7): ASK THE WORK SIDE BEFORE THE HANDSHAKE.
    -- CLAUDE.md 2.7: refusal is first-class and triggers re-solve, never an
    -- error. A non-deferrable recall is not offered for refusal -- see
    -- ottoq_work_side_accepts, which returns accepted without a lookup.
    IF v_should_return AND v_dispatch.status = ''active'' THEN
      SELECT * INTO v_ws FROM public.ottoq_work_side_accepts(
        v_dispatch.vehicle_id, p_sim_run_id, p_sim_clock_now,
        v_ret_trigger, v_ret_urgency, COALESCE(v_ret_deferrable, false));

      IF NOT v_ws.accepted THEN
        IF v_ws.is_new THEN
          SELECT rd.recall_id INTO v_recall_id
            FROM public.ottoq_recall_decisions rd
           WHERE rd.sim_run_id = p_sim_run_id
             AND rd.vehicle_id = v_dispatch.vehicle_id
             AND rd.decided_at_sim = p_sim_clock_now
           ORDER BY rd.decision_seq DESC LIMIT 1;

          -- A refusal that cannot name the decision it refuses is not evidence,
          -- so it is not written and the recall proceeds. Reachable only under
          -- ottoq.dryrun, where the wrapper writes no decision row.
          IF v_recall_id IS NOT NULL THEN
            INSERT INTO public.ottoq_recall_refusals
              (recall_id, sim_run_id, vehicle_id, depot_id, refused_at_sim,
               refused_by, reason_code, retry_after_min, recall_trigger,
               recall_urgency, was_deferrable, evidence, content_hash, data_source)
            VALUES
              (v_recall_id, p_sim_run_id, v_dispatch.vehicle_id,
               (SELECT v.home_depot_id FROM public.vehicles v WHERE v.id = v_dispatch.vehicle_id),
               p_sim_clock_now, ''ottow_dispatcher'', v_ws.reason_code,
               v_ws.retry_after_min, v_ret_trigger, v_ret_urgency,
               COALESCE(v_ret_deferrable, false),
               jsonb_build_object(''soc'', v_new_soc, ''recall_evidence'', v_ret_ev),
               md5(v_dispatch.vehicle_id::text || ''|''
                   || to_char(p_sim_clock_now AT TIME ZONE ''UTC'', ''YYYY-MM-DD HH24:MI:SS.US'') || ''|''
                   || v_ws.reason_code || ''|'' || COALESCE(v_ret_trigger, ''-'') || ''|''
                   || COALESCE(v_ret_urgency, ''-'') || ''|'' || v_ws.retry_after_min::text),
               CASE WHEN (SELECT r.run_by FROM public.ottoq_sim_runs r
                           WHERE r.sim_run_id = p_sim_run_id) = ''production_live''
                    THEN ''production'' ELSE ''twin'' END);

            PERFORM ottoq_record_event(
              p_actor_type    := ''ottow_dispatcher'',
              p_actor_id      := ''work_side'',
              p_event_type    := ''recall_refused'',
              p_entity_type   := ''vehicle'',
              p_entity_id     := v_dispatch.vehicle_id,
              p_fleet_operator_id := v_dispatch.v_fleet_op,
              p_depot_id      := (SELECT v.home_depot_id FROM public.vehicles v
                                   WHERE v.id = v_dispatch.vehicle_id),
              p_severity      := ''warning'',
              p_payload       := jsonb_build_object(
                                   ''reason_code'', v_ws.reason_code,
                                   ''retry_after_min'', v_ws.retry_after_min,
                                   ''recall_trigger'', v_ret_trigger,
                                   ''recall_urgency'', v_ret_urgency,
                                   ''deferrable'', COALESCE(v_ret_deferrable, false)),
              p_sim_run_id    := p_sim_run_id);

            v_should_return := false;
          END IF;
        ELSE
          -- still inside a standing refusal''s hold: suppress without a new row
          v_should_return := false;
        END IF;
      END IF;
    END IF;';

  v_new := replace(v_new, v_anchor, v_block);
  EXECUTE v_new;
END $rw$;

DO $post$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_deployed_telemetry';
  IF v_def NOT LIKE '%ottoq_work_side_accepts%' THEN
    RAISE EXCEPTION '0212 A1: the seam is not in the installed body';
  END IF;
  IF v_def NOT LIKE '%recall_refused%' THEN
    RAISE EXCEPTION '0212 A2: the event is not emitted from the installed body';
  END IF;
  RAISE NOTICE '0212 post: tick now asks the work side; new md5 %', md5(v_def);
END $post$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0212_the_tick_asks_the_work_side_before_it_books_the_stall', FALSE,
        'G7. twin.ottoq_sim_advance_deployed_telemetry asks ottoq_work_side_accepts before the '
        'return handshake; a refusal writes ottoq_recall_refusals, emits recall_refused (the '
        'first time that type has been emitted since it was registered by 0045) and sets '
        'v_should_return false, so the asset stays deployed and the next tick re-solves. Never '
        'raises. A non-deferrable recall is not refusable. At the default refusal rate of 0 '
        'nothing refuses and the grid_smoke column reproduces its 2026-09-08 baseline exactly.',
        now());

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 to gxdrcyphqjzjsuhxuqtg.
--   twin.ottoq_sim_advance_deployed_telemetry
--     7777fdcb1191ce5c8530ac73281bc03a -> 35486348dff298a567c4d56f8989bd73
--   ottoq_cert_recert_floor()  2026-09-07 21:36:53.363037+00  UNMOVED
--
-- BOTH PREDICTIONS HELD, and they are the two that matter together.
--
-- 1. AT THE DEFAULT RATE, NOTHING MOVED. grid_smoke/424242/6t, run against the
--    baseline taken before 0211 on the same day:
--      fp d9ea88c5 · h_cmd e4158c95 · h_dec c37ba832 · h_evt 79fa107a
--      h_bkg 2c955357 · h_nrg beb1b391 · h_rcl f981b17b · h_rule d62d9672
--    All eight identical, outcome passed. The tick was rewritten and the twin
--    did not notice, which is the only acceptable result for a hot-path change
--    whose knob is off.
--
-- 2. AT RATE 1.0 THE PAIR STILL PASSED AND THE WORLD CHANGED. Both arms
--    identical (equal = true) while h_evt, h_bkg, h_dec and h_rcl all moved.
--    That combination is the whole proof: identical arms mean the refusal is
--    drawn from the CRN stream and not from random(); moved hashes mean the
--    refusal actually reached the schedule instead of being recorded and
--    ignored. Either half alone would have been worthless.
--
--    arm A 3 refusals, arm B 3 refusals, and the two arms' content hashes
--    agree exactly (71200303b1edfec9087a3461f79cd598).
--    recall_refused events: 6. That event type was registered by migration
--    0045 on 2026-08-19 and had been emitted ZERO times until this run.
--    Refusals of a NON-deferrable recall: 0, in a real run and not only in a
--    probe. The refused trigger was wash_cadence/routine — exactly the kind
--    that should be refusable.
--
-- 3. THE KNOB WAS REMOVED AND THE BASELINE RETURNED. All eight hashes back,
--    zero work_side_* rows left in ottoq_policy_params. The difference between
--    reading 1 and reading 2 was the knob and nothing else.
-- ---------------------------------------------------------------------------
