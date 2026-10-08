-- migration-version: 20261008134303
-- migration-name:    the_kernel_takes_an_agent_order_only_when_it_wins_most_futures
--
-- 0620  **The kernel takes the agent's charge order only when it beats the kernel's own order in the expected future
--       and in most sampled ones, with the cars coming home counted and the charges timed as they really run.** The
--       agent keeps proposing every pass; the decide path keeps disposing. What changes is the test an order must pass
--       before it seats a car. 0618 compared one projection of the line waiting now, on a clock that runs short, with no
--       car arriving and the agent's ranking held for eight hours. 0620 rolls the line forward from the order's moment
--       the way the charge cursor will actually run it: the agent's ranking for the order's life (its ttl), then the
--       kernel's own order, with every car that is driving home or will be called home for its reserve joining the
--       line when it arrives, every charge timed by 0619's learned model, and the whole thing repeated over sampled
--       futures (charge times and arrivals jittered by their learned spread, the same draws on both sides). The order
--       is taken only when it wins the expected future and at least `agent_charge_order_win_frac` (0.8) of the
--       `agent_charge_order_futures` (12) sampled ones. When it would seat the same cars on the same kinds of charger
--       as the kernel in its window, there is nothing to decide and the kernel's order flows (`same_as_kernel`).
--       Chase, 2026-10-08: "only get accepted if they beat or are optimized better than the greedy ... if there's
--       nothing to optimize, it should just flow normally ... When things get tight or congested, that's really when
--       the agent layer should shine." Rule 9 holds everywhere in this file: every car charges to its full target in
--       every future, on whichever charger it takes; an order decides who goes next and on which kind, never how much.
--
-- ══ §1 WHY (db/checks/0415 §5, run 089f46bd against 81787ef9, same seed, both cut at sim 15:11:06) ══════════════════
--
--   Under 0618's check the agent's order still cost the depot: uptime 35.9% against the kernel's 40.6%, 62 departures
--   against 71, 40.0% of cars ready by their due time against 45.2%. The check took 27 of 64 orders, all of them for
--   being a few minutes better on the line waiting at that moment (25 `line_ready_sooner` at 4.0-5.5 minutes, 2
--   `no_worse`); none for getting a car to its due time. Three things in its projection made those gains look real:
--     (a) the clock: 0614's estimate, which 0619 measured running 35-140% short of a real charge, worst for top-offs;
--     (b) no arrivals: a low battery put on an L2 holds it for hours, and the cars that come home behind it wait; a
--         projection of the line waiting now never sees them (5 of the 24 seats the checked orders made were that);
--     (c) the horizon of the ranking: the agent's order was projected as if it held for 480 minutes, when it lives 15
--         ticks (about 3 sim-minutes) and the next order or the kernel's takes over. What an order changes is the
--         seats made in its window; everything after is the next decision's. A check that scores a ranking held for
--         eight hours scores a policy nobody runs.
--   And one point estimate cannot tell a 4-minute gain from noise. This is the rollout test of approximate dynamic
--   programming: take the proposed decision only when, continued with the base policy (the kernel's own order), it
--   beats the base policy from the same state, across the futures the state can produce. Under exact simulation that
--   cannot do worse than the base policy; under estimated simulation the sampled futures are the margin of safety.
--
-- ══ §2 WHAT ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq_charge_line_inbound(run, depot, clock, window, return model)`: the cars the depot can see coming within
--       `window` minutes: a car driving home arrives at its dispatch's `scheduled_return_at` (distance over speed,
--       0320); a car at work is called home when its live battery reading reaches 0619's reserve threshold, at the
--       learned drain, then drives the learned trip. A car arriving at or above its target joins no charge line. With
--       no usable return model, only the cars already driving home. Returns no car that is not at this depot's run.
--   (b) `ottoq_charge_line_state(run, depot, clock)`: everything a rollout reads, once, as one jsonb: the line (each
--       car's wait, owed gap, immediate flag, battery, due time, which kinds it can plug into, and its learned minutes
--       and log spread on each kind), the cars coming home, the chargers (free now, or free when their car is full by
--       the learned clock; faulted ones and ones held for something else left out, as 0618), the tick, the order's
--       life in minutes (ttl ticks x the run's own minutes a tick), the pin, and the two models' ids. Stored with each
--       checked order (e), so 0621 can replay the check with what actually happened.
--   (c) `ottoq_charge_line_simulate(state, order, scenario, seed)`: pure. The charge cursor as a list schedule from the
--       state: at each moment a charger is free and a car is waiting, the waiting cars in the cursor's own order
--       (immediate dispatch; then, while the order lives, cars waited past the pin, then 0617's key with the kinds
--       free at that moment; then the response ratio of 0545 recomputed at that moment, battery, id), each taking a
--       free charger of the kind it wants (the order's kind while it lives, except for an immediate dispatch; else
--       fast below 45% or for an immediate dispatch, L2 otherwise) or the other kind it can plug into when that is all
--       that is free. Scenario 0 is the expected future. Scenario s > 0 multiplies each car's charge minutes by
--       exp(log spread x z), the remaining minutes of each charge under way the same way, and each forecast arrival's
--       time to its reserve by exp(drain spread x z), every z a standard normal drawn from md5(seed, s, car) and so the
--       same for both orders: common random numbers. Reports cars ready by their due time, summed lateness, summed
--       minutes in the depot (ready less arrival, every car, arrivals included; a car never seated counts the horizon
--       plus its fastest charge), and the seats made in the order's window.
--   (d) `ottoq_charge_line_compare(kernel, agent)` and `ottoq_charge_line_rollout(state, order, futures, seed)`: the
--       comparison is lexicographic, the owner's requirement first (rule 9): more cars ready by their due time wins;
--       then less summed lateness (half a minute of rounding); then fewer summed minutes in the depot (a minute of
--       rounding); else a tie. The rollout runs the expected future first and stops there when both orders seat the
--       same cars on the same kinds at the same moments in the window (`same_first_seats`); otherwise it runs every
--       future and counts wins, ties and losses.
--   (e) `ottoq_charge_order_verdict_v2(rollout, win_frac)`: take only when the expected future is a win and the wins
--       are at least ceil(win_frac x futures). Reasons: `same_as_kernel`, `worse_in_expected_future`,
--       `no_better_in_expected_future`, `not_enough_futures_won`, `wins_most_futures`; `rollout_failed` when the
--       door could not run it (refused: an order the kernel could not check is never taken).
--   (f) `public.ottoq_charge_order_snapshots`: append-only evidence, one row per checked order: the state the check
--       read, the order it ran, the seed, the futures and the bar, and the md5 of the code that judged it. No foreign
--       key: evidence outlives the run (0340/0364).
--   (g) Dials, catalogued, not agent-writable: `agent_charge_order_futures` (12, 1-64) and
--       `agent_charge_order_win_frac` (0.8, 0.5-1). Changing either is a person's change (rule 10).
--   (h) The door (`ottoq_agent_charge_order_record`) runs (b)-(e) for every order that names a car, records the
--       verdict in `projection` and the snapshot in (f); the usage read gives each order its futures won and counts
--       refusals by reason; the agent's board times every charge by the learned clock and shows the line's contention
--       (cars waiting against chargers free now and freeing within 15 minutes), the cars coming home, and the bar the
--       check sets.
--
--   The tick path is untouched: the cursor, the key, the stall pick and the live read are 0614's and 0617's.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the door, the usage read and the board are 0618's bodies; the kernel's order, the key,
--   the estimate and the learned minutes are the ones this file reads (md5 of each source); 0619's estimates exist;
--   nothing this file creates exists. V1: the normal draw is a pure function of its key with mean 0 and spread 1 over
--   4,000 keys. V2: the simulator on a three-car state, by hand. V3: the verdict's truth table. V4: on a running twin
--   run, the state builds, the kernel's order against itself is `same_as_kernel`, and a full rollout of the line
--   reversed is timed. tests/test_agent_arbiter_sql.py executes the rest on the miniature depot of
--   tests/test_agent_charge_order_sql.py.
--
-- ══ §4 RECERT ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   FALSE/FALSE. Only the door, the usage read and the board change; the door records an order only when
--   agent_charge_order = 1, which only an operator_demo run arms (0615); no certification, sweep or dial pair runs one.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0620_pre' (the door, the usage read and
--   the board as 0618 left them); DROP FUNCTION public.ottoq_charge_order_verdict_v2(jsonb, numeric),
--   public.ottoq_charge_line_rollout(jsonb, jsonb, integer, text), public.ottoq_charge_line_compare(jsonb, jsonb),
--   public.ottoq_charge_line_simulate(jsonb, jsonb, integer, text), public.ottoq_charge_line_state(uuid, uuid,
--   timestamptz), public.ottoq_charge_line_inbound(uuid, uuid, timestamptz, numeric, jsonb),
--   public.ottoq_charge_time_log_sd(jsonb, text, numeric), public.ottoq_hash_normal(text);
--   (the snapshots table may stay: nothing else reads it); DELETE FROM public.ottoq_policy_param_catalog WHERE param_key
--   IN ('agent_charge_order_futures', 'agent_charge_order_win_frac');
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0620_the_kernel_takes_an_agent_order_only_when_it_wins_most_futures'.

BEGIN;

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0620 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)', '3ef7643b', 'the door (0618)'),
      ('public.ottoq_agent_charge_order_usage(uuid,integer)', 'af401c13', 'the usage read (0618)'),
      ('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', '18c23f43', 'the board (0618)'),
      ('public.ottoq_agent_charge_order_key(jsonb,uuid,text)', 'fd6ac38a', 'the key (0617)'),
      ('public.ottoq_charge_queue_kernel_order(uuid,uuid,timestamp with time zone)', '7582ced2', 'the kernel''s order (0614)'),
      ('public.ottoq_charge_minutes_estimate(numeric,numeric,numeric,numeric,numeric)', '21f22ff8', 'the minutes estimate (0614)'),
      ('public.ottoq_charge_minutes_learned_with(jsonb,text,numeric,numeric,numeric,numeric,numeric)', '97486660', 'the learned minutes (0619)'),
      ('public.ottoq_learned_estimate(uuid,text)', 'ff910870', 'the latest fit (0619)'))
    AS x(sig, md5, what)
  LOOP
    IF left((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)), 8) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0620 P1: % is not the body this file was written against (md5 %); read it again', r.what, r.md5;
    END IF;
  END LOOP;
  IF to_regclass('public.ottoq_learned_estimates') IS NULL THEN
    RAISE EXCEPTION '0620 P1: 0619 is not applied (no ottoq_learned_estimates)';
  END IF;
  IF to_regprocedure('public.ottoq_charge_line_simulate(jsonb,jsonb,integer,text)') IS NOT NULL
     OR to_regprocedure('public.ottoq_hash_normal(text)') IS NOT NULL
     OR to_regclass('public.ottoq_charge_order_snapshots') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                 WHERE param_key IN ('agent_charge_order_futures', 'agent_charge_order_win_frac')) THEN
    RAISE EXCEPTION '0620 P1: something this file creates already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0620_the_kernel_takes_an_agent_order_only_when_it_wins_most_futures') THEN
    RAISE EXCEPTION '0620 P1: already applied';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0620_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)'::regprocedure,
                 'public.ottoq_agent_charge_order_usage(uuid,integer)'::regprocedure,
                 'public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)'::regprocedure);

-- ══ (g) the two dials ══════════════════════════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, agent_writable, affects, description)
VALUES
 ('agent_charge_order_futures', 1, 64, 12, false, 'ottoq_agent_charge_order_record (0620 rollout)',
  '0620: how many futures the kernel rolls the charge line forward in before it takes an agent''s charge order: the '
  'expected one and the rest sampled from the learned spread of charge times and arrivals (0619). A person''s dial, '
  'never the agent''s (rule 10).'),
 ('agent_charge_order_win_frac', 0.5, 1, 0.8, false, 'ottoq_agent_charge_order_record (0620 verdict)',
  '0620: the share of those futures in which the agent''s order must beat the kernel''s own for the kernel to take it '
  '(it must also win the expected one). 0.8 of 12 = 10. A person''s dial, never the agent''s (rule 10).');

-- ══ a normal draw that is a pure function of its key ═══════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_hash_normal(p_key text)
RETURNS double precision
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0620: a standard normal draw that is a pure function of p_key: Box-Muller over two 32-bit uniforms of md5(p_key).
  -- No sequence, no clock, no session state: the same key gives the same draw in every transaction.
  SELECT sqrt(-2.0 * ln(y.u1)) * cos(2.0 * pi() * y.u2)
    FROM (SELECT ((('x' || substr(x.h, 1, 8))::bit(32)::bigint) + 1)::float8 / 4294967297.0 AS u1,
                 (('x' || substr(x.h, 9, 8))::bit(32)::bigint)::float8 / 4294967296.0 AS u2
            FROM (SELECT md5(p_key) AS h) x) y
$fn$;

CREATE FUNCTION public.ottoq_charge_time_log_sd(p_model jsonb, p_kind text, p_soc numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0620: the learned log spread of a charge on p_kind from p_soc (0619's cell, else the kind's), 0 with no model.
  SELECT COALESCE(
           CASE WHEN (p_model #>> ARRAY['params', 'cells', p_kind || ':' || public.ottoq_charge_time_band(p_soc), 'usable']) = 'true'
                THEN (p_model #>> ARRAY['params', 'cells', p_kind || ':' || public.ottoq_charge_time_band(p_soc), 'log_sd'])::numeric END,
           CASE WHEN (p_model #>> ARRAY['params', 'cells', p_kind || ':*', 'usable']) = 'true'
                THEN (p_model #>> ARRAY['params', 'cells', p_kind || ':*', 'log_sd'])::numeric END,
           0)
$fn$;

-- ══ (a) the cars the depot can see coming ══════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_line_inbound(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz,
                                                 p_window_min numeric DEFAULT 180, p_return_model jsonb DEFAULT NULL)
RETURNS TABLE(vehicle_id uuid, eta_min numeric, soc_at_arrival numeric, source text, eta_log_sd numeric, trip_min numeric)
LANGUAGE sql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0620: a car driving home arrives at its dispatch's scheduled_return_at (distance over speed, 0320); a car at work is
  -- called home when its live battery reaches the learned reserve (0619 return_v1), at the learned drain, then drives the
  -- learned trip. With no usable return model, only the cars already driving home. Read-only.
  WITH m AS (
    SELECT COALESCE(p_return_model, public.ottoq_learned_estimate(p_depot_id, 'return_v1')) AS j
  ), p AS (
    SELECT COALESCE((m.j ->> 'usable')::boolean, false) AS usable,
           (m.j #>> '{params,threshold_soc}')::numeric AS thr,
           (m.j #>> '{params,drain_pct_per_min}')::numeric AS drain,
           COALESCE((m.j #>> '{params,drain_log_sd}')::numeric, 0) AS dsd,
           COALESCE((m.j #>> '{params,trip_min}')::numeric, 0) AS trip
      FROM m
  ), d AS (
    SELECT DISTINCT ON (d.vehicle_id) d.vehicle_id, d.status, d.scheduled_return_at, v.current_soc::numeric AS soc
      FROM public.ottoq_vehicle_dispatches d
      JOIN public.vehicles v ON v.id = d.vehicle_id
     WHERE d.sim_run_id = p_sim_run_id AND d.status IN ('active', 'returning') AND d.actual_return_at IS NULL
       AND v.home_depot_id = p_depot_id AND v.category = 'autonomous' AND v.current_soc IS NOT NULL
     ORDER BY d.vehicle_id, d.dispatched_at DESC
  )
  SELECT x.vehicle_id, round(x.eta, 2), round(GREATEST(x.soc, 0), 1), x.source, round(x.sd, 4), round(x.trip, 2)
    FROM (
      SELECT d.vehicle_id, GREATEST(extract(epoch FROM (d.scheduled_return_at - p_clock)) / 60.0, 0) AS eta,
             d.soc - COALESCE(p.drain, 0) * GREATEST(extract(epoch FROM (d.scheduled_return_at - p_clock)) / 60.0, 0) AS soc,
             'returning'::text AS source, 0::numeric AS sd, 0::numeric AS trip
        FROM d, p WHERE d.status = 'returning'
      UNION ALL
      SELECT d.vehicle_id, GREATEST((d.soc - p.thr) / p.drain, 0) + p.trip AS eta,
             LEAST(d.soc, p.thr) - p.drain * p.trip AS soc,
             'forecast'::text AS source, p.dsd AS sd, p.trip AS trip
        FROM d, p WHERE d.status = 'active' AND p.usable AND p.drain > 0 AND p.thr IS NOT NULL
    ) x
   WHERE x.eta <= COALESCE(p_window_min, 180)
$fn$;

-- ══ (b) the state a rollout reads ══════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_line_state(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0620: everything a charge-line rollout reads, once: the line (less a car holding a reserved charger, already
   assigned), the cars coming home within 180 minutes, the chargers (0618's gates), the order's life in minutes and the
   pin, every charge timed and spread by 0619's charge_time_v1. Read-only. */
DECLARE
  c_horizon constant numeric := 480;
  c_window  constant numeric := 180;
  v_ct jsonb := public.ottoq_learned_estimate(p_depot_id, 'charge_time_v1');
  v_rt jsonb := public.ottoq_learned_estimate(p_depot_id, 'return_v1');
  v_kw_d numeric; v_kw_l numeric; v_tick numeric; v_ttl numeric; v_pin numeric;
  v_cars jsonb; v_inb jsonb; v_ch jsonb;
BEGIN
  SELECT max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'dcfc'),
         max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'l2')
    INTO v_kw_d, v_kw_l
    FROM stalls s WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc', 'l2');
  SELECT CASE WHEN r.tick_count > 0 AND r.sim_clock_start IS NOT NULL AND r.sim_clock_current > r.sim_clock_start
              THEN extract(epoch FROM (r.sim_clock_current - r.sim_clock_start)) / 60.0 / r.tick_count END
    INTO v_tick FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  v_tick := COALESCE(v_tick, 0.25);
  v_ttl := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15) * v_tick;
  v_pin := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_pin_wait_min', 90), 90);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', x.id, 'w', round(x.wait_min, 2), 'g', round(x.gap, 2), 'imm', x.immediate, 'soc', x.soc,
           'due', x.due, 'dok', x.dok, 'lok', x.lok, 'md', x.md, 'ml', x.ml, 'sd', x.sdd, 'sl', x.sdl)
           ORDER BY x.kernel_pos), '[]'::jsonb)
    INTO v_cars
    FROM (SELECT k.vehicle_id AS id, k.kernel_pos, k.wait_min, k.gap, k.immediate, k.soc,
                 round(extract(epoch FROM (vn.dispatch_due_at - p_clock)) / 60.0, 2) AS due,
                 public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'dcfc') AS dok,
                 public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2') AS lok,
                 public.ottoq_charge_minutes_learned_with(v_ct, 'dcfc', v.battery_capacity_kwh, k.soc, tg.t, v_kw_d, v.inlet_max_kw) AS md,
                 public.ottoq_charge_minutes_learned_with(v_ct, 'l2', v.battery_capacity_kwh, k.soc, tg.t, v_kw_l, v.inlet_max_kw) AS ml,
                 public.ottoq_charge_time_log_sd(v_ct, 'dcfc', k.soc) AS sdd,
                 public.ottoq_charge_time_log_sd(v_ct, 'l2', k.soc) AS sdl
            FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, p_depot_id, p_clock) k
            JOIN vehicles v ON v.id = k.vehicle_id
            CROSS JOIN LATERAL (SELECT public.ottoq_effective_target_soc_at(v.id, p_clock) AS t) tg
            LEFT JOIN LATERAL (SELECT vn.dispatch_due_at FROM ottoq_visit_needs vn
                                WHERE vn.vehicle_id = v.id AND vn.status IN ('open', 'in_progress')
                                  AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                                    = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                                ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) vn ON true
           WHERE NOT k.holds_charger) x
   WHERE x.md IS NOT NULL AND x.ml IS NOT NULL;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', i.vehicle_id, 'eta', i.eta_min, 'src', i.source, 'esd', i.eta_log_sd, 'trip', i.trip_min,
           'soc', i.soc_at_arrival, 'g', round(GREATEST(tg.t - i.soc_at_arrival, 1), 2), 'imm', false, 'w', 0,
           'dok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'dcfc'),
           'lok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2'),
           'md', public.ottoq_charge_minutes_learned_with(v_ct, 'dcfc', v.battery_capacity_kwh, i.soc_at_arrival, tg.t, v_kw_d, v.inlet_max_kw),
           'ml', public.ottoq_charge_minutes_learned_with(v_ct, 'l2', v.battery_capacity_kwh, i.soc_at_arrival, tg.t, v_kw_l, v.inlet_max_kw),
           'sd', public.ottoq_charge_time_log_sd(v_ct, 'dcfc', i.soc_at_arrival),
           'sl', public.ottoq_charge_time_log_sd(v_ct, 'l2', i.soc_at_arrival))
           ORDER BY i.eta_min, i.vehicle_id), '[]'::jsonb)
    INTO v_inb
    FROM public.ottoq_charge_line_inbound(p_sim_run_id, p_depot_id, p_clock, c_window, v_rt) i
    JOIN vehicles v ON v.id = i.vehicle_id
    CROSS JOIN LATERAL (SELECT public.ottoq_effective_target_soc_at(v.id, p_clock) AS t) tg
   WHERE i.soc_at_arrival < tg.t - 1 AND v.battery_capacity_kwh IS NOT NULL;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', y.id, 'k', y.kind, 'free', y.free_at, 'sd', y.sd)
                            ORDER BY y.kind, y.free_at, y.id), '[]'::jsonb)
    INTO v_ch
    FROM (
      SELECT s.id, s.stall_type::text AS kind,
             CASE WHEN s.current_vehicle_id IS NULL THEN 0::numeric
                  ELSE public.ottoq_charge_minutes_learned_with(v_ct, s.stall_type::text, cv.battery_capacity_kwh, cv.current_soc,
                         public.ottoq_effective_target_soc_at(cv.id, p_clock), s.connector_max_kw, cv.inlet_max_kw) END AS free_at,
             CASE WHEN s.current_vehicle_id IS NULL THEN 0::numeric
                  ELSE public.ottoq_charge_time_log_sd(v_ct, s.stall_type::text, cv.current_soc) END AS sd
        FROM stalls s
        JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
        LEFT JOIN vehicles cv ON cv.id = s.current_vehicle_id
       WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc', 'l2')
         AND c.station_state IS DISTINCT FROM 'Faulted'
         AND (   (s.current_vehicle_id IS NULL
                  AND NOT (s.reserved_by IS NOT NULL AND COALESCE(s.reservation_expires_at, 'infinity'::timestamptz) > p_clock)
                  AND c.station_state = 'Available' AND c.last_heartbeat_at >= p_clock - interval '90 seconds'
                  AND NOT EXISTS (SELECT 1 FROM ottoq_stall_bookings b
                                   WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                                     AND b.state IN ('held', 'active', 'done', 'interrupted') AND b.during @> p_clock))
              OR cv.current_state::text IN ('charging_dcfc', 'charging_l2'))) y
   WHERE y.free_at IS NOT NULL;

  RETURN jsonb_build_object(
    'v', 1, 'clock', p_clock, 'tick_min', round(v_tick, 4), 'ttl_min', round(v_ttl, 3), 'pin_min', v_pin,
    'horizon_min', c_horizon, 'arrival_window_min', c_window,
    'models', jsonb_build_object('charge_time', v_ct -> 'estimate_id', 'return', v_rt -> 'estimate_id',
                                 'return_usable', COALESCE((v_rt ->> 'usable')::boolean, false)),
    'cars', v_cars, 'inbound', v_inb, 'chargers', v_ch);
END $fn$;

-- ══ (c) the simulator ══════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_line_simulate(p_state jsonb, p_order jsonb, p_scenario integer, p_seed text)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
/* 0620: the charge cursor as a list schedule from p_state (ottoq_charge_line_state), in the kernel's own order when
   p_order is NULL or '{}', else under p_order ({vehicle_id: {rank, kind}}) for the order's life (ttl_min) and the
   kernel's after. Scenario 0 is the expected future; scenario s > 0 draws every car's charge minutes, every running
   charge's remaining minutes and every forecast arrival from md5(seed, s, id): the same draws for any order (common
   random numbers). Pure: no table is read. Every car charges to its full target (rule 9). */
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
  s_id text[] := '{}'; s_k text[] := '{}'; s_free float8[] := '{}';
  n int := 0; m int := 0; i int; j int; best int; t float8 := 0; t_c float8; t_a float8; t_next float8;
  v_seated int := 0; v_any boolean; v_live boolean; v_mode text; v_dur float8; v_want text; z float8; v_free_n int;
  e jsonb; v_inbound boolean; v_rk text; v_order int[]; v_first text[] := '{}';
  v_out jsonb;
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
    IF COALESCE(p_scenario, 0) > 0 AND s_free[m] > 0 THEN
      z := public.ottoq_hash_normal(COALESCE(p_seed, '') || ':' || p_scenario || ':' || s_id[m] || ':running');
      s_free[m] := s_free[m] * exp(COALESCE((e ->> 'sd')::float8, 0) * z);
    END IF;
  END LOOP;

  c_ready := array_fill(NULL::float8, ARRAY[GREATEST(n, 1)]);
  c_start := array_fill(NULL::float8, ARRAY[GREATEST(n, 1)]);
  c_kind  := array_fill(NULL::text, ARRAY[GREATEST(n, 1)]);

  WHILE v_seated < n AND m > 0 LOOP
    -- the first moment a charger is free and a car is waiting
    SELECT min(f) INTO t_c FROM unnest(s_free) f;
    SELECT min(u.a) INTO t_a FROM unnest(c_av, c_ready) AS u(a, r) WHERE u.r IS NULL;
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
             WHERE z3.i <= n AND c_ready[z3.i] IS NULL AND c_av[z3.i] <= t) u;
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
      s_free[best] := t + GREATEST(v_dur, 0.01);
      v_seated := v_seated + 1; v_any := true; v_free_n := v_free_n - 1;
      IF t < v_ttl THEN
        v_first := v_first || (c_id[i] || '@' || s_k[best] || '@' || to_char(t, 'FM99990.00'));
      END IF;
    END LOOP;
    IF NOT v_any THEN
      -- no car waiting can use a charger free at t: those chargers wait for the next charger to free or car to arrive
      SELECT min(f) INTO t_c FROM unnest(s_free) f WHERE f > t;
      SELECT min(u.a) INTO t_a FROM unnest(c_av, c_ready) AS u(a, r) WHERE u.r IS NULL AND u.a > t;
      t_next := LEAST(t_c, t_a);
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
  RETURN v_out;
END $fn$;

-- ══ (d) the comparison and the rollout ═════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_line_compare(p_kernel jsonb, p_agent jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0620: is the agent's side better (+1), worse (-1) or no different (0)? The owner's requirement first (rule 9): cars
  -- ready by their due time; then summed lateness (half a minute of rounding); then summed minutes in the depot (one).
  SELECT jsonb_build_object('cmp', x.cmp, 'by', x.by, 'd_on_time', x.dot, 'd_late', x.dl, 'd_flow', x.df)
    FROM (SELECT CASE WHEN s.ao > s.ko THEN 1 WHEN s.ao < s.ko THEN -1
                      WHEN s.al < s.kl - 0.5 THEN 1 WHEN s.al > s.kl + 0.5 THEN -1
                      WHEN s.af < s.kf - 1.0 THEN 1 WHEN s.af > s.kf + 1.0 THEN -1 ELSE 0 END AS cmp,
                 CASE WHEN s.ao <> s.ko THEN 'on_time' WHEN abs(s.al - s.kl) > 0.5 THEN 'lateness'
                      WHEN abs(s.af - s.kf) > 1.0 THEN 'flow' ELSE 'tie' END AS by,
                 s.ao - s.ko AS dot, round(s.al - s.kl, 2) AS dl, round(s.af - s.kf, 2) AS df
            FROM (SELECT COALESCE((p_kernel ->> 'on_time')::int, 0) AS ko, COALESCE((p_agent ->> 'on_time')::int, 0) AS ao,
                         COALESCE((p_kernel ->> 'late_sum')::numeric, 0) AS kl, COALESCE((p_agent ->> 'late_sum')::numeric, 0) AS al,
                         COALESCE((p_kernel ->> 'flow_sum')::numeric, 0) AS kf, COALESCE((p_agent ->> 'flow_sum')::numeric, 0) AS af) s) x
$fn$;

CREATE FUNCTION public.ottoq_charge_line_rollout(p_state jsonb, p_order jsonb, p_futures integer, p_seed text)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
/* 0620: the line rolled forward in the kernel's order and in p_order, in the expected future and p_futures - 1 sampled
   ones (common random numbers from p_seed). When both seat the same cars on the same kinds at the same moments in the
   order's window, the expected future is the only one run: the order changes nothing. */
DECLARE
  v_n int := GREATEST(1, LEAST(COALESCE(p_futures, 12), 64));
  k0 jsonb; a0 jsonb; k jsonb; a jsonb; c jsonb; c0 jsonb; s int;
  v_w int := 0; v_t int := 0; v_l int := 0; v_per jsonb := '[]'::jsonb;
BEGIN
  k0 := public.ottoq_charge_line_simulate(p_state, NULL, 0, p_seed);
  a0 := public.ottoq_charge_line_simulate(p_state, p_order, 0, p_seed);
  c0 := public.ottoq_charge_line_compare(k0, a0);
  IF (k0 -> 'first') = (a0 -> 'first') THEN
    RETURN jsonb_build_object('same_first_seats', true, 'futures', 1, 'wins', 0, 'ties', 1, 'losses', 0,
                              'point', c0 || jsonb_build_object('kernel', k0 - 'first', 'agent', a0 - 'first'),
                              'first', jsonb_build_object('kernel', k0 -> 'first', 'agent', a0 -> 'first'),
                              'per', '[]'::jsonb);
  END IF;
  FOR s IN 0 .. v_n - 1 LOOP
    IF s = 0 THEN
      c := c0;
    ELSE
      k := public.ottoq_charge_line_simulate(p_state, NULL, s, p_seed);
      a := public.ottoq_charge_line_simulate(p_state, p_order, s, p_seed);
      c := public.ottoq_charge_line_compare(k, a);
    END IF;
    IF (c ->> 'cmp')::int > 0 THEN v_w := v_w + 1; ELSIF (c ->> 'cmp')::int < 0 THEN v_l := v_l + 1; ELSE v_t := v_t + 1; END IF;
    v_per := v_per || jsonb_build_array(jsonb_build_array((c ->> 'cmp')::int, c ->> 'by', (c ->> 'd_on_time')::int,
                                                          (c ->> 'd_late')::numeric, (c ->> 'd_flow')::numeric));
  END LOOP;
  RETURN jsonb_build_object('same_first_seats', false, 'futures', v_n, 'wins', v_w, 'ties', v_t, 'losses', v_l,
                            'point', c0 || jsonb_build_object('kernel', k0 - 'first', 'agent', a0 - 'first'),
                            'first', jsonb_build_object('kernel', k0 -> 'first', 'agent', a0 -> 'first'),
                            'per', v_per);
END $fn$;

-- ══ (e) the verdict ════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_order_verdict_v2(p_rollout jsonb, p_win_frac numeric)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0620: take the agent's order only when it wins the expected future and at least ceil(win_frac x futures) of all.
  -- 'kernel' and 'agent' are the expected future's two sides, as 0618's projection carried them.
  SELECT jsonb_build_object(
           'take', x.take, 'reason', x.reason, 'futures', x.n, 'wins', x.w, 'ties', x.ti, 'losses', x.l, 'need', x.need,
           'win_frac', p_win_frac, 'expected', x.pcmp, 'expected_by', x.pby,
           'kernel', p_rollout #> '{point,kernel}', 'agent', p_rollout #> '{point,agent}',
           'first', p_rollout -> 'first', 'per', p_rollout -> 'per')
    FROM (SELECT s.n, s.w, s.ti, s.l, s.need, s.pcmp, s.pby,
                 (NOT s.same AND s.pcmp = 1 AND s.w >= s.need) AS take,
                 CASE WHEN s.n IS NULL THEN 'no_rollout'
                      WHEN s.same THEN 'same_as_kernel'
                      WHEN s.pcmp < 0 THEN 'worse_in_expected_future'
                      WHEN s.pcmp = 0 THEN 'no_better_in_expected_future'
                      WHEN s.w < s.need THEN 'not_enough_futures_won'
                      ELSE 'wins_most_futures' END AS reason
            FROM (SELECT (p_rollout ->> 'futures')::int AS n, COALESCE((p_rollout ->> 'wins')::int, 0) AS w,
                         COALESCE((p_rollout ->> 'ties')::int, 0) AS ti, COALESCE((p_rollout ->> 'losses')::int, 0) AS l,
                         COALESCE((p_rollout ->> 'same_first_seats')::boolean, false) AS same,
                         COALESCE((p_rollout #>> '{point,cmp}')::int, 0) AS pcmp, p_rollout #>> '{point,by}' AS pby,
                         ceil(COALESCE(p_win_frac, 0.8) * COALESCE((p_rollout ->> 'futures')::int, 1))::int AS need) s) x
$fn$;

-- ══ (f) the snapshots ══════════════════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_charge_order_snapshots (
  --: the order this state was checked for (ottoq_agent_charge_orders.order_id). NO foreign key, deliberately: evidence
  --: outlives ottoq_purge_prior_runs (0340/0364), and so does the order row it names.
  order_id     bigint PRIMARY KEY,
  sim_run_id   uuid NOT NULL,
  depot_id     uuid,
  sim_clock    timestamptz,
  seed         text NOT NULL,
  futures      integer NOT NULL,
  win_frac     numeric NOT NULL,
  --: ottoq_charge_line_state as the check read it, and the order map it ran ({vehicle_id: {rank, kind}})
  state        jsonb NOT NULL,
  agent_order  jsonb NOT NULL,
  --: md5 of the simulator, comparison, rollout and verdict as they judged this order
  code_md5     text NOT NULL,
  recorded_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.ottoq_charge_order_snapshots IS
'0620. One row per agent charge order the kernel checked: the state its rollout read (ottoq_charge_line_state), the order it ran, the seed, the futures and the bar, and the md5 of the code that judged it, so the check can be replayed, and replayed with what actually happened (0621). Class=evidence with NO foreign key (0340/0364). Append-only (override: ottoq.charge_order_snapshots_unlock=on).';

CREATE INDEX ottoq_charge_order_snapshots_run_idx ON public.ottoq_charge_order_snapshots (sim_run_id, order_id);

CREATE FUNCTION public.ottoq_charge_order_snapshots_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.charge_order_snapshots_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_charge_order_snapshots is append-only: % refused. Set ottoq.charge_order_snapshots_unlock=on in the session to '
    'override, and say why in a migration.', TG_OP
    USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_charge_order_snapshots_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_charge_order_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_charge_order_snapshots_append_only();

ALTER TABLE public.ottoq_charge_order_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_charge_order_snapshots_read ON public.ottoq_charge_order_snapshots FOR SELECT USING (true);
REVOKE ALL ON public.ottoq_charge_order_snapshots FROM anon, authenticated;
GRANT SELECT ON public.ottoq_charge_order_snapshots TO anon, authenticated;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_charge_order_snapshots', 'sim_run_id', 'evidence',
        '0620: the state each agent charge order was checked against, the order, the seed and the code: what makes the '
        'kernel''s check of the agent replayable, in hindsight too (0621). Evidence, not engine. NO foreign key to '
        'ottoq_sim_runs, as 0340 and 0364.');

-- ══ (h) the door ═══════════════════════════════════════════════════════════════════════════════════════════════════════
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
              md5(pg_get_functiondef('public.ottoq_charge_line_simulate(jsonb,jsonb,integer,text)'::regprocedure)
                  || pg_get_functiondef('public.ottoq_charge_line_compare(jsonb,jsonb)'::regprocedure)
                  || pg_get_functiondef('public.ottoq_charge_line_rollout(jsonb,jsonb,integer,text)'::regprocedure)
                  || pg_get_functiondef('public.ottoq_charge_order_verdict_v2(jsonb,numeric)'::regprocedure)));
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0620: the snapshot of order % was not written: %', v_order_id, SQLERRM;
    END;
  END IF;

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

-- ══ (h) what the orders did: futures won, and refusals by reason ═══════════════════════════════════════════════════════
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
               'seats', (SELECT count(*) FROM t WHERE t.order_id = o.order_id),
               'seats_by_rank', (SELECT count(*) FROM t WHERE t.order_id = o.order_id AND t.by_rank),
               'moved_ahead', (SELECT count(*) FROM t WHERE t.order_id = o.order_id AND t.by_rank
                                                       AND t.kernel_pos > t.seats_in_tick))
             ORDER BY o.order_id DESC)
        FROM (SELECT * FROM o ORDER BY o.order_id DESC LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 200))) o), '[]'::jsonb))
$function$;

-- ══ (h) the agent's board: the learned clock, the line's contention, the cars coming home, the check's bar ════════════
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
    'usage', public.ottoq_agent_charge_order_usage(p_sim_run_id, 3))
$function$;

GRANT EXECUTE ON FUNCTION public.ottoq_hash_normal(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_line_simulate(jsonb, jsonb, integer, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_line_rollout(jsonb, jsonb, integer, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_line_compare(jsonb, jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_order_verdict_v2(jsonb, numeric) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_charge_line_state(uuid, uuid, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_charge_line_inbound(uuid, uuid, timestamptz, numeric, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_line_state(uuid, uuid, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_line_inbound(uuid, uuid, timestamptz, numeric, jsonb) TO service_role;

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v1$
DECLARE v_mean float8; v_sd float8;
BEGIN
  IF public.ottoq_hash_normal('0620:a') IS DISTINCT FROM public.ottoq_hash_normal('0620:a')
     OR public.ottoq_hash_normal('0620:a') = public.ottoq_hash_normal('0620:b') THEN
    RAISE EXCEPTION '0620 V1: the normal draw is not a pure function of its key';
  END IF;
  SELECT avg(z), stddev(z) INTO v_mean, v_sd
    FROM (SELECT public.ottoq_hash_normal('0620:v1:' || g) AS z FROM generate_series(1, 4000) g) x;
  IF abs(v_mean) > 0.08 OR v_sd < 0.92 OR v_sd > 1.08 THEN
    RAISE EXCEPTION '0620 V1: the normal draw is off: mean %, sd %', v_mean, v_sd;
  END IF;
END $v1$;

DO $v2$
DECLARE
  -- one fast charger and one L2, both free; three cars waiting 0 minutes: A at 30% (40 min fast / 200 on L2), B at 90%
  -- (20 / 30), C at 60% due in 50 minutes (30 / 120). Kernel: the response ratio ties at 1, so battery: A, then C;
  -- A wants fast (below 45) and takes it, C wants L2 and takes it; B waits for the fast charger at 40 (60).
  -- Ready: A 40, C 120 (due 50: late 70), B 60: on time 0, lateness 70, minutes 220.
  st jsonb := '{"ttl_min": 5, "pin_min": 90, "horizon_min": 480,
                "cars": [{"id": "a", "w": 0, "g": 70, "imm": false, "soc": 30, "due": null, "md": 40, "ml": 200},
                         {"id": "b", "w": 0, "g": 10, "imm": false, "soc": 90, "due": null, "md": 20, "ml": 30},
                         {"id": "c", "w": 0, "g": 40, "imm": false, "soc": 60, "due": 50, "md": 30, "ml": 120}],
                "inbound": [], "chargers": [{"id": "f", "k": "dcfc", "free": 0}, {"id": "l", "k": "l2", "free": 0}]}';
  k jsonb; a jsonb; v jsonb;
BEGIN
  k := public.ottoq_charge_line_simulate(st, NULL, 0, 's');
  IF (k ->> 'on_time')::int <> 0 OR (k ->> 'late_sum')::numeric <> 70 OR (k ->> 'flow_sum')::numeric <> 220 THEN
    RAISE EXCEPTION '0620 V2: the kernel''s line is not the hand-computed one: %', k;
  END IF;
  -- the agent: C first on the fast charger (ready 30, on time), A on the L2 (200), B on the fast charger at 30 (50)
  a := public.ottoq_charge_line_simulate(st, '{"c": {"rank": 1, "kind": "dcfc"}, "a": {"rank": 2, "kind": "l2"}}', 0, 's');
  IF (a ->> 'on_time')::int <> 1 OR (a ->> 'late_sum')::numeric <> 0 OR (a ->> 'flow_sum')::numeric <> 280 THEN
    RAISE EXCEPTION '0620 V2: the agent''s line is not the hand-computed one: %', a;
  END IF;
  v := public.ottoq_charge_line_compare(k, a);
  IF (v ->> 'cmp')::int <> 1 OR v ->> 'by' <> 'on_time' THEN
    RAISE EXCEPTION '0620 V2: a car made ready by its due time must win on on_time: %', v;
  END IF;
  -- the kernel's own order sent as an order changes no seat
  IF NOT (public.ottoq_charge_line_rollout(st, '{"a": {"rank": 1, "kind": "dcfc"}, "c": {"rank": 2, "kind": "l2"}}', 12, 's')
          ->> 'same_first_seats')::boolean THEN
    RAISE EXCEPTION '0620 V2: the kernel''s own order sent as an order should seat the same cars';
  END IF;
END $v2$;

DO $v3$
DECLARE r jsonb;
BEGIN
  r := '{"futures": 12, "wins": 10, "ties": 1, "losses": 1, "same_first_seats": false, "point": {"cmp": 1, "by": "flow"}}';
  IF NOT (public.ottoq_charge_order_verdict_v2(r, 0.8) ->> 'take')::boolean
     OR public.ottoq_charge_order_verdict_v2(r, 0.8) ->> 'reason' <> 'wins_most_futures'
     OR (public.ottoq_charge_order_verdict_v2(r, 0.8) ->> 'need')::int <> 10
     OR (public.ottoq_charge_order_verdict_v2(r, 0.9) ->> 'take')::boolean
     OR public.ottoq_charge_order_verdict_v2(r, 0.9) ->> 'reason' <> 'not_enough_futures_won'
     OR public.ottoq_charge_order_verdict_v2(jsonb_set(r, '{point,cmp}', '0'), 0.8) ->> 'reason' <> 'no_better_in_expected_future'
     OR public.ottoq_charge_order_verdict_v2(jsonb_set(r, '{point,cmp}', '-1'), 0.8) ->> 'reason' <> 'worse_in_expected_future'
     OR (public.ottoq_charge_order_verdict_v2(jsonb_set(r, '{point,cmp}', '-1'), 0.8) ->> 'take')::boolean
     OR public.ottoq_charge_order_verdict_v2(r || '{"same_first_seats": true}', 0.8) ->> 'reason' <> 'same_as_kernel'
     OR (public.ottoq_charge_order_verdict_v2(r || '{"same_first_seats": true}', 0.8) ->> 'take')::boolean
     OR public.ottoq_charge_order_verdict_v2(NULL, 0.8) ->> 'reason' <> 'no_rollout'
     OR (public.ottoq_charge_order_verdict_v2(NULL, 0.8) ->> 'take')::boolean THEN
    RAISE EXCEPTION '0620 V3: the verdict''s truth table is wrong';
  END IF;
END $v3$;

DO $v4$
DECLARE r record; s jsonb; v_map jsonb; t0 timestamptz; ro jsonb;
BEGIN
  SELECT x.sim_run_id, x.depot_id, x.sim_clock_current INTO r
    FROM public.ottoq_sim_runs x
   WHERE x.status = 'running' AND x.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY x.started_at DESC LIMIT 1;
  IF r.sim_run_id IS NULL THEN
    RAISE NOTICE '0620 V4: no twin run is running; the rollout is executed by the tests on stubs';
    RETURN;
  END IF;
  s := public.ottoq_charge_line_state(r.sim_run_id, r.depot_id, r.sim_clock_current);
  SELECT jsonb_object_agg(c ->> 'id', jsonb_build_object('rank', c.o, 'kind', 'either'))
    INTO v_map FROM jsonb_array_elements(s -> 'cars') WITH ORDINALITY AS c(c, o);
  IF jsonb_array_length(s -> 'cars') > 0
     AND NOT (public.ottoq_charge_line_rollout(s, v_map, 12, 'v4') ->> 'same_first_seats')::boolean THEN
    RAISE EXCEPTION '0620 V4: the kernel''s own line sent as an order should change no seat';
  END IF;
  SELECT jsonb_object_agg(c ->> 'id', jsonb_build_object('rank', jsonb_array_length(s -> 'cars') + 1 - c.o, 'kind', 'either'))
    INTO v_map FROM jsonb_array_elements(s -> 'cars') WITH ORDINALITY AS c(c, o);
  t0 := clock_timestamp();
  ro := public.ottoq_charge_order_verdict_v2(public.ottoq_charge_line_rollout(s, v_map, 12, 'v4'), 0.8);
  RAISE NOTICE '0620 V4 on run %: % cars, % coming home, % chargers; the line reversed: % (% of % futures won) in % ms',
    r.sim_run_id, jsonb_array_length(s -> 'cars'), jsonb_array_length(s -> 'inbound'), jsonb_array_length(s -> 'chargers'),
    ro ->> 'reason', ro ->> 'wins', ro ->> 'futures', round(extract(epoch FROM clock_timestamp() - t0) * 1000);
END $v4$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0620_the_kernel_takes_an_agent_order_only_when_it_wins_most_futures', false, false,
  'The agent''s charge-order door rolls the line forward in the kernel''s order and the agent''s (its ttl, then the '
  'kernel''s), with the cars coming home and the learned charge clock, over the expected future and sampled ones, and '
  'takes the order only when it wins the expected one and 80% of all; snapshots for replay; the board shows contention, '
  'arrivals and the bar. FALSE/FALSE: the tick path is untouched and orders exist only on operator_demo runs (0615).',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
