-- migration-version: 20261013151002
-- migration-name:    every_car_has_a_deterministic_scout_and_the_agent_reads_what_they_find
--
-- 0704  **Every car has a deterministic scout, and the agent reads what they find.** Six SQL scouts check each car's
--        own records against CLAUDE.md rule 9 and its owner's contract, once a minute and whenever the agent is about
--        to be consulted. Zero model tokens, byte-reproducible, and every finding is an append-only evidence row. The
--        agent's board carries a digest of them. This is the per-vehicle "swarm" OTTO-Q actually needs. (Study
--        2026-10-13: VF-1, VF-2, VF-3, VF-6, the architecture verdict; db/checks/0441.)
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase asked on 2026-10-13 whether OTTO-Q should run swarms of agents that spin up each run and scan the vehicles
--   and the depot. The study's answer (docs/AGENT_ARCHITECTURE.md) is: yes to a swarm that scans every car, no to that
--   swarm being language models. Every vehicle-first failure the study found was a disagreement between two of OTTO-Q's
--   own records about ONE car, visible with the right join and needing no reasoning:
--
--   (a) VF-1 / G181 / G218. On run 3390752c (busy_day, twin depot) 163 departures followed a recall for
--       service_interval_due and 130 of them left with no preventive maintenance or calibration done in between (re-run
--       2026-10-13, read-only, by exactly the query scout A uses). The recall policy reads the wear counters; the
--       departure gate reads only visit atoms; the twin observer puts the interval service on the visit 24-30% of the
--       time. Rule 9: "preventive maintenance, a sensor calibration ... are all finished before the car leaves."
--   (b) 158 departures on the same run came back within 30 sim-minutes for the same trigger that sent them home.
--   (c) VF-2 / G313. Four schedule_tasks rows from 2026-06-04 sit 'in_progress' at the twin depot and make the critical
--       rule HW.005 refuse Zoox-AV-084's bay work on every run (455 refusals across today's four runs).
--   (d) VF-3 / G384. 43.7-45.7% of plug-ins came after the owner's 30-minute contract queue wait; nothing records which
--       car crossed it, and ottoq_sla_violations has received 0 rows in its life.
--   (e) The shield logged 131 failures in 180,658 evaluations on 3390752c, 130 of them (c). None of (a), (b) or (d)
--       is any rule's job today, so a green shield said nothing about them.
--
--   A language-model agent per car would cost a model call per car per scan and could disagree with itself on the same
--   records. A SQL scout per car costs a join, gives the same answer every time, and can be certified.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════
--
--   1. public.ottoq_vehicle_scout_findings -- append-only evidence, one row per (run, car, scout, episode). Episodes:
--      a departure (dispatch_id), a visit (visit_id) or a legacy task (task id), so a finding is recorded once, the
--      first time a scan sees it, and never rewritten. NO foreign key (0340/0364), registered class 'evidence'.
--   2. public.ottoq_vehicle_scouts_scan(run) -- the six scouts, each in its own error-swallowing block:
--        A interval_due_departure  high      a departure after a service_interval_due recall with no PM/calibration
--                                            done between the return and the departure (rule 9)
--        B same_trigger_rebound    medium    a departure recalled within 30 sim-minutes for the trigger that sent it
--                                            home the time before
--        C departed_below_target   critical  a departure after run start below ottoq_effective_target_soc_at - 1
--                                            (rule 9's charge half; expected 0 -- the scout is the assurance monitor)
--        D contract_wait_breach    high      a car in the kernel's charge line waiting longer than its owner's active
--                                            contract max_queue_wait_minutes (one per visit)
--        E stranded_open_must_do   high      an open visit more than 4 sim-hours old with a must_do atom open and no
--                                            atom finished in the last 2 sim-hours
--        F legacy_task_residue     high      an in_progress schedule_tasks row for a car of this depot created more
--                                            than a day before the run started (G313's shape)
--      Advisory only: no scout moves a car, books a stall, writes a dial or blocks anything. A scout that errors records
--      its error in the return value and the others still run.
--   3. public.ottoq_vehicle_scouts_scan_live() -- scans every running run (and any run that ticked in the last 10
--      minutes, so a run's last minute is not lost), each in its own block. cron job 'ottoq-vehicle-scouts' runs it
--      every minute as ONE statement (G141: a multi-statement cron command blocks the scheduler).
--   4. public.ottoq_vehicle_scouts_digest(run, limit) -- counts by scout, the last 60 sim-minutes, the newest findings.
--   5. public.ottoq_agent_board gains a 'scouts' block when grounding is armed (agent_board_grounding_enabled >= 1)
--      and agent_scouts_enabled (new catalog row, default 1) >= 1. Done by SUBSTITUTION on the live definition: the
--      function body is read, the one anchor `RETURN v_board;` is asserted to occur exactly once, the block is
--      inserted before it, and the result is executed -- so every other byte of the board is the live board's. V1
--      asserts the board grew by exactly the block; tests/test_agent_scouts_wake_sql.py executes the live board before
--      and after and shows an unarmed board (every certification arm) is byte-identical.
--
--   NOT changed: the departure gate, the recall policy, the twin observer and the shield. The scouts SEE (a)-(d); fixing
--   them is separate, certified work (G218 decides (a)).
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═══════════════════════════════════════════════════════════════
--
--   The scan writes only its own evidence table and runs from cron and the agent's edge function, never inside a tick.
--   The board change is gated on agent_board_grounding_enabled, which certification arms never set; the pytest above
--   asserts an unarmed board is unchanged. No atom hashes the findings table (P2).
--
-- ══ §4 ROLLBACK ══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   SELECT cron.unschedule('ottoq-vehicle-scouts'); and EXECUTE the ottoq_agent_board definition snapshotted under
--   label '0704_pre' in ottoq_schema_snapshots. The findings table is evidence and stays.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0704 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file was written against ──
DO $premises$
DECLARE v_md5 text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0703_every_agent_pass_keeps_what_it_saw_and_what_it_changed') THEN
    RAISE EXCEPTION '0704 P1: 0703 is not classified; apply in order';
  END IF;
  IF to_regclass('public.ottoq_vehicle_scout_findings') IS NOT NULL THEN
    RAISE EXCEPTION '0704 P1: the findings table already exists';
  END IF;
  IF to_regprocedure('public.ottoq_charge_queue_kernel_order(uuid,uuid,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.ottoq_effective_target_soc_at(uuid,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.ottoq_policy_get(uuid,text,numeric)') IS NULL THEN
    RAISE EXCEPTION '0704 P1: a function the scouts read is missing';
  END IF;
  SELECT md5(pg_get_functiondef('public.ottoq_agent_board(uuid)'::regprocedure)) INTO v_md5;
  IF v_md5 IS DISTINCT FROM '8613653559d1cb10eacacbe3c73293fc' THEN
    RAISE EXCEPTION '0704 P1: ottoq_agent_board is not the definition this file was written against (md5 %)', v_md5;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_scouts_enabled') THEN
    RAISE EXCEPTION '0704 P1: agent_scouts_enabled is already in the catalog';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-vehicle-scouts') THEN
    RAISE EXCEPTION '0704 P1: a cron job named ottoq-vehicle-scouts already exists';
  END IF;
END $premises$;

-- ── P2: no hashing function or atom names the new table ──
DO $atoms$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname IN ('public','ottoq','twin') AND p.prosrc ~ 'ottoq_vehicle_scout') THEN
    RAISE EXCEPTION '0704 P2: a function already names the scouts';
  END IF;
END $atoms$;

-- ── snapshot the one function this file replaces ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0704_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_board';

-- ══ 1. the findings ═══════════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_vehicle_scout_findings (
  finding_id            bigserial PRIMARY KEY,
  --: durable keys, NO foreign keys (0340/0364)
  sim_run_id            uuid,
  depot_id              uuid,
  vehicle_id            uuid NOT NULL,
  scout                 text NOT NULL,
  severity              text NOT NULL,
  --: the thing the finding is about: a dispatch, a visit or a task. Recorded once per episode.
  episode_key           text NOT NULL,
  --: SIM domain: when the thing happened (a departure) or when the scan first saw it (a state)
  first_seen_sim_clock  timestamptz,
  first_seen_tick       bigint,
  detail                jsonb NOT NULL DEFAULT '{}'::jsonb,
  recorded_at           timestamptz NOT NULL DEFAULT now(),
  source_kind           text NOT NULL DEFAULT 'live',
  CONSTRAINT ottoq_vehicle_scout_known CHECK (scout IN ('interval_due_departure','same_trigger_rebound',
             'departed_below_target','contract_wait_breach','stranded_open_must_do','legacy_task_residue')),
  CONSTRAINT ottoq_vehicle_scout_severity CHECK (severity IN ('critical','high','medium','low')),
  CONSTRAINT ottoq_vehicle_scout_once UNIQUE NULLS NOT DISTINCT (sim_run_id, vehicle_id, scout, episode_key)
);

COMMENT ON TABLE public.ottoq_vehicle_scout_findings IS
'0704. One row per (run, car, scout, episode) the first time a deterministic per-vehicle scout sees it: interval_due_departure (a departure after a service_interval_due recall with no PM/calibration done since -- rule 9), same_trigger_rebound (recalled within 30 sim-min for the same trigger), departed_below_target (rule 9 charge half; expected 0), contract_wait_breach (waiting past the owner''s contract max_queue_wait_minutes), stranded_open_must_do (an open visit over 4 sim-hours with a must_do open and nothing finished in 2), legacy_task_residue (an in_progress schedule_tasks row older than the run, G313). Advisory: no scout acts. Append-only evidence, NO foreign key. The agent''s board carries ottoq_vehicle_scouts_digest.';

CREATE INDEX ottoq_vehicle_scout_findings_run_idx ON public.ottoq_vehicle_scout_findings (sim_run_id, finding_id DESC);
CREATE INDEX ottoq_vehicle_scout_findings_scout_idx ON public.ottoq_vehicle_scout_findings (scout, recorded_at DESC);

CREATE OR REPLACE FUNCTION public.ottoq_vehicle_scout_findings_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.scout_findings_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'ottoq_vehicle_scout_findings is append-only: % refused. Set ottoq.scout_findings_unlock=on in the '
                  'session to override, and say why in a migration.', TG_OP
    USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_vehicle_scout_findings_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_vehicle_scout_findings
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_vehicle_scout_findings_append_only();

ALTER TABLE public.ottoq_vehicle_scout_findings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ottoq_vehicle_scout_findings FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.ottoq_vehicle_scout_findings_finding_id_seq FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.ottoq_vehicle_scout_findings TO service_role;
GRANT USAGE ON SEQUENCE public.ottoq_vehicle_scout_findings_finding_id_seq TO service_role;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_vehicle_scout_findings', 'sim_run_id', 'evidence',
        '0704: what the deterministic per-vehicle scouts found, one row per (run, car, scout, episode). Evidence: the '
        'record of every car whose own records disagreed with rule 9 or its owner''s contract must outlive the run '
        'that produced it. NO foreign key, for 0340/0364''s reason.');

-- ══ 2. the scan ═══════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_vehicle_scouts_scan(p_sim_run_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_run    record;
  v_zero   constant uuid := '00000000-0000-0000-0000-000000000000';
  v_new    jsonb := '{}'::jsonb;
  v_err    jsonb := '{}'::jsonb;
  v_n      integer;
  v_t0     timestamptz := clock_timestamp();
BEGIN
  SELECT r.sim_run_id, r.depot_id, r.sim_clock_current, r.sim_clock_start, r.tick_count, r.started_at
    INTO v_run FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_run.sim_run_id IS NULL OR v_run.depot_id IS NULL OR v_run.sim_clock_current IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'run', p_sim_run_id, 'skipped', 'run not found or has no sim clock');
  END IF;
  --: two scans of one run (the cron job and an agent pass) take turns; inserts are idempotent anyway
  PERFORM pg_advisory_xact_lock(hashtextextended('ottoq_vehicle_scouts:' || p_sim_run_id::text, 0));

  --: A, B, C -- departures, judged after the fact from the dispatch ledger
  BEGIN
    WITH d AS (
      SELECT d.dispatch_id, d.vehicle_id, d.dispatched_at, d.return_trigger, d.returning_started_at,
             d.actual_return_at, d.soc_at_dispatch_pct,
             lag(d.return_trigger)   OVER w AS prev_trigger,
             lag(d.actual_return_at) OVER w AS prev_return_at
        FROM public.ottoq_vehicle_dispatches d
       WHERE d.sim_run_id = p_sim_run_id
      WINDOW w AS (PARTITION BY d.vehicle_id ORDER BY d.dispatched_at, d.dispatch_id)
    ), f AS (
      SELECT d.vehicle_id, 'interval_due_departure'::text AS scout, 'high'::text AS sev, d.dispatch_id::text AS ek,
             d.dispatched_at AS at,
             jsonb_build_object('dispatch_id', d.dispatch_id, 'dispatched_at', d.dispatched_at,
                                'recalled_last_for', d.prev_trigger, 'returned_at', d.prev_return_at,
                                'owed', 'mechanical_pm or sensor_calibration',
                                'rule', 'CLAUDE.md rule 9: preventive maintenance and calibration are finished before a car leaves') AS detail
        FROM d
       WHERE d.prev_trigger = 'service_interval_due'
         AND NOT EXISTS (
               SELECT 1 FROM public.ottoq_visit_needs vn, jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
                WHERE vn.vehicle_id = d.vehicle_id AND vn.sim_run_id = p_sim_run_id
                  AND a ->> 'svc' IN ('mechanical_pm', 'sensor_calibration') AND a ->> 'status' = 'done'
                  AND COALESCE(NULLIF(a ->> 'done_at', '')::timestamptz, NULLIF(a ->> 'closed_at', '')::timestamptz)
                      BETWEEN d.prev_return_at AND d.dispatched_at)
      UNION ALL
      SELECT d.vehicle_id, 'same_trigger_rebound', 'medium', d.dispatch_id::text, d.dispatched_at,
             jsonb_build_object('dispatch_id', d.dispatch_id, 'trigger', d.return_trigger,
                                'minutes_out', round(extract(epoch FROM (COALESCE(d.returning_started_at, d.actual_return_at)
                                                                         - d.dispatched_at)) / 60.0, 1))
        FROM d
       WHERE d.return_trigger IS NOT NULL AND d.return_trigger = d.prev_trigger
         AND COALESCE(d.returning_started_at, d.actual_return_at) < d.dispatched_at + interval '30 minutes'
      UNION ALL
      SELECT d.vehicle_id, 'departed_below_target', 'critical', d.dispatch_id::text, d.dispatched_at,
             jsonb_build_object('dispatch_id', d.dispatch_id, 'soc_at_dispatch', d.soc_at_dispatch_pct,
                                'target', public.ottoq_effective_target_soc_at(d.vehicle_id, d.dispatched_at),
                                'rule', 'CLAUDE.md rule 9: a car below its charge target does not leave')
        FROM d
       WHERE d.dispatched_at > v_run.sim_clock_start
         AND d.soc_at_dispatch_pct IS NOT NULL
         AND d.soc_at_dispatch_pct < public.ottoq_effective_target_soc_at(d.vehicle_id, d.dispatched_at) - 1
    )
    INSERT INTO public.ottoq_vehicle_scout_findings
           (sim_run_id, depot_id, vehicle_id, scout, severity, episode_key, first_seen_sim_clock, first_seen_tick, detail)
    SELECT p_sim_run_id, v_run.depot_id, f.vehicle_id, f.scout, f.sev, f.ek, f.at, v_run.tick_count, f.detail FROM f
    ON CONFLICT ON CONSTRAINT ottoq_vehicle_scout_once DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_new := v_new || jsonb_build_object('departures', v_n);
  EXCEPTION WHEN OTHERS THEN
    v_err := v_err || jsonb_build_object('departures', SQLERRM);
  END;

  --: D -- a car in the kernel's charge line past its owner's contract queue wait, once per visit
  BEGIN
    INSERT INTO public.ottoq_vehicle_scout_findings
           (sim_run_id, depot_id, vehicle_id, scout, severity, episode_key, first_seen_sim_clock, first_seen_tick, detail)
    SELECT p_sim_run_id, v_run.depot_id, k.vehicle_id, 'contract_wait_breach', 'high',
           COALESCE(vn.visit_id::text, 'no_open_visit'), v_run.sim_clock_current, v_run.tick_count,
           jsonb_build_object('wait_min', round(k.wait_min, 0), 'contract_wait_limit_min', sla.max_queue_wait_minutes,
                              'soc', round(k.soc, 1), 'kernel_pos', k.kernel_pos, 'visit_id', vn.visit_id)
      FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current) k
      JOIN public.vehicles v ON v.id = k.vehicle_id
      CROSS JOIN LATERAL (
        SELECT s.max_queue_wait_minutes FROM public.ottoq_fleet_operator_slas s
         WHERE s.fleet_operator_id = v.fleet_operator_id AND s.status = 'active'
           AND s.effective_from <= v_run.sim_clock_current
           AND (s.effective_until IS NULL OR s.effective_until > v_run.sim_clock_current)
         ORDER BY s.version DESC LIMIT 1) sla
      LEFT JOIN LATERAL (
        SELECT vn.visit_id FROM public.ottoq_visit_needs vn
         WHERE vn.vehicle_id = k.vehicle_id AND vn.status IN ('open', 'in_progress')
           AND COALESCE(vn.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
         ORDER BY vn.created_at DESC LIMIT 1) vn ON true
     WHERE sla.max_queue_wait_minutes IS NOT NULL AND k.wait_min > sla.max_queue_wait_minutes
    ON CONFLICT ON CONSTRAINT ottoq_vehicle_scout_once DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_new := v_new || jsonb_build_object('contract_wait_breach', v_n);
  EXCEPTION WHEN OTHERS THEN
    v_err := v_err || jsonb_build_object('contract_wait_breach', SQLERRM);
  END;

  --: E -- an open visit over 4 sim-hours with a must_do atom open and nothing finished in the last 2
  BEGIN
    INSERT INTO public.ottoq_vehicle_scout_findings
           (sim_run_id, depot_id, vehicle_id, scout, severity, episode_key, first_seen_sim_clock, first_seen_tick, detail)
    SELECT p_sim_run_id, v_run.depot_id, vn.vehicle_id, 'stranded_open_must_do', 'high', vn.visit_id::text,
           v_run.sim_clock_current, v_run.tick_count,
           jsonb_build_object('visit_id', vn.visit_id, 'arrived_at', vn.arrived_at,
                              'hours_since_arrival', round(extract(epoch FROM (v_run.sim_clock_current - vn.arrived_at)) / 3600.0, 1),
                              'open_must_do', (SELECT jsonb_agg(a ->> 'svc' ORDER BY a ->> 'svc')
                                                 FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
                                                WHERE COALESCE(a ->> 'must_do', 'false') = 'true'
                                                  AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled')))
      FROM public.ottoq_visit_needs vn
     WHERE vn.depot_id = v_run.depot_id
       AND COALESCE(vn.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
       AND vn.status IN ('open', 'in_progress')
       AND vn.arrived_at < v_run.sim_clock_current - interval '240 minutes'
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
                    WHERE COALESCE(a ->> 'must_do', 'false') = 'true'
                      AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled'))
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
                        WHERE COALESCE(NULLIF(a ->> 'done_at', ''), NULLIF(a ->> 'closed_at', '')) IS NOT NULL
                          AND COALESCE(NULLIF(a ->> 'done_at', '')::timestamptz, NULLIF(a ->> 'closed_at', '')::timestamptz)
                              > v_run.sim_clock_current - interval '120 minutes')
    ON CONFLICT ON CONSTRAINT ottoq_vehicle_scout_once DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_new := v_new || jsonb_build_object('stranded_open_must_do', v_n);
  EXCEPTION WHEN OTHERS THEN
    v_err := v_err || jsonb_build_object('stranded_open_must_do', SQLERRM);
  END;

  --: F -- an in_progress scheduler task older than the run, for a car of this depot (G313's shape)
  BEGIN
    INSERT INTO public.ottoq_vehicle_scout_findings
           (sim_run_id, depot_id, vehicle_id, scout, severity, episode_key, first_seen_sim_clock, first_seen_tick, detail)
    SELECT p_sim_run_id, v_run.depot_id, st.vehicle_id, 'legacy_task_residue', 'high', st.id::text,
           v_run.sim_clock_current, v_run.tick_count,
           jsonb_build_object('task_id', st.id, 'service_code', st.service_code, 'status', st.status::text,
                              'created_at', st.created_at,
                              'note', 'an in_progress task older than the run; HW.005 counts it as the car''s one task (G313)')
      FROM public.schedule_tasks st
      JOIN public.vehicles v ON v.id = st.vehicle_id
     WHERE v.home_depot_id = v_run.depot_id
       AND st.status::text = 'in_progress'
       AND st.created_at < COALESCE(v_run.started_at, now()) - interval '1 day'
    ON CONFLICT ON CONSTRAINT ottoq_vehicle_scout_once DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_new := v_new || jsonb_build_object('legacy_task_residue', v_n);
  EXCEPTION WHEN OTHERS THEN
    v_err := v_err || jsonb_build_object('legacy_task_residue', SQLERRM);
  END;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'ok', v_err = '{}'::jsonb, 'run', p_sim_run_id, 'tick', v_run.tick_count, 'new', v_new,
    'errors', NULLIF(v_err, '{}'::jsonb),
    'ms', round(extract(epoch FROM (clock_timestamp() - v_t0)) * 1000)));
EXCEPTION WHEN OTHERS THEN
  --: total: a scan never raises to its caller (cron, the agent's edge function)
  RETURN jsonb_build_object('ok', false, 'run', p_sim_run_id, 'error', SQLERRM);
END $fn$;

COMMENT ON FUNCTION public.ottoq_vehicle_scouts_scan(uuid) IS
'0704. Runs the six deterministic per-vehicle scouts over one run and records each new finding once (ON CONFLICT DO NOTHING on run, car, scout, episode). Advisory: it writes only ottoq_vehicle_scout_findings. Total: returns {ok,new,errors,ms} and never raises.';

CREATE OR REPLACE FUNCTION public.ottoq_vehicle_scouts_scan_live()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE v_r record; v_out jsonb := '[]'::jsonb;
BEGIN
  FOR v_r IN
    SELECT r.sim_run_id FROM public.ottoq_sim_runs r
     WHERE r.status = 'running' OR r.last_tick_at > now() - interval '10 minutes'
     ORDER BY r.started_at DESC LIMIT 5
  LOOP
    v_out := v_out || jsonb_build_array(public.ottoq_vehicle_scouts_scan(v_r.sim_run_id));
  END LOOP;
  RETURN v_out;
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_array(jsonb_build_object('ok', false, 'error', SQLERRM));
END $fn$;

COMMENT ON FUNCTION public.ottoq_vehicle_scouts_scan_live() IS
'0704. The scouts over every running run (and any run that ticked in the last 10 minutes), newest first, at most 5. Called once a minute by cron job ottoq-vehicle-scouts as a single statement.';

-- ══ 3. the digest the agent reads ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_vehicle_scouts_digest(p_sim_run_id uuid, p_limit integer DEFAULT 10)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  WITH r AS (
    SELECT r.sim_clock_current AS clk FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id
  ), f AS (
    SELECT f.finding_id, f.vehicle_id, f.scout, f.severity, f.first_seen_sim_clock, f.detail,
           COALESCE(v.display_name, f.vehicle_id::text) AS car
      FROM public.ottoq_vehicle_scout_findings f
      LEFT JOIN public.vehicles v ON v.id = f.vehicle_id
     WHERE f.sim_run_id = p_sim_run_id
  )
  SELECT jsonb_build_object(
    'what', 'Deterministic per-vehicle scouts (0704): one SQL check per car, zero model calls. Each finding is a car '
            'whose own records disagree with CLAUDE.md rule 9 or its owner''s contract. No dial fixes these; name the car '
            'and the finding in a directive, and never propose shortening a charge or skipping a service because of one.',
    'total', (SELECT count(*) FROM f),
    'by_scout', COALESCE((SELECT jsonb_object_agg(x.scout, x.n) FROM (SELECT scout, count(*) n FROM f GROUP BY 1) x),
                         '{}'::jsonb),
    'last_60_sim_min', COALESCE((SELECT jsonb_object_agg(x.scout, x.n)
                                   FROM (SELECT f.scout, count(*) n FROM f, r
                                          WHERE f.first_seen_sim_clock > r.clk - interval '60 minutes' GROUP BY 1) x),
                                '{}'::jsonb),
    'newest', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                 'car', x.car, 'scout', x.scout, 'severity', x.severity,
                                 'min_ago', round(extract(epoch FROM ((SELECT clk FROM r) - x.first_seen_sim_clock)) / 60.0, 0),
                                 'detail', x.detail) ORDER BY x.finding_id DESC)
                          FROM (SELECT * FROM f ORDER BY finding_id DESC LIMIT GREATEST(p_limit, 0)) x),
                       '[]'::jsonb))
