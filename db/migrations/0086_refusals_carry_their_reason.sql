-- migration-version: 20260829170000
-- migration-name:    refusals_carry_their_reason
-- 0086 -- R3 of the run-reconciliation audit (db/checks/0045): every refusal carries a reason
-- code, structurally.
--
-- MEASURED on run 9291ec6d (busy_day, seed 777011): 73 refused commands, 14 with reason_code
-- NULL -- every one written by twin.ottoq_sim_confirm_commands' refusal branch, which records a
-- rich refusal_reason INSIDE the payload jsonb and never writes the reason_code COLUMN two
-- lines away. Its own EXCEPTION branch writes the column correctly, which is how the gap
-- survived review: the error path was audited, the normal path was not. "Every directive
-- carries a reason code" is a founding principle; a NULL in the column built for it means the
-- why exists only inside a blob no constraint can see.
--
-- THREE CHANGES, one per layer of the defect:
--
-- 1. The refusal branch maps its own refusal_reason onto the coded vocabulary:
--       stall unavailable            -> target_occupied      (that is what it means)
--       vehicle state incompatible   -> vehicle_state_incompatible  (new vocabulary word)
--       anything else                -> command_malformed
--
-- 2. A pre-sweep refuses commands whose vehicle row no longer exists ('target_unknown').
--    The reactor loop INNER JOINs vehicles, so a command for a vanished vehicle was not
--    refused, not expired, not counted -- it was INVISIBLE, forever 'issued'. The join keeps
--    its shape; the sweep in front of it makes the skip impossible.
--
-- 3. The vocabulary constraint gains 'vehicle_state_incompatible' and 'run_ended' (0087 uses
--    the latter), and a NEW constraint makes the rule structural going forward:
--    status='refused' => reason_code IS NOT NULL, added NOT VALID so the 14 historical rows
--    stay as evidence rather than being backfilled with invented codes.
--
-- 4. public.ottoq_ack_vehicle_command -- the VEHICLE-SIDE refusal path -- gains the same
--    discipline, and it is not optional: without it the new constraint would start REJECTING
--    vehicle refusals, since ack writes status='refused' with no reason_code. A vehicle that
--    refuses has answered, so the code is 'vehicle_declined' (new vocabulary word), with the
--    caller's free-text reason preserved in reason_detail as well as the payload.
--
-- Pre-image pins, read live 2026-08-29:
--   twin.ottoq_sim_confirm_commands   55acfdfa5f884837c641c20a831ac872
--   public.ottoq_ack_vehicle_command  36a8f8a4b4dbb84fe0caaba143e7d5cc
-- (confirm_commands differs from db/fn_current's 2026-08-19 capture by the 0060 deterministic-
--  ordering changes; anchors below were verified against the LIVE text, each exactly once.)

DO $do$
DECLARE
  v_oid oid; v_src text; v_new text; v_cnt int;

  -- Anchor 1: the refusal branch head. reason_code is inserted between confirmed_by and payload.
  v_a1_old text := E'             confirmed_by = ''otto_q_preflight_refusal'',\n             payload = v_rec.payload || jsonb_build_object(';
  v_a1_new text := E'             confirmed_by = ''otto_q_preflight_refusal'',\n'
                || E'             reason_code = CASE\n'
                || E'               WHEN NOT v_stall_ok THEN ''target_occupied''\n'
                || E'               WHEN NOT v_vehicle_ok THEN ''vehicle_state_incompatible''\n'
                || E'               ELSE ''command_malformed''\n'
                || E'             END,\n'
                || E'             payload = v_rec.payload || jsonb_build_object(';

  -- Anchor 2: the FOR loop head. The missing-vehicle sweep goes immediately before it.
  v_a2_old text := E'  FOR v_rec IN\n';
  -- Anchor 3: the ack path's status write. A refusal disposition now carries its code and detail.
  v_a3_old text := E'     SET status = v_disp,\n         confirmed_at = COALESCE(confirmed_at, v_now),\n         confirmed_by = p_actor,';
  v_a3_new text := E'     SET status = v_disp,\n         confirmed_at = COALESCE(confirmed_at, v_now),\n         confirmed_by = p_actor,\n'
                || E'         reason_code   = CASE WHEN v_disp = ''refused'' THEN ''vehicle_declined'' ELSE reason_code END,\n'
                || E'         reason_detail = CASE WHEN v_disp = ''refused'' THEN COALESCE(p_reason, reason_detail) ELSE reason_detail END,';

  v_a2_new text := E'  -- 0086: a command whose vehicle row is GONE must be refused, not skipped.\n'
                || E'  -- The loop below INNER JOINs vehicles, so such a command was invisible to it and\n'
                || E'  -- stayed ''issued'' forever with nothing anywhere reporting the absence.\n'
                || E'  UPDATE ottoq_vehicle_commands c\n'
                || E'     SET status = ''refused'', reason_code = ''target_unknown'',\n'
                || E'         confirmed_at = v_now, confirmed_by = ''otto_q_missing_vehicle'',\n'
                || E'         payload = c.payload || jsonb_build_object(''refusal_reason'',''vehicle_row_missing'',''refused_at_clock'',v_now)\n'
                || E'   WHERE c.sim_run_id = p_sim_run_id AND c.status = ''issued''\n'
                || E'     AND NOT EXISTS (SELECT 1 FROM vehicles v WHERE v.id = c.vehicle_id);\n\n'
                || E'  FOR v_rec IN\n';
