-- migration-version: PENDING
-- migration-name:    the_day_plan_could_not_see_the_fleet_waiting_to_charge_so_the_boot_surge_set_the_billed_peak
--
-- 0444  **The battery's day plan could not see the fleet waiting to charge, so the boot surge set the day's billed
--       peak while the battery sat at 95%.** `public.ottoq_bess_day_plan` (0435) forecasts EV load as
--       GREATEST(known, persistence). `known` (`ottoq_forecast_ev_known_kw`) counts two things: sessions already
--       running, held at their rate until they finish, and returning dispatches, charged from their ETA.
--       `persistence` is the depot's mean EV draw over the last hour. Neither counts a vehicle that is already on
--       site, below its target SoC and waiting for a charger. At boot there are no sessions, no history and dozens
--       of such vehicles, so the plan forecasts no EV load at all. FINDINGS G177.
--
-- ══ §1 MEASURED 2026-09-23, RUN 324eb0f1 (busy_day, plan mode from tick 1) ═════════════════════════════════════
--
--   - Tick 3, sim 04:23:19 CT: the plan's level was 54.1 kW (the ratchet, i.e. building load), `ev_persist_kw` 0.0,
--     charge cap 50 kW. In that same tick 26 sessions started. By tick 5 EV load was 1,523 kW.
--   - The day's billed peak, 1,624 kW, was set in the 04:00 CT hour. The largest grid draw from 05:00 to 08:00 CT
--     was 1,250 kW. The battery's hourly mean output was 0–3 kW from 04:00 to 08:00 CT, and its SoC went from
--     95.68% at boot to 94.25% by 07:42 CT. The battery is 3,000 kWh / 1,500 kW (`ottoq_bess_units`).
--   - So 374 kW of the billed peak exists only in the boot hour. At NES GSA-3's $21.40/kW-month
--     (`ottoq_depot_tariffs`, September) that is $8,004 a month, $267 a day amortised over 30 days. The battery
--     had the energy to cover it, and the plan never asked, because it forecast no EV load.
--   - At sim 07:42 CT, 57 of the 62 `staged_awaiting_service` vehicles were below target, needing 2,325 kWh.
--     The 36 running sessions needed 1,170 kWh. The known forecast covers the 1,170 and not the 2,325.
--   - The charge cap the plan emits did not starve the fleet. The decide path gates admissions on
--     `ottoq_ev_charge_allowance_kw` (the service limit, less any DR call; 0136/0433), not on the orchestrator's
--     advisory cap. So G177 cost money, not readiness. The run had 0 readiness violations at this measurement.
--
-- ══ §2 WHAT THIS DOES ════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `public.ottoq_ev_queue_schedule(...)`: a pure, IMMUTABLE list scheduler. It takes charger power and
--       free-at times, and jobs (kWh, release minute, vehicle inlet kW) in queue order. Each job takes the charger
--       that can start it earliest (ties: the more powerful charger, then the lower index). A job draws
--       LEAST(charger, inlet, 250) kW x 0.60 on a charger faster than 50 kW, and LEAST(charger, inlet) on one at
--       or under 50 kW. Load is returned as the AVERAGE kW of each step, i.e. energy-conserving. A 30-minute step
--       is also what NES GSA-3 bills, so the average is the quantity that matters. Jobs that cannot start inside
--       the horizon are counted as `unplaced`.
--       ASSUMPTION: the 0.60 DCFC taper factor is `ottoq_forecast_ev_known_kw` loop (2)'s own "avg DCFC session
--       power". It is reused so the two forecasts disagree only on WHO charges, not on how fast.
--   (2) `public.ottoq_forecast_ev_queue_kw(run, depot, clock, steps, step_min)`: the wrapper.
--       - Chargers: every non-decommissioned charger at the depot. A faulted charger is excluded unless a session
--         is still running on it (0372's gate).
--       - A charger holding an active session of this run is busy until that session's forecast end, at loop (1)'s
--         exact arithmetic. Its load goes into the result the same way loop (1) computes it.
--       - Jobs, in queue order (release, then SoC, then vehicle id), are two groups:
--         on-site vehicles in `arrived_at_gate` / `staged_awaiting_service` below target with no active session
--         (the proposer's serviceable set less the charging states, which are the sessions above), released now;
--         and returning dispatches, loop (2)'s own predicate, released at their ETA. A returning vehicle that is
--         already in one of those four states is not counted again.
--       - It returns the load array plus pending count, pending kWh, returning count, charger count and unplaced.
--   (3) The day plan's EV term becomes GREATEST(known, queue, persistence). The two old terms stay as floors, so the
--       forecast can only rise. The plan also reports `ev_queue` (the counts and the queue's peak) beside
--       `ev_persist_kw`, and `ev_queue_kw` / `ev_known_kw` beside `ev_kw` in its forecast. That makes it auditable
--       which term drove a level.
--
-- ══ §3 WHAT THIS DOES NOT FIX, AND WHY IT MATTERS TONIGHT (G178) ═══════════════════════════════════════════════
--
--   The battery reacts ONE TICK LATE to new charging load. `twin.ottoq_world_advance` (and
--   `ottoq_sim_advance_tick_world`) run `ottoq_energy_orchestrate` and the energy controller BEFORE
--   `ottoq_sim_reconcile_charge_sessions` starts this tick's new sessions. Those sessions then draw power in this
--   tick's energy advance, against a setpoint computed before they existed. Tick 5 above shows it: the orchestrator
--   saw a net load of 377 kW, and the snapshot at the same instant shows 1,574 kW of grid draw.
--   - At the demo cadence (~0.5 sim-min per tick) the lag is 30 seconds of a 30-minute billing window, so this
--     migration's forecast is enough for the battery to shave a surge.
--   - At the certification cadence (30 sim-min per tick), which is also the cadence the dial-experiment pairs
--     (0439) run at, the lag is a whole billing interval. No plan can shave the first interval of a surge there.
--   So a treatment-vs-incumbent verdict on an energy dial measured at 30-minute ticks understates any strategy
--   whose value is at the leading edge of a surge. Fixing G178 moves where the battery is dispatched, so it
--   changes certification energy atoms. It belongs in a recert window, not in this file.
--
-- ══ §4 forces_recert FALSE ═══════════════════════════════════════════════════════════════════════════════════
--
--   The day plan is reached only from `ottoq_energy_orchestrate` with `energy_reserve_shave` >= 0.5, and no
--   certification run has that on (P2; 0435 P3; 0442 P2). The two new functions have no other caller.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0444 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%' OR query ILIKE '%ottoq_dial_experiment_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0444 P0: a determinism or dial pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0444 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: the day plan as read on 2026-09-23, every anchor unique, and nothing this creates exists yet ──
DO $$
DECLARE v_src text; v_n int; v_a text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc
   WHERE oid = 'public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure;
  IF md5(v_src) <> '7f2a404edbee50b9bcb091516576231b' THEN
    RAISE EXCEPTION '0444 P1: ottoq_bess_day_plan md5 is %', md5(v_src);
  END IF;
  FOREACH v_a IN ARRAY ARRAY[
      E'  v_prof numeric[]; v_prof_now numeric; v_anom numeric;\n',
      E'  v_known := public.ottoq_forecast_ev_known_kw(p_sim_run_id, p_depot_id, p_sim_clock, v_n, 30, 30);\n',
      E'    v_ev[k] := GREATEST(COALESCE(v_known[k], 0), v_ev_persist);\n',
      E'''ev_persist_kw'', round(v_ev_persist, 1),\n',
      E'       ''ev_kw'',    (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_ev)    WITH ORDINALITY AS u(x, o)),\n']
  LOOP
    v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
    IF v_n <> 1 THEN RAISE EXCEPTION '0444 P1: anchor matched % times: %', v_n, left(v_a, 60); END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_ev_queue_schedule(numeric[],numeric[],numeric[],numeric[],numeric[],numeric,integer)') IS NOT NULL
     OR to_regprocedure('public.ottoq_forecast_ev_queue_kw(uuid,uuid,timestamp with time zone,integer,numeric)') IS NOT NULL THEN
    RAISE EXCEPTION '0444 P1: the queue forecast already exists';
  END IF;
END $$;

-- ── P2: the premises forces_recert FALSE rests on ──
DO $$
DECLARE v_callers text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params
              WHERE param_key = 'energy_reserve_shave' AND scope_type IN ('depot','global') AND param_value >= 0.5) THEN
    RAISE EXCEPTION '0444 P2: energy_reserve_shave is on at depot/global scope, so certification runs reach plan mode';
  END IF;
  SELECT string_agg(DISTINCT n.nspname || '.' || p.proname, ', ') INTO v_callers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq') AND p.proname <> 'ottoq_bess_day_plan'
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') ~ 'ottoq_bess_day_plan';
  IF v_callers IS DISTINCT FROM 'public.ottoq_energy_orchestrate' THEN
    RAISE EXCEPTION '0444 P2: ottoq_bess_day_plan has callers other than the orchestrator: %', v_callers;
  END IF;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0444_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure;

-- ── (1) THE PURE CORE ──
CREATE FUNCTION public.ottoq_ev_queue_schedule(
  p_charger_kw numeric[], p_charger_free_min numeric[],
  p_job_kwh numeric[], p_job_release_min numeric[], p_job_inlet_kw numeric[],
  p_step_min numeric, p_steps integer,
  OUT load_kw numeric[], OUT placed integer, OUT unplaced integer, OUT placed_kwh numeric)
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0444: list scheduling of charge jobs onto chargers, for a load FORECAST. Jobs arrive in queue order; each takes
   the charger that can start it earliest (ties: more kW, then lower index). Load is each step's AVERAGE kW, so
   sum(load) x step/60 is the energy delivered inside the horizon. Pure: no table is read. */
DECLARE
  v_free numeric[]; v_nc int; v_nj int; j int; c int; h int;
  v_best int; v_bt numeric; v_t numeric; v_ac numeric; v_rate numeric;
  v_s numeric; v_e numeric; v_end numeric; v_lo numeric; v_hi numeric;
BEGIN
  IF p_step_min IS NULL OR p_step_min <= 0 OR p_steps IS NULL OR p_steps < 1 THEN
    RAISE EXCEPTION 'ottoq_ev_queue_schedule: step_min % and steps % must be positive', p_step_min, p_steps;
  END IF;
  load_kw := array_fill(0::numeric, ARRAY[p_steps]);
  placed := 0; unplaced := 0; placed_kwh := 0;
  v_nc := COALESCE(array_length(p_charger_kw, 1), 0);
  v_nj := COALESCE(array_length(p_job_kwh, 1), 0);
  IF COALESCE(array_length(p_charger_free_min, 1), 0) <> v_nc
     OR COALESCE(array_length(p_job_release_min, 1), 0) <> v_nj
     OR COALESCE(array_length(p_job_inlet_kw, 1), 0) <> v_nj THEN
    RAISE EXCEPTION 'ottoq_ev_queue_schedule: charger or job arrays disagree in length';
  END IF;
  IF v_nj = 0 THEN RETURN; END IF;
  v_free := COALESCE(p_charger_free_min, '{}'::numeric[]);
  v_end := p_step_min * p_steps;

  FOR j IN 1 .. v_nj LOOP
    IF COALESCE(p_job_kwh[j], 0) <= 0 THEN CONTINUE; END IF;
    v_best := NULL; v_bt := NULL;
    FOR c IN 1 .. v_nc LOOP
      IF COALESCE(p_charger_kw[c], 0) <= 0 THEN CONTINUE; END IF;
      v_t := GREATEST(COALESCE(v_free[c], 0), COALESCE(p_job_release_min[j], 0));
      IF v_best IS NULL OR v_t < v_bt OR (v_t = v_bt AND p_charger_kw[c] > p_charger_kw[v_best]) THEN
        v_best := c; v_bt := v_t;
      END IF;
    END LOOP;
    IF v_best IS NULL OR v_bt >= v_end THEN unplaced := unplaced + 1; CONTINUE; END IF;

    v_ac   := LEAST(p_charger_kw[v_best], COALESCE(NULLIF(p_job_inlet_kw[j], 0), p_charger_kw[v_best]));
    v_rate := GREATEST(1, LEAST(v_ac, 250) * CASE WHEN v_ac <= 50 THEN 1.0 ELSE 0.60 END);
    v_s := v_bt;
    v_e := v_s + p_job_kwh[j] / v_rate * 60.0;
    v_free[v_best] := v_e;
    placed := placed + 1; placed_kwh := placed_kwh + p_job_kwh[j];
    FOR h IN (floor(v_s / p_step_min)::int + 1) .. LEAST(p_steps, ceil(v_e / p_step_min)::int) LOOP
      v_lo := GREATEST(v_s, (h - 1) * p_step_min);
      v_hi := LEAST(v_e, h * p_step_min);
      IF v_hi > v_lo THEN load_kw[h] := load_kw[h] + v_rate * (v_hi - v_lo) / p_step_min; END IF;
    END LOOP;
  END LOOP;
END $fn$;

-- ── (2) THE WRAPPER: the depot's chargers, its running sessions, its waiting fleet and its returns ──
CREATE FUNCTION public.ottoq_forecast_ev_queue_kw(
  p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamptz, p_horizon_steps integer, p_step_min numeric,
  OUT load_kw numeric[], OUT pending_n integer, OUT pending_kwh numeric, OUT returning_n integer,
  OUT chargers_n integer, OUT unplaced_n integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0444 (G177): the EV load the depot will draw, as a queue. Running sessions hold their charger until their
   forecast end (ottoq_forecast_ev_known_kw loop (1)'s arithmetic, verbatim); vehicles waiting on site and returning
   dispatches (loop (2)'s predicate) are scheduled onto the chargers as they free, by ottoq_ev_queue_schedule.
   Every input is this run's rows or the depot's static data, so the two arms of a pair see the same forecast. */
DECLARE
  r record; v_q record; h int;
  v_ckw numeric[] := '{}'; v_cfree numeric[] := '{}'; v_active numeric[];
  v_jkwh numeric[] := '{}'; v_jrel numeric[] := '{}'; v_jin numeric[] := '{}'; v_ql numeric[];
  v_rate numeric; v_dur numeric; v_hi numeric;
BEGIN
  v_active := array_fill(0::numeric, ARRAY[p_horizon_steps]);
  pending_n := 0; pending_kwh := 0; returning_n := 0;

  -- the chargers, and the running session on each (a faulted charger counts only while a session still runs on it)
  FOR r IN
    SELECT COALESCE(ch.max_kw, st.connector_max_kw, 0)::numeric AS kw, a.rate, a.kwh
      FROM stalls st
      JOIN ottoq_ocpp_chargers ch ON ch.charger_id = st.ocpp_charger_id
      LEFT JOIN LATERAL (
        SELECT ottoq_sim_compute_charge_rate(
                 p_soc_pct := v.current_soc, p_battery_temp_c := COALESCE(s.ambient_temp_c,22)+5,
                 p_ambient_temp_c := COALESCE(s.ambient_temp_c,22), p_charger_max_kw := ch.max_kw,
                 p_vehicle_max_kw := v.inlet_max_kw, p_battery_capacity_kwh := v.battery_capacity_kwh,
                 p_battery_soh_pct := 95, p_noise_seed := 1, p_noise_salt := s.vehicle_id::text) AS rate,
               GREATEST(0,(COALESCE(v.target_soc, public.ottoq_default_target_soc())-v.current_soc)/100.0
                          *COALESCE(v.battery_capacity_kwh,75)) AS kwh
          FROM ocpp_sessions s JOIN vehicles v ON v.id = s.vehicle_id
         WHERE s.stall_id = st.id AND s.status = 'active' AND s.sim_run_id = p_sim_run_id
         ORDER BY s.started_at DESC, s.vehicle_id
         LIMIT 1) a ON true
     WHERE st.depot_id = p_depot_id AND ch.decommissioned_at IS NULL
       AND (a.rate IS NOT NULL OR ch.station_state IS DISTINCT FROM 'Faulted')
     ORDER BY st.id
  LOOP
    v_ckw := v_ckw || r.kw;
    IF r.rate IS NULL THEN
      v_cfree := v_cfree || 0::numeric;
    ELSE
      v_rate := GREATEST(r.rate, 1);
      v_dur  := r.kwh / v_rate * 60.0;
      v_cfree := v_cfree || v_dur;
      FOR h IN 1 .. LEAST(p_horizon_steps, ceil(v_dur / p_step_min)::int) LOOP
        v_hi := LEAST(v_dur, h * p_step_min);
        IF v_hi > (h - 1) * p_step_min THEN
          v_active[h] := v_active[h] + v_rate * (v_hi - (h - 1) * p_step_min) / p_step_min;
        END IF;
      END LOOP;
    END IF;
  END LOOP;

  -- the queue: the fleet waiting on site now, then the returns at their ETAs
  FOR r IN
    SELECT q.kwh, q.rel, q.inlet, q.kind FROM (
      SELECT GREATEST(0,(COALESCE(v.target_soc, public.ottoq_default_target_soc())-v.current_soc)/100.0
                        *COALESCE(v.battery_capacity_kwh,75)) AS kwh,
             0::numeric AS rel, COALESCE(v.inlet_max_kw,150)::numeric AS inlet, 'on_site'::text AS kind,
             v.current_soc AS soc, v.id AS vid
        FROM vehicles v
       WHERE v.home_depot_id = p_depot_id
         AND v.current_state IN ('arrived_at_gate','staged_awaiting_service')
         AND v.current_soc IS NOT NULL
         AND v.current_soc < COALESCE(v.target_soc, public.ottoq_default_target_soc())
         AND NOT EXISTS (SELECT 1 FROM ocpp_sessions s
                          WHERE s.vehicle_id = v.id AND s.status = 'active' AND s.sim_run_id = p_sim_run_id)
      UNION ALL
      SELECT GREATEST(0,(COALESCE(v.target_soc, public.ottoq_default_target_soc())-COALESCE(v.current_soc, 30))/100.0
                        *COALESCE(v.battery_capacity_kwh,75)),
             GREATEST(0, EXTRACT(EPOCH FROM (d.scheduled_return_at - p_sim_clock)) / 60.0),
             COALESCE(v.inlet_max_kw,150)::numeric, 'returning', COALESCE(v.current_soc, 30), v.id
        FROM ottoq_vehicle_dispatches d JOIN vehicles v ON v.id = d.vehicle_id
       WHERE d.sim_run_id = p_sim_run_id AND d.status IN ('active','returning')
         AND d.scheduled_return_at IS NOT NULL
         AND d.scheduled_return_at <= p_sim_clock + (p_horizon_steps * p_step_min) * interval '1 min'
         AND d.scheduled_return_at >  p_sim_clock - interval '30 min'
         AND v.current_state NOT IN ('arrived_at_gate','staged_awaiting_service','charging_dcfc','charging_l2')
    ) q
    WHERE q.kwh > 0
    ORDER BY q.rel, q.soc, q.vid
  LOOP
    v_jkwh := v_jkwh || r.kwh; v_jrel := v_jrel || r.rel; v_jin := v_jin || r.inlet;
    IF r.kind = 'on_site' THEN
      pending_n := pending_n + 1; pending_kwh := pending_kwh + r.kwh;
    ELSE
      returning_n := returning_n + 1;
    END IF;
  END LOOP;

  SELECT * INTO v_q FROM public.ottoq_ev_queue_schedule(v_ckw, v_cfree, v_jkwh, v_jrel, v_jin, p_step_min, p_horizon_steps);
  v_ql := v_q.load_kw;
  load_kw := v_active;
  FOR h IN 1 .. p_horizon_steps LOOP
    load_kw[h] := load_kw[h] + COALESCE(v_ql[h], 0);
  END LOOP;
  chargers_n := COALESCE(array_length(v_ckw, 1), 0);
  unplaced_n := v_q.unplaced;
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_ev_queue_schedule(numeric[], numeric[], numeric[], numeric[], numeric[], numeric, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_ev_queue_schedule(numeric[], numeric[], numeric[], numeric[], numeric[], numeric, integer) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_forecast_ev_queue_kw(uuid, uuid, timestamptz, integer, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_forecast_ev_queue_kw(uuid, uuid, timestamptz, integer, numeric) TO authenticated, service_role;

-- ── (3) THE DAY PLAN READS THE QUEUE ──
DO $splice$
DECLARE v_def text; v_new text;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure);
  v_new := replace(v_def,
    E'  v_prof numeric[]; v_prof_now numeric; v_anom numeric;\n',
    E'  v_prof numeric[]; v_prof_now numeric; v_anom numeric;\n'
    || E'  v_q record; v_queue numeric[];   /* 0444 */\n');
  v_new := replace(v_new,
    E'  v_known := public.ottoq_forecast_ev_known_kw(p_sim_run_id, p_depot_id, p_sim_clock, v_n, 30, 30);\n',
    E'  v_known := public.ottoq_forecast_ev_known_kw(p_sim_run_id, p_depot_id, p_sim_clock, v_n, 30, 30);\n'
    || E'  -- 0444 (G177): and the fleet already on site waiting for a charger, queued onto the chargers as they free\n'
    || E'  SELECT * INTO v_q FROM public.ottoq_forecast_ev_queue_kw(p_sim_run_id, p_depot_id, p_sim_clock, v_n, 30);\n'
    || E'  v_queue := v_q.load_kw;\n');
  v_new := replace(v_new,
    E'    v_ev[k] := GREATEST(COALESCE(v_known[k], 0), v_ev_persist);\n',
    E'    v_ev[k] := GREATEST(COALESCE(v_known[k], 0), COALESCE(v_queue[k], 0), v_ev_persist);   /* 0444 */\n');
  v_new := replace(v_new,
    E'''ev_persist_kw'', round(v_ev_persist, 1),\n',
    E'''ev_persist_kw'', round(v_ev_persist, 1),\n'
    || E'    ''ev_queue'', jsonb_build_object(''pending_n'', v_q.pending_n, ''pending_kwh'', round(v_q.pending_kwh, 1),\n'
    || E'                 ''returning_n'', v_q.returning_n, ''chargers'', v_q.chargers_n, ''unplaced_n'', v_q.unplaced_n,\n'
    || E'                 ''peak_kw'', round((SELECT max(x) FROM unnest(v_queue) AS x), 1)),   /* 0444 */\n');
  v_new := replace(v_new,
    E'       ''ev_kw'',    (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_ev)    WITH ORDINALITY AS u(x, o)),\n',
    E'       ''ev_kw'',    (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_ev)    WITH ORDINALITY AS u(x, o)),\n'
    || E'       ''ev_queue_kw'', (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_queue) WITH ORDINALITY AS u(x, o)),   /* 0444 */\n'
    || E'       ''ev_known_kw'', (SELECT jsonb_agg(round(x, 0) ORDER BY o) FROM unnest(v_known) WITH ORDINALITY AS u(x, o)),\n');
  IF v_new = v_def
     OR position('ottoq_forecast_ev_queue_kw' IN v_new) = 0
     OR position('COALESCE(v_queue[k], 0), v_ev_persist' IN v_new) = 0
     OR position('''ev_queue'', jsonb_build_object' IN v_new) = 0
     OR position('''ev_queue_kw''' IN v_new) = 0 THEN
    RAISE EXCEPTION '0444: the day-plan splices did not all apply';
  END IF;
  EXECUTE v_new;
END $splice$;

-- ── V1: the core, by hand. Chargers 350 kW and 19.2 kW; jobs A 60 kWh / 150 kW inlet, B 30 kWh / 150, C 15 kWh / 11.
--       A: 350 (tie on start, more kW) at 150 x 0.60 = 90 kW, 0-40 min.  B: 19.2 kW free at 0, 0-93.75 min.
--       C: 350 frees at 40, inlet 11 so 11 kW, 40-121.82 min.  Step means (30 min, 4 steps):
--       [90 + 19.2, 30 + 19.2 + 7.333, 19.2 + 11, 2.4 + 11] = [109.2, 56.533, 30.2, 13.4]. ──
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM public.ottoq_ev_queue_schedule(ARRAY[350, 19.2]::numeric[], ARRAY[0, 0]::numeric[],
         ARRAY[60, 30, 15]::numeric[], ARRAY[0, 0, 0]::numeric[], ARRAY[150, 150, 11]::numeric[], 30, 4);
  IF (SELECT array_agg(round(x, 3) ORDER BY o) FROM unnest(r.load_kw) WITH ORDINALITY AS u(x, o))
       <> ARRAY[109.2, 56.533, 30.2, 13.4]::numeric[]
     OR r.placed <> 3 OR r.unplaced <> 0 OR r.placed_kwh <> 105 THEN
    RAISE EXCEPTION '0444 V1: the core scheduled % (placed %, unplaced %, kWh %)', r.load_kw, r.placed, r.unplaced, r.placed_kwh;
  END IF;
  -- energy conserved inside the horizon: 105 kWh placed, and C's last 1.818 min x 11 kW (1/3 kWh) falls outside it
  IF abs((SELECT sum(x) FROM unnest(r.load_kw) AS x) * 30 / 60.0 - (105 - 11 * (15 / 11.0 * 60 + 40 - 120) / 60.0)) > 1e-6 THEN
    RAISE EXCEPTION '0444 V1: energy is not conserved inside the horizon';
  END IF;
END $$;

-- ── V2: queueing and release. One 350 kW charger busy until minute 20; D 45 kWh released now, E 45 kWh released at 50,
--       both 250 kW inlets, so 150 kW each for 18 min: D 20-38, E 50-68 -> [50, 40 + 50, 40, 0]. ──
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM public.ottoq_ev_queue_schedule(ARRAY[350]::numeric[], ARRAY[20]::numeric[],
         ARRAY[45, 45]::numeric[], ARRAY[0, 50]::numeric[], ARRAY[250, 250]::numeric[], 30, 4);
  IF (SELECT array_agg(round(x, 3) ORDER BY o) FROM unnest(r.load_kw) WITH ORDINALITY AS u(x, o))
       <> ARRAY[50, 90, 40, 0]::numeric[] OR r.placed <> 2 OR r.unplaced <> 0 THEN
    RAISE EXCEPTION '0444 V2: the core queued % (placed %, unplaced %)', r.load_kw, r.placed, r.unplaced;
  END IF;
END $$;

-- ── V3: a job that cannot start inside the horizon is unplaced, not dropped silently. One 19.2 kW charger; F 100 kWh
--       at an 11 kW inlet runs 545 min, so G cannot start before minute 120. ──
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM public.ottoq_ev_queue_schedule(ARRAY[19.2]::numeric[], ARRAY[0]::numeric[],
         ARRAY[100, 10]::numeric[], ARRAY[0, 0]::numeric[], ARRAY[11, 11]::numeric[], 30, 4);
  IF r.load_kw <> ARRAY[11, 11, 11, 11]::numeric[] OR r.placed <> 1 OR r.unplaced <> 1 THEN
    RAISE EXCEPTION '0444 V3: % placed % unplaced %', r.load_kw, r.placed, r.unplaced;
  END IF;
  -- and no chargers at all: every job unplaced, zero load
  SELECT * INTO r FROM public.ottoq_ev_queue_schedule('{}'::numeric[], '{}'::numeric[],
         ARRAY[10]::numeric[], ARRAY[0]::numeric[], ARRAY[11]::numeric[], 30, 2);
  IF r.load_kw <> ARRAY[0, 0]::numeric[] OR r.placed <> 0 OR r.unplaced <> 1 THEN
    RAISE EXCEPTION '0444 V3: with no chargers the core returned % placed % unplaced %', r.load_kw, r.placed, r.unplaced;
  END IF;
END $$;

-- ── V4: the wrapper and the plan on the twin depot's latest run (read-only) ──
DO $$
DECLARE v_run uuid; v_clock timestamptz; r record; v_plan jsonb; v_cap_sum numeric; k int;
  v_ev numeric[]; v_q numeric[]; v_kn numeric[];
BEGIN
  SELECT sim_run_id, sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND sim_clock_current IS NOT NULL
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE NOTICE '0444 V4: no twin run to read; skipped'; RETURN; END IF;

  SELECT * INTO r FROM public.ottoq_forecast_ev_queue_kw(v_run, '11111111-1111-1111-1111-111111111111', v_clock, 16, 30);
  SELECT COALESCE(sum(COALESCE(ch.max_kw, st.connector_max_kw, 0)), 0) INTO v_cap_sum
    FROM stalls st JOIN ottoq_ocpp_chargers ch ON ch.charger_id = st.ocpp_charger_id
   WHERE st.depot_id = '11111111-1111-1111-1111-111111111111' AND ch.decommissioned_at IS NULL;
  IF array_length(r.load_kw, 1) <> 16 OR r.chargers_n < 1
     OR EXISTS (SELECT 1 FROM unnest(r.load_kw) AS x WHERE x < 0 OR x > v_cap_sum + 1e-6)
     OR r.pending_n < 0 OR r.pending_kwh < 0 OR r.unplaced_n < 0 THEN
    RAISE EXCEPTION '0444 V4: the wrapper returned % (chargers %, pending %/% kWh, unplaced %) against % kW of chargers',
      r.load_kw, r.chargers_n, r.pending_n, r.pending_kwh, r.unplaced_n, v_cap_sum;
  END IF;

  v_plan := public.ottoq_bess_day_plan(v_run, '11111111-1111-1111-1111-111111111111', v_clock, NULL);
  IF NOT COALESCE((v_plan->>'ok')::boolean, false) THEN
    RAISE EXCEPTION '0444 V4: the day plan no longer solves: %', v_plan;
  END IF;
  IF v_plan->'ev_queue' IS NULL OR v_plan->'forecast'->'ev_queue_kw' IS NULL OR v_plan->'forecast'->'ev_known_kw' IS NULL THEN
    RAISE EXCEPTION '0444 V4: the plan does not report its queue term';
  END IF;
  SELECT array_agg(x::numeric ORDER BY o) INTO v_ev FROM jsonb_array_elements_text(v_plan->'forecast'->'ev_kw') WITH ORDINALITY AS t(x, o);
  SELECT array_agg(x::numeric ORDER BY o) INTO v_q  FROM jsonb_array_elements_text(v_plan->'forecast'->'ev_queue_kw') WITH ORDINALITY AS t(x, o);
  SELECT array_agg(x::numeric ORDER BY o) INTO v_kn FROM jsonb_array_elements_text(v_plan->'forecast'->'ev_known_kw') WITH ORDINALITY AS t(x, o);
  FOR k IN 1 .. array_length(v_ev, 1) LOOP
    IF v_ev[k] < v_q[k] OR v_ev[k] < v_kn[k] THEN
      RAISE EXCEPTION '0444 V4: step % forecasts % kW of EV under its queue % or known % term', k, v_ev[k], v_q[k], v_kn[k];
    END IF;
  END LOOP;
END $$;

-- ── V5: what shipped is what the header says ──
DO $$
DECLARE v_src text;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src FROM pg_proc
   WHERE oid = 'public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure;
  IF position('ottoq_forecast_ev_queue_kw(p_sim_run_id, p_depot_id, p_sim_clock, v_n, 30)' IN v_src) = 0
     OR position('GREATEST(COALESCE(v_known[k], 0), COALESCE(v_queue[k], 0), v_ev_persist)' IN v_src) = 0 THEN
    RAISE EXCEPTION '0444 V5: the day plan does not read the queue the way the header says';
  END IF;
  IF (SELECT provolatile FROM pg_proc WHERE oid = 'public.ottoq_ev_queue_schedule(numeric[],numeric[],numeric[],numeric[],numeric[],numeric,integer)'::regprocedure) <> 'i'
     OR (SELECT provolatile FROM pg_proc WHERE oid = 'public.ottoq_forecast_ev_queue_kw(uuid,uuid,timestamp with time zone,integer,numeric)'::regprocedure) <> 's' THEN
    RAISE EXCEPTION '0444 V5: the core must be IMMUTABLE and the wrapper STABLE';
  END IF;
END $$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0444_the_day_plan_could_not_see_the_fleet_waiting_to_charge_so_the_boot_surge_set_the_billed_peak',
   false,
   'G177: ottoq_bess_day_plan''s EV forecast is GREATEST(known, queue, persistence). The queue term '
   '(ottoq_forecast_ev_queue_kw over the pure list scheduler ottoq_ev_queue_schedule) adds the vehicles waiting on '
   'site below target and the returning dispatches, scheduled onto the depot''s chargers as they free. FALSE: the '
   'plan is reached only with energy_reserve_shave on, which no certification run has (P2). G178, the one-tick '
   'battery lag, is recorded in the header and is not fixed here.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- forces_recert FALSE. After applying: every armed run's plan reports `ev_queue` and the forecast's `ev_queue_kw`;
-- the next busy_day demo run is the live proof (the boot hour's billed peak against 324eb0f1's 1,624 kW).
-- Rollback: restore ottoq_bess_day_plan from ottoq_schema_snapshots label '0444_pre'; the two functions can stay.
