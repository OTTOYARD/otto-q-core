-- migration-version: PENDING
-- migration-name:    the_twins_battery_paid_for_a_cooling_system_it_never_got_so_it_sat_out_a_demand_response_call
--
-- 0450  **The twin's battery paid for a cooling system it never got, so in hot weather it could not discharge and sat
--       out most of a demand-response call at 78–93% state of charge.** `twin.ottoq_sim_bess_step` charges the pack an
--       auxiliary load described as "(BMS + HVAC + comms)". Its thermal model is passive: the target cell temperature
--       is `ambient + 3 + 12 × |P| / max_charge_kw`, so the cells never sit below ambient. `ottoq_energy_orchestrate`
--       holds the battery at 0 kW once the cells reach `temperature_max_c − 2` (48 °C of 50). The unit is recorded as
--       a Tesla Megapack 2 XL, LFP, 3,000 kWh, 1,500 kW. That product is liquid-cooled: "It uses coolant fluid, made
--       of an equal-parts mixture of ethylene glycol and water, to keep the battery at operating temperature"
--       (https://en.wikipedia.org/wiki/Tesla_Megapack, read 2026-09-23). Its datasheet gives an operating ambient range
--       of –30 °C to 50 °C, as returned by a web search of the datasheet filed at
--       https://efiling.energy.ca.gov/GetDocument.aspx?tn=243445&DocumentContentId=77253 (2026-09-23). The PDF itself
--       is AES-encrypted and could not be text-extracted here, so the range rests on the search index's reading of it.
--       FINDINGS G183.
--
-- ══ §1 MEASURED 2026-09-23 ON RUN 324eb0f1 (busy_day, twin depot), THE WHOLE DR CALL ═══════════════════════════════
--
--   - The call ran sim 14:01:54 to 17:27 CT: baseline 404.8 kW, reduction 343.2 kW, cap 61.6 kW, heat-triggered at
--     45.3 °C ambient (G180, fixed by 0449).
--   - Of the 432 battery commands in the call, **317 (73%) were `thermal_hold` at 0 kW**. The other 114 were
--     `discharge_dr` and averaged 524 kW. SoC stayed between 77.8% and 93.0%, so roughly 2,000 kWh sat unused above
--     the 10% floor.
--   - Across 432 energy samples in the call, grid import averaged **376 kW against the 62 kW cap**; 363 samples were
--     over it (max 876 kW). EV charging averaged 603 kW, solar 247 kW and building load 156 kW.
--   - What the battery would have needed: holding 62 kW at the grid takes EV + building − solar − cap ≈ 450 kW for
--     3.4 h ≈ 1,530 kWh. That is inside what it held. The binding limit was temperature, not energy.
--   - The EV side is not this file's. Running sessions are never curtailed (the vehicle-first doctrine, N1, in
--     `twin.ottoq_sim_advance_charge_sessions`). The DR gate can only refuse new starts, so under N1 the battery is
--     the only instrument that can hold a DR cap. That is why its thermal model decides DR compliance. G184 records
--     the doctrine question separately.
--
-- ══ §2 WHAT THIS DOES ════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `ottoq_bess_units` gains the coolant loop's parameters, each defaulted and each ASSUMPTION-labelled:
--       - `hvac_setpoint_c` 25: the cell temperature the loop holds. It is the same 25 °C every certification reset
--         already writes.
--       - `hvac_rated_ambient_c` 50 and `hvac_rated_min_ambient_c` −30: the datasheet's operating range.
--         ASSUMPTION: full rated power across that range. The search reading gives the range, not a derate curve.
--       - `hvac_rated_kw`, NULL = 1% of rated power: the loop's electrical draw at full duty.
--         ASSUMPTION: loss heat at rated power (one-way 2%, 30 kW thermal at 1.5 MW) over a chiller COP of about 2
--         gives 15 kW, on top of the existing 8 kW auxiliary load.
--   (2) The thermal target is the passive target moved by the loop:
--       - Cooling, when passive > setpoint: `GREATEST(setpoint, passive − lift_c)`, with
--         `lift_c = rated_ambient + 15 − setpoint` (40 °C by default). The loop holds the setpoint at rated power up
--         to the rated ambient, and the cells rise only with the excess: 30 °C at rated power in 55 °C air.
--       - Heating, when passive < setpoint: `LEAST(setpoint, passive + lift_h)`, with
--         `lift_h = setpoint − (rated_min_ambient + 3)`.
--       - The loop's duty, `|passive − setpoint| / lift` capped at 1, times `hvac_rated_kw`, is added to the auxiliary
--         load the pack already pays.
--   (3) The thermal lag becomes tick-invariant: `1 − exp(−tick_minutes / 5)`, replacing 0.18 per tick. The comment it
--       replaces already said "~5 min tau". That held only at 1-minute ticks: the demo metronome ticks every ~0.48
--       sim-minutes (tau 2.6 min) and the certification harness every 30 (tau 2.7 h). The noise term is unchanged.
--   Unchanged:
--   - `ottoq_sim_bess_compute_max_power_kw`'s derate above 45 °C and below 5 °C.
--   - The `twin.bess_thermal_derate` event.
--   - The orchestrator's hold at `temperature_max_c − 2`, and the DR allowance's matching thermal predicate. Both
--     stay as safety backstops, and a loop that holds 25 °C keeps them from firing.
--
-- ══ §3 forces_recert TRUE ════════════════════════════════════════════════════════════════════════════════════
--
--   Every certification arm steps the battery. Its temperature is in the world fingerprint, and its SoC now pays the
--   loop's duty.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0450 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%' OR query ILIKE '%ottoq_dial_experiment_runner%'
          OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0450 P0: a pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0450 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: the battery step as read on 2026-09-23, every anchor unique; the columns do not exist yet ──
