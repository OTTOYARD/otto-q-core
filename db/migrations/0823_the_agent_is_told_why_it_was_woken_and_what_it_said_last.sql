-- migration-version: PENDING
-- migration-name:    0823_the_agent_is_told_why_it_was_woken_and_what_it_said_last
--
-- 0823  **The agent is told why it was woken, which cars and chargers are behind each reason, and what it said last.**
--       (G540)
--
-- ══ §1 WHY (measured 2026-11-13 02:10-02:50 UTC, the evening of 11-12 CT, read-only, the twin depot) ══════════════════
--
--   Since 0795 (2026-11-05) the agent is consulted on exceptions and on a 30-sim-minute heartbeat. Read from
--   public.ottoq_agent_pass_evidence for depot 11111111-…, recorded_at >= 2026-11-05 22:00 UTC: 286 answered consults
--   on 16 runs, 7,161,273 model tokens (mean 23,969 prompt tokens a consult).
--     * 0 of the 286 changed engine state (advisory, echo and no_effect only), and all 286 chose the same solver
--       objective, readiness_first.
--     * The wake gate (public.ottoq_agent_wake) knows WHY each consult happened: its `reasons`. The model is never
--       told. The edge function sends "BOARD DIGEST: <board>" and nothing else, and 0 of the 286 stored boards carry a
--       wake reason. The gate's fingerprint is counts only: it names no car and no charger.
--     * So the answers are the standing picture, whatever the reason. Of the 5 consults woken by an emergency, 0 of
--       the answers mention one. Of the 59 woken by a charger fault, repair or emergency, 31 mention a fault at all.
--     * The agent has no memory of its own words: each consult re-issues the standing directives (1,005 in 286).
--   What the depot's own records hold at such a moment, and the model never sees: on run cce21ff2 (busy_day,
--   2026-11-13 00:36 UTC) 19 charges were cut by a charger fault. 16 of the cars were charging again within 9 minutes,
--   one (Tesla-AV-055, cut at 75% by fault.thermal_emergency) waited 39 minutes and one 15. Rule 9 says a faulted
--   charge is re-queued to finish; which car that is, and how long it has waited, is exactly what an exception consult
--   should say, and it is one read away.
--
-- ══ §2 WHAT THIS ADDS ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) One dial, a person's (rule 10): agent_wake_brief (0..1, default 0, not agent-writable).
--   (b) public.ottoq_agent_wake_brief(p_sim_run_id, p_wake): STABLE, no write, total. NULL at the dial's default. With
--       the dial on it returns, from the run's own rows at the run's clock:
--         reasons            the gate's reasons, as passed in
--         last_answer        how long ago (sim minutes) the agent last answered on this run, and the directives it
--                            issued then (you_said) -- the same decision row the gate reads as the last consult (0710)
--         changed            each fingerprint count that differs from that consult's: {was, now}
--         subjects.charges_cut_by_fault   each charge a fault cut since the last answer, and every earlier one whose
--                            car is still in the charge line with no charge since: car, owner, post, fault, the SoC it
--                            was cut at, its target, and where it is now (charging again on which post and after how
--                            many minutes; or waiting, with its place in the kernel's line; or its state)
--         subjects.chargers_faulted       the chargers Faulted now: post, fault code, minutes ago, new since last
--         subjects.emergencies            the cars in tow_requested or emergency_staged
--         subjects.past_contract_wait     the count, and the 8 cars longest past their owner's contract wait
--         subjects.scout_findings_new     the actionable scout findings first seen since the last answer
--         subjects.dr_call                a live demand-response call
--       "Since the last answer" is the last 60 sim-minutes at a run's first consult. On an error it returns
--       {v, error, reasons} and never raises: a broken brief costs the brief, never the consult.
--   (c) public.ottoq_agent_wake_brief_coverage: one row per subject a brief named (a car whose charge was newly cut, a
--       car in an emergency, a newly faulted post, a car a scout newly found), with whether the agent's directives on
--       that pass name it. The instrument for "did the agent answer what it was woken for", and the label a later
--       evaluation or training set reads.
--   The agent's edge function (v32, in this commit) calls (b) after the gate says wake, puts the brief ahead of the
--   board in the model's message, appends a section to its prompt that says how to read it, and keeps the brief on the
--   pass's evidence row and decision row inside `wake` (wake.brief), so a pass replays from its own record.
--
-- ══ §3 WHAT IT DOES NOT CHANGE ════════════════════════════════════════════════════════════════════════════════════
--
--   No car's order, charge, target or service (rule 9). No lever: the agent proposes exactly what it could before (a
--   solver objective, three dials outside production, directives checked against rule 9, a shadow charge order). No
--   setting moves by itself (rule 10). The board (public.ottoq_agent_board) and the wake gate are not touched: not a
--   byte. With the dial at 0 the function returns NULL and edge v32 sends v31's message and v31's prompt.
--
-- ══ §4 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 0795 is classified and the objects this file reads exist with the columns it reads.
--   P2 once. V1 the brief is STABLE, executable by service_role and by no browser role, and its body writes nothing
--   (comment-stripped). V2 the board and the wake gate are byte for byte what they were. V3 at the default the brief is
--   NULL on every run this database holds. V4 with the dial on for one transaction-local probe (rolled back by a
--   savepoint) the brief of the newest run with agent passes is an object with v = 1 and no error, and nothing was
--   written. V5 the body is the one the tests ran (md5). tests/test_agent_wake_brief_sql.py runs this file on the
--   scratch PostgreSQL over the wake stub: each subject on its case and its near-miss, the first consult, an error that
--   returns instead of raising, no write, the ACL, the coverage view's name matching, and a refused second apply.
--
-- ══ §5 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE: nothing in the engine reads the new function or the view; their one caller is the agent's
--   edge function, quiesced in certification arms; no atom hashes a model's prompt. forces_dial_restart FALSE: the one
--   new dial is read by the brief alone.
--
-- ══ §6 ON AT THE TWIN DEPOT (CLAUDE.md rule 12) ═══════════════════════════════════════════════════════════════════
--
--   agent_wake_brief = 1 at depot scope for the twin depot, at the apply (Chase, 2026-11-12 evening CT: "do a new pass
--   of OTTO-Q. Specifically analyzing the agent layer ... find the edge to implement for us"). It has an effect only
--   once edge v32 is deployed; until then nothing calls the function. The demo-run check is db/checks/0488.
--
-- ROLLBACK: DROP VIEW public.ottoq_agent_wake_brief_coverage; DROP FUNCTION public.ottoq_agent_wake_brief(uuid, jsonb);
--   DELETE FROM public.ottoq_policy_params WHERE param_key = 'agent_wake_brief'; DELETE FROM
--   public.ottoq_policy_param_catalog WHERE param_key = 'agent_wake_brief'; DELETE FROM public.ottoq_cert_lineage WHERE
--   name = '0823_the_agent_is_told_why_it_was_woken_and_what_it_said_last'. Edge v32 treats a missing function as no
--   brief.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0823 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: what this file reads is there ──
DO $p1$
DECLARE v_missing text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0795_the_agents_charge_order_becomes_a_background_challenger_and_the_agent_wakes_for_exceptions') THEN
    RAISE EXCEPTION '0823 P1: 0795 is not classified; apply in order';
  END IF;
  IF to_regprocedure('public.ottoq_agent_wake(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_agent_board(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_charge_queue_kernel_order(uuid,uuid,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.ottoq_effective_target_soc_at(uuid,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.ottoq_policy_get(uuid,text,numeric)') IS NULL THEN
    RAISE EXCEPTION '0823 P1: a function the brief reads is missing';
  END IF;
  SELECT string_agg(w.t || '.' || w.c, ', ') INTO v_missing
    FROM (VALUES ('ocpp_sessions', 'id'), ('ocpp_sessions', 'sim_run_id'), ('ocpp_sessions', 'vehicle_id'),
                 ('ocpp_sessions', 'stall_id'), ('ocpp_sessions', 'status'), ('ocpp_sessions', 'started_at'),
                 ('ocpp_sessions', 'ended_at'), ('ocpp_sessions', 'soc_end'), ('ocpp_sessions', 'stopped_reason'),
                 ('ottoq_ocpp_chargers', 'ocpp_identifier'), ('ottoq_ocpp_chargers', 'last_fault_code'),
                 ('ottoq_ocpp_chargers', 'last_fault_at'), ('ottoq_ocpp_chargers', 'station_state'),
                 ('ottoq_ocpp_chargers', 'decommissioned_at'),
                 ('vehicles', 'display_name'), ('vehicles', 'last_state_change'), ('vehicles', 'current_state'),
                 ('vehicles', 'current_soc'), ('vehicles', 'fleet_operator_id'), ('vehicles', 'home_depot_id'),
                 ('stalls', 'stall_code'), ('stalls', 'ocpp_charger_id'), ('fleet_operators', 'name'),
                 ('ottoq_vehicle_scout_findings', 'finding_id'), ('ottoq_vehicle_scout_findings', 'first_seen_sim_clock'),
                 ('ottoq_vehicle_scout_findings', 'severity'), ('ottoq_vehicle_scout_findings', 'detail'),
                 ('ottoq_dr_calls', 'required_load_cap_kw'), ('ottoq_dr_calls', 'call_status'),
                 ('ottoq_sim_runs', 'sim_clock_start'), ('ottoq_sim_runs', 'sim_clock_current'),
                 ('ottoq_decisions', 'decision_seq'), ('ottoq_decisions', 'enacted_action'),
                 ('ottoq_agent_pass_evidence', 'wake'), ('ottoq_agent_pass_evidence', 'answer'),
                 ('ottoq_agent_pass_evidence', 'consulted')) AS w(t, c)
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns ic
                      WHERE ic.table_schema = 'public' AND ic.table_name = w.t AND ic.column_name = w.c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0823 P1: a column the brief reads is missing: %', v_missing;
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0823_the_agent_is_told_why_it_was_woken_and_what_it_said_last')
     OR to_regprocedure('public.ottoq_agent_wake_brief(uuid,jsonb)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_wake_brief') THEN
    RAISE EXCEPTION '0823 P2: already applied';
  END IF;
END $once$;

-- ── what V2 holds the board and the gate to ──
CREATE TEMP TABLE _0823_untouched ON COMMIT DROP AS
SELECT p.oid::regprocedure::text AS fn, md5(pg_get_functiondef(p.oid)) AS def_md5
  FROM pg_proc p
 WHERE p.oid IN ('public.ottoq_agent_board(uuid)'::regprocedure, 'public.ottoq_agent_wake(uuid)'::regprocedure);

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES
  ('agent_wake_brief',
   '0823: 1 = a consulted agent pass is told why it was woken: the wake gate''s reasons, each count that changed since '
   'its last answer, the cars and chargers behind each reason (a charge a fault cut and where its car is now, the '
   'chargers faulted, the cars in an emergency, the cars longest past their contract wait, the scouts'' new findings, '
   'a demand-response call) and the directives it issued last. Read-only, from the run''s own rows. 0 = the agent is '
   'sent its board alone, as before 0823. A person''s dial (rule 10).',
   0, 0, 1,
   'public.ottoq_agent_wake_brief; edge ottoq-orchestrator-agent v32', false);

-- ── (b) the brief. Created from a string with every carriage return removed, so a paste with Windows line endings
-- stores the body the tests ran (V5). ──
DO $create$
BEGIN
  EXECUTE replace($def$CREATE FUNCTION public.ottoq_agent_wake_brief(p_sim_run_id uuid, p_wake jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_zero      constant uuid := '00000000-0000-0000-0000-000000000000';
  v_run       record;
  v_last      record;
  v_new       timestamptz;   --: what happened after this moment is new to the agent
  v_now_fp    jsonb;
  v_changed   jsonb;
  v_said      jsonb;
  v_cut       jsonb;  v_cut_n   integer;
  v_over      jsonb;  v_over_n  integer;
  v_fault     jsonb;  v_fault_n integer;  v_fault_new integer;
  v_emerg     jsonb;
  v_scout     jsonb;  v_scout_n integer;
  v_dr        jsonb;
BEGIN
  --: 0823 (G540). Why the agent was woken, in the depot's own rows. Read-only and total: NULL when the dial is off or
  --: the run is unknown, {v, error, reasons} when anything below fails.
  IF p_sim_run_id IS NULL THEN RETURN NULL; END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_wake_brief', 0), 0) < 1 THEN RETURN NULL; END IF;
  SELECT r.sim_run_id, r.depot_id, r.sim_clock_current AS clock, r.sim_clock_start AS started
    INTO v_run FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_run.sim_run_id IS NULL OR v_run.depot_id IS NULL OR v_run.clock IS NULL THEN RETURN NULL; END IF;
  v_now_fp := CASE WHEN jsonb_typeof(p_wake -> 'fingerprint') = 'object' THEN p_wake -> 'fingerprint' ELSE '{}'::jsonb END;

  --: the agent's last answered consult on this run: the decision row the wake gate reads (0710)
  SELECT d.sim_clock, d.context_frame -> 'wake' -> 'fingerprint' AS fp, d.enacted_action -> 'applied' AS applied
    INTO v_last
    FROM public.ottoq_decisions d
   WHERE d.sim_run_id = p_sim_run_id AND d.resolved_action_context = 'orchestrator_agent'
     AND d.enacted_action ->> 'source' = 'nemotron' AND d.context_frame ? 'wake'
   ORDER BY d.tick_seq DESC, d.decision_seq DESC LIMIT 1;
  v_new := COALESCE(v_last.sim_clock, v_run.clock - interval '60 minutes');

  --: each count the gate keeps that differs from that consult's
  SELECT jsonb_object_agg(n.key, jsonb_build_object('was', p.value, 'now', n.value))
    INTO v_changed
    FROM jsonb_each(v_now_fp) n
    JOIN jsonb_each(CASE WHEN jsonb_typeof(v_last.fp) = 'object' THEN v_last.fp ELSE '{}'::jsonb END) p ON p.key = n.key
   WHERE p.value IS DISTINCT FROM n.value;

  --: what the agent told the operators then
  SELECT jsonb_agg(left(a.value ->> 'text', 300) ORDER BY a.ordinality)
    INTO v_said
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v_last.applied) = 'array' THEN v_last.applied
                                   ELSE '[]'::jsonb END) WITH ORDINALITY a
   WHERE a.value ->> 'type' = 'directive' AND a.ordinality <= 8;

  --: the charges a fault cut, and the cars past their contract wait: one read of the kernel's line for both
  WITH k AS MATERIALIZED (
    SELECT q.vehicle_id, q.kernel_pos, q.wait_min, q.soc
      FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, v_run.depot_id, v_run.clock) q
  ), cut AS (
    --: new since the last answer, or older with its car still in the charge line and no charge since (rule 9: a
    --: faulted charge is re-queued to finish, so a car still waiting is the exception that has not closed)
    SELECT s.vehicle_id, s.ended_at, s.soc_end, s.stopped_reason, st.stall_code AS post,
           nx.started_at AS again_at, ns.stall_code AS again_post, k.kernel_pos,
           (s.ended_at > v_new) AS is_new,
           (nx.started_at IS NULL AND k.kernel_pos IS NOT NULL) AS waiting
      FROM public.ocpp_sessions s
      LEFT JOIN public.stalls st ON st.id = s.stall_id
      LEFT JOIN LATERAL (SELECT n.started_at, n.stall_id FROM public.ocpp_sessions n
                          WHERE n.sim_run_id = s.sim_run_id AND n.vehicle_id = s.vehicle_id AND n.id <> s.id
                            AND n.started_at >= s.ended_at AND n.started_at <= v_run.clock
                          ORDER BY n.started_at LIMIT 1) nx ON true
      LEFT JOIN public.stalls ns ON ns.id = nx.stall_id
      LEFT JOIN k ON k.vehicle_id = s.vehicle_id
     WHERE s.sim_run_id = p_sim_run_id AND s.status::text = 'faulted'
       AND s.ended_at IS NOT NULL AND s.ended_at <= v_run.clock
       AND (s.ended_at > v_new OR (nx.started_at IS NULL AND k.kernel_pos IS NOT NULL))
  ), cutj AS (
    SELECT c.waiting, c.ended_at, v.display_name,
           jsonb_build_object(
             'car', v.display_name, 'owner', fo.name, 'post', c.post, 'fault', c.stopped_reason,
             'cut_at_soc', c.soc_end, 'target', public.ottoq_effective_target_soc_at(c.vehicle_id, v_run.clock),
             'min_ago', round(extract(epoch FROM (v_run.clock - c.ended_at)) / 60.0), 'new', c.is_new,
             'charging_again_on', c.again_post,
             'again_after_min', round(extract(epoch FROM (c.again_at - c.ended_at)) / 60.0),
             'waiting_in_line_pos', CASE WHEN c.waiting THEN c.kernel_pos END,
             'state', CASE WHEN c.again_at IS NULL THEN v.current_state::text END,
             'soc_now', CASE WHEN c.again_at IS NULL THEN round(v.current_soc) END) AS j
      FROM cut c
      JOIN public.vehicles v ON v.id = c.vehicle_id
      LEFT JOIN public.fleet_operators fo ON fo.id = v.fleet_operator_id
  ), over AS (
    SELECT k.kernel_pos, k.wait_min, k.soc, sla.max_queue_wait_minutes AS lim, v.display_name, fo.name AS owner
      FROM k
      JOIN public.vehicles v ON v.id = k.vehicle_id
      LEFT JOIN public.fleet_operators fo ON fo.id = v.fleet_operator_id
      CROSS JOIN LATERAL (
        SELECT s.max_queue_wait_minutes FROM public.ottoq_fleet_operator_slas s
         WHERE s.fleet_operator_id = v.fleet_operator_id AND s.status = 'active'
           AND s.effective_from <= v_run.clock
           AND (s.effective_until IS NULL OR s.effective_until > v_run.clock)
         ORDER BY s.version DESC LIMIT 1) sla
     WHERE sla.max_queue_wait_minutes IS NOT NULL AND k.wait_min > sla.max_queue_wait_minutes
  )
  SELECT (SELECT count(*) FROM cutj),
         (SELECT jsonb_agg(z.j ORDER BY z.waiting DESC, z.wait_key ASC NULLS LAST, z.ended_at DESC, z.display_name)
            FROM (SELECT c.waiting, CASE WHEN c.waiting THEN c.ended_at END AS wait_key, c.ended_at, c.display_name, c.j
                    FROM cutj c
                   ORDER BY c.waiting DESC, CASE WHEN c.waiting THEN c.ended_at END ASC NULLS LAST, c.ended_at DESC,
                            c.display_name
                   LIMIT 10) z),
         (SELECT count(*) FROM over),
         (SELECT jsonb_agg(z.j ORDER BY z.over_min DESC, z.kernel_pos, z.display_name)
            FROM (SELECT (o.wait_min - o.lim) AS over_min, o.kernel_pos, o.display_name,
                         jsonb_build_object('car', o.display_name, 'owner', o.owner, 'wait_min', round(o.wait_min),
                                            'limit_min', o.lim, 'over_min', round(o.wait_min - o.lim),
                                            'line_pos', o.kernel_pos, 'soc', round(o.soc)) AS j
                    FROM over o
                   ORDER BY (o.wait_min - o.lim) DESC, o.kernel_pos, o.display_name
                   LIMIT 8) z)
    INTO v_cut_n, v_cut, v_over_n, v_over;

  --: the chargers Faulted now
  SELECT count(*), count(*) FILTER (WHERE f.is_new),
         jsonb_agg(f.j ORDER BY f.is_new DESC, f.last_fault_at DESC NULLS LAST, f.post) FILTER (WHERE f.rn <= 10)
    INTO v_fault_n, v_fault_new, v_fault
    FROM (SELECT x.*, row_number() OVER (ORDER BY x.is_new DESC, x.last_fault_at DESC NULLS LAST, x.post) AS rn
            FROM (SELECT c.last_fault_at, COALESCE(st.stall_code, c.ocpp_identifier, c.charger_id::text) AS post,
                         COALESCE(c.last_fault_at > v_new AND c.last_fault_at <= v_run.clock, false) AS is_new,
                         jsonb_build_object(
                           'post', COALESCE(st.stall_code, c.ocpp_identifier, c.charger_id::text),
                           'charger', c.ocpp_identifier, 'fault', c.last_fault_code,
                           'min_ago', CASE WHEN c.last_fault_at <= v_run.clock
                                            AND c.last_fault_at >= COALESCE(v_run.started, c.last_fault_at)
                                           THEN round(extract(epoch FROM (v_run.clock - c.last_fault_at)) / 60.0) END,
                           'new', COALESCE(c.last_fault_at > v_new AND c.last_fault_at <= v_run.clock, false)) AS j
                    FROM public.ottoq_ocpp_chargers c
                    LEFT JOIN LATERAL (SELECT s.stall_code FROM public.stalls s
                                        WHERE s.ocpp_charger_id = c.charger_id
                                        ORDER BY s.stall_code LIMIT 1) st ON true
                   WHERE c.depot_id = v_run.depot_id AND c.station_state = 'Faulted'
                     AND c.decommissioned_at IS NULL) x) f;

  --: the cars in an emergency, as the gate counts them
  SELECT jsonb_agg(e.j ORDER BY e.display_name)
    INTO v_emerg
    FROM (SELECT v.display_name,
                 jsonb_build_object(
                   'car', v.display_name, 'owner', fo.name, 'state', v.current_state::text,
                   'soc', round(v.current_soc),
                   'min_in_state', CASE WHEN v.last_state_change <= v_run.clock
                                         AND v.last_state_change >= COALESCE(v_run.started, v.last_state_change)
                                        THEN round(extract(epoch FROM (v_run.clock - v.last_state_change)) / 60.0) END) AS j
            FROM public.vehicles v
            LEFT JOIN public.fleet_operators fo ON fo.id = v.fleet_operator_id
           WHERE v.home_depot_id = v_run.depot_id AND v.current_state::text IN ('tow_requested', 'emergency_staged')
           ORDER BY v.display_name LIMIT 10) e;

  --: the scouts' actionable findings first seen since the last answer (the three the gate counts; a car past its
  --: contract wait is counted above)
  SELECT count(*), jsonb_agg(f.j ORDER BY f.crit DESC, f.first_seen DESC, f.finding_id) FILTER (WHERE f.rn <= 10)
    INTO v_scout_n, v_scout
    FROM (SELECT x.*, row_number() OVER (ORDER BY x.crit DESC, x.first_seen DESC, x.finding_id) AS rn
            FROM (SELECT sf.finding_id, sf.first_seen_sim_clock AS first_seen,
                         (sf.scout IN ('departed_below_target', 'legacy_task_residue')) AS crit,
                         jsonb_build_object(
                           'scout', sf.scout, 'severity', sf.severity, 'car', v.display_name, 'owner', fo.name,
                           'min_ago', round(extract(epoch FROM (v_run.clock - sf.first_seen_sim_clock)) / 60.0),
                           'detail', COALESCE(sf.detail, '{}'::jsonb) - 'visit_id' - 'task_id' - 'note') AS j
                    FROM public.ottoq_vehicle_scout_findings sf
                    JOIN public.vehicles v ON v.id = sf.vehicle_id
                    LEFT JOIN public.fleet_operators fo ON fo.id = v.fleet_operator_id
                   WHERE sf.sim_run_id = p_sim_run_id
                     AND sf.scout IN ('stranded_open_must_do', 'departed_below_target', 'legacy_task_residue')
                     AND sf.first_seen_sim_clock > v_new AND sf.first_seen_sim_clock <= v_run.clock) x) f;

  --: a live demand-response call, as the gate reads one
  SELECT jsonb_build_object('program', c.program, 'reason', c.reason, 'status', c.call_status,
                            'required_load_cap_kw', c.required_load_cap_kw,
                            'minutes_left', round(extract(epoch FROM (c.expires_at - v_run.clock)) / 60.0))
    INTO v_dr
    FROM public.ottoq_dr_calls c
   WHERE c.depot_id = v_run.depot_id AND c.call_status IN ('active', 'issued') AND c.expires_at > v_run.clock
     AND COALESCE(c.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
   ORDER BY c.expires_at DESC LIMIT 1;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'v', 1,
    'reasons', CASE WHEN jsonb_typeof(p_wake -> 'reasons') = 'array' THEN p_wake -> 'reasons' ELSE '[]'::jsonb END,
    'sim_clock', v_run.clock,
    'new_means', CASE WHEN v_last.sim_clock IS NOT NULL THEN 'since your last answer'
                      ELSE 'in the last 60 minutes: this is your first answer on this run' END,
    'last_answer', CASE WHEN v_last.sim_clock IS NOT NULL THEN jsonb_build_object(
                     'sim_min_ago', round(extract(epoch FROM (v_run.clock - v_last.sim_clock)) / 60.0, 1),
                     'you_said', v_said) END,
    'changed', v_changed,
    'subjects', jsonb_build_object(
      'charges_cut_by_fault', CASE WHEN v_cut_n > 0 THEN jsonb_build_object('count', v_cut_n, 'cars', v_cut) END,
      'chargers_faulted', CASE WHEN v_fault_n > 0 THEN jsonb_build_object('count', v_fault_n, 'new', v_fault_new,
                                                                          'chargers', v_fault) END,
      'emergencies', v_emerg,
      'past_contract_wait', CASE WHEN v_over_n > 0 THEN jsonb_build_object('count', v_over_n, 'longest', v_over) END,
      'scout_findings_new', CASE WHEN v_scout_n > 0 THEN jsonb_build_object('count', v_scout_n,
                                                                            'findings', v_scout) END,
      'dr_call', v_dr)));
