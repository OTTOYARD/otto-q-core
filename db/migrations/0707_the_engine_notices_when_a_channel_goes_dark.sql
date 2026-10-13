-- migration-version: 20261013193522
-- migration-name:    the_engine_notices_when_a_channel_goes_dark
--
-- 0707  **The engine notices when a channel goes dark.** One function reads six channels: the minute-level cron beats,
--       the running run's tick, the agent's passes, the model behind them, CP-SAT, and the engine's outbound calls. A
--       one-statement cron job runs it every minute and keeps an append-only row each time a channel changes colour,
--       and every 30 minutes regardless. A dark channel is then a row with a time and a reason, not a gap nobody
--       noticed. Advisory only: nothing reads the table to decide anything, and nothing is sent anywhere.
--       (Study 2026-10-13, lane comms CI-7; G433; db/checks/0444.)
--
-- ══ §1 WHY (measured 2026-10-13, read-only, 19:22:11-19:33:59 UTC, 2:22-2:33 PM CT) ══════════════════════════════════════
--
--   (a) NOTHING WATCHES THE CHANNELS.
--       - 10 functions in public/ottoq/twin call net.http_post (8 names; ottoq_energy_mpc_replan has 3 overloads).
--       - Only the energy-MPC replan reads its own reply from net._http_response. Two collectors read replies too:
--         ottoq_energy_mpc_ingest and ottoq_oem_webhook_collect_responses.
--       - The agent's dispatches never read theirs: ottoq_sim_decide_and_dispatch, ottoq_cron_tick and
--         ottoq_cuopt_refresh. Nor does the twin's ingest refresh. Most of them PERFORM the call and discard its id.
--       - net._http_response carries no URL, and pg_net deletes the request row once it is sent. So a reply cannot
--         be traced to the call that made it after the fact. pg_net.ttl is 6 hours.
--       - No function calls pg_notify. No function reads cron.job_run_details.
--       - public.integration_health exists, is empty, and is read and written by no function or view. It is the
--         OEM-integration circuit breaker, keyed by av_platform (waymo, zoox, ...) with circuit_state
--         closed/open/half_open. It is not a home for the engine's own channels, and this file leaves it alone.
--   (b) WHAT A DARK CHANNEL LOOKED LIKE TODAY, NOTICED ONLY BY READING BY HAND.
--       - In the 6 hours to 19:24 UTC, the depot tick (*/2) went up to 3 min 25 s between starts, and the metronome
--         and every other minute job went up to 2 min 25 s. Those are the recertification pair after 0562 holding
--         pg_cron (G141): job 746 ran 144.6 s and was cancelled by the operator door at 19:19:24.
--       - 2 of the last 3,000 cron runs failed, both "canceling statement due to user request".
--       - In the 24 hours before a read taken between 19:22:11 and 19:25:39 UTC, the model ledger held 119 agent rows: 112 enacted, 6 fallback, and 1 with no
--         candidate. Attempts carry 503s from the primary model (G424).
--       - Most of the 20-second pg_net timeouts are agent dispatches whose pass outlives pg_net's timeout and then
--         completes. That is 51 of 267 calls in the 15:00 UTC hour and 18 of 350 in the 18:00 UTC hour.
--       None of this reached anyone. The study found it by reading the tables.
--   (c) WHAT A HEALTHY CHANNEL LOOKS LIKE, so the thresholds below come from data.
--       - Agent passes: on today's three runs (176b2912, 57188f55, 02ac27b3) the longest gap between passes was
--         111.7 s, and the p95 61-95 s.
--       - CP-SAT: the longest gap between calls with a status was 109.5 s, and 0 of 390 calls were non-200.
--       - Run tick: under live playback a tick is due every few seconds (02ac27b3: 73 ticks in 6 minutes).
--       - Cron cost: cron.job_run_details holds 84,846 rows (278 MB) with one index, on runid. So the watchdog reads
--         the last 1,500 runids, about 2.7 hours at today's rate, and never scans the table.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   1. public.ottoq_channel_health: append-only evidence. Columns: health_id, channel, status, prev_status, reason,
--      observed, sim_run_id, checked_at. No foreign key (0340/0364).
--   2. public.ottoq_channel_health_read(p_now): reads the six channels as of p_now and writes nothing. Thresholds:
--        cron          every active job on '* * * * *' or '*/N * * * *'. The limit L = max(3 x period, 5 min).
--                      red when a job has not started within L. amber when, in the last hour, a gap between starts
--                      exceeded L or a run failed. Other schedules (daily, weekly) are listed and not judged.
--        run_tick      the newest running run that is not a certification arm. How far now is past next_tick_due_at
--                      (else last_tick_at, else started_at): red over 5 min, amber over 2 min. idle with no such run.
--        agent_passes  on that run, the age of the newest ottoq_agent_pass_evidence row: red over 10 min, amber over
--                      3 min (healthy max 111.7 s). A run with agent_solver_chain_enabled >= 1 and no pass yet: red
--                      10 min after it started, amber after 3. With no pass and the dial off: idle.
--        agent_model   consulted passes in the last hour, any run. red when 3 or more asked and none answered; amber
--                      when under 75% answered. The primary model's failed attempts are counted in observed.
--                      idle with no ask.
--        cpsat         on that run, the newest cpsat_service ledger row with an HTTP status: red over 10 min, amber
--                      over 3 min. Over the last 15 min: red when 3 or more calls and none was 200; amber on any
--                      non-200. With no call and the dial off: idle.
--        pg_net        replies created in the last 15 min. red on any 401/403 (an engine call was refused its
--                      credentials), or when 5 or more replies and none was 2xx while not all timed out. amber on any
--                      other 4xx, any 5xx, or any error that is not a timeout. A timeout alone is counted, not judged:
--                      the agent's pass outlives pg_net's 20 s and completes (§1(b)).
--   3. public.ottoq_channel_watchdog(): writes a row for each channel whose status differs from that channel's last
--      row, or whose last row is 30 minutes old. Returns the six statuses and how many rows it wrote. It swallows
--      nothing: if it fails, cron.job_run_details records it, and its next success reports its own job amber.
--   4. public.ottoq_channel_health_now: the latest row per channel, with the time its current status began.
--   5. cron job 'ottoq-channel-watchdog', '* * * * *', one statement: SELECT public.ottoq_channel_watchdog().
--   Grants: service_role only, on the table, view and both functions. anon and authenticated get nothing.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════
--
--   No tick, decide path, proposer, check or atom reads the new table or calls either function. They read engine
--   tables and write only their own table. A certification pair blocks pg_cron (G141), so the watchdog does not run
--   inside an arm; when it runs next, it reports the gap.
--
-- ══ §4 NOT IN THIS FILE ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   - Sending an alert anywhere: where it goes (email, Slack, a phone) is Chase's choice. The table and view are what
--     a sender would read.
--   - Tracing a reply to its caller: that needs each caller to keep its request id. One change per caller, later.
--   - The twin app's cockpit: it can read the view through service_role. No UI change here.
--
-- ══ §5 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   SELECT cron.unschedule('ottoq-channel-watchdog');
--   DELETE FROM ottoq_cert_lineage WHERE name = '0707_the_engine_notices_when_a_channel_goes_dark'.
--   The table, view and functions stay (never DROP). Nothing else reads them.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0707 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0703_every_agent_pass_keeps_what_it_saw_and_what_it_changed') THEN
    RAISE EXCEPTION '0707 P1: 0703 is not classified; the agent pass evidence this file reads is not there';
  END IF;
  IF to_regclass('public.ottoq_channel_health') IS NOT NULL
     OR to_regprocedure('public.ottoq_channel_health_read(timestamp with time zone)') IS NOT NULL
     OR to_regprocedure('public.ottoq_channel_watchdog()') IS NOT NULL THEN
    RAISE EXCEPTION '0707 P1: the watchdog already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-channel-watchdog') THEN
    RAISE EXCEPTION '0707 P1: a cron job named ottoq-channel-watchdog already exists';
  END IF;
  IF to_regclass('cron.job_run_details') IS NULL OR to_regclass('net._http_response') IS NULL
     OR to_regclass('public.ottoq_agent_pass_evidence') IS NULL OR to_regclass('public.ottoq_model_call_ledger') IS NULL
     OR to_regprocedure('public.ottoq_policy_get(uuid,text,numeric)') IS NULL THEN
    RAISE EXCEPTION '0707 P1: a table or function the watchdog reads is missing';
  END IF;
  --: every column read, by name, so a renamed one refuses here and not in the first cron run
  IF (SELECT count(*) FROM information_schema.columns
       WHERE (table_schema, table_name, column_name) IN (
         ('cron','job','jobid'), ('cron','job','jobname'), ('cron','job','schedule'), ('cron','job','active'),
         ('cron','job_run_details','runid'), ('cron','job_run_details','jobid'), ('cron','job_run_details','start_time'),
         ('cron','job_run_details','status'), ('cron','job_run_details','return_message'),
         ('net','_http_response','status_code'), ('net','_http_response','timed_out'),
         ('net','_http_response','error_msg'), ('net','_http_response','created'),
         ('public','ottoq_sim_runs','next_tick_due_at'), ('public','ottoq_sim_runs','last_tick_at'),
         ('public','ottoq_sim_runs','started_at'), ('public','ottoq_sim_runs','run_by'),
         ('public','ottoq_agent_pass_evidence','recorded_at'), ('public','ottoq_agent_pass_evidence','consulted'),
         ('public','ottoq_agent_pass_evidence','model_answered'), ('public','ottoq_agent_pass_evidence','attempts'),
         ('public','ottoq_agent_pass_evidence','total_ms'),
         ('public','ottoq_model_call_ledger','provider'), ('public','ottoq_model_call_ledger','http_status'),
         ('public','ottoq_model_call_ledger','called_at'))) <> 25 THEN
    RAISE EXCEPTION '0707 P1: a column the watchdog reads is missing or renamed';
  END IF;
