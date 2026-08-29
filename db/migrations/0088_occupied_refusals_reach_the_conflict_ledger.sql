-- migration-version: 20260829173000
-- migration-name:    occupied_refusals_reach_the_conflict_ledger
-- 0088 -- R6 of the run-reconciliation audit (db/checks/0045): a calendar-vs-reality
-- disagreement leaves a first-class record, whichever path discovers it.
--
-- MEASURED on run 9291ec6d: 18 commands refused 'target_occupied' -- the engine's plan met a
-- stall that physical reality says is taken -- and space_conflict_ledger holds 0 rows for the
-- run. The ledger's ONLY writer is the displacement path ("stale claim displaced"); the refusal
-- path, which discovers the same class of disagreement from the other side, never writes it.
-- The ledger's own design comment says why that matters: "a displacement that is not recorded
-- is indistinguishable from a bug."
--
-- TWO PATCHES:
--
-- 1. ottoq.ottoq_validate_assignment: each of the three target_occupied returns now names the
--    BLOCKER in a machine-readable field ('blocker_vehicle_id') instead of only inside prose
--    ("stall occupied by <uuid>"). The prose stays; the field is what downstream code may use.
--
-- 2. ottoq.ottoq_emit_vehicle_command: when the preflight refusal is target_occupied and the
--    blocker and stall are known, one conflict row is written --
--    conflict_kind 'assignment_refused_occupied', resolution 'command_refused_preflight',
--    present = the blocker (reality), displaced = the vehicle whose claim was refused (plan).
--    Wrapped in the same EXCEPTION-WARN pattern as the displacement writer: a ledger write
--    failure must never block the refusal itself.
--
-- Pre-image pins, read live 2026-08-29 (all four anchors verified at exactly 1 occurrence):
--   ottoq.ottoq_validate_assignment    b7165a642513dfcbb1f3ed80dbc1d7c0
--   ottoq.ottoq_emit_vehicle_command   05785c849251c006f9e5d89e2b371cca

DO $do$
DECLARE
  v_oid oid; v_src text; v_new text; v_cnt int;

  v_v1_old text := E'''detail'',''stall occupied by ''||v_stall.current_vehicle_id);';
  v_v1_new text := E'''detail'',''stall occupied by ''||v_stall.current_vehicle_id,''blocker_vehicle_id'',v_stall.current_vehicle_id);';
  v_v2_old text := E'''detail'',''stall reserved by ''||v_stall.reserved_by);';
  v_v2_new text := E'''detail'',''stall reserved by ''||v_stall.reserved_by,''blocker_vehicle_id'',v_stall.reserved_by);';
  v_v3_old text := E'''detail'',''calendar booking held by ''||v_cal_conflict);';
  v_v3_new text := E'''detail'',''calendar booking held by ''||v_cal_conflict,''blocker_vehicle_id'',v_cal_conflict);';

  v_e1_old text := E'''otto_q_preflight'')\n    RETURNING command_id INTO v_id;\n  END IF;';
  v_e1_new text := E'''otto_q_preflight'')\n    RETURNING command_id INTO v_id;\n\n'
    || E'    -- 0088: the plan met occupied reality. That disagreement is a first-class record,\n'
    || E'    -- not just a refusal row. Same failure-isolation as the displacement writer.\n'
    || E'    IF v_check->>''code'' = ''target_occupied''\n'
    || E'       AND NULLIF(v_check->>''blocker_vehicle_id'','''') IS NOT NULL\n'
    || E'       AND NULLIF(p_payload->>''stall_id'','''') IS NOT NULL THEN\n'
    || E'      BEGIN\n'
    || E'        INSERT INTO public.space_conflict_ledger\n'
    || E'          (sim_run_id, depot_id, sim_clock, stall_id, stall_type,\n'
    || E'           conflict_kind, resolution, present_vehicle_id, displaced_vehicle_id, detail)\n'
    || E'        SELECT p_run, p_depot, p_clock, s.id, s.stall_type::text,\n'
    || E'               ''assignment_refused_occupied'', ''command_refused_preflight'',\n'
    || E'               (v_check->>''blocker_vehicle_id'')::uuid, p_vehicle,\n'
    || E'               jsonb_build_object(''command_id'', v_id, ''command_type'', p_type,\n'
    || E'                                  ''code'', v_check->>''code'', ''detail'', v_check->>''detail'')\n'
    || E'          FROM public.stalls s WHERE s.id = (p_payload->>''stall_id'')::uuid;\n'
    || E'      EXCEPTION WHEN OTHERS THEN\n'
    || E'        RAISE WARNING ''emit_vehicle_command conflict ledger write FAILED % %'', SQLSTATE, SQLERRM;\n'
    || E'      END;\n'
    || E'    END IF;\n'
    || E'  END IF;';
BEGIN
  -- ---------- 1. the validator names the blocker ----------
  SELECT p.oid INTO STRICT v_oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_validate_assignment';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'b7165a642513dfcbb1f3ed80dbc1d7c0' THEN
    RAISE EXCEPTION '0088 abort: validate_assignment drifted from the pinned pre-image (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_v1_old, ''))) / length(v_v1_old)
         + (length(v_src) - length(replace(v_src, v_v2_old, ''))) / length(v_v2_old)
         + (length(v_src) - length(replace(v_src, v_v3_old, ''))) / length(v_v3_old);
  IF v_cnt <> 3 THEN
    RAISE EXCEPTION '0088 abort: validator anchors found % times total, expected 3', v_cnt;
  END IF;
  v_new := replace(v_src, v_v1_old, v_v1_new);
  v_new := replace(v_new, v_v2_old, v_v2_new);
  v_new := replace(v_new, v_v3_old, v_v3_new);
  EXECUTE v_new;
  v_src := pg_get_functiondef(v_oid);
  v_cnt := (length(v_src) - length(replace(v_src, 'blocker_vehicle_id', ''))) / length('blocker_vehicle_id');
  IF v_cnt <> 3 THEN
    RAISE EXCEPTION '0088 abort: validator carries blocker_vehicle_id % times after patch, expected 3', v_cnt;
  END IF;

  -- ---------- 2. the emitter records the conflict ----------
  SELECT p.oid INTO STRICT v_oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_emit_vehicle_command';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '05785c849251c006f9e5d89e2b371cca' THEN
    RAISE EXCEPTION '0088 abort: emit_vehicle_command drifted from the pinned pre-image (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src) - length(replace(v_src, v_e1_old, ''))) / length(v_e1_old);
  IF v_cnt <> 1 THEN
    RAISE EXCEPTION '0088 abort: emitter anchor found % times, expected 1', v_cnt;
  END IF;
  v_new := replace(v_src, v_e1_old, v_e1_new);
  EXECUTE v_new;
  v_src := pg_get_functiondef(v_oid);
  IF position('assignment_refused_occupied' in v_src) = 0 THEN
    RAISE EXCEPTION '0088 abort: emitter does not carry the conflict write after patch';
  END IF;

  RAISE NOTICE '0088 applied: occupied refusals name their blocker and reach the conflict ledger.';
END
$do$;
