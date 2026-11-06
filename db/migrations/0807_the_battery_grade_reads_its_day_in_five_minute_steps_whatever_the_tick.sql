-- migration-version: 20261106184139
-- migration-name:    the_battery_grade_reads_its_day_in_five_minute_steps_whatever_the_tick
--
-- 0807  **The battery's daily grade reads its day in 5-minute steps, whatever the tick.** (G527; B2, the battery's
--        hindsight)
--
-- ══ §0 WHY NOW ══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0805 (applied 2026-11-06 17:53:21 UTC) grades each day the battery ran against perfect foresight. It was measured in the
--   research lab on days that tick every 5 minutes. Read on production's latest run after the apply, it rounds a
--   fast-ticking run's step to 0 minutes (G527). Its dial is off and the edge function is not deployed, so no grade has
--   been fired; this file is the fix before the dial is switched on.
--
-- ══ §1 WHAT IS WRONG (FINDINGS G527; read on production 2026-11-06 17:58:31 and 18:03:36 UTC) ════════════════════════
--
--   ottoq_bess_hindsight_segment takes its step as the mean snapshot interval rounded to whole minutes, its 30-minute
--   demand window as 30 / step snapshots, and grades any run-day with 24 snapshots. 55 of the 57 operator demo runs started
--   at the twin depot in the last 60 days ticked under 5 sim-minutes (median 14.7 sim-seconds a tick). On the latest,
--   edf611ad (2026-11-04, 8:02-8:16 AM CT), 74 snapshots span 14.6 sim-minutes: the step rounds to 0, the demand window to
--   one snapshot, perfect foresight's request would carry step_min 0, and the slice bills $622.25 realized ($608.37 of it
--   demand) against $833.32 with no battery: a grade of nothing.
--
-- ══ §2 WHAT THIS CHANGES (one function replaced; nothing in the engine reads it) ═════════════════════════════════════
--
--   ottoq_bess_hindsight_segment reads the day in 5-minute steps of sim time, the planner's own step, whatever the tick:
--   each snapshot holds until the next (the last for the interval before it), as before and as the research lab's
--   bound_energy.py bills; each step is the time-weighted mean of what held over it; the demand charge falls on the highest
--   6 steps (30 minutes); perfect foresight's request has one load, price and floor a step, step_min 5 and window_steps 6;
--   and a day is graded only with 24 steps (2 hours of the run in it). Energy is still each snapshot's draw at its rate for
--   its interval, and wear each snapshot's discharge. At a 5-minute tick a step is a snapshot and the grade is the one 0805
--   gave. Its result's shape is unchanged, so the fire, the landing, the sweep and the board are untouched.
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 not applied; 0805 applied and its segment the body production carries (prosrc md5 0acfd7ce,
--   read 2026-11-06 18:08:44 UTC). The pre-image to ottoq_schema_snapshots as '0807_pre'.
--   V1 the new body is byte for byte the one the research lab ran. V2 on the twin's latest run, rolled back with its rows:
--   one day's load drawn at a 15-second tick and the next day's the same load averaged over 5-minute ticks, 8 to 11 AM,
--   grade alike (both 36 steps of 5 minutes; the bills within a cent; the peaks within 0.1 kW; perfect foresight's
--   loads within 0.1 kW a step and its prices equal); and a part-day of under 2 hours is not graded. Skipped with a
--   notice when the twin depot has no run.
--   In the research lab (2026-11-06; lab/research/p2_capacity/g528_lab_2026-11-06.md): at the 5-minute tick the grade is
--   0805's to the value (424242_b36, the window from 6 PM day 1 and both local days: 0 of 903, 687 and 686 values
--   differing; realized $1,539.61 as bound_energy.py); at a 2-minute tick energy ($765.55) and wear as bound_energy.py and
--   the peaks 2-3 kW lower on the 5-minute grid (realized $1,484.35 against $1,485.76); V1 and V2 passed.
--
-- ══ §4 LINEAGE ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: no function the engine runs is changed; the grade is evidence for
--   people (rule 10), behind bess_hindsight_enabled (0).
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0807_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0807_the_battery_grade_reads_its_day_in_five_minute_steps_whatever_the_tick'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0807 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0807_the_battery_grade_reads_its_day_in_five_minute_steps_whatever_the_tick') THEN
    RAISE EXCEPTION '0807 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0805_the_battery_grades_its_day_against_perfect_foresight') THEN
    RAISE EXCEPTION '0807 P1: 0805 (the battery''s daily grade) comes first';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_bess_hindsight_segment(uuid,uuid,timestamp with time zone,timestamp with time zone)'))
     IS DISTINCT FROM '0acfd7ce5efcdf94fa8f6dcf0b121b34' THEN
    RAISE EXCEPTION '0807 P1: public.ottoq_bess_hindsight_segment is not the body 0805 left (0acfd7ce)';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0807_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_bess_hindsight_segment(uuid,uuid,timestamp with time zone,timestamp with time zone)'::regprocedure;

