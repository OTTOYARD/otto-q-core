-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run2/C4)
-- md5 at capture: 809257934e4314ee8d70d84005c93c81
CREATE OR REPLACE FUNCTION public.cuopt_log_gate(p_run uuid, p_reason text, p_cands integer DEFAULT NULL::integer, p_detail jsonb DEFAULT NULL::jsonb, p_t0 timestamp with time zone DEFAULT NULL::timestamp with time zone, p_note text DEFAULT 'sql_gate:v2'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_tick bigint; v_clock timestamptz;
BEGIN
  IF p_run IS NOT NULL THEN
    SELECT tick_count, sim_clock_current INTO v_tick, v_clock
      FROM public.ottoq_sim_runs WHERE sim_run_id = p_run;
  END IF;
  INSERT INTO public.cuopt_invocation_log
    (sim_run_id, stage, tick_seq, sim_clock, called_at, candidates_in,
     abstained_reason, latency_ms, source_note, detail)
  VALUES
    (p_run, 'sql_gate', v_tick, v_clock, COALESCE(p_t0, clock_timestamp()), p_cands,
     p_reason,
     CASE WHEN p_t0 IS NULL THEN NULL
          ELSE (EXTRACT(EPOCH FROM (clock_timestamp() - p_t0)) * 1000)::int END,
     p_note, p_detail);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cuopt_invocation_log write FAILED (reason=%): % / %', p_reason, SQLSTATE, SQLERRM;
END;
$function$

