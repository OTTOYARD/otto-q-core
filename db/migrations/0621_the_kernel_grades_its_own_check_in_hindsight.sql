-- migration-version: 20261008144612
-- migration-name:    the_kernel_grades_its_own_check_in_hindsight
--
-- 0621  **The kernel grades its own check in hindsight, and says what made it wrong.** 0620 judges each agent charge
--       order on a forecast: the cars it expects home, the charge clock it learned, the charges it sees under way, and
--       nothing of what it cannot see (a car that leaves after the order and comes back inside the window, a charger
--       that faults). 0621 replays every checked order, 90 sim-minutes after it, with what actually happened in place of
--       the forecast, read from the run's own records and put through the same simulator from the same state, and keeps
--       the result: a taken order that won, tied or lost in the world that came, a refused one that would have won. It
--       then splits every difference between the check's expected future and hindsight exactly across the five things
--       the forecast had to guess (arrivals, cars it never saw coming, charge times, the charges under way, faults) by
--       Shapley value; scores the check's own win probability (its wins over futures) against the outcomes; measures each
--       forecast against what came (bias, spread, coverage); measures the simulator itself against when each car really
--       plugged in, given the real inputs; and names the moves each order made, so the agent's board can say which moves
--       have won and which have lost. A nightly self-assessment turns those into improvement areas for the research wing.
--       Chase, 2026-10-08: "When things get tight or congested, that's really when the agent layer should shine that
--       it's still proposing what could make sense and it's just up to our other layers to confirm and learn from ...
--       identify well, it can't technically do XYZ, so I should probably build that in ... Ideally, after a while, the
--       system itself will pick up areas for self improvement." Rule 10 holds throughout: OTTO-Q grades its own decisions
--       and its forecasts and writes only its own ledgers; it changes no rule, dial, bar or model. Every improvement area
--       is a finding for a person, who decides whether to build it and ships it as a certified change.
--
-- ══ §1 WHY ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0620's check can be wrong in three ways, and until now nothing measured which. (a) Its inputs: the forecast of who
--   comes home and when (0619 return_v1), the learned charge clock (0619 charge_time_v1), when the charges under way end,
--   and what it does not see at all: a car dispatched after the order that comes back inside the window, a car that was
--   in a bay at the order and joins the line later, a charger that faults (the twin injects them at a calibrated rate:
--   12 on run 089f46bd in five sim-hours, each down 2 to 6 hours). (b) Its structure: the simulator is a list schedule
--   of the charge line; it has no bays, no holds, no stall pick beyond the kind, and assumes the kernel's order after
--   the agent's lapses where in fact the next order may take over. (c) Its bar: 10 of 12 futures may be too strict or
--   too loose, and the futures' spread may be too narrow or too wide. 0619 learned two models from evidence because a
--   forecast that is never compared with what came cannot be improved except by guessing; this is the same discipline
--   applied to the check that uses them, and to the check's own bar.
--
-- ══ §2 WHAT ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq_charge_line_schedule(state, order, scenario, seed, trace)`: 0620's simulator, which is now this with
--       trace false (`ottoq_charge_line_simulate` is kept as that call, for every caller), and two additions that act only
--       when asked. With trace it reports each car's first seat (when, which kind), its last kind and ready time and how
--       many times a fault stopped it. And a charger carrying `dn`, a list of [from, until] minutes, goes down at from and
--       is back at until: a car charging on it at from stops there and rejoins the line owing the rest of its charge, on
--       whichever charger it takes next (rule 9: a car whose charger faulted is re-queued to finish, as the twin's
--       auto_rerouted). No state 0620 builds carries `dn`, so the check's futures are the same futures; V1 and V3 prove it,
--       V3 by replaying the stored snapshots of live orders to their stored verdicts.
--   (b) `ottoq_charge_order_realized(order, window)`: what happened in the window after the order, from the run's own
--       records, in minutes from the order's clock: each car's first charge (when, on which kind, how long, whether it
--       finished: a charge still running at the cut is a lower bound, one cut by a fault is the faults' part), when each
--       car the check saw coming home arrived and with what battery and due time, the cars the check did not see that
--       joined the line (home inside the window, or in the depot and charged on a charger the check modelled), when each
--       charge under way at the order ended, each charger that faulted in the window (from its faulted session and the
--       repair minutes on its event) and each charger the check left out as faulted that came back inside it. Read-only.
--   (c) `ottoq_charge_line_realize(state, realized, parts)`: the state with the named parts of what happened in place of
--       what the check expected: arrivals, appeared, charge_times, running, faults. Pure.
--   (d) `public.ottoq_charge_order_hindsight`: one row per checked order, graded once its window has closed (or its run
--       has ended): the expected future and hindsight side by side, the outcome (right_take, neutral_take, wrong_take,
--       missed_win, right_refusal; no_decision for an order the check found changed nothing, no_decision_mattered when
--       what happened made it change something), the moves, the forecast errors as sums, the simulator's fidelity, and the
--       realized record the grade was computed from, so it replays without the run's working rows. Evidence.
--   (e) `ottoq_charge_order_grade(order)` writes one; `ottoq_charge_order_attribute(order)` writes the Shapley split to
--       `public.ottoq_charge_order_attribution` (32 subsets of the five parts, each replayed both ways; exact, and the
--       five values sum to hindsight minus the expected future on each of cmp, on-time, lateness and flow);
--       `ottoq_charge_order_grade_pending(run, limit, attribute, budget)` grades what is due within a time budget.
--   (f) The door grades up to three of the run's own closed orders after it records a new one (no attribution: that is
--       the night's), so the agent's next board carries a track record that grows during the run; the board shows it
--       (`track_record`: this run and the depot over seven days, by outcome; each move with how often it won and lost in
--       hindsight; what most often made the check wrong); the usage read gives each order its hindsight outcome.
--   (g) `ottoq_arbiter_self_assessment(depot, since)`: for the research wing, read-only: the check's confusion matrix,
--       the Brier score of its win probability against the base rate and by band, how each bar from 0.5 to 1.0 would have
--       done on the same orders, every forecast's bias, spread and coverage, the simulator's fidelity, the Shapley mass of
--       each part, the moves, and the improvement areas they point to, ranked, each with its evidence. Nightly,
--       `ottoq-arbiter-hindsight-nightly` (every 10 minutes from 11:00 to 12:50 UTC, 6:00-7:50 AM CT, 90 s each, never
--       while a run is running) grades and attributes, and `ottoq-arbiter-assess-nightly` (12:55 UTC, 7:55 AM CT) writes
--       the day's assessment to `public.ottoq_arbiter_assessments`.
--
--   The tick path is untouched. Nothing here writes a dial, a rule, a model or the bar.
--
--   What hindsight is and is not. It replays both orders through the same simulator with what happened as its inputs,
--   so it removes the forecast's error and keeps the simulator's; `fidelity` measures what is left (the applied arm's
--   predicted first plug-in against the real one). It is one draw: an order judged right at 11 of 12 futures that loses
--   in hindsight is not proof the check was wrong, which is why the check is scored by calibration over many orders
--   (Brier, by band) and never order by order. Orders overlap in time, so sums over orders rank alternatives; they do not
--   add up to a day.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the simulator, rollout, comparison, verdict, state, door, usage read, board, learned
--   minutes and learned spread are 0620's (md5 of each source); 0620 is applied; nothing this file creates exists.
--   V1: the schedule without trace returns what 0620's simulator returned, on hand states, both orders and four
--   scenarios, captured before the replacement and compared after; with trace, the seats are the hand-computed ones.
--   V2: a fault, by hand: the charge on the faulted charger stops, the car rejoins the line and finishes the rest when
--   the charger is back. V3: the stored snapshots of live orders replay to their stored verdicts under this file's code.
--   V4: on a running twin run, one order whose window has closed is graded without writing, timed.
--   tests/test_agent_arbiter_sql.py executes the rest on the miniature depot.
--
-- ══ §4 RECERT ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   FALSE/FALSE. The simulator's results are unchanged (V1, V3); the door, usage read and board change only on runs
--   that take an agent's order, which only an operator_demo run arms (0615); no certification, sweep or dial pair runs
--   one. The new ledgers are evidence and read nothing a certification writes.
--
-- ROLLBACK: SELECT cron.unschedule('ottoq-arbiter-hindsight-nightly'); SELECT cron.unschedule('ottoq-arbiter-assess-nightly');
--   EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0621_pre' (the simulator, door, usage read and
--   board as 0620 left them); DROP FUNCTION public.ottoq_arbiter_assess(uuid, integer),
--   public.ottoq_arbiter_hindsight_nightly(integer), public.ottoq_arbiter_self_assessment(uuid, timestamptz),
--   public.ottoq_charge_order_track_record(uuid, uuid, integer),
--   public.ottoq_charge_order_grade_pending(uuid, integer, boolean, integer, numeric),
--   public.ottoq_charge_order_attribute(bigint), public.ottoq_charge_order_grade(bigint, numeric),
--   public.ottoq_hindsight_code_md5(), public.ottoq_charge_order_fidelity(jsonb, jsonb),
--   public.ottoq_charge_order_forecast_errors(jsonb, jsonb), public.ottoq_charge_order_moves(jsonb, jsonb, jsonb),
--   public.ottoq_charge_order_realized(bigint, numeric), public.ottoq_charge_line_realize(jsonb, jsonb, text[]),
--   public.ottoq_charge_line_real_minutes(jsonb, jsonb), public.ottoq_charge_line_schedule(jsonb, jsonb, integer, text,
--   boolean); (the three ledgers may stay: nothing else reads them);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0621_the_kernel_grades_its_own_check_in_hindsight'.

BEGIN;

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0621 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_charge_line_simulate(jsonb,jsonb,integer,text)', '25af07da', 'the simulator (0620)'),
      ('public.ottoq_charge_line_rollout(jsonb,jsonb,integer,text)', '0fed8ccd', 'the rollout (0620)'),
      ('public.ottoq_charge_line_compare(jsonb,jsonb)', '4be5001b', 'the comparison (0620)'),
      ('public.ottoq_charge_order_verdict_v2(jsonb,numeric)', '394b3dc2', 'the verdict (0620)'),
      ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', 'b2e9ddaa', 'the state (0620)'),
      ('public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)', '0da885f6', 'the door (0620)'),
      ('public.ottoq_agent_charge_order_usage(uuid,integer)', 'abc03205', 'the usage read (0620)'),
      ('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', 'ace397a9', 'the board (0620)'),
      ('public.ottoq_charge_minutes_learned_with(jsonb,text,numeric,numeric,numeric,numeric,numeric)', '97486660', 'the learned minutes (0619)'),
      ('public.ottoq_charge_time_log_sd(jsonb,text,numeric)', '8f4b869e', 'the learned spread (0620)'))
    AS x(sig, md5, what)
  LOOP
    IF left((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)), 8) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0621 P1: % is not the body this file was written against (md5 %); read it again', r.what, r.md5;
    END IF;
  END LOOP;
  IF to_regclass('public.ottoq_charge_order_snapshots') IS NULL THEN
    RAISE EXCEPTION '0621 P1: 0620 is not applied (no ottoq_charge_order_snapshots)';
  END IF;
  IF to_regprocedure('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)') IS NOT NULL
     OR to_regclass('public.ottoq_charge_order_hindsight') IS NOT NULL
     OR to_regclass('public.ottoq_charge_order_attribution') IS NOT NULL
     OR to_regclass('public.ottoq_arbiter_assessments') IS NOT NULL THEN
    RAISE EXCEPTION '0621 P1: something this file creates already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0621_the_kernel_grades_its_own_check_in_hindsight') THEN
    RAISE EXCEPTION '0621 P1: already applied';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0621_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_charge_line_simulate(jsonb,jsonb,integer,text)'::regprocedure,
                 'public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)'::regprocedure,
                 'public.ottoq_agent_charge_order_usage(uuid,integer)'::regprocedure,
                 'public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure);

-- V1, before: what 0620's simulator returns on two hand states, the kernel's order and two others, four futures
CREATE TEMP TABLE v0621_states (name text PRIMARY KEY, state jsonb NOT NULL) ON COMMIT DROP;
INSERT INTO v0621_states VALUES
 ('three', '{"ttl_min": 5, "pin_min": 90, "horizon_min": 480,
             "cars": [{"id": "a", "w": 0, "g": 70, "imm": false, "soc": 30, "due": null, "md": 40, "ml": 200, "sd": 0.3, "sl": 0.2},
                      {"id": "b", "w": 0, "g": 10, "imm": false, "soc": 90, "due": null, "md": 20, "ml": 30, "sd": 0.3, "sl": 0.2},
                      {"id": "c", "w": 0, "g": 40, "imm": false, "soc": 60, "due": 50, "md": 30, "ml": 120, "sd": 0.3, "sl": 0.2}],
             "inbound": [], "chargers": [{"id": "f", "k": "dcfc", "free": 0}, {"id": "l", "k": "l2", "free": 0}]}'),
 ('busy', '{"ttl_min": 3.2, "pin_min": 90, "horizon_min": 480,
            "cars": [{"id": "i", "w": 5, "g": 60, "imm": true, "soc": 40, "due": 40, "md": 41, "ml": 141, "sd": 0.25, "sl": 0.3},
                     {"id": "p", "w": 120, "g": 30, "imm": false, "soc": 70, "due": null, "md": 25, "ml": 70, "sd": 0.25, "sl": 0.3},
                     {"id": "q", "w": 95, "g": 12, "imm": false, "soc": 88, "due": 10, "md": 18, "ml": 33, "sd": 0.2, "sl": 0.3},
                     {"id": "r", "w": 20, "g": 70, "imm": false, "soc": 30, "due": 90, "md": 45, "ml": 200, "sd": 0.25, "sl": 0.3},
                     {"id": "s", "w": 10, "g": 15, "imm": false, "soc": 85, "due": null, "md": 15, "ml": 45, "sd": 0.2, "sl": 0.3, "dok": false},
                     {"id": "t", "w": 2, "g": 50, "imm": false, "soc": 50, "due": 120, "md": 35, "ml": 117, "sd": 0.25, "sl": 0.3}],
            "inbound": [{"id": "u", "eta": 12, "src": "returning", "esd": 0, "trip": 0, "soc": 27, "g": 73, "imm": false, "w": 0,
                         "md": 48, "ml": 210, "sd": 0.25, "sl": 0.3},
                        {"id": "v", "eta": 42, "src": "forecast", "esd": 0.1, "trip": 2, "soc": 49, "g": 51, "imm": false, "w": 0,
                         "md": 36, "ml": 120, "sd": 0.25, "sl": 0.3}],
            "chargers": [{"id": "f1", "k": "dcfc", "free": 0}, {"id": "f2", "k": "dcfc", "free": 14, "sd": 0.2},
                         {"id": "l1", "k": "l2", "free": 0}, {"id": "l2", "k": "l2", "free": 55, "sd": 0.3}]}');
CREATE TEMP TABLE v0621_orders (name text PRIMARY KEY, ord jsonb) ON COMMIT DROP;
INSERT INTO v0621_orders VALUES
 ('kernel', NULL), ('empty', '{}'),
 ('three_c_fast', '{"c": {"rank": 1, "kind": "dcfc"}, "a": {"rank": 2, "kind": "l2"}}'),
 ('busy_rescue', '{"q": {"rank": 1, "kind": "dcfc"}, "r": {"rank": 2, "kind": "l2"}, "u": {"rank": 3, "kind": "either"}}'),
 ('busy_bad', '{"r": {"rank": 1, "kind": "l2"}, "t": {"rank": 2, "kind": "l2"}, "s": {"rank": 3, "kind": "dcfc"}}');
CREATE TEMP TABLE v0621_before ON COMMIT DROP AS
  SELECT s.name AS st, o.name AS ord, g AS scenario,
         public.ottoq_charge_line_simulate(s.state, o.ord, g, 'v0621') AS r
    FROM v0621_states s CROSS JOIN v0621_orders o CROSS JOIN generate_series(0, 3) g;

-- ══ (a) the simulator, traced, and able to take a charger down ══════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_line_schedule(p_state jsonb, p_order jsonb, p_scenario integer, p_seed text,
                                                  p_trace boolean)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
/* 0621: 0620's ottoq_charge_line_simulate (which is now this with p_trace false), unchanged where it was, plus two things
   that act only when asked. p_trace adds 'seats': for each car its first seat (s0 minutes, k0 kind), its last kind and
   ready time (k, r), its arrival (a), whether it came home in the window (inb) and how many times a fault stopped its
   charge (x). And a charger carrying 'dn', a list of [from, until] minutes, goes down at from and is back at until: a
   car charging on it at from stops there and rejoins the line owing the rest of its charge, on whichever charger it
   takes next (rule 9: a car whose charger faulted is re-queued to finish; the twin's auto_rerouted). No state 0620 builds
   carries 'dn', and with p_trace false the result is 0620's, key for key. Pure: no table is read. */
DECLARE
  v_ttl float8 := COALESCE((p_state ->> 'ttl_min')::float8, 0);
  v_pin float8 := COALESCE((p_state ->> 'pin_min')::float8, 90);
  v_hor float8 := COALESCE((p_state ->> 'horizon_min')::float8, 480);
  v_on  boolean := (p_order IS NOT NULL AND jsonb_typeof(p_order) = 'object' AND p_order <> '{}'::jsonb);
  c_id text[] := '{}'; c_idr int[] := '{}'; c_w0 float8[] := '{}'; c_g float8[] := '{}'; c_imm boolean[] := '{}';
  c_soc float8[] := '{}'; c_due float8[] := '{}'; c_dok boolean[] := '{}'; c_lok boolean[] := '{}';
  c_md float8[] := '{}'; c_ml float8[] := '{}'; c_av float8[] := '{}'; c_inb boolean[] := '{}';
  c_rank int[] := '{}'; c_okind text[] := '{}';
  c_ready float8[]; c_start float8[]; c_kind text[];
  c_gate float8[] := '{}'; c_s0 float8[]; c_k0 text[]; c_x int[];                                   -- 0621
  s_id text[] := '{}'; s_k text[] := '{}'; s_free float8[] := '{}'; s_car int[] := '{}';            -- 0621: s_car
  d_j int[] := '{}'; d_a float8[] := '{}'; d_b float8[] := '{}'; d_done boolean[] := '{}'; nd int := 0;   -- 0621
  n int := 0; m int := 0; i int; j int; best int; t float8 := 0; t_c float8; t_a float8; t_next float8;
  v_seated int := 0; v_any boolean; v_live boolean; v_mode text; v_dur float8; v_want text; z float8; v_free_n int;
  e jsonb; v_inbound boolean; v_rk text; v_order int[]; v_first text[] := '{}';
  v_out jsonb; v_dn float8; w jsonb; v_frac float8; q int;                                          -- 0621
BEGIN
  FOR v_inbound IN SELECT unnest(ARRAY[false, true]) LOOP
    FOR e IN SELECT x.value FROM jsonb_array_elements(COALESCE(p_state -> CASE WHEN v_inbound THEN 'inbound' ELSE 'cars' END,
                                                               '[]'::jsonb)) WITH ORDINALITY x(value, o) ORDER BY x.o
    LOOP
      CONTINUE WHEN (e ->> 'md') IS NULL OR (e ->> 'ml') IS NULL OR (e ->> 'id') IS NULL;
      n := n + 1;
      c_id[n] := e ->> 'id';
      c_w0[n] := COALESCE((e ->> 'w')::float8, 0);
      c_g[n] := GREATEST(COALESCE((e ->> 'g')::float8, 1), 1);
      c_imm[n] := COALESCE((e ->> 'imm')::boolean, false);
      c_soc[n] := COALESCE((e ->> 'soc')::float8, 0);
      c_due[n] := (e ->> 'due')::float8;
      c_dok[n] := COALESCE((e ->> 'dok')::boolean, true);
      c_lok[n] := COALESCE((e ->> 'lok')::boolean, true);
      c_md[n] := (e ->> 'md')::float8;
      c_ml[n] := (e ->> 'ml')::float8;
      c_inb[n] := v_inbound;
      c_av[n] := CASE WHEN v_inbound THEN GREATEST(COALESCE((e ->> 'eta')::float8, 0), 0) ELSE 0 END;
      IF COALESCE(p_scenario, 0) > 0 THEN
        z := public.ottoq_hash_normal(COALESCE(p_seed, '') || ':' || p_scenario || ':' || c_id[n] || ':charge');
        c_md[n] := c_md[n] * exp(COALESCE((e ->> 'sd')::float8, 0) * z);
        c_ml[n] := c_ml[n] * exp(COALESCE((e ->> 'sl')::float8, 0) * z);
        IF v_inbound AND e ->> 'src' = 'forecast' THEN
          z := public.ottoq_hash_normal(COALESCE(p_seed, '') || ':' || p_scenario || ':' || c_id[n] || ':arrival');
          c_av[n] := COALESCE((e ->> 'trip')::float8, 0)
                     + GREATEST(c_av[n] - COALESCE((e ->> 'trip')::float8, 0), 0) * exp(COALESCE((e ->> 'esd')::float8, 0) * z);
        END IF;
      END IF;
      c_gate[n] := c_av[n];   -- 0621: when the car may take a charger: its arrival, or when a fault put it back in line
      v_rk := CASE WHEN v_on AND p_order ? c_id[n] THEN p_order -> c_id[n] ->> 'rank' END;
      c_rank[n] := CASE WHEN v_rk IS NULL THEN NULL WHEN v_rk ~ '^[0-9]{1,6}$' THEN v_rk::int ELSE 999 END;
      c_okind[n] := CASE WHEN v_on AND p_order ? c_id[n] THEN p_order -> c_id[n] ->> 'kind' END;
    END LOOP;
  END LOOP;

  -- the id's rank, the cursor's last key, computed once (comparing a uuid's text is comparing the uuid)
  IF n > 0 THEN
    SELECT array_agg(r.rk ORDER BY r.i) INTO c_idr
      FROM (SELECT u.i, rank() OVER (ORDER BY u.id) AS rk FROM unnest(c_id) WITH ORDINALITY AS u(id, i)) r;
  END IF;

  FOR e IN SELECT x.value FROM jsonb_array_elements(COALESCE(p_state -> 'chargers', '[]'::jsonb)) WITH ORDINALITY x(value, o)
            ORDER BY x.o
  LOOP
    CONTINUE WHEN (e ->> 'free') IS NULL OR (e ->> 'k') NOT IN ('dcfc', 'l2');
    m := m + 1;
    s_id[m] := e ->> 'id';
    s_k[m] := e ->> 'k';
    s_free[m] := GREATEST((e ->> 'free')::float8, 0);
    s_car[m] := NULL;
    IF COALESCE(p_scenario, 0) > 0 AND s_free[m] > 0 THEN
      z := public.ottoq_hash_normal(COALESCE(p_seed, '') || ':' || p_scenario || ':' || s_id[m] || ':running');
      s_free[m] := s_free[m] * exp(COALESCE((e ->> 'sd')::float8, 0) * z);
    END IF;
    -- 0621: the windows this charger is down, as given (never drawn)
    IF jsonb_typeof(e -> 'dn') = 'array' THEN
      FOR w IN SELECT x.value FROM jsonb_array_elements(e -> 'dn') WITH ORDINALITY x(value, o) ORDER BY x.o LOOP
        CONTINUE WHEN jsonb_typeof(w) <> 'array' OR (w ->> 0) IS NULL;
        nd := nd + 1;
        d_j[nd] := m;
        d_a[nd] := GREATEST((w ->> 0)::float8, 0);
        d_b[nd] := GREATEST(COALESCE((w ->> 1)::float8, v_hor + 1), d_a[nd]);
        d_done[nd] := false;
      END LOOP;
    END IF;
  END LOOP;

  c_ready := array_fill(NULL::float8, ARRAY[GREATEST(n, 1)]);
  c_start := array_fill(NULL::float8, ARRAY[GREATEST(n, 1)]);
  c_kind  := array_fill(NULL::text, ARRAY[GREATEST(n, 1)]);
  c_s0    := array_fill(NULL::float8, ARRAY[GREATEST(n, 1)]);
  c_k0    := array_fill(NULL::text, ARRAY[GREATEST(n, 1)]);
  c_x     := array_fill(0, ARRAY[GREATEST(n, 1)]);

  LOOP
    -- 0621: the next charger to go down, if one is still to (with no 'dn' this is NULL and the loop is 0620's)
    v_dn := NULL;
    IF nd > 0 THEN
      SELECT min(u.a) INTO v_dn FROM unnest(d_a, d_done) AS u(a, done) WHERE NOT u.done;
    END IF;
    EXIT WHEN m = 0 OR (v_seated >= n AND v_dn IS NULL);
    -- the first moment a charger is free and a car is waiting
    SELECT min(f) INTO t_c FROM unnest(s_free) f;
    SELECT min(u.a) INTO t_a FROM unnest(c_gate, c_ready) AS u(a, r) WHERE u.r IS NULL;
    IF v_dn IS NOT NULL AND (t_c IS NULL OR t_a IS NULL OR v_dn <= GREATEST(t, t_c, t_a)) THEN
      -- 0621: a charger goes down before the next seat: the charge on it stops, its car rejoins the line owing the rest
      EXIT WHEN v_dn > v_hor;
      FOR q IN 1 .. nd LOOP
        CONTINUE WHEN d_done[q] OR d_a[q] > v_dn;
        d_done[q] := true;
        j := d_j[q];
        i := s_car[j];
        IF i IS NOT NULL AND c_start[i] IS NOT NULL AND c_start[i] < d_a[q] AND c_ready[i] > d_a[q] THEN
          v_frac := (c_ready[i] - d_a[q]) / GREATEST(c_ready[i] - c_start[i], 0.01);
          c_md[i] := c_md[i] * v_frac;
          c_ml[i] := c_ml[i] * v_frac;
          c_ready[i] := NULL; c_start[i] := NULL; c_kind[i] := NULL;
          c_gate[i] := d_a[q];
          c_x[i] := c_x[i] + 1;
          v_seated := v_seated - 1;
          s_car[j] := NULL;
          s_free[j] := d_b[q];
        ELSE
          s_free[j] := GREATEST(s_free[j], d_b[q]);
        END IF;
      END LOOP;
      CONTINUE;
    END IF;
    EXIT WHEN t_c IS NULL OR t_a IS NULL;
    t := GREATEST(t, t_c, t_a);
    EXIT WHEN t > v_hor;
    v_live := v_on AND t < v_ttl;
    -- the kinds free at t, read once, as the cursor reads them once a tick
    SELECT CASE WHEN bool_or(z2.k = 'dcfc') AND bool_or(z2.k = 'l2') THEN 'both'
                WHEN bool_or(z2.k = 'dcfc') THEN 'dcfc' ELSE 'l2' END
      INTO v_mode FROM unnest(s_k, s_free) AS z2(k, f) WHERE z2.f <= t;
    -- the cars waiting at t, in the cursor's order at t
    SELECT array_agg(u.i ORDER BY
             u.imm DESC,
             CASE WHEN v_live THEN u.w >= v_pin END DESC NULLS LAST,
             CASE WHEN v_live AND NOT (u.w >= v_pin) THEN
                    CASE WHEN u.rk IS NULL THEN 500
                         ELSE u.rk + CASE WHEN v_mode = 'dcfc' AND u.ok = 'l2' THEN 1000
                                          WHEN v_mode = 'l2' AND u.ok = 'dcfc' THEN 1000 ELSE 0 END END END ASC NULLS LAST,
             (u.w + u.g) / u.g DESC, u.soc ASC, u.idr ASC)
      INTO v_order
      FROM (SELECT z3.i, c_imm[z3.i] AS imm,
                   CASE WHEN c_inb[z3.i] THEN t - c_av[z3.i] ELSE c_w0[z3.i] + t END AS w,
                   c_g[z3.i] AS g, c_soc[z3.i] AS soc, c_idr[z3.i] AS idr, c_rank[z3.i] AS rk, c_okind[z3.i] AS ok
              FROM generate_subscripts(c_ready, 1) AS z3(i)
             WHERE z3.i <= n AND c_ready[z3.i] IS NULL AND c_gate[z3.i] <= t) u;
    v_any := false;
    SELECT count(*) INTO v_free_n FROM unnest(s_free) f WHERE f <= t;
    FOREACH i IN ARRAY COALESCE(v_order, '{}'::int[]) LOOP
      EXIT WHEN v_free_n = 0;     -- every charger free at t is taken: the rest wait for the next one
      v_want := CASE WHEN v_live AND NOT c_imm[i] AND c_okind[i] IN ('dcfc', 'l2') THEN c_okind[i]
                     WHEN c_soc[i] < 45 OR c_imm[i] THEN 'dcfc' ELSE 'l2' END;
      best := NULL;
      FOR j IN 1..m LOOP
        CONTINUE WHEN s_free[j] > t;
        CONTINUE WHEN (s_k[j] = 'dcfc' AND NOT c_dok[i]) OR (s_k[j] = 'l2' AND NOT c_lok[i]);
        IF best IS NULL OR (s_k[j] = v_want AND s_k[best] <> v_want) THEN best := j; END IF;
      END LOOP;
      CONTINUE WHEN best IS NULL;
      v_dur := CASE WHEN s_k[best] = 'dcfc' THEN c_md[i] ELSE c_ml[i] END;
      c_start[i] := t; c_ready[i] := t + v_dur; c_kind[i] := s_k[best];
      IF c_s0[i] IS NULL THEN c_s0[i] := t; c_k0[i] := s_k[best]; END IF;   -- 0621
      s_free[best] := t + GREATEST(v_dur, 0.01);
      s_car[best] := i;                                                     -- 0621
      v_seated := v_seated + 1; v_any := true; v_free_n := v_free_n - 1;
      IF t < v_ttl THEN
        v_first := v_first || (c_id[i] || '@' || s_k[best] || '@' || to_char(t, 'FM99990.00'));
      END IF;
    END LOOP;
    IF NOT v_any THEN
      -- no car waiting can use a charger free at t: those chargers wait for the next charger to free, car to arrive,
      -- or (0621) charger to go down
      SELECT min(f) INTO t_c FROM unnest(s_free) f WHERE f > t;
      SELECT min(u.a) INTO t_a FROM unnest(c_gate, c_ready) AS u(a, r) WHERE u.r IS NULL AND u.a > t;
      t_next := LEAST(t_c, t_a, v_dn);
      EXIT WHEN t_next IS NULL;
      FOR j IN 1..m LOOP
        IF s_free[j] <= t THEN s_free[j] := t_next; END IF;
      END LOOP;
    END IF;
  END LOOP;

  SELECT jsonb_build_object(
           'cars', n,
           'inbound', count(*) FILTER (WHERE c_inb[z.i]),
           'chargers', m,
           'seated', count(*) FILTER (WHERE c_ready[z.i] IS NOT NULL),
           'with_due', count(*) FILTER (WHERE c_due[z.i] IS NOT NULL),
           'on_time', count(*) FILTER (WHERE c_due[z.i] IS NOT NULL AND c_ready[z.i] IS NOT NULL AND c_ready[z.i] <= c_due[z.i]),
           'late_sum', round(COALESCE(sum(GREATEST(COALESCE(c_ready[z.i], v_hor + LEAST(c_md[z.i], c_ml[z.i])) - c_due[z.i], 0))
                                        FILTER (WHERE c_due[z.i] IS NOT NULL), 0)::numeric, 2),
           'flow_sum', round(COALESCE(sum(COALESCE(c_ready[z.i], v_hor + LEAST(c_md[z.i], c_ml[z.i])) - c_av[z.i]), 0)::numeric, 2),
           'line_flow_sum', round(COALESCE(sum(COALESCE(c_ready[z.i], v_hor + LEAST(c_md[z.i], c_ml[z.i])))
                                             FILTER (WHERE NOT c_inb[z.i]), 0)::numeric, 2),
           'on_dcfc', count(*) FILTER (WHERE c_kind[z.i] = 'dcfc'),
           'on_l2', count(*) FILTER (WHERE c_kind[z.i] = 'l2'),
           -- the seats made in the order's window, as a set: the same seats made in another order are the same seats
           'first', to_jsonb(ARRAY(SELECT f FROM unnest(v_first) f ORDER BY f)))
    INTO v_out
    FROM generate_subscripts(c_ready, 1) AS z(i)
   WHERE z.i <= n;
  IF COALESCE(p_trace, false) THEN
    v_out := v_out || jsonb_build_object('seats', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', c_id[z.i], 's0', round(c_s0[z.i]::numeric, 2), 'k0', c_k0[z.i],
               'r', round(c_ready[z.i]::numeric, 2), 'k', c_kind[z.i], 'a', round(c_av[z.i]::numeric, 2),
               'inb', c_inb[z.i], 'x', c_x[z.i]) ORDER BY z.i)
        FROM generate_subscripts(c_ready, 1) AS z(i) WHERE z.i <= n), '[]'::jsonb));
  END IF;
  RETURN v_out;
END $fn$;

COMMENT ON FUNCTION public.ottoq_charge_line_schedule(jsonb, jsonb, integer, text, boolean) IS
'0621. The charge line as a list schedule (0620''s simulator): with p_trace, every car''s first seat, last kind and ready time; a charger carrying dn [[from, until], ...] goes down and back, its car re-queued to finish (rule 9). Pure.';

CREATE OR REPLACE FUNCTION public.ottoq_charge_line_simulate(p_state jsonb, p_order jsonb, p_scenario integer, p_seed text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0621: 0620's simulator is ottoq_charge_line_schedule without its trace; the name stays for every caller.
  SELECT public.ottoq_charge_line_schedule(p_state, p_order, p_scenario, p_seed, false)
$fn$;

-- ══ (c) the state with what happened in place of the forecast ═════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_line_real_minutes(p_entry jsonb, p_real jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0621: a car of the state with its charge timed as it really ran: the real minutes on the kind it took (at least as
  -- long as it had run, and at least the learned clock's, when it was still running at the cut), the other kind scaled
  -- as the learned clock scales it. The entry unchanged when no finished or running charge was read (a charge cut by a
  -- fault is the faults' part, not this one).
  SELECT CASE WHEN y.m IS NULL OR y.md IS NULL OR y.ml IS NULL OR y.md <= 0 OR y.ml <= 0 THEN p_entry
              ELSE p_entry || jsonb_build_object(
                     'md', round(CASE WHEN y.k = 'dcfc' THEN y.m ELSE y.m * y.md / y.ml END, 2),
                     'ml', round(CASE WHEN y.k = 'l2' THEN y.m ELSE y.m * y.ml / y.md END, 2)) END
    FROM (SELECT x.k, x.md, x.ml,
                 CASE WHEN COALESCE(x.k, '') NOT IN ('dcfc', 'l2') OR x.m0 IS NULL THEN NULL
                      WHEN x.cen THEN GREATEST(x.m0, CASE WHEN x.k = 'dcfc' THEN x.md ELSE x.ml END)
                      ELSE x.m0 END AS m
            FROM (SELECT p_real ->> 'k0' AS k,
                         CASE WHEN jsonb_typeof(p_real -> 'm') = 'number' THEN (p_real ->> 'm')::numeric END AS m0,
                         COALESCE((p_real ->> 'cen')::boolean, false) AS cen,
                         (p_entry ->> 'md')::numeric AS md, (p_entry ->> 'ml')::numeric AS ml) x) y
$fn$;

CREATE FUNCTION public.ottoq_charge_line_realize(p_state jsonb, p_real jsonb, p_parts text[])
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
/* 0621: p_state (ottoq_charge_line_state, as the check read it) with the named parts of what happened (p_real, from
   ottoq_charge_order_realized) in place of what the check expected. arrivals: when each car the check saw coming home
   arrived, with its battery, its minutes at that battery on the check's own clock, and its due time; appeared: the cars
   the check did not see that joined the line, when they did; charge_times: each charge's real minutes on the kind it
   took; running: when each charge under way at the order ended; faults: each charger's down windows, and the chargers
   back from a repair. Every other number is the check's. Pure. */
DECLARE
  v_a boolean := 'arrivals' = ANY (COALESCE(p_parts, '{}'::text[]));
  v_u boolean := 'appeared' = ANY (COALESCE(p_parts, '{}'::text[]));
  v_d boolean := 'charge_times' = ANY (COALESCE(p_parts, '{}'::text[]));
  v_r boolean := 'running' = ANY (COALESCE(p_parts, '{}'::text[]));
  v_f boolean := 'faults' = ANY (COALESCE(p_parts, '{}'::text[]));
  v_cars jsonb := '[]'::jsonb; v_inb jsonb := '[]'::jsonb; v_ch jsonb := '[]'::jsonb; e jsonb; r jsonb;
BEGIN
  IF p_real IS NULL OR NOT (v_a OR v_u OR v_d OR v_r OR v_f) THEN
    RETURN p_state;
  END IF;
  FOR e IN SELECT x.value FROM jsonb_array_elements(COALESCE(p_state -> 'cars', '[]'::jsonb)) WITH ORDINALITY x(value, o)
            ORDER BY x.o
  LOOP
    IF v_d THEN e := public.ottoq_charge_line_real_minutes(e, p_real #> ARRAY['cars', e ->> 'id']); END IF;
    v_cars := v_cars || jsonb_build_array(e);
  END LOOP;
  FOR e IN SELECT x.value FROM jsonb_array_elements(COALESCE(p_state -> 'inbound', '[]'::jsonb)) WITH ORDINALITY x(value, o)
            ORDER BY x.o
  LOOP
    r := p_real #> ARRAY['inbound', e ->> 'id'];
    IF v_a AND r IS NOT NULL THEN
      e := e || jsonb_strip_nulls(jsonb_build_object('eta', r -> 'eta', 'soc', r -> 'soc', 'g', r -> 'g', 'md', r -> 'md',
                                                     'ml', r -> 'ml', 'sd', r -> 'sd', 'sl', r -> 'sl', 'due', r -> 'due',
                                                     'imm', r -> 'imm'));
      IF COALESCE((r ->> 'arrived')::boolean, false) THEN
        e := e || jsonb_build_object('src', 'arrived', 'esd', 0);
      END IF;
    END IF;
    IF v_d THEN e := public.ottoq_charge_line_real_minutes(e, r); END IF;
    v_inb := v_inb || jsonb_build_array(e);
  END LOOP;
  IF v_u THEN
    FOR e IN SELECT x.value FROM jsonb_array_elements(COALESCE(p_real -> 'appeared', '[]'::jsonb)) WITH ORDINALITY x(value, o)
              ORDER BY x.o
    LOOP
      IF v_d THEN e := public.ottoq_charge_line_real_minutes(e, e); END IF;
      v_inb := v_inb || jsonb_build_array(e - ARRAY['s0', 'k0', 'm', 'cen', 'end', 'how']);
    END LOOP;
  END IF;
  FOR e IN SELECT x.value FROM jsonb_array_elements(COALESCE(p_state -> 'chargers', '[]'::jsonb)) WITH ORDINALITY x(value, o)
            ORDER BY x.o
  LOOP
    r := p_real #> ARRAY['chargers', e ->> 'id'];
    IF v_r AND jsonb_typeof(r -> 'free') = 'number' THEN e := e || jsonb_build_object('free', r -> 'free'); END IF;
    IF v_f AND jsonb_typeof(r -> 'dn') = 'array' THEN e := e || jsonb_build_object('dn', r -> 'dn'); END IF;
    v_ch := v_ch || jsonb_build_array(e);
  END LOOP;
  IF v_f THEN
    v_ch := v_ch || COALESCE(p_real -> 'back', '[]'::jsonb);
  END IF;
  RETURN p_state || jsonb_build_object('cars', v_cars, 'inbound', v_inb, 'chargers', v_ch);
END $fn$;

-- ══ (d) the ledgers ════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_charge_order_hindsight (
  --: the order graded (ottoq_agent_charge_orders.order_id = ottoq_charge_order_snapshots.order_id). NO foreign key,
  --: deliberately: evidence outlives ottoq_purge_prior_runs (0340/0364), as the snapshot it grades does.
  order_id      bigint PRIMARY KEY,
  sim_run_id    uuid NOT NULL,
  depot_id      uuid,
  --: the order's sim clock: minute 0 of every minute in this row
  sim_clock     timestamptz,
  --: how long after the order hindsight looks, and how much of that the run lived through (less only when it ended)
  window_min    numeric NOT NULL,
  observed_min  numeric NOT NULL,
  --: the order's status (accepted, partial, refused) and the check's reason (0620)
  status        text,
  reason        text,
  taken         boolean NOT NULL,
  --: the check had something to decide: not same_as_kernel, not rollout_failed
  decision      boolean NOT NULL,
  futures       integer,
  wins          integer,
  need          integer,
  --: wins / futures: the check's own probability that the order beats the kernel's
  p_win         numeric,
  --: the expected future as the check saw it, and the world that came, each {cmp, by, d_on_time, d_late, d_flow,
  --: kernel{...}, agent{...}}: the same simulator from the same state, the second with what happened as its inputs
  expected      jsonb NOT NULL,
  hindsight     jsonb NOT NULL,
  outcome       text NOT NULL,
  --: what the order changed in the expected future's window (ottoq_charge_order_moves)
  moves         text[] NOT NULL DEFAULT '{}'::text[],
  --: each forecast against what came, as sums (ottoq_charge_order_forecast_errors)
  forecast      jsonb NOT NULL,
  --: the simulator against the run, given the real inputs (ottoq_charge_order_fidelity)
  fidelity      jsonb NOT NULL,
  --: what happened, as ottoq_charge_order_realized read it: the grade and its attribution replay from this
  realized      jsonb NOT NULL,
  code_md5      text NOT NULL,
  graded_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ottoq_charge_order_hindsight_outcome_ck CHECK (outcome IN
    ('right_take', 'neutral_take', 'wrong_take', 'missed_win', 'right_refusal', 'no_decision', 'no_decision_mattered'))
);

COMMENT ON TABLE public.ottoq_charge_order_hindsight IS
'0621. One row per agent charge order the kernel checked (0620), graded once its window (90 sim-minutes) closed or its run ended: the check''s expected future and the world that came, replayed by the same simulator from the same state; the outcome; the moves the order made; each forecast against what came; the simulator''s fidelity given the real inputs; and the realized record it was computed from. Class=evidence with NO foreign key (0340/0364). Append-only (override: ottoq.hindsight_unlock=on).';

CREATE INDEX ottoq_charge_order_hindsight_run_idx ON public.ottoq_charge_order_hindsight (sim_run_id, order_id);
CREATE INDEX ottoq_charge_order_hindsight_depot_idx ON public.ottoq_charge_order_hindsight (depot_id, graded_at);

CREATE TABLE public.ottoq_charge_order_attribution (
  order_id        bigint PRIMARY KEY,
  sim_run_id      uuid NOT NULL,
  depot_id        uuid,
  --: the parts of what happened, in bit order: bit i of a subset is parts[i + 1]
  parts           text[] NOT NULL,
  --: v(S) for every subset S of the parts put in place of the forecast, S = 0 .. 31: [cmp, d_on_time, d_late, d_flow]
  subset_values   jsonb NOT NULL,
  --: each part's Shapley value on cmp, on_time, late and flow; on each, they sum to v(all) - v(none) = hindsight - expected
  shapley         jsonb NOT NULL,
  --: the hindsight comparison's sign differs from the expected one's
  verdict_changed boolean NOT NULL,
  code_md5        text NOT NULL,
  computed_at     timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.ottoq_charge_order_attribution IS
'0621. Why hindsight differs from the check, for one graded order: the comparison of the agent''s order with the kernel''s replayed with every subset of the five parts of what happened (arrivals, appeared, charge_times, running, faults) put in place of the forecast, and each part''s exact Shapley share of the difference. Class=evidence, NO foreign key. Append-only (override: ottoq.hindsight_unlock=on).';

CREATE TABLE public.ottoq_arbiter_assessments (
  assessment_id     bigserial PRIMARY KEY,
  depot_id          uuid NOT NULL,
  assessed_at       timestamptz NOT NULL DEFAULT now(),
  --: the graded orders read: graded_at >= since
  since             timestamptz NOT NULL,
  n_graded          integer NOT NULL,
  n_decisions       integer NOT NULL,
  assessment        jsonb NOT NULL,
  --: ranked findings for the research wing, each with its evidence; never applied by OTTO-Q (rule 10)
  improvement_areas jsonb NOT NULL,
  code_md5          text NOT NULL
);

COMMENT ON TABLE public.ottoq_arbiter_assessments IS
'0621. The check''s nightly self-assessment from the hindsight ledger (ottoq_arbiter_self_assessment): calibration, the bar, the forecasts, the simulator, the moves, and the improvement areas they point to. Findings for a person: OTTO-Q changes no rule, dial, bar or model from them (CLAUDE.md rule 10). Append-only (override: ottoq.hindsight_unlock=on).';

CREATE FUNCTION public.ottoq_hindsight_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.hindsight_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION '% is append-only: % refused. Set ottoq.hindsight_unlock=on in the session to override, and say why '
                  'in a migration.', TG_TABLE_NAME, TG_OP
    USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_charge_order_hindsight_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_charge_order_hindsight
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_hindsight_append_only();
CREATE TRIGGER ottoq_charge_order_attribution_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_charge_order_attribution
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_hindsight_append_only();
CREATE TRIGGER ottoq_arbiter_assessments_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_arbiter_assessments
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_hindsight_append_only();

ALTER TABLE public.ottoq_charge_order_hindsight ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_charge_order_attribution ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ottoq_arbiter_assessments ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_charge_order_hindsight_read ON public.ottoq_charge_order_hindsight FOR SELECT USING (true);
CREATE POLICY ottoq_charge_order_attribution_read ON public.ottoq_charge_order_attribution FOR SELECT USING (true);
CREATE POLICY ottoq_arbiter_assessments_read ON public.ottoq_arbiter_assessments FOR SELECT USING (true);
REVOKE ALL ON public.ottoq_charge_order_hindsight, public.ottoq_charge_order_attribution, public.ottoq_arbiter_assessments
  FROM anon, authenticated;
GRANT SELECT ON public.ottoq_charge_order_hindsight, public.ottoq_charge_order_attribution, public.ottoq_arbiter_assessments
  TO anon, authenticated;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_charge_order_hindsight', 'sim_run_id', 'evidence',
        '0621: each checked agent charge order graded in hindsight, with the realized record it was graded from: what '
        'lets the kernel''s check be scored after its run''s working rows are purged. Evidence, not engine. NO foreign key '
        'to ottoq_sim_runs, as 0340, 0364 and 0620.'),
       ('public', 'ottoq_charge_order_attribution', 'sim_run_id', 'evidence',
        '0621: the Shapley split of each graded order''s difference between the check and hindsight across the parts of '
        'what happened. Evidence, not engine. NO foreign key to ottoq_sim_runs.');

-- ══ (b) what happened after an order ═══════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_order_realized(p_order_id bigint, p_window_min numeric DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0621: what actually happened in the p_window_min sim-minutes after a checked order (ottoq_charge_order_snapshots), from
   the run's own records, shaped as the order's state is, in minutes from the order's clock. cars / inbound: each car
   the check saw, keyed by id: its first charge after the order (s0 when, k0 on which kind, m how long, cen true when the
   charge was still running at the cut (m is then a lower bound) or ended any way but completed, end how it ended; m is
   NULL for a charge cut by a fault, which is the faults' part); and for a car the check saw coming home, when it arrived
   (eta; when it had not by the cut, no sooner than the cut), its battery, its due time and immediacy, and its minutes at
   that battery on the check's own charge clock (the snapshot's model, by id). appeared: the cars the check did not see
   that joined the line, as state entries: home inside the window owing a charge (how = returned), or in the depot at
   the order and charged on a charger the check modelled (how = at_depot, joining when it plugged in). chargers: for each
   charger the check modelled, when the charge under way at the order ended (free) and when it was down (dn: from the
   charger's faulted sessions, until the repair on the fault's event). back: the chargers the check left out that came
   back from a repair inside the window. faults: faults inside the window; unmodeled_sessions: charges inside the window
   on chargers the check left out. Read-only. */
DECLARE
  s record; v_clock timestamptz; v_status text; v_t0 timestamptz; v_cut timestamptz; v_obs numeric;
  v_model jsonb; v_kw_d numeric; v_kw_l numeric; v_ids text[]; v_ch_ids text[]; v_back_ids text[];
  v_cars jsonb; v_inb jsonb; v_app jsonb; v_ch jsonb; v_back jsonb; v_faults int; v_unmod int; v_fs jsonb;
BEGIN
  SELECT * INTO s FROM ottoq_charge_order_snapshots x WHERE x.order_id = p_order_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT r.sim_clock_current, r.status INTO v_clock, v_status FROM ottoq_sim_runs r WHERE r.sim_run_id = s.sim_run_id;
  v_t0 := s.sim_clock;
  v_cut := GREATEST(LEAST(v_t0 + make_interval(secs => GREATEST(COALESCE(p_window_min, 90), 1) * 60),
                          COALESCE(v_clock, v_t0)), v_t0);
  v_obs := round((extract(epoch FROM (v_cut - v_t0)) / 60.0)::numeric, 2);
  SELECT jsonb_build_object('params', e.params) INTO v_model
    FROM ottoq_learned_estimates e
   WHERE e.estimate_id = CASE WHEN (s.state #>> '{models,charge_time}') ~ '^[0-9]+$'
                              THEN (s.state #>> '{models,charge_time}')::bigint END;
  SELECT max(st.connector_max_kw) FILTER (WHERE st.stall_type::text = 'dcfc'),
         max(st.connector_max_kw) FILTER (WHERE st.stall_type::text = 'l2')
    INTO v_kw_d, v_kw_l
    FROM stalls st WHERE st.depot_id = s.depot_id AND st.stall_type::text IN ('dcfc', 'l2');
  SELECT COALESCE(array_agg(x.value ->> 'id'), '{}'::text[]) INTO v_ids
    FROM (SELECT value FROM jsonb_array_elements(COALESCE(s.state -> 'cars', '[]'::jsonb))
          UNION ALL
          SELECT value FROM jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb))) x;
  SELECT COALESCE(array_agg(x.value ->> 'id'), '{}'::text[]) INTO v_ch_ids
    FROM jsonb_array_elements(COALESCE(s.state -> 'chargers', '[]'::jsonb)) x;

  -- the chargers the check left out that came back from a repair inside the window
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', b.id, 'k', b.kind, 'free', round(b.back::numeric, 2), 'sd', 0)
                            ORDER BY b.kind, b.back, b.id), '[]'::jsonb),
         COALESCE(array_agg(b.id), '{}'::text[])
    INTO v_back, v_back_ids
    FROM (SELECT DISTINCT ON (os.stall_id) os.stall_id::text AS id, st.stall_type::text AS kind,
                 extract(epoch FROM (COALESCE(ev.at, os.ended_at) + make_interval(secs => COALESCE(ev.rep, 0) * 60) - v_t0)) / 60.0 AS back
            FROM ocpp_sessions os
            JOIN stalls st ON st.id = os.stall_id
            LEFT JOIN LATERAL (SELECT e.sim_clock_at AS at, (e.payload ->> 'repair_minutes')::numeric AS rep
                                 FROM ottoq_events e
                                WHERE e.entity_type = 'ocpp_session' AND e.entity_id = os.id
                                  AND e.event_type = 'charge.session_faulted'
                                ORDER BY e.occurred_at DESC LIMIT 1) ev ON true
           WHERE os.sim_run_id = s.sim_run_id AND os.status::text = 'faulted' AND os.ended_at IS NOT NULL
             AND st.depot_id = s.depot_id AND st.stall_type::text IN ('dcfc', 'l2')
             AND os.stall_id::text <> ALL (v_ch_ids)
             AND COALESCE(ev.at, os.ended_at) < v_t0
           ORDER BY os.stall_id, COALESCE(ev.at, os.ended_at) DESC) b
   WHERE b.back > 0 AND b.back <= v_obs;

  -- the chargers the check modelled: when the charge under way ended, and when each was down
  SELECT COALESCE(jsonb_object_agg(c.id, jsonb_strip_nulls(jsonb_build_object(
           'free', CASE WHEN rs.stall_id IS NULL THEN NULL
                        WHEN rs.ended_at IS NOT NULL AND rs.ended_at <= v_cut
                        THEN round((extract(epoch FROM (rs.ended_at - v_t0)) / 60.0)::numeric, 2)
                        ELSE GREATEST(v_obs, c.free) END,
           'cen', CASE WHEN rs.stall_id IS NOT NULL THEN NOT (rs.ended_at IS NOT NULL AND rs.ended_at <= v_cut) END,
           'dn', dn.w)))
           FILTER (WHERE rs.stall_id IS NOT NULL OR dn.w IS NOT NULL), '{}'::jsonb)
    INTO v_ch
    FROM (SELECT x.value ->> 'id' AS id, COALESCE((x.value ->> 'free')::numeric, 0) AS free
            FROM jsonb_array_elements(COALESCE(s.state -> 'chargers', '[]'::jsonb)) x
           WHERE (x.value ->> 'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') c
    LEFT JOIN LATERAL (SELECT os.stall_id, os.ended_at FROM ocpp_sessions os
                        WHERE c.free > 0 AND os.sim_run_id = s.sim_run_id AND os.stall_id = c.id::uuid
                          AND os.started_at < v_t0 AND (os.ended_at IS NULL OR os.ended_at > v_t0)
                        ORDER BY os.started_at DESC LIMIT 1) rs ON true
    LEFT JOIN LATERAL (SELECT jsonb_agg(jsonb_build_array(round(f.a::numeric, 2), round((f.a + f.rep)::numeric, 2))
                                        ORDER BY f.a) AS w
                         FROM (SELECT extract(epoch FROM (COALESCE(ev.at, os.ended_at) - v_t0)) / 60.0 AS a,
                                      COALESCE(ev.rep, 0) AS rep
                                 FROM ocpp_sessions os
                                 LEFT JOIN LATERAL (SELECT e.sim_clock_at AS at, (e.payload ->> 'repair_minutes')::numeric AS rep
                                                      FROM ottoq_events e
                                                     WHERE e.entity_type = 'ocpp_session' AND e.entity_id = os.id
                                                       AND e.event_type = 'charge.session_faulted'
                                                     ORDER BY e.occurred_at DESC LIMIT 1) ev ON true
                                WHERE os.sim_run_id = s.sim_run_id AND os.stall_id = c.id::uuid
                                  AND os.status::text = 'faulted' AND os.ended_at IS NOT NULL
                                  AND COALESCE(ev.at, os.ended_at) >= v_t0 AND COALESCE(ev.at, os.ended_at) < v_cut) f) dn ON true;

  SELECT count(*) INTO v_faults
    FROM ocpp_sessions os JOIN stalls st ON st.id = os.stall_id
   WHERE os.sim_run_id = s.sim_run_id AND os.status::text = 'faulted' AND os.ended_at >= v_t0 AND os.ended_at < v_cut
     AND st.depot_id = s.depot_id;
  SELECT count(*) INTO v_unmod
    FROM ocpp_sessions os JOIN stalls st ON st.id = os.stall_id
   WHERE os.sim_run_id = s.sim_run_id AND os.started_at >= v_t0 AND os.started_at < v_cut
     AND st.depot_id = s.depot_id AND st.stall_type::text IN ('dcfc', 'l2')
     AND os.stall_id::text <> ALL (v_ch_ids || v_back_ids);

  -- every car's first charge after the order, keyed by vehicle: {j: the car's record, stall, started_at, soc_start}
  SELECT COALESCE(jsonb_object_agg(f.id, jsonb_build_object(
           'j', jsonb_build_object(
                  's0', round((extract(epoch FROM (f.started_at - v_t0)) / 60.0)::numeric, 2),
                  'k0', f.kind,
                  'm', CASE WHEN f.status = 'faulted' OR COALESCE(f.stopped_reason, '') LIKE 'fault.%' THEN NULL
                            ELSE round((extract(epoch FROM (LEAST(COALESCE(f.ended_at, v_cut), v_cut) - f.started_at)) / 60.0)::numeric, 2) END,
                  'cen', NOT (f.ended_at IS NOT NULL AND f.ended_at <= v_cut AND f.stopped_reason = 'completed'),
                  'end', CASE WHEN f.ended_at IS NULL OR f.ended_at > v_cut THEN 'running'
                              ELSE COALESCE(f.stopped_reason, f.status) END),
           'stall', f.stall, 'started_at', f.started_at, 'soc_start', f.soc_start)), '{}'::jsonb)
    INTO v_fs
    FROM (SELECT DISTINCT ON (os.vehicle_id) os.vehicle_id::text AS id, os.started_at, os.ended_at, os.stopped_reason,
                 os.status::text AS status, os.stall_id::text AS stall, st.stall_type::text AS kind, os.soc_start
            FROM ocpp_sessions os JOIN stalls st ON st.id = os.stall_id
           WHERE os.sim_run_id = s.sim_run_id AND os.vehicle_id IS NOT NULL
             AND os.started_at >= v_t0 AND os.started_at < v_cut AND st.stall_type::text IN ('dcfc', 'l2')
           ORDER BY os.vehicle_id, os.started_at, os.id) f;

  SELECT COALESCE(jsonb_object_agg(c.id, COALESCE(v_fs #> ARRAY[c.id, 'j'], jsonb_build_object('s0', NULL))), '{}'::jsonb)
    INTO v_cars
    FROM (SELECT x.value ->> 'id' AS id FROM jsonb_array_elements(COALESCE(s.state -> 'cars', '[]'::jsonb)) x) c;

  SELECT COALESCE(jsonb_object_agg(i.id, q.j), '{}'::jsonb)
    INTO v_inb
    FROM (SELECT x.value AS e, x.value ->> 'id' AS id
            FROM jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) x) i
    JOIN vehicles v ON v.id::text = i.id
    LEFT JOIN LATERAL (SELECT d.actual_return_at, d.soc_at_return_pct FROM ottoq_vehicle_dispatches d
                        WHERE d.sim_run_id = s.sim_run_id AND d.vehicle_id = v.id AND d.dispatched_at <= v_t0
                        ORDER BY d.dispatched_at DESC LIMIT 1) d ON true
    CROSS JOIN LATERAL (SELECT (d.actual_return_at IS NOT NULL AND d.actual_return_at >= v_t0
                                AND d.actual_return_at <= v_cut) AS arrived) a
    CROSS JOIN LATERAL (SELECT CASE WHEN a.arrived THEN COALESCE(d.soc_at_return_pct, (i.e ->> 'soc')::numeric)
                                    ELSE (i.e ->> 'soc')::numeric END AS soc,
                               public.ottoq_effective_target_soc_at(v.id, v_t0) AS tgt) b
    LEFT JOIN LATERAL (SELECT vn.dispatch_due_at, vn.urgency FROM ottoq_visit_needs vn
                        WHERE a.arrived AND vn.vehicle_id = v.id AND vn.sim_run_id = s.sim_run_id
                          AND vn.arrived_at >= d.actual_return_at - interval '2 minutes' AND vn.arrived_at <= v_cut
                        ORDER BY vn.arrived_at, vn.created_at LIMIT 1) vn ON true
    CROSS JOIN LATERAL (SELECT COALESCE(v_fs #> ARRAY[i.id, 'j'], '{}'::jsonb) || jsonb_build_object(
        'arrived', a.arrived,
        'eta', CASE WHEN a.arrived THEN round((extract(epoch FROM (d.actual_return_at - v_t0)) / 60.0)::numeric, 2)
                    ELSE round(GREATEST(COALESCE((i.e ->> 'eta')::numeric, 0), v_obs), 2) END,
        'soc', round(b.soc, 1),
        'g', round(GREATEST(b.tgt - b.soc, 1), 2),
        'md', public.ottoq_charge_minutes_learned_with(v_model, 'dcfc', v.battery_capacity_kwh, b.soc, b.tgt, v_kw_d, v.inlet_max_kw),
        'ml', public.ottoq_charge_minutes_learned_with(v_model, 'l2', v.battery_capacity_kwh, b.soc, b.tgt, v_kw_l, v.inlet_max_kw),
        'sd', public.ottoq_charge_time_log_sd(v_model, 'dcfc', b.soc),
        'sl', public.ottoq_charge_time_log_sd(v_model, 'l2', b.soc),
        'due', CASE WHEN vn.dispatch_due_at IS NOT NULL
                    THEN round((extract(epoch FROM (vn.dispatch_due_at - v_t0)) / 60.0)::numeric, 2) END,
        'imm', COALESCE(vn.urgency = 'immediate_dispatch', false)) AS j) q;

  -- the cars the check did not see that joined the line: home inside the window owing a charge, or in the depot and
  -- charged on a charger the check modelled
  SELECT COALESCE(jsonb_agg(z.j ORDER BY (z.j ->> 'eta')::numeric, z.j ->> 'id'), '[]'::jsonb)
    INTO v_app
    FROM (
      SELECT COALESCE(fs.f -> 'j', '{}'::jsonb) || jsonb_build_object(
               'id', v.id::text, 'src', 'appeared', 'how', CASE WHEN rt.actual_return_at IS NOT NULL THEN 'returned' ELSE 'at_depot' END,
               'eta', round((extract(epoch FROM (COALESCE(rt.actual_return_at, fs.plug_at) - v_t0)) / 60.0)::numeric, 2),
               'esd', 0, 'trip', 0, 'w', 0, 'soc', round(b.soc, 1), 'g', round(GREATEST(b.tgt - b.soc, 1), 2),
               'imm', COALESCE(vn.urgency = 'immediate_dispatch', false),
               'due', CASE WHEN vn.dispatch_due_at IS NOT NULL
                           THEN round((extract(epoch FROM (vn.dispatch_due_at - v_t0)) / 60.0)::numeric, 2) END,
               'dok', public.ottoq_charge_kind_compatible(v.id, s.depot_id, 'dcfc'),
               'lok', public.ottoq_charge_kind_compatible(v.id, s.depot_id, 'l2'),
               'md', public.ottoq_charge_minutes_learned_with(v_model, 'dcfc', v.battery_capacity_kwh, b.soc, b.tgt, v_kw_d, v.inlet_max_kw),
               'ml', public.ottoq_charge_minutes_learned_with(v_model, 'l2', v.battery_capacity_kwh, b.soc, b.tgt, v_kw_l, v.inlet_max_kw),
               'sd', public.ottoq_charge_time_log_sd(v_model, 'dcfc', b.soc),
               'sl', public.ottoq_charge_time_log_sd(v_model, 'l2', b.soc)) AS j
        FROM (SELECT k.key AS id FROM jsonb_each(v_fs) k
               WHERE k.key <> ALL (v_ids)
                 AND ((k.value ->> 'stall') = ANY (v_ch_ids) OR (k.value ->> 'stall') = ANY (v_back_ids))
              UNION
              SELECT d.vehicle_id::text FROM ottoq_vehicle_dispatches d
               WHERE d.sim_run_id = s.sim_run_id AND d.actual_return_at > v_t0 AND d.actual_return_at <= v_cut
                 AND d.vehicle_id::text <> ALL (v_ids)
                 -- a car whose first charge was on a charger the check left out never competed for the ones it modelled
                 AND NOT (v_fs ? d.vehicle_id::text
                          AND NOT ((v_fs #>> ARRAY[d.vehicle_id::text, 'stall']) = ANY (v_ch_ids)
                                   OR (v_fs #>> ARRAY[d.vehicle_id::text, 'stall']) = ANY (v_back_ids)))) cand
        JOIN vehicles v ON v.id::text = cand.id AND v.home_depot_id = s.depot_id AND v.category = 'autonomous'
        CROSS JOIN LATERAL (SELECT v_fs -> cand.id AS f, (v_fs #>> ARRAY[cand.id, 'started_at'])::timestamptz AS plug_at,
                                   (v_fs #>> ARRAY[cand.id, 'soc_start'])::numeric AS soc_start) fs
        LEFT JOIN LATERAL (SELECT d.actual_return_at, d.soc_at_return_pct FROM ottoq_vehicle_dispatches d
                            WHERE d.sim_run_id = s.sim_run_id AND d.vehicle_id = v.id AND d.actual_return_at > v_t0
                              AND d.actual_return_at <= COALESCE(fs.plug_at, v_cut)
                            ORDER BY d.actual_return_at DESC LIMIT 1) rt ON true
        CROSS JOIN LATERAL (SELECT COALESCE(rt.soc_at_return_pct, fs.soc_start) AS soc,
                                   public.ottoq_effective_target_soc_at(v.id, v_t0) AS tgt) b
        LEFT JOIN LATERAL (SELECT vn.dispatch_due_at, vn.urgency FROM ottoq_visit_needs vn
                            WHERE vn.vehicle_id = v.id AND vn.sim_run_id = s.sim_run_id
                              AND vn.arrived_at <= COALESCE(rt.actual_return_at, fs.plug_at) + interval '2 minutes'
                            ORDER BY vn.arrived_at DESC, vn.created_at DESC LIMIT 1) vn ON true
       WHERE COALESCE(rt.actual_return_at, fs.plug_at) IS NOT NULL AND b.soc IS NOT NULL AND b.soc < b.tgt - 1
         AND v.battery_capacity_kwh IS NOT NULL) z;

  RETURN jsonb_build_object(
    'v', 1, 'order_id', p_order_id, 'window_min', COALESCE(p_window_min, 90), 'observed_min', v_obs,
    'run_status', v_status, 'cut', v_cut,
    'cars', v_cars, 'inbound', v_inb, 'appeared', v_app, 'chargers', v_ch, 'back', v_back,
    'faults', v_faults, 'unmodeled_sessions', v_unmod);
END $fn$;

-- ══ (e) what an order changed, how each forecast fared, how close the simulator came ═══════════════════════════════════
CREATE FUNCTION public.ottoq_charge_order_moves(p_state jsonb, p_kernel jsonb, p_agent jsonb)
RETURNS text[]
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0621: what an order changed in the expected future, read from the two traced schedules (ottoq_charge_line_schedule
  -- with p_trace) of the same state. due_rescue_fast / due_rescue: a car late in the kernel's order made ready by its due
  -- time, on a fast charger or not. low_battery_on_l2: a car under 45% put on an L2 in the order's window where the
  -- kernel's order did not. top_off_ahead: a car at 80% or more seated in the window where the kernel's order did not.
  -- late_car_first: a car already past its due time seated in the window where the kernel's order did not. kind_swap: a
  -- car both seat in the window, on the other kind. reorder_only: the window's seats differ and none of the above.
  WITH lim AS (SELECT COALESCE((p_state ->> 'ttl_min')::numeric, 0) AS ttl),
  c AS (SELECT x.value ->> 'id' AS id, (x.value ->> 'soc')::numeric AS soc, (x.value ->> 'due')::numeric AS due
          FROM jsonb_array_elements(COALESCE(p_state -> 'cars', '[]'::jsonb)) x
        UNION ALL
        SELECT x.value ->> 'id', (x.value ->> 'soc')::numeric, (x.value ->> 'due')::numeric
          FROM jsonb_array_elements(COALESCE(p_state -> 'inbound', '[]'::jsonb)) x),
  k AS (SELECT x.value ->> 'id' AS id, (x.value ->> 's0')::numeric AS s0, x.value ->> 'k0' AS k0, (x.value ->> 'r')::numeric AS r
          FROM jsonb_array_elements(COALESCE(p_kernel -> 'seats', '[]'::jsonb)) x),
  a AS (SELECT x.value ->> 'id' AS id, (x.value ->> 's0')::numeric AS s0, x.value ->> 'k0' AS k0, (x.value ->> 'r')::numeric AS r,
               x.value ->> 'k' AS k
          FROM jsonb_array_elements(COALESCE(p_agent -> 'seats', '[]'::jsonb)) x),
  j AS (SELECT c.soc, c.due, k.k0 AS kk0, COALESCE(k.r, 1e9) AS kr, a.k0 AS ak0, COALESCE(a.r, 1e9) AS ar, a.k AS ak,
               COALESCE(k.s0 < lim.ttl, false) AS k_in, COALESCE(a.s0 < lim.ttl, false) AS a_in
          FROM c CROSS JOIN lim LEFT JOIN k ON k.id = c.id LEFT JOIN a ON a.id = c.id),
  t AS (SELECT unnest(ARRAY[
          CASE WHEN j.due IS NOT NULL AND j.kr > j.due AND j.ar <= j.due AND j.ak = 'dcfc' THEN 'due_rescue_fast' END,
          CASE WHEN j.due IS NOT NULL AND j.kr > j.due AND j.ar <= j.due AND j.ak IS DISTINCT FROM 'dcfc' THEN 'due_rescue' END,
          CASE WHEN j.soc < 45 AND j.a_in AND j.ak0 = 'l2' AND NOT (j.k_in AND j.kk0 = 'l2') THEN 'low_battery_on_l2' END,
          CASE WHEN j.soc >= 80 AND j.a_in AND NOT j.k_in THEN 'top_off_ahead' END,
          CASE WHEN j.due IS NOT NULL AND j.due <= 0 AND j.a_in AND NOT j.k_in THEN 'late_car_first' END,
          CASE WHEN j.a_in AND j.k_in AND j.ak0 IS DISTINCT FROM j.kk0 THEN 'kind_swap' END]) AS tag
          FROM j)
  SELECT CASE WHEN EXISTS (SELECT 1 FROM t WHERE t.tag IS NOT NULL)
              THEN ARRAY(SELECT DISTINCT t.tag FROM t WHERE t.tag IS NOT NULL ORDER BY t.tag)
              WHEN (p_kernel -> 'first') IS DISTINCT FROM (p_agent -> 'first') THEN ARRAY['reorder_only']
              ELSE '{}'::text[] END
$fn$;

CREATE FUNCTION public.ottoq_charge_order_forecast_errors(p_state jsonb, p_real jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0621: each forecast the check made against what came, as sums, so they aggregate across orders exactly. arrivals: a
  -- car the check saw coming home (forecast: to be called home at the learned reserve; returning: driving home): minutes
  -- late (+) or early (-); for a forecast, the error in units of the spread its futures sampled (z = ln of the real over
  -- the forecast time to the reserve, over the learned drain spread), and how many fell inside that spread's 80% band
  -- (|z| <= 1.2816); no_show: due inside the window and not come. charge_times: a charge that finished, by kind, its real
  -- minutes against the check's (at the battery it really started from), as log ratio and z. running: when a charge under
  -- way at the order ended against when the check expected. appeared and faults: what the check could not see.
  WITH o AS (SELECT COALESCE((p_real ->> 'observed_min')::numeric, 0) AS w),
  ar AS (SELECT x.value ->> 'src' AS src, (x.value ->> 'eta')::numeric AS fc, COALESCE((x.value ->> 'trip')::numeric, 0) AS trip,
                COALESCE((x.value ->> 'esd')::numeric, 0) AS esd,
                COALESCE((rr.r ->> 'arrived')::boolean, false) AS arrived, (rr.r ->> 'eta')::numeric AS act
           FROM jsonb_array_elements(COALESCE(p_state -> 'inbound', '[]'::jsonb)) x
           CROSS JOIN LATERAL (SELECT p_real #> ARRAY['inbound', x.value ->> 'id'] AS r) rr),
  arz AS (SELECT ar.*, CASE WHEN ar.arrived AND ar.src = 'forecast' AND ar.esd > 0 AND ar.act > ar.trip AND ar.fc > ar.trip
                            THEN ln((ar.act - ar.trip) / (ar.fc - ar.trip)) / ar.esd END AS z
            FROM ar),
  ch AS (SELECT q.r ->> 'k0' AS k, (q.r ->> 'm')::numeric AS m,
                CASE WHEN q.r ->> 'k0' = 'dcfc' THEN COALESCE((q.ri ->> 'md')::numeric, (q.e ->> 'md')::numeric)
                     ELSE COALESCE((q.ri ->> 'ml')::numeric, (q.e ->> 'ml')::numeric) END AS fc,
                CASE WHEN q.r ->> 'k0' = 'dcfc' THEN COALESCE((q.ri ->> 'sd')::numeric, (q.e ->> 'sd')::numeric)
                     ELSE COALESCE((q.ri ->> 'sl')::numeric, (q.e ->> 'sl')::numeric) END AS sd
           FROM (SELECT x.value AS e, p_real #> ARRAY['cars', x.value ->> 'id'] AS r, NULL::jsonb AS ri
                   FROM jsonb_array_elements(COALESCE(p_state -> 'cars', '[]'::jsonb)) x
                 UNION ALL
                 SELECT x.value, p_real #> ARRAY['inbound', x.value ->> 'id'], p_real #> ARRAY['inbound', x.value ->> 'id']
                   FROM jsonb_array_elements(COALESCE(p_state -> 'inbound', '[]'::jsonb)) x) q
          WHERE jsonb_typeof(q.r -> 'm') = 'number' AND NOT COALESCE((q.r ->> 'cen')::boolean, true)
            AND q.r ->> 'k0' IN ('dcfc', 'l2')),
  chz AS (SELECT ch.k, ln(ch.m / ch.fc) AS lr, CASE WHEN ch.sd > 0 THEN ln(ch.m / ch.fc) / ch.sd END AS z
            FROM ch WHERE ch.fc > 0 AND ch.m > 0),
  rn AS (SELECT (rr.r ->> 'free')::numeric - (x.value ->> 'free')::numeric AS err
           FROM jsonb_array_elements(COALESCE(p_state -> 'chargers', '[]'::jsonb)) x
           CROSS JOIN LATERAL (SELECT p_real #> ARRAY['chargers', x.value ->> 'id'] AS r) rr
          WHERE COALESCE((x.value ->> 'free')::numeric, 0) > 0 AND jsonb_typeof(rr.r -> 'free') = 'number'
            AND NOT COALESCE((rr.r ->> 'cen')::boolean, true))
  SELECT jsonb_build_object(
    'arrivals', (SELECT jsonb_build_object(
                   'n', count(*), 'arrived', count(*) FILTER (WHERE arz.arrived),
                   'no_show', count(*) FILTER (WHERE NOT arz.arrived AND arz.fc < (SELECT o.w FROM o)),
                   'sum_err', round(COALESCE(sum(arz.act - arz.fc) FILTER (WHERE arz.arrived), 0), 2),
                   'sum_abs_err', round(COALESCE(sum(abs(arz.act - arz.fc)) FILTER (WHERE arz.arrived), 0), 2),
                   'n_z', count(arz.z), 'sum_z', round(COALESCE(sum(arz.z), 0), 4),
                   'sum_z2', round(COALESCE(sum(arz.z * arz.z), 0), 4),
                   'in_band', count(*) FILTER (WHERE abs(arz.z) <= 1.2816))
                   FROM arz),
    'charge_times', (SELECT COALESCE(jsonb_object_agg(g.k, g.j), '{}'::jsonb)
                       FROM (SELECT chz.k, jsonb_build_object(
                                      'n', count(*), 'sum_lr', round(sum(chz.lr), 4), 'sum_lr2', round(sum(chz.lr * chz.lr), 4),
                                      'n_z', count(chz.z), 'sum_z', round(COALESCE(sum(chz.z), 0), 4),
                                      'sum_z2', round(COALESCE(sum(chz.z * chz.z), 0), 4),
                                      'in_band', count(*) FILTER (WHERE abs(chz.z) <= 1.2816)) AS j
                               FROM chz GROUP BY chz.k) g),
    'running', (SELECT jsonb_build_object('n', count(*), 'sum_err', round(COALESCE(sum(rn.err), 0), 2),
                                          'sum_abs_err', round(COALESCE(sum(abs(rn.err)), 0), 2)) FROM rn),
    'appeared', jsonb_build_object(
                  'n', jsonb_array_length(COALESCE(p_real -> 'appeared', '[]'::jsonb)),
                  'returned', (SELECT count(*) FROM jsonb_array_elements(COALESCE(p_real -> 'appeared', '[]'::jsonb)) x
                                WHERE x.value ->> 'how' = 'returned')),
    'faults', jsonb_build_object('in_window', COALESCE((p_real ->> 'faults')::int, 0),
                                 'back', jsonb_array_length(COALESCE(p_real -> 'back', '[]'::jsonb))),
    'unmodeled_sessions', COALESCE((p_real ->> 'unmodeled_sessions')::int, 0))
$fn$;

CREATE FUNCTION public.ottoq_charge_order_fidelity(p_applied jsonb, p_real jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0621: the simulator against the run. p_applied is the arm that ran (the agent's order if taken, else the kernel's)
  -- replayed with what happened as its inputs; against it, when each car really first plugged in. The inputs are real
  -- here, so what is left is the simulator's own: what it does not model (bays, holds, the stall pick beyond the kind,
  -- the next order). A car the check saw that plugged in inside the window and that the replay seats inside it is
  -- compared; missed: plugged in, not in the replay's window; phantom: in the replay's window, not plugged in. Cars that
  -- joined from inside the depot are left out (they join the replay when they really plugged in).
  WITH o AS (SELECT COALESCE((p_real ->> 'observed_min')::numeric, 0) AS w),
  ac AS (SELECT c.key AS id, (c.value ->> 's0')::numeric AS s0 FROM jsonb_each(COALESCE(p_real -> 'cars', '{}'::jsonb)) c
         UNION ALL
         SELECT c.key, (c.value ->> 's0')::numeric FROM jsonb_each(COALESCE(p_real -> 'inbound', '{}'::jsonb)) c
          WHERE COALESCE((c.value ->> 'arrived')::boolean, false)
         UNION ALL
         SELECT x.value ->> 'id', (x.value ->> 's0')::numeric
           FROM jsonb_array_elements(COALESCE(p_real -> 'appeared', '[]'::jsonb)) x WHERE x.value ->> 'how' = 'returned'),
  pr AS (SELECT x.value ->> 'id' AS id, (x.value ->> 's0')::numeric AS s0
           FROM jsonb_array_elements(COALESCE(p_applied -> 'seats', '[]'::jsonb)) x),
  j AS (SELECT ac.id, ac.s0 AS act, CASE WHEN pr.s0 < o.w THEN pr.s0 END AS pred
          FROM ac CROSS JOIN o LEFT JOIN pr ON pr.id = ac.id)
  SELECT jsonb_build_object(
    'cars', count(*),
    'both', count(*) FILTER (WHERE j.act IS NOT NULL AND j.pred IS NOT NULL),
    'sum_err', round(COALESCE(sum(j.pred - j.act), 0), 2),
    'sum_abs_err', round(COALESCE(sum(abs(j.pred - j.act)), 0), 2),
    'within_5_min', count(*) FILTER (WHERE abs(j.pred - j.act) <= 5),
    'missed', count(*) FILTER (WHERE j.act IS NOT NULL AND j.pred IS NULL),
    'phantom', count(*) FILTER (WHERE j.act IS NULL AND j.pred IS NOT NULL),
    'worst', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', w.id, 'pred', round(w.pred, 1), 'act', round(w.act, 1))
                                        ORDER BY abs(w.pred - w.act) DESC, w.id)
                         FROM (SELECT * FROM j WHERE j.act IS NOT NULL AND j.pred IS NOT NULL
                                ORDER BY abs(j.pred - j.act) DESC, j.id LIMIT 3) w), '[]'::jsonb))
  FROM j
$fn$;

CREATE FUNCTION public.ottoq_hindsight_code_md5()
RETURNS text
LANGUAGE sql
STABLE
AS $fn$
  -- 0621: the md5 of the code that grades: the simulator, the comparison, the realizer, the reader and the grade's parts
  SELECT md5(string_agg(pg_get_functiondef(p::regprocedure), '' ORDER BY p))
    FROM unnest(ARRAY['public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)',
                      'public.ottoq_charge_line_compare(jsonb,jsonb)',
                      'public.ottoq_charge_line_real_minutes(jsonb,jsonb)',
                      'public.ottoq_charge_line_realize(jsonb,jsonb,text[])',
                      'public.ottoq_charge_order_realized(bigint,numeric)',
                      'public.ottoq_charge_order_moves(jsonb,jsonb,jsonb)',
                      'public.ottoq_charge_order_forecast_errors(jsonb,jsonb)',
                      'public.ottoq_charge_order_fidelity(jsonb,jsonb)',
                      'public.ottoq_charge_order_grade(bigint,numeric)',
                      'public.ottoq_charge_order_attribute(bigint)']) p
$fn$;

-- ══ (e) the grade, the attribution, and what is due ════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_order_grade(p_order_id bigint, p_window_min numeric DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0621: one checked order, graded once: the check's expected future (scenario 0 of its own rollout) and the world that
   came, each replayed both ways by the same simulator from the same state; the outcome; what the order changed; how
   each forecast fared; how close the simulator came given the real inputs. Writes only its own ledger. */
DECLARE
  v_row jsonb; s record; o record; v_real jsonb; v_full jsonb; ek jsonb; ea jsonb; hk jsonb; ha jsonb;
  v_exp jsonb; v_hind jsonb; v_reason text; v_taken boolean; v_decision boolean; v_outcome text; v_hc int;
  v_futures int; v_wins int; v_need int; v_w numeric := GREATEST(COALESCE(p_window_min, 90), 1);
BEGIN
  SELECT to_jsonb(h) INTO v_row FROM ottoq_charge_order_hindsight h WHERE h.order_id = p_order_id;
  IF v_row IS NOT NULL THEN RETURN v_row; END IF;
  SELECT * INTO s FROM ottoq_charge_order_snapshots x WHERE x.order_id = p_order_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO o FROM ottoq_agent_charge_orders x WHERE x.order_id = p_order_id;
  v_reason := COALESCE(o.projection ->> 'reason', 'unknown');
  v_taken := COALESCE(o.status IN ('accepted', 'partial'), false);
  v_decision := v_reason IN ('worse_in_expected_future', 'no_better_in_expected_future', 'not_enough_futures_won',
                             'wins_most_futures');
  v_futures := CASE WHEN (o.projection ->> 'futures') ~ '^[0-9]+$' THEN (o.projection ->> 'futures')::int END;
  v_wins := CASE WHEN (o.projection ->> 'wins') ~ '^[0-9]+$' THEN (o.projection ->> 'wins')::int END;
  v_need := CASE WHEN (o.projection ->> 'need') ~ '^[0-9]+$' THEN (o.projection ->> 'need')::int END;

  v_real := public.ottoq_charge_order_realized(p_order_id, v_w);
  ek := public.ottoq_charge_line_schedule(s.state, NULL, 0, s.seed, true);
  ea := public.ottoq_charge_line_schedule(s.state, s.agent_order, 0, s.seed, true);
  v_full := public.ottoq_charge_line_realize(s.state, v_real,
                                             ARRAY['arrivals', 'appeared', 'charge_times', 'running', 'faults']);
  hk := public.ottoq_charge_line_schedule(v_full, NULL, 0, s.seed, true);
  ha := public.ottoq_charge_line_schedule(v_full, s.agent_order, 0, s.seed, true);
  v_exp := public.ottoq_charge_line_compare(ek, ea);
  v_hind := public.ottoq_charge_line_compare(hk, ha);
  v_hc := (v_hind ->> 'cmp')::int;
  v_outcome := CASE WHEN NOT v_decision THEN
                      CASE WHEN (hk -> 'first') IS NOT DISTINCT FROM (ha -> 'first') THEN 'no_decision'
                           ELSE 'no_decision_mattered' END
                    WHEN v_taken AND v_hc > 0 THEN 'right_take'
                    WHEN v_taken AND v_hc = 0 THEN 'neutral_take'
                    WHEN v_taken THEN 'wrong_take'
                    WHEN v_hc > 0 THEN 'missed_win'
                    ELSE 'right_refusal' END;

  INSERT INTO ottoq_charge_order_hindsight
    (order_id, sim_run_id, depot_id, sim_clock, window_min, observed_min, status, reason, taken, decision, futures,
     wins, need, p_win, expected, hindsight, outcome, moves, forecast, fidelity, realized, code_md5)
  VALUES (p_order_id, s.sim_run_id, s.depot_id, s.sim_clock, v_w, COALESCE((v_real ->> 'observed_min')::numeric, 0),
          o.status, v_reason, v_taken, v_decision, v_futures, v_wins, v_need,
          CASE WHEN v_decision AND v_futures > 0 THEN round(v_wins::numeric / v_futures, 4) END,
          v_exp || jsonb_build_object('kernel', ek - ARRAY['first', 'seats'], 'agent', ea - ARRAY['first', 'seats']),
          v_hind || jsonb_build_object('kernel', hk - ARRAY['first', 'seats'], 'agent', ha - ARRAY['first', 'seats']),
          v_outcome,
          CASE WHEN v_decision OR v_outcome = 'no_decision_mattered'
               THEN public.ottoq_charge_order_moves(s.state, ek, ea) ELSE '{}'::text[] END,
          public.ottoq_charge_order_forecast_errors(s.state, v_real),
          public.ottoq_charge_order_fidelity(CASE WHEN v_taken THEN ha ELSE hk END, v_real),
          COALESCE(v_real, '{}'::jsonb), public.ottoq_hindsight_code_md5())
  ON CONFLICT (order_id) DO NOTHING;
  SELECT to_jsonb(h) INTO v_row FROM ottoq_charge_order_hindsight h WHERE h.order_id = p_order_id;
  RETURN v_row;
END $fn$;

CREATE FUNCTION public.ottoq_charge_order_attribute(p_order_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0621: why hindsight differs from the check, for one graded order. v(S) is the comparison of the agent's order with
   the kernel's, replayed with only the parts of what happened in S put in place of the forecast (all 32 subsets of the
   five, each replayed both ways, from the realized record the grade kept). A part's Shapley value is its contribution
   averaged over every order in which the parts could be put in: weight |S|! (4 - |S|)! / 5! on v(S + part) - v(S). The
   five sum, on each of cmp, on_time, lateness and flow, to v(all) - v(none) = hindsight - the expected future. */
DECLARE
  h record; s record; c_parts constant text[] := ARRAY['arrivals', 'appeared', 'charge_times', 'running', 'faults'];
  v_cmp int[] := '{}'; v_dot numeric[] := '{}'; v_dl numeric[] := '{}'; v_df numeric[] := '{}';
  mask int; b int; sz int; w numeric; st jsonb; k jsonb; a jsonb; c jsonb; v_vals jsonb := '[]'::jsonb;
  p_cmp numeric; p_dot numeric; p_dl numeric; p_df numeric; v_sh jsonb := '{}'::jsonb; v_row jsonb; up int;
BEGIN
  SELECT to_jsonb(x) INTO v_row FROM ottoq_charge_order_attribution x WHERE x.order_id = p_order_id;
  IF v_row IS NOT NULL THEN RETURN v_row; END IF;
  SELECT * INTO h FROM ottoq_charge_order_hindsight x WHERE x.order_id = p_order_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO s FROM ottoq_charge_order_snapshots x WHERE x.order_id = p_order_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  FOR mask IN 0 .. 31 LOOP
    st := public.ottoq_charge_line_realize(s.state, h.realized,
            ARRAY(SELECT c_parts[g + 1] FROM generate_series(0, 4) g WHERE (mask >> g) & 1 = 1));
    k := public.ottoq_charge_line_simulate(st, NULL, 0, s.seed);
    a := public.ottoq_charge_line_simulate(st, s.agent_order, 0, s.seed);
    c := public.ottoq_charge_line_compare(k, a);
    v_cmp[mask + 1] := (c ->> 'cmp')::int;
    v_dot[mask + 1] := (c ->> 'd_on_time')::numeric;
    v_dl[mask + 1] := (c ->> 'd_late')::numeric;
    v_df[mask + 1] := (c ->> 'd_flow')::numeric;
    v_vals := v_vals || jsonb_build_array(jsonb_build_array(v_cmp[mask + 1], v_dot[mask + 1], v_dl[mask + 1], v_df[mask + 1]));
  END LOOP;
  FOR b IN 0 .. 4 LOOP
    p_cmp := 0; p_dot := 0; p_dl := 0; p_df := 0;
    FOR mask IN 0 .. 31 LOOP
      CONTINUE WHEN (mask >> b) & 1 = 1;
      sz := (mask & 1) + ((mask >> 1) & 1) + ((mask >> 2) & 1) + ((mask >> 3) & 1) + ((mask >> 4) & 1);
      w := (CASE sz WHEN 0 THEN 24 WHEN 1 THEN 6 WHEN 2 THEN 4 WHEN 3 THEN 6 ELSE 24 END)::numeric / 120;
      up := (mask | (1 << b)) + 1;
      p_cmp := p_cmp + w * (v_cmp[up] - v_cmp[mask + 1]);
      p_dot := p_dot + w * (v_dot[up] - v_dot[mask + 1]);
      p_dl := p_dl + w * (v_dl[up] - v_dl[mask + 1]);
      p_df := p_df + w * (v_df[up] - v_df[mask + 1]);
    END LOOP;
    v_sh := v_sh || jsonb_build_object(c_parts[b + 1], jsonb_build_object(
              'cmp', round(p_cmp, 4), 'on_time', round(p_dot, 4), 'late', round(p_dl, 4), 'flow', round(p_df, 4)));
  END LOOP;
  INSERT INTO ottoq_charge_order_attribution
    (order_id, sim_run_id, depot_id, parts, subset_values, shapley, verdict_changed, code_md5)
  VALUES (p_order_id, s.sim_run_id, s.depot_id, c_parts, v_vals, v_sh,
          sign(v_cmp[32]) IS DISTINCT FROM sign(v_cmp[1]), public.ottoq_hindsight_code_md5())
  ON CONFLICT (order_id) DO NOTHING;
  SELECT to_jsonb(x) INTO v_row FROM ottoq_charge_order_attribution x WHERE x.order_id = p_order_id;
  RETURN v_row;
END $fn$;

CREATE FUNCTION public.ottoq_charge_order_grade_pending(p_sim_run_id uuid DEFAULT NULL, p_limit integer DEFAULT 3,
                                                         p_attribute boolean DEFAULT false, p_budget_ms integer DEFAULT 2000,
                                                         p_window_min numeric DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0621: grade, oldest first, the checked orders whose window has closed (their run's clock is p_window_min past them, or
   their run is no longer running), on one run or all, within p_budget_ms; with p_attribute, then attribute the graded
   decisions that have no attribution yet, those whose verdict hindsight changed first. A run whose working rows were
   purged is skipped: what happened can no longer be read. */
DECLARE
  t0 timestamptz := clock_timestamp(); r record; v_graded int := 0; v_attr int := 0; v_err int := 0; v_last text;
  v_lim int := GREATEST(COALESCE(p_limit, 3), 0); v_w numeric := GREATEST(COALESCE(p_window_min, 90), 1);
  v_budget numeric := GREATEST(COALESCE(p_budget_ms, 2000), 0);
BEGIN
  FOR r IN
    SELECT s.order_id
      FROM ottoq_charge_order_snapshots s
      JOIN ottoq_sim_runs x ON x.sim_run_id = s.sim_run_id
     WHERE (p_sim_run_id IS NULL OR s.sim_run_id = p_sim_run_id)
       AND x.purged_at IS NULL
       AND NOT EXISTS (SELECT 1 FROM ottoq_charge_order_hindsight h WHERE h.order_id = s.order_id)
       AND (x.status NOT IN ('running', 'paused') OR x.sim_clock_current >= s.sim_clock + make_interval(secs => v_w * 60))
     ORDER BY s.order_id
     LIMIT v_lim
  LOOP
    EXIT WHEN extract(epoch FROM clock_timestamp() - t0) * 1000 > v_budget;
    BEGIN
      PERFORM public.ottoq_charge_order_grade(r.order_id, v_w);
      v_graded := v_graded + 1;
    EXCEPTION WHEN OTHERS THEN
      v_err := v_err + 1; v_last := left(SQLERRM, 200);
    END;
  END LOOP;
  IF COALESCE(p_attribute, false) THEN
    FOR r IN
      SELECT h.order_id
        FROM ottoq_charge_order_hindsight h
       WHERE (p_sim_run_id IS NULL OR h.sim_run_id = p_sim_run_id) AND h.decision
         AND NOT EXISTS (SELECT 1 FROM ottoq_charge_order_attribution a WHERE a.order_id = h.order_id)
       ORDER BY (sign((h.hindsight ->> 'cmp')::int) IS DISTINCT FROM sign((h.expected ->> 'cmp')::int)) DESC, h.order_id
       LIMIT GREATEST(v_lim, 1)
    LOOP
      EXIT WHEN extract(epoch FROM clock_timestamp() - t0) * 1000 > v_budget;
      BEGIN
        PERFORM public.ottoq_charge_order_attribute(r.order_id);
        v_attr := v_attr + 1;
      EXCEPTION WHEN OTHERS THEN
        v_err := v_err + 1; v_last := left(SQLERRM, 200);
      END;
    END LOOP;
  END IF;
  RETURN jsonb_build_object(
    'graded', v_graded, 'attributed', v_attr, 'errors', v_err, 'last_error', v_last,
    'due', (SELECT count(*) FROM ottoq_charge_order_snapshots s JOIN ottoq_sim_runs x ON x.sim_run_id = s.sim_run_id
             WHERE (p_sim_run_id IS NULL OR s.sim_run_id = p_sim_run_id) AND x.purged_at IS NULL
               AND NOT EXISTS (SELECT 1 FROM ottoq_charge_order_hindsight h WHERE h.order_id = s.order_id)
               AND (x.status NOT IN ('running', 'paused')
                    OR x.sim_clock_current >= s.sim_clock + make_interval(secs => v_w * 60))),
    'ms', round(extract(epoch FROM clock_timestamp() - t0) * 1000));
END $fn$;

-- ══ (f) the agent's track record ═══════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_order_track_record(p_sim_run_id uuid, p_depot_id uuid, p_days integer DEFAULT 7)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  -- 0621: how the agent's orders did in what actually happened (ottoq_charge_order_hindsight), for its board: on this
  -- run and at this depot over p_days, by outcome; each move with how often an order making it beat the kernel's own
  -- order in hindsight, taken or not; and what most often made the check wrong (the part with the largest Shapley mass on
  -- the verdict, ottoq_charge_order_attribution). Read-only.
  WITH h AS (
    SELECT x.* FROM ottoq_charge_order_hindsight x
     WHERE x.depot_id IS NOT DISTINCT FROM p_depot_id
       AND x.graded_at >= now() - make_interval(days => GREATEST(COALESCE(p_days, 7), 1))
  ), att AS (
    SELECT p.key AS part, sum(abs((p.value ->> 'cmp')::numeric)) AS mass, count(*) FILTER (WHERE a.verdict_changed) AS n
      FROM ottoq_charge_order_attribution a JOIN h ON h.order_id = a.order_id
      CROSS JOIN LATERAL jsonb_each(a.shapley) p
     GROUP BY p.key
  )
  SELECT jsonb_build_object(
    'window_min', COALESCE((SELECT max(h.window_min) FROM h), 90),
    'this_run', (SELECT jsonb_build_object(
                   'graded', count(*), 'decisions', count(*) FILTER (WHERE h.decision),
                   'taken', jsonb_build_object('n', count(*) FILTER (WHERE h.decision AND h.taken),
                                               'won', count(*) FILTER (WHERE h.outcome = 'right_take'),
                                               'tied', count(*) FILTER (WHERE h.outcome = 'neutral_take'),
                                               'lost', count(*) FILTER (WHERE h.outcome = 'wrong_take')),
                   'refused', jsonb_build_object('n', count(*) FILTER (WHERE h.decision AND NOT h.taken),
                                                 'would_have_won', count(*) FILTER (WHERE h.outcome = 'missed_win')),
                   'no_decision', count(*) FILTER (WHERE NOT h.decision))
                   FROM h WHERE h.sim_run_id = p_sim_run_id),
    'depot_days', GREATEST(COALESCE(p_days, 7), 1),
    'depot', (SELECT jsonb_build_object(
                'graded', count(*), 'decisions', count(*) FILTER (WHERE h.decision),
                'taken', jsonb_build_object('n', count(*) FILTER (WHERE h.decision AND h.taken),
                                            'won', count(*) FILTER (WHERE h.outcome = 'right_take'),
                                            'tied', count(*) FILTER (WHERE h.outcome = 'neutral_take'),
                                            'lost', count(*) FILTER (WHERE h.outcome = 'wrong_take')),
                'refused', jsonb_build_object('n', count(*) FILTER (WHERE h.decision AND NOT h.taken),
                                              'would_have_won', count(*) FILTER (WHERE h.outcome = 'missed_win')),
                'no_decision', count(*) FILTER (WHERE NOT h.decision),
                -- the check's own win probability scored against hindsight: 0 is perfect, 0.25 is a coin
                'brier', round(avg(power(h.p_win - CASE WHEN (h.hindsight ->> 'cmp')::int > 0 THEN 1 ELSE 0 END, 2))
                                 FILTER (WHERE h.decision AND h.p_win IS NOT NULL), 3))
                FROM h),
    'moves', (SELECT COALESCE(jsonb_object_agg(m.tag, jsonb_build_object('orders', m.n, 'taken', m.taken, 'won', m.won,
                                                                        'tied', m.tied, 'lost', m.lost)), '{}'::jsonb)
                FROM (SELECT t.tag, count(*) AS n, count(*) FILTER (WHERE h.taken) AS taken,
                             count(*) FILTER (WHERE (h.hindsight ->> 'cmp')::int > 0) AS won,
                             count(*) FILTER (WHERE (h.hindsight ->> 'cmp')::int = 0) AS tied,
                             count(*) FILTER (WHERE (h.hindsight ->> 'cmp')::int < 0) AS lost
                        FROM h CROSS JOIN LATERAL unnest(h.moves) AS t(tag)
                       WHERE h.decision
                       GROUP BY t.tag) m),
    'check_wrong_by', (SELECT jsonb_build_object('part', z.part, 'share', z.share, 'verdicts_changed', z.changed)
                         FROM (SELECT att.part, round(att.mass / NULLIF(sum(att.mass) OVER (), 0), 2) AS share,
                                      (SELECT count(*) FROM ottoq_charge_order_attribution a JOIN h ON h.order_id = a.order_id
                                        WHERE a.verdict_changed) AS changed
                                 FROM att ORDER BY att.mass DESC, att.part LIMIT 1) z
                        WHERE z.share IS NOT NULL AND z.share > 0))
$fn$;

-- ══ (g) the check's self-assessment, for the research wing ═════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_arbiter_self_assessment(p_depot_id uuid, p_since timestamptz DEFAULT now() - interval '7 days')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0621: the check's self-assessment from the hindsight ledger, read-only. How its verdicts did (the confusion of taken
   and refused against hindsight); how good its win probability is (Brier score against the base rate's, and by band);
   how each bar from 0.5 to 1.0 would have done on the same orders (an order is taken at bar b when it won the expected
   future and at least ceil(b x futures) of all; sums over orders rank bars, they do not add up to a day, because orders
   overlap); each forecast's bias, spread and coverage; the simulator's fidelity given the real inputs; the Shapley mass
   of each part of what happened on the verdicts; the moves; and the improvement areas these point to, ranked by how many
   orders they touch, each with its evidence and in plain words. Every area is a finding for a person: OTTO-Q changes no
   rule, dial, bar or model from it (CLAUDE.md rule 10). */
DECLARE
  v_n int; v_dec int; v_out jsonb := '{}'::jsonb; v_areas jsonb := '[]'::jsonb; v jsonb; x record;
  v_brier numeric; v_base numeric; v_wr numeric; v_cur numeric;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE h.decision) INTO v_n, v_dec
    FROM ottoq_charge_order_hindsight h WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since;
  v_out := jsonb_build_object('depot_id', p_depot_id, 'since', p_since, 'graded', v_n, 'decisions', v_dec);
  IF v_n = 0 THEN
    RETURN v_out || jsonb_build_object('improvement_areas', '[]'::jsonb);
  END IF;

  -- the verdicts against hindsight
  SELECT jsonb_build_object(
           'right_take', count(*) FILTER (WHERE h.outcome = 'right_take'),
           'neutral_take', count(*) FILTER (WHERE h.outcome = 'neutral_take'),
           'wrong_take', count(*) FILTER (WHERE h.outcome = 'wrong_take'),
           'missed_win', count(*) FILTER (WHERE h.outcome = 'missed_win'),
           'right_refusal', count(*) FILTER (WHERE h.outcome = 'right_refusal'),
           'no_decision', count(*) FILTER (WHERE h.outcome = 'no_decision'),
           'no_decision_mattered', count(*) FILTER (WHERE h.outcome = 'no_decision_mattered'),
           'expected_agreed', count(*) FILTER (WHERE h.decision AND sign((h.expected ->> 'cmp')::int)
                                                                     = sign((h.hindsight ->> 'cmp')::int)),
           'by_reason', (SELECT jsonb_object_agg(q.reason, q.j) FROM (
                           SELECT h2.reason, jsonb_build_object('n', count(*),
                                    'hindsight_won', count(*) FILTER (WHERE (h2.hindsight ->> 'cmp')::int > 0),
                                    'hindsight_lost', count(*) FILTER (WHERE (h2.hindsight ->> 'cmp')::int < 0)) AS j
                             FROM ottoq_charge_order_hindsight h2
                            WHERE h2.depot_id IS NOT DISTINCT FROM p_depot_id AND h2.graded_at >= p_since
                            GROUP BY h2.reason) q))
    INTO v
    FROM ottoq_charge_order_hindsight h WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since;
  v_out := v_out || jsonb_build_object('verdicts', v);

  -- the win probability against hindsight: Brier, the base rate's Brier, and by band
  SELECT round(avg(power(h.p_win - y.won, 2)), 4), round(avg(y.won), 4)
    INTO v_brier, v_wr
    FROM ottoq_charge_order_hindsight h
    CROSS JOIN LATERAL (SELECT CASE WHEN (h.hindsight ->> 'cmp')::int > 0 THEN 1 ELSE 0 END AS won) y
   WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since AND h.decision AND h.p_win IS NOT NULL;
  v_base := round(v_wr * (1 - v_wr), 4);
  SELECT COALESCE(jsonb_agg(jsonb_build_object('band', b.band, 'orders', b.n, 'mean_p_win', b.p, 'won_in_hindsight', b.w)
                            ORDER BY b.lo), '[]'::jsonb)
    INTO v
    FROM (SELECT z.band, z.lo, count(*) AS n, round(avg(h.p_win), 3) AS p,
                 round(avg(CASE WHEN (h.hindsight ->> 'cmp')::int > 0 THEN 1 ELSE 0 END), 3) AS w
            FROM ottoq_charge_order_hindsight h
            CROSS JOIN LATERAL (SELECT CASE WHEN h.p_win < 0.5 THEN '0-0.5' WHEN h.p_win < 0.8 THEN '0.5-0.8'
                                            WHEN h.p_win < 0.9 THEN '0.8-0.9' ELSE '0.9-1' END AS band,
                                       CASE WHEN h.p_win < 0.5 THEN 0 WHEN h.p_win < 0.8 THEN 1
                                            WHEN h.p_win < 0.9 THEN 2 ELSE 3 END AS lo) z
           WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since AND h.decision AND h.p_win IS NOT NULL
           GROUP BY z.band, z.lo) b;
  v_out := v_out || jsonb_build_object('calibration', jsonb_build_object(
             'brier', v_brier, 'base_rate_won', v_wr, 'brier_of_base_rate', v_base, 'bands', v));

  -- the bar: how each would have done on the same orders
  -- the bar the check ran under, as each snapshot recorded it (not need / futures: 10 of 12 is a bar of 0.8)
  SELECT round(avg(s.win_frac), 2) INTO v_cur
    FROM ottoq_charge_order_hindsight h JOIN ottoq_charge_order_snapshots s ON s.order_id = h.order_id
   WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since AND h.decision;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('win_frac', b.wf, 'taken', b.taken, 'won', b.won, 'tied', b.tied,
                                               'lost', b.lost, 'd_on_time', b.dot, 'd_late', b.dl, 'd_flow', b.df)
                            ORDER BY b.wf), '[]'::jsonb)
    INTO v
    FROM (SELECT wf.wf, count(*) FILTER (WHERE tk.take) AS taken,
                 count(*) FILTER (WHERE tk.take AND (h.hindsight ->> 'cmp')::int > 0) AS won,
                 count(*) FILTER (WHERE tk.take AND (h.hindsight ->> 'cmp')::int = 0) AS tied,
                 count(*) FILTER (WHERE tk.take AND (h.hindsight ->> 'cmp')::int < 0) AS lost,
                 COALESCE(sum((h.hindsight ->> 'd_on_time')::numeric) FILTER (WHERE tk.take), 0) AS dot,
                 round(COALESCE(sum((h.hindsight ->> 'd_late')::numeric) FILTER (WHERE tk.take), 0), 1) AS dl,
                 round(COALESCE(sum((h.hindsight ->> 'd_flow')::numeric) FILTER (WHERE tk.take), 0), 1) AS df
            FROM (VALUES (0.5), (0.6), (0.7), (0.8), (0.9), (1.0)) wf(wf)
            CROSS JOIN ottoq_charge_order_hindsight h
            CROSS JOIN LATERAL (SELECT (h.expected ->> 'cmp')::int = 1
                                       AND COALESCE(h.wins, 0) >= ceil(wf.wf * COALESCE(h.futures, 1)) AS take) tk
           WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since AND h.decision
           GROUP BY wf.wf) b;
  v_out := v_out || jsonb_build_object('bar', jsonb_build_object('current_win_frac', v_cur, 'sweep', v));

  -- each forecast against what came
  SELECT jsonb_build_object(
    'arrivals', jsonb_build_object(
       'seen', sum((h.forecast #>> '{arrivals,n}')::numeric), 'arrived', sum((h.forecast #>> '{arrivals,arrived}')::numeric),
       'no_show', sum((h.forecast #>> '{arrivals,no_show}')::numeric),
       'mean_err_min', round(sum((h.forecast #>> '{arrivals,sum_err}')::numeric)
                             / NULLIF(sum((h.forecast #>> '{arrivals,arrived}')::numeric), 0), 2),
       'mae_min', round(sum((h.forecast #>> '{arrivals,sum_abs_err}')::numeric)
                        / NULLIF(sum((h.forecast #>> '{arrivals,arrived}')::numeric), 0), 2),
       'n_z', sum((h.forecast #>> '{arrivals,n_z}')::numeric),
       'z_mean', round(sum((h.forecast #>> '{arrivals,sum_z}')::numeric) / NULLIF(sum((h.forecast #>> '{arrivals,n_z}')::numeric), 0), 3),
       'z_sd', round(sqrt(GREATEST(sum((h.forecast #>> '{arrivals,sum_z2}')::numeric) / NULLIF(sum((h.forecast #>> '{arrivals,n_z}')::numeric), 0)
                                   - power(sum((h.forecast #>> '{arrivals,sum_z}')::numeric)
                                           / NULLIF(sum((h.forecast #>> '{arrivals,n_z}')::numeric), 0), 2), 0)), 3),
       'in_80pct_band', round(sum((h.forecast #>> '{arrivals,in_band}')::numeric)
                              / NULLIF(sum((h.forecast #>> '{arrivals,n_z}')::numeric), 0), 3)),
    'running', jsonb_build_object(
       'n', sum((h.forecast #>> '{running,n}')::numeric),
       'mean_err_min', round(sum((h.forecast #>> '{running,sum_err}')::numeric) / NULLIF(sum((h.forecast #>> '{running,n}')::numeric), 0), 2),
       'mae_min', round(sum((h.forecast #>> '{running,sum_abs_err}')::numeric) / NULLIF(sum((h.forecast #>> '{running,n}')::numeric), 0), 2)),
    'appeared_per_order', round(avg((h.forecast #>> '{appeared,n}')::numeric), 2),
    'appeared_returned_per_order', round(avg((h.forecast #>> '{appeared,returned}')::numeric), 2),
    'orders_with_a_fault', count(*) FILTER (WHERE (h.forecast #>> '{faults,in_window}')::int > 0),
    'unmodeled_sessions_per_order', round(avg((h.forecast ->> 'unmodeled_sessions')::numeric), 2))
    INTO v
    FROM ottoq_charge_order_hindsight h WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since;
  v_out := v_out || jsonb_build_object('forecasts', v || jsonb_build_object('charge_times', (
    SELECT COALESCE(jsonb_object_agg(c.k, jsonb_build_object(
             'n', c.n, 'factor_off_by', round(exp(c.slr / c.n), 3),
             'log_sd', round(sqrt(GREATEST(c.slr2 / c.n - power(c.slr / c.n, 2), 0)), 3),
             'z_mean', round(c.sz / NULLIF(c.nz, 0), 3),
             'z_sd', round(sqrt(GREATEST(c.sz2 / NULLIF(c.nz, 0) - power(c.sz / NULLIF(c.nz, 0), 2), 0)), 3),
             'in_80pct_band', round(c.band / NULLIF(c.nz, 0), 3))), '{}'::jsonb)
      FROM (SELECT g.key AS k, sum((g.value ->> 'n')::numeric) AS n, sum((g.value ->> 'sum_lr')::numeric) AS slr,
                   sum((g.value ->> 'sum_lr2')::numeric) AS slr2, sum((g.value ->> 'n_z')::numeric) AS nz,
                   sum((g.value ->> 'sum_z')::numeric) AS sz, sum((g.value ->> 'sum_z2')::numeric) AS sz2,
                   sum((g.value ->> 'in_band')::numeric) AS band
              FROM ottoq_charge_order_hindsight h CROSS JOIN LATERAL jsonb_each(h.forecast -> 'charge_times') g
             WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since
             GROUP BY g.key) c WHERE c.n > 0)));

  -- the simulator given the real inputs
  SELECT jsonb_build_object(
           'cars_compared', sum((h.fidelity ->> 'both')::numeric),
           'mae_min', round(sum((h.fidelity ->> 'sum_abs_err')::numeric) / NULLIF(sum((h.fidelity ->> 'both')::numeric), 0), 2),
           'bias_min', round(sum((h.fidelity ->> 'sum_err')::numeric) / NULLIF(sum((h.fidelity ->> 'both')::numeric), 0), 2),
           'within_5_min', round(sum((h.fidelity ->> 'within_5_min')::numeric) / NULLIF(sum((h.fidelity ->> 'both')::numeric), 0), 3),
           'missed', sum((h.fidelity ->> 'missed')::numeric), 'phantom', sum((h.fidelity ->> 'phantom')::numeric))
    INTO v
    FROM ottoq_charge_order_hindsight h WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since;
  v_out := v_out || jsonb_build_object('simulator', v);

  -- what made the check wrong: the Shapley mass of each part
  SELECT jsonb_build_object(
           'orders_attributed', (SELECT count(*) FROM ottoq_charge_order_attribution a JOIN ottoq_charge_order_hindsight h
                                     ON h.order_id = a.order_id
                                  WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since),
           'verdicts_changed', (SELECT count(*) FROM ottoq_charge_order_attribution a JOIN ottoq_charge_order_hindsight h
                                    ON h.order_id = a.order_id
                                 WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since
                                   AND a.verdict_changed),
           'parts', COALESCE(jsonb_object_agg(z.part, jsonb_build_object(
                      'verdict_mass', z.mass, 'verdict_share', z.share,
                      'net_on_verdict', z.net, 'on_time_mass', z.ot, 'flow_mass_min', z.fl, 'orders_moved', z.moved)), '{}'::jsonb))
    INTO v
    FROM (SELECT y.*, round(y.mass / NULLIF(sum(y.mass) OVER (), 0), 3) AS share
            FROM (SELECT p.key AS part, round(sum(abs((p.value ->> 'cmp')::numeric)), 3) AS mass,
                         round(sum((p.value ->> 'cmp')::numeric), 3) AS net,
                         round(sum(abs((p.value ->> 'on_time')::numeric)), 3) AS ot,
                         round(sum(abs((p.value ->> 'flow')::numeric)), 1) AS fl,
                         count(*) FILTER (WHERE abs((p.value ->> 'cmp')::numeric) >= 0.5) AS moved
                    FROM ottoq_charge_order_attribution a JOIN ottoq_charge_order_hindsight h ON h.order_id = a.order_id
                    CROSS JOIN LATERAL jsonb_each(a.shapley) p
                   WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since
                   GROUP BY p.key) y) z;
  v_out := v_out || jsonb_build_object('what_made_the_check_wrong', v);

  -- the moves
  SELECT COALESCE(jsonb_object_agg(m.tag, jsonb_build_object('orders', m.n, 'taken', m.taken, 'won', m.won, 'tied', m.tied,
                                                             'lost', m.lost)), '{}'::jsonb)
    INTO v
    FROM (SELECT t.tag, count(*) AS n, count(*) FILTER (WHERE h.taken) AS taken,
                 count(*) FILTER (WHERE (h.hindsight ->> 'cmp')::int > 0) AS won,
                 count(*) FILTER (WHERE (h.hindsight ->> 'cmp')::int = 0) AS tied,
                 count(*) FILTER (WHERE (h.hindsight ->> 'cmp')::int < 0) AS lost
            FROM ottoq_charge_order_hindsight h CROSS JOIN LATERAL unnest(h.moves) AS t(tag)
           WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since AND h.decision
           GROUP BY t.tag) m;
  v_out := v_out || jsonb_build_object('moves', v);

  -- ── the improvement areas: findings, ranked by how many orders they touch ──────────────────────────────────────────
  -- (1) a part of what happened that moved verdicts: the forecast the check could not make, or made badly
  FOR x IN SELECT p.key AS part, (p.value ->> 'verdict_share')::numeric AS share, (p.value ->> 'orders_moved')::int AS moved,
                  (p.value ->> 'verdict_mass')::numeric AS mass
             FROM jsonb_each(COALESCE(v_out #> '{what_made_the_check_wrong,parts}', '{}'::jsonb)) p
            WHERE (p.value ->> 'verdict_share')::numeric >= 0.15 AND (p.value ->> 'verdict_mass')::numeric >= 1
  LOOP
    v_areas := v_areas || jsonb_build_object(
      'area', 'forecast_' || x.part,
      'kind', CASE WHEN x.part IN ('appeared', 'faults') THEN 'capability_gap' ELSE 'forecast' END,
      'weight', x.moved,
      'finding', CASE x.part
        WHEN 'arrivals' THEN 'When the cars it expected home really came moved the check''s verdict more than anything '
                             'but this: the return model (0619 return_v1) times them poorly in these windows.'
        WHEN 'appeared' THEN 'Cars the check never saw coming joined the line inside the window: it sees only cars already '
                             'out at the order, not a round trip that starts after it or a car finishing in a bay. A model '
                             'of the depot''s own outflow and return cycle would let it.'
        WHEN 'charge_times' THEN 'Charges ran other than the learned clock said, enough to change verdicts: the clock '
                                 '(0619 charge_time_v1) misses a variable that matters here.'
        WHEN 'running' THEN 'Charges under way at the order ended other than the check expected.'
        ELSE 'Chargers faulted inside the window; the check''s futures never take a charger down. Sampling faults at '
             'the depot''s measured rate in the futures (the simulator takes a down window since 0621) would let it see them.'
        END,
      'evidence', jsonb_build_object('verdict_share', x.share, 'verdict_mass', x.mass, 'orders_moved', x.moved));
  END LOOP;
  -- (2) the forecasts' own calibration
  IF COALESCE((v_out #>> '{forecasts,arrivals,n_z}')::numeric, 0) >= 10 THEN
    IF abs((v_out #>> '{forecasts,arrivals,z_mean}')::numeric) > 0.5 OR (v_out #>> '{forecasts,arrivals,z_sd}')::numeric > 1.5
       OR (v_out #>> '{forecasts,arrivals,in_80pct_band}')::numeric < 0.6 THEN
      v_areas := v_areas || jsonb_build_object(
        'area', 'arrival_spread', 'kind', 'calibration', 'weight', (v_out #>> '{forecasts,arrivals,n_z}')::int,
        'finding', 'The forecast arrivals fall outside the spread the futures sample: z mean '
                   || (v_out #>> '{forecasts,arrivals,z_mean}') || ', sd ' || (v_out #>> '{forecasts,arrivals,z_sd}')
                   || ', ' || round(100 * (v_out #>> '{forecasts,arrivals,in_80pct_band}')::numeric) || '% inside an 80% band. '
                   || 'The futures are narrower (or shifted) than what comes, so the check is more sure than it should be.',
        'evidence', v_out #> '{forecasts,arrivals}');
    END IF;
  END IF;
  FOR x IN SELECT c.key AS k, c.value AS j FROM jsonb_each(COALESCE(v_out #> '{forecasts,charge_times}', '{}'::jsonb)) c
            WHERE (c.value ->> 'n')::numeric >= 10
  LOOP
    IF abs(ln((x.j ->> 'factor_off_by')::numeric)) > 0.15 OR (x.j ->> 'z_sd')::numeric > 1.5
       OR (x.j ->> 'in_80pct_band')::numeric < 0.6 THEN
      v_areas := v_areas || jsonb_build_object(
        'area', 'charge_clock_' || x.k, 'kind', 'calibration', 'weight', (x.j ->> 'n')::int,
        'finding', 'Charges on ' || x.k || ' ran ' || round(100 * ((x.j ->> 'factor_off_by')::numeric - 1)) || '% against the '
                   || 'learned clock in these windows, z sd ' || (x.j ->> 'z_sd') || ', '
                   || round(100 * COALESCE((x.j ->> 'in_80pct_band')::numeric, 0)) || '% inside an 80% band. The nightly refit '
                   || 'absorbs a level shift; a spread that stays wide means the band model misses a variable.',
        'evidence', x.j);
    END IF;
  END LOOP;
  -- (3) the win probability, and the bar
  IF v_dec >= 10 AND v_brier IS NOT NULL AND v_base IS NOT NULL AND v_brier >= v_base THEN
    v_areas := v_areas || jsonb_build_object(
      'area', 'futures_uninformative', 'kind', 'calibration', 'weight', v_dec,
      'finding', 'The check''s win probability (futures won over futures) predicts hindsight no better than the base rate: '
                 || 'Brier ' || v_brier || ' against ' || v_base || '. More futures do not help a spread that is wrong; the '
                 || 'forecast areas above are the lever.',
      'evidence', v_out -> 'calibration');
  END IF;
  SELECT b.value INTO v
    FROM jsonb_array_elements(COALESCE(v_out #> '{bar,sweep}', '[]'::jsonb)) b
   ORDER BY (b.value ->> 'd_on_time')::numeric DESC, (b.value ->> 'd_late')::numeric ASC, (b.value ->> 'd_flow')::numeric ASC,
            abs((b.value ->> 'win_frac')::numeric - COALESCE(v_cur, 0.8)) ASC
   LIMIT 1;
  IF v_dec >= 10 AND v IS NOT NULL AND (v ->> 'win_frac')::numeric IS DISTINCT FROM COALESCE(v_cur, 0.8) THEN
    v_areas := v_areas || jsonb_build_object(
      'area', CASE WHEN (v ->> 'win_frac')::numeric < COALESCE(v_cur, 0.8) THEN 'bar_looser' ELSE 'bar_stricter' END,
      'kind', 'threshold', 'weight', v_dec,
      'finding', 'On these orders a bar of ' || (v ->> 'win_frac') || ' would have done better in hindsight than '
                 || COALESCE(v_cur, 0.8) || ': ' || (v ->> 'taken') || ' taken, ' || (v ->> 'won') || ' won, '
                 || (v ->> 'lost') || ' lost. Orders overlap, so this ranks bars; it is not a day''s gain. The bar is a '
                 || 'person''s dial (agent_charge_order_win_frac), changed only as a certified change after a paired test.',
      'evidence', jsonb_build_object('best', v, 'current_win_frac', v_cur));
  END IF;
  -- (4) the simulator itself, given the real inputs
  IF COALESCE((v_out #>> '{simulator,cars_compared}')::numeric, 0) >= 20 AND (v_out #>> '{simulator,mae_min}')::numeric > 10 THEN
    v_areas := v_areas || jsonb_build_object(
      'area', 'simulator_structure', 'kind', 'capability_gap', 'weight', (v_out #>> '{simulator,cars_compared}')::int,
      'finding', 'Given what really happened, the simulator still puts a car''s plug-in a mean '
                 || (v_out #>> '{simulator,mae_min}') || ' minutes from when it really plugged in (bias '
                 || (v_out #>> '{simulator,bias_min}') || '). It does not model bays, holds, the stall pick beyond the kind, '
                 || 'or the next order taking over; that error no forecast can remove.',
      'evidence', v_out -> 'simulator');
  END IF;
  IF COALESCE((v_out #>> '{forecasts,unmodeled_sessions_per_order}')::numeric, 0) >= 1 THEN
    v_areas := v_areas || jsonb_build_object(
      'area', 'chargers_left_out', 'kind', 'capability_gap', 'weight', v_n,
      'finding', 'Chargers the check left out at the order (held for a car, booked, or faulted) served '
                 || (v_out #>> '{forecasts,unmodeled_sessions_per_order}') || ' charges per window: the check never adds a '
                 || 'charger back when its hold ends.',
      'evidence', jsonb_build_object('unmodeled_sessions_per_order', v_out #> '{forecasts,unmodeled_sessions_per_order}'));
  END IF;
  -- (5) the agent's moves: one that keeps losing in hindsight, one that keeps winning and is refused
  FOR x IN SELECT m.key AS tag, m.value AS j FROM jsonb_each(COALESCE(v_out -> 'moves', '{}'::jsonb)) m
            WHERE (m.value ->> 'orders')::int >= 3
  LOOP
    IF (x.j ->> 'lost')::numeric / (x.j ->> 'orders')::numeric >= 0.6 THEN
      v_areas := v_areas || jsonb_build_object(
        'area', 'agent_move_loses_' || x.tag, 'kind', 'agent', 'weight', (x.j ->> 'orders')::int,
        'finding', 'Orders that made the move ' || x.tag || ' lost to the kernel''s own order in hindsight '
                   || (x.j ->> 'lost') || ' times of ' || (x.j ->> 'orders') || '. The agent''s board shows it '
                   || '(track_record.moves); its prompt says to stop making it.',
        'evidence', x.j);
    ELSIF (x.j ->> 'won')::numeric / (x.j ->> 'orders')::numeric >= 0.7
          AND (x.j ->> 'orders')::int - (x.j ->> 'taken')::int >= 2 THEN
      v_areas := v_areas || jsonb_build_object(
        'area', 'agent_move_wins_refused_' || x.tag, 'kind', 'agent', 'weight', (x.j ->> 'orders')::int,
        'finding', 'Orders that made the move ' || x.tag || ' beat the kernel''s own order in hindsight '
                   || (x.j ->> 'won') || ' times of ' || (x.j ->> 'orders') || ', and the check refused '
                   || ((x.j ->> 'orders')::int - (x.j ->> 'taken')::int) || ' of them: the check undervalues this move.',
        'evidence', x.j);
    END IF;
  END LOOP;

  SELECT COALESCE(jsonb_agg(a.value ORDER BY (a.value ->> 'weight')::numeric DESC NULLS LAST, a.value ->> 'area'), '[]'::jsonb)
    INTO v_areas FROM jsonb_array_elements(v_areas) a;
  RETURN v_out || jsonb_build_object('improvement_areas', v_areas);
END $fn$;

-- ══ (g) the night's grading and assessment ═════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_arbiter_hindsight_nightly(p_budget_ms integer DEFAULT 90000)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0621: grade and attribute what is due, within p_budget_ms (pg_cron runs each statement under a 120 s timeout).
   Never while a run is running: a run's tick cadence is part of what it measures, and the attribution is CPU. */
BEGIN
  IF EXISTS (SELECT 1 FROM ottoq_sim_runs WHERE status = 'running') THEN
    RETURN jsonb_build_object('skipped', 'a run is running');
  END IF;
  RETURN public.ottoq_charge_order_grade_pending(NULL, 100000, true, LEAST(GREATEST(COALESCE(p_budget_ms, 90000), 0), 100000), 90);
END $fn$;

CREATE FUNCTION public.ottoq_arbiter_assess(p_depot_id uuid, p_days integer DEFAULT 7)
RETURNS bigint
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0621: the day's self-assessment of the check at a depot, written to ottoq_arbiter_assessments; NULL when nothing was
   graded in the window. A finding for a person, never a change (rule 10). */
DECLARE v jsonb; v_since timestamptz := now() - make_interval(days => GREATEST(COALESCE(p_days, 7), 1)); v_id bigint;
BEGIN
  v := public.ottoq_arbiter_self_assessment(p_depot_id, v_since);
  IF COALESCE((v ->> 'graded')::int, 0) = 0 THEN RETURN NULL; END IF;
  INSERT INTO ottoq_arbiter_assessments (depot_id, since, n_graded, n_decisions, assessment, improvement_areas, code_md5)
  VALUES (p_depot_id, v_since, (v ->> 'graded')::int, (v ->> 'decisions')::int, v - 'improvement_areas',
          COALESCE(v -> 'improvement_areas', '[]'::jsonb),
          md5(pg_get_functiondef('public.ottoq_arbiter_self_assessment(uuid,timestamptz)'::regprocedure)))
  RETURNING assessment_id INTO v_id;
  RETURN v_id;
END $fn$;

SELECT cron.schedule('ottoq-arbiter-hindsight-nightly', '*/10 11,12 * * *',
                     $cron$SELECT public.ottoq_arbiter_hindsight_nightly(90000)$cron$);
SELECT cron.schedule('ottoq-arbiter-assess-nightly', '55 12 * * *',
                     $cron$SELECT public.ottoq_arbiter_assess('11111111-1111-1111-1111-111111111111'::uuid, 7)$cron$);

-- ══ (f) the door grades what is due on its run, the usage read gives each order its outcome, the board the record ══
CREATE OR REPLACE FUNCTION public.ottoq_agent_charge_order_record(p_sim_run_id uuid, p_board_tick bigint, p_chain_id text,
                                                                  p_model text, p_order jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_run record; v_q jsonb := '{}'::jsonb; v_cars jsonb := '[]'::jsonb; v_dropped jsonb := '[]'::jsonb;
  v_seen text[] := ARRAY[]::text[]; v_rank int := 0; v_n int := 0; e jsonb; v_id uuid; v_kind text; v_info jsonb;
  v_status text; v_order_id bigint; v_why text;
  v_map jsonb; v_verdict jsonb;   -- 0618
  v_state jsonb; v_futures int; v_win numeric; v_seed text;   -- 0620
BEGIN
  SELECT r.sim_run_id, r.depot_id, r.tick_count, r.sim_clock_current, r.status INTO v_run
    FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  IF v_run.sim_run_id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'run_not_found'); END IF;
  IF v_run.status IS DISTINCT FROM 'running' THEN
    RETURN jsonb_build_object('ok', false, 'skipped', 'run_not_running');
  END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order', 0), 0) < 1 THEN
    RETURN jsonb_build_object('ok', false, 'skipped', 'agent_charge_order is 0 for this run');
  END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_seat', 0), 0) <> 0 THEN
    RETURN jsonb_build_object('ok', false, 'skipped', 'a baseline seat owns this run');
  END IF;

  -- the line as the kernel holds it now: an order is accepted only for cars in it
  SELECT COALESCE(jsonb_object_agg(k.vehicle_id::text, jsonb_build_object(
           'kernel_pos', k.kernel_pos, 'wait_min', round(k.wait_min, 1), 'soc', round(k.soc, 1),
           'name', COALESCE(v.display_name, k.vehicle_id::text))), '{}'::jsonb)
    INTO v_q
    FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current) k
    JOIN vehicles v ON v.id = k.vehicle_id;

  v_why := left(btrim(COALESCE(p_order ->> 'why', '')), 400);
  IF jsonb_typeof(p_order -> 'cars') IS DISTINCT FROM 'array' THEN
    v_dropped := jsonb_build_array(jsonb_build_object('reason', 'no cars array'));
  ELSE
    FOR e IN SELECT x.value FROM jsonb_array_elements(p_order -> 'cars') WITH ORDINALITY x(value, i) ORDER BY x.i LIMIT 40
    LOOP
      v_n := v_n + 1;
      v_id := NULL;
      IF jsonb_typeof(e) = 'object' AND (e ->> 'vehicle_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        v_id := (e ->> 'vehicle_id')::uuid;
      END IF;
      IF v_id IS NULL THEN
        v_dropped := v_dropped || jsonb_build_object('vehicle_id', left(COALESCE(e ->> 'vehicle_id', e::text), 60), 'reason', 'not_a_vehicle_id');
        CONTINUE;
      END IF;
      IF v_id::text = ANY (v_seen) THEN
        v_dropped := v_dropped || jsonb_build_object('vehicle_id', v_id, 'reason', 'duplicate');
        CONTINUE;
      END IF;
      v_seen := v_seen || v_id::text;
      v_info := v_q -> v_id::text;
      IF v_info IS NULL THEN
        v_dropped := v_dropped || jsonb_build_object('vehicle_id', v_id, 'reason', 'not_waiting_for_a_charger');
        CONTINUE;
      END IF;
      v_kind := lower(COALESCE(e ->> 'kind', 'either'));
      IF v_kind NOT IN ('dcfc', 'l2', 'either') THEN v_kind := 'either'; END IF;
      -- a kind the car cannot plug into here is the kernel's to pick, not a reason to drop the car
      IF v_kind <> 'either' AND NOT public.ottoq_charge_kind_compatible(v_id, v_run.depot_id, v_kind) THEN
        v_kind := 'either';
      END IF;
      v_rank := v_rank + 1;
      v_cars := v_cars || jsonb_build_object(
        'vehicle_id', v_id, 'rank', v_rank, 'kind', v_kind, 'why', left(btrim(COALESCE(e ->> 'why', '')), 200),
        'name', v_info -> 'name', 'soc', v_info -> 'soc', 'wait_min', v_info -> 'wait_min',
        'kernel_pos', v_info -> 'kernel_pos');
    END LOOP;
  END IF;

  v_status := CASE WHEN v_rank = 0 THEN 'rejected' WHEN v_rank < v_n THEN 'partial' ELSE 'accepted' END;

  /* 0620: THE KERNEL'S CHECK. The line rolled forward from now in the kernel's own order and in this one (its ttl, then
     the kernel's), with the cars coming home and the learned charge clock, in the expected future and the sampled ones.
     Taken only when it wins the expected future and at least agent_charge_order_win_frac of all. A rollout that fails
     refuses: an order the kernel could not check is never taken. */
  IF v_rank > 0 THEN
    BEGIN
      SELECT jsonb_object_agg(c ->> 'vehicle_id', jsonb_build_object('rank', c -> 'rank', 'kind', c ->> 'kind'))
        INTO v_map FROM jsonb_array_elements(v_cars) c;
      v_futures := GREATEST(1, LEAST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_futures', 12), 12), 64))::int;
      v_win := LEAST(GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_win_frac', 0.8), 0.8), 0.5), 1);
      v_seed := p_sim_run_id::text || ':' || COALESCE(v_run.tick_count, 0) || ':' || COALESCE(p_chain_id, '');
      v_state := public.ottoq_charge_line_state(p_sim_run_id, v_run.depot_id, v_run.sim_clock_current);
      v_verdict := public.ottoq_charge_order_verdict_v2(
        public.ottoq_charge_line_rollout(v_state, v_map, v_futures, v_seed), v_win);
    EXCEPTION WHEN OTHERS THEN
      v_verdict := jsonb_build_object('take', false, 'reason', 'rollout_failed', 'error', left(SQLERRM, 200));
      v_state := NULL;
    END;
    IF NOT COALESCE((v_verdict ->> 'take')::boolean, false) THEN
      v_status := 'refused';
    END IF;
  END IF;

  INSERT INTO ottoq_agent_charge_orders
    (sim_run_id, depot_id, board_tick, recorded_tick, sim_clock, chain_id, model, status, n_offered, n_accepted,
     cars, dropped, why, projection)
  VALUES (p_sim_run_id, v_run.depot_id, p_board_tick, COALESCE(v_run.tick_count, 0), v_run.sim_clock_current,
          left(p_chain_id, 80), left(p_model, 120), v_status, v_n, v_rank, v_cars, v_dropped, NULLIF(v_why, ''),
          v_verdict)
  RETURNING order_id INTO v_order_id;

  -- 0620: the state the check read, so the check can be replayed (0621); a failure here never loses the order
  IF v_state IS NOT NULL THEN
    BEGIN
      INSERT INTO ottoq_charge_order_snapshots
        (order_id, sim_run_id, depot_id, sim_clock, seed, futures, win_frac, state, agent_order, code_md5)
      VALUES (v_order_id, p_sim_run_id, v_run.depot_id, v_run.sim_clock_current, v_seed, v_futures, v_win, v_state, v_map,
              -- 0621: the simulator is the schedule; its source is in the md5 too
              md5(pg_get_functiondef('public.ottoq_charge_line_simulate(jsonb,jsonb,integer,text)'::regprocedure)
                  || pg_get_functiondef('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure)
                  || pg_get_functiondef('public.ottoq_charge_line_compare(jsonb,jsonb)'::regprocedure)
                  || pg_get_functiondef('public.ottoq_charge_line_rollout(jsonb,jsonb,integer,text)'::regprocedure)
                  || pg_get_functiondef('public.ottoq_charge_order_verdict_v2(jsonb,numeric)'::regprocedure)));
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0620: the snapshot of order % was not written: %', v_order_id, SQLERRM;
    END;
  END IF;

  -- 0621: grade in hindsight up to three of this run's earlier orders whose window has closed, so the agent's next board
  -- carries its track record; never the attribution (that is the night's), and a failure here never loses the order
  BEGIN
    PERFORM public.ottoq_charge_order_grade_pending(p_sim_run_id, 3, false, 2000, 90);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0621: hindsight grading after order % failed: %', v_order_id, SQLERRM;
  END;

  RETURN jsonb_build_object(
    'ok', true, 'order_id', v_order_id, 'status', v_status, 'offered', v_n, 'accepted', v_rank,
    'dropped', v_dropped, 'queue', (SELECT count(*) FROM jsonb_object_keys(v_q)),
    'recorded_tick', COALESCE(v_run.tick_count, 0),
    'ttl_ticks', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15),
    'pin_wait_min', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_pin_wait_min', 90), 90),
    'projection', v_verdict - 'per');
EXCEPTION WHEN OTHERS THEN
  -- the agent's pass reads this receipt; a fault here must say so and never take the pass down
  RETURN jsonb_build_object('ok', false, 'error', SQLERRM);
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_agent_charge_order_record(uuid, bigint, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_agent_charge_order_record(uuid, bigint, text, text, jsonb) TO service_role;

CREATE OR REPLACE FUNCTION public.ottoq_agent_charge_order_usage(p_sim_run_id uuid, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0614: what the agent's charge orders did on one run, read-only. A seat is a stall_assignment the decide path
  -- enacted while an order was live (its context_frame carries agent_charge_order). by_rank = the agent's order seated
  -- it (not pinned); pinned = the fairness floor seated it ahead of the order; unranked = the order did not name it;
  -- moved_ahead = seated by rank while the kernel's own order had it behind as many cars as were seated that tick;
  -- kind_followed = it took the kind the order named.
  WITH o AS (
    SELECT x.order_id, x.chain_id, x.recorded_tick, x.status, x.n_offered, x.n_accepted, x.projection
      FROM ottoq_agent_charge_orders x WHERE x.sim_run_id = p_sim_run_id
  ), s AS (
    SELECT d.tick_seq,
           CASE WHEN (d.context_frame -> 'agent_charge_order' ->> 'order_id') ~ '^[0-9]+$'
                THEN (d.context_frame -> 'agent_charge_order' ->> 'order_id')::bigint END AS order_id,
           COALESCE((d.context_frame -> 'agent_charge_order' ->> 'pinned')::boolean, false) AS pinned,
           d.context_frame -> 'agent_charge_order' ->> 'kind' AS kind,
           (d.context_frame -> 'agent_charge_order' ->> 'rank') AS rank,
           CASE WHEN (d.context_frame -> 'agent_charge_order' ->> 'kernel_pos') ~ '^[0-9]+$'
                THEN (d.context_frame -> 'agent_charge_order' ->> 'kernel_pos')::int END AS kernel_pos,
           COALESCE(d.enacted_action ->> 'stall_type', d.proposed_action ->> 'stall_type') AS took,
           count(*) OVER (PARTITION BY d.tick_seq) AS seats_in_tick
      FROM ottoq_decisions d
     WHERE d.sim_run_id = p_sim_run_id AND d.action_context = 'stall_assignment' AND d.outcome_status = 'enacted'
       AND d.context_frame ? 'agent_charge_order'
  ), t AS (
    SELECT s.*, (NOT s.pinned AND s.rank IS NOT NULL) AS by_rank FROM s
  )
  SELECT jsonb_build_object(
    'orders', (SELECT count(*) FROM o),
    'orders_accepted', (SELECT count(*) FROM o WHERE o.status IN ('accepted', 'partial')),
    -- 0618: the orders the kernel's own check said were worse than its order, and so never steered a seat
    'orders_refused', (SELECT count(*) FROM o WHERE o.status = 'refused'),
    -- 0620: why, by the check's reason (same_as_kernel: the order would have changed nothing)
    'refused_by_reason', COALESCE((SELECT jsonb_object_agg(r.reason, r.n) FROM (
                                     SELECT COALESCE(o.projection ->> 'reason', 'unknown') AS reason, count(*) AS n
                                       FROM o WHERE o.status = 'refused' GROUP BY 1) r), '{}'::jsonb),
    -- 0621: how the run's orders did in what actually happened, once graded (ottoq_charge_order_hindsight)
    'hindsight', (SELECT jsonb_build_object(
                    'graded', count(*),
                    'right_take', count(*) FILTER (WHERE h.outcome = 'right_take'),
                    'neutral_take', count(*) FILTER (WHERE h.outcome = 'neutral_take'),
                    'wrong_take', count(*) FILTER (WHERE h.outcome = 'wrong_take'),
                    'missed_win', count(*) FILTER (WHERE h.outcome = 'missed_win'),
                    'right_refusal', count(*) FILTER (WHERE h.outcome = 'right_refusal'),
                    'no_decision', count(*) FILTER (WHERE h.outcome IN ('no_decision', 'no_decision_mattered')))
                    FROM ottoq_charge_order_hindsight h WHERE h.sim_run_id = p_sim_run_id),
    'cars_ranked', (SELECT COALESCE(sum(o.n_accepted), 0) FROM o WHERE o.status IN ('accepted', 'partial')),
    'seats_under_order', (SELECT count(*) FROM t),
    'seats_by_rank', (SELECT count(*) FROM t WHERE t.by_rank),
    -- 0616: the orders that seated at least one car by their rank: the agent passes the twin draws green
    'orders_seating', (SELECT count(DISTINCT t.order_id) FROM t WHERE t.by_rank),
    'seats_pinned', (SELECT count(*) FROM t WHERE t.pinned),
    'seats_unranked', (SELECT count(*) FROM t WHERE NOT t.pinned AND t.rank IS NULL),
    'moved_ahead', (SELECT count(*) FROM t WHERE t.by_rank AND t.kernel_pos > t.seats_in_tick),
    'kind_named', (SELECT count(*) FROM t WHERE t.kind IN ('dcfc', 'l2')),
    'kind_followed', (SELECT count(*) FROM t WHERE t.kind IN ('dcfc', 'l2') AND t.took = t.kind),
    'by_order', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'order_id', o.order_id, 'chain_id', o.chain_id, 'recorded_tick', o.recorded_tick, 'status', o.status,
               'offered', o.n_offered, 'accepted', o.n_accepted,
               'verdict', o.projection ->> 'reason',
               -- 0620: how many of the futures the check rolled the order beat the kernel's own in, of how many
               'futures_won', (o.projection ->> 'wins')::int, 'futures', (o.projection ->> 'futures')::int,
               'need', (o.projection ->> 'need')::int,
               -- 0621: the order replayed with what actually happened, once its window closed
               'hindsight', (SELECT h.outcome FROM ottoq_charge_order_hindsight h WHERE h.order_id = o.order_id),
               'moves', (SELECT to_jsonb(h.moves) FROM ottoq_charge_order_hindsight h WHERE h.order_id = o.order_id),
               'seats', (SELECT count(*) FROM t WHERE t.order_id = o.order_id),
               'seats_by_rank', (SELECT count(*) FROM t WHERE t.order_id = o.order_id AND t.by_rank),
               'moved_ahead', (SELECT count(*) FROM t WHERE t.order_id = o.order_id AND t.by_rank
                                                       AND t.kernel_pos > t.seats_in_tick))
             ORDER BY o.order_id DESC)
        FROM (SELECT * FROM o ORDER BY o.order_id DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 200))) o), '[]'::jsonb))
$function$;

CREATE OR REPLACE FUNCTION public.ottoq_agent_charge_queue_board(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  -- 0614: the charge line as the agent needs it to order it, read-only. The head 24 cars in the kernel's own order,
  -- each with what it owes (to rule 9's one target, ottoq_effective_target_soc_at), the minutes that charge takes on
  -- each kind of charger here, its whole wait against its contract's queue limit, its other open work, the kernel's own
  -- rule for its kind, and whether it can plug into each kind at all. Then the chargers: free and down by kind, and the
  -- in-use ones that free soonest. 0620: every minute is the learned clock (0619 charge_time_v1, on the depot's fastest
  -- charger of the kind); 'contention' sets the cars waiting against the chargers free now and freeing within 15
  -- minutes; 'arriving' lists the cars coming home (ottoq_charge_line_inbound); 'check' states the bar an order meets.
  -- 0621: 'track_record' says how the agent's orders did in what actually happened (ottoq_charge_order_track_record).
  WITH k AS (
    SELECT * FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, p_depot_id, p_clock) WHERE kernel_pos <= 24
  ), kw AS (
    SELECT max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'dcfc') AS dcfc_kw,
           max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'l2')   AS l2_kw
      FROM stalls s WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc','l2')
  ), m AS (
    SELECT public.ottoq_learned_estimate(p_depot_id, 'charge_time_v1') AS ct,
           public.ottoq_learned_estimate(p_depot_id, 'return_v1') AS rt
  ), cars AS (
    SELECT k.kernel_pos, jsonb_build_object(
             'vehicle_id', v.id, 'name', COALESCE(v.display_name, v.id::text),
             'operator', fo.name,
             'soc', round(k.soc, 1),
             'target', round(public.ottoq_effective_target_soc_at(v.id, p_clock), 0),
             'kwh_owed', round(COALESCE(v.battery_capacity_kwh, 0)
                               * GREATEST(public.ottoq_effective_target_soc_at(v.id, p_clock) - k.soc, 0) / 100.0, 1),
             'min_on_dcfc', round(public.ottoq_charge_minutes_learned_with((SELECT ct FROM m), 'dcfc', v.battery_capacity_kwh, k.soc,
                              public.ottoq_effective_target_soc_at(v.id, p_clock), (SELECT dcfc_kw FROM kw), v.inlet_max_kw), 0),
             'min_on_l2', round(public.ottoq_charge_minutes_learned_with((SELECT ct FROM m), 'l2', v.battery_capacity_kwh, k.soc,
                              public.ottoq_effective_target_soc_at(v.id, p_clock), (SELECT l2_kw FROM kw), v.inlet_max_kw), 0),
             'wait_min', round(k.wait_min, 0),
             'contract_wait_limit_min', sla.max_queue_wait_minutes,
             'over_limit_min', CASE WHEN sla.max_queue_wait_minutes IS NOT NULL
                                    THEN GREATEST(round(k.wait_min - sla.max_queue_wait_minutes, 0), 0) END,
             'urgency', vn.urgency,
             'due_in_min', CASE WHEN vn.dispatch_due_at IS NOT NULL
                                THEN round(extract(epoch FROM (vn.dispatch_due_at - p_clock)) / 60.0, 0) END,
             'other_work', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                       'svc', a ->> 'svc', 'min', a -> 'est_min',
                                       'where', CASE WHEN a ->> 'concurrency' = 'bay' THEN 'bay' ELSE 'in_place' END)
                                       ORDER BY a ->> 'svc')
                                       FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
                                      WHERE a ->> 'svc' NOT IN ('charge', 'readiness_check')
                                        AND COALESCE(a ->> 'status', 'pending') NOT IN ('done', 'cancelled')), '[]'::jsonb),
             'rule_kind', CASE WHEN k.soc < 45 OR k.immediate THEN 'dcfc' ELSE 'l2' END,
             'dcfc_ok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'dcfc'),
             'l2_ok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2'),
             'holds_charger', k.holds_charger,
             'kernel_pos', k.kernel_pos) AS j
      FROM k JOIN vehicles v ON v.id = k.vehicle_id
      LEFT JOIN fleet_operators fo ON fo.id = v.fleet_operator_id
      LEFT JOIN LATERAL (SELECT s.max_queue_wait_minutes FROM ottoq_fleet_operator_slas s
                          WHERE s.fleet_operator_id = v.fleet_operator_id AND s.status = 'active'
                            AND s.effective_from <= p_clock AND (s.effective_until IS NULL OR s.effective_until > p_clock)
                          ORDER BY s.version DESC LIMIT 1) sla ON true
      LEFT JOIN LATERAL (SELECT vn.urgency, vn.dispatch_due_at, vn.atoms FROM ottoq_visit_needs vn
                          WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                            AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                              = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                          ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) vn ON true
  ), st AS (
    SELECT s.id, s.stall_type::text AS kind, COALESCE(s.display_name, s.stall_code) AS name, s.connector_max_kw,
           s.current_vehicle_id,
           COALESCE(c.station_state = 'Faulted', false) AS faulted,
           (s.current_vehicle_id IS NULL
            AND NOT (s.reserved_by IS NOT NULL AND COALESCE(s.reservation_expires_at, 'infinity'::timestamptz) > p_clock)
            AND c.station_state = 'Available' AND c.last_heartbeat_at >= p_clock - interval '90 seconds'
            AND NOT EXISTS (SELECT 1 FROM ottoq_stall_bookings b
                             WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                               AND b.state IN ('held','active','done','interrupted') AND b.during @> p_clock)) AS free
      FROM stalls s LEFT JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
     WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc','l2')
  ), soon AS (
    SELECT st.kind, st.name, COALESCE(v.display_name, v.id::text) AS car,
           round(public.ottoq_charge_minutes_learned_with((SELECT ct FROM m), st.kind, v.battery_capacity_kwh, v.current_soc,
             public.ottoq_effective_target_soc_at(v.id, p_clock), st.connector_max_kw, v.inlet_max_kw), 0) AS in_min
      FROM st JOIN vehicles v ON v.id = st.current_vehicle_id
     WHERE v.current_state::text IN ('charging_dcfc', 'charging_l2')
  ), inb AS (
    SELECT i.*, COALESCE(v.display_name, v.id::text) AS name
      FROM public.ottoq_charge_line_inbound(p_sim_run_id, p_depot_id, p_clock, 180, (SELECT rt FROM m)) i
      JOIN vehicles v ON v.id = i.vehicle_id
  ), ln AS (
    SELECT count(*) AS waiting FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, p_depot_id, p_clock)
  ), cn AS (
    SELECT (SELECT waiting FROM ln) AS waiting,
           (SELECT count(*) FROM st WHERE st.free) AS free_now,
           (SELECT count(*) FROM soon WHERE soon.in_min <= 15) AS freeing_15
  )
  SELECT jsonb_build_object(
    'pin_wait_min', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_pin_wait_min', 90), 90),
    'ttl_ticks', COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15),
    'chargers', jsonb_build_object(
      'free', jsonb_build_object('dcfc', (SELECT count(*) FROM st WHERE st.kind = 'dcfc' AND st.free),
                                 'l2',   (SELECT count(*) FROM st WHERE st.kind = 'l2' AND st.free)),
      'down', jsonb_build_object('dcfc', (SELECT count(*) FROM st WHERE st.kind = 'dcfc' AND st.faulted),
                                 'l2',   (SELECT count(*) FROM st WHERE st.kind = 'l2' AND st.faulted)),
      'total', jsonb_build_object('dcfc', (SELECT count(*) FROM st WHERE st.kind = 'dcfc'),
                                  'l2',   (SELECT count(*) FROM st WHERE st.kind = 'l2')),
      'kw', jsonb_build_object('dcfc', (SELECT dcfc_kw FROM kw), 'l2', (SELECT l2_kw FROM kw)),
      'freeing_soonest', COALESCE((SELECT jsonb_agg(jsonb_build_object('kind', x.kind, 'stall', x.name, 'car', x.car,
                                                                       'in_min', x.in_min) ORDER BY x.in_min, x.name)
                                     FROM (SELECT * FROM soon ORDER BY soon.in_min NULLS LAST, soon.name LIMIT 8) x),
                                  '[]'::jsonb)),
    'waiting', (SELECT waiting FROM ln),
    -- 0620: how tight the line is: none = every car waiting can plug in now; tight = it can within 15 minutes;
    -- congested = it cannot. The order matters most when the line is congested.
    'contention', (SELECT jsonb_build_object(
                     'waiting', cn.waiting, 'free_now', cn.free_now, 'freeing_15_min', cn.freeing_15,
                     'arriving_60_min', (SELECT count(*) FROM inb WHERE inb.eta_min <= 60),
                     'pressure', CASE WHEN cn.waiting <= cn.free_now THEN 'none'
                                      WHEN cn.waiting <= cn.free_now + cn.freeing_15 THEN 'tight'
                                      ELSE 'congested' END)
                     FROM cn),
    -- 0620: the cars coming home, soonest first: a car driving home (returning) or one the depot forecasts will be
    -- called home for its reserve (forecast)
    'arriving', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', x.name, 'eta_min', round(x.eta_min, 0),
                                                              'soc', round(x.soc_at_arrival, 0), 'source', x.source)
                                           ORDER BY x.eta_min, x.name)
                            FROM (SELECT * FROM inb ORDER BY inb.eta_min, inb.name LIMIT 12) x), '[]'::jsonb),
    -- 0620: the bar the kernel's check sets, and the learned clock it times every charge by
    'check', jsonb_build_object(
      'futures', GREATEST(1, LEAST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_futures', 12), 12), 64))::int,
      'win_frac', LEAST(GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_win_frac', 0.8), 0.8), 0.5), 1),
      'charge_time_factors', (SELECT jsonb_object_agg(c.key, (c.value ->> 'factor')::numeric)
                                FROM m, jsonb_each(COALESCE(m.ct #> '{params,cells}', '{}'::jsonb)) c
                               WHERE (c.value ->> 'usable')::boolean),
      'return_model', (SELECT jsonb_build_object('reserve_soc', m.rt #> '{params,threshold_soc}',
                                                 'drain_pct_per_min', m.rt #> '{params,drain_pct_per_min}',
                                                 'drive_home_min', m.rt #> '{params,trip_min}',
                                                 'returns_not_forecast', m.rt #> '{params,other_share}')
                         FROM m WHERE COALESCE((m.rt ->> 'usable')::boolean, false))),
    'cars', COALESCE((SELECT jsonb_agg(cars.j ORDER BY cars.kernel_pos) FROM cars), '[]'::jsonb),
    'last_order', (
      SELECT jsonb_build_object('order_id', x.order_id, 'status', x.status, 'offered', x.n_offered,
                                'accepted', x.n_accepted, 'dropped', x.dropped, 'projection', x.projection - 'per',
                                'age_ticks', COALESCE((SELECT r.tick_count FROM ottoq_sim_runs r
                                                        WHERE r.sim_run_id = p_sim_run_id), x.recorded_tick) - x.recorded_tick)
        FROM ottoq_agent_charge_orders x WHERE x.sim_run_id = p_sim_run_id
       ORDER BY x.order_id DESC LIMIT 1),
    'usage', public.ottoq_agent_charge_order_usage(p_sim_run_id, 3),
    -- 0621: the agent's orders replayed with what actually happened: by outcome, by move, and what made the check wrong
    'track_record', public.ottoq_charge_order_track_record(p_sim_run_id, p_depot_id, 7))
$function$;

GRANT EXECUTE ON FUNCTION public.ottoq_charge_line_schedule(jsonb, jsonb, integer, text, boolean) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_line_real_minutes(jsonb, jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_line_realize(jsonb, jsonb, text[]) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_order_moves(jsonb, jsonb, jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_order_forecast_errors(jsonb, jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_order_fidelity(jsonb, jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_order_track_record(uuid, uuid, integer) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_arbiter_self_assessment(uuid, timestamptz) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_hindsight_code_md5() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_charge_order_realized(bigint, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_charge_order_grade(bigint, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_charge_order_attribute(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_charge_order_grade_pending(uuid, integer, boolean, integer, numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_arbiter_hindsight_nightly(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_arbiter_assess(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_hindsight_code_md5() TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_order_realized(bigint, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_order_grade(bigint, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_order_attribute(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_order_grade_pending(uuid, integer, boolean, integer, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_arbiter_hindsight_nightly(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_arbiter_assess(uuid, integer) TO service_role;

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v1$
DECLARE v_bad int; v_n int; t jsonb; sa jsonb; sb jsonb; sc jsonb;
BEGIN
  -- 0620's simulator and this file's, on the same states, orders and futures
  SELECT count(*), count(*) FILTER (WHERE b.r IS DISTINCT FROM public.ottoq_charge_line_simulate(s.state, o.ord, b.scenario, 'v0621')
                                       OR b.r IS DISTINCT FROM (public.ottoq_charge_line_schedule(s.state, o.ord, b.scenario, 'v0621', true) - 'seats'))
    INTO v_n, v_bad
    FROM v0621_before b JOIN v0621_states s ON s.name = b.st JOIN v0621_orders o ON o.name = b.ord;
  IF v_n <> 40 OR v_bad > 0 THEN
    RAISE EXCEPTION '0621 V1: the schedule does not return what 0620''s simulator returned: % of % differ', v_bad, v_n;
  END IF;
  -- the trace, by hand (0620 V2's line): a on the fast charger at 0, ready 40; c on the L2 at 0, ready 120; b on the
  -- fast charger at 40, ready 60
  t := public.ottoq_charge_line_schedule((SELECT state FROM v0621_states WHERE name = 'three'), NULL, 0, 's', true);
  SELECT x.value INTO sa FROM jsonb_array_elements(t -> 'seats') x WHERE x.value ->> 'id' = 'a';
  SELECT x.value INTO sb FROM jsonb_array_elements(t -> 'seats') x WHERE x.value ->> 'id' = 'b';
  SELECT x.value INTO sc FROM jsonb_array_elements(t -> 'seats') x WHERE x.value ->> 'id' = 'c';
  IF (sa ->> 's0')::numeric <> 0 OR sa ->> 'k0' <> 'dcfc' OR (sa ->> 'r')::numeric <> 40
     OR (sc ->> 's0')::numeric <> 0 OR sc ->> 'k0' <> 'l2' OR (sc ->> 'r')::numeric <> 120
     OR (sb ->> 's0')::numeric <> 40 OR sb ->> 'k0' <> 'dcfc' OR (sb ->> 'r')::numeric <> 60
     OR (sb ->> 'x')::int <> 0 THEN
    RAISE EXCEPTION '0621 V1: the trace is not the hand-computed one: %', t -> 'seats';
  END IF;
  RAISE NOTICE '0621 V1: the schedule returns 0620''s results on % cases; the trace is the hand-computed one', v_n;
END $v1$;

DO $v2$
DECLARE r jsonb; s jsonb;
BEGIN
  -- one fast charger, down from minute 20 to minute 50; car a (60 minutes on it) plugs in at 0. At 20 it stops owing
  -- 40 minutes, rejoins the line, takes the charger back at 50 and is ready at 90.
  r := public.ottoq_charge_line_schedule(
         '{"ttl_min": 3, "pin_min": 90, "horizon_min": 480,
           "cars": [{"id": "a", "w": 0, "g": 50, "imm": false, "soc": 50, "due": 100, "md": 60, "ml": 200}],
           "inbound": [], "chargers": [{"id": "f", "k": "dcfc", "free": 0, "dn": [[20, 50]]}]}', NULL, 0, 's', true);
  s := r -> 'seats' -> 0;
  IF (s ->> 's0')::numeric <> 0 OR (s ->> 'r')::numeric <> 90 OR (s ->> 'x')::int <> 1 OR (r ->> 'on_time')::int <> 1
     OR (r ->> 'flow_sum')::numeric <> 90 THEN
    RAISE EXCEPTION '0621 V2: a charge stopped by a fault does not finish when the charger is back: %', r;
  END IF;
  -- a charger down from the start is not offered: b (wants fast) takes the L2 at 0
  r := public.ottoq_charge_line_schedule(
         '{"ttl_min": 3, "pin_min": 90, "horizon_min": 480,
           "cars": [{"id": "b", "w": 0, "g": 70, "imm": false, "soc": 30, "md": 20, "ml": 100}],
           "inbound": [], "chargers": [{"id": "f", "k": "dcfc", "free": 0, "dn": [[0, 30]]},
                                       {"id": "l", "k": "l2", "free": 0}]}', NULL, 0, 's', true);
  s := r -> 'seats' -> 0;
  IF s ->> 'k0' <> 'l2' OR (s ->> 'r')::numeric <> 100 THEN
    RAISE EXCEPTION '0621 V2: a charger that is down was offered: %', r;
  END IF;
  RAISE NOTICE '0621 V2: a fault stops the charge on its charger and the car finishes when it is back';
END $v2$;

DO $v3$
DECLARE r record; v jsonb; n int := 0; t0 timestamptz := clock_timestamp();
BEGIN
  FOR r IN
    (SELECT s.order_id, s.state, s.agent_order, s.futures, s.win_frac, s.seed, o.projection
       FROM public.ottoq_charge_order_snapshots s JOIN public.ottoq_agent_charge_orders o ON o.order_id = s.order_id
      WHERE o.projection ->> 'reason' IN ('worse_in_expected_future', 'no_better_in_expected_future',
                                          'not_enough_futures_won', 'wins_most_futures')
      ORDER BY s.order_id DESC LIMIT 8)
    UNION ALL
    (SELECT s.order_id, s.state, s.agent_order, s.futures, s.win_frac, s.seed, o.projection
       FROM public.ottoq_charge_order_snapshots s JOIN public.ottoq_agent_charge_orders o ON o.order_id = s.order_id
      WHERE o.projection ->> 'reason' = 'same_as_kernel'
      ORDER BY s.order_id DESC LIMIT 4)
  LOOP
    v := public.ottoq_charge_order_verdict_v2(public.ottoq_charge_line_rollout(r.state, r.agent_order, r.futures, r.seed),
                                              r.win_frac);
    n := n + 1;
    IF v IS DISTINCT FROM r.projection THEN
      RAISE EXCEPTION '0621 V3: order % does not replay to its stored verdict: stored %, now %',
        r.order_id, r.projection - 'per', v - 'per';
    END IF;
  END LOOP;
  RAISE NOTICE '0621 V3: % stored snapshots replay to their stored verdicts under this file''s code (% ms)',
    n, round(extract(epoch FROM clock_timestamp() - t0) * 1000);
END $v3$;

DO $v4$
DECLARE r record; v_real jsonb; v_full jsonb; k jsonb; a jsonb; t0 timestamptz;
BEGIN
  SELECT s.order_id, s.state, s.agent_order, s.seed INTO r
    FROM public.ottoq_charge_order_snapshots s
    JOIN public.ottoq_sim_runs x ON x.sim_run_id = s.sim_run_id
    JOIN public.ottoq_agent_charge_orders o ON o.order_id = s.order_id
   WHERE x.status = 'running' AND x.depot_id = '11111111-1111-1111-1111-111111111111'
     AND x.sim_clock_current >= s.sim_clock + interval '90 minutes'
   ORDER BY (o.projection ->> 'reason' <> 'same_as_kernel') DESC, s.order_id DESC
   LIMIT 1;
  IF r.order_id IS NULL THEN
    RAISE NOTICE '0621 V4: no running twin run has an order whose window has closed; the grade is executed by the tests';
    RETURN;
  END IF;
  t0 := clock_timestamp();
  v_real := public.ottoq_charge_order_realized(r.order_id, 90);
  v_full := public.ottoq_charge_line_realize(r.state, v_real, ARRAY['arrivals', 'appeared', 'charge_times', 'running', 'faults']);
  k := public.ottoq_charge_line_schedule(v_full, NULL, 0, r.seed, false);
  a := public.ottoq_charge_line_schedule(v_full, r.agent_order, 0, r.seed, false);
  RAISE NOTICE '0621 V4 order %: % cars arrived of % seen coming, % appeared, % faults, % running ends read; hindsight %; % ms (not written)',
    r.order_id,
    (SELECT count(*) FROM jsonb_each(v_real -> 'inbound') i WHERE (i.value ->> 'arrived')::boolean),
    jsonb_array_length(r.state -> 'inbound'), jsonb_array_length(v_real -> 'appeared'), v_real -> 'faults',
    (SELECT count(*) FROM jsonb_each(v_real -> 'chargers') c WHERE c.value ? 'free'),
    public.ottoq_charge_line_compare(k, a), round(extract(epoch FROM clock_timestamp() - t0) * 1000);
END $v4$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0621_the_kernel_grades_its_own_check_in_hindsight', false, false,
  'Every agent charge order the kernel checked is replayed 90 sim-minutes later with what actually happened (arrivals, '
  'cars it never saw, charge times, the charges under way, faults) through the same simulator from the same state, and '
  'graded; the difference from the check is split by Shapley value; a nightly self-assessment names improvement areas '
  'for a person. The simulator gains a trace and charger down windows, with results unchanged (V1, V3). FALSE/FALSE: '
  'the tick path is untouched and orders exist only on operator_demo runs (0615).',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