END $premises$;

-- ══ 1. the record ═══════════════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_channel_health (
  health_id    bigserial PRIMARY KEY,
  channel      text NOT NULL,
  status       text NOT NULL,
  --: the channel's status on its previous row (NULL on its first)
  prev_status  text,
  reason       text NOT NULL,
  observed     jsonb NOT NULL DEFAULT '{}'::jsonb,
  --: the run the run-scoped channels read; NO foreign key (0340/0364)
  sim_run_id   uuid,
  checked_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ottoq_channel_health_channel CHECK (channel IN ('cron','run_tick','agent_passes','agent_model','cpsat','pg_net')),
  CONSTRAINT ottoq_channel_health_status CHECK (status IN ('green','amber','red','idle','unknown'))
);

COMMENT ON TABLE public.ottoq_channel_health IS
'0707. One row per channel each time the watchdog (cron, every minute) sees its status change, and every 30 minutes regardless: cron (the minute-level jobs), run_tick, agent_passes, agent_model, cpsat, pg_net. Advisory: nothing reads it to decide anything. The live reading is public.ottoq_channel_health_read(); the latest row per channel is public.ottoq_channel_health_now. Append-only evidence, NO foreign key.';

CREATE INDEX ottoq_channel_health_channel_idx ON public.ottoq_channel_health (channel, health_id DESC);