DO $$
DECLARE v_src text; v_n int; v_a text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'twin.ottoq_sim_bess_step'::regproc;
  IF md5(v_src) <> 'dd65d18b5129bde1d0ab9cc1609b0cce' THEN
    RAISE EXCEPTION '0450 P1: twin.ottoq_sim_bess_step md5 is %', md5(v_src);
  END IF;
  FOREACH v_a IN ARRAY ARRAY[
      E'  v_thermal_lag  NUMERIC := 0.18;            -- per tick (~5 min tau time)\n',
      E'  v_bms_margin   NUMERIC;\nBEGIN\n',
      E'  v_aux_load   := v.auxiliary_load_kw * v_aux_noise;\n',
      E'  v_target_temp := v_ambient + 3.0 + (ABS(v_actual_kw) / v.max_charge_kw) * 12.0;\n']
  LOOP
    v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
    IF v_n <> 1 THEN RAISE EXCEPTION '0450 P1: anchor matched % times: %', v_n, left(v_a, 70); END IF;
  END LOOP;
  IF (SELECT count(*) FROM regexp_matches(v_src, 'v_thermal_lag', 'g')) <> 2 THEN
    RAISE EXCEPTION '0450 P1: v_thermal_lag is used somewhere this file does not cover';
  END IF;
  IF (SELECT count(*) FROM regexp_matches(v_src, 'v_target_temp', 'g')) <> 3 THEN
    RAISE EXCEPTION '0450 P1: v_target_temp is used somewhere this file does not cover';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ottoq_bess_units'
              AND column_name IN ('hvac_setpoint_c','hvac_rated_ambient_c','hvac_rated_min_ambient_c','hvac_rated_kw')) THEN
    RAISE EXCEPTION '0450 P1: an hvac column already exists on ottoq_bess_units';
  END IF;
  -- the unit this was measured on is still what §1 says
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_bess_units WHERE depot_id = '11111111-1111-1111-1111-111111111111'
                  AND max_discharge_kw = 1500 AND capacity_kwh = 3000 AND temperature_max_c = 50) THEN
    RAISE EXCEPTION '0450 P1: the twin depot battery is not the 3,000 kWh / 1,500 kW / 50 C unit this file was built on';
  END IF;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0450_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_bess_step'::regproc;

-- ── (1) THE LOOP'S PARAMETERS ──
ALTER TABLE public.ottoq_bess_units
  ADD COLUMN hvac_setpoint_c          numeric NOT NULL DEFAULT 25  CHECK (hvac_setpoint_c BETWEEN 0 AND 45),
  ADD COLUMN hvac_rated_ambient_c     numeric NOT NULL DEFAULT 50  CHECK (hvac_rated_ambient_c BETWEEN 20 AND 70),
  ADD COLUMN hvac_rated_min_ambient_c numeric NOT NULL DEFAULT -30 CHECK (hvac_rated_min_ambient_c BETWEEN -60 AND 10),
  ADD COLUMN hvac_rated_kw            numeric CHECK (hvac_rated_kw IS NULL OR hvac_rated_kw >= 0);
COMMENT ON COLUMN public.ottoq_bess_units.hvac_setpoint_c IS
  '0450 (G183). Cell temperature the coolant loop holds. 25 C = the value every certification reset writes.';
