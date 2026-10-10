-- migration-version: 20261010014628
-- migration-name:    the_walk_reports_to_the_twin_and_the_ticks_let_its_operators_answer_first
--
-- 0654  **The walk reports what it did with a handed directive to the twin's own log instead of writing OTTO-Q's
--        command row, and every tick driver lets the twin's operators answer before the world moves, behind the flag
--        twin_operator_door.** (Step 4 of the twin data contract review, 2026-10-08: "Acks stop happening inside
--        OTTO-Q's transaction." Chase, 2026-10-09 CT: "Start building.")
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0653 gave the twin two operators and a step in which they read their directives, have the world carry them out
--   and answer through the v2 door. Two things kept that from being the twin's only way: the walk still wrote the
--   outcome straight onto OTTO-Q's command row (so an ack arrived to a row already decided, and the door had nothing
--   to record), and no tick ran the step. This makes the walk report when it is handed directives, and gives every
--   driver the step behind one flag, so the switch is one policy row and can be measured before it is made.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) twin.ottoq_sim_confirm_commands (the walk), patched at ten anchors between md5s of the live definition
--       (fba6dd47836c81eead40a63846e7f282 before, 9e3925550fba1e9f0924ad167731f7cd after): when it is handed directives (ottoq.apply_only, set
--       only by public.ottoq_api_twin_apply_directives), each of its five writes to ottoq_vehicle_commands (superseded,
--       car gone, executed, refused, execution error) becomes a report to twin.ottoq_twin_operator_log with the same
--       outcome, the engine's own reason code and the same refusal reason, and a directive it reported is not walked
--       twice in one pass. What the world does (stalls, the car's state and stall, the bay contract, the booking
--       turned active) is unchanged. When it is handed nothing, as in every tick today, every write is as it was.
--   (b) twin.ottoq_twin_walk_report: the one writer of those reports.
--   (c) The tick drivers, each patched at one anchor between md5s, all reading ottoq_policy_get(run,
--       'twin_operator_door', 0):
--         public.ottoq_sim_advance_tick_world  skips the walk when the flag is on            af31f15ac730af8f93e9a26b8d687858 -> 3e0ddbb1b097587bc2c0e9135d7895aa
--         twin.ottoq_world_advance             (production_live runs) skips it likewise      d19fec0e86cf1b743289a321c9716216 -> 3489fb1392073751df4f601d45dc7731
--         public.ottoq_sim_advance_tick        runs the operators' step first (pairs, sweeps, jumps: the caller's
--                                              transaction)                                  ace9e84a535e3a89f374307ce9423830 -> 0dbe2e53e659696e2b16a3745d7b7aeb
--         public.ottoq_demo_metronome          runs the step first and COMMITs it: its own transaction, before the
--                                              world's                                        30fb5ae4f76ed2f083be333624926bc6 -> d02b6af9e3fa622267247f7277ef7057
--   (d) twin.ottoq_twin_operators_beat (a procedure) and the pg_cron job ottoq-twin-operators (every minute): for a
--       running production_live run at a sim-fed depot with the flag on, the step in its own transaction. The cron
--       tick's world_advance runs with the decide path in one transaction, so the step cannot live there.
--
--   With the flag on, a directive OTTO-Q issues at a tick is read by its operator at the start of the next beat, at
--   the run's clock then (the tick it was issued in): the twin answers when it hears it. Before, the walk ran it
--   inside the next world tick at that tick's clock. That is a change in what the twin models, so it is measured on
--   a paired run before the flag is set anywhere (db/checks/0431).
--
-- ══ §3 WHAT IT DOES NOT CHANGE; forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════
--
--   The flag is 0 everywhere (catalog default 0, no policy row at any scope), so no tick runs the step and every walk
--   is handed nothing: every patched function does exactly what it did. The cron job finds no production_live run
--   with the flag on and does nothing. V1 proves both halves on the live walk, rolled back.
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   EXECUTE the five definitions in ottoq_schema_snapshots WHERE label = '0654_pre'; SELECT cron.unschedule(
--   'ottoq-twin-operators'). Dropping the procedure and the report function needs a person at the connector's prompt.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0654 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0653_the_twin_speaks_to_otto_q_as_two_operators') THEN
    RAISE EXCEPTION '0654 P1: 0653 is not classified; apply in order';
  END IF;
  IF to_regprocedure('twin.ottoq_twin_walk_report(uuid,uuid,text,text,text,timestamptz)') IS NOT NULL
     OR to_regprocedure('twin.ottoq_twin_operators_beat()') IS NOT NULL THEN
    RAISE EXCEPTION '0654 P1: an object this file creates exists already';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-twin-operators') THEN
    RAISE EXCEPTION '0654 P1: the cron job ottoq-twin-operators exists already';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'twin_operator_door' AND default_value = 0) THEN
    RAISE EXCEPTION '0654 P1: twin_operator_door is not declared with default 0 (0653)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_operator_door') THEN
    RAISE EXCEPTION '0654 P1: twin_operator_door is already set somewhere; this file assumes it is 0 everywhere';
  END IF;
  IF to_regprocedure('twin.ottoq_twin_operator_step(uuid)') IS NULL OR to_regclass('twin.ottoq_twin_operator_log') IS NULL THEN
    RAISE EXCEPTION '0654 P1: 0653''s step or log is missing';
  END IF;
