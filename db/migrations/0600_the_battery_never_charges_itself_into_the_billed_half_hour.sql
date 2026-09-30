-- migration-version: PENDING
-- migration-name:    the_battery_never_charges_itself_into_the_billed_half_hour
--
-- 0600  **The battery's day plan treated the highest five-minute SAMPLE as the demand already billed, and refilled its
--       demand-response reserve as fast as that let it, so on the smoke day it charged into the half hours NES bills.**
--       Overnight review 2026-09-30 (G310). Engine: ottoq_bess_day_plan only.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   NES bills demand on the month's highest 30-minute average (ottoq_depot_tariffs.demand_basis = NCP_30min; $21.40 a kW
--   in summer). Under NES's real energy prices (0574) trading on price never pays (6.724/0.96 + 2.0 = 9.0 c to buy back
--   against an 8.182 c peak), so the battery's whole value is that demand charge. Three things in the plan worked against
--   it, all measured on the smoke arm (88e46ad3, busy_day, 20 fast chargers, from 6 AM CT):
--
--   (a) The "already-billed peak" was the wrong number. The plan reads `billing_period_peak_kw`, which
--       twin.ottoq_sim_advance_site_energy keeps as the month's highest single SAMPLE of grid draw. At 11:10 and 11:15
--       UTC the opening surge drew 2,415.1 and 2,404.9 kW for one five-minute sample each; the billed half hour
--       (11:10-11:40) averaged 1,960.8 kW. From then on the plan held its level at 2,415.1 kW, as though the 454 kW between
--       the two were already paid for, and charged under it.
--   (b) The DR-reserve refill took half the headroom under that level at once. The seed started the battery at 21%, under
--       the 600 kWh reserve 0435 holds for an afternoon demand-response call, so the plan was `reserve_protected` and
--       refilled at 0.5 x (level - net load - margin) every tick: 118, 285, 358, 494 kW in the first half hour after the
--       surge (11:25-11:40), 506, 697, 764, 755 kW averaged over the next four half hours. The DR window opens at 2 PM,
--       eight hours later. The billed half hour 11:10-11:40 carries 127 kW of that charging; the half hours after it
--       carry 506-764 kW, which is most of what 0577 measures as the peak "from an hour in" (1,414.9 kW against about
--       780 kW of site load).
--   (c) Nothing in the plan looked at the half hour a charge lands in. Every check was against the instantaneous net
--       load, so a charge right after a surge added to a half hour that the surge had already filled.
--
--   (The forecast the level came from was also wrong: it put a phantom 1,750-2,200 kW in every tick's next half hour.
--   That is 0601, the queue forecast, and this migration does not depend on it.)
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Three splices into ottoq_bess_day_plan, each at an anchor P1 proves occurs exactly once:
--
--   (1) The billed peak so far is the highest COMPLETED 30-minute average of this run's grid draw this month: the sweep
--       scorer's own window (ottoq_dial_arm_metrics, 0439; ottoq_arm_peak_profile, 0577), over windows whose end is at or
--       before the plan's clock. It replaces the sample maximum everywhere the plan uses it: the value of shaving above it
--       (ottoq_bess_plan_eval's p_ratchet), the level it defends, and the level it holds when the reserve is short. The
--       sample maximum is kept in the output as `ratchet_sample_kw` so the two can be compared on every tick.
--   (2) When the battery is under its DR reserve, it refills in the lowest-load half hours before the DR window opens
--       (valley filling): the level L such that the charge max(0, L - forecast net load), capped at the battery's power,
--       summed over the steps before the window, is the energy the reserve is short (AC kWh = deliverable / roundtrip).
--       It charges now only up to L. On a rolling horizon the deadline comes closer every tick, so L rises until the
--       reserve is full in time; if the steps left cannot hold the shortfall, L is the top and it charges at full power.
--       Inside or after the window's start it fills over the rest of the day, as before.
--   (3) No charge from the grid lifts the half hour it lands in above the billed peak or the charge's own target: with n
--       samples in the last 30 minutes summing S kW, a charge c with net load x now is capped so (S + x + c)/(n + 1) <=
--       max(billed peak, target). Every 30-minute window is the trailing window at the tick of its last sample, so this
--       bounds every window the battery's own charging could raise. The target is L for a reserve refill and the level less
--       the plan's margin for every other reason. A solar-surplus charge takes no power from the grid and is unchanged.
--
--   Nothing here can lower a vehicle's charge (rule 9): the plan sets the battery's setpoint and the level the
--   orchestrator defends. The EV allowance the orchestrator derives from the level is unchanged.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: ottoq_bess_day_plan is the function measured on 2026-09-30 (prosrc md5
--   8f136624ad07b64a3ef3022b3bab0753; 0573-0577 do not touch it), each of its four anchors occurs exactly once, and this
--   has not been applied. The plan goes to `ottoq_schema_snapshots` as '0600_pre'.
--   V1: the new source carries each splice once. V2: on the latest twin run with at least 12 energy samples, at a clock
--   an hour into it, the plan's ratchet_kw equals the highest completed 30-minute average computed here independently,
--   and is never above ratchet_sample_kw. V3: every splice sits where it was meant to (the ratchet after the snapshot
--   read, the refill and the half-hour cap after the charge line and before the solar-surplus branch).
--   Executed against the live source by tests/test_bess_half_hour_sql.py (tests/fixtures/bess_half_hour_stub.sql).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert TRUE and forces_dial_restart TRUE. 0444 could call a day-plan change FALSE because no certification
--   run reached plan mode; that premise no longer holds: `energy_reserve_shave` = 1 at the twin depot's scope (set
--   2026-09-26 by the promoter, CLAUDE.md rule 10), so every run there without a run-scoped 0 reaches this plan, and the
--   energy atom hashes its setpoints. Apply it in the same window as 0573 and 0574 (both TRUE/TRUE) so the canon is reset
--   once, and before night 2 (0575) so the planner night 2 measures is this one.
--
-- ROLLBACK: DO $$ BEGIN EXECUTE (SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0600_pre'
--                                  AND object_name = 'ottoq_bess_day_plan' ORDER BY snapshot_id DESC LIMIT 1); END $$;
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'bess_plan_bill_from_min';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0600_the_battery_never_charges_itself_into_the_billed_half_hour'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0600 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: the plan measured on 2026-09-30, every anchor once, not yet applied ──
DO $premises$
DECLARE
  v_src text;
  v_a text;
  n int;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0600_the_battery_never_charges_itself_into_the_billed_half_hour') THEN
    RAISE EXCEPTION '0600 P1: already applied';
  END IF;
  SELECT prosrc INTO v_src FROM pg_proc
   WHERE oid = 'public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure;
  IF md5(v_src) IS DISTINCT FROM '8f136624ad07b64a3ef3022b3bab0753' THEN
    RAISE EXCEPTION '0600 P1: ottoq_bess_day_plan is not the function measured on 2026-09-30 (md5 %)', md5(v_src);
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'bess_plan_bill_from_min') THEN
    RAISE EXCEPTION '0600 P1: bess_plan_bill_from_min is already catalogued';
  END IF;
  FOREACH v_a IN ARRAY ARRAY[
      E'  v_charge numeric := 0; v_head numeric; v_surplus numeric; v_why_charge text := NULL;\n',
      E'  v_ev_persist := COALESCE(v_ev_persist, v_ev_now);\n',
      E'    IF v_why_charge IS NOT NULL THEN v_charge := LEAST(v_pc, 0.5 * v_head, v_e_room / c_dt); END IF;\n',
      E'    ''ratchet_kw'', round(v_ratchet, 1), ''forecast_peak_kw'', round(v_lmax, 1), ''level_energy_bound'', v_level_bound,\n']
  LOOP
    n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
    IF n <> 1 THEN RAISE EXCEPTION '0600 P1: anchor matched % times: %', n, left(v_a, 70); END IF;
  END LOOP;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0600_pre', 'function', 'public', 'ottoq_bess_day_plan',
       pg_get_functiondef('public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure));

INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, agent_writable, affects, description)
VALUES ('bess_plan_bill_from_min', 0, 240, 0, false, 'ottoq_bess_day_plan',
  '0600 (G310, research wing): the battery day plan bills completed 30-minute windows starting this many minutes after '
  'the run''s sim_clock_start. 0 (the default) = the NES bill: every window. A test day that bills from an hour in '
  '(0576/0577) sets 60 run-scoped so its plan and its bill agree. Never set by the engine.');