COMMENT ON COLUMN public.ottoq_bess_units.hvac_rated_ambient_c IS
  '0450. Highest ambient at which the loop holds the setpoint at rated power (lift = this + 15 - setpoint). Default 50 C: '
  'the Megapack 2 XL operating range as read by a web search of its datasheet on 2026-09-23 (ASSUMPTION: no derate '
  'inside the range; the reading gives the range, not a curve).';
COMMENT ON COLUMN public.ottoq_bess_units.hvac_rated_min_ambient_c IS
  '0450. Lowest ambient at which the loop holds the setpoint (heating lift = setpoint - (this + 3)). Default -30 C, same source.';
COMMENT ON COLUMN public.ottoq_bess_units.hvac_rated_kw IS
  '0450. Electrical draw of the loop at full duty, added to auxiliary_load_kw in proportion to duty. NULL = 1% of rated '
  'power (ASSUMPTION: one-way loss heat 2% of rated power over a chiller COP of about 2).';

-- ── (2)+(3) THE STEP ──
DO $splice$
DECLARE v_def text; v_new text;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_bess_step'::regproc);
  v_new := replace(v_def,
    E'  v_thermal_lag  NUMERIC := 0.18;            -- per tick (~5 min tau time)\n',
    E'  v_thermal_lag  NUMERIC;                    -- 0450: 1 - exp(-tick_minutes / 5), set below (was 0.18 per tick)\n');
  v_new := replace(v_new,
    E'  v_bms_margin   NUMERIC;\nBEGIN\n',
    E'  v_bms_margin   NUMERIC;\n'
    || E'  v_passive_c    NUMERIC;                    -- 0450 (G183): the old target, before the coolant loop\n'
    || E'  v_lift_c       NUMERIC;                    -- 0450: cooling lift the loop was sized for\n'
    || E'  v_lift_h       NUMERIC;                    -- 0450: heating lift\n'
    || E'  v_setpoint_c   NUMERIC;\n'
    || E'  v_duty         NUMERIC := 0;\n'
    || E'BEGIN\n');
  v_new := replace(v_new,
    E'  v_aux_load   := v.auxiliary_load_kw * v_aux_noise;\n',
    E'  /* 0450 (G183): the coolant loop. The passive target is the old model; the loop holds the setpoint while the lift\n'
    || E'     it needs is within the lift it was sized for (rated power at the rated ambient), and pays for it in\n'
    || E'     proportion to duty. Computed here because the pack pays the loop in this tick''s energy. */\n'
    || E'  v_setpoint_c := COALESCE(v.hvac_setpoint_c, 25);\n'
    || E'  v_passive_c  := v_ambient + 3.0 + (ABS(v_actual_kw) / v.max_charge_kw) * 12.0;\n'
    || E'  v_lift_c     := GREATEST(1.0, COALESCE(v.hvac_rated_ambient_c, 50) + 15.0 - v_setpoint_c);\n'
    || E'  v_lift_h     := GREATEST(1.0, v_setpoint_c - (COALESCE(v.hvac_rated_min_ambient_c, -30) + 3.0));\n'
    || E'  v_duty       := CASE WHEN v_passive_c > v_setpoint_c THEN LEAST(1.0, (v_passive_c - v_setpoint_c) / v_lift_c)\n'
    || E'                       ELSE LEAST(1.0, (v_setpoint_c - v_passive_c) / v_lift_h) END;\n'
    || E'  v_aux_load   := v.auxiliary_load_kw * v_aux_noise\n'
    || E'                + v_duty * COALESCE(v.hvac_rated_kw, 0.01 * GREATEST(v.max_charge_kw, v.max_discharge_kw));\n');
  v_new := replace(v_new,
    E'  v_target_temp := v_ambient + 3.0 + (ABS(v_actual_kw) / v.max_charge_kw) * 12.0;\n',
    E'  -- 0450 (G183): the loop holds the setpoint up to its lift; the cells follow only the excess beyond it.\n'
    || E'  v_target_temp := CASE WHEN v_passive_c > v_setpoint_c THEN GREATEST(v_setpoint_c, v_passive_c - v_lift_c)\n'
    || E'                        ELSE LEAST(v_setpoint_c, v_passive_c + v_lift_h) END;\n'
    || E'  -- 0450: tick-invariant lag with the 5-minute time constant the original comment named\n'
    || E'  v_thermal_lag := 1 - exp(-GREATEST(COALESCE(p_tick_minutes, 1), 0) / 5.0);\n');
  IF v_new = v_def
     OR position('v_passive_c - v_lift_c' IN v_new) = 0
     OR position('v_duty * COALESCE(v.hvac_rated_kw' IN v_new) = 0
     OR position('1 - exp(-GREATEST(COALESCE(p_tick_minutes, 1), 0) / 5.0)' IN v_new) = 0
     OR position('v_thermal_lag  NUMERIC := 0.18;' IN v_new) > 0 THEN
    RAISE EXCEPTION '0450: the battery-step splices did not all apply';
  END IF;
  EXECUTE v_new;
