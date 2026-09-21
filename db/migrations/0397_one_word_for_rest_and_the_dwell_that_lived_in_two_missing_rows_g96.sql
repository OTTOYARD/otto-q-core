-- migration-version: 20260921031935
-- migration-name:    one_word_for_rest_and_the_dwell_that_lived_in_two_missing_rows_g96
--
-- 0397  G96, STEPS 0 AND 1. **THE BESS GETS ONE WORD FOR REST.** Three places in this schema declare
--       what states a BESS may be in and **no two of them agree**; the commanded column's CHECK
--       cannot even express the resting state the matrix requires. And the dwell SM.006 promises is
--       removed from where it actually lived — **two rows that were never inserted into the
--       transition matrix** — not from a line of prose and not from a timer.
--
-- `forces_recert` **TRUE**, measured not assumed: `ottoq.ottoq_world_fingerprint` hashes
-- `COALESCE(b.current_state,'-')` in its BESS section, so the word this column carries is part of the
-- world fingerprint.
--
-- **AND A CORRECTION TO MY OWN REASONING FOR LANDING IT NOW, because it was wrong by five columns.**
-- `db/checks/0298` §1b argued this was a free window: all 9 canon columns were already below floor
-- from `0396`, so a further TRUE "costs nothing extra." That was true when written and **false by the
-- time this applied.** The recert sweep drains concurrently — it had cleared 5 of the 9 while this
-- migration was being written, and applying it put `awaiting_recert` straight back to **9**. So this
-- cost five re-certifications, not zero. **The correct rule: batching `forces_recert` changes is free
-- only if they land TOGETHER, before the sweep starts clearing columns — not merely "while the floor
-- is broken."** A window that is draining is not a window.
--
-- ══ THE THREE DISAGREEING DECLARATIONS ═════════════════════════════════════
--
--   `ottoq_bess_units_current_state_check`  (CHECK on the COMMANDED column)
--       idle, charging, discharging, maintenance, fault, offline
--   `bess_status`                           (enum typing `bess_snapshots.status`)
--       online, offline, charging, discharging, standby, fault
--   `ottoq_state_transitions`, entity_kind='bess'   (the matrix SM.006 evaluates against)
--       charging, discharging, fault, offline, online, standby
--
-- Their intersection is `charging, discharging, fault, offline`. **The CHECK alone carries `idle` and
-- `maintenance`; the enum and the matrix alone carry `standby` and `online`.** So the commanded column
-- **cannot hold `standby` at all** and the matrix **cannot represent `idle`** — the two ends are
-- mutually exclusive on the resting state, by construction, and have been since 2026-07-10.
--
-- `twin.ottoq_sim_bess_step` writes both ends from one value in one statement pair:
--
--     UPDATE ottoq_bess_units SET current_state = CASE ... ELSE 'idle' END,
--            -- the code's own comment: "'idle' is the unit-level vocabulary"
--     INSERT INTO bess_snapshots (... status) VALUES (... CASE ... ELSE 'standby' END::bess_status);
--
-- **THE TRAP THIS SET FOR G96.** A `bess_state_change` probe naturally reads the commanded column, and
-- passing `idle` refuses every transition into or out of rest, because no matrix row mentions it. A
-- `critical`/`block` rule wired that way takes the BESS offline on the first tick. Not the 14.4% of
-- direct flips `0285` measured — nearly all transitions.
--
-- ══ THE CENSUS, AND THE TWO SITES MY FIRST PASS MISSED ═════════════════════
--
-- `db/checks/0298` §2 claimed four sites and that the column was "plain `text` with no CHECK". **Both
-- claims were wrong, and the method is why.** I censused `pg_proc.prosrc`, so I found only what a
-- function body contains. The real list is:
--
--   1. `twin.ottoq_sim_bess_step`                  writer — the CASE above
--   2. `public.ottoq_tick_invariance_reset_fleet`  writer — fixture reset
--   3. `twin.ottoq_grid_fixture_create`            writer — fixture default
--   4. `public.ottoq_trigger_emergency_cascade`    **both** — sets `discharging` WHERE `idle`, and `offline`
--   5. **the column DEFAULT, `'idle'::text`**      — not in any `prosrc`, so the census could not see it
--   6. **`ottoq_bess_units_current_state_check`**  — a CHECK that permits `idle` and forbids `standby`
--
-- Same shape as G99: a `prosrc` match is evidence about a function body and nothing else. It cannot
-- see a DEFAULT, a constraint, a trigger or a view. **And it produced a false positive too** —
-- `'maintenance'` appears in `ottoq_tick_invariance_reset_fleet`, which is why I had to check the
-- context: that line reads `WHERE depot_id = ... AND status <> 'maintenance'` and is about
-- **`stalls.status`**, a different column. **Nothing writes `maintenance` to the BESS state**, so
-- dropping it from the vocabulary costs nothing.
--
-- Verified by the same census: the only values any code writes to this column are **`charging`,
-- `discharging`, `idle` and `offline`** — and with `idle` renamed, that set is a strict subset of
-- `bess_status`'s six labels. So the enum's vocabulary is sufficient, and it is the one the matrix
-- already uses.
--
-- ══ WHAT THIS DOES ═════════════════════════════════════════════════════════
--
-- STEP 0 — one word for rest. The CHECK is replaced with the enum's six labels, the DEFAULT becomes
-- `standby`, the three live rows are rewritten, and all three writers emit `standby`. **The reader in
-- `ottoq_trigger_emergency_cascade` is made TOLERANT of both and is the only place that is** — rows
-- written across the engine's whole life before today say `idle`, and narrowing that predicate to
-- `standby` alone would silently stop matching them.
--
-- STEP 1 — drop the dwell, which means INSERTING TWO ROWS and correcting a declaration. SM.006 v1 is
-- archived, v2 is active with the parenthetical gone and its rationale replaced. The old rationale
-- asserted a direct flip is *"physically impossible for the inverter/contactor and would damage the
-- unit"* — the strongest claim in the declaration and the one with no source. `0295` searched it:
-- IEEE 1547-2018 sets a 30-second CEILING on completing a mode transition and imposes no minimum
-- dwell, while grid-support literature describes sub-second standby-to-full-power and charge/discharge
-- reversal within seconds. NREL fy20osti/75436, IREC on 1547.1-2020, Sandia's 1547 introduction — all
-- secondary institutional summaries, labelled as such because the standard is paywalled.
--
-- **NOT DONE HERE, and each for a stated reason:**
--   - **Typing the column to `bess_status`** is the right end state — one declaration instead of two
--     hand-maintained lists — but it **breaks `ottoq_world_fingerprint`**, which does
--     `COALESCE(b.current_state,'-')`: `COALESCE(bess_status, text)` has no common type. That edit
--     touches the certification spine and must not ride along with a vocabulary change. Instead,
--     `ottoq_assert_bess_state_vocabulary` below compares the CHECK's list to the enum's labels, so
--     the two lists diverging again is **loud** rather than silent. Tracked.
--   - **STEP 2, wiring the probe at `bess_state_change`**, waits for its own file: a `critical`/`block`
--     gate must not depend on a vocabulary change that has not yet survived a run. `0294` §2 is the
--     record of me moving two things at once and losing the answer.

BEGIN;

-- ─── STEP 0: the schema first, because the CHECK forbids the value we are about to write ───
ALTER TABLE public.ottoq_bess_units
  DROP CONSTRAINT IF EXISTS ottoq_bess_units_current_state_check;

ALTER TABLE public.ottoq_bess_units
  ALTER COLUMN current_state SET DEFAULT 'standby'::text;

