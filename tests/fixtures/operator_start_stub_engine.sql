-- A STUB ENGINE for exercising db/migrations/0564 on a throwaway PostgreSQL. NOT the engine.
--
-- It carries exactly what 0564's P1 reads (the world lock inside ottoq_try_world_lock, the two runners' cron jobs and
-- bodies, ottoq_dial_pair's lock, the start's signature) and one thing P1 does not: the CONFLICT that made every cockpit
-- start fail on 2026-09-28. The stub pair writes the world row and then sleeps, as a determinism pair holds the twin
-- depot's rows for its whole transaction; the stub start writes the same row, so it cannot finish while a pair runs.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon')          THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role')  THEN CREATE ROLE service_role NOLOGIN; END IF;
END $roles$;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- The world: one row every pair and every start must write.
CREATE TABLE public.stub_world (id int PRIMARY KEY, v int NOT NULL);
INSERT INTO public.stub_world VALUES (1, 0);

CREATE TABLE public.ottoq_sim_runs (
  sim_run_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scenario_code text NOT NULL,
  status        text NOT NULL,
  run_by        text,
  notes         text,
  started_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.ottoq_cert_lineage (
  name                text PRIMARY KEY,
  forces_recert       boolean NOT NULL,
  forces_dial_restart boolean NOT NULL DEFAULT false,
  note                text,
  classified_at       timestamptz NOT NULL DEFAULT now()
);

-- The world lock, as the live ottoq_try_world_lock takes it.
CREATE FUNCTION public.ottoq_try_world_lock(p_attempts int DEFAULT 1, p_sleep_s numeric DEFAULT 0)
RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  RETURN pg_try_advisory_xact_lock(hashtext('ottoq_recert_runner')::bigint);
END $$;

-- A determinism pair: writes the world and holds it for p_arm_budget_s seconds, in one transaction.
CREATE FUNCTION public.ottoq_determinism_pair(p_seed bigint, p_ticks int, p_scenario text, p_depot uuid DEFAULT NULL,
                                              p_sim_start timestamptz DEFAULT NULL, p_arm_budget_s int DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.stub_world SET v = v + 1 WHERE id = 1;
  PERFORM pg_sleep(p_arm_budget_s);
  RETURN jsonb_build_object('equal', true);
END $$;

CREATE FUNCTION public.ottoq_dial_pair(p_experiment_id uuid, p_seed bigint, p_arm_budget_s int DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  IF NOT public.ottoq_try_world_lock() THEN RETURN jsonb_build_object('ran', false); END IF;
  RETURN public.ottoq_determinism_pair(p_seed, 12, 'busy_day', NULL, NULL, p_arm_budget_s);
END $$;

CREATE FUNCTION public.ottoq_dial_experiment_runner()
RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  IF NOT public.ottoq_try_world_lock() THEN RETURN jsonb_build_object('ran', false, 'why', 'world held'); END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN
    RETURN jsonb_build_object('ran', false, 'why', 'a run is live');
  END IF;
  RETURN public.ottoq_dial_pair(gen_random_uuid(), 1, 30);
END $$;

-- The start 0564 wraps: same signature and defaults as the live one; it writes the world, so a running pair blocks it.
CREATE FUNCTION public.ottoq_sim_run_scenario(p_scenario_code text, p_seed bigint DEFAULT NULL,
                                              p_run_by text DEFAULT 'system_scheduler',
                                              p_start_clock timestamptz DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_run uuid;
BEGIN
  UPDATE public.stub_world SET v = v + 1 WHERE id = 1;
  INSERT INTO public.ottoq_sim_runs(scenario_code, status, run_by, notes)
  VALUES (p_scenario_code, 'running', p_run_by, 'Started via ottoq_sim_run_scenario(' || p_scenario_code || ')')
  RETURNING sim_run_id INTO v_run;
  RETURN v_run;
END $$;

-- pg_cron's job table, holding the two runners exactly as the live commands read them.
CREATE SCHEMA cron;
CREATE TABLE cron.job (jobid bigint PRIMARY KEY, schedule text, command text, database text, username text,
                       active boolean DEFAULT true, jobname text);
INSERT INTO cron.job(jobid, schedule, command, database, username, jobname) VALUES
  (746, '* * * * *',
   E'SET statement_timeout = 0;\nDO $runner$\nBEGIN\n  IF NOT pg_try_advisory_xact_lock(hashtext(''ottoq_recert_runner'')::bigint) THEN RETURN; END IF;\n'
   || E'  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN (''running'',''paused'')) THEN RETURN; END IF;\n'
   || E'  PERFORM public.ottoq_determinism_pair(p_seed => 1, p_ticks => 48, p_scenario => ''busy_day'');\nEND $runner$;',
   'postgres', 'postgres', 'ottoq-recert-runner'),
  (755, '*/10 * * * *', 'SELECT public.ottoq_dial_experiment_runner()', 'postgres', 'postgres',
   'ottoq-dial-experiment-runner');