DO $splice$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure);
  a1 text := E'  v_charge numeric := 0; v_head numeric; v_surplus numeric; v_why_charge text := NULL;\n';
  a2 text := E'  v_ev_persist := COALESCE(v_ev_persist, v_ev_now);\n';
  a3 text := E'    IF v_why_charge IS NOT NULL THEN v_charge := LEAST(v_pc, 0.5 * v_head, v_e_room / c_dt); END IF;\n';
  a4 text := E'    ''ratchet_kw'', round(v_ratchet, 1), ''forecast_peak_kw'', round(v_lmax, 1), ''level_energy_bound'', v_level_bound,\n';
BEGIN
  v_def := replace(v_def, a1, a1
    || E'  v_ratchet_sample numeric; v_n30 int; v_sum30 numeric; v_cap30 numeric; v_bill_from timestamptz;   /* 0600 */\n'
    || E'  v_need numeric; v_fill numeric; v_kdl int; v_flo numeric; v_fhi numeric; v_fmid numeric; v_fe numeric; v_hfk numeric;\n');
  v_def := replace(v_def, a2, a2
    || E'  /* 0600 (G310): the billed peak so far is the highest COMPLETED 30-minute average of this run''s grid draw this\n'
    || E'     month, the sweep scorer''s own window (0439, 0577), not billing_period_peak_kw, which the site-energy step keeps\n'
    || E'     as the highest single SAMPLE. On the smoke arm (88e46ad3) the sample was 2,415.1 kW when the billed half hour was\n'
    || E'     1,960.8, and the plan treated the difference as already paid for. */\n'
    || E'  v_ratchet_sample := v_ratchet;\n'
    || E'  v_bill_from := GREATEST(date_trunc(''month'', p_sim_clock),\n'
    || E'                  COALESCE((SELECT r.sim_clock_start FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id),\n'
    || E'                           ''-infinity''::timestamptz)\n'
    || E'                  + make_interval(mins => GREATEST(0, ottoq_policy_get(p_sim_run_id, ''bess_plan_bill_from_min'', 0))::int));\n'
    || E'  SELECT COALESCE(max(w.g30), 0) INTO v_ratchet\n'
    || E'    FROM (SELECT e.timestamp AS t,\n'
    || E'                 avg(GREATEST(COALESCE(e.grid_import_kw, 0), 0))\n'
    || E'                   OVER (ORDER BY e.timestamp RANGE BETWEEN CURRENT ROW AND interval ''29 minutes 59 seconds'' FOLLOWING) AS g30\n'
    || E'            FROM site_energy_snapshots e\n'
    || E'           WHERE e.depot_id = p_depot_id AND e.sim_run_id = p_sim_run_id\n'
    || E'             AND e.timestamp >= v_bill_from AND e.timestamp < p_sim_clock) w\n'
    || E'   WHERE w.t + interval ''30 minutes'' <= p_sim_clock;\n');
  v_def := replace(v_def, a3, a3
    || E'    /* 0600 (G310): a reserve short of its DR target refills in the lowest-load half hours before the DR window\n'
    || E'       (valley filling), not at half the headroom at once: the level L where max(0, L - net), capped at the\n'
    || E'       battery''s power, summed over those steps, is the AC energy the reserve is short. Charge now only up to L. */\n'
    || E'    IF v_why_charge = ''restore_dr_reserve'' AND v_charge > 0 THEN\n'
    || E'      v_need := GREATEST(0, v_res[1] - v_e_avail) / v_rt;\n'
    || E'      v_kdl := 0;\n'
    || E'      FOR k IN 1..v_n LOOP\n'
    || E'        v_t := p_sim_clock + ((k - 1) * 30) * interval ''1 minute'';\n'
    || E'        v_hfk := EXTRACT(HOUR FROM v_t AT TIME ZONE c_tz) + EXTRACT(MINUTE FROM v_t AT TIME ZONE c_tz) / 60.0;\n'
    || E'        EXIT WHEN v_hfk >= v_dr_s;\n'
    || E'        v_kdl := k;\n'
    || E'      END LOOP;\n'
    || E'      IF v_kdl = 0 THEN v_kdl := v_n; END IF;                  -- inside the window already: the rest of the day\n'
    || E'      v_flo := 0;\n'
    || E'      v_fhi := (SELECT max(x) FROM unnest(v_net[1:v_kdl]) AS x) + v_pc;\n'
    || E'      FOR i IN 1..40 LOOP\n'
    || E'        v_fmid := (v_flo + v_fhi) / 2.0;\n'
    || E'        SELECT COALESCE(sum(LEAST(v_pc, GREATEST(0, v_fmid - x))), 0) * c_dt INTO v_fe FROM unnest(v_net[1:v_kdl]) AS x;\n'
    || E'        IF v_fe >= v_need THEN v_fhi := v_fmid; ELSE v_flo := v_fmid; END IF;\n'
    || E'      END LOOP;\n'
    || E'      v_fill := v_fhi;\n'
    || E'      v_charge := LEAST(v_charge, GREATEST(0, v_fill - v_net[1]));\n'
    || E'    END IF;\n'
    || E'    /* 0600: no charge from the grid lifts the half hour it lands in above the billed peak or the charge''s own\n'
    || E'       target. Every 30-minute window is the trailing window at the tick of its last sample. */\n'
    || E'    IF v_charge > 0 THEN\n'
    || E'      SELECT count(*), COALESCE(sum(GREATEST(COALESCE(e.grid_import_kw, 0), 0)), 0) INTO v_n30, v_sum30\n'
    || E'        FROM site_energy_snapshots e\n'
    || E'       WHERE e.depot_id = p_depot_id AND e.sim_run_id = p_sim_run_id\n'
    || E'         AND e.timestamp > p_sim_clock - interval ''30 minutes'' AND e.timestamp < p_sim_clock;\n'
    || E'      v_cap30 := GREATEST(v_ratchet, CASE WHEN v_why_charge = ''restore_dr_reserve'' THEN v_fill\n'
    || E'                                          ELSE v_level - GREATEST(100, 0.10 * v_level) END);\n'
    || E'      v_charge := LEAST(v_charge, GREATEST(0, v_cap30 * (v_n30 + 1) - v_sum30 - v_net[1]));\n'
    || E'    END IF;\n');
  v_def := replace(v_def, a4, a4
    || E'    ''ratchet_sample_kw'', round(v_ratchet_sample, 1), ''refill_level_kw'', round(v_fill, 1),   /* 0600 */\n'
    || E'    ''half_hour_cap_kw'', round(v_cap30, 1),\n');
  EXECUTE v_def;