BEGIN
  SELECT p.oid INTO STRICT v_oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_confirm_commands';
  v_src := pg_get_functiondef(v_oid);

  IF md5(v_src) <> '55acfdfa5f884837c641c20a831ac872' THEN
    RAISE EXCEPTION '0086 abort: confirm_commands drifted from the pinned pre-image (md5 %)', md5(v_src);
  END IF;

  v_cnt := (length(v_src) - length(replace(v_src, v_a1_old, ''))) / length(v_a1_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0086 abort: refusal-branch anchor found % times, expected 1', v_cnt;
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a2_old, ''))) / length(v_a2_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0086 abort: FOR-loop anchor found % times, expected 1', v_cnt;
  END IF;

  v_new := replace(v_src, v_a1_old, v_a1_new);
  v_new := replace(v_new, v_a2_old, v_a2_new);
  EXECUTE v_new;

  v_src := pg_get_functiondef(v_oid);
  IF position('vehicle_state_incompatible' in v_src) = 0
     OR position('otto_q_missing_vehicle' in v_src) = 0 THEN
    RAISE EXCEPTION '0086 abort: patched function does not carry both fixes';
  END IF;

  -- ---------- the vehicle-side path: public.ottoq_ack_vehicle_command ----------
  SELECT p.oid INTO STRICT v_oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_ack_vehicle_command';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '36a8f8a4b4dbb84fe0caaba143e7d5cc' THEN
    RAISE EXCEPTION '0086 abort: ack_vehicle_command drifted from the pinned pre-image (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_a3_old, ''))) / length(v_a3_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0086 abort: ack anchor found % times, expected 1', v_cnt;
  END IF;
  v_new := replace(v_src, v_a3_old, v_a3_new);
  EXECUTE v_new;
  v_src := pg_get_functiondef(v_oid);
  IF position('vehicle_declined' in v_src) = 0 THEN
    RAISE EXCEPTION '0086 abort: ack path does not carry the vehicle_declined code after patch';
  END IF;

  -- Vocabulary + structural rule. Historical NULLs stay as evidence (NOT VALID).
  ALTER TABLE public.ottoq_vehicle_commands DROP CONSTRAINT ottoq_vehicle_commands_reason_code_check;
  ALTER TABLE public.ottoq_vehicle_commands ADD CONSTRAINT ottoq_vehicle_commands_reason_code_check
    CHECK (reason_code IS NULL OR reason_code = ANY (ARRAY[
      'target_occupied','resource_faulted','target_unknown','vehicle_unresponsive',
      'command_malformed','no_capacity','superseded','vehicle_state_incompatible','run_ended',
      'vehicle_declined']));
  ALTER TABLE public.ottoq_vehicle_commands ADD CONSTRAINT ottoq_vehicle_commands_refusal_has_code
    CHECK (status <> 'refused' OR reason_code IS NOT NULL) NOT VALID;

  RAISE NOTICE '0086 applied: refusals carry reason codes; missing-vehicle commands are refused, not skipped.';
END
$do$;