CREATE OR REPLACE FUNCTION public.ottoq_bess_hindsight_segment(p_sim_run_id uuid, p_depot_id uuid,
    p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0805, 0807: the grade's inputs for the run's snapshots in (p_from, p_to]: {steps, realized, no_battery, battery, request},
   or NULL under 24 five-minute steps (2 hours) or without a battery. Each snapshot holds until the next (the last for the
   interval before it), as the research lab's bound_energy.py bills. The day is read in 5-minute steps of sim time, the
   planner's own step, each the time-weighted mean of what held over it (0807, G527: the twin's demo runs tick every 15
   sim-seconds or so, and a step taken from the tick rounded to 0 minutes): the demand charge falls on the highest 6 steps
   (30 minutes) at the day plan's daily rate, and perfect foresight plans in those steps. Energy at each snapshot's rate on
   the grid drawn (never below zero), wear per kWh discharged. At a 5-minute tick a step is a snapshot. Design: 0805 §2(b),
   0807 §2. */
DECLARE
  c_tz CONSTANT text := 'America/Chicago';
  c_step CONSTANT numeric := 5;
  c_win CONSTANT int := 6;
  v_t timestamptz[]; v_pre numeric[]; v_grid numeric[]; v_out numeric[]; v_rate numeric[]; v_dt numeric[];
  v_n int; i int; b record; v_rt numeric; v_eff numeric; v_lo numeric; v_hi numeric;
  v_e0 numeric; v_e1 numeric; v_month int; v_season text; v_d_rate numeric; v_amort numeric; v_d_day numeric;
  v_min_rate numeric; v_c_rep numeric; v_c_deg numeric; v_dr_kwh numeric; v_dr_s numeric; v_dr_e numeric; v_lead numeric;
  v_hf numeric; v_r numeric; v_floor numeric[] := ARRAY[]::numeric[];
  v_bt timestamptz[]; v_bpre numeric[]; v_bg numeric[]; v_bgn numeric[]; v_brate numeric[]; v_nb int;
  v_real jsonb; v_none jsonb; v_modes jsonb; v_follow numeric;