END $premises$;

-- ── snapshot: the five definitions as they stood ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0654_pre', 'function', split_part(f, '.', 1), split_part(f, '.', 2), d.def, md5(d.def)
  FROM unnest(ARRAY['twin.ottoq_sim_confirm_commands(uuid,timestamptz)', 'public.ottoq_sim_advance_tick_world(uuid)',
                    'twin.ottoq_world_advance()', 'public.ottoq_sim_advance_tick(uuid)', 'public.ottoq_demo_metronome(integer)']) f
 CROSS JOIN LATERAL (SELECT pg_get_functiondef(f::regprocedure) AS def) d;

-- ── (b) the one writer of the walk's reports ──
CREATE OR REPLACE FUNCTION twin.ottoq_twin_walk_report(
  p_run uuid, p_command uuid, p_outcome text, p_reason_code text, p_refusal_reason text, p_at timestamptz)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
  /* 0654: what the walk did with a directive it was handed. The operator's ack through the v2 door, not this, is
     what writes OTTO-Q's command row. */
  INSERT INTO twin.ottoq_twin_operator_log (sim_run_id, command_id, outcome, reason_code, refusal_reason, walked_at, walks)
  VALUES (p_run, p_command, p_outcome, p_reason_code, p_refusal_reason, p_at, 1)
  ON CONFLICT (sim_run_id, command_id) DO UPDATE
    SET outcome = EXCLUDED.outcome, reason_code = EXCLUDED.reason_code, refusal_reason = EXCLUDED.refusal_reason,
        walked_at = EXCLUDED.walked_at, walks = twin.ottoq_twin_operator_log.walks + 1
$fn$;
REVOKE ALL ON FUNCTION twin.ottoq_twin_walk_report(uuid,uuid,text,text,text,timestamptz) FROM PUBLIC, anon, authenticated;

-- ── (a) the walk reports when it is handed directives ──
DO $p_walk$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamptz)'::regprocedure);
  a text[] := ARRAY[$a01$  )
  UPDATE ottoq_vehicle_commands c
     SET status = 'refused', reason_code = 'superseded',$a01$,
$a02$   WHERE c.command_id = sc.command_id
     AND ( (sc.command_type, sc.stall_id) IS DISTINCT FROM (sc.cur_type, sc.cur_stall)
           OR sc.dup_rn > 1 );$a02$,
