-- 0440  **What one agent did on a busy day, measured from its own evidence.**
--        The first run that kept every agent pass as evidence (0703), with deterministic per-car scouts (0704) and the
--        wake gate in shadow (0705): run 176b2912-7f91-4700-82e9-bbc42bbad0ff, busy_day, seed 305838298283560562, the
--        twin depot (rule 8), started by ottoq_operator_start_run at 15:17:28 UTC (10:17 AM CT), live playback, 755
--        ticks, ended 16:22:00 UTC (11:22 AM CT). Agent edge function v29 (deployed as v41).
--
--        Read-only. Measured 2026-10-13 between 15:19 and 18:08 UTC (10:19 AM - 1:08 PM CT; the end stamped from now()
--        on the last query). It led to db/migrations/0709 (the board's return wave), 0710 (the wake race) and 0711 (the
--        wake gate's hysteresis). Findings G421-G427.
--
-- ══ §1 THE RECORD RECONCILES (reproduce: (1)) ══
--
--   79 evidence rows, 79 orchestrator_agent decision rows (73 source 'nemotron', 6 'deterministic_fallback'), 79
--   nvidia_nemotron rows in ottoq_model_call_ledger (77 cpsat_service rows beside them). One prompt (one prompt_sha256
--   in ottoq_agent_prompts) served all 79. The outcome classes sum to the passes: echo 55, advisory 13, fallback 6,
--   no_effect 4, changed_state 1. No pass was solver-only: the gate was in shadow, so every pass consulted.
--
-- ══ §2 WHAT THE AGENT CHANGED: ONE ORDER IN 79 PASSES (reproduce: (2)) ══
--
--   Its charge order, by the check's verdict:   same_as_kernel / refused        55   (70%: the kernel's own order back)
--                                               no order                        12
--                                               worse_in_expected_future        6
--                                               not_enough_futures_won          5
--                                               wins_most_futures / accepted    1   (tick 233)
--
--   The hindsight grader (0621) on the 12 orders that differed from the kernel's:
--
--     accepted  right_take       1   p_win 0.917
--     refused   missed_win       5   mean p_win 0.367
--     refused   right_refusal    6   mean p_win 0.431
--
--   So the agent's differing orders won in hindsight 6 times in 12, and the check's win probability ranks the missed
--   wins BELOW the right refusals. G389's finding (the check cannot yet tell a better agent order from a worse one)
--   holds on a fresh run. Twelve decisions: a single reading, not a range.
--
--   The 13 advisory passes issued directives only. Directives change no engine state (0703 §2), so they are counted
--   apart from a changed state and never as one.
--
-- ══ §3 WHAT IT COST (reproduce: (3)) ══
--
--   Prompt tokens 25,768 mean, completion 1,427 mean, 1,985,250 in all; board 53,325 bytes mean. Pass time p50 59.5 s,
--   p90 98.4 s, max 107.9 s. The primary model (Nemotron 3 Ultra) answered 60 of its 91 attempts: 15 returned HTTP 503
--   and 16 timed out (one at 75,005 ms before the fallback answered in 8,633 ms). The fallback (Super 120B) answered 13
--   of 18, 5 timeouts. 6 passes got no answer from either and fell back to the kernel. The NVIDIA endpoint was the
--   least reliable part of the pass. (G424)
--
-- ══ §4 THE BOARD TOLD THE AGENT A RETURN WAVE 40 TIMES ITS SIZE (reproduce: (4)) -> 0709 ══
--
--   Pass 5 quoted "Inbound 60m is 501 vehicles". The board's inbound_60m joined every open dispatch ever written for a
--   car now driving home, with no run predicate; dispatches left open by runs that stopped with cars out are counted
--   again. At 15:19 UTC the formula gave 315; scoped to the run it gave 8, equal to the 8 cars en_route_to_depot, and
--   open dispatches from 119 distinct runs contributed. Every dispatch carries a sim_run_id (0 NULL), so the predicate
--   loses nothing in production. The first defect the new evidence record found, on the first pass it kept. (G421)
--
-- ══ §5 THE WAKE GATE READ A RECORD WRITTEN AFTER THE ONE THE CLAIM READS (reproduce: (5)) -> 0710 ══
--
--   Pass 5's decision row 15:18:23.95, its evidence row 15:18:29.53. Pass 6 was claimed in that gap: the claim
--   (ottoq_agent_chain_claim) saw pass 5's decision and let it in; the wake test read evidence, found no answered
--   consult, and reported [first_consult]. In shadow that mislabels a reason; with the gate on it is a model call the
--   gate exists to save. 0710 reads the decision row first. Verified after apply: on this run last_consult.from =
--   'decision', tick 753. (G422)
--
-- ══ §6 PASSES OVERLAP: 58 OF 79 STARTED WHILE ANOTHER WAS RUNNING (reproduce: (6)) ══
--
--   ottoq_agent_chain_claim lets a new pass in when the previous claim is older than agent_chain_inflight_timeout_s
--   (45 s here); a consulted pass took a median 59.5 s. Measured from each pass's start (recorded_at minus total_ms):
--   58 of 79 started while an earlier pass was still running. Two passes then compute on boards a minute apart, and
--   the later-finishing one's order stands, whichever board it was computed from (the study's DC-6). Not fixed by any
--   file in this set; run 57188f55 sets the lease to its catalog maximum, 120 s, run-scoped, to measure what that
--   does (§9). (G423)
--
-- ══ §7 THE SHADOW GATE WOULD HAVE SAVED ALMOST NOTHING (reproduce: (7)) -> 0711 ══
--
--   Recorded in shadow: 75 of 79 passes would have woken. Replayed in order over the recorded fingerprints (the
--   reference moving only on a woken pass the model answered, as the live gate's does): 66. The depot sat in
--   contention all day -- a mean of 53 cars in the charge line, about 0 chargers open, 46 cars past their 30-minute
--   contract wait -- and every count the gate watched moved by one on almost every beat (cars past the contract wait
--   50, 52, 51, 52, 54...; faulted chargers 2, 3, 2, 3, 4...; stranded-car findings 4 to 93 one at a time).
--
--   Replayed under 0711's rules (onset or a jump of max(5, 20%); two or more chargers; any critical finding): 25 woke
--   (9 heartbeat, 9 charger, 7 stranded-car scout, 5 contract wait, 1 emergency, 1 first consult). It keeps 6 of the
--   12 differing orders and skips the one that was taken. Given §2, that is a coin flip lost against about 1.4 million
--   tokens saved; it is why the gate stays shadow by default and a person's switch. (G425)
--
-- ══ §8 THE SCOUTS ON A BUSY DAY (reproduce: (8)) ══
--
--   contract_wait_breach 126, stranded_open_must_do 89, legacy_task_residue 4, interval_due_departure 3,
--   departed_below_target 0. Rule 9 held on this run: no car left below its target. The 89 stranded cars arrived at
--   13:00 sim -- the run's boot draw -- and were still waiting at tick 329 with charge and the readiness check open,
--   4.1 hours after arrival. That is G384's congestion on a fresh seed, larger: it is a capacity finding (rule 9:
--   "site pressure is a capacity finding, never a lever on a vehicle"), and no ordering an agent proposes can seat
--   more cars than there are free chargers. (G426, a lead beside G384)
--
-- ══ §9 RUN 57188f55 -- THE GATE ON (reproduce: (9)) ══
--
--   Started 18:08:54 UTC (1:08 PM CT): busy_day, the same seed, ottoq_operator_start_run, live playback (requested 12x,
--   the playback capped it at 8x), with agent_wake_enabled = 1 and agent_chain_inflight_timeout_s = 120, both run-scoped,
--   set by 'research_wing:claude_code'. Live playback ties a tick's sim length to the database's load, so the same seed
--   draws a different world after the first tick (0416); nothing here compares the two runs' depot KPIs. What this run
--   measures is the gate itself: how many passes consult, how many run solver-only, whether the solver-only path that
--   had never run live writes its decision and evidence correctly, and whether passes still overlap. Results: §10.
--
-- ══ §11 A DIAL'S CATALOG DEFAULT IS NOT THE ENGINE'S DEFAULT (reproduce: (11)) -> 0713, 0714 ══
--
--   Found writing 0713. public.ottoq_policy_get reads run, depot, global, then the caller's literal, and never the
--   catalog's default_value: asked for agent_chain_inflight_timeout_s with fallback 7 on run 176b2912 (no row) it
--   returns 7. So 0713 changes the literal inside ottoq_agent_chain_claim, 45 -> 130 (applied 20261013182717), and 0714
--   brings the catalog row in step -- an UPDATE, which the database connector holds for a person's confirmation (two
--   applies of a combined file timed out unexecuted at the connector, 18:23-18:26 UTC; the split 0713 applied at once).
--   Census of every ottoq_policy_get call with a literal default: 201 dials; the catalog disagrees on 4, at 7 call
--   sites, all masked today by a global or depot row. (G429)
--
-- ══ §12 0712 LIVE, AND WHAT A FIXED DRAW DOES AND DOES NOT BUY (reproduce: (12)) ══
--
--   Applied 20261013181932 (1:19 PM CT) with run 57188f55 under way: its orders 842-844 carry the old seed
--   (run id : tick : chain id), and 845 onward `world:305838298283560562:<tick>`. The stored snapshots still replay as
--   decided: the study's two flip cases, 382 and 385 (run d9d49732), give take=true, 10 and 11 of 12, under their stored
--   seeds, as recorded. Under their world seeds 385 is still taken (10 of 12) and 382 is refused -- 8 won, 4 tied, 0
--   lost, against 10 needed. So 382 sat on the edge of the draw: a fixed seed makes its verdict repeatable, not right.
--   And note the shape of that refusal: an order that lost none of 12 futures is refused because ties count as not
--   winning. Whether a tie should count is the comparator's question (G427), not the seed's.
--
-- ══ QUERIES ══