BEGIN
  SELECT array_agg(t ORDER BY t), array_agg(pre ORDER BY t), array_agg(grid ORDER BY t), array_agg(bout ORDER BY t),
         array_agg(rate ORDER BY t)
    INTO v_t, v_pre, v_grid, v_out, v_rate
    FROM (SELECT e.timestamp AS t,
                 COALESCE(e.total_ev_charging_kw, 0) + COALESCE(e.building_load_kw, 0) + COALESCE(e.lighting_load_kw, 0)
                 - COALESCE(e.solar_generation_kw, 0) AS pre,
                 COALESCE(e.grid_import_kw, 0) - COALESCE(e.grid_export_kw, 0) AS grid, COALESCE(e.bess_output_kw, 0) AS bout,
                 COALESCE((SELECT t.out_rate_usd_kwh FROM twin.ottoq_sim_current_tariff(p_depot_id, e.timestamp) t), 0.07) AS rate
            FROM site_energy_snapshots e
           WHERE e.sim_run_id = p_sim_run_id AND e.depot_id = p_depot_id AND e.timestamp > p_from AND e.timestamp <= p_to) s;
  v_n := COALESCE(cardinality(v_t), 0);
  IF v_n < 2 THEN RETURN NULL; END IF;
  v_dt := ARRAY(SELECT CASE WHEN k < v_n THEN GREATEST(EXTRACT(EPOCH FROM (v_t[k + 1] - v_t[k])) / 3600.0, 1e-6)
                            ELSE GREATEST(EXTRACT(EPOCH FROM (v_t[v_n] - v_t[v_n - 1])) / 3600.0, 1e-6) END
                  FROM generate_series(1, v_n) k ORDER BY k);

  -- the day in 5-minute steps of sim time: each the time-weighted mean of the snapshots that hold over it (0807)
  WITH s AS (SELECT v_t[k] AS t0, v_t[k] + make_interval(secs => (v_dt[k] * 3600)::double precision) AS t1,
                    v_pre[k] AS pre, v_grid[k] AS g, GREATEST(v_pre[k], 0) AS gn, v_rate[k] AS r
               FROM generate_series(1, v_n) k),
       st AS (SELECT generate_series(date_bin(interval '5 minutes', v_t[1], timestamptz '2000-01-01 00:00:00+00'),
                                     (SELECT max(t1) FROM s) - interval '1 microsecond', interval '5 minutes') AS b0),
       ov AS (SELECT st.b0, s.pre, s.g, s.gn, s.r,
                     EXTRACT(EPOCH FROM (LEAST(s.t1, st.b0 + interval '5 minutes') - GREATEST(s.t0, st.b0))) AS w
                FROM st JOIN s ON s.t0 < st.b0 + interval '5 minutes' AND s.t1 > st.b0),
       bs AS (SELECT b0, sum(w * pre) / sum(w) AS pre, sum(w * g) / sum(w) AS g, sum(w * gn) / sum(w) AS gn,
                     round(sum(w * r) / sum(w), 6) AS r
                FROM ov WHERE w > 0 GROUP BY b0)
  SELECT array_agg(b0 ORDER BY b0), array_agg(pre ORDER BY b0), array_agg(g ORDER BY b0), array_agg(gn ORDER BY b0),
         array_agg(r ORDER BY b0)
    INTO v_bt, v_bpre, v_bg, v_bgn, v_brate FROM bs;
  v_nb := COALESCE(cardinality(v_bt), 0);
  IF v_nb < 24 THEN RETURN NULL; END IF;

  -- the battery, and its charge at the day's start and end (the orchestrator's own reading of it, tick by tick)
  SELECT capacity_kwh AS cap, COALESCE(soc_min_floor_pct, 10) AS fl, COALESCE(soc_max_ceiling_pct, 90) AS ce,
         COALESCE(max_charge_kw, 500) AS pc, COALESCE(max_discharge_kw, 500) AS pd, roundtrip_efficiency_pct AS rt
    INTO b FROM ottoq_bess_units WHERE depot_id = p_depot_id ORDER BY bess_id LIMIT 1;
  IF b.cap IS NULL THEN RETURN NULL; END IF;
  v_rt := LEAST(1.0, GREATEST(0.5, CASE WHEN b.rt IS NULL THEN 0.96 WHEN b.rt <= 1 THEN b.rt ELSE b.rt / 100.0 END));  -- G172
  v_eff := sqrt(v_rt);
  v_lo := b.cap * b.fl / 100.0; v_hi := b.cap * b.ce / 100.0;
  SELECT b.cap * (c.reason->>'soc_pct')::numeric / 100.0 INTO v_e0 FROM ottoq_energy_commands c
   WHERE c.sim_run_id = p_sim_run_id AND c.depot_id = p_depot_id AND c.command_type = 'bess_setpoint_kw'
     AND c.issued_at > p_from ORDER BY c.issued_at LIMIT 1;
  SELECT b.cap * (c.reason->>'soc_pct')::numeric / 100.0 INTO v_e1 FROM ottoq_energy_commands c
   WHERE c.sim_run_id = p_sim_run_id AND c.depot_id = p_depot_id AND c.command_type = 'bess_setpoint_kw'
     AND c.issued_at > v_t[v_n] ORDER BY c.issued_at LIMIT 1;
  IF v_e1 IS NULL THEN       -- the run stopped inside the day: its last reading, and the last tick's own dispatch
    SELECT b.cap * (c.reason->>'soc_pct')::numeric / 100.0
           - (CASE WHEN c.setpoint_kw > 0 THEN c.setpoint_kw / v_eff ELSE c.setpoint_kw * v_eff END) * v_dt[v_n]
      INTO v_e1 FROM ottoq_energy_commands c
     WHERE c.sim_run_id = p_sim_run_id AND c.depot_id = p_depot_id AND c.command_type = 'bess_setpoint_kw'
       AND c.issued_at <= v_t[v_n] ORDER BY c.issued_at DESC LIMIT 1;
  END IF;
  IF v_e0 IS NULL OR v_e1 IS NULL THEN RETURN NULL; END IF;
  v_e1 := LEAST(v_hi, GREATEST(v_lo, v_e1));

  -- money, as the day plan reads it
  v_month := EXTRACT(MONTH FROM v_t[1] AT TIME ZONE c_tz)::int;
  SELECT t.season, t.demand_first_block_usd_kw INTO v_season, v_d_rate FROM ottoq_depot_tariffs t
   WHERE t.depot_id = p_depot_id AND t.active AND v_month = ANY(t.season_months)
   ORDER BY t.effective_from DESC, t.tariff_row_id LIMIT 1;
  v_amort := GREATEST(1, ottoq_policy_get(p_sim_run_id, 'bess_plan_demand_amortization_days', 30));
  v_d_day := COALESCE(v_d_rate, 0) / v_amort;
  SELECT min(w.rate_usd_per_kwh) INTO v_min_rate FROM ottoq_tariff_windows w
   WHERE w.depot_id = p_depot_id AND w.active
     AND (w.season = 'all' OR w.season = CASE WHEN v_month BETWEEN 6 AND 9 THEN 'summer' WHEN v_month IN (12, 1, 2) THEN 'winter'
                                              ELSE 'shoulder' END);
  v_c_rep := COALESCE(v_min_rate, 0.05) / v_rt;
  v_c_deg := GREATEST(0, ottoq_policy_get(p_sim_run_id, 'bess_plan_degradation_usd_kwh', 0.02));

  -- the realized day and the day with no battery: energy and wear by snapshot, the peaks on 6 steps of 5 minutes
  WITH x AS (SELECT v_grid[k] AS g, GREATEST(v_pre[k], 0) AS gn, v_rate[k] AS r, v_dt[k] AS dt, GREATEST(v_out[k], 0) AS dis
               FROM generate_series(1, v_n) k),
       w AS (SELECT j, avg(v_bg[j]) OVER (ORDER BY j ROWS BETWEEN CURRENT ROW AND c_win - 1 FOLLOWING) AS mg,
                    avg(v_bgn[j]) OVER (ORDER BY j ROWS BETWEEN CURRENT ROW AND c_win - 1 FOLLOWING) AS mn
               FROM generate_series(1, v_nb) j),
       pk AS (SELECT (SELECT j FROM w WHERE j <= v_nb - c_win + 1 ORDER BY mg DESC, j LIMIT 1) AS kg,
                     (SELECT j FROM w WHERE j <= v_nb - c_win + 1 ORDER BY mn DESC, j LIMIT 1) AS kn)
  SELECT jsonb_build_object(
           'energy_usd', round(sum(GREATEST(g, 0) * r * dt), 2),
           'peak30_kw', round((SELECT mg FROM w WHERE w.j = pk.kg), 1),
           'peak30_ends_ct', to_char(v_bt[LEAST(pk.kg + c_win - 1, v_nb)] AT TIME ZONE c_tz, 'YYYY-MM-DD HH24:MI'),
           'demand_usd', round(v_d_day * GREATEST((SELECT mg FROM w WHERE w.j = pk.kg), 0), 2),
           'discharge_kwh', round(sum(dis * dt), 1), 'wear_usd', round(v_c_deg * sum(dis * dt), 2),
           'total_usd', round(sum(GREATEST(g, 0) * r * dt) + v_d_day * GREATEST((SELECT mg FROM w WHERE w.j = pk.kg), 0)
                              + v_c_deg * sum(dis * dt), 2)),
         jsonb_build_object(
           'energy_usd', round(sum(gn * r * dt), 2),
           'peak30_kw', round((SELECT mn FROM w WHERE w.j = pk.kn), 1),
           'peak30_ends_ct', to_char(v_bt[LEAST(pk.kn + c_win - 1, v_nb)] AT TIME ZONE c_tz, 'YYYY-MM-DD HH24:MI'),
           'demand_usd', round(v_d_day * (SELECT mn FROM w WHERE w.j = pk.kn), 2),
           'total_usd', round(sum(gn * r * dt) + v_d_day * (SELECT mn FROM w WHERE w.j = pk.kn), 2),
           -- at the realized day's end charge: the energy the battery stored over the day, at its replacement cost
           'total_usd_at_realized_end', round(sum(gn * r * dt) + v_d_day * (SELECT mn FROM w WHERE w.j = pk.kn)
                                              + v_c_rep * (v_e1 - v_e0), 2))
    INTO v_real, v_none
    FROM x, pk GROUP BY pk.kg, pk.kn;

  -- how the battery was run: its modes, and the share of ticks it followed an outside plan
  SELECT jsonb_object_agg(m, n), COALESCE(sum(n) FILTER (WHERE m = 'mpc_follow'), 0)::numeric / NULLIF(sum(n), 0)
    INTO v_modes, v_follow
    FROM (SELECT COALESCE(c.reason->>'mode', '?') AS m, count(*) AS n FROM ottoq_energy_commands c
           WHERE c.sim_run_id = p_sim_run_id AND c.depot_id = p_depot_id AND c.command_type = 'bess_setpoint_kw'
             AND c.issued_at > p_from AND c.issued_at <= p_to GROUP BY 1) z;

  -- perfect foresight's floor: the call reserve as the depot's dials hold it (0804's planner floor), at each step's start
  v_dr_kwh := GREATEST(0, COALESCE(ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_reserve_kwh', 600), 600));
  v_dr_s := ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_window_start_hour', 14);
  v_dr_e := ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_window_end_hour', 20);
  v_lead := COALESCE(ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_reserve_lead_h', 24), 24);
  FOR i IN 1..v_nb LOOP
    v_hf := EXTRACT(HOUR FROM v_bt[i] AT TIME ZONE c_tz) + EXTRACT(MINUTE FROM v_bt[i] AT TIME ZONE c_tz) / 60.0;
    v_r := CASE WHEN COALESCE(v_season, '') <> 'summer' OR v_dr_kwh <= 0 OR v_dr_e <= v_dr_s THEN 0
                WHEN v_hf < v_dr_s - v_lead THEN 0
                WHEN v_hf < v_dr_s THEN v_dr_kwh
                WHEN v_hf < v_dr_e THEN v_dr_kwh * (v_dr_e - v_hf) / (v_dr_e - v_dr_s)
                ELSE 0 END;
    v_floor := v_floor || round(CASE WHEN v_r > 0 THEN LEAST(v_hi, v_lo + v_r / v_eff) ELSE v_lo END, 1);
  END LOOP;

  RETURN jsonb_build_object(
    'steps', v_nb, 'step_min', c_step, 'from', v_t[1], 'to', v_t[v_n],
    'realized', v_real, 'no_battery', v_none,
    'battery', jsonb_build_object('soc_start_kwh', round(v_e0, 1), 'soc_end_kwh', round(v_e1, 1),
                                  'replacement_usd_kwh', round(v_c_rep, 5), 'modes', v_modes,
                                  'followed_a_plan', round(v_follow, 3)),
    'request', jsonb_build_object(
      'load_kw', (SELECT jsonb_agg(round(x, 1) ORDER BY o) FROM unnest(v_bpre) WITH ORDINALITY u(x, o)),
      'price_usd_kwh', to_jsonb(v_brate), 'step_min', c_step,
      'battery', jsonb_build_object('soc_kwh', round(v_e0, 1), 'floor_kwh', round(v_lo, 1), 'ceiling_kwh', round(v_hi, 1),
                                    'max_charge_kw', b.pc, 'max_discharge_kw', b.pd, 'eff_one_way', v_eff),
      'demand_usd_kw', v_d_day,
      'periods', jsonb_build_array(jsonb_build_object('start', 0, 'end', v_nb, 'sunk_kw', 0, 'margin_kw', 0)),
      'past_grid_kw', '[]'::jsonb, 'window_steps', c_win, 'soc_floor_kwh', to_jsonb(v_floor),
      'wear_usd_kwh', v_c_deg, 'terminal_usd_kwh', round(v_c_rep, 5)));
END;
$function$;

-- ── V1: the new body is byte for byte the one the research lab ran ──
DO $v1$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'public.ottoq_bess_hindsight_segment(uuid,uuid,timestamp with time zone,timestamp with time zone)'::regprocedure)
     IS DISTINCT FROM 'fe69891a48c74b4e534aee094b593bd4' THEN
    RAISE EXCEPTION '0807 V1: the segment is not the body the lab ran (md5 %)',
      (SELECT md5(prosrc) FROM pg_proc
        WHERE oid = 'public.ottoq_bess_hindsight_segment(uuid,uuid,timestamp with time zone,timestamp with time zone)'::regprocedure);
  END IF;
END $v1$;

-- ── V2: a 15-second tick and a 5-minute tick of the same load grade alike; under 2 hours is not graded (rolled back) ──
DO $v2$
DECLARE
  c_twin CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  c_tz CONSTANT text := 'America/Chicago';
  v_run uuid; a jsonb; c jsonb; v_short jsonb; d0 timestamptz; d1 timestamptz; k int; t timestamptz; v_pre numeric;
  v_out numeric; v_sum numeric; v_sumo numeric; j int;
BEGIN
  SELECT r.sim_run_id INTO v_run FROM ottoq_sim_runs r WHERE r.depot_id = c_twin AND r.sim_clock_start IS NOT NULL
   ORDER BY r.started_at DESC NULLS LAST LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0807 V2: skipped, the twin depot has no run to hold the synthetic days';
    RETURN;
  END IF;
  d0 := (timestamp '2026-01-05 08:00') AT TIME ZONE c_tz;   -- two January days the run never reached, 8 to 11 AM CST
  d1 := (timestamp '2026-01-06 08:00') AT TIME ZONE c_tz;
  IF EXISTS (SELECT 1 FROM site_energy_snapshots e WHERE e.sim_run_id = v_run AND e.depot_id = c_twin
               AND e.timestamp > d0 - interval '1 day' AND e.timestamp < d1 + interval '1 day') THEN
    RAISE NOTICE '0807 V2: skipped, the run holds snapshots on the synthetic days';
    RETURN;
  END IF;
  BEGIN
    -- day A: a 15-second tick; the load a smooth wave, the battery discharging in one hour of three, sign constant in
    -- each 5-minute step so the step means carry it exactly
    FOR k IN 0..719 LOOP
      t := d0 + make_interval(secs => 15 * k);
      v_pre := round((500 + 300 * sin(2 * pi() * (15 * k) / 10800.0))::numeric, 2);
      v_out := CASE WHEN (k / 20) % 3 = 1 THEN 200 ELSE -100 END;
      INSERT INTO site_energy_snapshots (depot_id, timestamp, grid_import_kw, grid_export_kw, total_ev_charging_kw,
                                         building_load_kw, lighting_load_kw, solar_generation_kw, bess_output_kw,
                                         peak_demand_kw_15min, sim_run_id, data_source)
      VALUES (c_twin, t, v_pre - v_out, 0, v_pre - 100, 100, 0, 0, v_out, 0, v_run, 'twin');
    END LOOP;
    -- day B: the same load at a 5-minute tick, each snapshot the mean of day A's 20 snapshots in its step
    FOR j IN 0..35 LOOP
      v_sum := 0; v_sumo := 0;
      FOR k IN 20 * j..20 * j + 19 LOOP
        v_sum := v_sum + round((500 + 300 * sin(2 * pi() * (15 * k) / 10800.0))::numeric, 2);
        v_sumo := v_sumo + CASE WHEN (k / 20) % 3 = 1 THEN 200 ELSE -100 END;
      END LOOP;
      INSERT INTO site_energy_snapshots (depot_id, timestamp, grid_import_kw, grid_export_kw, total_ev_charging_kw,
                                         building_load_kw, lighting_load_kw, solar_generation_kw, bess_output_kw,
                                         peak_demand_kw_15min, sim_run_id, data_source)
      VALUES (c_twin, d1 + make_interval(mins => 5 * j), v_sum / 20 - v_sumo / 20, 0, v_sum / 20 - 100, 100, 0, 0,
              v_sumo / 20, 0, v_run, 'twin');
    END LOOP;
    -- the battery's charge as the orchestrator reads it, at each day's start and after its end
    INSERT INTO ottoq_energy_commands (sim_run_id, depot_id, issued_at, command_type, setpoint_kw, reason, status, data_source)
    VALUES (v_run, c_twin, d0, 'bess_setpoint_kw', 0, jsonb_build_object('soc_pct', 60, 'mode', 'plan_hold'), 'executed', 'twin'),
           (v_run, c_twin, d0 + interval '3 hours 1 minute', 'bess_setpoint_kw', 0, jsonb_build_object('soc_pct', 55, 'mode', 'plan_hold'), 'executed', 'twin'),
           (v_run, c_twin, d1, 'bess_setpoint_kw', 0, jsonb_build_object('soc_pct', 60, 'mode', 'plan_hold'), 'executed', 'twin'),
           (v_run, c_twin, d1 + interval '3 hours 1 minute', 'bess_setpoint_kw', 0, jsonb_build_object('soc_pct', 55, 'mode', 'plan_hold'), 'executed', 'twin');
    a := public.ottoq_bess_hindsight_segment(v_run, c_twin, d0 - interval '8 hours', d0 + interval '16 hours');
    c := public.ottoq_bess_hindsight_segment(v_run, c_twin, d1 - interval '8 hours', d1 + interval '16 hours');
    v_short := public.ottoq_bess_hindsight_segment(v_run, c_twin, d0 - interval '1 microsecond', d0 + interval '1 hour 50 minutes');
    IF a IS NULL OR c IS NULL OR (a->>'steps')::int <> 36 OR (c->>'steps')::int <> 36
       OR (a->>'step_min')::numeric <> 5 OR (a->'request'->>'window_steps')::int <> 6 THEN
      RAISE EXCEPTION '0807 V2: the days are not read in 36 steps of 5 minutes: % / %', left(a::text, 300), left(c::text, 300);
    END IF;
    IF abs((a->'realized'->>'total_usd')::numeric - (c->'realized'->>'total_usd')::numeric) > 0.01
       OR abs((a->'no_battery'->>'total_usd')::numeric - (c->'no_battery'->>'total_usd')::numeric) > 0.01
       OR abs((a->'realized'->>'peak30_kw')::numeric - (c->'realized'->>'peak30_kw')::numeric) > 0.1
       OR abs((a->'no_battery'->>'peak30_kw')::numeric - (c->'no_battery'->>'peak30_kw')::numeric) > 0.1
       OR abs((a->'realized'->>'discharge_kwh')::numeric - (c->'realized'->>'discharge_kwh')::numeric) > 0.1
       OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(a->'request'->'load_kw') WITH ORDINALITY x(v, o)
                    JOIN jsonb_array_elements_text(c->'request'->'load_kw') WITH ORDINALITY y(v, o) USING (o)
                   WHERE abs(x.v::numeric - y.v::numeric) > 0.1)
       OR a->'request'->'price_usd_kwh' IS DISTINCT FROM c->'request'->'price_usd_kwh' THEN
      RAISE EXCEPTION '0807 V2: a 15-second tick and a 5-minute tick of the same load grade differently: % / %',
        a->'realized', c->'realized';
    END IF;
    IF v_short IS NOT NULL THEN
      RAISE EXCEPTION '0807 V2: a part-day of 1 hour 50 minutes was graded';
    END IF;
    RAISE NOTICE '0807 V2: 15-second tick realized % (peak % kW), 5-minute tick realized % (peak % kW), no battery % / %',
      a->'realized'->'total_usd', a->'realized'->'peak30_kw', c->'realized'->'total_usd', c->'realized'->'peak30_kw',
      a->'no_battery'->'total_usd', c->'no_battery'->'total_usd';
    RAISE EXCEPTION USING ERRCODE = 'P0807', MESSAGE = 'roll back the synthetic days';
  EXCEPTION WHEN SQLSTATE 'P0807' THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM site_energy_snapshots e WHERE e.sim_run_id = v_run AND e.depot_id = c_twin
               AND e.timestamp >= d0 AND e.timestamp < d1 + interval '4 hours') THEN
    RAISE EXCEPTION '0807 V2: the synthetic days were not rolled back';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0807_the_battery_grade_reads_its_day_in_five_minute_steps_whatever_the_tick', false, false,
        'G527. ottoq_bess_hindsight_segment reads the day in 5-minute steps of sim time whatever the tick (each the '
        'time-weighted mean of what held over it), the demand window 6 steps, and grades a day only with 24 steps; at a '
        '5-minute tick nothing changes. Nothing in the engine reads the grade (bess_hindsight_enabled 0).',
        now());

COMMIT;

-- APPLIED 2026-11-06 at 18:41:39 UTC (12:41 PM CT), ledger 20261106184139, through apply_migration, on Chase's word
--   ("Yes, just keep building", read 2026-11-06 by 13:20 UTC, the go-ahead for the battery planner), confirmed by Chase
--   at the connector's prompt. Nothing live and the segment at the md5 P1 names, 0acfd7ce (read 18:37:23 UTC). The text
--   sent was this file before its version line and this footer were set: 25,728 characters, md5 261a7d71, equal to the
--   ledger's statements[1] read back. P0, P1, V1 and V2 (its synthetic days held by edf611ad, the twin's latest run)
--   passed inside the apply. Read back at 18:41:48 UTC: md5(prosrc) of the segment fe69891a, the body the lab ran; one
--   '0807_pre' snapshot; no synthetic snapshot or command left; edf611ad's 2026-11-04 (14.6 sim-minutes) is now not
--   graded (the segment returns NULL); the lineage row FALSE/FALSE at 18:41:39. bess_hindsight_enabled stays off at the
--   twin depot until the edge function is deployed. The lab template ottoq_lab took the same text and ledger row at
--   18:42 UTC.