EXCEPTION WHEN OTHERS THEN
  --: total: a broken brief costs the brief, never the consult
  RETURN jsonb_build_object('v', 1, 'error', SQLERRM,
                            'reasons', CASE WHEN jsonb_typeof(p_wake -> 'reasons') = 'array' THEN p_wake -> 'reasons'
                                            ELSE '[]'::jsonb END);
END $function$$def$, E'\r', '');
END $create$;

REVOKE ALL ON FUNCTION public.ottoq_agent_wake_brief(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_wake_brief(uuid, jsonb) TO service_role;

COMMENT ON FUNCTION public.ottoq_agent_wake_brief(uuid, jsonb) IS
  '0823 (G540): why a consulted agent pass was woken, from the run''s own rows: the wake gate''s reasons, each count '
  'changed since the agent''s last answer, the cars and chargers behind each reason, and the directives it issued '
  'last. STABLE, writes nothing, never raises. NULL while agent_wake_brief is 0. Its caller is the agent''s edge '
  'function (v32), which keeps the brief on the pass''s record as wake.brief.';

-- ── (c) did the agent answer what it was woken for ──
CREATE VIEW public.ottoq_agent_wake_brief_coverage WITH (security_invoker = true) AS
SELECT e.pass_id, e.sim_run_id, e.depot_id, e.recorded_at, e.sim_clock, e.agent_version, e.source_kind,
       e.wake -> 'reasons' AS reasons, s.kind, s.name,
       (lower(COALESCE((e.answer -> 'actions')::text, ''))
          ~ ('(^|[^a-z0-9-])' || regexp_replace(lower(s.name), '([^a-z0-9])', '\\\1', 'g') || '([^a-z0-9-]|$)')) AS addressed
  FROM public.ottoq_agent_pass_evidence e
  CROSS JOIN LATERAL (
    SELECT 'charge_cut'::text AS kind, c ->> 'car' AS name
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(e.wake #> '{brief,subjects,charges_cut_by_fault,cars}') = 'array'
                                     THEN e.wake #> '{brief,subjects,charges_cut_by_fault,cars}' ELSE '[]'::jsonb END) c
     WHERE (c ->> 'new') = 'true'
    UNION ALL
    SELECT 'emergency', c ->> 'car'
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(e.wake #> '{brief,subjects,emergencies}') = 'array'
                                     THEN e.wake #> '{brief,subjects,emergencies}' ELSE '[]'::jsonb END) c
    UNION ALL
    SELECT 'charger_fault', c ->> 'post'
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(e.wake #> '{brief,subjects,chargers_faulted,chargers}') = 'array'
                                     THEN e.wake #> '{brief,subjects,chargers_faulted,chargers}' ELSE '[]'::jsonb END) c
     WHERE (c ->> 'new') = 'true'
    UNION ALL
    SELECT 'scout_finding', c ->> 'car'
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(e.wake #> '{brief,subjects,scout_findings_new,findings}') = 'array'
                                     THEN e.wake #> '{brief,subjects,scout_findings_new,findings}' ELSE '[]'::jsonb END) c
  ) s
 WHERE e.consulted AND e.answer IS NOT NULL AND s.name IS NOT NULL AND s.name <> '';

REVOKE ALL ON public.ottoq_agent_wake_brief_coverage FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.ottoq_agent_wake_brief_coverage TO service_role;

COMMENT ON VIEW public.ottoq_agent_wake_brief_coverage IS
  '0823 (G540): one row per subject an agent pass''s wake brief named as new (a car whose charge a fault cut, a car in '
  'an emergency, a newly faulted post, a car a scout newly found), with whether that pass''s directives name it '
  '(whole name, any letter case). Count subjects, and count the distinct runs behind them (0339).';

-- ── V1: who may run it, and that it writes nothing ──
DO $v1$
DECLARE v_p record; v_src text;
BEGIN
  SELECT p.proacl::text AS acl, p.provolatile, p.prosecdef,
         regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') AS src
    INTO v_p FROM pg_proc p WHERE p.oid = 'public.ottoq_agent_wake_brief(uuid,jsonb)'::regprocedure;
  IF v_p.acl IS NULL OR v_p.acl ~ '(^|[{,])=X' OR v_p.acl ~ '(^|[{,])(anon|authenticated)=' OR v_p.acl !~ 'service_role=X' THEN
    RAISE EXCEPTION '0823 V1 FAILED: the brief''s ACL is %', v_p.acl;
  END IF;
  IF v_p.provolatile <> 's' THEN RAISE EXCEPTION '0823 V1 FAILED: the brief is not STABLE'; END IF;
  IF v_p.src ~* '(INSERT\s+INTO|UPDATE\s+[a-z_\.]+\s+SET|DELETE\s+FROM|ottoq_record_event\s*\(|PERFORM\s)' THEN
    RAISE EXCEPTION '0823 V1 FAILED: the brief''s body writes or performs';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.role_table_grants g
              WHERE g.table_schema = 'public' AND g.table_name = 'ottoq_agent_wake_brief_coverage'
                AND g.grantee IN ('anon', 'authenticated', 'PUBLIC')) THEN
    RAISE EXCEPTION '0823 V1 FAILED: a browser role can read the coverage view';
  END IF;
END $v1$;

-- ── V2: the board and the gate are untouched ──
DO $v2$
BEGIN
  IF EXISTS (SELECT 1 FROM _0823_untouched u
              WHERE md5(pg_get_functiondef(u.fn::regprocedure)) IS DISTINCT FROM u.def_md5) THEN
    RAISE EXCEPTION '0823 V2 FAILED: the board or the wake gate moved';
  END IF;
END $v2$;

-- ── V3: NULL at the default, on every run here ──
DO $v3$
DECLARE v_n integer;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs r
   WHERE public.ottoq_agent_wake_brief(r.sim_run_id, '{"reasons":["heartbeat"]}'::jsonb) IS NOT NULL;
  IF v_n > 0 THEN RAISE EXCEPTION '0823 V3 FAILED: % run(s) get a brief with the dial at its default', v_n; END IF;
END $v3$;

-- ── V4: with the dial on for one probe, the newest run with agent passes gets a well-formed brief; the probe's
-- setting is rolled back to a savepoint, so nothing of it stays ──
DO $v4$
DECLARE v_run uuid; v_b jsonb; v_before bigint; v_after bigint;
BEGIN
  SELECT e.sim_run_id INTO v_run
    FROM public.ottoq_agent_pass_evidence e JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
   WHERE e.consulted ORDER BY e.pass_id DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0823 V4 SKIPPED: no run with a consulted agent pass in this database';
    RETURN;
  END IF;
  SELECT count(*) INTO v_before FROM public.ottoq_policy_params;
  BEGIN
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
    VALUES ('run', v_run, 'agent_wake_brief', 1, '0823 self-test', now());
    v_b := public.ottoq_agent_wake_brief(v_run, '{"reasons":["heartbeat"],"fingerprint":{"faulted_chargers":0}}'::jsonb);
    RAISE EXCEPTION USING ERRCODE = 'P0823', MESSAGE = COALESCE(v_b::text, 'null');
  EXCEPTION WHEN SQLSTATE 'P0823' THEN
    v_b := NULLIF(SQLERRM, 'null')::jsonb;
  END;
  SELECT count(*) INTO v_after FROM public.ottoq_policy_params;
  IF v_before <> v_after THEN RAISE EXCEPTION '0823 V4 FAILED: the probe left a setting behind'; END IF;
  IF v_b IS NULL OR jsonb_typeof(v_b) <> 'object' OR (v_b ->> 'v') <> '1' OR v_b ? 'error'
     OR jsonb_typeof(v_b -> 'subjects') <> 'object' OR (v_b -> 'reasons') <> '["heartbeat"]'::jsonb THEN
    RAISE EXCEPTION '0823 V4 FAILED: the brief of run % is %', v_run, left(COALESCE(v_b::text, 'null'), 400);
  END IF;
  RAISE NOTICE '0823 V4 PASSED on run %: % bytes, subjects %', v_run, length(v_b::text),
    (SELECT COALESCE(string_agg(k, ', '), 'none') FROM jsonb_object_keys(v_b -> 'subjects') k);
END $v4$;

-- ── V5: the body is the one the scratch PostgreSQL ran ──
DO $v5$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_agent_wake_brief(uuid,jsonb)'::regprocedure)
       IS DISTINCT FROM '7cb3ec838b0b1668662cfb42ca7c15d6' THEN
    RAISE EXCEPTION '0823 V5 FAILED: the brief''s body is not the one the tests ran';
  END IF;
END $v5$;

-- ── on at the twin depot (rule 12) ──
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('depot', '11111111-1111-1111-1111-111111111111', 'agent_wake_brief', 1,
        'Chase (delegated to Claude Code: 0823)', now());

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0823_the_agent_is_told_why_it_was_woken_and_what_it_said_last', false, false,
        'G540. public.ottoq_agent_wake_brief (new, STABLE, no write, total) and the view '
        'public.ottoq_agent_wake_brief_coverage, behind agent_wake_brief (default 0, at which the brief is NULL; 1 at '
        'the twin depot). Read only by the agent''s edge function (v32), quiesced in certification arms; the board and '
        'the wake gate are byte for byte unchanged (V2); no engine function reads the new objects and no atom hashes a '
        'model''s prompt.',
        now());

COMMIT;
