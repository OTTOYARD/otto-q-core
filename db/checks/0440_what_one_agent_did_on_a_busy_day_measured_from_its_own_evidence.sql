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
-- ══ §10 THE GATE ON, MEASURED (reproduce: (10)) ══
--
--   57188f55 ran 789 ticks to the governor's 540 sim-minute stop at 19:12:00 UTC (2:12 PM CT). 0711 was live from its
--   start; 0712 from 18:19:32 UTC and 0713 from 18:27:17 UTC, mid-run (both read in §11-§12).
--
--                                   176b2912 (shadow, lease 45 s)    57188f55 (gate on, lease 120 s)
--     agent passes                  79                               287 at the stop (288 with the one in flight)
--     consulted the model           79                               20 at the stop (heartbeat 11, scout 5, charger 2, contract 2,
--                                                                     first 1); 21 with the heartbeat in flight
--     solver-only                   0                                267, mean 2,055 ms
--     passes overlapping another    58                               0
--     model tokens                  1,985,250                        549,077 at the stop (-72%); 576,986 with the pass in
--                                                                     flight (-71%)
--     fallback passes               6                                0
--     decision rows = passes        79 = 79                          287 = 287; Nemotron ledger rows = consults 20 = 20
--     CP-SAT (forward_lex)          0 enacted, 106 refused, 11 sup.  22 enacted, 461 refused, 574 superseded
--
--   CORRECTED in the commit of 19:39:26 UTC (2:39 PM CT), read back from the evidence: one more consult, a heartbeat (pass 371, 58.3 s,
--   27,909 tokens, outcome advisory), was in flight when the governor stopped the run at 19:12:00 and landed 41 s
--   later. The figures above were read before it landed. Counting it: 21 of 288 passes consulted, tokens -71%.
--   Every later figure that quotes 72% is the at-the-stop figure.
--
--   The solver-only path, which had never run live, wrote its decision and evidence on every one of 267 passes. The
--   agent's 20 consults: echo 14, advisory 5, no_effect 1; it took no order. Its differing orders were graded 6 times,
--   all refused by the check, 5 of them missed_win in hindsight (G427 again: on the two runs, 18 graded differing
--   orders, 11 won in hindsight, the check took 1).
--
--   CP-SAT's 22 enactments against 0 are the unexpected result. Behind a 60-second model call the solver ran about
--   once a minute on a board a minute old; behind the gate it runs every pass, every 2-3 ticks, on a board two seconds
--   old. That is a mechanism, not yet a measurement: live playback draws a different world after the first tick (0416),
--   and this is one pair. (G432, a lead.)
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
-- ══ §13 CARS LEAVE WITH MAINTENANCE OR CALIBRATION DUE (reproduce: (13)) -> 0715, pending ══
--
--   The scout interval_due_departure (a departure after a service_interval_due recall with no PM or calibration done
--   since): 3 on 176b2912 (Tesla-AV-070, Waymo-AV-021, Zoox-AV-100), 5 on 57188f55 by tick 213. Read by hand for
--   Tesla-AV-070 on 57188f55: its visit carried no PM and no calibration atom at all, and it left at 14:40:24 sim. The
--   planner adds those atoms only when the twin observer draws them (0.30 / 0.24); 0448's upgrade keys on a trigger no
--   live recall emits; the departure test reads atoms, never wear. G218 / G181, now measured per run.
--   What enforcing it would do on busy_day, measured: pm_interval_km median 78 (the need profile says 6,500-9,500),
--   calib_interval_h median 4.85; at 4:54 PM sim on 57188f55, 71 of 116 cars had one due (67 PM, 18 calibration);
--   176b2912's two service bays finished 14 PM and 4 calibrations in 9 sim-hours. 0715 is written and tested, and left
--   for Chase with the scenario's intervals. (G430)
--
-- ══ §14 0562 LIVE: NO CHARGER HELD FOR A CAR STILL OUT (reproduce: (14)) -> G293 part 1 ══
--
--   Run 02ac27b3 (busy_day, seed 305838298283560562, the twin depot, wake gate on, lease 120 s, live playback): started
--   by ottoq_operator_start_run at 19:19:24 UTC (2:19 PM CT), 0562 applied at 19:14:24, so the run ran under it from
--   its first tick; the governor stopped it at 20:26:00 UTC (3:26 PM CT), sim 22:07. Measured after the stop, the last
--   query finishing by 20:28:11 UTC. prearrival_charge_yields_to_solver = 1 on all three runs (the agentic arm sets it),
--   and all three ran to the governor's ceiling (176b2912 to sim 22:24, 57188f55 to 22:08).
--
--   Chargers (dcfc, l2) reserved while their car was deployed or driving back, from stall.state_changed events:
--
--                                        176b2912 (before)   57188f55 (before)   02ac27b3 (0562)
--     reservations for a car still out   39                  39                  0
--       of which in the first 3 sim h    21                  24                  0
--     charger-minutes held empty         208.4               151.6               0
--     longest single hold, min           50.7                16.0                -
--
--   All 219 reservations on 02ac27b3 went to a car at the gate (145) or staged waiting for service (74).
--
--   Charge seatings by source (stall_assignment, enacted, dcfc or l2), with how many went in ahead of a car refused in
--   the same tick:
--                                        176b2912            57188f55            02ac27b3
--     reservation_honoured               33 (25 ahead)       33 (31 ahead)        0
--     reservation_reopt                   6                   6                   0
--     greedy_constrained                 16 (11 ahead)       29 (22 ahead)       21 (16 ahead)
--     forward_lex (CP-SAT)                0                  22                  27
--     kernel                             166 (1)             131 (0)             171 (2)
--     total                              221 (37 ahead)      221 (53 ahead)      219 (18 ahead)
--
--   The mechanism is gone: no charger stood empty for a car not yet at the depot, and no car took a pre-held charger
--   ahead of the line. What remains of G293 is its part 2 (greedy_constrained: a waiting car's plan booked a charger
--   window first come, 16 of its 21 seatings ahead of a refused car), a research-wing question (0562 §4). CP-SAT's
--   seatings with the wake gate on, 22 and now 27 against 0 in shadow, are a second reading of G432's lead, still not a
--   paired measurement.
--
--   What this run does NOT show is an outcome. Over the whole run the scouts read: contract-wait breaches 137 findings
--   on 107 cars, against 126 on 101 and 129 on 98; cars stranded with open must-do work at the stop 79, against 89 and
--   75; departures with an interval due 1, against 3 and 6; departures below target 0 on all three. All of it is inside
--   the live twin's noise floor (0416): live playback draws a different world after the first tick. Returning cars now
--   queue in the line instead of jumping it, which is rule 9's "better ordering of who is served next"; a deterministic
--   pair is what would measure what that costs or saves.
--
-- ══ §15 AGENT v30 LIVE: NO DIRECTIVE SETS A CHARGE TARGET UNDER 100% (reproduce: (15)) -> G434 ══
--
--   Deployed as v42 at 20:06:39 UTC (3:06 PM CT), mid-run: the last v29 pass on 02ac27b3 landed at 20:06:39, the first
--   v30 pass (solver-only) at 20:06:50, and the first v30 consult at 20:07:53. Every v30 consult carries prompt_sha256
--   7ae8ac4f348ffb45f02954325ba6a83a649a9166d77b943cf33880f5cdfd0974, the sha256 of the repo's SYSTEM prompt plus the
--   charge-line section computed locally before it landed: the deployed prompt is the committed one byte for byte.
--
--                                        v29 (to 20:06:39)   v30 (from 20:06:50)
--     passes                             224                 96
--     consults                           18                  6
--     directives issued                  64 of 68            25 of 25
--     directives naming any percentage   10                  0
--     directives naming a target < 100%  0                   0
--     refused                            3 (no_change dials) 0
--
--   On this run neither version named a charge target, so v30's lint had nothing to refuse; its work is in the 114
--   distinct directive texts on record from earlier runs (G434), which tests/agent_rule_nine.test.mjs carries. One v30
--   directive names a rule-9 violation itself (Zoox-AV-088 left with maintenance owed). v29's 10 percentages are state
--   ("contract wait breach (33 min vs 30 min limit) at kernel_pos 6, SoC 98%"), which the lint lets pass by design.
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