CREATE OR REPLACE FUNCTION public.ottoq_channel_health_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.channel_health_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'ottoq_channel_health is append-only: % refused. Set ottoq.channel_health_unlock=on in the session '
                  'to override, and say why in a migration.', TG_OP
    USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_channel_health_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_channel_health
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_channel_health_append_only();

ALTER TABLE public.ottoq_channel_health ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ottoq_channel_health FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.ottoq_channel_health_health_id_seq FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.ottoq_channel_health TO service_role;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_channel_health', 'sim_run_id', 'evidence',
        '0707: the channel watchdog''s record, one row per channel per change of status (and a 30-minute heartbeat). '
        'Evidence: when a channel went dark, and for how long, must outlive the run it went dark in. NO foreign key, '
        'for 0340/0364''s reason.');

-- ══ 2. the reading ═════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_channel_health_read(p_now timestamptz DEFAULT now())
RETURNS TABLE (channel text, status text, reason text, observed jsonb, sim_run_id uuid)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  v_floor     bigint;
  j           record;
  v_lim       interval;
  v_since     interval;
  v_st        text;
  v_why       text;
  v_jobs      jsonb := '[]'::jsonb;
  v_unjudged  jsonb := '[]'::jsonb;
  v_worst     text := 'green';
  v_worst_why text;
  v_n_judged  integer := 0;
  v_run       record;
  v_armed     boolean;
  v_last      timestamptz;
  v_n         bigint;
  v_m         record;
  v_c         record;
  v_h         record;