-- (1) the record reconciles
WITH r AS (SELECT '176b2912-7f91-4700-82e9-bbc42bbad0ff'::uuid AS id)
SELECT (SELECT count(*) FROM public.ottoq_agent_pass_evidence WHERE sim_run_id = (SELECT id FROM r)) AS evidence_rows,
       (SELECT count(*) FROM public.ottoq_decisions
         WHERE sim_run_id = (SELECT id FROM r) AND resolved_action_context = 'orchestrator_agent') AS decision_rows,
       (SELECT jsonb_object_agg(provider, n) FROM (SELECT provider, count(*) n FROM public.ottoq_model_call_ledger
                                                    WHERE sim_run_id = (SELECT id FROM r) GROUP BY 1) x) AS ledger,
       (SELECT jsonb_object_agg(outcome_class, n) FROM (SELECT outcome_class, count(*) n
                                                         FROM public.ottoq_agent_pass_evidence
                                                        WHERE sim_run_id = (SELECT id FROM r) GROUP BY 1) x) AS classes;

-- (2) the orders and their hindsight grades
SELECT coalesce(levers ->> 'order_reason', '(none)') AS order_reason, levers ->> 'order_status' AS status, count(*)
  FROM public.ottoq_agent_pass_evidence WHERE sim_run_id = '176b2912-7f91-4700-82e9-bbc42bbad0ff' GROUP BY 1, 2;