-- (13) the twin depot's cars with an interval due, by the recall's own test, on a run
WITH r AS (SELECT '57188f55-4503-4c5c-82c8-b42000f73ba2'::uuid AS id),
c AS (
  SELECT v.id,
         COALESCE((v.config ->> 'pm_interval_km')::numeric, public.ottoq_policy_get((SELECT id FROM r), 'pm_interval_km', 8000)) AS pm_km,
         COALESCE((v.config ->> 'calib_interval_h')::numeric, public.ottoq_policy_get((SELECT id FROM r), 'calib_interval_h', 250)) AS cal_h,
         w.drive_km_total - w.km_at_last_pm AS km_since, w.drive_hours_total - w.hours_at_last_calibration AS h_since
    FROM public.vehicles v JOIN public.ottoq_vehicle_wear w ON w.vehicle_id = v.id AND w.sim_run_id = (SELECT id FROM r)
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111')
SELECT count(*) AS cars, count(*) FILTER (WHERE km_since >= pm_km) AS pm_due, count(*) FILTER (WHERE h_since >= cal_h) AS calib_due,
       count(*) FILTER (WHERE km_since >= pm_km OR h_since >= cal_h) AS any_due,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY pm_km) AS median_pm_km
  FROM c;

-- (10) the two runs, side by side
WITH r(id) AS (VALUES ('176b2912-7f91-4700-82e9-bbc42bbad0ff'::uuid), ('57188f55-4503-4c5c-82c8-b42000f73ba2'::uuid)),
e AS (SELECT *, recorded_at - make_interval(secs => total_ms / 1000.0) AS t0
        FROM public.ottoq_agent_pass_evidence WHERE sim_run_id IN (SELECT id FROM r))
