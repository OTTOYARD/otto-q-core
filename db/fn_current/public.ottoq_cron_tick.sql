-- CAPTURED LIVE from gxdrcyphqjzjsuhxuqtg via pg_get_functiondef, 2026-08-19 (run2/C4)
-- md5 at capture: 0000aacc9027798730952daa214d5ece
CREATE OR REPLACE FUNCTION public.ottoq_cron_tick()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE k text; base text := 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1';
BEGIN
  -- GATE: no started run, no work. Nothing below costs a cent while idle.
  IF NOT EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE status = 'running') THEN
    RETURN;
  END IF;

  -- (0) advance the WORLD (twin physics) FIRST so the brain reads FRESH state.
  BEGIN PERFORM ottoq_world_advance(); EXCEPTION WHEN OTHERS THEN RAISE WARNING 'cron world_advance: %', SQLERRM; END;

  -- (0b) hygiene: pending external proposals whose run is no longer running
  BEGIN
    UPDATE ottoq_external_proposals p SET status='expired'
     WHERE p.status='pending'
       AND NOT EXISTS (SELECT 1 FROM ottoq_sim_runs r WHERE r.sim_run_id=p.sim_run_id AND r.status='running');
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'cron proposal sweep: %', SQLERRM; END;

  SELECT decrypted_secret INTO k FROM vault.decrypted_secrets WHERE name = 'ottoq_anon_key' LIMIT 1;
  IF k IS NULL THEN RAISE WARNING 'ottoq_cron_tick: anon key missing from vault'; RETURN; END IF;

  -- (1) depot-wide re-optimize (~7s w/ cuOpt -> needs >5s pg_net default timeout)
  PERFORM net.http_post(
    url := base || '/ottoq-orchestrate-tick',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||k,'apikey',k),
    body := jsonb_build_object('depot_id','11111111-1111-1111-1111-111111111111','submit',true,'shadow',false),
    timeout_milliseconds := 25000);

  -- N4: OTTO-Q Prime (central orchestrator agent) — board review every ~10 min
  IF EXTRACT(MINUTE FROM now())::int % 10 < 2 THEN
    PERFORM net.http_post(
      url := base || '/ottoq-orchestrator-agent',
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||k,'apikey',k),
      body := jsonb_build_object('depot_id','11111111-1111-1111-1111-111111111111'),
      timeout_milliseconds := 25000);
  END IF;

  -- (2) ingress / wave-admission policy (auto day/night)
  PERFORM net.http_post(
    url := base || '/ottoq-wave-admit',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||k,'apikey',k),
    body := jsonb_build_object('depot_id','11111111-1111-1111-1111-111111111111','commit',true),
    timeout_milliseconds := 12000);
END $function$