$fn$;

COMMENT ON FUNCTION public.ottoq_vehicle_scouts_digest(uuid, integer) IS
'0704. What the scouts found on a run, for the agent''s board: totals by scout, the last 60 sim-minutes, and the newest findings by car.';

REVOKE ALL ON FUNCTION public.ottoq_vehicle_scouts_scan(uuid), public.ottoq_vehicle_scouts_scan_live(),
                       public.ottoq_vehicle_scouts_digest(uuid, integer),
                       public.ottoq_vehicle_scout_findings_append_only() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_vehicle_scouts_scan(uuid), public.ottoq_vehicle_scouts_scan_live(),
                          public.ottoq_vehicle_scouts_digest(uuid, integer) TO service_role;

-- ══ 4. the dial and the board ═══════════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('agent_scouts_enabled',
        '0704: when >= 1 (the default) and grounding is armed (agent_board_grounding_enabled >= 1), ottoq_agent_board '
        'carries a scouts block: what the deterministic per-vehicle scouts found on the run. 0 removes the block. An '
        'unarmed board (every certification arm) never carries it.',
        1, 0, 1, 'ottoq_agent_board (0704)', false);

DO $board$
DECLARE
  v_def    text := pg_get_functiondef('public.ottoq_agent_board(uuid)'::regprocedure);
  v_anchor constant text := E'\n  RETURN v_board;\nEND;';
  v_block  constant text := E'\n  --: 0704. THE SCOUTS. What the deterministic per-vehicle scouts found on this run (ottoq_vehicle_scouts_digest).\n'
                         || E'  --: Gated on grounding like 0432, so an unarmed board (every certification arm) is byte-identical.\n'
                         || E'  IF COALESCE(ottoq_policy_get(p_sim_run_id,''agent_board_grounding_enabled'',0),0) >= 1\n'
                         || E'     AND COALESCE(ottoq_policy_get(p_sim_run_id,''agent_scouts_enabled'',1),1) >= 1 THEN\n'
                         || E'    v_board := v_board || jsonb_build_object(''scouts'', public.ottoq_vehicle_scouts_digest(p_sim_run_id, 10));\n'
                         || E'  END IF;\n';
  v_n int;