SELECT r.id,
  (SELECT count(*) FROM e WHERE e.sim_run_id = r.id) AS passes,
  (SELECT count(*) FROM e WHERE e.sim_run_id = r.id AND consulted) AS consulted,
  (SELECT count(*) FROM e a WHERE a.sim_run_id = r.id AND EXISTS (SELECT 1 FROM e b WHERE b.sim_run_id = r.id
      AND b.pass_id <> a.pass_id AND b.t0 < a.t0 AND b.recorded_at > a.t0)) AS overlapped,
  (SELECT sum((usage ->> 'total_tokens')::numeric) FROM e WHERE e.sim_run_id = r.id) AS tokens,
  (SELECT count(*) FROM public.ottoq_decisions d WHERE d.sim_run_id = r.id AND d.resolved_action_context = 'orchestrator_agent') AS decisions,
  (SELECT count(*) FROM public.ottoq_model_call_ledger l WHERE l.sim_run_id = r.id AND l.provider = 'nvidia_nemotron') AS nemotron,
  (SELECT jsonb_object_agg(status, n) FROM (SELECT status, count(*) n FROM public.ottoq_external_proposals p
      WHERE p.sim_run_id = r.id AND p.source = 'forward_lex' GROUP BY 1) x) AS cpsat
FROM r;

-- (14) 0562: chargers reserved for a car still out, and charge seatings by source (one run at a time; MATERIALIZED, or it
-- times out)
WITH ch AS (SELECT id, stall_type::text stype FROM public.stalls WHERE depot_id = '11111111-1111-1111-1111-111111111111'
              AND stall_type::text IN ('dcfc', 'l2')),
ev AS MATERIALIZED (SELECT e.entity_id, e.event_seq, e.sim_clock_at, e.payload -> 'diff' d FROM public.ottoq_events e
                      JOIN ch ON ch.id = e.entity_id
                     WHERE e.sim_run_id = '02ac27b3-fe50-42b1-bf1b-82ac2a50445f' AND e.event_type = 'stall.state_changed'),