BEGIN
  --: ── 1. CRON ──────────────────────────────────────────────────────────────────────────────────────────────────
  --: cron.job_run_details has one index, on runid, which pg_cron allocates as it starts each run: read the newest
  --: 1,500 runids through it (about 2.7 hours at 9 runs a minute) and never scan the table (278 MB on 2026-10-13).
  SELECT COALESCE(max(d.runid), 0) - 1500 INTO v_floor FROM cron.job_run_details d;
  FOR j IN
    WITH jobs AS (
      SELECT cj.jobid, cj.jobname, cj.schedule,
             CASE WHEN cj.schedule = '* * * * *' THEN 60
                  WHEN cj.schedule ~ '^\*/[0-9]+ \* \* \* \*$'
                    THEN 60 * substring(cj.schedule FROM '^\*/([0-9]+) ')::integer
             END AS period_s
        FROM cron.job cj
       WHERE cj.active),
    runs AS (
      SELECT d.jobid, d.start_time, d.status, d.return_message,
             d.start_time - lag(d.start_time) OVER (PARTITION BY d.jobid ORDER BY d.start_time) AS gap
        FROM cron.job_run_details d
       WHERE d.runid > v_floor AND d.start_time <= p_now)
    SELECT jb.jobname, jb.schedule, jb.period_s,
           (SELECT max(r.start_time) FROM runs r WHERE r.jobid = jb.jobid) AS last_start,
           (SELECT max(r.gap) FROM runs r
             WHERE r.jobid = jb.jobid AND r.start_time > p_now - interval '1 hour') AS max_gap,
           (SELECT count(*) FROM runs r
             WHERE r.jobid = jb.jobid AND r.status = 'failed' AND r.start_time > p_now - interval '1 hour') AS failed,
           (SELECT left(r.return_message, 200) FROM runs r
             WHERE r.jobid = jb.jobid AND r.status = 'failed' AND r.start_time > p_now - interval '1 hour'
             ORDER BY r.start_time DESC LIMIT 1) AS last_error
      FROM jobs jb
     ORDER BY jb.jobname
  LOOP
    IF j.period_s IS NULL THEN
      v_unjudged := v_unjudged || jsonb_build_array(j.jobname);
      CONTINUE;
    END IF;
    v_n_judged := v_n_judged + 1;
    v_lim   := make_interval(secs => GREATEST(3 * j.period_s, 300));
    v_since := p_now - j.last_start;
    IF j.last_start IS NULL OR v_since > v_lim THEN
      v_st  := 'red';
      v_why := CASE WHEN j.last_start IS NULL
                    THEN format('%s has not started in the last %s runs of any job', j.jobname, 1500)
                    ELSE format('%s has not started for %s min (schedule %s)', j.jobname,
                                round(extract(epoch FROM v_since)::numeric / 60, 1), j.schedule) END;
    ELSIF j.max_gap > v_lim THEN
      v_st  := 'amber';
      v_why := format('%s went %s min without a start in the last hour (schedule %s)', j.jobname,
                      round(extract(epoch FROM j.max_gap)::numeric / 60, 1), j.schedule);
    ELSIF j.failed > 0 THEN
      v_st  := 'amber';
      v_why := format('%s failed %s time(s) in the last hour: %s', j.jobname, j.failed, j.last_error);
    ELSE
      v_st  := 'green';
      v_why := NULL;
    END IF;
    IF v_st <> 'green' THEN
      v_jobs := v_jobs || jsonb_build_array(jsonb_build_object(
        'job', j.jobname, 'status', v_st, 'why', v_why,
        'last_start', j.last_start, 'max_gap_1h_s', round(extract(epoch FROM j.max_gap)::numeric, 1),
        'failed_1h', j.failed));
    END IF;
    IF (v_st = 'red' AND v_worst <> 'red') OR (v_st = 'amber' AND v_worst = 'green') THEN
      v_worst := v_st;
      v_worst_why := v_why;
    END IF;
  END LOOP;
  channel := 'cron'; sim_run_id := NULL;
  status  := CASE WHEN v_n_judged = 0 THEN 'unknown' ELSE v_worst END;
  reason  := CASE WHEN v_n_judged = 0 THEN 'no active job runs on a minute schedule'
                  WHEN v_worst = 'green' THEN format('all %s minute-level jobs on time in the last hour', v_n_judged)
                  ELSE v_worst_why END;
  observed := jsonb_build_object('judged', v_n_judged, 'not_green', v_jobs, 'not_judged', v_unjudged,
                                 'runid_floor', v_floor);
  RETURN NEXT;

  --: ── 2. RUN TICK ─────────────────────────────────────────────────────────────────────────────────────────────
  SELECT r.sim_run_id, r.depot_id, r.run_by, r.tick_count, r.sim_clock_current, r.started_at, r.last_tick_at,
         r.next_tick_due_at
    INTO v_run
    FROM public.ottoq_sim_runs r
   WHERE r.status = 'running' AND COALESCE(r.run_by, '') <> 'cert_harness' AND r.started_at <= p_now
   ORDER BY r.started_at DESC
   LIMIT 1;

  IF v_run.sim_run_id IS NULL THEN
    FOREACH channel IN ARRAY ARRAY['run_tick', 'agent_passes', 'cpsat'] LOOP
      status := 'idle'; reason := 'no run is running'; observed := '{}'::jsonb; sim_run_id := NULL;
      RETURN NEXT;
    END LOOP;
  ELSE
    v_since := p_now - COALESCE(v_run.next_tick_due_at, v_run.last_tick_at, v_run.started_at);
    channel := 'run_tick'; sim_run_id := v_run.sim_run_id;
    status  := CASE WHEN v_since > interval '5 minutes' THEN 'red'
                    WHEN v_since > interval '2 minutes' THEN 'amber' ELSE 'green' END;
    reason  := CASE WHEN status = 'green' THEN format('ticking (tick %s)', v_run.tick_count)
                    ELSE format('tick %s is %s min overdue', v_run.tick_count + 1,
                                round(extract(epoch FROM v_since)::numeric / 60, 1)) END;
    observed := jsonb_build_object('run_by', v_run.run_by, 'depot_id', v_run.depot_id, 'tick', v_run.tick_count,
                                   'sim_clock', v_run.sim_clock_current, 'last_tick_at', v_run.last_tick_at,
                                   'next_tick_due_at', v_run.next_tick_due_at,
                                   'overdue_s', round(extract(epoch FROM v_since)::numeric, 1));
    RETURN NEXT;

    --: ── 3. AGENT PASSES ────────────────────────────────────────────────────────────────────────────────────────
    v_armed := COALESCE(public.ottoq_policy_get(v_run.sim_run_id, 'agent_solver_chain_enabled', 0), 0) >= 1;
    SELECT max(e.recorded_at), count(*) INTO v_last, v_n
      FROM public.ottoq_agent_pass_evidence e
     WHERE e.sim_run_id = v_run.sim_run_id AND e.recorded_at <= p_now;
    channel := 'agent_passes'; sim_run_id := v_run.sim_run_id;
    IF v_n = 0 AND NOT v_armed THEN
      status := 'idle'; reason := 'the agent is not armed on this run (agent_solver_chain_enabled is 0)';
    ELSE
      v_since := p_now - COALESCE(v_last, v_run.started_at);
      status  := CASE WHEN v_since > interval '10 minutes' THEN 'red'
                      WHEN v_since > interval '3 minutes' THEN 'amber' ELSE 'green' END;
      reason  := CASE WHEN v_n = 0 AND status <> 'green'
                        THEN format('armed, and no agent pass in the %s min since the run started',
                                    round(extract(epoch FROM v_since)::numeric / 60, 1))
                      WHEN v_n = 0 THEN 'armed; the first pass is not due yet'
                      WHEN status = 'green' THEN format('%s passes on this run, the last %s s ago', v_n,
                                                        round(extract(epoch FROM v_since)::numeric))
                      ELSE format('no agent pass for %s min (%s on this run)',
                                  round(extract(epoch FROM v_since)::numeric / 60, 1), v_n) END;
    END IF;
    observed := jsonb_build_object('armed', v_armed, 'passes', v_n, 'last_pass_at', v_last);
    RETURN NEXT;

    --: ── 5. CP-SAT (on the run) ─────────────────────────────────────────────────────────────────────────────────
    SELECT max(l.called_at) AS last_at, count(*) AS n,
           count(*) FILTER (WHERE l.called_at > p_now - interval '15 minutes') AS n15,
           count(*) FILTER (WHERE l.called_at > p_now - interval '15 minutes' AND l.http_status <> 200) AS bad15,
           (array_agg(l.http_status ORDER BY l.called_at DESC) FILTER (WHERE l.http_status <> 200))[1] AS last_bad
      INTO v_c
      FROM public.ottoq_model_call_ledger l
     WHERE l.sim_run_id = v_run.sim_run_id AND l.provider = 'cpsat_service' AND l.http_status IS NOT NULL
       AND l.called_at <= p_now;
    channel := 'cpsat'; sim_run_id := v_run.sim_run_id;
    IF v_c.n = 0 AND NOT v_armed THEN
      status := 'idle'; reason := 'no CP-SAT call on this run and the agent is not armed';
    ELSE
      v_since := p_now - COALESCE(v_c.last_at, v_run.started_at);
      status  := CASE WHEN v_since > interval '10 minutes' THEN 'red'
                      WHEN v_c.n15 >= 3 AND v_c.bad15 = v_c.n15 THEN 'red'
                      WHEN v_since > interval '3 minutes' OR v_c.bad15 > 0 THEN 'amber' ELSE 'green' END;
      reason  := CASE WHEN v_c.n15 >= 3 AND v_c.bad15 = v_c.n15
                        THEN format('none of the last %s CP-SAT calls returned 200 (last %s)', v_c.n15, v_c.last_bad)
                      WHEN v_c.n = 0 AND status <> 'green'
                        THEN format('armed, and CP-SAT has not answered in the %s min since the run started',
                                    round(extract(epoch FROM v_since)::numeric / 60, 1))
                      WHEN v_c.n = 0 THEN 'armed; no CP-SAT call due yet'
                      WHEN v_since > interval '3 minutes'
                        THEN format('no CP-SAT call for %s min', round(extract(epoch FROM v_since)::numeric / 60, 1))
                      WHEN v_c.bad15 > 0
                        THEN format('%s of %s CP-SAT calls in the last 15 min were not 200 (last %s)', v_c.bad15,
                                    v_c.n15, v_c.last_bad)
                      ELSE format('%s calls in the last 15 min, all 200', v_c.n15) END;
    END IF;
    observed := jsonb_build_object('calls', v_c.n, 'calls_15m', v_c.n15, 'not_200_15m', v_c.bad15,
                                   'last_call_at', v_c.last_at);
    RETURN NEXT;
  END IF;

  --: ── 4. AGENT MODEL (any run, last hour) ─────────────────────────────────────────────────────────────────────
  SELECT count(*) AS asked,
         count(*) FILTER (WHERE e.model_answered IS NOT NULL) AS answered,
         count(*) FILTER (WHERE jsonb_typeof(e.attempts) = 'array' AND jsonb_array_length(e.attempts) > 0
                            AND e.attempts -> 0 ->> 'status' IS DISTINCT FROM 'ok') AS primary_failed,
         round(avg(e.total_ms)) AS mean_ms
    INTO v_m
    FROM public.ottoq_agent_pass_evidence e
   WHERE e.consulted AND e.recorded_at > p_now - interval '1 hour' AND e.recorded_at <= p_now;
  channel := 'agent_model'; sim_run_id := NULL;
  status := CASE WHEN v_m.asked = 0 THEN 'idle'
                 WHEN v_m.asked >= 3 AND v_m.answered = 0 THEN 'red'
                 WHEN v_m.answered::numeric < 0.75 * v_m.asked THEN 'amber' ELSE 'green' END;
  reason := CASE WHEN v_m.asked = 0 THEN 'the model was not asked in the last hour'
                 ELSE format('%s of %s asks in the last hour answered; the first model asked failed on %s',
                             v_m.answered, v_m.asked, v_m.primary_failed) END;
  observed := jsonb_build_object('asked_1h', v_m.asked, 'answered_1h', v_m.answered,
                                 'primary_failed_1h', v_m.primary_failed, 'mean_pass_ms', v_m.mean_ms);
  RETURN NEXT;

  --: ── 6. PG_NET (the engine's outbound calls, last 15 minutes) ────────────────────────────────────────────────
  SELECT count(*) AS n,
         count(*) FILTER (WHERE h.status_code BETWEEN 200 AND 299) AS ok,
         count(*) FILTER (WHERE h.status_code IN (401, 403)) AS auth,
         count(*) FILTER (WHERE h.status_code BETWEEN 400 AND 499 AND h.status_code NOT IN (401, 403)) AS c4xx,
         count(*) FILTER (WHERE h.status_code >= 500) AS c5xx,
         count(*) FILTER (WHERE h.timed_out) AS timed_out,
         count(*) FILTER (WHERE h.status_code IS NULL AND NOT COALESCE(h.timed_out, false)
                            AND h.error_msg IS NOT NULL) AS other_err,
         (array_agg(left(h.error_msg, 160) ORDER BY h.created DESC)
            FILTER (WHERE h.error_msg IS NOT NULL AND NOT COALESCE(h.timed_out, false)))[1] AS last_err
    INTO v_h
    FROM net._http_response h
   WHERE h.created > p_now - interval '15 minutes' AND h.created <= p_now;
  channel := 'pg_net'; sim_run_id := NULL;
  status := CASE WHEN v_h.n = 0 THEN 'idle'
                 WHEN v_h.auth > 0 THEN 'red'
                 WHEN v_h.n >= 5 AND v_h.ok = 0 AND v_h.timed_out < v_h.n THEN 'red'
                 WHEN v_h.c4xx > 0 OR v_h.c5xx > 0 OR v_h.other_err > 0 THEN 'amber' ELSE 'green' END;
  reason := CASE WHEN v_h.n = 0 THEN 'no outbound call replied in the last 15 min'
                 WHEN v_h.auth > 0 THEN format('%s outbound call(s) refused their credentials (401/403) in the last 15 min',
                                               v_h.auth)
                 ELSE format('%s replies in the last 15 min: %s 2xx, %s 4xx, %s 5xx, %s other errors, %s timed out',
                             v_h.n, v_h.ok, v_h.c4xx + v_h.auth, v_h.c5xx, v_h.other_err, v_h.timed_out) END;
  observed := jsonb_build_object('replies_15m', v_h.n, 'ok_2xx', v_h.ok, 'auth_401_403', v_h.auth, 'other_4xx', v_h.c4xx,
                                 'c5xx', v_h.c5xx, 'timed_out', v_h.timed_out, 'other_errors', v_h.other_err,
                                 'last_error', v_h.last_err,
                                 'timed_out_note', 'a call that outlives pg_net''s 20 s timeout reads timed out; the '
                                                   'agent''s pass does, and completes (0707 §1(b))');
  RETURN NEXT;
END $fn$;

COMMENT ON FUNCTION public.ottoq_channel_health_read(timestamptz) IS
'0707. The six channels as of p_now (cron, run_tick, agent_passes, agent_model, cpsat, pg_net), each green, amber, red, idle or unknown, with a reason and what was observed. Reads only. Thresholds in db/migrations/0707 §2.';

-- ══ 3. the watchdog ═════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_channel_watchdog()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $fn$
DECLARE
  r              record;
  v_prev_status  text;
  v_prev_at      timestamptz;
  v_written      integer := 0;
  v_out          jsonb := '{}'::jsonb;
BEGIN
  FOR r IN SELECT * FROM public.ottoq_channel_health_read(now()) LOOP
    v_prev_status := NULL;
    v_prev_at := NULL;
    SELECT h.status, h.checked_at INTO v_prev_status, v_prev_at
      FROM public.ottoq_channel_health h
     WHERE h.channel = r.channel
     ORDER BY h.health_id DESC
     LIMIT 1;
    IF v_prev_at IS NULL OR v_prev_status IS DISTINCT FROM r.status OR v_prev_at < now() - interval '30 minutes' THEN
      INSERT INTO public.ottoq_channel_health (channel, status, prev_status, reason, observed, sim_run_id)
      VALUES (r.channel, r.status, v_prev_status, r.reason, r.observed, r.sim_run_id);
      v_written := v_written + 1;
    END IF;
    v_out := v_out || jsonb_build_object(r.channel, r.status);
  END LOOP;
  RETURN v_out || jsonb_build_object('written', v_written);
END $fn$;

COMMENT ON FUNCTION public.ottoq_channel_watchdog() IS
'0707. Reads ottoq_channel_health_read(now()) and appends a row for each channel whose status changed since its last row, or whose last row is 30 minutes old. Run by cron job ottoq-channel-watchdog every minute. Swallows nothing.';

-- ══ 4. the latest row per channel ═══════════════════════════════════════════════════════════════════════════════
CREATE VIEW public.ottoq_channel_health_now WITH (security_invoker = true) AS
SELECT DISTINCT ON (h.channel)
       h.channel, h.status, h.reason, h.observed, h.sim_run_id, h.checked_at,
       --: when the current status began: the first row after the last row with a different status
       (SELECT min(h2.checked_at) FROM public.ottoq_channel_health h2
         WHERE h2.channel = h.channel
           AND h2.health_id > COALESCE((SELECT max(h3.health_id) FROM public.ottoq_channel_health h3
                                         WHERE h3.channel = h.channel AND h3.status <> h.status), 0)) AS status_since
  FROM public.ottoq_channel_health h
 ORDER BY h.channel, h.health_id DESC;

COMMENT ON VIEW public.ottoq_channel_health_now IS
'0707. The latest watchdog row per channel and when its status began. As of the watchdog''s last write (at most a minute old while cron runs); for a live reading call ottoq_channel_health_read().';

REVOKE ALL ON public.ottoq_channel_health_now FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ottoq_channel_health_now TO service_role;
REVOKE ALL ON FUNCTION public.ottoq_channel_health_read(timestamptz), public.ottoq_channel_watchdog(),
                       public.ottoq_channel_health_append_only()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_channel_health_read(timestamptz), public.ottoq_channel_watchdog()
  TO service_role;

-- ══ 5. the schedule: one statement, every minute ══════════════════════════════════════════════════════════════
SELECT cron.schedule('ottoq-channel-watchdog', '* * * * *', $cron$SELECT public.ottoq_channel_watchdog()$cron$);

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v$
DECLARE v_n integer; v_r jsonb; v_cron text;
BEGIN
  --: V1 the reading names each channel once, each with a known status
  SELECT count(*) INTO v_n FROM (SELECT DISTINCT c.channel FROM public.ottoq_channel_health_read(now()) c
                                  WHERE c.status IN ('green','amber','red','idle','unknown')) x;
  IF v_n <> 6 OR (SELECT count(*) FROM public.ottoq_channel_health_read(now())) <> 6 THEN
    RAISE EXCEPTION '0707 V1 FAILED: the reading did not name six channels once each (%)', v_n;
  END IF;

  --: V2 the staleness arithmetic: read as of an hour from now, every minute job is an hour stale, so cron is red
  SELECT c.status INTO v_cron FROM public.ottoq_channel_health_read(now() + interval '1 hour') c WHERE c.channel = 'cron';
  IF v_cron IS DISTINCT FROM 'red' THEN
    RAISE EXCEPTION '0707 V2 FAILED: cron read as of an hour from now is %, not red', v_cron;
  END IF;

  --: V3 the first watch writes one row per channel; the record is append-only
  v_r := public.ottoq_channel_watchdog();
  IF (v_r ->> 'written')::integer <> 6 OR (SELECT count(*) FROM public.ottoq_channel_health) <> 6 THEN
    RAISE EXCEPTION '0707 V3 FAILED: the first watch did not write six rows: %', v_r;
  END IF;
  BEGIN
    UPDATE public.ottoq_channel_health SET status = 'green';
    RAISE EXCEPTION '0707 V3 FAILED: an UPDATE was allowed';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  --: V4 one statement, every minute, and no client role can read or call any of it
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-channel-watchdog' AND schedule = '* * * * *'
                    AND command = 'SELECT public.ottoq_channel_watchdog()') THEN
    RAISE EXCEPTION '0707 V4 FAILED: the cron job is not as written';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_channel_watchdog()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_channel_health_read(timestamp with time zone)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'public.ottoq_channel_health', 'SELECT')
     OR has_table_privilege('anon', 'public.ottoq_channel_health_now', 'SELECT')
     OR NOT has_function_privilege('service_role', 'public.ottoq_channel_watchdog()', 'EXECUTE') THEN
    RAISE EXCEPTION '0707 V4 FAILED: grants are not as written';
  END IF;
  RAISE NOTICE '0707 V1-V4 PASSED: %', v_r;
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0707_the_engine_notices_when_a_channel_goes_dark', false, false,
  'Study 2026-10-13 (comms CI-7; G433; db/checks/0444): a channel watchdog. ottoq_channel_health_read(p_now) reads six '
  'channels (minute-level cron jobs, the running run''s tick, agent passes, the model behind them, CP-SAT, pg_net '
  'replies) with thresholds from the day''s data; ottoq_channel_watchdog() appends a row to the evidence table '
  'ottoq_channel_health on a change of status or a 30-minute heartbeat, from one cron statement a minute. Advisory: '
  'nothing reads it to decide, nothing is sent. No tick, decide path or atom reads it: FALSE/FALSE.',
  now());

COMMIT;