END $splice$;

-- ── V1: what shipped is what the header says (comment-stripped): the loop is computed before the pack pays it, and
--        the lag is set before the temperature update uses it ──
DO $$
DECLARE v_src text;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc WHERE oid = 'twin.ottoq_sim_bess_step'::regproc;
  IF position('v_duty * COALESCE(v.hvac_rated_kw' IN v_src) = 0
     OR position('v_passive_c  := v_ambient' IN v_src) > position('v_duty * COALESCE(v.hvac_rated_kw' IN v_src)
     OR position('v_duty * COALESCE(v.hvac_rated_kw' IN v_src) > position('v_new_soc_kwh := v.current_soc_kwh + v_kwh_delta' IN v_src)
     OR position('v_thermal_lag := 1 - exp(' IN v_src) = 0
     OR position('v_thermal_lag := 1 - exp(' IN v_src) > position('* v_thermal_lag' IN v_src)
     OR position('GREATEST(v_setpoint_c, v_passive_c - v_lift_c)' IN v_src) = 0 THEN
    RAISE EXCEPTION '0450 V1: the battery step does not model the loop in the order the header says';
  END IF;
END $$;

-- ── V2: the step itself, on the twin depot's unit, rolled back:
--        (a) §1's call: 46.6 C cells, 45.3 C air, 1,500 kW discharge for 30 sim-minutes at the demo cadence: the cells
--            fall toward the setpoint and never approach the 48 C hold;
--        (b) 55 C air at rated power, long enough to settle: the cells rise only with the excess, to ~30 C;
--        (c) 0 C air, idle: the loop heats to the setpoint;
--        (d) the loop's duty is paid: at rated power in 45 C air a tick removes more energy than the same tick in
--            25 C air;
--        (e) tick invariance: ten ticks of 0.5 min and one tick of 5 min land within noise of each other. ──
DO $v2$
DECLARE
  v_b uuid; v_run uuid; v_clk timestamptz := '2026-09-22 19:00:00+00'; i int; r record; v_t numeric; v_max_t numeric;
  v_soc_hot numeric; v_soc_cool numeric; v_t_fine numeric; v_t_coarse numeric;
