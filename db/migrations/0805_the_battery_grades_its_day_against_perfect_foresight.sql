-- migration-version: PENDING
-- migration-name:    the_battery_grades_its_day_against_perfect_foresight
--
-- 0805  **The battery grades each day it ran against perfect foresight.** (B2, the battery's hindsight; the measurement an
--        agent's nightly battery review reads)
--
-- ══ §0 WHY NOW ══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-11-05: "let's not sleep on the agent/AI with BESS usage angle (Forward planning/analyzing, etc.)"; and
--   2026-11-06 (read by 13:20 UTC): "Yes, just keep building". B1 (0803, 0804) is the forward planning. This is the
--   analysing: every day the battery ran is set against the best that day allowed, so how good the battery was is a number
--   with a run beside it, not an impression. Rule 10: production OTTO-Q grades its own decisions read-only and changes
--   nothing because of the grade; the grade is for a person (and for an agent that writes to a person).
--
-- ══ §1 WHAT IS MISSING ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   The research lab grades a battery by setting its bill beside the bill with no battery and the bill perfect foresight
--   would have run up (lab/research/p2_perfect_day/bound_energy.py: a linear program over the day's realized load). On the
--   six 36-hour lab days the day plan closed 22% of the gap to perfect foresight and the planner 54%. Production has
--   nothing like it: site_energy_snapshots, the energy commands and every input the grade needs are run-scoped engine data
--   that the next demo run's purge deletes, and no LP runs in the database. ottoq-intelligence's battery planner (B1, POST
--   /optimize/battery-plan) is that LP: given the day's realized load it is perfect foresight.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_bess_hindsight, evidence (registered; no foreign key, 0340's pattern; guarded against TRUNCATE by
--       0748's registry trigger): one row per run and local day the battery ran (a day's part when the run started or
--       stopped inside it). At fire time it keeps everything the grade needs, so the row outlives the purge of the
--       snapshots it was built from: the realized bill, the bill with no battery, the battery's charge at the day's start
--       and end, how the battery was run (modes, and the share of ticks on an outside plan), and the request for perfect
--       foresight. A row moves once, from 'pending' to 'graded' or 'failed', and is otherwise append-only.
--   (b) public.ottoq_bess_hindsight_segment(run, depot, from, to): the day's grade inputs from the run's snapshots, as the
--       research lab bills a day (bound_energy.py): energy at each snapshot's rate for its interval, the demand charge on
--       the day's highest 30-minute window at the day plan's daily rate (bess_plan_demand_amortization_days), wear per kWh
--       discharged; no battery is the load before the battery, floored at zero. Perfect foresight's request: the realized
--       load, the same prices and battery, the battery's charge at the day's start, the call reserve as the depot's dials
--       hold it (the planner's floor, 0804), the energy left at the end valued at the day plan's replacement cost. Each
--       day pays for its own highest half hour, as the lab's days do.
--   (c) public.ottoq_bess_hindsight_fire(run, depot, day): the row, 'pending', and the edge function
--       ottoq-battery-planner asked for it ({hindsight_id}, the vault's anon key), which reads the request from the row.
--   (d) public.ottoq_bess_hindsight_land(id, response, http_status, latency): perfect foresight's bill at the realized
--       day's end charge (its objective plus the end charge's value), and the grade:
--         capture_share = (no battery - realized) / (no battery - perfect foresight), every bill at the realized end charge,
--         left_usd      = realized - perfect foresight,
--       'failed' with its reason for an answer that is not a solved plan for every step; each call a ledger row
--       (provider intelligence_battery_planner, role hindsight). The service role's alone.
--   (e) public.ottoq_bess_hindsight_sweep(depot, run_by, days): every run of those origins started within the days, and
--       each of its local days that is over (the run's clock has passed its midnight, or the run has stopped) with 24
--       snapshots or more and no row yet, fired; only where the run reads bess_hindsight_enabled as 1. Hourly by cron
--       ('ottoq-bess-hindsight-sweep', 17 * * * *), so a day is graded well before a later demo run's purge.
--   (f) public.ottoq_bess_hindsight_board: one line a graded day, for a person or an agent: the three bills, the capture
--       share, what was left, the half hours that set each peak, and how the battery was run.
--   (g) The dial bess_hindsight_enabled (0..1, default 0, a person's). Nothing in the engine reads the grade.
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 not applied; none of this file's objects, its dial or cron job exists.
--   V1 on the twin's latest run with 24 snapshots or more, rolled back with its rows: the segment's bills are well formed
--   (positive, no battery's peak at least the realized load's floor), the fire writes one pending row carrying the
--   request, a solved answer grades it, a second landing is refused, a failed answer fails with its reason, and each
--   landing is one ledger row. Skipped with a notice when the twin has no such run.
--   In the research lab (2026-11-06, read by 14:45 UTC), on a copy of the 36-hour base day 424242_b36: V1 passed; the
--   segment billed the window from 6 PM day 1 exactly as the research lab's bound_energy.py does (realized $1,539.61, peak
--   1,019.4 kW at 23:00; no battery $1,497.50, 1,139.9 kW), its end charge 0.9 kWh from the battery's own snapshot; and the
--   sweep fired the run's two local days, a local ottoq-intelligence answered both, and they graded: 2026-09-01 (6 AM to
--   midnight) the day plan captured 52.8% of what perfect foresight could save, leaving $211.74; 2026-09-02 (to 6 PM) it
--   was 1.6% worse than no battery at the same end charge, leaving $473.70.
--
-- ══ §4 LINEAGE ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: no function the engine runs is changed; the sweep reads run data
--   and writes evidence.
--
-- ROLLBACK: SELECT cron.unschedule('ottoq-bess-hindsight-sweep');
--   DROP VIEW public.ottoq_bess_hindsight_board;
--   DROP FUNCTION public.ottoq_bess_hindsight_sweep(uuid,text[],integer), public.ottoq_bess_hindsight_land(bigint,jsonb,integer,integer),
--     public.ottoq_bess_hindsight_fire(uuid,uuid,date), public.ottoq_bess_hindsight_segment(uuid,uuid,timestamptz,timestamptz);
--   the table is evidence: keep it (0749), or drop it under ottoq.evidence_truncate_unlock with a reason;
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'bess_hindsight_enabled';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0805_the_battery_grades_its_day_against_perfect_foresight'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0805 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0805_the_battery_grades_its_day_against_perfect_foresight') THEN
    RAISE EXCEPTION '0805 P1: already applied';
  END IF;
  IF to_regclass('public.ottoq_bess_hindsight') IS NOT NULL OR to_regproc('public.ottoq_bess_hindsight_segment') IS NOT NULL
     OR to_regproc('public.ottoq_bess_hindsight_fire') IS NOT NULL OR to_regproc('public.ottoq_bess_hindsight_land') IS NOT NULL
     OR to_regproc('public.ottoq_bess_hindsight_sweep') IS NOT NULL THEN
    RAISE EXCEPTION '0805 P1: an object of this file already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bess_hindsight_enabled') THEN
    RAISE EXCEPTION '0805 P1: the dial bess_hindsight_enabled is already catalogued';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-bess-hindsight-sweep') THEN
    RAISE EXCEPTION '0805 P1: the cron job ottoq-bess-hindsight-sweep already exists';
  END IF;