$a03$     AND (v_only IS NULL OR c.command_id = ANY (v_only));   -- 0652
$a03$,
$a04$       AND (v_only IS NULL OR c.command_id = ANY (v_only))   -- 0652
     /* ═════════ 0060$a04$,
$a05$      UPDATE ottoq_vehicle_commands
         SET status = 'executed',$a05$,
$a06$       WHERE command_id = v_rec.command_id;
      
      v_executed := v_executed + 1;$a06$,
$a07$      UPDATE ottoq_vehicle_commands
         SET status = 'refused',
             confirmed_at = v_now,
             confirmed_by = 'otto_q_preflight_refusal',$a07$,
$a08$       WHERE command_id = v_rec.command_id;
      
      v_refused := v_refused + 1;
    END IF;$a08$,
$a09$       UPDATE ottoq_vehicle_commands
          SET status = 'refused',
              confirmed_at = v_now,
              confirmed_by = 'otto_q_preflight_error',$a09$,
$a10$        WHERE command_id = v_rec.command_id;
     EXCEPTION WHEN OTHERS THEN NULL;$a10$];
  b text[] := ARRAY[$b01$  ),
  /* 0654: a handed directive (ottoq.apply_only) is reported to the twin's log instead: the operator's ack through the
     v2 door writes the engine's row. Unset, as in every tick, this inserts nothing and the UPDATE below is as it was. */
  reported AS (
    INSERT INTO twin.ottoq_twin_operator_log (sim_run_id, command_id, outcome, reason_code, refusal_reason, walked_at, walks)
    SELECT p_sim_run_id, sc.command_id, 'refused', 'superseded',
           CASE WHEN (sc.command_type, sc.stall_id) IS DISTINCT FROM (sc.cur_type, sc.cur_stall)
                THEN 'superseded_by_newer_stall_command' ELSE 'duplicate_reissue_of_in_flight_command' END, v_now, 1
      FROM stall_cmds sc
     WHERE v_only IS NOT NULL
       AND ( (sc.command_type, sc.stall_id) IS DISTINCT FROM (sc.cur_type, sc.cur_stall) OR sc.dup_rn > 1 )
    ON CONFLICT (sim_run_id, command_id) DO UPDATE
      SET outcome = EXCLUDED.outcome, reason_code = EXCLUDED.reason_code, refusal_reason = EXCLUDED.refusal_reason,
          walked_at = EXCLUDED.walked_at, walks = twin.ottoq_twin_operator_log.walks + 1
  )
  UPDATE ottoq_vehicle_commands c
     SET status = 'refused', reason_code = 'superseded',$b01$,
$b02$   WHERE c.command_id = sc.command_id AND v_only IS NULL   /* 0654 */
     AND ( (sc.command_type, sc.stall_id) IS DISTINCT FROM (sc.cur_type, sc.cur_stall)
           OR sc.dup_rn > 1 );$b02$,
$b03$     AND v_only IS NULL;   -- 0654: a handed directive is reported just below instead
  INSERT INTO twin.ottoq_twin_operator_log (sim_run_id, command_id, outcome, reason_code, refusal_reason, walked_at, walks)
  SELECT p_sim_run_id, c.command_id, 'refused', 'target_unknown', 'vehicle_row_missing', v_now, 1
    FROM ottoq_vehicle_commands c
   WHERE v_only IS NOT NULL AND c.sim_run_id = p_sim_run_id AND c.status = 'issued' AND c.command_id = ANY (v_only)
     AND NOT EXISTS (SELECT 1 FROM vehicles v WHERE v.id = c.vehicle_id)
  ON CONFLICT (sim_run_id, command_id) DO UPDATE
    SET outcome = EXCLUDED.outcome, reason_code = EXCLUDED.reason_code, refusal_reason = EXCLUDED.refusal_reason,
        walked_at = EXCLUDED.walked_at, walks = twin.ottoq_twin_operator_log.walks + 1;   -- 0654
