-- Stub for 0577 (tests/test_throughput_sweep_sql.py), loaded on top of the sweep stubs. It adds what the peak after the
-- opening is read from: an energy sample per tick, the twin's demand tariff (NES, the same block and rates 0439 bills), and
-- a scorer whose energy block is the live one byte for byte (md5 f95eaf7bc07cbf9e440bfa636a313ff1, which 0577 P2 pins).
-- Its other keys are the sweep stub's, unchanged.
--
-- The day, from the run's start: the opening half hour is the fleet plugging in (1,900 kW; 1,100 with the planner
-- shaving it), then 800 kW, and 8:00-8:40 PM on a 6 AM day is the evening's returns (1,400 kW; 1,000 with the planner).

CREATE TABLE public.site_energy_snapshots (
  snapshot_id bigserial PRIMARY KEY, sim_run_id uuid, depot_id uuid, timestamp timestamptz NOT NULL,
  grid_import_kw numeric, bess_output_kw numeric, current_rate_per_kwh numeric);

CREATE TABLE public.ottoq_depot_tariffs (
  tariff_row_id bigserial PRIMARY KEY, depot_id uuid NOT NULL, active boolean NOT NULL DEFAULT true, season text,
  season_months integer[] NOT NULL, effective_from date NOT NULL, block_kw numeric, demand_first_block_usd_kw numeric,
  demand_excess_usd_kw numeric);
INSERT INTO public.ottoq_depot_tariffs (depot_id, season, season_months, effective_from, block_kw,
                                        demand_first_block_usd_kw, demand_excess_usd_kw)
VALUES ('11111111-1111-1111-1111-111111111111', 'summer', '{6,7,8,9}', '2024-10-01', 1000, 21.40, 21.78),
       ('11111111-1111-1111-1111-111111111111', 'winter', '{1,2,3,4,5,10,11,12}', '2024-10-01', 1000, 20.34, 20.73);

CREATE FUNCTION public.stub_energy_sample() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_on boolean := public.ottoq_policy_get(NEW.sim_run_id, 'energy_orchestration_enabled', 1) >= 1;
  v_hr numeric := EXTRACT(EPOCH FROM (NEW.sim_clock_current - NEW.sim_clock_start)) / 3600.0;
BEGIN
  IF NEW.tick_count IS NOT DISTINCT FROM OLD.tick_count THEN
    RETURN NEW;
  END IF;
  INSERT INTO public.site_energy_snapshots (sim_run_id, depot_id, timestamp, grid_import_kw, bess_output_kw, current_rate_per_kwh)
  VALUES (NEW.sim_run_id, NEW.depot_id, NEW.sim_clock_current,
          CASE WHEN v_hr <= 0.5 THEN CASE WHEN v_on THEN 1100 ELSE 1900 END
               WHEN v_hr > 14 AND v_hr <= 14 + 40 / 60.0 THEN CASE WHEN v_on THEN 1000 ELSE 1400 END
               ELSE 800 END,
          0, 0.07);
  RETURN NEW;
END $$;
CREATE TRIGGER trg_stub_energy_sample AFTER UPDATE OF tick_count ON public.ottoq_sim_runs
  FOR EACH ROW EXECUTE FUNCTION public.stub_energy_sample();

ALTER FUNCTION public.ottoq_dial_arm_metrics(uuid, uuid, numeric) RENAME TO stub_arm_metrics;

CREATE FUNCTION public.ottoq_dial_arm_metrics(p_run uuid, p_depot uuid, p_soc_start_kwh numeric) RETURNS jsonb
LANGUAGE plpgsql STABLE AS $function$
DECLARE
  c_tz CONSTANT text := 'America/Chicago';
  r ottoq_sim_runs%ROWTYPE; v_month int;
  v_grid_kwh numeric; v_cost numeric; v_peak30 numeric; v_dis numeric; v_chg numeric; v_min_rate numeric; v_samples int;
  v_block numeric; v_r1 numeric; v_r2 numeric; v_demand numeric; v_amort numeric;
BEGIN
  SELECT * INTO r FROM ottoq_sim_runs WHERE sim_run_id = p_run;
  WITH s AS (
    SELECT e.timestamp AS t, GREATEST(COALESCE(e.grid_import_kw, 0), 0) AS g, COALESCE(e.bess_output_kw, 0) AS b,
           e.current_rate_per_kwh AS rate,
           EXTRACT(EPOCH FROM (lead(e.timestamp) OVER (ORDER BY e.timestamp) - e.timestamp)) / 3600.0 AS dt
      FROM site_energy_snapshots e
     WHERE e.sim_run_id = p_run AND e.depot_id = p_depot
  ), s2 AS (
    -- the last sample has no successor; it holds for the arm's mean interval. Gaps beyond an hour are capped.
    SELECT t, g, b, rate, LEAST(COALESCE(dt, (SELECT avg(dt) FROM s WHERE dt IS NOT NULL), 0), 1.0) AS dt FROM s
  ), w AS (
    SELECT avg(g) OVER (ORDER BY t RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS g30 FROM s2
  )
  SELECT count(*), sum(g * dt), sum(g * dt * rate), (SELECT max(g30) FROM w),
         sum(GREATEST(b, 0) * dt), sum(GREATEST(-b, 0) * dt), min(rate)
    INTO v_samples, v_grid_kwh, v_cost, v_peak30, v_dis, v_chg, v_min_rate
    FROM s2;

  v_month := EXTRACT(MONTH FROM (r.sim_clock_start AT TIME ZONE c_tz))::int;
  SELECT t.block_kw, t.demand_first_block_usd_kw, t.demand_excess_usd_kw INTO v_block, v_r1, v_r2
    FROM ottoq_depot_tariffs t
   WHERE t.depot_id = p_depot AND t.active AND v_month = ANY (t.season_months)
   ORDER BY t.effective_from DESC LIMIT 1;
  v_demand := CASE WHEN v_r1 IS NULL OR v_peak30 IS NULL THEN NULL
                   ELSE v_r1 * LEAST(v_peak30, COALESCE(v_block, v_peak30))
                        + COALESCE(v_r2, v_r1) * GREATEST(0, v_peak30 - COALESCE(v_block, v_peak30)) END;

  v_amort := GREATEST(1, 30);
  RETURN public.stub_arm_metrics(p_run, p_depot, p_soc_start_kwh)
         || jsonb_build_object('energy_samples', v_samples, 'peak_30min_kw', round(v_peak30, 1),
                               'demand_charge_usd_month', round(v_demand, 2));
END
$function$;