res AS MATERIALIZED (SELECT entity_id stall_id, (d -> 'reserved_by' ->> 'to')::uuid vehicle_id, sim_clock_at at, event_seq seq
                       FROM ev WHERE jsonb_typeof(d -> 'reserved_by' -> 'to') = 'string'),
vs AS MATERIALIZED (SELECT e.entity_id, e.event_seq, e.payload -> 'diff' -> 'current_state' ->> 'to' st FROM public.ottoq_events e
                     WHERE e.sim_run_id = '02ac27b3-fe50-42b1-bf1b-82ac2a50445f' AND e.event_type = 'vehicle.state_changed'
                       AND e.entity_id IN (SELECT vehicle_id FROM res) AND e.payload -> 'diff' ? 'current_state'),
enr AS (SELECT r.*, (SELECT st FROM vs WHERE vs.entity_id = r.vehicle_id AND vs.event_seq <= r.seq
                      ORDER BY vs.event_seq DESC LIMIT 1) veh_state_then,
               (SELECT min(sim_clock_at) FROM ev WHERE ev.entity_id = r.stall_id AND ev.event_seq > r.seq
                   AND (ev.d ? 'current_vehicle_id' OR ev.d ? 'reserved_by')) ended_at FROM res r)
SELECT veh_state_then, count(*) n, round((sum(extract(epoch FROM (COALESCE(ended_at, at) - at))) / 60)::numeric, 1) min_held
  FROM enr GROUP BY 1 ORDER BY 1;

WITH seat AS MATERIALIZED (
  SELECT d.tick_seq, d.decision_seq, COALESCE(d.enacted_action ->> 'source', 'kernel') AS source
    FROM public.ottoq_decisions d JOIN public.stalls st ON st.id = (d.enacted_action ->> 'stall_id')::uuid
   WHERE d.sim_run_id = '02ac27b3-fe50-42b1-bf1b-82ac2a50445f' AND d.action_context = 'stall_assignment'
     AND d.outcome_status = 'enacted' AND st.stall_type::text IN ('dcfc', 'l2')),
ref AS MATERIALIZED (SELECT a.tick_seq, a.decision_seq FROM public.ottoq_decisions a
   WHERE a.sim_run_id = '02ac27b3-fe50-42b1-bf1b-82ac2a50445f' AND a.action_context = 'stall_assignment'
     AND a.outcome_status = 'noop_no_candidate')
SELECT s.source, count(*) seatings,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM ref r WHERE r.tick_seq = s.tick_seq AND r.decision_seq < s.decision_seq)) ahead
  FROM seat s GROUP BY 1 ORDER BY 2 DESC;

-- (15) v29 against v30 on 02ac27b3: passes, consults, the prompt hash, and the directives
WITH d AS (SELECT e.agent_version, x ->> 'text' t FROM public.ottoq_agent_pass_evidence e,
             jsonb_array_elements(jsonb_path_query_array(e.answer, '$.actions[*] ? (@.type == "directive")')) x
            WHERE e.sim_run_id = '02ac27b3-fe50-42b1-bf1b-82ac2a50445f' AND e.consulted)
SELECT e.agent_version, count(*) AS passes, count(*) FILTER (WHERE e.consulted) AS consults,
       array_agg(DISTINCT e.prompt_sha256) FILTER (WHERE e.consulted) AS prompts,
       sum(COALESCE((e.levers ->> 'directives_issued')::int, 0)) AS directives_issued,
       (SELECT count(*) FROM d WHERE d.agent_version = e.agent_version AND d.t ~ '\d+\s*%') AS naming_a_percentage
  FROM public.ottoq_agent_pass_evidence e WHERE e.sim_run_id = '02ac27b3-fe50-42b1-bf1b-82ac2a50445f'
 GROUP BY 1 ORDER BY 1;
