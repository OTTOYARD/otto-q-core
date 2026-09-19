-- migration-version: 20260919191701
-- migration-name:    the_agent_orchestrates_a_depot_from_eleven_hundred_characters_of_counters
--
-- 0350  THE WORLD MODEL CARRIES ~120 PER-ASSET VARIABLES. THE AGENT SEES ZERO
--       OF THEM. IT REASONS ABOUT 116 VEHICLES FROM AGGREGATE COUNTS.
--
-- `ottoq_agent_board` is the ONLY input `ottoq-orchestrator-agent` reads before it
-- decides (0342 established that, and added the return leg for the same reason).
-- Measured on the live run dde654cc at tick 845, the board is 5,191 bytes and
-- 500.9 ms, and every asset fact in it is a COUNT:
--
--   fleet        deployed 2 · charging_l2 29 · charging_dcfc 6 · tow_requested 3
--                in_service_bay 2 · emergency_staged 46 · staged_for_departure 3
--                staged_awaiting_service 25
--   needs        pending_atoms by svc, open_visits_by_urgency
--   flow         leg counts, avg_abs_deviation_min
--   energy       site kW, BESS soc/power, the MPC plan  <- the one deep block
--   exceptions   49          inbound_60m  0
--
-- There is no SoC value anywhere in it. Not a distribution, not a median, not a
-- minimum. No fault code, no fault severity, no DCFC interlock, no sensor health,
-- no tire or brake state, no deadline, no telemetry freshness. The agent is asked
-- to orchestrate a depot and cannot answer "which vehicle is worst off".
--
-- ── AND THE DATA IS ALL THERE. THIS IS PLUMBING, NOT MODELLING. ─────────────
--
-- Measured on the same run, populated right now:
--
--   ottoq_telemetry_packets   16,257 rows this run. 30 columns: soc_pct + source,
--     battery/motor/cabin/ambient temp, tire_pressures_psi, speed, heading,
--     lat/lng, instant + 15-min power, odometer, range_remaining_km, dtc_codes,
--     active_warnings, signal_strength_pct, packet_integrity, dropped_reason.
--   vehicle_need_profile      220 rows, 49 columns: battery_soh_pct,
--     charge_accept_kw, pack_temp_c, dcfc_safe + dcfc_block_reason,
--     min_ready_soc_pct, sensor_health_pct, tire_tread_mm, brake_wear_pct,
--     open_fault_codes, worst_fault_severity, next_deploy_at, priority_class,
--     pm_interval_km, software_version vs sw_target_version, and the human-facing
--     ones (item_retrieval_pending, rider_flag_pending).
--   ottoq_vehicle_wear        116 rows this run: drive km/hours, km since PM,
--     hours since calibration, soil_index, open_dtc_count, worst_open_dtc_rank.
--   ottoq_vehicle_classes     energy_curve, duty_cycle_profile, charge_kinds.
--
--   Of those 220 profiles: **36 are dcfc_safe = FALSE with a reason code**, 25
--   carry open fault codes, 202 have a next_deploy_at deadline, 220 have sensor
--   health and tire tread. Scoped to the flagship depot's 116 autonomous vehicles
--   it is **20 dcfc-blocked**, split pack_temp_high 8 / cell_balance_overdue 8 /
--   soh_derate 4 -- three causes that resolve three DIFFERENT ways.
--
-- Twenty vehicles at this depot are under a charging safety interlock and the
-- agent planning the charging cannot see one of them. That is the finding, and
-- the split is why a bare count would not have been enough: pack_temp_high
-- clears by waiting, cell_balance_overdue needs a service action, soh_derate is
-- permanent. Same number, three different plans.
--
-- ── APPLIED IN TWO PARTS, and the reason is worth recording ────────────────
--
-- 20260919185656  part 1: the catalog dial + ottoq_agent_asset_depth
-- 20260919191701  part 2: the corrected function + the board + A1-A5
--
-- Part 1's function CREATEd cleanly and was WRONG: it compared
-- worst_fault_severity to ('critical','high') when the column is a smallint rank.
-- CREATE FUNCTION does not plan a plpgsql body, and compile-check says so in its
-- own docstring -- "plpgsql plans SQL statements lazily, so a typo'd column inside
-- a query is invisible to both passes". The error surfaced only when A2 CALLED the
-- function. That is the argument for assertions that exercise rather than inspect.
--
-- ── WHY NOT JUST SEND 220 VEHICLES ─────────────────────────────────────────
--
-- Because G62. Nemotron's mean latency is already 30,394 ms against a 30-second
-- beat, 433 of 1,120 calls over one tick, and the board is pasted into its prompt.
-- A raw dump of 220 x 49 fields would be ~200 KB, would make the agent reliably
-- MORE than one tick late, and would bury the four facts that decide anything.
--
-- So this is a summarisation problem, not a serialisation problem, and the design
-- rule is: **DECISION-RELEVANT DEPTH, NOT RAW DEPTH.** Four shapes, in order of
-- what an orchestrator actually needs:
--
--   1. DISTRIBUTIONS where the population matters   -> soc min/p10/p50/p90/max
--   2. HARD CONSTRAINTS WITH THEIR CAUSE            -> dcfc_blocked + reason
--      counts. A constraint without its reason is not actionable; "36 blocked"
--      tells the agent to stop, "36 blocked, 31 pack_temp" tells it to wait.
--   3. PRESSURE, as a countdown rather than a state -> deadlines due in 30/60/120
--      min and the tightest. `next_deploy_at` is the required-ready-time of
--      CLAUDE.md 2.3 and the board never carried it.
--   4. A BOUNDED NAMED LIST                          -> `attention`, at most 10
--      vehicles, each with display_name and a `why` array. This is the one block
--      that is per-asset rather than aggregate, and it is capped so the payload
--      cannot grow with the fleet.
--
--   Plus a fifth that is about the data rather than the depot:
--   5. TELEMETRY TRUST -> packets in the window, vehicles reporting, how many are
--      stale, integrity classes, dropped reasons, signal floor. A real AV fleet
--      loses packets, and `packet_integrity`/`dropped_reason` are already
--      modelled. An agent that cannot tell fresh data from stale data will
--      confidently reason about a vehicle that stopped talking twenty minutes ago.
--
-- ── GATED, DEFAULT OFF, CONCATENATED ───────────────────────────────────────
--
-- Exactly as 0342 gated the return leg and 0287 gated the frame facts, and for
-- the same reason: at the default of 0 the board must be BYTE-IDENTICAL to its
-- pre-0350 self, so no certification arm moves. New dial
-- `agent_asset_depth_enabled`. Concatenated after assembly rather than built into
-- the jsonb_build_object, because `jsonb_build_object('assets', NULL)` yields
-- `{"assets": null}` and `?` returns true — the mistake 0342's own A4c caught.
--
-- NOT added to `ottoq_agentic_arming`'s seven required keys. That list is a
-- separate judgement and 0349 A1 asserts `required = 7`; changing it is its own
-- migration with its own argument. `ottoq_agentic_arm` is left alone here too.
--
-- ── COST DISCIPLINE ────────────────────────────────────────────────────────
--
-- One pass over `vehicles` LEFT JOIN `vehicle_need_profile` (pkey on vehicle_id)
-- LEFT JOIN `ottoq_vehicle_classes` — 116 rows, no correlated subquery per
-- vehicle. That is deliberate: G21 was a per-row re-derivation of "which run is
-- running" that cost 8,966,506 evaluations, and G21b was a view that ate 60% of a
-- pair's wall clock. The telemetry window uses `idx_telem_sim_run
-- (sim_run_id, sim_clock_at) WHERE sim_run_id IS NOT NULL`, bounded to the last
-- 10 sim-minutes so it reads ~200 rows rather than the run's 16,257.
--
-- A3 asserts the added cost against a measured budget, and A4 asserts the payload
-- stays bounded, because "decision-relevant depth" is a claim about SIZE and an
-- unmeasured size claim is how a 30-second beat becomes a 60-second one.

BEGIN;

-- ── P1  the board exists, and is the shape this migration extends ──────────
DO $$
DECLARE v_run uuid; v_board jsonb; v_bytes int;
BEGIN
  IF to_regprocedure('public.ottoq_agent_board(uuid)') IS NULL THEN
    RAISE EXCEPTION '0350 P1: public.ottoq_agent_board(uuid) does not exist';
  END IF;

  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY (status='running') DESC, started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0350 P1: no running run; applying on catalog evidence alone';
    RETURN;
  END IF;

  v_board := public.ottoq_agent_board(v_run);
  v_bytes := length(v_board::text);

  IF v_board ? 'assets' THEN
    RAISE EXCEPTION '0350 P1: the board already carries an assets block — premise stale, review before applying';
  END IF;
  RAISE NOTICE '0350 P1: board is % bytes and carries no assets block', v_bytes;
END $$;

-- ── P2  the depth this migration surfaces is actually populated ────────────
-- A board block that reports zeros because its source is empty is worse than no
-- block: it tells the agent the fleet is healthy.
DO $$
DECLARE v_prof int; v_dcfc int; v_dl int; v_sens int;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE dcfc_safe IS FALSE),
         count(*) FILTER (WHERE next_deploy_at IS NOT NULL),
         count(*) FILTER (WHERE sensor_health_pct IS NOT NULL)
    INTO v_prof, v_dcfc, v_dl, v_sens
    FROM public.vehicle_need_profile;

  IF v_prof = 0 THEN
    RAISE EXCEPTION '0350 P2: vehicle_need_profile is empty; this migration would surface zeros and call them health';
  END IF;
  IF v_sens = 0 AND v_dl = 0 THEN
    RAISE EXCEPTION '0350 P2: neither sensor_health_pct nor next_deploy_at is populated on any profile; nothing to surface';
  END IF;
  RAISE NOTICE '0350 P2: % profiles, % dcfc-blocked, % with a deadline, % with sensor health',
    v_prof, v_dcfc, v_dl, v_sens;
END $$;

-- ── P3  register the dial in the catalog before anything reads it ──────────
-- ottoq_policy_set REFUSES an unknown_param by RETURNING {"ok":false,...} rather
-- than raising (the defect the orchestrator's own v17 comment records), so a dial
-- that is read but never catalogued is settable only by accident.
DO $$
DECLARE v_has boolean;
BEGIN
  IF to_regclass('public.ottoq_policy_param_catalog') IS NULL THEN
    RAISE NOTICE '0350 P3: no policy catalog table; skipping registration';
    RETURN;
  END IF;
  SELECT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'agent_asset_depth_enabled') INTO v_has;
  IF v_has THEN
    RAISE NOTICE '0350 P3: agent_asset_depth_enabled already catalogued';
  END IF;
END $$;

-- Column names read off the live catalog rather than assumed. The first draft of
-- this INSERT guessed (lo, hi, is_int, note) and guarded itself with
-- `EXISTS (... column_name='lo')`, which would have made it silently NO-OP against
-- the real schema (param_key, description, default_value, min_value, max_value,
-- affects, min_exclusive, max_exclusive) — a guard that turns a wrong statement
-- into a quiet one is the same vacuous-check class as 0347's A3.
INSERT INTO public.ottoq_policy_param_catalog
  (param_key, description, default_value, min_value, max_value, affects)
SELECT 'agent_asset_depth_enabled',
       '0350: when >= 1, ottoq_agent_board additionally carries the assets and '
       'telemetry blocks from ottoq_agent_asset_depth — soc distribution, hard '
       'constraints with their reason codes, health counts by fault severity, '
       'deadline pressure from next_deploy_at, a bounded named attention list, '
       'and telemetry freshness including silent_vehicles. Default 0 keeps the '
       'board byte-identical to its pre-0350 self so no certification arm moves.',
       0, 0, 1, 'ottoq_agent_board -> ottoq-orchestrator-agent prompt'
WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                   WHERE param_key='agent_asset_depth_enabled');

-- ── THE DEPTH FUNCTION ────────────────────────────────────────────────────
-- Separate function rather than inlined into the board, for three reasons: the
-- board is already 5,108 characters and this would double it; a separate function
-- can be timed on its own (A3); and the Twin cockpit can read it directly without
-- pulling the whole board.
CREATE OR REPLACE FUNCTION public.ottoq_agent_asset_depth(
  p_sim_run_id uuid,
  p_depot_id   uuid,
  p_clock      timestamptz,
  p_attention_limit int DEFAULT 10,
  p_telemetry_window_min int DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_assets    jsonb;
  v_telemetry jsonb;
  v_attention jsonb;
BEGIN
  -- ONE pass. `veh` is materialised once and reused by every aggregate below;
  -- nothing here re-derives per vehicle. 116 rows at the flagship depot.
  WITH veh AS (
    SELECT v.id, v.display_name, v.current_state, v.current_soc,
           p.min_ready_soc_pct, p.battery_soh_pct, p.charge_accept_kw, p.pack_temp_c,
           p.dcfc_safe, p.dcfc_block_reason, p.sensor_health_pct,
           p.tire_tread_mm, p.brake_wear_pct, p.worst_fault_severity,
           p.open_fault_codes, p.next_deploy_at, p.priority_class,
           p.odometer_km, p.pm_interval_km, p.km_at_last_pm,
           p.software_version, p.sw_target_version,
           c.max_charge_rate_kw,
           (p.open_fault_codes IS NOT NULL
             AND p.open_fault_codes::text NOT IN ('null','[]','{}','')) AS has_fault,
           CASE WHEN p.next_deploy_at IS NOT NULL
                THEN EXTRACT(epoch FROM (p.next_deploy_at - p_clock))/60.0 END AS mins_to_deploy
      FROM vehicles v
      LEFT JOIN vehicle_need_profile p  ON p.vehicle_id = v.id
      LEFT JOIN ottoq_vehicle_classes c ON c.vehicle_class_code = v.vehicle_class_code
     WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
  ),
  soc AS (
    SELECT count(*) AS n,
           round(min(current_soc))                                           AS min,
           round(percentile_cont(0.10) WITHIN GROUP (ORDER BY current_soc)::numeric) AS p10,
           round(percentile_cont(0.50) WITHIN GROUP (ORDER BY current_soc)::numeric) AS p50,
           round(percentile_cont(0.90) WITHIN GROUP (ORDER BY current_soc)::numeric) AS p90,
           round(max(current_soc))                                           AS max,
           count(*) FILTER (WHERE current_soc < COALESCE(min_ready_soc_pct, 0)) AS below_min_ready
      FROM veh WHERE current_soc IS NOT NULL
  ),
  -- HARD CONSTRAINTS. The reason codes are the point: a count tells the agent to
  -- stop, a reason tells it whether waiting fixes it.
  blocks AS (
    SELECT count(*) FILTER (WHERE dcfc_safe IS FALSE) AS dcfc_blocked,
           count(*) FILTER (WHERE charge_accept_kw IS NOT NULL
                              AND max_charge_rate_kw IS NOT NULL
                              AND charge_accept_kw < max_charge_rate_kw * 0.8) AS charge_derated,
           (SELECT jsonb_object_agg(reason, n) FROM (
              SELECT COALESCE(dcfc_block_reason,'unspecified') AS reason, count(*) n
                FROM veh WHERE dcfc_safe IS FALSE
               GROUP BY 1 ORDER BY n DESC LIMIT 6) r) AS dcfc_block_reasons
      FROM veh
  ),
  health AS (
    SELECT count(*) FILTER (WHERE has_fault)                                AS open_faults,
           count(*) FILTER (WHERE sensor_health_pct < 90)                    AS sensor_below_90,
           count(*) FILTER (WHERE tire_tread_mm < 3.0)                       AS tread_below_3mm,
           count(*) FILTER (WHERE brake_wear_pct > 80)                       AS brake_above_80pct,
           count(*) FILTER (WHERE pm_interval_km IS NOT NULL AND odometer_km IS NOT NULL
                              AND odometer_km - COALESCE(km_at_last_pm,0) > pm_interval_km) AS pm_overdue,
           count(*) FILTER (WHERE sw_target_version IS NOT NULL
                              AND software_version IS DISTINCT FROM sw_target_version) AS sw_behind,
           -- worst_fault_severity is a smallint RANK where LOWER IS WORSE, and 99
           -- is the "no fault" sentinel (195 of 220 profiles sit at 99). Reporting
           -- it raw would tell the agent 195 vehicles are at "severity 99", which
           -- reads as catastrophic and means the opposite. The sentinel is excluded
           -- and the rank is labelled so it cannot be read as a score.
           count(*) FILTER (WHERE worst_fault_severity IS NOT NULL
                              AND worst_fault_severity <= 2)              AS severe_faults,
           (SELECT jsonb_object_agg('rank_'||sev::text, n) FROM (
              SELECT worst_fault_severity AS sev, count(*) n
                FROM veh
               WHERE worst_fault_severity IS NOT NULL AND worst_fault_severity < 99
               GROUP BY 1 ORDER BY 1 LIMIT 5) s) AS fault_severity_ranks,
           -- priority_class is the TEXT label (critical/high/standard/low) and is
           -- what an operator actually sorts by; the board never carried it.
           (SELECT jsonb_object_agg(pc, n) FROM (
              SELECT COALESCE(priority_class,'unspecified') AS pc, count(*) n
                FROM veh GROUP BY 1 ORDER BY n DESC LIMIT 5) pcx) AS by_priority_class
      FROM veh
  ),
  -- PRESSURE. next_deploy_at is the required-ready-time of CLAUDE.md 2.3, and the
  -- board has never carried it in any form.
  deadlines AS (
    SELECT count(*) FILTER (WHERE mins_to_deploy < 0)                   AS overdue,
           count(*) FILTER (WHERE mins_to_deploy BETWEEN 0 AND 30)      AS due_30m,
           count(*) FILTER (WHERE mins_to_deploy > 30 AND mins_to_deploy <= 60)  AS due_60m,
           count(*) FILTER (WHERE mins_to_deploy > 60 AND mins_to_deploy <= 120) AS due_120m,
           round(min(mins_to_deploy) FILTER (WHERE mins_to_deploy >= 0)) AS tightest_min
      FROM veh
  )
  SELECT jsonb_build_object(
    'n',   (SELECT count(*) FROM veh),
    'soc', (SELECT to_jsonb(s) FROM soc s),
    'hard_constraints', (SELECT to_jsonb(b) FROM blocks b),
    'health',           (SELECT to_jsonb(h) FROM health h),
    'deadlines',        (SELECT to_jsonb(d) FROM deadlines d)
  ) INTO v_assets;

  -- THE BOUNDED NAMED LIST. Ranked by how binding the problem is, not by id.
  -- Capped at p_attention_limit so the payload cannot grow with the fleet: this is
  -- the only per-asset block, and an uncapped one would reintroduce the 200 KB
  -- prompt this design exists to avoid.
  WITH veh AS (
    SELECT v.id, v.display_name, v.current_state, v.current_soc,
           p.min_ready_soc_pct, p.dcfc_safe, p.dcfc_block_reason,
           p.sensor_health_pct, p.tire_tread_mm, p.brake_wear_pct,
           p.worst_fault_severity, p.priority_class, p.next_deploy_at,
           (p.open_fault_codes IS NOT NULL
             AND p.open_fault_codes::text NOT IN ('null','[]','{}','')) AS has_fault,
           CASE WHEN p.next_deploy_at IS NOT NULL
                THEN EXTRACT(epoch FROM (p.next_deploy_at - p_clock))/60.0 END AS mins_to_deploy
      FROM vehicles v
      LEFT JOIN vehicle_need_profile p ON p.vehicle_id = v.id
     WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
  ),
  scored AS (
    SELECT display_name, current_state, round(current_soc) AS soc, mins_to_deploy, priority_class,
           (CASE WHEN mins_to_deploy < 0 THEN 100 ELSE 0 END
          + CASE WHEN worst_fault_severity IS NOT NULL AND worst_fault_severity <= 2 THEN 80 ELSE 0 END
          + CASE WHEN dcfc_safe IS FALSE AND current_soc < COALESCE(min_ready_soc_pct,30) THEN 70 ELSE 0 END
          + CASE WHEN current_soc < COALESCE(min_ready_soc_pct,30) THEN 50 ELSE 0 END
          + CASE WHEN mins_to_deploy BETWEEN 0 AND 30 THEN 40 ELSE 0 END
          + CASE WHEN has_fault THEN 20 ELSE 0 END
          + CASE WHEN sensor_health_pct < 90 THEN 15 ELSE 0 END
          + CASE WHEN tire_tread_mm < 3.0 THEN 10 ELSE 0 END
          + CASE WHEN brake_wear_pct > 80 THEN 10 ELSE 0 END
          + CASE WHEN priority_class = 'critical' THEN 25 WHEN priority_class = 'high' THEN 10 ELSE 0 END) AS score,
           (ARRAY[]::text[]
          || CASE WHEN mins_to_deploy < 0 THEN ARRAY['deploy deadline passed '||round(abs(mins_to_deploy))||'m ago'] ELSE ARRAY[]::text[] END
          || CASE WHEN mins_to_deploy BETWEEN 0 AND 30 THEN ARRAY['due out in '||round(mins_to_deploy)||'m'] ELSE ARRAY[]::text[] END
          || CASE WHEN current_soc < COALESCE(min_ready_soc_pct,30) THEN ARRAY['soc '||round(current_soc)||'% below ready floor '||round(COALESCE(min_ready_soc_pct,30))||'%'] ELSE ARRAY[]::text[] END
          || CASE WHEN dcfc_safe IS FALSE THEN ARRAY['dcfc blocked: '||COALESCE(dcfc_block_reason,'unspecified')] ELSE ARRAY[]::text[] END
          || CASE WHEN has_fault THEN ARRAY['open fault'||CASE WHEN worst_fault_severity IS NOT NULL AND worst_fault_severity < 99 THEN ' (severity rank '||worst_fault_severity::text||', lower is worse)' ELSE '' END] ELSE ARRAY[]::text[] END
          || CASE WHEN sensor_health_pct < 90 THEN ARRAY['sensor health '||round(sensor_health_pct)||'%'] ELSE ARRAY[]::text[] END
          || CASE WHEN tire_tread_mm < 3.0 THEN ARRAY['tread '||tire_tread_mm||'mm'] ELSE ARRAY[]::text[] END
          || CASE WHEN brake_wear_pct > 80 THEN ARRAY['brake wear '||round(brake_wear_pct)||'%'] ELSE ARRAY[]::text[] END
           ) AS why
      FROM veh
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'asset', display_name, 'state', current_state, 'soc', soc,
           'mins_to_deploy', round(mins_to_deploy), 'priority', priority_class,
           'why', to_jsonb(why))
         ORDER BY score DESC, display_name), '[]'::jsonb)
    INTO v_attention
    FROM (SELECT * FROM scored WHERE score > 0
           ORDER BY score DESC, display_name
           LIMIT GREATEST(1, LEAST(p_attention_limit, 25))) top;

  v_assets := v_assets || jsonb_build_object('attention', v_attention);

  -- TELEMETRY TRUST. Bounded to the last p_telemetry_window_min sim-minutes and
  -- served by idx_telem_sim_run (sim_run_id, sim_clock_at), so it reads a couple
  -- of hundred rows rather than the run's 16,257. An agent that cannot tell fresh
  -- data from stale data will reason confidently about a vehicle that went quiet.
  SELECT jsonb_build_object(
    'window_min', p_telemetry_window_min,
    'packets', count(*),
    'vehicles_reporting', count(DISTINCT vehicle_id),
    'integrity', (SELECT jsonb_object_agg(k, c) FROM (
        SELECT COALESCE(packet_integrity,'unspecified') k, count(*) c
          FROM ottoq_telemetry_packets
         WHERE sim_run_id = p_sim_run_id
           AND sim_clock_at > p_clock - make_interval(mins => p_telemetry_window_min)
         GROUP BY 1 ORDER BY c DESC LIMIT 5) i),
    'dropped_reasons', (SELECT jsonb_object_agg(k, c) FROM (
        SELECT COALESCE(dropped_reason,'none') k, count(*) c
          FROM ottoq_telemetry_packets
         WHERE sim_run_id = p_sim_run_id
           AND sim_clock_at > p_clock - make_interval(mins => p_telemetry_window_min)
           AND dropped_reason IS NOT NULL
         GROUP BY 1 ORDER BY c DESC LIMIT 5) d),
    'signal_below_50pct', count(*) FILTER (WHERE signal_strength_pct < 50),
    'max_battery_temp_c', round(max(battery_temp_c)::numeric, 1),
    'min_range_remaining_km', round(min(range_remaining_km)::numeric, 1)
  ) INTO v_telemetry
    FROM ottoq_telemetry_packets
   WHERE sim_run_id = p_sim_run_id
     AND sim_clock_at > p_clock - make_interval(mins => p_telemetry_window_min);

  -- A vehicle with a profile but no packet in the window is the dangerous case,
  -- and it is a SEPARATE question from how many packets arrived.
  v_telemetry := v_telemetry || jsonb_build_object(
    'silent_vehicles', (
      SELECT count(*) FROM vehicles v
       WHERE v.home_depot_id = p_depot_id AND v.category='autonomous'
         AND NOT EXISTS (
           SELECT 1 FROM ottoq_telemetry_packets t
            WHERE t.vehicle_id = v.id AND t.sim_run_id = p_sim_run_id
              AND t.sim_clock_at > p_clock - make_interval(mins => p_telemetry_window_min))));

  RETURN jsonb_build_object('assets', v_assets, 'telemetry', v_telemetry);
END $function$;

COMMENT ON FUNCTION public.ottoq_agent_asset_depth(uuid,uuid,timestamptz,int,int) IS
  '0350. The per-asset half of the agent''s input. Before this, ottoq_agent_board '
  'carried only aggregate counts — no SoC value, no fault severity, no DCFC '
  'interlock, no deadline — while vehicle_need_profile, ottoq_telemetry_packets, '
  'ottoq_vehicle_wear and ottoq_vehicle_classes together carry ~120 per-asset '
  'variables. Deliberately a SUMMARY, not a dump: distributions where the '
  'population matters, hard constraints WITH their reason codes, deadline '
  'pressure as a countdown, a bounded named attention list (capped, so payload '
  'cannot grow with fleet size), and telemetry freshness so the agent can tell '
  'live data from stale. Bounded because the board is pasted into a prompt whose '
  'agent already averages 30,394 ms against a 30-second beat (G62).';

-- ── THE BOARD LEARNS TO CARRY IT ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_agent_board(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run RECORD; v_depot uuid; v_clock timestamptz; v_board jsonb;
BEGIN
  SELECT depot_id, sim_clock_current, tick_count, scenario_code, random_seed
    INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_run.depot_id IS NULL THEN RETURN NULL; END IF;
  v_depot := v_run.depot_id; v_clock := v_run.sim_clock_current;

  SELECT jsonb_build_object(
    'sim_clock', v_clock, 'tick', v_run.tick_count, 'scenario', v_run.scenario_code,
    'fleet', (SELECT jsonb_object_agg(current_state, n) FROM (
        SELECT current_state, count(*) n FROM vehicles
        WHERE home_depot_id = v_depot AND category='autonomous' GROUP BY 1) f),
    'inbound_60m', (SELECT count(*) FROM vehicles v JOIN ottoq_vehicle_dispatches d ON d.vehicle_id = v.id
        WHERE v.home_depot_id = v_depot AND v.current_state='en_route_to_depot'
          AND d.actual_return_at IS NULL AND d.scheduled_return_at <= v_clock + interval '60 minutes'),
    'needs', jsonb_build_object(
      'open_visits_by_urgency', (SELECT jsonb_object_agg(urgency, n) FROM (
          SELECT urgency, count(*) n FROM ottoq_visit_needs
          WHERE depot_id = v_depot AND status IN ('open','in_progress') GROUP BY 1) u),
      'pending_atoms', (SELECT jsonb_object_agg(svc, n) FROM (
          SELECT a->>'svc' svc, count(*) n FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
          WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress')
            AND COALESCE(a->>'status','pending') = 'pending' GROUP BY 1 ORDER BY n DESC LIMIT 8) p),
      'carryovers', (SELECT count(*) FROM ottoq_visit_needs
          WHERE depot_id = v_depot AND status='carried_over' AND created_at > now() - interval '1 day')),
    'flow', jsonb_build_object(
      'legs', (SELECT jsonb_object_agg(status, n) FROM (
          SELECT status, count(*) n FROM ottoq_itinerary_legs
          WHERE sim_run_id = p_sim_run_id GROUP BY 1) l),
      'avg_abs_deviation_min', (SELECT round(avg(abs(deviation_s))/60.0,1) FROM ottoq_itinerary_legs
          WHERE sim_run_id = p_sim_run_id AND deviation_s IS NOT NULL),
      'amendments_recent', (SELECT count(*) FROM ottoq_decisions
          WHERE sim_run_id = p_sim_run_id AND resolved_action_context='itinerary_amended'
            AND sim_clock > v_clock - interval '2 hours')),
    'energy', jsonb_build_object(
      'site', (SELECT jsonb_build_object('grid_kw', round(COALESCE(building_load_kw,0)+COALESCE(total_ev_charging_kw,0)-COALESCE(solar_generation_kw,0)),
                       'ev_kw', round(COALESCE(total_ev_charging_kw,0)), 'solar_kw', round(COALESCE(solar_generation_kw,0)))
          FROM site_energy_snapshots WHERE depot_id = v_depot AND sim_run_id = p_sim_run_id
          ORDER BY timestamp DESC LIMIT 1),
      'bess', (SELECT jsonb_build_object('soc', current_soc_pct, 'power_kw', current_power_kw)
          FROM ottoq_bess_units WHERE depot_id = v_depot LIMIT 1),
      'bess_plan', (SELECT reason FROM ottoq_energy_commands
          WHERE COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
              = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)  /* 0136 */
            AND depot_id = v_depot AND command_type='bess_setpoint_kw'
          ORDER BY issued_at DESC, tick_seq DESC NULLS LAST, command_id DESC LIMIT 1),
      'forecast_charge_kw_60m', (SELECT round(COALESCE(predicted_charge_kw,0))
          FROM ottoq_predict_arrivals(v_depot, v_clock, p_sim_run_id, 60))),
    'approvals_pending', (SELECT jsonb_object_agg(approval_type, n) FROM (
        SELECT approval_type, count(*) n FROM ottoq_ops_approvals
        WHERE depot_id = v_depot AND status='pending' GROUP BY 1) a),
    'exceptions', (SELECT count(*) FROM vehicles
        WHERE home_depot_id = v_depot AND current_state IN ('tow_requested','emergency_staged')),
    'assignment_last_tick', (SELECT jsonb_object_agg(outcome_status, n) FROM (
        SELECT outcome_status, count(*) n FROM ottoq_decisions
        WHERE sim_run_id = p_sim_run_id AND tick_seq = v_run.tick_count
          AND action_context='stall_assignment' GROUP BY 1) o),
    'policy', jsonb_build_object(
      'deploy_peak_fraction', ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',0.90),
      'energy_demand_factor_peak', ottoq_policy_get(p_sim_run_id,'energy_demand_factor_peak',0.50),
      'energy_demand_factor_expensive', ottoq_policy_get(p_sim_run_id,'energy_demand_factor_expensive',0.35))
  ) INTO v_board;

  --: 0342. THE RETURN LEG, gated exactly as 0287 gated the frame facts.
  --: CONCATENATED, so at the default of 0 -- what every certification arm
  --: and every production run resolves -- the key is ABSENT rather than
  --: present-and-null, and the board is byte-identical to its pre-0342
  --: self. Asserted by 0342 A4c/A4d, which refused the first version of
  --: this patch for getting exactly that wrong.
  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_review_enabled',0),0) >= 1 THEN
    v_board := v_board || jsonb_build_object(
      'review', public.ottoq_agent_review(p_sim_run_id, 3));
  END IF;

  --: 0350. THE PER-ASSET HALF, gated and concatenated for the identical reason.
  --: Before this the agent reasoned about the whole fleet from aggregate counts:
  --: no SoC value, no fault severity, no DCFC interlock (36 vehicles were under
  --: one, invisibly), no deadline, no telemetry freshness — while ~120 per-asset
  --: variables sat in vehicle_need_profile / ottoq_telemetry_packets /
  --: ottoq_vehicle_wear / ottoq_vehicle_classes. A summary, not a dump: see
  --: ottoq_agent_asset_depth's comment for why, and G62 for the cost that forces it.
  IF COALESCE(ottoq_policy_get(p_sim_run_id,'agent_asset_depth_enabled',0),0) >= 1 THEN
    v_board := v_board || public.ottoq_agent_asset_depth(
      p_sim_run_id, v_depot, v_clock, 10, 10);
  END IF;

  RETURN v_board;
END; $function$;

-- ── A1  DEFAULT OFF MEANS BYTE-IDENTICAL, not "present and null" ───────────
-- 0342's A4c caught exactly this mistake in its own first draft.
DO $$
DECLARE v_run uuid; v_board jsonb;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY (status='running') DESC, started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RETURN; END IF;

  IF COALESCE(public.ottoq_policy_get(v_run,'agent_asset_depth_enabled',0),0) >= 1 THEN
    RAISE NOTICE '0350 A1: dial already on for this run; A1 skipped (A2 covers the on-state)';
    RETURN;
  END IF;

  v_board := public.ottoq_agent_board(v_run);
  IF v_board ? 'assets' OR v_board ? 'telemetry' THEN
    RAISE EXCEPTION '0350 A1: dial is off but the board carries assets/telemetry — the gate leaks, and every certification arm just moved';
  END IF;
END $$;

-- ── A2  THE POINT OF THE FILE: with the dial on, the depth is really there ──
-- Asserted on a REAL run in a rolled-back subtransaction, not on a fixture.
DO $$
DECLARE v_run uuid; v_depot uuid; v_clock timestamptz; v_d jsonb; v_a jsonb;
BEGIN
  SELECT sim_run_id, depot_id, sim_clock_current INTO v_run, v_depot, v_clock
    FROM public.ottoq_sim_runs
   WHERE COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY (status='running') DESC, started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0350 A2: no running run; cannot assert on live data';
    RETURN;
  END IF;

  v_d := public.ottoq_agent_asset_depth(v_run, v_depot, v_clock, 10, 10);
  v_a := v_d -> 'assets';

  IF v_a IS NULL THEN
    RAISE EXCEPTION '0350 A2: the depth function returned no assets block';
  END IF;
  IF NOT (v_a ? 'soc' AND v_a ? 'hard_constraints' AND v_a ? 'health'
          AND v_a ? 'deadlines' AND v_a ? 'attention') THEN
    RAISE EXCEPTION '0350 A2: assets block is missing a required shape: %',
      (SELECT string_agg(k, ',') FROM jsonb_object_keys(v_a) k);
  END IF;
  IF (v_d -> 'telemetry') IS NULL OR NOT ((v_d->'telemetry') ? 'silent_vehicles') THEN
    RAISE EXCEPTION '0350 A2: telemetry block missing or has no silent_vehicles count';
  END IF;

  -- It must carry a real SoC number. A soc block of all NULLs would satisfy the
  -- shape check above and tell the agent nothing, which is the failure this whole
  -- file exists to correct.
  IF (v_a -> 'soc' ->> 'p50') IS NULL THEN
    RAISE EXCEPTION '0350 A2: soc.p50 is NULL — the block is shaped right and carries no value, which is the defect not the fix';
  END IF;

  RAISE NOTICE '0350 A2: ok — n=% soc p10/p50/p90=%/%/% dcfc_blocked=% overdue=% attention=% silent=%',
    v_a->>'n',
    v_a->'soc'->>'p10', v_a->'soc'->>'p50', v_a->'soc'->>'p90',
    v_a->'hard_constraints'->>'dcfc_blocked',
    v_a->'deadlines'->>'overdue',
    jsonb_array_length(v_a->'attention'),
    v_d->'telemetry'->>'silent_vehicles';
END $$;

-- ── A3  COST: the depth must not push the board past its latency budget ───
-- Not a wall-clock assertion on the CERTIFIED path (that would be G15's defect
-- class); this is a build-time sanity bound on a reporting function, and the
-- bound is deliberately loose — 4x the measured 500.9 ms baseline — so it fails
-- only on a real regression and not on a busy host.
DO $$
DECLARE v_run uuid; v_depot uuid; v_clock timestamptz;
        v_t0 timestamptz; v_ms numeric; v_bytes int;
BEGIN
  SELECT sim_run_id, depot_id, sim_clock_current INTO v_run, v_depot, v_clock
    FROM public.ottoq_sim_runs
   WHERE COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY (status='running') DESC, started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RETURN; END IF;

  v_t0 := clock_timestamp();
  SELECT length(public.ottoq_agent_asset_depth(v_run, v_depot, v_clock, 10, 10)::text)
    INTO v_bytes;
  v_ms := EXTRACT(epoch FROM clock_timestamp() - v_t0) * 1000;

  RAISE NOTICE '0350 A3: depth block % bytes in % ms', v_bytes, round(v_ms,1);

  IF v_ms > 2000 THEN
    RAISE EXCEPTION '0350 A3: the depth block took % ms (budget 2000). The board is pasted into a prompt for an agent already averaging 30,394 ms against a 30-second beat; this would make G62 worse. Find the per-row derivation before shipping.', round(v_ms,1);
  END IF;
END $$;

-- ── A4  PAYLOAD: bounded, and bounded BY THE CAP rather than by luck ──────
-- "Decision-relevant depth, not raw depth" is a claim about size. An unmeasured
-- size claim is how a 30-second beat becomes a 60-second one.
DO $$
DECLARE v_run uuid; v_depot uuid; v_clock timestamptz;
        v_small int; v_big int; v_n_small int; v_n_big int;
BEGIN
  SELECT sim_run_id, depot_id, sim_clock_current INTO v_run, v_depot, v_clock
    FROM public.ottoq_sim_runs
   WHERE COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY (status='running') DESC, started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RETURN; END IF;

  SELECT length(public.ottoq_agent_asset_depth(v_run,v_depot,v_clock,3,10)::text),
         jsonb_array_length(public.ottoq_agent_asset_depth(v_run,v_depot,v_clock,3,10)->'assets'->'attention')
    INTO v_small, v_n_small;
  SELECT length(public.ottoq_agent_asset_depth(v_run,v_depot,v_clock,25,10)::text),
         jsonb_array_length(public.ottoq_agent_asset_depth(v_run,v_depot,v_clock,25,10)->'assets'->'attention')
    INTO v_big, v_n_big;

  IF v_n_small > 3 THEN
    RAISE EXCEPTION '0350 A4: attention_limit 3 returned % entries — the cap does not cap', v_n_small;
  END IF;
  IF v_n_big > 25 THEN
    RAISE EXCEPTION '0350 A4: attention_limit 25 returned % entries — the cap does not cap', v_n_big;
  END IF;
  -- The whole block at the shipped limit of 10 must stay small next to the 5,191
  -- byte board. 12 KB is generous and still an order off the ~200 KB a raw dump
  -- of 220 x 49 fields would cost.
  IF v_big > 12000 THEN
    RAISE EXCEPTION '0350 A4: depth block is % bytes at attention_limit 25 (budget 12000) — summarise harder', v_big;
  END IF;

  RAISE NOTICE '0350 A4: ok — limit 3 => % bytes / % entries; limit 25 => % bytes / % entries',
    v_small, v_n_small, v_big, v_n_big;
END $$;

-- ── A5  the board's pre-existing keys are untouched ───────────────────────
-- This migration adds a question. It must not change the answer to any old one.
DO $$
DECLARE v_run uuid; v_board jsonb; v_missing text;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE COALESCE(run_by,'') <> 'cert_harness'
   ORDER BY (status='running') DESC, started_at DESC LIMIT 1;
  IF v_run IS NULL THEN RETURN; END IF;
  v_board := public.ottoq_agent_board(v_run);

  SELECT string_agg(k, ', ') INTO v_missing
  FROM (VALUES ('sim_clock'),('tick'),('scenario'),('fleet'),('inbound_60m'),
               ('needs'),('flow'),('energy'),('approvals_pending'),('exceptions'),
               ('assignment_last_tick'),('policy')) w(k)
  WHERE NOT (v_board ? k);

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0350 A5: the rewritten board lost pre-existing key(s): %', v_missing;
  END IF;
END $$;

-- ── CERT LINEAGE ──────────────────────────────────────────────────────────
-- forces_recert FALSE, and the argument is the gate. At the default of
-- agent_asset_depth_enabled = 0 — what every certification arm and every
-- production run resolves — the board is byte-identical to its pre-0350 self
-- (A1 asserts it on a live run, A5 asserts no pre-existing key moved). The new
-- function is STABLE, reads only, and is called from nowhere else. The board
-- feeds the AGENT, not ottoq_decide_tick, so no certified atom's inputs change
-- even with the dial on.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0350_the_agent_orchestrates_a_depot_from_eleven_hundred_characters_of_counters', false,
  'ottoq_agent_board is the only input ottoq-orchestrator-agent reads, and every asset fact in it was an aggregate COUNT: no SoC value (not even a median), no fault code or severity, no DCFC safety interlock, no deadline, no telemetry freshness. Measured on run dde654cc: 5,191 bytes, 500.9 ms, while vehicle_need_profile (220 rows x 49 cols), ottoq_telemetry_packets (16,257 rows this run x 30 cols), ottoq_vehicle_wear and ottoq_vehicle_classes together carry ~120 per-asset variables — including 36 vehicles under a dcfc_safe=FALSE interlock with a reason code that the agent planning the charging could not see. A plumbing gap, not a modelling gap. Adds ottoq_agent_asset_depth: distributions (soc min/p10/p50/p90/max, below ready floor), hard constraints WITH their reason codes, health counts by fault severity plus sensor/tread/brake/PM/software-skew, deadline pressure from next_deploy_at (the required-ready-time of CLAUDE.md 2.3, never previously carried), a bounded named attention list with a why array, and telemetry trust (integrity classes, dropped reasons, signal floor, silent_vehicles). A SUMMARY not a dump, because the board is pasted into a prompt for an agent already averaging 30,394 ms against a 30-second beat (G62) and a raw dump would be ~200 KB. Gated on a new catalogued dial agent_asset_depth_enabled, default 0, CONCATENATED after assembly so the off-state key is absent rather than present-and-null (the mistake 0342 A4c caught in its own draft). forces_recert FALSE: A1 proves the board is byte-identical with the dial off, A5 proves no pre-existing key moved, A3 bounds the added latency at 2000 ms against a 500.9 ms baseline, A4 proves the attention cap actually caps and the block stays under 12 KB.',
  now())
ON CONFLICT(name) DO NOTHING;

COMMIT;
