-- migration-version: 20260923012038
-- migration-name:    a_demand_response_reduction_was_read_as_the_depots_whole_charging_ceiling_and_the_gate_forgot_the_battery
--
-- 0433  **A demand-response call asks the depot to shed 50–400 kW. The engine read that number as the depot's
--       entire charging ceiling, refused charges against it without counting a 3,000 kWh battery that could
--       cover the reduction for hours, and drew the call per scheduler tick.** Evidence: `db/checks/0353`
--       (measured on run `7a42982a`), FINDINGS G160, docs/REVIEW_RANKED_FINDINGS_2026-09-22.md rank 1.
--
-- ══ §1 WHAT IS WRONG, FROM SOURCE ═════════════════════════════════════════════
--
--   (a) `twin.ottoq_sim_maybe_ignite_dr_call` samples `50 + U·350` — its own comment: *"Sample required load
--       cap (50-400 kW reduction)"* — and stores it in `ottoq_dr_calls.required_load_cap_kw`. Every consumer
--       reads that column as an ABSOLUTE cap: `ottoq_effective_charge_cap_kw` = `LEAST(service_max_kw, it)`,
--       `ottoq_energy_orchestrate` lowers its grid target to it, the twin's site model and the excursion
--       detector compare grid import to it, and `ottoq_mirror_dr_call` would publish it as `target_kw`. So on
--       a 2,500 kW service a call to shed ~205 kW became "the depot may import ~205 kW".
--       Provenance for the reduction reading: TVA's own inspector general describes its DR programs as offering
--       "incentives for electric utility customers to reduce their energy use during peak demand" — TVA OIG
--       report 2025-17554, issued 2026-01-12, https://www.oversight.gov/reports/tva-demand-response
--       (retrieved 2026-09-22). The call's program is `TVA_VOLUNTARY`.
--   (b) `ottoq_decide_tick`'s 0132 gate refuses a charge when committed EV kW + the request exceeds that cap. It
--       counts no battery, no solar and no building load — while `ottoq_energy_orchestrate` treats the SAME
--       number as a GRID target and discharges the battery to meet it. Two consumers, two meanings: the gate
--       refuses load the battery was about to carry. The twin depot's battery is 3,000 kWh, 1,500 kW, floor 10%.
--   (c) The ignition probability (3% + 1.2%/°C above 32 °C, 14:00–19:00 CT) is rolled every TICK, and the
--       roll's seed carries the run-relative clock, so it is redrawn each tick. At the demo cadence (~0.3–0.5
--       sim-min) a hot afternoon ignites a call within minutes and re-ignites on expiry; at the cert cadence
--       (30 sim-min) the same five hours carry ~26% odds. G130's defect class (0413/0420), same fix shape.
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════
--
--   (A) The generator keeps its draw EXACTLY (same salts, same sample) and reads it as what its comment says, a
--       REDUCTION. It measures a baseline — the mean grid import of this run's last 60 sim-minutes of site
--       snapshots, else the latest snapshot — and stores `required_load_cap_kw = GREATEST(0, baseline −
--       reduction)`. So the column finally holds what its name, and every one of its readers, says: a cap on
--       grid import. Baseline, reduction and the baseline's source ride in the `twin.dr_call_issued` event.
--       This is a PRIOR-HOUR baseline, a deliberate simplification of a utility customer-baseline method; it is
--       named as such in the payload. Dial `dr_cap_from_baseline` (default 1; 0 = the old reading).
--   (B) `public.ottoq_ev_charge_allowance_kw(run, depot, clock)`: outside a call it returns exactly what
--       `ottoq_effective_charge_cap_kw` returns (0132's meaning unchanged). Inside a call it returns the EV load
--       the grid cap leaves room for: `cap − building + solar + sustainable battery discharge`, where the
--       battery term is `LEAST(max_discharge_kw, usable kWh above floor ÷ hours left in the call)` for units
--       inside their thermal limit, floored at 0 and capped at the service maximum. `ottoq_decide_tick`'s
--       gate reads it in place of the cap — one line. Dial `dr_gate_credits_site_energy` (default 1).
--   (C) The ignition probability is read as a per-30-sim-minute hazard — the cadence the canon runs at, so
--       every cert arm draws EXACTLY the probability it drew before — and elapsed over the sim time this tick
--       advanced (`payload.tick_minutes_actual`, 0420's source): `p_tick = 1 − (1 − p30)^(Δ/30)`.
--       ASSUMPTION: the model's author calibrated at the 30-minute cert cadence; nothing in the source states a
--       unit. Dial `dr_hazard_per_sim_time` (default 1).
--   (D) The agent's grounding block publishes `ev_charge_allowance_kw` beside the cap and stops telling it that
--       battery discharge does not help.
--
-- ══ §3 forces_recert TRUE ══════════════════════════════════════════════════
--
-- A cert arm that ignites a call now stores a different cap and admits different charges. (C) alone would
-- leave the canon's draw unchanged at Δ = 30, but (A) and (B) move commands, decisions and end state.
--
-- ══ §4 WHAT IS DELIBERATELY NOT DONE ════════════════════════════════════════
--
--   1. **`EN.004` is not rewired.** It reads `ottoq_grid_events`, never populated by the twin (the mirror has no
--      caller), and `charge_session_start` is an ENFORCING checkpoint since 0428 — wiring the mirror now would
--      add a second DR gate with its own current-demand arithmetic. Do it once, after measuring this, with EN.004
--      reading `ottoq_ev_charge_allowance_kw`.
--   2. **No DR reserve.** Holding battery for a call that has not been issued (hot-afternoon reserve) is a policy
--      change in `ottoq_energy_orchestrate`; measure the SoC at ignition first (0353 §3).
--   3. **The call stays binding.** A voluntary program could be treated as a priced objective rather than a
--      constraint; that is a product decision, not a bug.
--
-- ══ §5 PRE-FLIGHT, CHANGE, VERIFICATION ══════════════════════════════════════

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0433 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0433 P0: a determinism pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0433 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: md5 guards ──
DO $$
DECLARE r record; v_n int := 0;
BEGIN
  FOR r IN SELECT n.nspname, p.proname, md5(p.prosrc) AS m FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE (n.nspname, p.proname) IN (('twin','ottoq_sim_maybe_ignite_dr_call'), ('public','ottoq_decide_tick'),
                                             ('public','ottoq_agent_board_grounding'), ('public','ottoq_effective_charge_cap_kw'))
  LOOP
    v_n := v_n + 1;
    IF (r.proname = 'ottoq_sim_maybe_ignite_dr_call' AND r.m <> 'e633a13455f733cd7d71ded13752e77a')
    OR (r.proname = 'ottoq_decide_tick'              AND r.m <> '52d06d71cbfb079634899ec79a4ad696')
    OR (r.proname = 'ottoq_agent_board_grounding'    AND r.m <> 'e1412c66cf63bcb340c266b48897d13a')
    OR (r.proname = 'ottoq_effective_charge_cap_kw'  AND r.m <> 'e976e8bb0f4cc29715c73935cebde33e') THEN
      RAISE EXCEPTION '0433 P1: %.% prosrc md5 is % -- it changed since this file read it', r.nspname, r.proname, r.m;
    END IF;
  END LOOP;
  IF v_n <> 4 THEN RAISE EXCEPTION '0433 P1: expected 4 functions (one overload each), found %', v_n; END IF;
END $$;

-- ── P2: anchors occur exactly once; the gate is the only reader of the cap in decide_tick ──
DO $$
DECLARE v_src text; v_n int; v_a text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_decide_tick';
  v_a := 'v_charge_cap_kw := public.ottoq_effective_charge_cap_kw(p_sim_run_id, v_depot, v_clock);  /* 0132 */';
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0433 P2: decide_tick cap anchor matched % times', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, 'ottoq_effective_charge_cap_kw', ''))) / length('ottoq_effective_charge_cap_kw');
  IF v_n <> 1 THEN RAISE EXCEPTION '0433 P2: decide_tick names the cap function % times -- a second reader would keep the old meaning', v_n; END IF;

  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_board_grounding';
  v_a := $a$'effective_charge_cap_kw', round(public.ottoq_effective_charge_cap_kw(p_sim_run_id, p_depot_id, p_clock)),$a$;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0433 P2: grounding cap anchor matched % times', v_n; END IF;
  v_a := $a$'note', 'While a DR call is active, new charges are admitted only while committed EV kW stays under the '
              'call''s cap; battery discharge does not raise that cap in the current gate.'),$a$;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0433 P2: grounding energy note anchor matched % times', v_n; END IF;
END $$;

-- ── P3: premises ──
DO $$
DECLARE v_n int;
BEGIN
  -- the generator is the only writer of ottoq_dr_calls, so (A) covers every row
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq') AND p.proname <> 'ottoq_sim_maybe_ignite_dr_call'
     AND regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~* 'INSERT\s+INTO\s+(public\.)?ottoq_dr_calls';
  IF v_n <> 0 THEN RAISE EXCEPTION '0433 P3: % other writer(s) of ottoq_dr_calls -- their rows would keep the old meaning', v_n; END IF;
  -- no call is in force on a live run (P0 already requires no live run; this is the table-level form)
  SELECT count(*) INTO v_n FROM public.ottoq_dr_calls c JOIN public.ottoq_sim_runs r ON r.sim_run_id = c.sim_run_id
   WHERE r.status IN ('running','paused') AND c.call_status IN ('active','issued');
  IF v_n <> 0 THEN RAISE EXCEPTION '0433 P3: % call(s) in force on a live run', v_n; END IF;
  -- the orchestrator and the site model already read the column as a GRID cap (the meaning (A) makes true)
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_energy_orchestrate'
     AND p.prosrc ~ 'IF v_dr_active THEN v_demand_target := LEAST\(v_demand_target, v_dr_cap\); END IF;';
  IF v_n <> 1 THEN RAISE EXCEPTION '0433 P3: ottoq_energy_orchestrate no longer lowers its grid target to the DR cap'; END IF;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0433_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname, p.proname) IN (('twin','ottoq_sim_maybe_ignite_dr_call'), ('public','ottoq_decide_tick'),
                                  ('public','ottoq_agent_board_grounding'));