UPDATE public.ottoq_bess_units
   SET current_state = 'standby'
 WHERE current_state = 'idle';

-- The new CHECK is the `bess_status` labels, verbatim and in enum order. `idle` and `maintenance` are
-- gone: nothing writes either (the one `'maintenance'` in the codebase is about `stalls.status`).
-- `online` is admitted although nothing writes it yet, because the matrix has four transitions
-- involving it and a state the matrix can reach must be a state the column can hold.
ALTER TABLE public.ottoq_bess_units
  ADD CONSTRAINT ottoq_bess_units_current_state_check
  CHECK (current_state = ANY (ARRAY['online','offline','charging','discharging','standby','fault']));

CREATE OR REPLACE FUNCTION twin.ottoq_sim_bess_step(p_bess_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone, p_tick_minutes numeric, p_target_power_kw numeric, p_ambient_temp_c numeric DEFAULT NULL::numeric, p_dispatch_reason text DEFAULT 'manual'::text)
 RETURNS TABLE(out_actual_power_kw numeric, out_soc_pct_new numeric, out_temp_c_new numeric, out_soh_pct_new numeric, out_thermal_derated boolean, out_soc_limited boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v              ottoq_bess_units%ROWTYPE;
  v_seed         BIGINT;
  v_max_kw       NUMERIC;
  v_actual_kw    NUMERIC;
  v_kwh_delta    NUMERIC;
  v_one_way_eff  NUMERIC;
  v_thermal_derated BOOLEAN := FALSE;
  v_soc_limited     BOOLEAN := FALSE;
  v_new_soc_kwh  NUMERIC;
  v_new_soc_pct  NUMERIC;
  v_aux_load     NUMERIC;
  v_aux_noise    NUMERIC;
  v_new_temp     NUMERIC;
  v_target_temp  NUMERIC;
  v_thermal_lag  NUMERIC := 0.18;            -- per tick (~5 min tau time)
  v_kwh_through  NUMERIC;
  v_delta_soh    NUMERIC;
  v_ambient      NUMERIC;
  v_thermal_noise NUMERIC;
  v_bms_margin   NUMERIC;
BEGIN
  SELECT * INTO v FROM ottoq_bess_units WHERE bess_id = p_bess_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'bess % not found', p_bess_id;
  END IF;

  v_seed   := abs(hashtextextended(p_bess_id::text || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now), 23));
  v_ambient := COALESCE(p_ambient_temp_c, v.current_temperature_c, 22);
  v_one_way_eff := SQRT(COALESCE(v.roundtrip_efficiency_pct, 0.96));   -- per-direction

  -- BMS safety margin: 95-100% of theoretical max (jittered)
  v_bms_margin := 0.95 + ottoq_sim_seeded_random(v_seed, 'bms') * 0.05;

  IF p_target_power_kw > 0 THEN
    v_max_kw    := ottoq_sim_bess_compute_max_power_kw(p_bess_id, 'charge', v.current_temperature_c) * v_bms_margin;
    v_actual_kw := LEAST(p_target_power_kw, v_max_kw);
    IF v.current_temperature_c > 45 OR v.current_temperature_c < 5 THEN
      v_thermal_derated := TRUE;
    END IF;
    IF v.current_soc_pct >= v.soc_max_ceiling_pct - 0.05 THEN
      v_actual_kw    := 0;
      v_soc_limited  := TRUE;
    END IF;
  ELSIF p_target_power_kw < 0 THEN
    v_max_kw    := ottoq_sim_bess_compute_max_power_kw(p_bess_id, 'discharge', v.current_temperature_c) * v_bms_margin;
    v_actual_kw := -LEAST(ABS(p_target_power_kw), v_max_kw);
    IF v.current_temperature_c > 45 OR v.current_temperature_c < 5 THEN
      v_thermal_derated := TRUE;
    END IF;
    IF v.current_soc_pct <= v.soc_min_floor_pct + 0.05 THEN
      v_actual_kw    := 0;
      v_soc_limited  := TRUE;
    END IF;
  ELSE
    v_actual_kw := 0;
  END IF;

  -- Apply round-trip efficiency
  -- Charging: kWh stored = power_in × eff
  -- Discharging: kWh removed from pack = |power_out| / eff (need to pull more from pack to deliver)
  v_kwh_delta := CASE
    WHEN v_actual_kw > 0 THEN v_actual_kw * (p_tick_minutes / 60.0) * v_one_way_eff
    WHEN v_actual_kw < 0 THEN v_actual_kw * (p_tick_minutes / 60.0) / v_one_way_eff
    ELSE 0 END;

  -- Auxiliary load (BMS + HVAC + comms) — always pulls from pack
  v_aux_noise  := 0.85 + ottoq_sim_seeded_random(v_seed, 'aux') * 0.30;
  v_aux_load   := v.auxiliary_load_kw * v_aux_noise;
  v_kwh_delta  := v_kwh_delta - (v_aux_load * (p_tick_minutes / 60.0));

  v_new_soc_kwh := v.current_soc_kwh + v_kwh_delta;
  v_new_soc_kwh := GREATEST(0, LEAST(v.capacity_kwh, v_new_soc_kwh));
  v_new_soc_pct := v_new_soc_kwh / v.capacity_kwh * 100.0;

  -- Thermal model: heat from |P| × (1 - one_way_eff)
  v_target_temp := v_ambient + 3.0 + (ABS(v_actual_kw) / v.max_charge_kw) * 12.0;
  v_thermal_noise := (ottoq_sim_seeded_random(v_seed, 'noise') - 0.5) * 3.0;
  v_new_temp := v.current_temperature_c
              + (v_target_temp - v.current_temperature_c) * v_thermal_lag
              + v_thermal_noise;

  -- Throughput in kWh (for SOH calc)
  v_kwh_through := ABS(v_actual_kw) * (p_tick_minutes / 60.0);
  v_delta_soh := ottoq_sim_bess_apply_degradation(p_bess_id, p_tick_minutes, v_kwh_through, v_seed);

  -- Persist unit state
  UPDATE ottoq_bess_units
     SET current_soc_kwh           = ROUND(v_new_soc_kwh::numeric, 2),
         current_soc_pct           = ROUND(v_new_soc_pct::numeric, 2),
         current_temperature_c     = ROUND(v_new_temp::numeric, 2),
         current_power_kw          = ROUND(v_actual_kw::numeric, 2),
         current_state             = CASE
                                       WHEN v_actual_kw > 0  THEN 'charging'
                                       WHEN v_actual_kw < 0  THEN 'discharging'
                                       --: 0397 / G96. WAS 'idle'. The comment this replaces said
                                      --: "'idle' is the unit-level vocabulary" and that was the
                                      --: whole defect: the INSERT twelve lines below writes
                                      --: 'standby' from this same v_actual_kw, and 'standby' is
                                      --: what the bess_status enum and the bess rows of
                                      --: ottoq_state_transitions both use. 'idle' appeared in no
                                      --: matrix row, so a bess_state_change probe reading this
                                      --: column would have refused every transition into or out
                                      --: of rest -- a critical/block rule taking the BESS offline
                                      --: on the first tick. One state, one word. db/checks/0298.
                                      ELSE 'standby' END,
         current_state_updated_at  = p_sim_clock_now,
         last_heartbeat_at         = p_sim_clock_now,
         updated_at                = NOW()
   WHERE bess_id = p_bess_id;

  -- Snapshot to time-series
  INSERT INTO bess_snapshots (
    id, depot_id, system_id, timestamp, soc_percent,
    capacity_kwh, usable_capacity_kwh, current_output_kw,
    max_discharge_kw, max_charge_kw,
    grid_import_kw, grid_export_kw,
    temperature_c, health_percent, cycle_count, status
  ) VALUES (
    gen_random_uuid(), v.depot_id, v.bess_id, p_sim_clock_now, ROUND(v_new_soc_pct::numeric, 2),
    v.capacity_kwh,
    v.capacity_kwh * (v.soc_max_ceiling_pct - v.soc_min_floor_pct) / 100,
    ROUND(v_actual_kw::numeric, 2),
    v.max_discharge_kw, v.max_charge_kw,
    0, 0,                                                   -- grid linkage in A.5.4
    ROUND(v_new_temp::numeric, 2),
    ROUND(LEAST(100, v.current_soh_pct + v_delta_soh)::numeric, 3),
    ROUND((v.current_cycle_count + (v_kwh_through / (2 * v.capacity_kwh)))::numeric, 4),
    (CASE WHEN v_actual_kw > 0 THEN 'charging'
          WHEN v_actual_kw < 0 THEN 'discharging'
          ELSE 'standby' END)::bess_status
  );

  -- Emit events for noteworthy conditions
  IF v_thermal_derated THEN
    PERFORM ottoq_record_event(
      p_actor_type    := 'bess_controller',
      p_actor_id      := v.bess_identifier,
      p_event_type    := 'twin.bess_thermal_derate',
      p_entity_type   := 'depot',
      p_entity_id     := v.depot_id,
      p_payload       := jsonb_build_object(
        'temp_c', v.current_temperature_c,
        'requested_kw', p_target_power_kw,
        'actual_kw', v_actual_kw),
      p_severity      := 'warning',
      p_ingest_source := 'twin',
      p_data_source   := 'twin',
      p_sim_run_id    := p_sim_run_id);
  END IF;

  IF v_soc_limited THEN
    PERFORM ottoq_record_event(
      p_actor_type    := 'bess_controller',
      p_actor_id      := v.bess_identifier,
      p_event_type    := 'twin.bess_soc_limit',
      p_entity_type   := 'depot',
      p_entity_id     := v.depot_id,
      p_payload       := jsonb_build_object(
        'soc_pct', v.current_soc_pct,
        'direction', CASE WHEN p_target_power_kw > 0 THEN 'charge' ELSE 'discharge' END),
      p_severity      := 'warning',
      p_ingest_source := 'twin',
      p_data_source   := 'twin',
      p_sim_run_id    := p_sim_run_id);
  END IF;

  PERFORM ottoq_record_event(
    p_actor_type    := 'bess_controller',
    p_actor_id      := v.bess_identifier,
    p_event_type    := 'twin.bess_dispatch',
    p_entity_type   := 'depot',
    p_entity_id     := v.depot_id,
    p_payload       := jsonb_build_object(
      'target_kw',      p_target_power_kw,
      'actual_kw',      v_actual_kw,
      'soc_pct_after',  ROUND(v_new_soc_pct::numeric, 2),
      'soh_pct_after',  ROUND(LEAST(100, v.current_soh_pct + v_delta_soh)::numeric, 3),
      'temp_c_after',   ROUND(v_new_temp::numeric, 2),
      'reason',         p_dispatch_reason),
    p_severity      := 'info',
    p_ingest_source := 'twin',
    p_data_source   := 'twin',
    p_sim_run_id    := p_sim_run_id);

  out_actual_power_kw := ROUND(v_actual_kw::numeric, 2);
  out_soc_pct_new     := ROUND(v_new_soc_pct::numeric, 2);
  out_temp_c_new      := ROUND(v_new_temp::numeric, 2);
  out_soh_pct_new     := ROUND(LEAST(100, v.current_soh_pct + v_delta_soh)::numeric, 3);
  out_thermal_derated := v_thermal_derated;
  out_soc_limited     := v_soc_limited;
  RETURN NEXT;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.ottoq_tick_invariance_reset_fleet(p_depot_id uuid, p_seed bigint, p_as_of timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_n int;
BEGIN
  -- deterministic, seed-derived SoC in a deployable band; identical for every arm
  UPDATE vehicles v
     SET current_soc   = ROUND((85 + ottoq_sim_seeded_random(p_seed, 'inv:soc:' || v.id::text) * 14)::numeric, 1),
         current_state = 'offline'::vehicle_state,
         current_stall_id = NULL,
         -- 0243 (probe db/checks/0160): a vehicle left mid-tether by whatever
         -- touched the depot last was inherited by arm A and never by arm B,
         -- and its deadline came due mid-run. The reset owns these four.
         robotic_tether_phase = NULL, robotic_tether_until = NULL,
         robotic_tether_stall_id = NULL, robotic_tether_direction = NULL,
         -- 0245 (probe db/checks/0160 s11): written inside a tick by
         -- twin.ottoq_sim_start_charge_session and cleared by nothing. A no-op
         -- against today's world (all 116 already equal home); a guarantee against
         -- a vehicle left pointing at another depot by a run on the other lane.
         current_depot_id = p_depot_id,
         last_state_change = COALESCE(p_as_of, now()),
         current_soc_source = 'estimated',
         -- 0096: NOT NULL column; canonical means a CONSTANT (seeded fleet rests at 90).
         target_soc = 90,
         -- 0095: WHITELIST, not blacklist. Keep durable identity + scenario-drawn
         -- condition; drop every run-written key, present or future, automatically.
         -- Measured leaks that ended the blacklist: last_balance_charge_at,
         -- deploy_gate, arm_fault_*, flagged_issue_type (8-tick probe).
         config = (SELECT COALESCE(jsonb_object_agg(e.key, e.value), '{}'::jsonb)
                     FROM jsonb_each(COALESCE(v.config,'{}'::jsonb)) e
                    WHERE e.key IN ('oem','inlet_type','vehicle_class_code',
                          'seed_idx','seed_version','simulated','data_source',
                          'lifetime_miles','battery_chemistry',  -- 0120: last_calibration_at is run-mutated (wear_mark_serviced) and read by nothing; a whitelist keeps only STILL parts
                          'battery_onboarded_at','balance_interval_days',
                          'nightly_soc_target','soil_rate','wash_cadence_cycles',
                          'wash_group','pm_interval_km','calib_interval_h',
                          'battery_soh_pct','consumption_scalar','charge_curve_scalar',
                          'service_speed_scalar','scenario_interval_scale',
                          'condition_drawn_run'))
                  || jsonb_build_object('cycles_since_wash', 1,
                       -- 0121: the odometer is DEALT from the seed, not inherited from the
                       -- lineage (it accrues in-run via the arrival-payload round-trip).
                       'lifetime_miles', round(500 + 79000 * power(twin.ottoq_sim_seeded_random(p_seed, 'veh_lifemiles:' || v.id::text), 2)))
   WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous';
  GET DIAGNOSTICS v_n = ROW_COUNT;

  UPDATE stalls SET current_vehicle_id = NULL, reserved_by = NULL,
                    reserved_at = NULL,
                    reservation_expires_at = NULL, status = 'available'
   WHERE depot_id = p_depot_id AND status <> 'maintenance';

  -- 0093: sim-injected charger faults survive the teardown reconcile; a seeded
  -- world reset canonicalizes them (measured: 4 chargers stuck non-Available).
  UPDATE public.ottoq_ocpp_chargers c
     SET station_state = 'Available', last_fault_code = NULL,
         -- 0194: the fingerprint hashes both; the decide path gates on heartbeat. The reset owns them.
         last_fault_at = NULL, last_heartbeat_at = COALESCE(p_as_of, now()), /* 0194 */
         -- 0094: the column is NOT NULL; canonical means a CONSTANT, not an absence.
         station_state_changed_at = 'epoch'::timestamptz
   WHERE c.charger_id IN (SELECT s.ocpp_charger_id FROM public.stalls s
                           WHERE s.depot_id = p_depot_id AND s.ocpp_charger_id IS NOT NULL)
     AND (c.station_state IS DISTINCT FROM 'Available'
          OR c.last_fault_code IS NOT NULL
          OR c.station_state_changed_at IS DISTINCT FROM 'epoch'::timestamptz
          OR c.last_fault_at IS NOT NULL
          OR c.last_heartbeat_at IS DISTINCT FROM COALESCE(p_as_of, now()) /* 0194 */);
  -- 0196: the chargers no stall points at carry the last run's heartbeat and fault
  -- stamps too, and the fingerprint hashes every charger of the depot.
  UPDATE public.ottoq_ocpp_chargers c
     SET last_fault_at = NULL, last_heartbeat_at = COALESCE(p_as_of, now()) /* 0196 */
   WHERE c.depot_id = p_depot_id
     AND c.charger_id NOT IN (SELECT s.ocpp_charger_id FROM public.stalls s
                              WHERE s.depot_id = p_depot_id AND s.ocpp_charger_id IS NOT NULL)
     AND (c.last_fault_at IS NOT NULL
          OR c.last_heartbeat_at IS DISTINCT FROM COALESCE(p_as_of, now()));
  -- 0133: THE BESS IS START-RELEVANT WORLD. Probe: db/checks/0051 -- two byte-identical
  -- arms produced peak_site_kw 524.9 vs 416.3 because the battery carried across runs.
  -- Seed-derived inside the unit's OWN configured band, mirroring the vehicle SoC line
  -- above rather than inventing a constant. Also brings any unit sitting above its own
  -- ceiling back into band (the benchmark unit was at 97.58% against a 95% ceiling).
  UPDATE public.ottoq_bess_units b
     SET current_power_kw = 0,
         --: 0397 / G96. WAS 'idle'; see db/checks/0298. The fixture reset must leave the
         --: BESS in a state the transition matrix recognises, or the first commanded
         --: change out of it is unrepresentable.
         current_state    = 'standby',
         current_temperature_c   = 25.0,   /* 0135 */
         current_soh_pct         = 100.0,  /* 0135 */
         current_cycle_count     = 0,      /* 0135 */
         lifetime_kwh_charged    = 0,      /* 0135 */
         lifetime_kwh_discharged = 0,      /* 0135 */
         current_soc_pct  = ROUND((COALESCE(b.soc_min_floor_pct,10)
              + twin.ottoq_sim_seeded_random(p_seed, 'inv:bess:' || b.bess_id::text)
                * (COALESCE(b.soc_max_ceiling_pct,95) - COALESCE(b.soc_min_floor_pct,10)))::numeric, 2),
         current_soc_kwh  = ROUND((COALESCE(b.capacity_kwh,0) *
              (COALESCE(b.soc_min_floor_pct,10)
               + twin.ottoq_sim_seeded_random(p_seed, 'inv:bess:' || b.bess_id::text)
                 * (COALESCE(b.soc_max_ceiling_pct,95) - COALESCE(b.soc_min_floor_pct,10))) / 100.0)::numeric, 3)
   WHERE b.depot_id = p_depot_id;  /* 0133 */


  /* 0162: A DECLARED FAULT IS PART OF THE SEEDED WORLD. Everything above
     canonicalizes residue away (0093). A fault the fixture DECLARES is not
     residue - it is the world we meant to test - so it is re-applied here,
     after canonicalization, identically for every arm. Without this a
     charger set Faulted before a pair is healed before tick one and the
     run silently tests a healthy site. Inert unless depots.config names
     an injected_fault. */
  DECLARE v_fault jsonb; BEGIN
    SELECT d.config->'injected_fault' INTO v_fault FROM public.depots d WHERE d.id = p_depot_id;
    IF v_fault IS NOT NULL THEN
      IF v_fault->>'kind' = 'charger_offline' THEN
        UPDATE public.ottoq_ocpp_chargers c
           SET station_state = 'Faulted', last_fault_code = 'fault.injected_offline',
               last_fault_payload = jsonb_build_object('repair_minutes',
                 COALESCE((v_fault->>'repair_minutes')::numeric, 100000)),
               station_state_changed_at = COALESCE(p_as_of, 'epoch'::timestamptz)
         WHERE c.charger_id = (SELECT s.ocpp_charger_id FROM public.stalls s
                                WHERE s.id = (v_fault->>'stall_id')::uuid);
      ELSIF v_fault->>'kind' = 'point_blocked' THEN
        UPDATE public.stalls SET status = 'blocked'
         WHERE id = (v_fault->>'stall_id')::uuid;
      END IF;
    END IF;
  END;

  RETURN v_n;
END; $function$
;

CREATE OR REPLACE FUNCTION twin.ottoq_grid_fixture_create(p_slug text DEFAULT 'grid-fixture'::text, p_n_vehicles integer DEFAULT 4, p_dcfc integer DEFAULT 2, p_l2 integer DEFAULT 2, p_wash integer DEFAULT 1, p_service integer DEFAULT 1, p_staging integer DEFAULT 4, p_source_depot uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid, p_scenario_code text DEFAULT 'grid_smoke'::text, p_scenario_seed bigint DEFAULT 424242, p_service_max_kw numeric DEFAULT 600)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_depot      uuid := md5('ottoq_grid_fixture:'||p_slug)::uuid;
  v_src        public.depots%ROWTYPE;
  r            record;
  i            int := 0;
  v_code       text;
  v_stall_id   uuid;
  v_charger_id uuid;
  v_canopy     text := p_slug||'_canopy_1';
  v_n_stalls   int; v_n_veh int; v_n_chg int;
BEGIN
  IF EXISTS (SELECT 1 FROM public.depots WHERE id = v_depot) THEN
    RAISE NOTICE 'grid fixture % already exists as %', p_slug, v_depot;
    RETURN v_depot;
  END IF;
  SELECT * INTO v_src FROM public.depots WHERE id = p_source_depot;
  IF NOT FOUND THEN RAISE EXCEPTION 'grid fixture: source depot % not found', p_source_depot; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_scenarios WHERE scenario_code = p_scenario_code) THEN
    RAISE EXCEPTION 'grid fixture: scenario_code % already exists', p_scenario_code;
  END IF;

  INSERT INTO public.depots
  SELECT (jsonb_populate_record(NULL::public.depots,
           (to_jsonb(v_src) - 'geofence' - 'origin_point')
           || jsonb_build_object('id', v_depot,
                                 'name', 'OTTOYARD Grid Fixture ('||p_slug||')',
                                 'slug', p_slug,
                                 'address', 'grid fixture - not a place',
                                 'service_max_kw', p_service_max_kw,
                                 'dcfc_max_concurrent_kw', p_service_max_kw,
                                 'config', COALESCE(v_src.config,'{}'::jsonb) || jsonb_build_object('demand_limit_kw', p_service_max_kw),
                                 'created_at', now(), 'updated_at', now()))).*;
  UPDATE public.depots SET geofence = v_src.geofence, origin_point = v_src.origin_point WHERE id = v_depot;

  INSERT INTO public.service_definitions
  SELECT (jsonb_populate_record(NULL::public.service_definitions,
           to_jsonb(s) || jsonb_build_object('id', md5('grid:'||p_slug||':svc:'||s.code)::uuid, 'depot_id', v_depot))).*
    FROM public.service_definitions s WHERE s.depot_id = p_source_depot;

  INSERT INTO public.ottoq_tariff_windows
  SELECT (jsonb_populate_record(NULL::public.ottoq_tariff_windows,
           to_jsonb(t) || jsonb_build_object('tariff_id', md5('grid:'||p_slug||':tw:'||t.tariff_id)::uuid, 'depot_id', v_depot))).*
    FROM public.ottoq_tariff_windows t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.ottoq_depot_tariffs
  SELECT (jsonb_populate_record(NULL::public.ottoq_depot_tariffs,
           to_jsonb(t) || jsonb_build_object('tariff_row_id', md5('grid:'||p_slug||':dt:'||t.tariff_row_id)::uuid, 'depot_id', v_depot))).*
    FROM public.ottoq_depot_tariffs t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.ottoq_depot_staffing
  SELECT (jsonb_populate_record(NULL::public.ottoq_depot_staffing,
           to_jsonb(t) || jsonb_build_object('depot_id', v_depot))).*
    FROM public.ottoq_depot_staffing t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.engine_config
  SELECT (jsonb_populate_record(NULL::public.engine_config,
           to_jsonb(t) || jsonb_build_object('id', md5('grid:'||p_slug||':engine_config')::uuid, 'depot_id', v_depot))).*
    FROM public.engine_config t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.tariff_schedules
  SELECT (jsonb_populate_record(NULL::public.tariff_schedules,
           to_jsonb(t) || jsonb_build_object('id', md5('grid:'||p_slug||':ts:'||t.id)::uuid, 'depot_id', v_depot))).*
    FROM public.tariff_schedules t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.action_guardrails
  SELECT (jsonb_populate_record(NULL::public.action_guardrails,
           to_jsonb(t) || jsonb_build_object('id', md5('grid:'||p_slug||':ag:'||t.id)::uuid, 'depot_id', v_depot))).*
    FROM public.action_guardrails t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.waves
  SELECT (jsonb_populate_record(NULL::public.waves,
           to_jsonb(t) || jsonb_build_object('id', md5('grid:'||p_slug||':wave:'||t.id)::uuid, 'depot_id', v_depot))).*
    FROM public.waves t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.ottoq_site_structures
  SELECT (jsonb_populate_record(NULL::public.ottoq_site_structures,
           to_jsonb(t) || jsonb_build_object('structure_id', md5('grid:'||p_slug||':struct:'||t.structure_code)::uuid, 'depot_id', v_depot))).*
    FROM public.ottoq_site_structures t WHERE t.depot_id = p_source_depot;

  INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
  SELECT 'depot', v_depot, p.param_key, p.param_value, 'grid_fixture:'||p_slug
    FROM public.ottoq_policy_params p WHERE p.scope_type = 'depot' AND p.scope_id = p_source_depot;

  INSERT INTO public.ottoq_bess_units
  SELECT (jsonb_populate_record(NULL::public.ottoq_bess_units,
           to_jsonb(b) || jsonb_build_object('bess_id', md5('grid:'||p_slug||':bess:1')::uuid, 'depot_id', v_depot,
             'bess_identifier', upper(p_slug)||'-BESS-01',
             'capacity_kwh', round(b.capacity_kwh/10.0, 0), 'max_charge_kw', round(b.max_charge_kw/10.0, 0),
             'max_discharge_kw', round(b.max_discharge_kw/10.0, 0),
             --: 0397 / G96. WAS 'idle'; see db/checks/0298. One word for rest.
             'current_power_kw', 0, 'current_state', 'standby', 'current_soc_pct', 50,
             'current_soc_kwh', round(b.capacity_kwh/20.0, 3), 'current_cycle_count', 0,
             'lifetime_kwh_charged', 0, 'lifetime_kwh_discharged', 0,
             'last_fault_code', NULL, 'last_fault_at', NULL, 'last_fault_payload', NULL,
             'created_at', now(), 'updated_at', now()))).*
    FROM public.ottoq_bess_units b WHERE b.depot_id = p_source_depot ORDER BY b.bess_identifier LIMIT 1;

  INSERT INTO public.ottoq_canopy_state (canopy_code, depot_id, structure_id, nameplate_dc_kw, nameplate_ac_kw,
                                         tilt_deg, azimuth_deg, current_soiling, last_rain_clean_at, last_updated_at)
  SELECT v_canopy, v_depot, NULL, 36, 30, c.tilt_deg, c.azimuth_deg, 0.85, c.last_rain_clean_at, now()
    FROM public.ottoq_canopy_state c WHERE c.depot_id = p_source_depot ORDER BY c.canopy_code LIMIT 1;

  FOR r IN
    SELECT s.*, row_number() OVER (PARTITION BY s.stall_type ORDER BY s.stall_code) AS rn
      FROM public.stalls s WHERE s.depot_id = p_source_depot
     ORDER BY s.stall_type, s.stall_code
  LOOP
    IF NOT ((r.stall_type::text = 'dcfc'        AND r.rn <= p_dcfc)
         OR (r.stall_type::text = 'l2'          AND r.rn <= p_l2)
         OR (r.stall_type::text = 'wash_bay'    AND r.rn <= p_wash)
         OR (r.stall_type::text = 'service_bay' AND r.rn <= p_service)
         OR (r.stall_type::text = 'staging'     AND r.rn <= p_staging)) THEN
      CONTINUE;
    END IF;
    v_code := upper(p_slug)||'-'||upper(r.stall_type::text)||'-'||lpad(r.rn::text, 2, '0');
    v_charger_id := NULL;
    IF r.ocpp_charger_id IS NOT NULL THEN
      v_charger_id := md5('grid:'||p_slug||':chg:'||v_code)::uuid;
      INSERT INTO public.ottoq_ocpp_chargers
      SELECT (jsonb_populate_record(NULL::public.ottoq_ocpp_chargers,
               to_jsonb(c) || jsonb_build_object('charger_id', v_charger_id, 'depot_id', v_depot,
                 'ocpp_identifier', v_code, 'serial_number', NULL,
                 'station_state', 'Available', 'station_state_changed_at', 'epoch',
                 'last_heartbeat_at', now(), 'last_fault_code', NULL, 'last_fault_at', NULL, 'last_fault_payload', NULL,
                 'created_at', now(), 'updated_at', now()))).*
        FROM public.ottoq_ocpp_chargers c WHERE c.charger_id = r.ocpp_charger_id;
    END IF;
    v_stall_id := md5('grid:'||p_slug||':stall:'||v_code)::uuid;
    INSERT INTO public.stalls
    SELECT (jsonb_populate_record(NULL::public.stalls,
             (to_jsonb(r) - 'rn' - 'absolute_point')
             || jsonb_build_object('id', v_stall_id, 'depot_id', v_depot, 'stall_code', v_code, 'display_name', v_code,
                  'ocpp_charger_id', v_charger_id, 'current_vehicle_id', NULL,
                  'reserved_by', NULL, 'reserved_at', NULL, 'reservation_expires_at', NULL, 'reserved_for_mission_id', NULL,
                  'status', 'available',
                  'canopy_code', CASE WHEN r.canopy_code IS NULL THEN NULL ELSE v_canopy END,
                  'created_at', now(), 'updated_at', now()))).*;
    UPDATE public.stalls SET absolute_point = r.absolute_point WHERE id = v_stall_id;
  END LOOP;

  FOR r IN
    SELECT v.* FROM public.vehicles v
     WHERE v.home_depot_id = p_source_depot AND v.category = 'autonomous'
     ORDER BY v.display_name LIMIT p_n_vehicles
  LOOP
    i := i + 1;
    INSERT INTO public.vehicles
    SELECT (jsonb_populate_record(NULL::public.vehicles,
             to_jsonb(r) || jsonb_build_object(
               'id', md5('grid:'||p_slug||':veh:'||i)::uuid,
               'vin', 'GRID'||upper(left(md5(p_slug),4))||lpad(i::text, 9, '0'),
               'display_name', upper(p_slug)||'-AV-'||lpad(i::text, 2, '0'),
               'license_plate', 'GRID-'||lpad(i::text, 3, '0'),
               'av_api_vehicle_id', 'grid-sim-'||left(md5(p_slug),4)||'-'||lpad(i::text, 2, '0'),
               'home_depot_id', v_depot, 'current_depot_id', v_depot, 'current_stall_id', NULL,
               'current_state', 'offline', 'owning_sim_run_id', NULL, 'retail_member_id', NULL,
               'robotic_tether_until', NULL, 'robotic_tether_stall_id', NULL,
               'robotic_tether_direction', NULL, 'robotic_tether_phase', NULL,
               'last_state_change', now(), 'created_at', now(), 'updated_at', now()))).*;
  END LOOP;

  INSERT INTO public.ottoq_scenarios
  SELECT (jsonb_populate_record(NULL::public.ottoq_scenarios,
           to_jsonb(sc) || jsonb_build_object(
             'scenario_id', md5('grid:'||p_slug||':scenario:'||p_scenario_code)::uuid,
             'scenario_code', p_scenario_code, 'category', 'regression',
             'title', 'Grid fixture smoke ('||p_slug||')',
             'description', 'Point-to-point conformance on the '||p_slug||' fixture: the normal_day shape on a tiny grid (0153).',
             'depot_id', v_depot, 'random_seed', p_scenario_seed,
             'introduced_in', '0153', 'created_at', now(), 'updated_at', now()))).*
    FROM public.ottoq_scenarios sc WHERE sc.scenario_code = 'normal_day';

  SELECT count(*) INTO v_n_stalls FROM public.stalls WHERE depot_id = v_depot;
  SELECT count(*) INTO v_n_veh    FROM public.vehicles WHERE home_depot_id = v_depot;
  SELECT count(*) INTO v_n_chg    FROM public.ottoq_ocpp_chargers WHERE depot_id = v_depot;
  IF v_n_stalls <> p_dcfc + p_l2 + p_wash + p_service + p_staging THEN
    RAISE EXCEPTION 'grid fixture: expected % stalls, made %', p_dcfc + p_l2 + p_wash + p_service + p_staging, v_n_stalls;
  END IF;
  IF v_n_veh <> p_n_vehicles THEN
    RAISE EXCEPTION 'grid fixture: expected % vehicles, made % (source has fewer autonomous vehicles?)', p_n_vehicles, v_n_veh;
  END IF;
  IF v_n_chg <> p_dcfc + p_l2 THEN
    RAISE EXCEPTION 'grid fixture: expected % chargers, made %', p_dcfc + p_l2, v_n_chg;
  END IF;
  RAISE NOTICE 'grid fixture % = % : % stalls (% chargers), % vehicles, scenario %',
               p_slug, v_depot, v_n_stalls, v_n_chg, v_n_veh, p_scenario_code;
  RETURN v_depot;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.ottoq_trigger_emergency_cascade(p_protocol_code text, p_depot_id uuid, p_triggered_by_actor_type text, p_triggered_by_actor_id text DEFAULT NULL::text, p_source_payload jsonb DEFAULT '{}'::jsonb, p_triggered_by_event_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_protocol         ottoq_emergency_protocols%ROWTYPE;
  v_invocation_id    UUID := gen_random_uuid();
  v_correlation      UUID := COALESCE(
                        NULLIF(current_setting('ottoq.correlation_id', TRUE), '')::UUID,
                        gen_random_uuid()
                      );
  v_event_id         UUID;
  v_action           JSONB;
  v_action_results   JSONB := '[]'::jsonb;
  v_action_status    TEXT;
  v_action_details   JSONB;
  v_outcome          TEXT := 'completed';
  v_affected_stalls  INTEGER := 0;
  v_affected_vehicles INTEGER := 0;
  v_affected_chargers INTEGER := 0;
BEGIN
  -- 1. Lookup protocol
  SELECT * INTO v_protocol
    FROM ottoq_emergency_protocols
   WHERE protocol_code = p_protocol_code AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OTTOQ_PROTOCOL_NOT_FOUND: %', p_protocol_code USING ERRCODE = 'P0001';
  END IF;

  -- 2. Emit "emergency.triggered" event FIRST (before any side effects)
  v_event_id := ottoq_record_event(
    p_actor_type        := p_triggered_by_actor_type,
    p_actor_id          := p_triggered_by_actor_id,
    p_event_type        := 'emergency.triggered',
    p_entity_type       := 'emergency_invocation',
    p_entity_id         := v_invocation_id,
    p_depot_id          := p_depot_id,
    p_payload           := jsonb_build_object(
                             'protocol_code', p_protocol_code,
                             'category', v_protocol.category,
                             'severity', v_protocol.severity,
                             'source', p_source_payload
                           ),
    p_severity          := v_protocol.severity,
    p_parent_event_id   := p_triggered_by_event_id,
    p_correlation_id    := v_correlation
  );

  -- 3. Insert invocation row
  INSERT INTO ottoq_emergency_invocations (
    invocation_id, protocol_code, triggered_at,
    triggered_by_actor_type, triggered_by_actor_id, triggered_by_event_id,
    source_payload, depot_id, affects_scope,
    outcome, linked_event_id, correlation_id
  ) VALUES (
    v_invocation_id, p_protocol_code, NOW(),
    p_triggered_by_actor_type, p_triggered_by_actor_id, p_triggered_by_event_id,
    p_source_payload, p_depot_id, v_protocol.affects_scope,
    'in_progress', v_event_id, v_correlation
  );

  -- 4. Execute cascade actions in order
  FOR v_action IN SELECT jsonb_array_elements(v_protocol.cascade_actions)
  LOOP
    BEGIN
      v_action_status := 'ok';
      v_action_details := '{}'::jsonb;

      CASE v_action ->> 'action'
        WHEN 'de_energize_all_chargers' THEN
          UPDATE ottoq_ocpp_chargers
             SET station_state = 'Unavailable',
                 station_state_changed_at = NOW()
           WHERE depot_id = p_depot_id;
          GET DIAGNOSTICS v_affected_chargers = ROW_COUNT;
          v_action_details := jsonb_build_object('chargers_de_energized', v_affected_chargers);

        WHEN 'sequester_all_vehicles' THEN
          -- Move all in-flow vehicles at this depot to emergency_staged
          BEGIN
            EXECUTE format('
              UPDATE vehicles SET current_state = ''emergency_staged''
               WHERE current_state IN (''queued'',''assigned'',''in_service'',''charging'',''washing'',''calibrating'',''staged_for_departure'')
                 AND id IN (SELECT current_vehicle_id FROM stalls WHERE depot_id = $1 AND current_vehicle_id IS NOT NULL)
            ') USING p_depot_id;
            GET DIAGNOSTICS v_affected_vehicles = ROW_COUNT;
          EXCEPTION WHEN OTHERS THEN
            v_affected_vehicles := 0;
          END;
          v_action_details := jsonb_build_object('vehicles_sequestered', v_affected_vehicles);

        WHEN 'lock_all_stalls' THEN
          BEGIN
            EXECUTE 'UPDATE stalls SET status = ''offline'' WHERE depot_id = $1 AND status <> ''offline'''
              USING p_depot_id;
            GET DIAGNOSTICS v_affected_stalls = ROW_COUNT;
          EXCEPTION WHEN OTHERS THEN
            v_affected_stalls := 0;
          END;
          v_action_details := jsonb_build_object('stalls_locked', v_affected_stalls);

        WHEN 'pause_arrivals' THEN
          -- Insert a grid_event-style marker; arrival logic checks for active
          -- 'arrival_pause' rows during admission.
          INSERT INTO ottoq_grid_events (
            depot_id, event_type, severity, effective_at, source, payload
          ) VALUES (
            p_depot_id, 'curtailment_request', 'safety_critical', NOW(),
            'emergency_cascade',
            jsonb_build_object('reason','arrival_pause_emergency',
                               'protocol_code', p_protocol_code,
                               'invocation_id', v_invocation_id)
          );
          v_action_details := jsonb_build_object('arrival_pause_set', TRUE);

        WHEN 'notify_actors' THEN
          -- Notification is downstream; we just emit an event other systems
          -- subscribe to. ottoq_event 'emergency.notify_actors' carries the list.
          PERFORM ottoq_record_event(
            p_actor_type     := 'ottoq_engine',
            p_event_type     := 'emergency.notify_actors',
            p_entity_type    := 'emergency_invocation',
            p_entity_id      := v_invocation_id,
            p_depot_id       := p_depot_id,
            p_payload        := jsonb_build_object(
                                  'protocol_code', p_protocol_code,
                                  'actors_to_notify', v_protocol.notify_actors,
                                  'webhooks', v_protocol.external_notify_webhooks
                                ),
            p_severity       := v_protocol.severity,
            p_parent_event_id := v_event_id,
            p_correlation_id := v_correlation
          );
          v_action_details := jsonb_build_object('notify_actors', v_protocol.notify_actors);

        WHEN 'engage_bess' THEN
          UPDATE ottoq_bess_units
             SET current_state = 'discharging'
           WHERE depot_id = p_depot_id
             --: 0397 / G96. DELIBERATELY TOLERANT, and the only place that is. Every WRITER
             --: now emits 'standby', and this migration rewrites the live rows -- but this is
             --: a READER, and rows written before 0397 across the engine's whole life say
             --: 'idle'. Narrowing it to 'standby' alone would silently stop matching any such
             --: row. The tolerance belongs here and nowhere else: a second writer of 'idle'
             --: would re-open the split this migration closes. db/checks/0298.
             AND current_state IN ('standby', 'idle')
             AND current_soc_pct > soc_min_floor_pct;
          GET DIAGNOSTICS v_action_details = ROW_COUNT;
          v_action_details := jsonb_build_object('bess_engaged_count', v_action_details);

        WHEN 'isolate_bess' THEN
          UPDATE ottoq_bess_units
             SET current_state = 'offline'
           WHERE depot_id = p_depot_id;
          v_action_details := jsonb_build_object('bess_isolated', TRUE);

        WHEN 'log_only' THEN
          -- Pure observation, no side effects
          v_action_details := jsonb_build_object('logged', TRUE);

        ELSE
          v_action_status := 'unknown_action';
          v_action_details := jsonb_build_object('unknown_action', v_action ->> 'action');
      END CASE;

    EXCEPTION WHEN OTHERS THEN
      v_action_status := 'failed';
      v_action_details := jsonb_build_object('error', SQLERRM, 'sqlstate', SQLSTATE);
      v_outcome := 'partial';
    END;

    v_action_results := v_action_results || jsonb_build_object(
      'action', v_action ->> 'action',
      'status', v_action_status,
      'details', v_action_details,
      'executed_at', NOW()
    );

    -- Per-action event for granular audit
    PERFORM ottoq_record_event(
      p_actor_type      := 'ottoq_engine',
      p_event_type      := 'emergency.action_executed',
      p_entity_type     := 'emergency_invocation',
      p_entity_id       := v_invocation_id,
      p_depot_id        := p_depot_id,
      p_payload         := jsonb_build_object(
                             'protocol_code', p_protocol_code,
                             'action', v_action ->> 'action',
                             'status', v_action_status,
                             'details', v_action_details
                           ),
      p_severity        := CASE WHEN v_action_status='ok' THEN 'info' ELSE 'critical' END,
      p_parent_event_id := v_event_id,
      p_correlation_id  := v_correlation
    );
  END LOOP;

  -- 5. Finalize invocation row
  UPDATE ottoq_emergency_invocations
     SET cascade_executed = v_action_results,
         outcome          = v_outcome
   WHERE invocation_id = v_invocation_id;

  -- 6. Emit completion event
  PERFORM ottoq_record_event(
    p_actor_type      := 'ottoq_engine',
    p_event_type      := 'emergency.cascade_complete',
    p_entity_type     := 'emergency_invocation',
    p_entity_id       := v_invocation_id,
    p_depot_id        := p_depot_id,
    p_payload         := jsonb_build_object(
                          'protocol_code', p_protocol_code,
                          'outcome', v_outcome,
                          'actions_executed', jsonb_array_length(v_action_results)
                        ),
    p_severity        := v_protocol.severity,
    p_parent_event_id := v_event_id,
    p_correlation_id  := v_correlation
  );

  RETURN v_invocation_id;
END;
$function$
;

-- ─── STEP 1a: the two rows the dwell actually lived in ───────────────────────
-- trigger_event / allowed_actor_types / required_conditions shaped on the standby->charging and
-- standby->discharging siblings, so these are indistinguishable in form from the rows that were
-- always there.
INSERT INTO public.ottoq_state_transitions
  (entity_kind, from_state, to_state, trigger_event, allowed_actor_types,
   required_conditions, description, introduced_in, status)
VALUES
  ('bess', 'charging', 'discharging', 'reverse_to_discharge',
   ARRAY['bess_controller','ottoq_engine'], ARRAY[]::text[],
   'reverse directly from charge to discharge; no standby dwell is required -- IEEE 1547-2018 sets a '
   '30-second ceiling on COMPLETING a mode transition and imposes no minimum dwell (0295/0397)',
   '20260921', 'active'),
  ('bess', 'discharging', 'charging', 'reverse_to_charge',
   ARRAY['bess_controller','ottoq_engine'], ARRAY[]::text[],
   'reverse directly from discharge to charge; no standby dwell is required -- see the sibling row',
   '20260921', 'active')
ON CONFLICT DO NOTHING;

-- ─── STEP 1b: SM.006 v1 archived, v2 active with the dwell gone ──────────────
UPDATE public.ottoq_rules
   SET status = 'archived', updated_at = now()
 WHERE rule_code = 'SM.006.bess_transition_validity' AND version = 1 AND status = 'active';

INSERT INTO public.ottoq_rules
  (rule_code, version, category, title, description, rationale, severity, enforcement,
   override_allowed, override_min_role, scope, evaluator_function, default_parameters,
   applies_to_actions, applies_to_entities, status, introduced_in, created_by, external_references)
SELECT
  r.rule_code, 2, r.category, r.title,
  'A BESS unit may only change power state along the admissible transition matrix in '
  'ottoq_state_transitions.',
  'An illegal power-state transition (offline -> charging, say) means the engine and the unit disagree '
  'about what the hardware is doing, and the actor gate keeps a state change attributable. THE DWELL '
  'CLAUSE OF v1 IS WITHDRAWN. It asserted that a direct charge<->discharge flip is "physically '
  'impossible for the inverter/contactor and would damage the unit", and no source supports that: '
  'IEEE 1547-2018 requires a DER mode transition to COMPLETE in no more than 30 seconds -- a ceiling, '
  'not a floor -- and imposes no minimum time in a non-exporting state, while grid-support literature '
  'describes storage going standby-to-full-power in under a second and inverters reversing '
  'charge/discharge within seconds. Sourced from secondary institutional summaries (NREL '
  'fy20osti/75436; IREC on IEEE 1547.1-2020; Sandia 2023 Vermont webinar), labelled secondary because '
  'the standard is paywalled. Our 30-second tick could not have observed such a dwell in any case, so '
  'the 14.4 percent of transitions v1 would have refused were never evidence of anything. A '
  'battery-wear argument for a dwell may still be made: it needs a wear rationale, a per-chemistry '
  'quantity, a non-critical severity and finer sampling, and it is not this rule.',
  r.severity, r.enforcement, r.override_allowed, r.override_min_role, r.scope,
  r.evaluator_function, r.default_parameters, r.applies_to_actions, r.applies_to_entities,
  'active', '20260921', 'db/migrations/0397', r.external_references
  FROM public.ottoq_rules r
 WHERE r.rule_code = 'SM.006.bess_transition_validity' AND r.version = 1;

-- ─── THE ASSERTION, which is the durable half of this migration ─────────────
-- Two hand-maintained lists agreed on nothing for two and a half months and no test could say so.
-- This one asks all three questions the split raised, and it is a FUNCTION rather than a constraint
-- for the reason 0396 gives: the writer is the tick hot path and is unwrapped, so a blocking
-- constraint converts a data defect into a dead run. A failure here costs a verdict.
CREATE OR REPLACE FUNCTION public.ottoq_assert_bess_state_vocabulary()
RETURNS TABLE (check_states text, enum_states text, matrix_states text,
               unit_states text, verdict text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
DECLARE
  v_chk text[]; v_enum text[]; v_matrix text[]; v_units text[]; v_bad text[]; v_def text;
BEGIN
  -- the CHECK's permitted set, read off the constraint rather than restated here
  SELECT COALESCE(array_agg(DISTINCT m[1] ORDER BY m[1]), '{}') INTO v_chk
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid,
         LATERAL regexp_matches(pg_get_constraintdef(con.oid), '''([a-z_]+)''::text', 'g') m
   WHERE c.relname = 'ottoq_bess_units'
     AND con.conname = 'ottoq_bess_units_current_state_check';

  SELECT COALESCE(array_agg(e.enumlabel::text ORDER BY e.enumlabel::text), '{}') INTO v_enum
    FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'bess_status';

  SELECT COALESCE(array_agg(DISTINCT s ORDER BY s), '{}') INTO v_matrix
    FROM (SELECT from_state AS s FROM public.ottoq_state_transitions
           WHERE entity_kind = 'bess' AND status = 'active'
          UNION SELECT to_state FROM public.ottoq_state_transitions
           WHERE entity_kind = 'bess' AND status = 'active') q;

  SELECT COALESCE(array_agg(DISTINCT current_state ORDER BY current_state), '{}') INTO v_units
    FROM public.ottoq_bess_units WHERE current_state IS NOT NULL;

  -- (1) the CHECK and the enum must declare the same vocabulary. This is the pair that diverged,
  --     and it is the pair a future edit will diverge again, because both are written by hand.
  IF v_chk <> v_enum THEN
    RAISE EXCEPTION 'BESS vocabulary FAILED (check vs enum): ottoq_bess_units_current_state_check '
                    'permits [%] while the bess_status enum declares [%]. Two hand-maintained lists '
                    'for one vocabulary is how 0397 happened; reconcile them. G96 / db/checks/0298.',
                    array_to_string(v_chk, ', '), array_to_string(v_enum, ', ');
  END IF;

  -- (2) every state a unit actually holds must be representable in the matrix, or a
  --     bess_state_change probe refuses every transition involving it.
  SELECT COALESCE(array_agg(u ORDER BY u), '{}') INTO v_bad
    FROM unnest(v_units) u WHERE NOT (u = ANY(v_matrix));
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION 'BESS vocabulary FAILED (unit vs matrix): units hold [%], which no active bess '
                    'row of ottoq_state_transitions mentions (matrix knows [%]). A bess_state_change '
                    'probe would refuse every transition involving those states. G96.',
                    array_to_string(v_bad, ', '), array_to_string(v_matrix, ', ');
  END IF;

  -- (3) the column DEFAULT is a writer too, and it is the one a prosrc census cannot see.
  SELECT pg_get_expr(ad.adbin, ad.adrelid) INTO v_def
    FROM pg_attrdef ad JOIN pg_class c ON c.oid = ad.adrelid
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ad.adnum
   WHERE c.relname = 'ottoq_bess_units' AND a.attname = 'current_state';
  IF v_def IS NOT NULL AND NOT (v_def LIKE '%''standby''%') THEN
    RAISE EXCEPTION 'BESS vocabulary FAILED (default): ottoq_bess_units.current_state defaults to %, '
                    'not standby. A DEFAULT is a writer and it is invisible to a pg_proc census -- '
                    'which is exactly how 0397 missed it the first time. G96.', v_def;
  END IF;

  RETURN QUERY SELECT array_to_string(v_chk, ', '), array_to_string(v_enum, ', '),
    array_to_string(v_matrix, ', '), array_to_string(v_units, ', '),
    'reconciled: the CHECK equals the enum, every held state is in the matrix, and the default is standby';
END;
$fn$;

COMMENT ON FUNCTION public.ottoq_assert_bess_state_vocabulary() IS
  'G96 / db/checks/0298. Three assertions over the BESS state vocabulary: the CHECK on '
  'ottoq_bess_units.current_state must declare the same set as the bess_status enum; every state a '
  'unit actually holds must be representable in the active bess rows of ottoq_state_transitions; and '
  'the column DEFAULT must be standby. Before 0397 the three declarations agreed on nothing and the '
  'commanded column could not express the resting state the matrix requires, which is what made '
  'SM.006 unwireable. Deliberately a function, not a constraint: the writer is the tick hot path.';

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0397_one_word_for_rest_and_the_dwell_that_lived_in_two_missing_rows_g96',
  true,
  'G96 steps 0 and 1. THREE declarations of the BESS state vocabulary disagreed: the CHECK on '
  'ottoq_bess_units.current_state permitted idle/maintenance and FORBADE standby, while the '
  'bess_status enum and the bess rows of ottoq_state_transitions both used standby and online. So the '
  'commanded column could not hold the resting state the matrix requires, and a bess_state_change '
  'probe reading it would have refused nearly every transition -- which is what made SM.006 '
  'unwireable, not the dwell. Replaces the CHECK with the enum labels, moves the DEFAULT from idle to '
  'standby, rewrites the 3 live rows, and updates the three writers; the single reader '
  '(ottoq_trigger_emergency_cascade) is made tolerant of both because pre-0397 rows say idle. Then '
  'removes SM.006''s dwell from where it actually lived -- the ABSENCE of charging->discharging and '
  'discharging->charging from the 17 active bess rows -- by inserting those two rows, and supersedes '
  'SM.006 to v2 with the unsourced "physically impossible for the inverter/contactor" rationale '
  'replaced by 0295''s IEEE 1547-2018 finding. TRUE and measured: ottoq.ottoq_world_fingerprint hashes '
  'COALESCE(b.current_state,''-''). Landed while all 9 canon columns were already below floor from '
  '0396. Adds ottoq_assert_bess_state_vocabulary, whose three checks exist because two hand-maintained '
  'lists disagreed for ten weeks and nothing could say so. NOT here: typing the column to bess_status '
  '(it breaks the fingerprint''s untyped COALESCE, so it touches the certification spine) and STEP 2, '
  'wiring the probe.',
  now());

COMMIT;
