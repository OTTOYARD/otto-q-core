-- 21_cron.sql: 25 statements, exported from production's catalog
-- @@ cron_job 2 ottoq-twin-ingest-weekly
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (2, '0 4-23 * * 0', 'SELECT ottoq_twin_ingest_refresh()', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-twin-ingest-weekly');
-- @@ cron_job 10 ottoq-depot-tick
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (10, '*/2 * * * *', 'SELECT public.ottoq_cron_tick()', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-depot-tick');
-- @@ cron_job 11 ottoq-retention-nightly
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (11, '0 8 * * *', 'CALL public.ottoq_retention_purge_worker(90, 2000, ''48 hours'', ARRAY[''ottoq_events'',''ottoq_rule_evaluations'',''ottoq_incident_reports'']);', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-retention-nightly');
-- @@ cron_job 12 ottoq-demo-metronome
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (12, '* * * * *', 'CALL public.ottoq_demo_metronome(57)', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-demo-metronome');
-- @@ cron_job 13 ottoq-cert-battery
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (13, '* * * * *', 'SET statement_timeout = 0; SELECT public.ottoq_cert_battery_step();', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-cert-battery');
-- @@ cron_job 17 ottoq-run-governor
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (17, '*/2 * * * *', 'SELECT public.ottoq_run_governor_auto_stop()', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-run-governor');
-- @@ cron_job 625 ottoq-run-purge-nightly
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (625, '0 9 * * *', 'CALL public.ottoq_retention_purge_runs(300, 2000, ''48 hours'', false);', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-run-purge-nightly');
-- @@ cron_job 746 ottoq-recert-runner
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (746, '* * * * *', '
SET statement_timeout = 0;
DO $runner$
DECLARE c record;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext(''ottoq_recert_runner'')::bigint) THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN (''running'',''paused'')) THEN RETURN; END IF;
  -- NO DEPOT PREDICATE, and that is a deliberate reading of operating rule 8 rather than
  -- an oversight. Rule 8 forbids testing or validating ACROSS SITES, and its stated
  -- rationale is that "a result from a second site does not advance" the one question the
  -- twin depot exists to answer -- how many vehicles it can stage and orchestrate. A
  -- determinism pair yields no such result: it asserts only that two arms of the SAME
  -- scenario agree with each other byte-for-byte. The two grid_smoke columns on fixture
  -- depot aacd0bb0 are the only columns exercising the 0132 site power gate under a tight
  -- cap, so dropping them would lose a regression canary and gain no scope discipline.
  -- Chase authorised resolving this on 2026-09-20 after it was flagged to him as a rule-8
  -- call rather than decided unilaterally.
  SELECT * INTO c FROM public.ottoq_determinism_canon
   WHERE enabled AND NOT satisfies_floor
   ORDER BY ticks, scenario, seed LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;
  -- 0481 (G211): a dial promotion this column keeps failing under rolls itself back, and the sweep restarts
  IF public.ottoq_recert_promotion_guard(c.scenario, c.seed, c.ticks, c.depot_id)->>''action'' = ''rolled_back'' THEN RETURN; END IF;
  PERFORM public.ottoq_determinism_pair(
            p_seed         => c.seed,
            p_ticks        => c.ticks,
            p_scenario     => c.scenario,
            p_depot        => c.depot_id,
            p_arm_budget_s => GREATEST(240, c.ticks * 30));
END $runner$;
', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-recert-runner');
-- @@ cron_job 755 ottoq-dial-experiment-runner
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (755, '*/10 * * * *', 'SET statement_timeout = 0; SELECT public.ottoq_dial_experiment_runner();', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-dial-experiment-runner');
-- @@ cron_job 761 ottoq_dial_window_open
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (761, '0 8 * * *', 'SELECT public.ottoq_policy_set(''global'', ''00000000-0000-0000-0000-000000000000''::uuid, ''dial_experiment_runner_enabled'', 1, ''dial_window_cron:open'')', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq_dial_window_open');
-- @@ cron_job 762 ottoq_dial_window_close
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (762, '41 10 * * *', 'SELECT public.ottoq_policy_set(''global'', ''00000000-0000-0000-0000-000000000000''::uuid, ''dial_experiment_runner_enabled'', 0, ''dial_window_cron:close'')', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq_dial_window_close');
-- @@ cron_job 763 ottoq_dial_window_open_once_20260928
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (763, '0 6 28 9 *', 'SELECT public.ottoq_policy_set(''global'', ''00000000-0000-0000-0000-000000000000''::uuid, ''dial_experiment_runner_enabled'', 1, ''dial_window_cron:open'')', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq_dial_window_open_once_20260928');
-- @@ cron_job 765 challenger_scan
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (765, '* * * * *', 'SELECT public.ottoq_challenger_tick();', 'localhost', 5432, 'postgres', 'postgres', false, 'challenger_scan');
-- @@ cron_job 783 ottoq-throughput-sweep-runner
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (783, '*/2 * * * *', 'SET statement_timeout = 0; SELECT public.ottoq_throughput_sweep_runner();', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-throughput-sweep-runner');
-- @@ cron_job 784 ottoq_sweep_window_open
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (784, '0 4 * * *', 'SELECT public.ottoq_policy_set(''global'', ''00000000-0000-0000-0000-000000000000''::uuid, ''throughput_sweep_runner_enabled'', 1, ''sweep_window_cron:open'')', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq_sweep_window_open');
-- @@ cron_job 785 ottoq_sweep_window_close
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (785, '0 11 * * *', 'SELECT public.ottoq_policy_set(''global'', ''00000000-0000-0000-0000-000000000000''::uuid, ''throughput_sweep_runner_enabled'', 0, ''sweep_window_cron:close'')', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq_sweep_window_close');
-- @@ cron_job 786 ottoq-learn-estimates-nightly
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (786, '20 11 * * *', 'SELECT public.ottoq_fit_charge_time_model(''11111111-1111-1111-1111-111111111111''::uuid, NULL, interval ''21 days'', ''nightly''), public.ottoq_fit_return_model(''11111111-1111-1111-1111-111111111111''::uuid, NULL, interval ''21 days'', ''nightly'');', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-learn-estimates-nightly');
-- @@ cron_job 787 ottoq-arbiter-hindsight-nightly
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (787, '*/10 11,12 * * *', 'SELECT public.ottoq_arbiter_hindsight_nightly(90000)', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-arbiter-hindsight-nightly');
-- @@ cron_job 788 ottoq-arbiter-assess-nightly
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (788, '55 12 * * *', 'SELECT public.ottoq_arbiter_assess(''11111111-1111-1111-1111-111111111111''::uuid, 7)', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-arbiter-assess-nightly');
-- @@ cron_job 789 ottoq-learn-charge-clock-nightly
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (789, '22 11 * * *', 'SET statement_timeout = ''15min''; SELECT public.ottoq_fit_charge_time_v2(''11111111-1111-1111-1111-111111111111''::uuid, NULL, interval ''21 days'', 3, ''nightly'');', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-learn-charge-clock-nightly');
-- @@ cron_job 790 ottoq-learn-charge-faults-nightly
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (790, '24 11 * * *', 'SELECT public.ottoq_fit_charge_fault_model(''11111111-1111-1111-1111-111111111111''::uuid, NULL, interval ''21 days'', ''nightly'');', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-learn-charge-faults-nightly');
-- @@ cron_job 793 ottoq-twin-operators
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (793, '* * * * *', 'CALL twin.ottoq_twin_operators_beat()', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-twin-operators');
-- @@ cron_job 800 ottoq-vehicle-scouts
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (800, '* * * * *', 'SELECT public.ottoq_vehicle_scouts_scan_live()', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-vehicle-scouts');
-- @@ cron_job 801 ottoq-channel-watchdog
INSERT INTO cron.job (jobid, schedule, command, nodename, nodeport, database, username, active, jobname) VALUES (801, '* * * * *', 'SELECT public.ottoq_channel_watchdog()', 'localhost', 5432, 'postgres', 'postgres', false, 'ottoq-channel-watchdog');
-- @@ cron_seq cron.jobid_seq
SELECT pg_catalog.setval('cron.jobid_seq', 801, true);