END $premises$;

-- ══ (a) the grades ══════════════════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_bess_hindsight (
  hindsight_id   bigserial PRIMARY KEY,
  depot_id       uuid NOT NULL,
  sim_run_id     uuid NOT NULL,
  run_by         text,
  local_day      date NOT NULL,
  window_from    timestamptz NOT NULL,
  window_to      timestamptz NOT NULL,
  steps          int NOT NULL,
  state          text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending', 'graded', 'failed')),
  realized       jsonb NOT NULL,
  no_battery     jsonb NOT NULL,
  battery        jsonb NOT NULL,
  request        jsonb NOT NULL,
  perfect        jsonb,
  capture_share  numeric,
  left_usd       numeric,
  request_id     bigint,
  error          text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  graded_at      timestamptz,
  CONSTRAINT ottoq_bess_hindsight_once UNIQUE (depot_id, sim_run_id, local_day)
);
COMMENT ON TABLE public.ottoq_bess_hindsight IS
  '0805: the battery''s grade for each run and local day it ran: the realized bill, the bill with no battery and the bill '
  'perfect foresight would have run up (ottoq-intelligence''s battery planner on the day''s realized load), each at the '
  'realized day''s end charge, with capture_share = (no battery - realized) / (no battery - perfect foresight) and '
  'left_usd = realized - perfect foresight. Kept whole at fire time, so it outlives the purge of the snapshots it was built '
  'from. A measurement for people (rule 10): nothing in the engine reads it. Evidence; one transition, pending to graded '
  'or failed; otherwise append-only.';

