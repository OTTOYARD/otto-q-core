-- migration-version: 20260917123453
-- migration-name:    the_agent_chain_gets_first_refusal_before_greedy_dispatch
--
-- Run a7a364e7 proved Nemotron, policy enactment and the deterministic kernel,
-- but also exposed a race. The FIRE beat delegated to the slower agent before
-- pinning any candidates. The next DECIDE beat greedily assigned every charge
-- candidate, so the agent-selected solver returned to an empty instance.
--
-- Arm the existing bounded first-refusal ledger before delegation. It holds a
-- candidate for one deterministic beat only, releases immediately when any
-- holds_tick proposer answers, and fails open to greedy on timeout.

DO $patch$
DECLARE
  d text;
  old text;
  new text;
  n integer;
BEGIN
  d := pg_get_functiondef('public.ottoq_cuopt_refresh(uuid)'::regprocedure);

  old := E'    SELECT r.depot_id INTO v_depot FROM public.ottoq_sim_runs r\n'
      || E'     WHERE r.sim_run_id=v_run AND r.status=''running'';';
  new := E'    SELECT r.depot_id, COALESCE(r.tick_count,0) INTO v_depot,v_tick\n'
      || E'      FROM public.ottoq_sim_runs r\n'
      || E'     WHERE r.sim_run_id=v_run AND r.status=''running'';';
  n := (length(d)-length(replace(d,old,'')))/length(old);
  IF n = 1 THEN
    d := replace(d,old,new);
  ELSIF d NOT LIKE '%INTO v_depot,v_tick%WHERE r.sim_run_id=v_run%' THEN
    RAISE EXCEPTION '0337 P1: delegated run lookup anchor occurs % times', n;
  END IF;

  old := E'    SELECT net.http_post(\n'
      || E'      url := ''https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-orchestrator-agent'',';
  new := E'    -- Give the agent-selected solver one bounded beat before greedy fallback.\n'
      || E'    BEGIN\n'
      || E'      PERFORM public.ottoq_cuopt_first_refusal_arm(v_run,v_tick);\n'
      || E'    EXCEPTION WHEN OTHERS THEN NULL;\n'
      || E'    END;\n'
      || old;
  n := (length(d)-length(replace(d,old,'')))/length(old);
  IF d NOT LIKE '%PERFORM public.ottoq_cuopt_first_refusal_arm(v_run,v_tick);%' THEN
    IF n <> 1 THEN
      RAISE EXCEPTION '0337 P2: delegated HTTP anchor occurs % times', n;
    END IF;
    d := replace(d,old,new);
  END IF;

  EXECUTE d;
END $patch$;

DO $assertions$
DECLARE d text;
BEGIN
  SELECT p.prosrc INTO d
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_cuopt_refresh'
     AND pg_get_function_identity_arguments(p.oid)='p_sim_run_id uuid';
  IF d NOT LIKE '%INTO v_depot,v_tick%'
     OR d NOT LIKE '%PERFORM public.ottoq_cuopt_first_refusal_arm(v_run,v_tick);%'
     OR strpos(d,'ottoq_cuopt_first_refusal_arm(v_run,v_tick)') > strpos(d,'ottoq-orchestrator-agent') THEN
    RAISE EXCEPTION '0337 A1: candidates are not held before agent delegation';
  END IF;
END $assertions$;

INSERT INTO public.ottoq_cert_lineage(name,forces_recert,note,classified_at)
VALUES ('0337_the_agent_chain_gets_first_refusal_before_greedy_dispatch',true,
  'The agent-selected solver now gets one bounded decision beat before greedy fallback. Assignment order can change, so recertification is required.',now())
ON CONFLICT(name) DO NOTHING;