$b03$,
$b04$       AND (v_only IS NULL OR c.command_id = ANY (v_only))   -- 0652
       AND (v_only IS NULL OR NOT EXISTS (SELECT 1 FROM twin.ottoq_twin_operator_log o
                                           WHERE o.sim_run_id = p_sim_run_id AND o.command_id = c.command_id
                                             AND o.outcome IS NOT NULL))   -- 0654: reported above in this pass
     /* ═════════ 0060$b04$,
$b05$      IF v_only IS NOT NULL THEN   -- 0654: reported to the twin's log; the operator's ack writes the engine's row
        PERFORM twin.ottoq_twin_walk_report(p_sim_run_id, v_rec.command_id, 'executed', NULL, NULL, v_now);
      ELSE
      UPDATE ottoq_vehicle_commands
         SET status = 'executed',$b05$,
$b06$       WHERE command_id = v_rec.command_id;
      END IF;   -- 0654
      
      v_executed := v_executed + 1;$b06$,
$b07$      IF v_only IS NOT NULL THEN   -- 0654: reported to the twin's log; the operator's ack writes the engine's row
        PERFORM twin.ottoq_twin_walk_report(p_sim_run_id, v_rec.command_id, 'refused',
          CASE WHEN NOT v_stall_ok THEN 'target_occupied' WHEN NOT v_vehicle_ok THEN 'vehicle_state_incompatible'
               ELSE 'command_malformed' END,
          CASE WHEN NOT v_stall_ok THEN 'stall_unavailable'
               WHEN NOT v_vehicle_ok THEN format('vehicle_state_incompatible: %s', v_rec.current_state)
               ELSE 'validation_failed' END,
          v_now);
      ELSE
      UPDATE ottoq_vehicle_commands
         SET status = 'refused',
             confirmed_at = v_now,
             confirmed_by = 'otto_q_preflight_refusal',$b07$,
$b08$       WHERE command_id = v_rec.command_id;
      END IF;   -- 0654
      
      v_refused := v_refused + 1;
    END IF;$b08$,
$b09$       IF v_only IS NOT NULL THEN   -- 0654: reported to the twin's log; the operator's ack writes the engine's row
         PERFORM twin.ottoq_twin_walk_report(p_sim_run_id, v_rec.command_id, 'refused', 'command_malformed',
                                             left('execution_error: ' || SQLSTATE || ' ' || SQLERRM, 500), v_now);
       ELSE
       UPDATE ottoq_vehicle_commands
          SET status = 'refused',
              confirmed_at = v_now,
              confirmed_by = 'otto_q_preflight_error',$b09$,
$b10$        WHERE command_id = v_rec.command_id;
       END IF;   -- 0654
     EXCEPTION WHEN OTHERS THEN NULL;$b10$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> 'fba6dd47836c81eead40a63846e7f282' THEN
    RAISE EXCEPTION '0654: the walk is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0654: anchor % of the walk occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '9e3925550fba1e9f0924ad167731f7cd' THEN
    RAISE EXCEPTION '0654: the walk, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('twin.ottoq_sim_confirm_commands(uuid,timestamptz)'::regprocedure)) <> '9e3925550fba1e9f0924ad167731f7cd' THEN
    RAISE EXCEPTION '0654: the walk did not read back as written';
  END IF;
END $p_walk$;

-- ── (c) the tick drivers ──
DO $p_world$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_sim_advance_tick_world(uuid)'::regprocedure);
  a text[] := ARRAY[$a01$    PERFORM ottoq_sim_confirm_commands(p_sim_run_id, v_new_sim_clock);
$a01$];
  b text[] := ARRAY[$b01$    -- 0654: with twin_operator_door on, the twin's operators carry out OTTO-Q's directives in their own step before
    -- this tick (twin.ottoq_twin_operator_step) and answer through the v2 door, so the walk does not run here.
    IF ottoq_policy_get(p_sim_run_id, 'twin_operator_door', 0) < 1 THEN
      PERFORM ottoq_sim_confirm_commands(p_sim_run_id, v_new_sim_clock);
    END IF;
$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> 'af31f15ac730af8f93e9a26b8d687858' THEN
    RAISE EXCEPTION '0654: the world tick is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0654: anchor % of the world tick occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '3e0ddbb1b097587bc2c0e9135d7895aa' THEN
    RAISE EXCEPTION '0654: the world tick, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('public.ottoq_sim_advance_tick_world(uuid)'::regprocedure)) <> '3e0ddbb1b097587bc2c0e9135d7895aa' THEN
    RAISE EXCEPTION '0654: the world tick did not read back as written';
  END IF;
END $p_world$;

DO $p_world_advance$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_world_advance()'::regprocedure);
  a text[] := ARRAY[$a01$  BEGIN PERFORM ottoq_sim_confirm_commands(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance confirm_commands: %', SQLERRM; END;
$a01$];
  b text[] := ARRAY[$b01$  -- 0654: with twin_operator_door on, the twin's operators answer in their own job (twin.ottoq_twin_operators_beat)
  IF ottoq_policy_get(v_run.sim_run_id, 'twin_operator_door', 0) < 1 THEN
  BEGIN PERFORM ottoq_sim_confirm_commands(v_run.sim_run_id, v_now);
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'world_advance confirm_commands: %', SQLERRM; END;
  END IF;
$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> 'd19fec0e86cf1b743289a321c9716216' THEN
    RAISE EXCEPTION '0654: the production world tick is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0654: anchor % of the production world tick occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '3489fb1392073751df4f601d45dc7731' THEN
    RAISE EXCEPTION '0654: the production world tick, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('twin.ottoq_world_advance()'::regprocedure)) <> '3489fb1392073751df4f601d45dc7731' THEN
    RAISE EXCEPTION '0654: the production world tick did not read back as written';
  END IF;
END $p_world_advance$;

DO $p_advance_tick$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_sim_advance_tick(uuid)'::regprocedure);
  a text[] := ARRAY[$a01$  PERFORM set_config('ottoq.skip_wash_bump', '', true); /* 0196 */