CREATE OR REPLACE FUNCTION public.ottoq_bess_hindsight_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF COALESCE(current_setting('ottoq.bess_forecast_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  -- the one move a grade makes: pending to graded or failed, its identity and inputs unchanged
  IF TG_OP = 'UPDATE' AND OLD.state = 'pending' AND NEW.state IN ('graded', 'failed', 'pending')
     AND NEW.hindsight_id = OLD.hindsight_id AND NEW.sim_run_id = OLD.sim_run_id AND NEW.local_day = OLD.local_day
     AND NEW.realized = OLD.realized AND NEW.no_battery = OLD.no_battery AND NEW.battery = OLD.battery
     AND NEW.request = OLD.request THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'ottoq_bess_hindsight is evidence: % refused (0805). A pending row may be graded once; nothing else '
                  'changes. Set ottoq.bess_forecast_unlock = on in the transaction to override, and say why in a migration.',
                  TG_OP USING ERRCODE = '42501';
END;
$function$;
CREATE TRIGGER ottoq_bess_hindsight_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_bess_hindsight
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_bess_hindsight_append_only();
ALTER TABLE public.ottoq_bess_hindsight ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ottoq_bess_hindsight FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.ottoq_bess_hindsight TO anon, authenticated, service_role;
INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_bess_hindsight', 'sim_run_id', 'evidence',
        '0805: the battery''s daily grade against perfect foresight, kept whole at fire time. Evidence, not engine: it '
        'is how a person reads how good the battery was on a day the next demo run''s purge has emptied. NO foreign key, '
        'for 0340/0364''s reason.');

-- ══ (b) the day's inputs ════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_bess_hindsight_segment(p_sim_run_id uuid, p_depot_id uuid,
    p_from timestamp with time zone, p_to timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0805: the grade's inputs for the run's snapshots in (p_from, p_to]: {steps, realized, no_battery, battery, request}, or
   NULL under 24 snapshots or without a battery. Bills as the research lab's bound_energy.py: each snapshot's interval the
   time to the next (the last as the one before), energy at its rate on the grid drawn (never below zero), the demand charge
   on the highest 30-minute window at the day plan's daily rate, wear per kWh discharged. Design: 0805 §2(b). */
DECLARE
  c_tz CONSTANT text := 'America/Chicago';
  v_t timestamptz[]; v_pre numeric[]; v_grid numeric[]; v_out numeric[]; v_rate numeric[]; v_dt numeric[];
  v_n int; v_win int; i int; j int; v_step numeric; b record; v_rt numeric; v_eff numeric; v_lo numeric; v_hi numeric;
  v_e0 numeric; v_e1 numeric; v_month int; v_season text; v_d_rate numeric; v_amort numeric; v_d_day numeric;
  v_min_rate numeric; v_c_rep numeric; v_c_deg numeric; v_dr_kwh numeric; v_dr_s numeric; v_dr_e numeric; v_lead numeric;
  v_hf numeric; v_r numeric; v_floor numeric[] := ARRAY[]::numeric[];
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
  IF v_n < 24 THEN RETURN NULL; END IF;
  v_dt := ARRAY(SELECT CASE WHEN k < v_n THEN GREATEST(EXTRACT(EPOCH FROM (v_t[k + 1] - v_t[k])) / 3600.0, 1e-6)
                            ELSE GREATEST(EXTRACT(EPOCH FROM (v_t[v_n] - v_t[v_n - 1])) / 3600.0, 1e-6) END
                  FROM generate_series(1, v_n) k ORDER BY k);
  v_step := round((SELECT avg(x) FROM unnest(v_dt) x) * 60);
  v_win := GREATEST(1, round(30 / NULLIF(v_step, 0))::int);

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

  -- the realized day and the day with no battery
  WITH x AS (SELECT k, v_grid[k] AS g, GREATEST(v_pre[k], 0) AS gn, v_rate[k] AS r, v_dt[k] AS dt, GREATEST(v_out[k], 0) AS dis,
                    v_t[k] AS t FROM generate_series(1, v_n) k),
       w AS (SELECT k, avg(g) OVER (ORDER BY k ROWS BETWEEN CURRENT ROW AND v_win - 1 FOLLOWING) AS mg,
                    avg(gn) OVER (ORDER BY k ROWS BETWEEN CURRENT ROW AND v_win - 1 FOLLOWING) AS mn
               FROM x),
       pk AS (SELECT (SELECT k FROM w WHERE k <= v_n - v_win + 1 ORDER BY mg DESC, k LIMIT 1) AS kg,
                     (SELECT k FROM w WHERE k <= v_n - v_win + 1 ORDER BY mn DESC, k LIMIT 1) AS kn)
  SELECT jsonb_build_object(
           'energy_usd', round(sum(GREATEST(g, 0) * r * dt), 2),
           'peak30_kw', round((SELECT mg FROM w WHERE w.k = pk.kg), 1),
           'peak30_ends_ct', to_char(v_t[LEAST(pk.kg + v_win - 1, v_n)] AT TIME ZONE c_tz, 'YYYY-MM-DD HH24:MI'),
           'demand_usd', round(v_d_day * GREATEST((SELECT mg FROM w WHERE w.k = pk.kg), 0), 2),
           'discharge_kwh', round(sum(dis * dt), 1), 'wear_usd', round(v_c_deg * sum(dis * dt), 2),
           'total_usd', round(sum(GREATEST(g, 0) * r * dt) + v_d_day * GREATEST((SELECT mg FROM w WHERE w.k = pk.kg), 0)
                              + v_c_deg * sum(dis * dt), 2)),
         jsonb_build_object(
           'energy_usd', round(sum(gn * r * dt), 2),
           'peak30_kw', round((SELECT mn FROM w WHERE w.k = pk.kn), 1),
           'peak30_ends_ct', to_char(v_t[LEAST(pk.kn + v_win - 1, v_n)] AT TIME ZONE c_tz, 'YYYY-MM-DD HH24:MI'),
           'demand_usd', round(v_d_day * (SELECT mn FROM w WHERE w.k = pk.kn), 2),
           'total_usd', round(sum(gn * r * dt) + v_d_day * (SELECT mn FROM w WHERE w.k = pk.kn), 2),
           -- at the realized day's end charge: the energy the battery stored over the day, at its replacement cost
           'total_usd_at_realized_end', round(sum(gn * r * dt) + v_d_day * (SELECT mn FROM w WHERE w.k = pk.kn)
                                              + v_c_rep * (v_e1 - v_e0), 2))
    INTO v_real, v_none
    FROM x, pk GROUP BY pk.kg, pk.kn;

  -- how the battery was run: its modes, and the share of ticks it followed an outside plan
  SELECT jsonb_object_agg(m, n), COALESCE(sum(n) FILTER (WHERE m = 'mpc_follow'), 0)::numeric / NULLIF(sum(n), 0)
    INTO v_modes, v_follow
    FROM (SELECT COALESCE(c.reason->>'mode', '?') AS m, count(*) AS n FROM ottoq_energy_commands c
           WHERE c.sim_run_id = p_sim_run_id AND c.depot_id = p_depot_id AND c.command_type = 'bess_setpoint_kw'
             AND c.issued_at > p_from AND c.issued_at <= p_to GROUP BY 1) z;

  -- perfect foresight's floor: the call reserve as the depot's dials hold it (0804's planner floor), at each step's end
  v_dr_kwh := GREATEST(0, COALESCE(ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_reserve_kwh', 600), 600));
  v_dr_s := ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_window_start_hour', 14);
  v_dr_e := ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_window_end_hour', 20);
  v_lead := COALESCE(ottoq_policy_get(p_sim_run_id, 'bess_plan_dr_reserve_lead_h', 24), 24);
  FOR i IN 1..v_n LOOP
    v_hf := EXTRACT(HOUR FROM v_t[i] AT TIME ZONE c_tz) + EXTRACT(MINUTE FROM v_t[i] AT TIME ZONE c_tz) / 60.0;
    v_r := CASE WHEN COALESCE(v_season, '') <> 'summer' OR v_dr_kwh <= 0 OR v_dr_e <= v_dr_s THEN 0
                WHEN v_hf < v_dr_s - v_lead THEN 0
                WHEN v_hf < v_dr_s THEN v_dr_kwh
                WHEN v_hf < v_dr_e THEN v_dr_kwh * (v_dr_e - v_hf) / (v_dr_e - v_dr_s)
                ELSE 0 END;
    v_floor := v_floor || round(CASE WHEN v_r > 0 THEN LEAST(v_hi, v_lo + v_r / v_eff) ELSE v_lo END, 1);
  END LOOP;

  RETURN jsonb_build_object(
    'steps', v_n, 'step_min', v_step, 'from', v_t[1], 'to', v_t[v_n],
    'realized', v_real, 'no_battery', v_none,
    'battery', jsonb_build_object('soc_start_kwh', round(v_e0, 1), 'soc_end_kwh', round(v_e1, 1),
                                  'replacement_usd_kwh', round(v_c_rep, 5), 'modes', v_modes,
                                  'followed_a_plan', round(v_follow, 3)),
    'request', jsonb_build_object(
      'load_kw', (SELECT jsonb_agg(round(x, 1) ORDER BY o) FROM unnest(v_pre) WITH ORDINALITY u(x, o)),
      'price_usd_kwh', to_jsonb(v_rate), 'step_min', v_step,
      'battery', jsonb_build_object('soc_kwh', round(v_e0, 1), 'floor_kwh', round(v_lo, 1), 'ceiling_kwh', round(v_hi, 1),
                                    'max_charge_kw', b.pc, 'max_discharge_kw', b.pd, 'eff_one_way', v_eff),
      'demand_usd_kw', v_d_day,
      'periods', jsonb_build_array(jsonb_build_object('start', 0, 'end', v_n, 'sunk_kw', 0, 'margin_kw', 0)),
      'past_grid_kw', '[]'::jsonb, 'window_steps', v_win, 'soc_floor_kwh', to_jsonb(v_floor),
      'wear_usd_kwh', v_c_deg, 'terminal_usd_kwh', round(v_c_rep, 5)));
END;
$function$;

-- ══ (c) the fire ════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_bess_hindsight_fire(p_sim_run_id uuid, p_depot_id uuid, p_local_day date)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0805: the run's local day as a pending grade, kept whole, and the edge function ottoq-battery-planner asked for perfect
   foresight ({hindsight_id}); NULL when the day has under 24 snapshots or is already graded. */
DECLARE
  c_tz CONSTANT text := 'America/Chicago';
  v_from timestamptz := (p_local_day::timestamp) AT TIME ZONE c_tz;
  v_to timestamptz := ((p_local_day + 1)::timestamp) AT TIME ZONE c_tz;
  v_seg jsonb; v_id bigint; v_k text; v_rid bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_bess_hindsight
              WHERE depot_id = p_depot_id AND sim_run_id = p_sim_run_id AND local_day = p_local_day) THEN
    RETURN NULL;
  END IF;
  v_seg := public.ottoq_bess_hindsight_segment(p_sim_run_id, p_depot_id, v_from, v_to);
  IF v_seg IS NULL THEN RETURN NULL; END IF;
  INSERT INTO public.ottoq_bess_hindsight (depot_id, sim_run_id, run_by, local_day, window_from, window_to, steps, realized,
                                           no_battery, battery, request)
  VALUES (p_depot_id, p_sim_run_id, (SELECT run_by FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), p_local_day,
          (v_seg->>'from')::timestamptz, (v_seg->>'to')::timestamptz, (v_seg->>'steps')::int, v_seg->'realized',
          v_seg->'no_battery', v_seg->'battery', v_seg->'request')
  ON CONFLICT ON CONSTRAINT ottoq_bess_hindsight_once DO NOTHING
  RETURNING hindsight_id INTO v_id;
  IF v_id IS NULL THEN RETURN NULL; END IF;
  BEGIN
    SELECT decrypted_secret INTO v_k FROM vault.decrypted_secrets WHERE name = 'ottoq_anon_key' LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_k := NULL;
  END;
  IF v_k IS NOT NULL THEN
    v_rid := net.http_post(
      url := 'https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-battery-planner',
      headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_k, 'apikey', v_k),
      body := jsonb_build_object('hindsight_id', v_id),
      timeout_milliseconds := 20000);
    UPDATE public.ottoq_bess_hindsight SET request_id = v_rid WHERE hindsight_id = v_id;
  END IF;
  RETURN v_id;
END;
$function$;

-- ══ (d) the landing ═════════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_bess_hindsight_land(p_hindsight_id bigint, p_response jsonb,
    p_http_status integer DEFAULT 200, p_latency_ms integer DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0805: perfect foresight's answer for a pending grade: its bill at the realized day's end charge (the objective, which
   credits the energy it leaves at the replacement cost, plus that cost on the realized end charge), the capture share and
   what was left; 'failed' with its reason for anything but a solved plan for every step. Each call a ledger row. */
DECLARE
  h record; v_err text; v_obj numeric; v_pf numeric; v_nb numeric; v_real numeric; v_share numeric; v_state text;
BEGIN
  SELECT * INTO h FROM public.ottoq_bess_hindsight WHERE hindsight_id = p_hindsight_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_such_grade'); END IF;
  IF h.state <> 'pending' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_pending', 'state', h.state); END IF;
  v_err := CASE
    WHEN COALESCE(p_http_status, 0) <> 200 THEN 'http_' || COALESCE(p_http_status::text, 'none')
    WHEN COALESCE(p_response->>'status', '') NOT IN ('optimal', 'feasible') THEN 'status_' || COALESCE(p_response->>'status', 'none')
    WHEN jsonb_typeof(p_response->'setpoint_kw') <> 'array' OR jsonb_array_length(p_response->'setpoint_kw') <> h.steps
      THEN 'steps_' || COALESCE(jsonb_array_length(p_response->'setpoint_kw')::text, 'none') || '_of_' || h.steps
    WHEN p_response->>'objective_usd' IS NULL THEN 'no_objective'
  END;
  IF v_err IS NULL THEN
    v_obj := (p_response->>'objective_usd')::numeric;
    v_pf := v_obj + (h.battery->>'replacement_usd_kwh')::numeric * (h.battery->>'soc_end_kwh')::numeric;
    v_nb := (h.no_battery->>'total_usd_at_realized_end')::numeric;
    v_real := (h.realized->>'total_usd')::numeric;
    v_share := CASE WHEN v_nb - v_pf > 0.01 THEN round((v_nb - v_real) / (v_nb - v_pf), 4) END;
  END IF;
  v_state := CASE WHEN v_err IS NULL THEN 'graded' ELSE 'failed' END;
  UPDATE public.ottoq_bess_hindsight
     SET state = v_state, graded_at = clock_timestamp(), error = v_err, capture_share = v_share,
         left_usd = CASE WHEN v_err IS NULL THEN round(v_real - v_pf, 2) END,
         perfect = CASE WHEN v_err IS NULL THEN jsonb_build_object(
           'total_usd_at_realized_end', round(v_pf, 2), 'objective_usd', round(v_obj, 2),
           'peak30_kw', (SELECT round(max(x::numeric), 1) FROM jsonb_array_elements_text(p_response->'peak_kw') x),
           'soc_end_kwh', round((p_response->'soc_kwh'->>(jsonb_array_length(p_response->'soc_kwh') - 1))::numeric, 1),
           'solve_ms', p_response->'solve_ms', 'solver', p_response->'solver', 'latency_ms', p_latency_ms) END
   WHERE hindsight_id = h.hindsight_id;
  BEGIN
    PERFORM public.ottoq_log_model_call(
      p_provider := 'intelligence_battery_planner', p_role := 'hindsight',
      p_outcome := CASE WHEN v_err IS NULL THEN 'answered' ELSE 'error' END,
      p_sim_run_id := h.sim_run_id, p_depot_id := h.depot_id, p_sim_clock := h.window_to, p_model := 'battery_planner_glop',
      p_endpoint := '/optimize/battery-plan', p_http_status := p_http_status, p_latency_ms := p_latency_ms,
      p_proposals_out := 0, p_rationale_present := false,
      p_detail := jsonb_build_object('hindsight_id', h.hindsight_id, 'local_day', h.local_day, 'state', v_state,
                                     'error', v_err, 'capture_share', v_share, 'path', 'edge:ottoq-battery-planner'),
      p_source_kind := 'live');
  EXCEPTION WHEN OTHERS THEN
    NULL;   -- evidence never fails the landing it records
  END;
  RETURN jsonb_build_object('ok', v_err IS NULL, 'state', v_state, 'error', v_err, 'capture_share', v_share,
                            'left_usd', CASE WHEN v_err IS NULL THEN round(v_real - v_pf, 2) END);
END;
$function$;

-- ══ (e) the sweep ═══════════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_bess_hindsight_sweep(p_depot_id uuid DEFAULT '11111111-1111-1111-1111-111111111111',
    p_run_by text[] DEFAULT ARRAY['operator_demo', 'production_live'], p_days integer DEFAULT 14)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0805: every local day that is over, of every run of those origins at the depot started within p_days that reads
   bess_hindsight_enabled as 1, with no grade yet: fired (ottoq_bess_hindsight_fire). A day is over when the run's clock
   has passed its midnight or the run has stopped. Returns what it fired. */
DECLARE
  c_tz CONSTANT text := 'America/Chicago';
  r record; d record; v_id bigint; v_fired jsonb := '[]'::jsonb;
BEGIN
  FOR r IN SELECT s.sim_run_id, s.status, s.sim_clock_current FROM ottoq_sim_runs s
            WHERE s.depot_id = p_depot_id AND s.run_by = ANY(p_run_by) AND s.started_at >= now() - make_interval(days => p_days)
              AND COALESCE(ottoq_policy_get(s.sim_run_id, 'bess_hindsight_enabled', 0), 0) >= 0.5
            ORDER BY s.started_at LOOP
    FOR d IN SELECT DISTINCT ((e.timestamp - interval '1 microsecond') AT TIME ZONE c_tz)::date AS day
               FROM site_energy_snapshots e WHERE e.sim_run_id = r.sim_run_id AND e.depot_id = p_depot_id ORDER BY 1 LOOP
      IF r.status = 'running' AND r.sim_clock_current < ((d.day + 1)::timestamp AT TIME ZONE c_tz) THEN
        CONTINUE;   -- the day is not over
      END IF;
      v_id := public.ottoq_bess_hindsight_fire(r.sim_run_id, p_depot_id, d.day);
      IF v_id IS NOT NULL THEN
        v_fired := v_fired || jsonb_build_array(jsonb_build_object('hindsight_id', v_id, 'run', r.sim_run_id, 'day', d.day));
      END IF;
    END LOOP;
  END LOOP;
  RETURN jsonb_build_object('fired', jsonb_array_length(v_fired), 'grades', v_fired);
END;
$function$;

-- ══ (f) the board ═══════════════════════════════════════════════════════════════════════════════════════════════════
CREATE VIEW public.ottoq_bess_hindsight_board AS
SELECT h.local_day, h.sim_run_id, h.run_by, h.state, h.steps,
       (h.realized->>'total_usd')::numeric AS realized_usd,
       (h.no_battery->>'total_usd_at_realized_end')::numeric AS no_battery_usd,
       (h.perfect->>'total_usd_at_realized_end')::numeric AS perfect_foresight_usd,
       h.capture_share, h.left_usd,
       (h.realized->>'peak30_kw')::numeric AS realized_peak_kw, h.realized->>'peak30_ends_ct' AS realized_peak_ends_ct,
       (h.no_battery->>'peak30_kw')::numeric AS no_battery_peak_kw, (h.perfect->>'peak30_kw')::numeric AS perfect_peak_kw,
       (h.battery->>'soc_start_kwh')::numeric AS soc_start_kwh, (h.battery->>'soc_end_kwh')::numeric AS soc_end_kwh,
       (h.battery->>'followed_a_plan')::numeric AS followed_a_plan, h.battery->'modes' AS modes,
       h.error, h.created_at, h.graded_at
  FROM public.ottoq_bess_hindsight h;
COMMENT ON VIEW public.ottoq_bess_hindsight_board IS
  '0805: one line a run''s local day: the realized bill, the bill with no battery and perfect foresight''s, each at the '
  'realized end charge, the capture share and what was left, the peaks and how the battery was run. For a person, and for '
  'an agent that writes to one (rule 10: nothing in the engine reads it).';

REVOKE ALL ON FUNCTION public.ottoq_bess_hindsight_fire(uuid,uuid,date), public.ottoq_bess_hindsight_land(bigint,jsonb,integer,integer),
                       public.ottoq_bess_hindsight_sweep(uuid,text[],integer), public.ottoq_bess_hindsight_append_only()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_bess_hindsight_land(bigint,jsonb,integer,integer) TO service_role;
GRANT SELECT ON public.ottoq_bess_hindsight_board TO anon, authenticated, service_role;

INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('bess_hindsight_enabled',
        '0805 (B2): 1 = each local day this run''s battery ran is graded against perfect foresight once it is over '
        '(ottoq_bess_hindsight, by the hourly sweep through ottoq-intelligence''s battery planner). A measurement for '
        'people; nothing in the engine reads it. A person''s dial (rule 10).',
        0, 0, 1, 'public.ottoq_bess_hindsight_sweep', false);

-- ── V1: segment, fire and landing on the twin's latest run, rolled back with their rows ──
DO $v1$
DECLARE
  c_twin CONSTANT uuid := '11111111-1111-1111-1111-111111111111';
  c_tz CONSTANT text := 'America/Chicago';
  v_run uuid; v_day date; v_id bigint; v_id2 bigint; v_l jsonb; v_seg jsonb; v_calls0 bigint; v_steps int;
BEGIN
  SELECT e.sim_run_id, ((e.timestamp - interval '1 microsecond') AT TIME ZONE c_tz)::date INTO v_run, v_day
    FROM site_energy_snapshots e JOIN ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
   WHERE e.depot_id = c_twin
   GROUP BY 1, 2 HAVING count(*) >= 24 ORDER BY max(r.started_at) DESC NULLS LAST LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE '0805 V1: skipped, the twin depot has no run with a day of 24 snapshots';
    RETURN;
  END IF;
  v_calls0 := (SELECT count(*) FROM public.ottoq_model_call_ledger WHERE provider = 'intelligence_battery_planner'
                AND role = 'hindsight');
  BEGIN
    v_seg := public.ottoq_bess_hindsight_segment(v_run, c_twin, (v_day::timestamp) AT TIME ZONE c_tz,
                                                 ((v_day + 1)::timestamp) AT TIME ZONE c_tz);
    IF v_seg IS NULL OR (v_seg->'realized'->>'total_usd')::numeric <= 0 OR (v_seg->'no_battery'->>'total_usd')::numeric <= 0
       OR jsonb_array_length(v_seg->'request'->'load_kw') <> (v_seg->>'steps')::int
       OR jsonb_array_length(v_seg->'request'->'soc_floor_kwh') <> (v_seg->>'steps')::int THEN
      RAISE EXCEPTION '0805 V1: the segment is not well formed: %', left(v_seg::text, 600);
    END IF;
    v_steps := (v_seg->>'steps')::int;
    v_id := public.ottoq_bess_hindsight_fire(v_run, c_twin, v_day);
    IF v_id IS NULL OR (SELECT state FROM public.ottoq_bess_hindsight WHERE hindsight_id = v_id) <> 'pending' THEN
      RAISE EXCEPTION '0805 V1: the fire did not write a pending grade';
    END IF;
    IF public.ottoq_bess_hindsight_fire(v_run, c_twin, v_day) IS NOT NULL THEN
      RAISE EXCEPTION '0805 V1: a day was fired twice';
    END IF;
    v_l := public.ottoq_bess_hindsight_land(v_id, jsonb_build_object(
             'status', 'optimal', 'solver', 'glop', 'objective_usd', 100.0, 'solve_ms', 9,
             'peak_kw', jsonb_build_array(500), 'setpoint_kw', to_jsonb(array_fill(0::numeric, ARRAY[v_steps])),
             'soc_kwh', to_jsonb(array_fill(1000::numeric, ARRAY[v_steps + 1]))), 200, 800);
    IF v_l->>'state' <> 'graded' THEN RAISE EXCEPTION '0805 V1: a solved answer did not grade: %', v_l; END IF;
    v_l := public.ottoq_bess_hindsight_land(v_id, jsonb_build_object('status', 'optimal'), 200, 1);
    IF v_l->>'reason' <> 'not_pending' THEN RAISE EXCEPTION '0805 V1: a grade was landed twice: %', v_l; END IF;
    BEGIN
      UPDATE public.ottoq_bess_hindsight SET left_usd = 0 WHERE hindsight_id = v_id;
      RAISE EXCEPTION '0805 V1: a graded row was changed';
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;
    -- a failed answer: the same day again under another run id is impossible (the row exists); use the day before or after
    v_id2 := public.ottoq_bess_hindsight_fire(v_run, c_twin, v_day + 1);
    IF v_id2 IS NOT NULL THEN
      v_l := public.ottoq_bess_hindsight_land(v_id2, jsonb_build_object('error', 'boom'), 503, 5);
      IF v_l->>'state' <> 'failed' OR v_l->>'error' <> 'http_503' THEN
        RAISE EXCEPTION '0805 V1: a failed answer did not fail with its reason: %', v_l;
      END IF;
    END IF;
    IF (SELECT count(*) FROM public.ottoq_model_call_ledger WHERE provider = 'intelligence_battery_planner'
         AND role = 'hindsight') - v_calls0 <> (CASE WHEN v_id2 IS NULL THEN 1 ELSE 2 END) THEN
      RAISE EXCEPTION '0805 V1: the ledger does not hold one row per landing';
    END IF;
    RAISE NOTICE '0805 V1: run %, day %, % steps: realized %, no battery % (at the realized end %), peaks % and % kW',
      v_run, v_day, v_steps, v_seg->'realized'->'total_usd', v_seg->'no_battery'->'total_usd',
      v_seg->'no_battery'->'total_usd_at_realized_end', v_seg->'realized'->'peak30_kw', v_seg->'no_battery'->'peak30_kw';
    RAISE EXCEPTION USING ERRCODE = 'P0805', MESSAGE = 'roll back the probe';
  EXCEPTION WHEN SQLSTATE 'P0805' THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_bess_hindsight WHERE sim_run_id = v_run) THEN
    RAISE EXCEPTION '0805 V1: the probe''s rows were not rolled back';
  END IF;
END $v1$;

SELECT cron.schedule('ottoq-bess-hindsight-sweep', '17 * * * *',
  $cron$SELECT public.ottoq_bess_hindsight_sweep('11111111-1111-1111-1111-111111111111'::uuid);$cron$);

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0805_the_battery_grades_its_day_against_perfect_foresight', false, false,
        'B2. Each local day a run''s battery ran is graded once over, hourly, behind bess_hindsight_enabled (default 0): the '
        'realized bill, the bill with no battery and perfect foresight''s (ottoq-intelligence''s battery planner on the '
        'realized load), the capture share and what was left, kept whole in ottoq_bess_hindsight (evidence). No engine '
        'function changes.',
        now());

COMMIT;