-- ── DIALS ──
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES ('dr_cap_from_baseline',
        '0433: when >= 1 the twin DR generator reads its 50-400 kW draw as a REDUCTION and stores cap = prior-hour '
        'baseline grid import minus it; 0 restores the pre-0433 reading (the draw itself as the cap).',
        1, 0, 1, 'twin.ottoq_sim_maybe_ignite_dr_call', false),
       ('dr_gate_credits_site_energy',
        '0433: when >= 1 the decide gate admits EV load up to cap - building + solar + sustainable battery discharge '
        'during a DR call (public.ottoq_ev_charge_allowance_kw); 0 restores the pre-0433 gate (EV kW against the cap).',
        1, 0, 1, 'public.ottoq_ev_charge_allowance_kw -> ottoq_decide_tick', false),
       ('dr_hazard_per_sim_time',
        '0433: when >= 1 the DR ignition probability is a per-30-sim-minute hazard elapsed over the sim time the tick '
        'advanced (identical at the 30-minute cert cadence); 0 restores the per-tick roll.',
        1, 0, 1, 'twin.ottoq_sim_maybe_ignite_dr_call', false)
ON CONFLICT (param_key) DO NOTHING;

-- ── (A) + (C): THE GENERATOR ──
CREATE OR REPLACE FUNCTION twin.ottoq_sim_maybe_ignite_dr_call(p_depot_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_ambient_temp_c numeric, p_seed bigint)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_hour     INTEGER;
  v_roll     NUMERIC;
  v_prob     NUMERIC := 0;
  v_existing UUID;
  v_call_id  UUID;
  v_dur_min  NUMERIC;
  v_cap_kw   NUMERIC;
  v_red_kw   NUMERIC;   -- 0433
  v_base_kw  NUMERIC;   -- 0433
  v_base_src TEXT;      -- 0433
  v_tick_min NUMERIC;   -- 0433
  v_zero     CONSTANT uuid := '00000000-0000-0000-0000-000000000000';