SELECT status, taken, decision, outcome, count(*), round(avg(p_win), 3) AS p_win
  FROM public.ottoq_charge_order_grades WHERE sim_run_id = '176b2912-7f91-4700-82e9-bbc42bbad0ff'
 GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4;

-- (3) cost: tokens, time, and every attempt the model call made
SELECT round(avg((usage ->> 'prompt_tokens')::numeric)) AS prompt_tok, round(avg((usage ->> 'completion_tokens')::numeric)) AS completion_tok,
       sum((usage ->> 'total_tokens')::numeric) AS total_tok, round(avg(board_bytes)) AS board_bytes,
       percentile_cont(ARRAY[0.5, 0.9, 1.0]) WITHIN GROUP (ORDER BY total_ms) FILTER (WHERE consulted) AS total_ms
  FROM public.ottoq_agent_pass_evidence WHERE sim_run_id = '176b2912-7f91-4700-82e9-bbc42bbad0ff';
SELECT a ->> 'model' AS model, a ->> 'status' AS status, count(*)
  FROM public.ottoq_agent_pass_evidence e, jsonb_array_elements(e.attempts) a
 WHERE e.sim_run_id = '176b2912-7f91-4700-82e9-bbc42bbad0ff' AND jsonb_typeof(e.attempts) = 'array'
 GROUP BY 1, 2 ORDER BY 1, 2;