$a01$];
  b text[] := ARRAY[$b01$  PERFORM set_config('ottoq.skip_wash_bump', '', true); /* 0196 */
  -- 0654: with twin_operator_door on, the twin's operators answer the directives the last tick issued before the world
  -- moves. Here (a pair, a sweep, a jump) that is the caller's transaction; the metronome gives it its own.
  IF ottoq_policy_get(p_sim_run_id, 'twin_operator_door', 0) >= 1 THEN
    PERFORM twin.ottoq_twin_operator_step(p_sim_run_id);
  END IF;
$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> 'ace9e84a535e3a89f374307ce9423830' THEN
    RAISE EXCEPTION '0654: the advance tick is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0654: anchor % of the advance tick occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> '0dbe2e53e659696e2b16a3745d7b7aeb' THEN
    RAISE EXCEPTION '0654: the advance tick, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('public.ottoq_sim_advance_tick(uuid)'::regprocedure)) <> '0dbe2e53e659696e2b16a3745d7b7aeb' THEN
    RAISE EXCEPTION '0654: the advance tick did not read back as written';
  END IF;
END $p_advance_tick$;

DO $p_metronome$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_demo_metronome(integer)'::regprocedure);
  a text[] := ARRAY[$a01$      v_tick_t0 := clock_timestamp();
      v_advanced := NULL;
$a01$];
  b text[] := ARRAY[$b01$      v_tick_t0 := clock_timestamp();
      -- 0654: with twin_operator_door on, the twin's operators answer OTTO-Q's directives in their own transaction,
      -- before the world moves: acks no longer happen inside OTTO-Q's.
      IF ottoq_policy_get(v_run.sim_run_id, 'twin_operator_door', 0) >= 1 THEN
        BEGIN
          PERFORM set_config('lock_timeout', '8000', true);
          PERFORM twin.ottoq_twin_operator_step(v_run.sim_run_id);
        EXCEPTION WHEN OTHERS THEN RAISE WARNING 'metronome operators % failed: %', v_run.sim_run_id, SQLERRM;
          PERFORM public.ottoq_record_tick_failure(v_run.sim_run_id, 'operators', SQLERRM, SQLSTATE); END;
        COMMIT;
      END IF;
      v_advanced := NULL;
$b01$];
  i int; v_n int;
BEGIN
  IF md5(v_def) <> '30fb5ae4f76ed2f083be333624926bc6' THEN
    RAISE EXCEPTION '0654: the metronome is not the definition this file patches (md5 %)', md5(v_def);
  END IF;
  FOR i IN 1 .. array_length(a, 1) LOOP
    v_n := (length(v_def) - length(replace(v_def, a[i], ''))) / length(a[i]);
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0654: anchor % of the metronome occurs % times, not once', i, v_n;
    END IF;
    v_def := replace(v_def, a[i], b[i]);
  END LOOP;
  IF md5(v_def) <> 'd02b6af9e3fa622267247f7277ef7057' THEN
    RAISE EXCEPTION '0654: the metronome, patched, is not the definition this file was written to produce (md5 %)', md5(v_def);
  END IF;
  EXECUTE v_def;
  IF md5(pg_get_functiondef('public.ottoq_demo_metronome(integer)'::regprocedure)) <> 'd02b6af9e3fa622267247f7277ef7057' THEN
    RAISE EXCEPTION '0654: the metronome did not read back as written';
  END IF;
END $p_metronome$;

-- ── (d) production_live runs: the operators answer in their own job ──
CREATE OR REPLACE PROCEDURE twin.ottoq_twin_operators_beat()
LANGUAGE plpgsql
AS $fn$
DECLARE r record;
BEGIN
  /* 0654: a production_live run's world and decisions advance together in public.ottoq_cron_tick's one transaction,
     so with twin_operator_door on, the twin's operators answer here, each run in its own transaction. The metronome
     does the same for every other run before each beat; a pair or sweep does it inside ottoq_sim_advance_tick.
     No SECURITY DEFINER and no SET clause: either would forbid the COMMIT (as for public.ottoq_demo_metronome), and
     every name below is schema-qualified. */
  FOR r IN SELECT s.sim_run_id FROM public.ottoq_sim_runs s JOIN public.depots d ON d.id = s.depot_id
            WHERE s.status = 'running' AND s.run_by = 'production_live' AND COALESCE(d.feed_mode, 'sim') = 'sim'
            ORDER BY s.started_at
  LOOP
    IF public.ottoq_policy_get(r.sim_run_id, 'twin_operator_door', 0) >= 1 THEN
      BEGIN
        PERFORM twin.ottoq_twin_operator_step(r.sim_run_id);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'twin operators beat % failed: %', r.sim_run_id, SQLERRM;
        PERFORM public.ottoq_record_tick_failure(r.sim_run_id, 'operators', SQLERRM, SQLSTATE);
      END;
      COMMIT;
    END IF;
  END LOOP;
END $fn$;
REVOKE ALL ON PROCEDURE twin.ottoq_twin_operators_beat() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule('ottoq-twin-operators', '* * * * *', 'CALL twin.ottoq_twin_operators_beat()');

-- ── V1: on the live walk, a copy of the newest twin run, in a sub-block that rolls back ──
DO $v1$
DECLARE
  v_msg text; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_run uuid; v_clock timestamptz; v_w1 uuid; v_w2 uuid; v_t1 uuid; v_w0 uuid; v_s1 uuid; v_s2 uuid; v_s0 uuid;
  c_t1 uuid; c_w1 uuid; c_w2 uuid; c_w0 uuid; v_set jsonb; v_step jsonb;
  r_t1 text; r_w1 text; r_w2 text; r_w0 text; v_s1_holder uuid; v_events int; v_self int; v_log text; v_viol bigint; v_iso jsonb;
BEGIN
  SELECT sim_run_id, COALESCE(sim_clock_current, started_at) INTO v_run, v_clock FROM public.ottoq_sim_runs
   WHERE depot_id = v_twin AND COALESCE(run_by, '') <> 'production_live' ORDER BY started_at DESC LIMIT 1;
  SELECT (array_agg(id ORDER BY display_name))[1], (array_agg(id ORDER BY display_name))[2], (array_agg(id ORDER BY display_name))[3]
    INTO v_w1, v_w2, v_w0
    FROM public.vehicles
   WHERE home_depot_id = v_twin AND fleet_operator_id = '22222222-2222-2222-2222-222222222222' AND current_stall_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = vehicles.id);
  SELECT id INTO v_t1 FROM public.vehicles
   WHERE home_depot_id = v_twin AND fleet_operator_id = '33333333-3333-3333-3333-333333333333' AND current_stall_id IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.stalls s WHERE s.current_vehicle_id = vehicles.id) ORDER BY display_name LIMIT 1;
  SELECT (array_agg(id ORDER BY stall_code))[1], (array_agg(id ORDER BY stall_code))[2], (array_agg(id ORDER BY stall_code))[3]
    INTO v_s1, v_s2, v_s0
    FROM (SELECT id, stall_code FROM public.stalls
           WHERE depot_id = v_twin AND stall_type = 'staging' AND current_vehicle_id IS NULL
             AND (reserved_by IS NULL OR reservation_expires_at <= COALESCE(v_clock, now()))
           ORDER BY stall_code DESC LIMIT 3) s;
  IF v_run IS NULL OR v_w0 IS NULL OR v_t1 IS NULL OR v_s0 IS NULL THEN
    RAISE EXCEPTION '0654 V1: no run, three free Waymo cars, a free Tesla car or three free staging stalls to probe with';
  END IF;

  BEGIN
    UPDATE public.ottoq_sim_runs SET status = 'running', sim_clock_current = v_clock WHERE sim_run_id = v_run;
    -- (i) the flag off: the walk handed nothing writes the engine's row, as it always has
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by)
    VALUES (v_run, v_twin, v_w0, 'hold', jsonb_build_object('stall_id', v_s0), v_clock, '0654_v1_probe') RETURNING command_id INTO c_w0;
    PERFORM twin.ottoq_sim_confirm_commands(v_run, v_clock);
    SELECT status || '|' || COALESCE(confirmed_by, '-') INTO r_w0 FROM public.ottoq_vehicle_commands WHERE command_id = c_w0;
    -- (ii) the flag on for this run: a Tesla car and a Waymo car sent to one stall (the Tesla one first), and a Waymo
    --      car to a stall of its own; the operators answer
    v_set := public.ottoq_policy_set('run', v_run, 'twin_operator_door', 1, '0654_v1_probe');
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by)
    VALUES (v_run, v_twin, v_t1, 'hold', jsonb_build_object('stall_id', v_s1), v_clock - interval '1 minute', '0654_v1_probe') RETURNING command_id INTO c_t1;
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by)
    VALUES (v_run, v_twin, v_w1, 'hold', jsonb_build_object('stall_id', v_s1), v_clock, '0654_v1_probe') RETURNING command_id INTO c_w1;
    INSERT INTO public.ottoq_vehicle_commands (sim_run_id, depot_id, vehicle_id, command_type, payload, issued_at, issued_by)
    VALUES (v_run, v_twin, v_w2, 'hold', jsonb_build_object('stall_id', v_s2), v_clock, '0654_v1_probe') RETURNING command_id INTO c_w2;
    v_step := twin.ottoq_twin_operator_step(v_run);
    SELECT status || '|' || COALESCE(reason_code, '-') || '|' || COALESCE(confirmed_by, '-') || '|' || COALESCE(payload -> 'ack' ->> 'reason', '-')
      INTO r_t1 FROM public.ottoq_vehicle_commands WHERE command_id = c_t1;
    SELECT status || '|' || COALESCE(reason_code, '-') || '|' || COALESCE(confirmed_by, '-') || '|' || COALESCE(payload -> 'ack' ->> 'reason', '-')
      INTO r_w1 FROM public.ottoq_vehicle_commands WHERE command_id = c_w1;
    SELECT status || '|' || COALESCE(reason_code, '-') || '|' || COALESCE(confirmed_by, '-') || '|' || COALESCE(payload -> 'ack' ->> 'reason', '-')
      INTO r_w2 FROM public.ottoq_vehicle_commands WHERE command_id = c_w2;
    SELECT current_vehicle_id INTO v_s1_holder FROM public.stalls WHERE id = v_s1;
    SELECT count(*) INTO v_events FROM public.ottoq_events
     WHERE sim_run_id = v_run AND event_type = 'directive.ack' AND actor_type = 'oem_dispatch_webhook'
       AND entity_id IN (v_t1, v_w1, v_w2);
    SELECT count(*) INTO v_self FROM public.ottoq_vehicle_commands
     WHERE command_id IN (c_t1, c_w1, c_w2) AND confirmed_by LIKE 'otto_q_preflight%';
    SELECT string_agg(source_name || ':' || outcome || ':' || COALESCE(reason_code, '-') || ':' || walks, ',' ORDER BY source_name, outcome)
      INTO v_log FROM twin.ottoq_twin_operator_log WHERE sim_run_id = v_run AND command_id IN (c_t1, c_w1, c_w2);
    SELECT jsonb_agg(to_jsonb(i)), sum(i.violations) INTO v_iso, v_viol FROM public.ottoq_assert_operator_isolation(v_run) i;
    RAISE EXCEPTION '0654 V1 PROBED';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM '0654 V1 PROBED' THEN RAISE EXCEPTION '0654 V1: the probe itself failed: %', v_msg; END IF;

  IF r_w0 IS DISTINCT FROM 'executed|otto_q_preflight' THEN
    RAISE EXCEPTION '0654 V1 FAILED: with nothing handed in, the walk did not write the row as before: %', r_w0;
  END IF;
  IF NOT COALESCE((v_set ->> 'ok')::boolean, false) THEN RAISE EXCEPTION '0654 V1 FAILED: the run-scoped flag: %', v_set; END IF;
  IF NOT COALESCE((v_step ->> 'ok')::boolean, false) THEN RAISE EXCEPTION '0654 V1 FAILED: the step: %', v_step; END IF;
  IF r_t1 IS DISTINCT FROM 'confirmed|-|operator:sim-b|-' OR r_w2 IS DISTINCT FROM 'confirmed|-|operator:sim-a|-'
     OR r_w1 IS DISTINCT FROM 'refused|target_occupied|operator:sim-a|occupied' THEN
    RAISE EXCEPTION '0654 V1 FAILED: the rows the acks wrote: Tesla %, Waymo (same stall) %, Waymo (own stall) %', r_t1, r_w1, r_w2;
  END IF;
  IF v_s1_holder IS DISTINCT FROM v_t1 THEN RAISE EXCEPTION '0654 V1 FAILED: the contested stall holds %, not the Tesla car', v_s1_holder; END IF;
  IF v_events <> 3 THEN RAISE EXCEPTION '0654 V1 FAILED: % directive.ack events, expected 3', v_events; END IF;
  IF v_self <> 0 THEN RAISE EXCEPTION '0654 V1 FAILED: the walk wrote % of the operators'' rows itself', v_self; END IF;
  IF v_log IS DISTINCT FROM 'sim-a:executed:-:1,sim-a:refused:target_occupied:1,sim-b:executed:-:1' THEN
    RAISE EXCEPTION '0654 V1 FAILED: the twin''s log: %', v_log;
  END IF;
  IF COALESCE(v_viol, -1) <> 0 THEN RAISE EXCEPTION '0654 V1 FAILED: isolation: %', v_iso; END IF;
  RAISE NOTICE '0654 V1 PASSED on run %: with the flag off the walk wrote the row as before (%); with it on, the walk reported to the twin''s log (%), the world seated the Tesla car first in the contested stall, and the operators'' acks wrote every row (Tesla %, Waymo %, Waymo %) with 3 directive.ack events; isolation 0 violations; all rolled back',
    v_run, r_w0, v_log, r_t1, r_w1, r_w2;