BEGIN
  -- Don't ignite if already active
  SELECT dr_call_id INTO v_existing
    FROM ottoq_dr_calls
   WHERE depot_id = p_depot_id AND call_status = 'active'
     AND expires_at > p_sim_clock_now LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  v_hour := EXTRACT(HOUR FROM p_sim_clock_now AT TIME ZONE 'America/Chicago')::int;

  -- Probability model: hot afternoon peak hours
  IF p_ambient_temp_c >= 32 AND v_hour BETWEEN 14 AND 19 THEN
    v_prob := 0.030 + (p_ambient_temp_c - 32) * 0.012;
  ELSIF p_ambient_temp_c >= 30 AND v_hour BETWEEN 15 AND 18 THEN
    v_prob := 0.010;
  ELSIF p_ambient_temp_c <= -5 AND v_hour BETWEEN 6 AND 9 THEN
    -- Winter morning event
    v_prob := 0.015;
  END IF;

  -- A.8: scale DR-ignition probability by the run's variability profile
  v_prob := v_prob * ottoq_profile_rate_mult(p_sim_run_id, 'dr_ignition');

  -- 0433 (C): A HAZARD, NOT A PER-TICK COIN. The probability above is read as per 30 sim-minutes -- the cadence
  -- the canon runs at, so a cert tick draws exactly what it drew before -- and elapsed over the sim time THIS tick
  -- advanced, which the advancer publishes before the world steps (0420's source, same reasoning). A tick that
  -- advanced no time carries no hazard. ASSUMPTION: the author calibrated at the 30-minute cadence.
  IF COALESCE(ottoq_policy_get(p_sim_run_id, 'dr_hazard_per_sim_time', 1), 1) >= 1 AND v_prob > 0 THEN
    SELECT COALESCE(NULLIF(r.payload->>'tick_minutes_actual','')::numeric,
                    (r.tick_interval_seconds * r.time_scale) / 60.0, 30)
      INTO v_tick_min FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
    v_tick_min := COALESCE(v_tick_min, 30);
    IF v_tick_min <= 0 THEN RETURN NULL; END IF;
    v_prob := 1 - power(1 - LEAST(v_prob, 0.999), v_tick_min / 30.0);
  END IF;

  v_roll := ottoq_sim_seeded_random(p_seed, 'dr_ignite');
  IF v_roll >= v_prob THEN RETURN NULL; END IF;

  -- Sample duration (90-240 min, Weibull-shaped via U^0.75)
  v_dur_min := 90 + POWER(ottoq_sim_seeded_random(p_seed, 'dr_dur'), 0.75) * 150;
  -- Sample required load cap (50-400 kW reduction)
  v_cap_kw  := 50 + ottoq_sim_seeded_random(p_seed, 'dr_cap') * 350;

  -- 0433 (A): THE DRAW IS A REDUCTION, AS THE LINE ABOVE HAS ALWAYS SAID. Every reader of required_load_cap_kw
  -- treats it as a cap on grid import, so store the cap: a prior-hour baseline minus the reduction. The draw is
  -- untouched (same salts, same sample) -- only its meaning is honoured.
  IF COALESCE(ottoq_policy_get(p_sim_run_id, 'dr_cap_from_baseline', 1), 1) >= 1 THEN
    v_red_kw := v_cap_kw;
    SELECT avg(e.grid_import_kw) INTO v_base_kw
      FROM site_energy_snapshots e
     WHERE e.depot_id = p_depot_id
       AND COALESCE(e.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
       AND e.timestamp >  p_sim_clock_now - interval '60 minutes'
       AND e.timestamp <= p_sim_clock_now;
    v_base_src := 'prior_60_sim_min_mean_grid_import';
    IF v_base_kw IS NULL THEN
      SELECT e.grid_import_kw INTO v_base_kw
        FROM site_energy_snapshots e
       WHERE e.depot_id = p_depot_id
         AND COALESCE(e.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
         AND e.timestamp <= p_sim_clock_now
       ORDER BY e.timestamp DESC, e.id LIMIT 1;
      v_base_src := 'latest_snapshot_grid_import';
    END IF;
    IF v_base_kw IS NULL THEN
      -- No site history at all: keep the pre-0433 value rather than invent a baseline, and say so.
      v_base_src := 'none_pre_0433_reading_kept';
    ELSE
      v_cap_kw := GREATEST(0, v_base_kw - v_red_kw);
    END IF;
  END IF;

  v_call_id := gen_random_uuid();
  INSERT INTO ottoq_dr_calls (
    dr_call_id, depot_id, sim_run_id, issued_at, expires_at,
    duration_minutes, required_load_cap_kw, reason, program, call_status
  ) VALUES (
    v_call_id, p_depot_id, p_sim_run_id, p_sim_clock_now,
    p_sim_clock_now + (v_dur_min || ' minutes')::interval,
    v_dur_min, v_cap_kw,
    CASE WHEN p_ambient_temp_c >= 32 THEN 'heat_demand_response'
         WHEN p_ambient_temp_c <= -5 THEN 'cold_winter_morning'
         ELSE 'contingency' END,
    'TVA_VOLUNTARY', 'active');

  PERFORM ottoq_record_event(
    p_actor_type    := 'external_sensor',
    p_actor_id      := 'tva_dr_program',
    p_event_type    := 'twin.dr_call_issued',
    p_entity_type   := 'depot',
    p_entity_id     := p_depot_id,
    p_payload       := jsonb_build_object(
      'dr_call_id', v_call_id,
      'duration_min', v_dur_min,
      'required_cap_kw', v_cap_kw,
      'required_reduction_kw', v_red_kw,        -- 0433
      'baseline_kw', round(v_base_kw, 1),       -- 0433
      'baseline_source', v_base_src,            -- 0433
      'tick_minutes', v_tick_min,               -- 0433
      'reason', CASE WHEN p_ambient_temp_c >= 32 THEN 'heat'
                     WHEN p_ambient_temp_c <= -5 THEN 'cold'
                     ELSE 'contingency' END,
      'temp_c', p_ambient_temp_c),
    p_severity      := 'warning',
    p_ingest_source := 'twin',
    p_data_source   := 'twin',
    p_sim_run_id    := p_sim_run_id);

  RETURN v_call_id;
END;
$function$;

-- ── (B): THE EV ALLOWANCE ──
CREATE OR REPLACE FUNCTION public.ottoq_ev_charge_allowance_kw(p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamptz)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'ottoq', 'twin', 'extensions'
AS $fn$
-- 0433 (db/checks/0353). The EV charging load the decide gate may admit. Outside a demand-response call it is
-- EXACTLY ottoq_effective_charge_cap_kw -- 0132's meaning, unchanged. Inside one, the cap is on GRID IMPORT
-- (what the utility meters, what ottoq_energy_orchestrate and the twin's site model already enforce), so EV load
-- may use what the building leaves, plus solar, plus what the battery can sustain until the call expires.
DECLARE
  v_zero    constant uuid := '00000000-0000-0000-0000-000000000000';
  v_cap     numeric; v_service numeric; v_expires timestamptz;
  v_bld     numeric; v_sol numeric; v_hours numeric; v_bess numeric;
BEGIN
  v_cap := public.ottoq_effective_charge_cap_kw(p_sim_run_id, p_depot_id, p_sim_clock);
  IF v_cap IS NULL THEN RETURN NULL; END IF;
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'dr_gate_credits_site_energy', 1), 1) < 1 THEN
    RETURN v_cap;
  END IF;

  -- the call that set the cap, by the cap function's own predicate and tie-break
  SELECT c.expires_at INTO v_expires
    FROM public.ottoq_dr_calls c
   WHERE c.depot_id = p_depot_id AND c.call_status IN ('active','issued') AND c.expires_at > p_sim_clock
     AND COALESCE(c.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
   ORDER BY c.required_load_cap_kw ASC, c.dr_call_id LIMIT 1;
  SELECT d.service_max_kw INTO v_service FROM public.depots d WHERE d.id = p_depot_id;
  IF v_expires IS NULL OR (v_service IS NOT NULL AND v_cap >= v_service) THEN
    RETURN v_cap;   -- no call binding: the 0132 gate exactly as it was
  END IF;

  SELECT e.building_load_kw, e.solar_generation_kw INTO v_bld, v_sol
    FROM public.site_energy_snapshots e
   WHERE e.depot_id = p_depot_id AND e.timestamp <= p_sim_clock
     AND COALESCE(e.sim_run_id, v_zero) = COALESCE(p_sim_run_id, v_zero)
   ORDER BY e.timestamp DESC, e.id LIMIT 1;

  -- the battery may cover the gap only as far as it can SUSTAIN it to the end of the call
  v_hours := GREATEST(0.25, extract(epoch FROM (v_expires - p_sim_clock)) / 3600.0);
  SELECT COALESCE(sum(LEAST(COALESCE(b.max_discharge_kw, 0),
                            GREATEST(0, COALESCE(b.capacity_kwh, 0)
                                       * (COALESCE(b.current_soc_pct, 0) - COALESCE(b.soc_min_floor_pct, 10)) / 100.0)
                              / v_hours)), 0)
    INTO v_bess
    FROM public.ottoq_bess_units b
   WHERE b.depot_id = p_depot_id
     AND COALESCE(b.current_temperature_c, 25) < COALESCE(b.temperature_max_c, 50) - 2;

  RETURN GREATEST(0, LEAST(COALESCE(v_service, v_cap + v_bess + COALESCE(v_sol, 0)),
                           v_cap - COALESCE(v_bld, 0) + COALESCE(v_sol, 0) + v_bess));
END
$fn$;

REVOKE ALL ON FUNCTION public.ottoq_ev_charge_allowance_kw(uuid, uuid, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_ev_charge_allowance_kw(uuid, uuid, timestamptz) TO authenticated, service_role;

-- ── (B): THE GATE READS THE ALLOWANCE ──
DO $$
DECLARE v_oid oid; v_def text; v_new text; v_a text; v_r text;
BEGIN
  SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_decide_tick';
  v_def := pg_get_functiondef(v_oid);
  v_a := 'v_charge_cap_kw := public.ottoq_effective_charge_cap_kw(p_sim_run_id, v_depot, v_clock);  /* 0132 */';
  v_r := 'v_charge_cap_kw := public.ottoq_ev_charge_allowance_kw(p_sim_run_id, v_depot, v_clock);  /* 0132; 0433: the cap is on grid import, so a DR call admits cap - building + solar + sustainable BESS */';
  IF (length(v_def) - length(replace(v_def, v_a, ''))) / length(v_a) <> 1 THEN
    RAISE EXCEPTION '0433 (B): decide_tick anchor not unique';
  END IF;
  v_new := replace(v_def, v_a, v_r);
  IF length(v_new) - length(v_def) <> length(v_r) - length(v_a) THEN
    RAISE EXCEPTION '0433 (B): byte delta % <> %', length(v_new) - length(v_def), length(v_r) - length(v_a);
  END IF;
  EXECUTE v_new;
END $$;

-- ── (D): THE AGENT SEES THE ALLOWANCE ──
DO $$
DECLARE v_oid oid; v_def text; v_new text; v_a1 text; v_r1 text; v_a2 text; v_r2 text;
BEGIN
  SELECT p.oid INTO v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_agent_board_grounding';
  v_def := pg_get_functiondef(v_oid);
  v_a1 := $a$'effective_charge_cap_kw', round(public.ottoq_effective_charge_cap_kw(p_sim_run_id, p_depot_id, p_clock)),$a$;
  v_r1 := $r$'effective_charge_cap_kw', round(public.ottoq_effective_charge_cap_kw(p_sim_run_id, p_depot_id, p_clock)),
      'ev_charge_allowance_kw', round(public.ottoq_ev_charge_allowance_kw(p_sim_run_id, p_depot_id, p_clock)),$r$;
  v_a2 := $a$'note', 'While a DR call is active, new charges are admitted only while committed EV kW stays under the '
              'call''s cap; battery discharge does not raise that cap in the current gate.'),$a$;
  v_r2 := $r$'note', 'effective_charge_cap_kw caps GRID import. While a DR call is active, new charges are admitted '
              'while committed EV kW stays under ev_charge_allowance_kw = cap - building + solar + what the '
              'battery can sustain until the call ends; keeping the battery charged before a hot afternoon '
              'keeps charging open during a call.'),$r$;
  IF (length(v_def) - length(replace(v_def, v_a1, ''))) / length(v_a1) <> 1
  OR (length(v_def) - length(replace(v_def, v_a2, ''))) / length(v_a2) <> 1 THEN
    RAISE EXCEPTION '0433 (D): a grounding anchor is not unique';
  END IF;
  v_new := replace(replace(v_def, v_a1, v_r1), v_a2, v_r2);
  IF length(v_new) - length(v_def) <> (length(v_r1) - length(v_a1)) + (length(v_r2) - length(v_a2)) THEN
    RAISE EXCEPTION '0433 (D): byte delta mismatch';
  END IF;
  EXECUTE v_new;
END $$;

-- ── V1: THE ALLOWANCE, on a synthetic call over the newest twin demo run's real site state ──
DO $v1$
DECLARE
  v_run uuid; v_clock timestamptz; v_cap numeric; v_allow numeric; v_bld numeric; v_sol numeric; v_off numeric; v_nocall numeric;
BEGIN
  SELECT sim_run_id, sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND run_by NOT IN ('cert_harness','benchmark') AND tick_count > 50
   ORDER BY started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE WARNING '0433 V1: no twin demo run to probe; skipped'; RETURN; END IF;
  BEGIN
    -- any call already in force on this run is expired INSIDE the probe, so the probe's own call is the binding one
    UPDATE public.ottoq_dr_calls SET expires_at = v_clock - interval '1 second'
     WHERE sim_run_id = v_run AND expires_at > v_clock;
    v_nocall := public.ottoq_ev_charge_allowance_kw(v_run, '11111111-1111-1111-1111-111111111111', v_clock);
    INSERT INTO public.ottoq_dr_calls (dr_call_id, depot_id, sim_run_id, issued_at, expires_at, duration_minutes,
                                       required_load_cap_kw, reason, program, call_status)
    VALUES (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', v_run, v_clock, v_clock + interval '120 minutes',
            120, 600, '0433_probe', 'TVA_VOLUNTARY', 'active');
    v_cap   := public.ottoq_effective_charge_cap_kw(v_run, '11111111-1111-1111-1111-111111111111', v_clock);
    v_allow := public.ottoq_ev_charge_allowance_kw(v_run, '11111111-1111-1111-1111-111111111111', v_clock);
    PERFORM public.ottoq_policy_set('run', v_run, 'dr_gate_credits_site_energy', 0, 'operator_0433_verify');
    v_off   := public.ottoq_ev_charge_allowance_kw(v_run, '11111111-1111-1111-1111-111111111111', v_clock);
    SELECT e.building_load_kw, e.solar_generation_kw INTO v_bld, v_sol FROM public.site_energy_snapshots e
     WHERE e.depot_id = '11111111-1111-1111-1111-111111111111' AND e.sim_run_id = v_run AND e.timestamp <= v_clock
     ORDER BY e.timestamp DESC, e.id LIMIT 1;
    RAISE EXCEPTION USING MESSAGE = '0433_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> '0433_probe_rollback' THEN RAISE; END IF;
  END;
  IF v_nocall IS DISTINCT FROM (SELECT service_max_kw FROM public.depots WHERE id = '11111111-1111-1111-1111-111111111111') THEN
    RAISE EXCEPTION '0433 V1: with no call the allowance is % -- the 0132 gate would have moved', v_nocall;
  END IF;
  IF v_cap <> 600 THEN RAISE EXCEPTION '0433 V1: the cap function no longer returns the call''s cap (%)', v_cap; END IF;
  IF v_off <> 600 THEN RAISE EXCEPTION '0433 V1: with the dial off the allowance is % not the cap', v_off; END IF;
  IF v_allow < 600 - COALESCE(v_bld, 0) + COALESCE(v_sol, 0) THEN
    RAISE EXCEPTION '0433 V1: the allowance % is below cap - building + solar (%), so the battery term went negative',
      v_allow, 600 - COALESCE(v_bld, 0) + COALESCE(v_sol, 0);
  END IF;
  RAISE NOTICE '0433 V1: cap 600, building %, solar %, allowance % (dial off: %)', v_bld, v_sol, v_allow, v_off;
END $v1$;

-- ── V2: THE GENERATOR -- a probed ignition stores baseline minus reduction, and the event says so ──
DO $v2$
DECLARE
  v_run uuid; v_probe timestamptz; v_seed bigint; v_call uuid; v_row record; v_evt jsonb; i int;
BEGIN
  -- the newest twin demo run that has a site snapshot inside the 14:00-19:59 CT ignition window
  SELECT e.sim_run_id, max(e.timestamp) INTO v_run, v_probe
    FROM public.site_energy_snapshots e JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
   WHERE e.depot_id = '11111111-1111-1111-1111-111111111111' AND r.run_by NOT IN ('cert_harness','benchmark')
     AND EXTRACT(HOUR FROM e.timestamp AT TIME ZONE 'America/Chicago') BETWEEN 14 AND 19
   GROUP BY e.sim_run_id, r.started_at ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RAISE WARNING '0433 V2: no twin demo run reached 14:00 CT; skipped'; RETURN; END IF;
  -- a seed whose ignition roll passes at 45 C with the per-tick reading, so the probe ignites deterministically
  -- (0.005 leaves room for a variability profile that scales the 45 C probability 0.186 down as far as 0.03x)
  FOR i IN 1..5000 LOOP
    IF twin.ottoq_sim_seeded_random(i::bigint, 'dr_ignite') < 0.005 THEN v_seed := i; EXIT; END IF;
  END LOOP;
  IF v_seed IS NULL THEN RAISE EXCEPTION '0433 V2: no probe seed found'; END IF;
  BEGIN
    -- nothing already in force at the depot may pre-empt the probe (the generator's own check is depot-wide)
    UPDATE public.ottoq_dr_calls SET expires_at = v_probe - interval '1 second'
     WHERE depot_id = '11111111-1111-1111-1111-111111111111' AND call_status = 'active' AND expires_at > v_probe;
    PERFORM public.ottoq_policy_set('run', v_run, 'dr_hazard_per_sim_time', 0, 'operator_0433_verify');
    v_call := twin.ottoq_sim_maybe_ignite_dr_call('11111111-1111-1111-1111-111111111111', v_run, v_probe, 45, v_seed);
    SELECT * INTO v_row FROM public.ottoq_dr_calls WHERE dr_call_id = v_call;
    SELECT e.payload INTO v_evt FROM public.ottoq_events e
     WHERE e.event_type = 'twin.dr_call_issued' AND e.payload->>'dr_call_id' = v_call::text LIMIT 1;
    RAISE EXCEPTION USING MESSAGE = '0433_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> '0433_probe_rollback' THEN RAISE; END IF;
  END;
  IF v_call IS NULL THEN RAISE EXCEPTION '0433 V2: the probe did not ignite'; END IF;
  IF v_evt IS NULL OR NOT (v_evt ? 'required_reduction_kw' AND v_evt ? 'baseline_source') THEN
    RAISE EXCEPTION '0433 V2: the ignition event lacks the reduction/baseline provenance: %', v_evt;
  END IF;
  IF (v_evt->>'baseline_source') <> 'none_pre_0433_reading_kept'
     AND abs(v_row.required_load_cap_kw - GREATEST(0, (v_evt->>'baseline_kw')::numeric - (v_evt->>'required_reduction_kw')::numeric)) > 0.2 THEN
    RAISE EXCEPTION '0433 V2: cap % is not baseline % minus reduction %', v_row.required_load_cap_kw,
      v_evt->>'baseline_kw', v_evt->>'required_reduction_kw';
  END IF;
  RAISE NOTICE '0433 V2: reduction %, baseline % (%), stored cap %', v_evt->>'required_reduction_kw',
    v_evt->>'baseline_kw', v_evt->>'baseline_source', v_row.required_load_cap_kw;
END $v2$;

-- ── V3: THE HAZARD -- unchanged at the cert cadence, scaled at the demo cadence ──
DO $v3$
DECLARE p30 numeric := 0.030; a numeric; b numeric;
BEGIN
  a := 1 - power(1 - p30, 30 / 30.0);
  b := 1 - power(1 - p30, 0.5 / 30.0);
  IF abs(a - p30) > 1e-12 THEN RAISE EXCEPTION '0433 V3: the cert-cadence probability moved (%)', a; END IF;
  IF NOT (b > 0 AND b < p30 / 50) THEN RAISE EXCEPTION '0433 V3: the demo-cadence probability % is not ~p/60', b; END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0433_a_demand_response_reduction_was_read_as_the_depots_whole_charging_ceiling_and_the_gate_forgot_the_battery',
  true,
  'G160. twin.ottoq_sim_maybe_ignite_dr_call sampled a 50-400 kW REDUCTION (its own comment) into '
  'ottoq_dr_calls.required_load_cap_kw, which every reader treats as an absolute grid cap, so a call to shed ~205 kW '
  'capped the depot at ~205 kW; ottoq_decide_tick''s 0132 gate refused charges against it counting no battery, solar or '
  'building load while ottoq_energy_orchestrate discharged the battery to the same number as a grid target; and the '
  'ignition probability was rolled per tick. Now: cap = prior-hour baseline grid import minus the reduction (draw '
  'unchanged); the gate reads ottoq_ev_charge_allowance_kw = cap - building + solar + sustainable BESS during a call '
  '(identical outside one); the probability is a per-30-sim-minute hazard elapsed over the tick''s real sim advance '
  '(identical at the cert cadence). Three dials, all default on. EN.004 deliberately not rewired. TRUE: a cert arm that '
  'ignites a call stores a different cap and admits different charges.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- ══ §6 AFTER APPLYING ═════════════════════════════════════════════════════════
--
-- forces_recert TRUE: let the recert runner resweep before quoting a determinism claim, and start the
-- validation run only after it is idle (a sweep starves the metronome, G141).
--
-- On the first armed run that reaches a hot afternoon (extend run_governor_max_sim_minutes to cover 14-19 CT):
--   rerun db/checks/0353 §2-§4 and compare: calls ignited, cap vs baseline, deferred_site_power_cap refusals,
--   committed EV kW during the call, grid import vs cap, BESS SoC and discharge.
--
-- Rollback, per piece: dr_cap_from_baseline / dr_gate_credits_site_energy / dr_hazard_per_sim_time -> 0
-- (global or per run), or restore from ottoq_schema_snapshots label '0433_pre'.