END $splice$;

-- ── V1: each splice once ──
DO $v1$
DECLARE
  v_src text;
  v_m text;
  n int;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc
   WHERE oid = 'public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure;
  FOREACH v_m IN ARRAY ARRAY['v_ratchet_sample := v_ratchet;', 'v_bill_from := GREATEST(', 'v_fill := v_fhi;',
                             'v_charge := LEAST(v_charge, GREATEST(0, v_cap30 * (v_n30 + 1) - v_sum30 - v_net[1]));',
                             '''half_hour_cap_kw'', round(v_cap30, 1),'] LOOP
    n := (length(v_src) - length(replace(v_src, v_m, ''))) / length(v_m);
    IF n <> 1 THEN RAISE EXCEPTION '0600 V1: % occurs % times in the new plan', v_m, n; END IF;
  END LOOP;
END $v1$;

-- ── V2: on a live twin run, the plan's billed peak is the scorer's completed-window figure, never above the sample ──
DO $v2$
DECLARE
  v_run uuid;
  v_t0 timestamptz;
  v_clock timestamptz;
  p jsonb;
  v_expect numeric;
BEGIN
  SELECT r.sim_run_id, r.sim_clock_start INTO v_run, v_t0
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
     AND (SELECT count(*) FROM public.site_energy_snapshots e
           WHERE e.sim_run_id = r.sim_run_id AND e.depot_id = r.depot_id) >= 12
   ORDER BY r.started_at DESC NULLS LAST, r.sim_run_id
   LIMIT 1;
  IF v_run IS NULL THEN
    RAISE EXCEPTION '0600 V2: no twin run with 12 energy samples to prove the billed peak against';
  END IF;
  SELECT min(e.timestamp) + interval '60 minutes' INTO v_clock FROM public.site_energy_snapshots e
   WHERE e.sim_run_id = v_run AND e.depot_id = '11111111-1111-1111-1111-111111111111';
  SELECT COALESCE(max(w.g30), 0) INTO v_expect
    FROM (SELECT e.timestamp AS t, avg(GREATEST(COALESCE(e.grid_import_kw, 0), 0))
                   OVER (ORDER BY e.timestamp RANGE BETWEEN CURRENT ROW AND interval '29 minutes 59 seconds' FOLLOWING) AS g30
            FROM public.site_energy_snapshots e
           WHERE e.sim_run_id = v_run AND e.depot_id = '11111111-1111-1111-1111-111111111111'
             AND e.timestamp >= GREATEST(date_trunc('month', v_clock), COALESCE(v_t0, '-infinity'::timestamptz)
                   + make_interval(mins => GREATEST(0, public.ottoq_policy_get(v_run, 'bess_plan_bill_from_min', 0))::int))
             AND e.timestamp < v_clock) w
   WHERE w.t + interval '30 minutes' <= v_clock;
  p := public.ottoq_bess_day_plan(v_run, '11111111-1111-1111-1111-111111111111', v_clock, NULL);
  IF NOT COALESCE((p ->> 'ok')::boolean, false) THEN
    RAISE EXCEPTION '0600 V2: the plan did not solve on run % at %: %', v_run, v_clock, p;
  END IF;
  IF (p ->> 'ratchet_kw')::numeric IS DISTINCT FROM round(v_expect, 1)
     OR (p ->> 'ratchet_kw')::numeric > (p ->> 'ratchet_sample_kw')::numeric THEN
    RAISE EXCEPTION '0600 V2: on run % at % the plan bills % kW (sample %), the completed half hours say %', v_run, v_clock,
      p ->> 'ratchet_kw', p ->> 'ratchet_sample_kw', round(v_expect, 1);
  END IF;
END $v2$;

-- ── V3: each splice where it was meant to be ──
DO $v3$
DECLARE
  v_src text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc
   WHERE oid = 'public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure;
  IF NOT (position('v_ratchet_sample := v_ratchet;' IN v_src) > position('INTO v_base_now, v_solar_now, v_ev_now, v_ratchet' IN v_src)
          AND position('v_ratchet_sample := v_ratchet;' IN v_src) < position('public.ottoq_bess_plan_eval(v_lmax' IN v_src)
          AND position('v_fill := v_fhi;' IN v_src) > position('v_charge := LEAST(v_pc, 0.5 * v_head, v_e_room / c_dt)' IN v_src)
          AND position('v_cap30 * (v_n30 + 1)' IN v_src) > position('v_fill := v_fhi;' IN v_src)
          AND position('v_cap30 * (v_n30 + 1)' IN v_src) < position('v_surplus := GREATEST(0, v_solar_now' IN v_src)) THEN
    RAISE EXCEPTION '0600 V3: a splice is out of place in the new plan';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0600_the_battery_never_charges_itself_into_the_billed_half_hour', true, true,
  'G310, overnight review 2026-09-30. ottoq_bess_day_plan: (1) the billed peak so far is the highest completed 30-minute '
  'average of the run''s grid draw (the scorer''s window), not the highest sample (smoke arm: 2,415.1 sample vs 1,960.8 '
  'billed); (2) a DR-reserve refill valley-fills the half hours before the DR window instead of taking half the headroom at '
  'once; (3) no grid charge lifts the half hour it lands in above max(billed peak, its target). TRUE/TRUE: '
  'energy_reserve_shave = 1 at the twin depot scope, so certification runs reach the plan. Apply with 0573/0574.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