-- (4) the return wave, unscoped and scoped (meaningful only while the run is live; the 0709 board carries the scoped one)
SELECT count(*) FILTER (WHERE true) AS every_run, count(*) FILTER (WHERE d.sim_run_id = r.sim_run_id) AS this_run
  FROM public.ottoq_sim_runs r
  JOIN public.vehicles v ON v.home_depot_id = r.depot_id AND v.current_state::text = 'en_route_to_depot'
  JOIN public.ottoq_vehicle_dispatches d ON d.vehicle_id = v.id
 WHERE r.sim_run_id = '176b2912-7f91-4700-82e9-bbc42bbad0ff'
   AND d.actual_return_at IS NULL AND d.scheduled_return_at <= r.sim_clock_current + interval '60 minutes';

-- (5) the race: decision and evidence times for the agent's passes
SELECT d.tick_seq, d.created_at AS decision_at, e.recorded_at AS evidence_at, e.wake -> 'reasons' AS reasons
  FROM public.ottoq_decisions d
  JOIN public.ottoq_agent_pass_evidence e ON e.chain_id = d.context_frame ->> 'agent_solver_chain_id'
 WHERE d.sim_run_id = '176b2912-7f91-4700-82e9-bbc42bbad0ff' AND d.resolved_action_context = 'orchestrator_agent'
 ORDER BY d.tick_seq LIMIT 8;

-- (6) overlap: passes that started while another was still running
WITH e AS (SELECT pass_id, recorded_at - make_interval(secs => total_ms / 1000.0) AS t0, recorded_at AS t1
             FROM public.ottoq_agent_pass_evidence WHERE sim_run_id = '176b2912-7f91-4700-82e9-bbc42bbad0ff')
SELECT count(*) FILTER (WHERE EXISTS (SELECT 1 FROM e b WHERE b.pass_id <> a.pass_id AND b.t0 < a.t0 AND b.t1 > a.t0))
         AS overlapped, count(*) AS passes
  FROM e a;

-- (7) the gate replayed over the recorded fingerprints under 0711's rules
WITH RECURSIVE p AS (
  SELECT row_number() OVER (ORDER BY pass_id) AS i, e.sim_clock AS c, e.wake -> 'fingerprint' AS fp, e.outcome_class AS o,
         e.levers ->> 'order_reason' AS ord,
         (SELECT count(*) FROM public.ottoq_vehicle_scout_findings f WHERE f.sim_run_id = e.sim_run_id
             AND f.scout IN ('departed_below_target', 'legacy_task_residue') AND f.recorded_at <= e.recorded_at) AS crit,
         (SELECT count(*) FROM public.ottoq_vehicle_scout_findings f WHERE f.sim_run_id = e.sim_run_id
             AND f.scout = 'stranded_open_must_do' AND f.recorded_at <= e.recorded_at) AS strand
    FROM public.ottoq_agent_pass_evidence e WHERE e.sim_run_id = '176b2912-7f91-4700-82e9-bbc42bbad0ff'),
w (i, ref_fp, ref_c, ref_crit, ref_strand, woke, reasons, o, ord) AS (
  SELECT p.i, p.fp, p.c, p.crit, p.strand, true, ARRAY['first_consult'], p.o, p.ord FROM p WHERE p.i = 1
  UNION ALL
  SELECT p.i,
         CASE WHEN d.wk AND p.o NOT IN ('fallback', 'failed') THEN p.fp ELSE w.ref_fp END,
         CASE WHEN d.wk AND p.o NOT IN ('fallback', 'failed') THEN p.c ELSE w.ref_c END,
         CASE WHEN d.wk AND p.o NOT IN ('fallback', 'failed') THEN p.crit ELSE w.ref_crit END,
         CASE WHEN d.wk AND p.o NOT IN ('fallback', 'failed') THEN p.strand ELSE w.ref_strand END,
         d.wk, d.rs, p.o, p.ord
    FROM w JOIN p ON p.i = w.i + 1
    CROSS JOIN LATERAL (SELECT (p.fp ->> 'faulted_chargers')::int AS f, (w.ref_fp ->> 'faulted_chargers')::int AS f0,
                               (p.fp ->> 'over_contract_wait')::int AS ow, (w.ref_fp ->> 'over_contract_wait')::int AS ow0,
                               (p.fp ->> 'emergencies')::int AS em, (w.ref_fp ->> 'emergencies')::int AS em0) n
    CROSS JOIN LATERAL (SELECT array_remove(ARRAY[
        CASE WHEN extract(epoch FROM p.c - w.ref_c) / 60 >= 30 THEN 'heartbeat' END,
        CASE WHEN (p.fp ->> 'line_exceeds_open_chargers') IS DISTINCT FROM (w.ref_fp ->> 'line_exceeds_open_chargers') THEN 'contention' END,
        CASE WHEN n.em > n.em0 THEN 'emergency' END,
        CASE WHEN (p.fp ->> 'dr_active') IS DISTINCT FROM (w.ref_fp ->> 'dr_active') THEN 'dr' END,
        CASE WHEN abs(n.f - n.f0) >= 2 THEN 'charger' END,
        CASE WHEN (n.ow0 = 0 AND n.ow > 0) OR n.ow >= n.ow0 + greatest(5, ceil(0.2 * n.ow0)) THEN 'contract_wait' END,
        CASE WHEN p.crit > w.ref_crit THEN 'scout_critical' END,
        CASE WHEN (w.ref_strand = 0 AND p.strand > 0) OR p.strand >= w.ref_strand + greatest(5, ceil(0.2 * w.ref_strand)) THEN 'scout_finding' END
      ], NULL) AS rs) r
    CROSS JOIN LATERAL (SELECT cardinality(r.rs) > 0 AS wk, r.rs) d)
