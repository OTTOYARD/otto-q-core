-- 0426  **0642 live, the first run under it stopped at 91 sim-minutes, and a blind spot that turned out to be luck.**
--        0642 (the kernel serves a car that has waited 90 minutes first and orders the rest by minutes of charge) went
--        onto the engine at 7:32 AM CT on 2026-10-09, stored byte for byte, and agent v28 followed at 7:38. The run
--        started on it, 72b09010 (busy_day, b2efcc07's seed and start clock, live at 3x), was stopped from the twin app
--        at 8:00 AM CT, at sim 14:31, before any car had waited 90 minutes: the floor never engaged, and the minutes
--        order had 91 minutes to show anything. And the build filed as G385 was rehearsed before it was written: drawing
--        which arriving cars will be due does not make the check's decisions right more often, so it was not built.
--
--        Written 2026-10-09, 8:05-8:20 AM CT. Read-only. Twin depot 11111111-…. One run each: single readings, not ranges.
--
-- ══ §1 THE APPLY AND THE RUN (reproduce: (1)) ══
--
--   0642: version 20261009123213, the file as committed in 4092778 minus its final newline, md5 0b7f95d2, 53,407
--   characters and 55,364 bytes on both sides; P0-P1 and V1-V3 passed inside the transaction (lineage at 12:32:13
--   UTC). ottoq-orchestrator-agent v40 (agent v28) at 12:38 UTC, all five files byte-identical on read-back
--   (edge-functions manifest footnote 9). 72b09010 started at 12:32:22 UTC, nine seconds after the commit, so the
--   recert runner waited for it.
--
--   The stop: otto-twin-control's scenarios/stop, from the twin app on a phone, at 13:00:07 UTC (an HTTP 500, nothing
--   in the database's error log) and again at 13:00:14 (ottoq_sim_stop_and_reset, reason operator_stop, 36 sessions
--   ended, 116 vehicles reset). Nothing in the engine stopped it. 352 ticks, 91.5 sim-minutes, 38 orders: 28 the
--   kernel's own, 1 taken, 9 refused for cause. Every one of the 4,028 seat decisions carries 0642's minutes key; none
--   carries the floor key, because no car waited 90 minutes in the 91.
--
-- ══ §2 THE SAME 91 MINUTES IN THREE RUNS OF ONE SEED (reproduce: (2)) ══
--
--   The longest wait each car waiting for a charger reached by sim 14:31, from the order snapshots (the cursor's own
--   wait, read every pass):
--
--                     battery       cars   mean longest wait   longest   over 30   over 60
--     b2efcc07        under 45%      16          49.1              89         9         7     before 0642
--     64251eb8        under 45%      16          57.5              89        10         9     before 0642
--     72b09010        under 45%      16          45.7              86        10         6     0642
--     b2efcc07        45-80%         34          22.9              70        10         4
--     64251eb8        45-80%         30          23.9              70         8         3
--     72b09010        45-80%         34          23.7              68         5         3
--     b2efcc07        80% and up     27          34.7              89        14         5
--     64251eb8        80% and up     28          30.6              80        12         4
--     72b09010        80% and up     29          35.1              86        13         7
--
--   The direction 0642's replay predicted (low batteries sooner, top-offs a little later), and a size inside the
--   noise floor: the two runs before 0642 differ by 8.4 minutes on the first row. The floor, the half of 0642 that
--   bounds the tail, did not get to act. A full run is needed to read it.
--
-- ══ §3 G385, REHEARSED AND NOT BUILT (reproduce: (3)) ══
--
--   A temporary copy of the check's simulator (pg_temp, never stored) drew each arriving car's urgency at the
--   depot's own rate by hour of arrival (from 31,327 visits in 161 other runs: about 0.30 by day, none overnight; due
--   45 minutes after arrival), keyed by the order's seed, the future and the car, so both sides of a future meet the
--   same draw. The 18 scored decisions of b2efcc07 and 64251eb8 were replayed with and without it:
--
--                             orders   without the draw          with the draw
--     right refusals             9     9 refused                 9 refused
--     wrong take                 1     taken (10 of 12, flow)    refused (same as the kernel)
--     missed wins                8     none taken                none taken; futures won fell on 5 of 8 (to 1 of 12)
--     decisions right           18     9                         10
--
--   The expected futures held 9 to 18 due cars where they held 0 to 3, and the agent's orders looked worse in them, not
--   better. So the due cars do explain why hindsight disagreed with the forecast (0425 §3), but which cars turn out due
--   is not knowable at the order, and a draw at the depot's rate does not recover those wins: on this evidence they
--   were the world's luck, not the check's blindness. One more thing the rehearsal shows: a single representative draw
--   in the expected future can make two orders seat the same cars in the window (order 608), and that gate then reads
--   same_as_kernel. A draw belongs in the sampled futures, if anywhere. Filed against G385.
--
-- ══ §4 G386 WITHDRAWN: THE L2 MISS IN 0425 §5 WAS THE WAY IT WAS COUNTED (reproduce: (4)) ══
--
--   0425 §5 summed the grades' per-order charge forecasts, and two things in that sum are not the clock. A charge is
--   counted once for every order whose window held it (64251eb8's 109 L2 counts are about 30 charges; its 230 fast-charge
--   counts about 25), and a charge is kept only when it finishes inside the order's 90-minute window, which on L2 keeps
--   the short ones. Read per charge, out of sample:
--
--     the clock's own trial, fitted through 64251eb8's start and scored on the 52 L2 and 35 fast charges completed after
--     it (ottoq_charge_clock_trial, with and without the air level):
--                     mean abs log error   mean log error
--       L2, with air        0.107             -0.009
--       L2, without         0.152             +0.087
--       fast, with air      0.137             +0.005
--       fast, without       0.144             +0.051
--     the self-review's audit (fit 6, per charge): L2 -4.8% on 64251eb8 (30 charges) and +0.8% on 72b09010 (24).
--
--   So the air level helps L2 out of sample rather than hurting it, and the clock is within a few percent on both kinds.
--   0425 §5's L2 row (0.892, 54.1% inside) and its fast row are per-order sums and must not be quoted as the clock's
--   error; G386 is withdrawn. The lesson is 0339's again: before pooling, count the distinct things being judged.
--
-- ══ §5 NEXT ══
--
--   A full run under 0642 to read the floor; the recert sweep after 0642 (forces_recert TRUE) is running and its verdicts
--   are read when it ends.