END $v1$;

-- ── V2: the five definitions as written, the flag 0 everywhere, the job, and who may call what ──
DO $v2$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(f, ', ') INTO v_bad FROM (VALUES
      ('twin.ottoq_sim_confirm_commands(uuid,timestamptz)', '9e3925550fba1e9f0924ad167731f7cd'),
      ('public.ottoq_sim_advance_tick_world(uuid)', '3e0ddbb1b097587bc2c0e9135d7895aa'),
      ('twin.ottoq_world_advance()', '3489fb1392073751df4f601d45dc7731'),
      ('public.ottoq_sim_advance_tick(uuid)', '0dbe2e53e659696e2b16a3745d7b7aeb'),
      ('public.ottoq_demo_metronome(integer)', 'd02b6af9e3fa622267247f7277ef7057')) AS t(f, m)
   WHERE md5(pg_get_functiondef(f::regprocedure)) <> m;
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION '0654 V2 FAILED: not as written: %', v_bad; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'twin_operator_door') THEN
    RAISE EXCEPTION '0654 V2 FAILED: twin_operator_door is set somewhere after the probe rolled back';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-twin-operators' AND active AND schedule = '* * * * *') THEN
    RAISE EXCEPTION '0654 V2 FAILED: the job ottoq-twin-operators is not scheduled';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_twin_walk_report(uuid,uuid,text,text,text,timestamptz)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'twin.ottoq_twin_walk_report(uuid,uuid,text,text,text,timestamptz)', 'EXECUTE')
     OR has_function_privilege('anon', 'twin.ottoq_twin_operators_beat()', 'EXECUTE') THEN
    RAISE EXCEPTION '0654 V2 FAILED: anon or authenticated can call the walk''s report or the beat';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0654_the_walk_reports_to_the_twin_and_the_ticks_let_its_operators_answer_first', false, false,
  'Step 4 of the twin data contract review: the walk reports a handed directive to twin.ottoq_twin_operator_log '
  'instead of writing the command row (the operator''s ack writes it); ottoq_sim_advance_tick_world and '
  'twin.ottoq_world_advance skip the walk, ottoq_sim_advance_tick and ottoq_demo_metronome run the operators'' step '
  'first, and the ottoq-twin-operators job serves production_live runs, all when twin_operator_door is on. The flag '
  'is 0 everywhere, so every tick is byte for byte as before. FALSE/FALSE.',
  now());

COMMIT;

-- ══ APPLIED 2026-10-10 01:46:28 UTC (8:46 PM CT on 2026-10-09), version 20261010014628 ═══════════════════════════════
--   Claude, MCP apply_migration, the file as committed in 2740375; the ledger's stored statement is that file byte for
--   byte (md5 ca3d2805c139b8a625fe91fbe519c26c, 33,255 characters, 34,039 bytes). P0, P1, V1 (on a copy of the twin
--   depot's newest run, the live walk: with the flag off it wrote the row as before; with it on it reported to the
--   twin's log, the world seated the Tesla car first in the contested stall, the operators' acks wrote all three rows
--   with 3 directive.ack events, isolation 0 violations; rolled back), V2 passed in the apply's transaction. Read
--   after: the five definitions at their stated md5s, five 0654_pre snapshots, cron job 793 ottoq-twin-operators active
--   every minute, twin_operator_door set nowhere, 0 operator log rows.