SELECT count(*) AS passes, count(*) FILTER (WHERE woke) AS woke,
       count(*) FILTER (WHERE woke AND ord IN ('not_enough_futures_won', 'worse_in_expected_future', 'wins_most_futures')) AS kept_differing
  FROM w;

-- (8) the scouts
SELECT scout, severity, count(*), count(DISTINCT vehicle_id) AS cars
  FROM public.ottoq_vehicle_scout_findings WHERE sim_run_id = '176b2912-7f91-4700-82e9-bbc42bbad0ff'
 GROUP BY 1, 2 ORDER BY 3 DESC;

-- (9) the gate-on run
SELECT outcome_class, consulted, count(*), round(avg(total_ms)) AS ms,
       count(*) FILTER (WHERE NOT decision_written) AS decision_missing
  FROM public.ottoq_agent_pass_evidence WHERE sim_run_id = '57188f55-4503-4c5c-82c8-b42000f73ba2'
 GROUP BY 1, 2 ORDER BY 3 DESC;

-- (11) every dial read with a literal default, against its catalog row (comments stripped)
WITH src AS (
  SELECT p.oid::regprocedure::text AS fn, regexp_replace(pg_get_functiondef(p.oid), '--[^\n]*', '', 'g') AS d
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prokind = 'f' AND pg_get_functiondef(p.oid) LIKE '%ottoq_policy_get%'),
calls AS (
  SELECT s.fn, m[1] AS key, m[2]::numeric AS lit
    FROM src s, regexp_matches(s.d, 'ottoq_policy_get\s*\([^,()]+(?:\([^()]*\))?[^,()]*,\s*''([a-z0-9_]+)''\s*,\s*\(?\s*(-?[0-9.]+)', 'g') m)
SELECT c.key, cat.default_value AS catalog, c.lit, c.fn,
       (SELECT jsonb_object_agg(pp.scope_type, pp.param_value) FROM public.ottoq_policy_params pp
         WHERE pp.param_key = c.key AND pp.scope_type IN ('global', 'depot')) AS masked_by
  FROM calls c LEFT JOIN public.ottoq_policy_param_catalog cat ON cat.param_key = c.key
 WHERE cat.default_value IS DISTINCT FROM c.lit
 ORDER BY 1, 4;

-- (12) the study's two flip cases under their stored seeds and under the world seed
WITH s AS (SELECT s.*, r.random_seed, o.recorded_tick, o.status AS recorded_status
             FROM public.ottoq_charge_order_snapshots s JOIN public.ottoq_agent_charge_orders o USING (order_id)
             JOIN public.ottoq_sim_runs r ON r.sim_run_id = s.sim_run_id
            WHERE s.order_id IN (382, 385))
SELECT order_id, recorded_status,
       public.ottoq_charge_order_verdict_v2(public.ottoq_charge_line_rollout(state, agent_order, futures, seed), win_frac)
         - 'per' - 'agent' - 'kernel' - 'first' AS under_stored,
       public.ottoq_charge_order_verdict_v2(public.ottoq_charge_line_rollout(state, agent_order, futures,
         'world:' || COALESCE(random_seed::text, sim_run_id::text) || ':' || recorded_tick), win_frac)
         - 'per' - 'agent' - 'kernel' - 'first' AS under_world
  FROM s ORDER BY order_id;