-- (1) the apply, as stored, and the stop
SELECT version, name, md5(statements[1]) AS stmt_md5, length(statements[1]) AS chars, octet_length(statements[1]) AS bytes
  FROM supabase_migrations.schema_migrations WHERE version = '20261009123213';
SELECT r.status, r.started_at, r.ended_at, r.tick_count, r.sim_clock_current, r.failure_reason,
       (SELECT e.payload FROM public.ottoq_events e WHERE e.event_type = 'twin.sim_stopped_and_reset'
         AND e.occurred_at BETWEEN r.ended_at - interval '1 second' AND r.ended_at + interval '1 second' LIMIT 1) AS stop_event,
       (SELECT jsonb_object_agg(k, n) FROM (SELECT o.status || ':' || COALESCE(o.projection ->> 'reason', '?') AS k, count(*) AS n
           FROM public.ottoq_agent_charge_orders o WHERE o.sim_run_id = r.sim_run_id GROUP BY 1) z) AS orders,
       (SELECT jsonb_build_object('n', count(*), 'floor', count(*) FILTER (WHERE d.context_frame #>> '{charge_order,floor_key}' IS NOT NULL),
                                  'minutes', count(*) FILTER (WHERE d.context_frame #>> '{charge_order,minutes_key}' IS NOT NULL))
          FROM public.ottoq_decisions d WHERE d.sim_run_id = r.sim_run_id AND d.context_frame ? 'charge_order') AS seat_keys
  FROM public.ottoq_sim_runs r WHERE r.sim_run_id = '72b09010-d277-45ee-bbe9-3e2fc98c5818';

-- (2) the same 91 minutes in three runs of one seed
WITH c AS (
  SELECT s.sim_run_id, s.sim_clock, x.value ->> 'id' AS id, (x.value ->> 'soc')::numeric AS soc, (x.value ->> 'w')::numeric AS w
    FROM public.ottoq_charge_order_snapshots s CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'cars', '[]')) x
   WHERE s.sim_run_id IN ('64251eb8-e5fb-4f7d-af25-9f4ddf5d3768', 'b2efcc07-e47e-40e2-9411-907e913a3976', '72b09010-d277-45ee-bbe9-3e2fc98c5818')
     AND s.sim_clock <= '2026-10-08 14:31:27+00'
), per AS (
  SELECT sim_run_id, id, min(soc) AS soc, max(w) AS longest_wait_seen FROM c GROUP BY 1, 2
)
SELECT left(sim_run_id::text, 8) AS run,
       CASE WHEN soc < 45 THEN '1 under 45' WHEN soc < 80 THEN '2 45-80' ELSE '3 80 and over' END AS battery,
       count(*) AS cars, round(avg(longest_wait_seen), 1) AS mean_longest_wait, round(max(longest_wait_seen), 0) AS max_wait,
       count(*) FILTER (WHERE longest_wait_seen > 30) AS over_30, count(*) FILTER (WHERE longest_wait_seen > 60) AS over_60
  FROM per GROUP BY 1, 2 ORDER BY 2, 1;

-- (3) G385's rehearsal: a temporary simulator that draws each arriving car's urgency, and the 18 scored decisions
--     (run in one session; the batches of 3-4 orders each fit the connector's 60 seconds)
--   DO block: pg_get_functiondef(public.ottoq_charge_line_schedule) renamed pg_temp.sched_u, five anchored inserts:
--     DECLARE   u_on (the state carries an 'urgency' object), u_p (24 shares by hour), u_off (45), u_h0 (the order's hour)
--     BEGIN     read p, off and h0 from the state's 'urgency'
--     inbound   an arriving car (src forecast or returning) with no due time is due at its arrival + off when
--               ottoq_hash_uniform(seed : scenario : car : 'urgency') < u_p[hour of its arrival]
--     returns   the same for a return visit (key ':urgency:r'), except in a hindsight replay
--     result    adds urgency_drawn
--   pg_temp.roll: ottoq_charge_line_rollout's loop over pg_temp.sched_u; the verdict is ottoq_charge_order_verdict_v2(roll, 0.8)
--   the shares: per UTC hour of arrival, (immediate visits + 20 x the overall share) / (visits + 20), over every visit at
--   the twin depot outside b2efcc07, 64251eb8 and 72b09010; h0 = the order's sim hour + minutes / 60
SELECT extract(hour FROM vn.arrived_at)::int AS utc_hour, count(*) AS visits,
       count(*) FILTER (WHERE vn.urgency = 'immediate_dispatch') AS immediate,
       round(count(*) FILTER (WHERE vn.urgency = 'immediate_dispatch')::numeric / count(*), 3) AS share
  FROM public.ottoq_visit_needs vn
 WHERE vn.depot_id = '11111111-1111-1111-1111-111111111111' AND vn.arrived_at IS NOT NULL
   AND vn.sim_run_id NOT IN ('64251eb8-e5fb-4f7d-af25-9f4ddf5d3768', 'b2efcc07-e47e-40e2-9411-907e913a3976', '72b09010-d277-45ee-bbe9-3e2fc98c5818')
 GROUP BY 1 ORDER BY 1;

-- (4) the clock's trial through 64251eb8's start: as fitted (with the air level) against the fit without it
SELECT public.ottoq_charge_clock_trial('11111111-1111-1111-1111-111111111111'::uuid,
         ARRAY['64251eb8-e5fb-4f7d-af25-9f4ddf5d3768'::uuid], NULL, '{}'::jsonb, '{"air": false}'::jsonb, false) -> 'by_kind' AS trial;

-- (3, run) the rehearsal itself, one session; change LIMIT/OFFSET for the next batch
DO $do$
DECLARE d text; a text;
BEGIN
  d := pg_get_functiondef('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure);
  d := replace(d, 'FUNCTION public.ottoq_charge_line_schedule(', 'FUNCTION pg_temp.sched_u(');
  a := E'  c_om float8[] := \'{}\'; c_mw float8[] := \'{}\';\n';
  IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'anchor 1'; END IF;
  d := replace(d, a, a || E'  u_on boolean := COALESCE(jsonb_typeof(p_state -> \'urgency\') = \'object\', false);\n'
                       || E'  u_p float8[]; u_off float8 := 45; u_h0 float8 := 0; u_n int := 0; v_ph float8;\n');
  a := E'BEGIN\n  IF r_on THEN';
  IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'anchor 2'; END IF;
  d := replace(d, a, E'BEGIN\n  IF u_on THEN\n'
     || E'    SELECT array_agg((x.value #>> \'{}\')::float8 ORDER BY x.o) INTO u_p\n'
     || E'      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_state #> \'{urgency,p}\') = \'array\' THEN p_state #> \'{urgency,p}\' ELSE \'[]\'::jsonb END) WITH ORDINALITY x(value, o);\n'
     || E'    u_off := COALESCE((p_state #>> \'{urgency,off}\')::float8, 45);\n'
     || E'    u_h0 := COALESCE((p_state #>> \'{urgency,h0}\')::float8, 0);\n'
     || E'    IF u_p IS NULL OR cardinality(u_p) <> 24 THEN u_on := false; END IF;\n'
     || E'  END IF;\n  IF r_on THEN');
  a := E'      c_gate[n] := c_av[n];   -- 0621:';
  IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'anchor 3'; END IF;
  d := replace(d, a, E'      IF u_on AND v_inbound AND NOT c_imm[n] AND c_due[n] IS NULL AND e ->> \'src\' IN (\'forecast\', \'returning\') THEN\n'
     || E'        v_ph := u_p[(((floor(u_h0 + c_av[n] / 60.0))::int % 24) + 24) % 24 + 1];\n'
     || E'        IF public.ottoq_hash_uniform(COALESCE(p_seed, \'\') || \':\' || COALESCE(p_scenario, 0) || \':\' || c_id[n] || \':urgency\') < v_ph THEN\n'
     || E'          c_imm[n] := true; c_due[n] := c_av[n] + u_off; u_n := u_n + 1;\n'
     || E'        END IF;\n'
     || E'      END IF;\n' || a);
  a := E'      c_md[n] := v_rr[4]; c_ml[n] := v_rr[5]; c_av[n] := v_rr[2]; c_gate[n] := v_rr[2];\n';
  IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'anchor 4'; END IF;
  d := replace(d, a, a
     || E'      IF u_on AND o_real IS NULL THEN\n'
     || E'        v_ph := u_p[(((floor(u_h0 + c_av[n] / 60.0))::int % 24) + 24) % 24 + 1];\n'
     || E'        IF public.ottoq_hash_uniform(COALESCE(p_seed, \'\') || \':\' || COALESCE(p_scenario, 0) || \':\' || c_id[n] || \':urgency:r\') < v_ph THEN\n'
     || E'          c_imm[n] := true; c_due[n] := c_av[n] + u_off; u_n := u_n + 1;\n'
     || E'        END IF;\n'
     || E'      END IF;\n');
  a := E'    v_out := v_out || jsonb_build_object(\'faults_drawn\', f_n, \'requeued\', f_rq);\n  END IF;\n';
  IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN RAISE EXCEPTION 'anchor 5'; END IF;
  d := replace(d, a, a || E'  IF u_on THEN\n    v_out := v_out || jsonb_build_object(\'urgency_drawn\', u_n);\n  END IF;\n');
  EXECUTE d;
END $do$;

CREATE FUNCTION pg_temp.roll(p_state jsonb, p_order jsonb, p_futures int, p_seed text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  v_n int := GREATEST(1, LEAST(COALESCE(p_futures, 12), 64));
  k0 jsonb; a0 jsonb; k jsonb; a jsonb; c jsonb; c0 jsonb; s int;
  v_w int := 0; v_t int := 0; v_l int := 0;
BEGIN
  k0 := pg_temp.sched_u(p_state, NULL, 0, p_seed, false);
  a0 := pg_temp.sched_u(p_state, p_order, 0, p_seed, false);
  c0 := public.ottoq_charge_line_compare(k0, a0);
  IF (k0 -> 'first') = (a0 -> 'first') THEN
    RETURN jsonb_build_object('same_first_seats', true, 'futures', 1, 'wins', 0, 'ties', 1, 'losses', 0,
                              'point', c0 || jsonb_build_object('kernel', k0 - 'first', 'agent', a0 - 'first'));
  END IF;
  FOR s IN 0 .. v_n - 1 LOOP
    IF s = 0 THEN c := c0;
    ELSE
      k := pg_temp.sched_u(p_state, NULL, s, p_seed, false);
      a := pg_temp.sched_u(p_state, p_order, s, p_seed, false);
      c := public.ottoq_charge_line_compare(k, a);
    END IF;
    IF (c ->> 'cmp')::int > 0 THEN v_w := v_w + 1; ELSIF (c ->> 'cmp')::int < 0 THEN v_l := v_l + 1; ELSE v_t := v_t + 1; END IF;
  END LOOP;
  RETURN jsonb_build_object('same_first_seats', false, 'futures', v_n, 'wins', v_w, 'ties', v_t, 'losses', v_l,
                            'point', c0 || jsonb_build_object('kernel', k0 - 'first', 'agent', a0 - 'first'));
END $f$;

WITH ex AS (SELECT unnest(ARRAY['64251eb8-e5fb-4f7d-af25-9f4ddf5d3768', 'b2efcc07-e47e-40e2-9411-907e913a3976', '72b09010-d277-45ee-bbe9-3e2fc98c5818']::uuid[]) AS r),
v AS (
  SELECT extract(hour FROM vn.arrived_at)::int AS h, count(*) AS n, count(*) FILTER (WHERE vn.urgency = 'immediate_dispatch') AS i
    FROM public.ottoq_visit_needs vn
   WHERE vn.depot_id = '11111111-1111-1111-1111-111111111111' AND vn.sim_run_id NOT IN (SELECT r FROM ex) AND vn.arrived_at IS NOT NULL
   GROUP BY 1
), pa AS (SELECT sum(i)::float8 / sum(n) AS p FROM v),
pm AS (SELECT jsonb_agg(round(((COALESCE(v.i, 0) + 20 * pa.p) / (COALESCE(v.n, 0) + 20))::numeric, 4) ORDER BY g.h) AS p
         FROM generate_series(0, 23) g(h) CROSS JOIN pa LEFT JOIN v ON v.h = g.h),
o AS (
  SELECT h.order_id, h.sim_run_id, h.outcome, h.p_win, s.state, s.seed, s.agent_order, s.sim_clock,
         CASE WHEN h.outcome IN ('right_take', 'missed_win') THEN 1 ELSE 0 END AS y
    FROM public.ottoq_charge_order_hindsight h JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
   WHERE h.sim_run_id IN ('64251eb8-e5fb-4f7d-af25-9f4ddf5d3768', 'b2efcc07-e47e-40e2-9411-907e913a3976') AND h.decision
     AND h.outcome IN ('right_take', 'missed_win', 'right_refusal', 'wrong_take')
   ORDER BY h.order_id
   LIMIT 4 OFFSET 0
), r AS (
  SELECT o.order_id, o.sim_run_id, o.outcome, o.y,
         public.ottoq_charge_order_verdict_v2(pg_temp.roll(o.state, o.agent_order, 12, o.seed), 0.8) AS v0,
         public.ottoq_charge_order_verdict_v2(pg_temp.roll(o.state || jsonb_build_object('urgency', jsonb_build_object(
             'p', (SELECT p FROM pm), 'off', 45,
             'h0', extract(hour FROM o.sim_clock) + extract(minute FROM o.sim_clock) / 60.0)), o.agent_order, 12, o.seed), 0.8) AS v1
    FROM o
)
SELECT left(sim_run_id::text, 8) AS run, order_id, outcome, y,
       (v0 ->> 'take')::boolean AS take0, v0 ->> 'reason' AS reason0, (v0 ->> 'wins') || '/' || (v0 ->> 'futures') AS w0, v0 ->> 'expected_by' AS by0,
       (v1 ->> 'take')::boolean AS take1, v1 ->> 'reason' AS reason1, (v1 ->> 'wins') || '/' || (v1 ->> 'futures') AS w1, v1 ->> 'expected_by' AS by1,
       (v1 #>> '{kernel,with_due}') AS due1, (v0 #>> '{kernel,with_due}') AS due0
  FROM r ORDER BY order_id;