BEGIN
  SELECT bess_id INTO v_b FROM public.ottoq_bess_units WHERE depot_id = '11111111-1111-1111-1111-111111111111' LIMIT 1;
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs WHERE depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY started_at DESC LIMIT 1;
  BEGIN
    -- (a)
    UPDATE public.ottoq_bess_units SET current_temperature_c = 46.6, current_soc_pct = 85, current_soc_kwh = 2550 WHERE bess_id = v_b;
    v_max_t := 0;
    FOR i IN 1..60 LOOP
      SELECT * INTO r FROM twin.ottoq_sim_bess_step(v_b, v_run, v_clk + make_interval(secs => i * 30), 0.5, -1500, 45.3, '0450_probe');
      v_max_t := GREATEST(v_max_t, r.out_temp_c_new);
    END LOOP;
    IF r.out_temp_c_new > 32 OR v_max_t >= 48 THEN
      RAISE EXCEPTION '0450 V2(a): cells at % C after 30 min at rated discharge in 45.3 C air (max %)', r.out_temp_c_new, v_max_t;
    END IF;
    RAISE NOTICE '0450 V2(a): 46.6 C -> % C in 30 sim-min at -1500 kW, 45.3 C air (max %)', r.out_temp_c_new, v_max_t;
    -- (b)
    UPDATE public.ottoq_bess_units SET current_temperature_c = 25, current_soc_pct = 85, current_soc_kwh = 2550 WHERE bess_id = v_b;
    -- two 30-minute ticks settle it (lag 1 - e^-6) without reaching the SoC floor, which would idle the pack
    FOR i IN 1..2 LOOP
      SELECT * INTO r FROM twin.ottoq_sim_bess_step(v_b, v_run, v_clk + make_interval(mins => i * 30), 30, -1500, 55, '0450_probe');
    END LOOP;
    IF r.out_temp_c_new < 26.5 OR r.out_temp_c_new > 33.5 THEN
      RAISE EXCEPTION '0450 V2(b): cells at % C at rated power in 55 C air, expected ~30 C', r.out_temp_c_new;
    END IF;
    -- (c)
    UPDATE public.ottoq_bess_units SET current_temperature_c = 5, current_soc_pct = 50, current_soc_kwh = 1500 WHERE bess_id = v_b;
    FOR i IN 1..4 LOOP
      SELECT * INTO r FROM twin.ottoq_sim_bess_step(v_b, v_run, v_clk + make_interval(mins => i * 30), 30, 0, 0, '0450_probe');
    END LOOP;
    IF abs(r.out_temp_c_new - 25) > 3.5 THEN
      RAISE EXCEPTION '0450 V2(c): cells at % C idle in 0 C air, expected ~25 C', r.out_temp_c_new;
    END IF;
    -- (d)
    UPDATE public.ottoq_bess_units SET current_temperature_c = 25, current_soc_pct = 60, current_soc_kwh = 1800 WHERE bess_id = v_b;
    SELECT * INTO r FROM twin.ottoq_sim_bess_step(v_b, v_run, v_clk, 30, -1500, 45, '0450_probe');
    v_soc_hot := r.out_soc_pct_new;
    UPDATE public.ottoq_bess_units SET current_temperature_c = 25, current_soc_pct = 60, current_soc_kwh = 1800 WHERE bess_id = v_b;
    SELECT * INTO r FROM twin.ottoq_sim_bess_step(v_b, v_run, v_clk, 30, -1500, 10, '0450_probe');
    v_soc_cool := r.out_soc_pct_new;
    IF NOT (v_soc_hot < v_soc_cool) THEN
      RAISE EXCEPTION '0450 V2(d): the loop is not paid: SoC after a hot tick % vs a mild tick %', v_soc_hot, v_soc_cool;
    END IF;
    -- (e)
    UPDATE public.ottoq_bess_units SET current_temperature_c = 40, current_soc_pct = 85, current_soc_kwh = 2550 WHERE bess_id = v_b;
    -- one time constant in: 25 + 15/e = 30.5 C both ways under 0450; under the old 0.18-per-tick lag, ten 0.5-minute
    -- ticks gave 27.1 C and one 5-minute tick 37.3 C
    FOR i IN 1..10 LOOP
      SELECT * INTO r FROM twin.ottoq_sim_bess_step(v_b, v_run, v_clk + make_interval(secs => i * 30), 0.5, 0, 30, '0450_probe');
    END LOOP;
    v_t_fine := r.out_temp_c_new;
    UPDATE public.ottoq_bess_units SET current_temperature_c = 40, current_soc_pct = 85, current_soc_kwh = 2550 WHERE bess_id = v_b;
    SELECT * INTO r FROM twin.ottoq_sim_bess_step(v_b, v_run, v_clk, 5, 0, 30, '0450_probe');
    v_t_coarse := r.out_temp_c_new;
    IF abs(v_t_fine - v_t_coarse) > 4.5 THEN
      RAISE EXCEPTION '0450 V2(e): 10 x 0.5 min ended at % C, 1 x 5 min at % C', v_t_fine, v_t_coarse;
    END IF;
    RAISE NOTICE '0450 V2: (d) SoC after a hot tick % vs a mild one %; (e) 10 x 0.5 min -> % C, 1 x 5 min -> % C',
      v_soc_hot, v_soc_cool, v_t_fine, v_t_coarse;
    RAISE EXCEPTION USING MESSAGE = '0450_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> '0450_probe_rollback' THEN RAISE; END IF;
  END;
END $v2$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0450_the_twins_battery_paid_for_a_cooling_system_it_never_got_so_it_sat_out_a_demand_response_call',
   true,
   'G183: twin.ottoq_sim_bess_step models the unit''s coolant loop (ottoq_bess_units.hvac_setpoint_c, hvac_rated_ambient_c, '
   'hvac_rated_min_ambient_c, hvac_rated_kw): the cells hold the setpoint while the lift is within the loop''s rating and '
   'follow only the excess; the loop''s duty is paid from the pack; the thermal lag is 1 - exp(-tick_minutes/5) instead of '
   '0.18 per tick. TRUE: every certification arm steps the battery and its temperature is fingerprinted.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- forces_recert TRUE. Live proof on the next hot demo run: ottoq_energy_commands shows no `thermal_hold` while ambient is
-- inside the rated range, and a DR call's grid import stays at its cap while the battery has energy above its floor.
-- Rollback: restore the step from ottoq_schema_snapshots label '0450_pre' and drop the four hvac_* columns.