BEGIN
  v_n := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0704 board: the anchor occurs % times in ottoq_agent_board, expected exactly 1', v_n;
  END IF;
  EXECUTE replace(v_def, v_anchor, v_block || v_anchor);
END $board$;

-- ══ 5. the schedule: one statement, every minute ══════════════════════════════════════════════════════════════
SELECT cron.schedule('ottoq-vehicle-scouts', '* * * * *', $cron$SELECT public.ottoq_vehicle_scouts_scan_live()$cron$);

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v$
DECLARE v_def text := pg_get_functiondef('public.ottoq_agent_board(uuid)'::regprocedure);
        v_old text := (SELECT s.definition FROM public.ottoq_schema_snapshots s
                        WHERE s.label = '0704_pre' AND s.object_name = 'ottoq_agent_board' ORDER BY 1 DESC LIMIT 1);
        v_r jsonb;
BEGIN
  --: V1 the board differs from the live one by exactly the block
  IF replace(v_def, 'v_board := v_board || jsonb_build_object(''scouts''', '') = v_def THEN
    RAISE EXCEPTION '0704 V1 FAILED: the board does not carry the scouts block';
  END IF;
  IF length(v_def) - length(v_old) <> length(E'\n  --: 0704. THE SCOUTS. What the deterministic per-vehicle scouts found on this run (ottoq_vehicle_scouts_digest).\n'
                         || E'  --: Gated on grounding like 0432, so an unarmed board (every certification arm) is byte-identical.\n'
                         || E'  IF COALESCE(ottoq_policy_get(p_sim_run_id,''agent_board_grounding_enabled'',0),0) >= 1\n'
                         || E'     AND COALESCE(ottoq_policy_get(p_sim_run_id,''agent_scouts_enabled'',1),1) >= 1 THEN\n'
                         || E'    v_board := v_board || jsonb_build_object(''scouts'', public.ottoq_vehicle_scouts_digest(p_sim_run_id, 10));\n'
                         || E'  END IF;\n') THEN
    RAISE EXCEPTION '0704 V1 FAILED: the board changed by more than the block (% -> % chars)', length(v_old), length(v_def);
  END IF;

  --: V2 the scan is total: an unknown run is a skip, not an error
  v_r := public.ottoq_vehicle_scouts_scan('00000000-0000-0000-0000-0000000000ff');
  IF COALESCE((v_r ->> 'ok')::boolean, true) OR v_r ->> 'skipped' IS NULL THEN
    RAISE EXCEPTION '0704 V2 FAILED: an unknown run did not return a skip: %', v_r;
  END IF;

  --: V3 one statement, every minute, and the public key cannot call any of it
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-vehicle-scouts' AND schedule = '* * * * *'
                    AND command = 'SELECT public.ottoq_vehicle_scouts_scan_live()') THEN
    RAISE EXCEPTION '0704 V3 FAILED: the cron job is not as written';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_vehicle_scouts_scan(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.ottoq_vehicle_scouts_scan(uuid)', 'EXECUTE')
     OR has_table_privilege('anon', 'public.ottoq_vehicle_scout_findings', 'SELECT') THEN
    RAISE EXCEPTION '0704 V3 FAILED: grants are not as written';
  END IF;
  RAISE NOTICE '0704 V1-V3 PASSED';
END $v$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0704_every_car_has_a_deterministic_scout_and_the_agent_reads_what_they_find', false, false,
  'Study 2026-10-13 (VF-1/VF-2/VF-3; db/checks/0441): six deterministic per-vehicle scouts write an append-only evidence '
  'table from cron (one statement a minute) and the agent''s edge function, never inside a tick; ottoq_agent_board '
  'gains a scouts block gated on agent_board_grounding_enabled, which certification arms never set, so an unarmed '
  'board is byte-identical. No atom hashes the findings: FALSE/FALSE.',
  now());

COMMIT;
