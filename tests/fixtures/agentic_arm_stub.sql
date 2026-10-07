-- tests/fixtures/agentic_arm_stub.sql -- ottoq_agentic_arm as the live database held it on 2026-10-07 (pg_get_functiondef's
-- output, byte for byte, so 0615's md5 premise 9c51a752 passes against it), and a stand-in for the attestation it returns,
-- ottoq_agentic_arming. Loaded after agent_charge_order_stub.sql by tests/test_agent_charge_order_sql.py.
SET check_function_bodies = off;
CREATE OR REPLACE FUNCTION public.ottoq_agentic_arm(p_sim_run_id uuid, p_by text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_run_by text; v_found boolean; v_k record; v_r jsonb;
  v_receipts jsonb := '[]'::jsonb;
BEGIN
  IF p_sim_run_id IS NULL OR NULLIF(p_by,'') IS NULL THEN
    RAISE EXCEPTION 'ottoq_agentic_arm: sim_run_id and by are both required'
      USING ERRCODE = '22023';
  END IF;

  SELECT r.run_by, true INTO v_run_by, v_found
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF NOT COALESCE(v_found, false) THEN
    RAISE EXCEPTION 'ottoq_agentic_arm: run % does not exist', p_sim_run_id
      USING ERRCODE = '22023';
  END IF;

  --: THE CANON GUARD. 0265: with the key absent the frame is byte-identical to
  --: its pre-0265 output, "which is what every certification arm sees." Arming
  --: a certification arm would change the frame under the canon. Refused here
  --: rather than left to the operator, which is the whole point of the file.
  IF v_run_by = 'cert_harness' THEN
    RAISE EXCEPTION 'ottoq_agentic_arm: run % is a certification arm (run_by=cert_harness). '
                    'Arming it would change the frame the canon was measured against. '
                    'A proposer reaches a certification by record-and-replay (0237/0239), '
                    'never by being armed into one.', p_sim_run_id
      USING ERRCODE = '42501';
  END IF;

  FOR v_k IN
    SELECT * FROM (VALUES
      ('agent_solver_chain_enabled',     1::numeric),
      ('cuopt_propose_enabled',          1::numeric),
      ('orchestrator_agent_enabled',     1::numeric),
      ('proposer_frame_facts',           1::numeric),
      ('proposer_hold_enabled',          1::numeric),
      ('cuopt_first_refusal_max_defers', 6::numeric),
      ('prearrival_charge_yields_to_solver', 1::numeric),
      ('agent_review_enabled', 1::numeric),
      ('agent_board_grounding_enabled', 1::numeric),   --: 0432
      ('agent_asset_depth_enabled', 1::numeric)        --: 0432: 0350's block, never armed before
    ) AS t(param_key, value) ORDER BY 1
  LOOP
    --: ALWAYS run scope. ottoq_policy_set clamps to the catalog range and
    --: answers {"ok":false,"error":"unknown_param"} for a key it does not know
    --: WITHOUT raising (0262) -- so the receipt is read, not assumed. That
    --: unread receipt is the exact mechanism by which proposer_seat has 12 rows
    --: nobody could have written through the setter.
    v_r := public.ottoq_policy_set('run', p_sim_run_id, v_k.param_key, v_k.value, p_by);
    IF NOT COALESCE((v_r->>'ok')::boolean, false) THEN
      RAISE EXCEPTION 'ottoq_agentic_arm: ottoq_policy_set refused % -> %', v_k.param_key, v_r
        USING ERRCODE = '22023';
    END IF;
    IF COALESCE((v_r->>'clamped')::boolean, false) THEN
      RAISE EXCEPTION 'ottoq_agentic_arm: % was clamped from % to % by the catalog range %; '
                      'an arm that silently lands on a different value is the defect this '
                      'function exists to end',
                      v_k.param_key, v_r->>'requested', v_r->>'applied', v_r->>'safe_range'
        USING ERRCODE = '22023';
    END IF;
    v_receipts := v_receipts || jsonb_build_array(v_r);
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id, 'armed_by', p_by,
                            'receipts', v_receipts,
                            'arming', public.ottoq_agentic_arming(p_sim_run_id));
END $function$

;
-- stand-in: the attestation the arm returns. The real one reads seven dials and the proposer ledgers; 0615 does not touch it.
CREATE OR REPLACE FUNCTION public.ottoq_agentic_arming(p_sim_run_id uuid) RETURNS jsonb LANGUAGE sql AS $stub$ SELECT '{}'::jsonb $stub$;
