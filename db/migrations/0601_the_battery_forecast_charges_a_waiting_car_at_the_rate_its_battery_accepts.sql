-- migration-version: PENDING
-- migration-name:    the_battery_forecast_charges_a_waiting_car_at_the_rate_its_battery_accepts
--
-- 0601  **The battery's EV forecast put every car waiting on site onto a charger at 60% of the charger's nameplate, so a
--       car at 90% was forecast to draw 90-150 kW from a fast charger that gives it 15. Every tick saw a peak in the next
--       half hour that never came.** Overnight review 2026-09-30 (G311). Engine: ottoq_forecast_ev_queue_kw only.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0444 (G177) gave the battery's day plan the fleet waiting on site: `ottoq_forecast_ev_queue_kw` schedules each waiting
--   car and each return onto the depot's chargers as they free (`ottoq_ev_queue_schedule`), and the plan's EV forecast is
--   GREATEST(known, queue, last hour). The scheduler charges a job at a flat LEAST(charger, inlet, 250) x 0.60 for a
--   charger over 50 kW, whatever the car's battery. That is 0444's "average DCFC session power" for a car arriving low. It
--   is not the power a car near full takes: on the twin's taper (ottoq_sim_compute_charge_rate) a car at 80% accepts 22%
--   of its maximum and falls to 8% at 100%.
--
--   The cars actually waiting are mostly near full. Night 1's arm 3 (85a5d396, busy_day, 10 fast chargers, 12 hours):
--   74 of its 117 fast-charger sessions started at 80% or more, and those sessions averaged 14.8-16.3 kW. The smoke arm
--   (88e46ad3) logged its forecast every tick (`ottoq_energy_plan.forecast_load_kw`): from 11:25 to 13:00 UTC the next
--   half hour was forecast at 1,752-2,222 kW on every tick, while the site's actual net load, which the plan reads as step
--   1, ran 610-1,937 kW and fell every half hour. The level the battery defends and the peak it thinks is coming both come
--   from that forecast, so the plan held its energy for a peak that did not exist and charged under a level set by it.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `public.ottoq_queue_job_inlet_kw(vehicle, soc)`: the average power this car's battery accepts from `soc` to its
--       target on an uncapped (250 kW) fast charger, by the twin's own rate function at four evenly spaced states of
--       charge, averaged harmonically (time-weighted; the error against the 1%-step integral is under 5% above 60% and
--       under 10% from 20%), encoded as the inlet that makes the scheduler's arithmetic give that rate: the rate itself
--       at 30 kW or less (the scheduler charges <= 50 kW at 100%), rate / 0.60 above. NULL when the car is at target or
--       unknown, which leaves the job as it was.
--   (b) The forecast passes LEAST(inlet, that) as each job's inlet. So a job's rate never RISES: a car low enough that
--       its battery would take more than 0.60 x the inlet keeps 0444's figure. On an L2 charger the rate stays the L2
--       charger's own. Nothing else in the forecast moves, and `ottoq_ev_queue_schedule` is untouched.
--
--   The rate function is the one 0573 calibrates; after 0573 this reads the calibrated curve with no change here. That
--   matters for the size of the effect, not its direction: on the curve the twin runs tonight a car at 90% averages
--   8-15% of its maximum to 100%, which is what arm 3 measured; on 0573's measured tails a Model Y averages about 0.4
--   kW per usable kWh from 90% and the median curve about 0.5, so the phantom shrinks with 0573 and this keeps the
--   forecast on whichever curve the twin charges by. Executed against both curves in the tests.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: ottoq_forecast_ev_queue_kw is 0444's function unchanged (prosrc md5
--   ff2cfc482ce702e664b24ed514435569), its job query line occurs exactly once, the helper does not exist, not yet applied.
--   The forecast goes to `ottoq_schema_snapshots` as '0601_pre'.
--   V1: the new forecast passes the helper once, on the job query. V2, written to hold on whatever charge curve the twin
--   runs when this is applied (0573 recalibrates it, and goes first): every twin car charging to 100 is forecast at 90%
--   at exactly the twin's own harmonic-mean rate, never above 0444's rate for that car, and at least one strictly below;
--   an unknown car is left as 0444 had it.
--   Executed against the live source by tests/test_bess_half_hour_sql.py (tests/fixtures/bess_half_hour_stub.sql).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert TRUE and forces_dial_restart TRUE, for 0600's reason: the forecast's one caller is the day plan, which
--   certification runs at the twin depot now reach. Apply with 0600, 0573 and 0574.
--
-- ROLLBACK: DO $$ BEGIN EXECUTE (SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0601_pre'
--                                  AND object_name = 'ottoq_forecast_ev_queue_kw' ORDER BY snapshot_id DESC LIMIT 1); END $$;
--   DROP FUNCTION public.ottoq_queue_job_inlet_kw(uuid, numeric);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0601_the_battery_forecast_charges_a_waiting_car_at_the_rate_its_battery_accepts'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0601 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: 0444's forecast unchanged, the job line once, nothing here exists yet ──
DO $premises$
DECLARE
  v_src text;
  v_a text := E'    SELECT q.kwh, q.rel, q.inlet, q.kind FROM (\n';
  n int;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0601_the_battery_forecast_charges_a_waiting_car_at_the_rate_its_battery_accepts')
     OR to_regprocedure('public.ottoq_queue_job_inlet_kw(uuid,numeric)') IS NOT NULL THEN
    RAISE EXCEPTION '0601 P1: already applied';
  END IF;
  SELECT prosrc INTO v_src FROM pg_proc
   WHERE oid = 'public.ottoq_forecast_ev_queue_kw(uuid,uuid,timestamp with time zone,integer,numeric)'::regprocedure;
  IF md5(v_src) IS DISTINCT FROM 'ff2cfc482ce702e664b24ed514435569' THEN
    RAISE EXCEPTION '0601 P1: ottoq_forecast_ev_queue_kw is not 0444''s function (md5 %)', md5(v_src);
  END IF;
  n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF n <> 1 THEN RAISE EXCEPTION '0601 P1: the job query line matched % times', n; END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0601_pre', 'function', 'public', 'ottoq_forecast_ev_queue_kw',
       pg_get_functiondef('public.ottoq_forecast_ev_queue_kw(uuid,uuid,timestamp with time zone,integer,numeric)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_forecast_ev_queue_kw(uuid,uuid,timestamp with time zone,integer,numeric)'::regprocedure));

-- ── (a) the power a waiting car's battery accepts, as the scheduler's inlet ──
CREATE FUNCTION public.ottoq_queue_job_inlet_kw(p_vehicle_id uuid, p_soc numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $fn$
/* 0601 (G311): the average power this car's battery accepts from p_soc to its target on an uncapped (250 kW) fast
   charger, by the twin's rate function at four evenly spaced states of charge, averaged harmonically (time-weighted);
   returned as the inlet that makes ottoq_ev_queue_schedule's arithmetic give that rate (x 1.0 at 50 kW or less, x 0.60
   above). NULL when the car is at its target or unknown: the forecast then keeps 0444's job unchanged. */
DECLARE
  v record;
  i int;
  v_s numeric;
  v_kw numeric;
  v_inv numeric := 0;
  v_r numeric;
BEGIN
  SELECT COALESCE(x.target_soc, public.ottoq_default_target_soc()) AS tgt, COALESCE(x.battery_capacity_kwh, 75) AS kwh,
         COALESCE(x.inlet_max_kw, 150) AS inlet
    INTO v FROM public.vehicles x WHERE x.id = p_vehicle_id;
  IF NOT FOUND OR p_soc IS NULL OR v.tgt <= p_soc THEN RETURN NULL; END IF;
  FOR i IN 1..4 LOOP
    v_s := p_soc + (i - 0.5) * (v.tgt - p_soc) / 4.0;
    v_kw := public.ottoq_sim_compute_charge_rate(
              p_soc_pct := v_s, p_battery_temp_c := 27, p_ambient_temp_c := 22, p_charger_max_kw := 250,
              p_vehicle_max_kw := v.inlet, p_battery_capacity_kwh := v.kwh, p_battery_soh_pct := 95,
              p_noise_seed := 1, p_noise_salt := p_vehicle_id::text);
    IF v_kw IS NULL OR v_kw <= 0.5 THEN RETURN NULL; END IF;
    v_inv := v_inv + 1.0 / v_kw;
  END LOOP;
  v_r := 4.0 / v_inv;
  RETURN CASE WHEN v_r <= 30 THEN v_r ELSE v_r / 0.60 END;
END $fn$;

COMMENT ON FUNCTION public.ottoq_queue_job_inlet_kw(uuid, numeric) IS
'0601 (G311). The average power a waiting car''s battery accepts from its state of charge to its target on a fast charger, '
'encoded as the inlet ottoq_ev_queue_schedule needs to charge the job at that rate. The queue forecast passes '
'LEAST(inlet, this), so a job''s forecast rate never rises; a car at 90% is forecast at the ~15 kW it takes, not 90-150.';
REVOKE ALL ON FUNCTION public.ottoq_queue_job_inlet_kw(uuid, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_queue_job_inlet_kw(uuid, numeric) TO authenticated, service_role;

-- ── (b) the forecast passes it ──
DO $splice$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_forecast_ev_queue_kw(uuid,uuid,timestamp with time zone,integer,numeric)'::regprocedure);
  v_old text := E'    SELECT q.kwh, q.rel, q.inlet, q.kind FROM (\n';
  v_new text := E'    -- 0601 (G311): a job charges at the rate its battery accepts from its state of charge, never above 0444''s\n'
             || E'    SELECT q.kwh, q.rel, LEAST(q.inlet, public.ottoq_queue_job_inlet_kw(q.vid, q.soc)) AS inlet, q.kind FROM (\n';
BEGIN
  EXECUTE replace(v_def, v_old, v_new);
END $splice$;

-- ── V1: the helper is passed once, on the job query ──
DO $v1$
DECLARE
  v_src text;
  v_call text := 'LEAST(q.inlet, public.ottoq_queue_job_inlet_kw(q.vid, q.soc)) AS inlet';
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src FROM pg_proc
   WHERE oid = 'public.ottoq_forecast_ev_queue_kw(uuid,uuid,timestamp with time zone,integer,numeric)'::regprocedure;
  IF (length(v_src) - length(replace(v_src, v_call, ''))) / length(v_call) <> 1
     OR position(v_call IN v_src) > position('public.ottoq_ev_queue_schedule(' IN v_src) THEN
    RAISE EXCEPTION '0601 V1: the forecast does not pass the helper once, before it schedules';
  END IF;
END $v1$;

-- ── V2: the forecast rate is the twin's own, and it never rises ──
-- Checked against whatever charge curve the twin runs when this is applied (0573 recalibrates it and goes first), so the
-- assertions are the design's invariants, not tonight's numbers: (a) an unknown car is left as 0444 had it; (b) for every
-- twin car charging to 100, the rate the scheduler will charge at 90% is the harmonic mean of the twin's own rate function
-- at 91.25/93.75/96.25/98.75% on a 250 kW charger, computed here independently, to the watt; (c) that rate is never above
-- 0444's 0.60 x LEAST(inlet, 250); (d) at least one of them is strictly below it, or this file changed nothing.
DO $v2$
DECLARE
  v_bad text;
  v_lower int;
BEGIN
  IF public.ottoq_queue_job_inlet_kw('f0000000-0601-0601-0601-000000000001', 90) IS NOT NULL THEN
    RAISE EXCEPTION '0601 V2: an unknown car was given a rate';
  END IF;
  WITH c AS (
    SELECT v.id, LEAST(COALESCE(v.inlet_max_kw, 150), 250) * 0.60 AS old_kw,
           public.ottoq_queue_job_inlet_kw(v.id, 90) AS enc,
           4.0 / (SELECT sum(1.0 / public.ottoq_sim_compute_charge_rate(
                      -- the helper's own expression: the rate function salts its noise with the SoC's text
                      p_soc_pct := 90 + (g - 0.5) * (COALESCE(v.target_soc, public.ottoq_default_target_soc()) - 90) / 4.0,
                      p_battery_temp_c := 27, p_ambient_temp_c := 22,
                      p_charger_max_kw := 250, p_vehicle_max_kw := COALESCE(v.inlet_max_kw, 150),
                      p_battery_capacity_kwh := COALESCE(v.battery_capacity_kwh, 75), p_battery_soh_pct := 95,
                      p_noise_seed := 1, p_noise_salt := v.id::text))
                    FROM generate_series(1, 4) g) AS want_kw
      FROM public.vehicles v
     WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND COALESCE(v.target_soc, 100) = 100
       AND COALESCE(v.inlet_max_kw, 150) > 50
  ), d AS (
    SELECT c.*, CASE WHEN c.enc <= 30 THEN c.enc ELSE c.enc * 0.60 END AS new_kw FROM c WHERE c.enc IS NOT NULL
  )
  SELECT string_agg(d.id::text || ' ' || round(d.new_kw, 3) || '/' || round(d.want_kw, 3) || '/' || round(d.old_kw, 1), ', '),
         (SELECT count(*) FROM d WHERE d.new_kw < d.old_kw - 0.001)
    INTO v_bad, v_lower
    FROM d
   WHERE abs(d.new_kw - d.want_kw) > 0.001 OR d.new_kw > d.old_kw + 0.001;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0601 V2: forecast rates at 90%% off the twin''s own or above 0444''s (new/twin/0444 kW): %', v_bad;
  END IF;
  IF COALESCE(v_lower, 0) = 0 AND EXISTS (SELECT 1 FROM public.vehicles
                                           WHERE home_depot_id = '11111111-1111-1111-1111-111111111111') THEN
    RAISE EXCEPTION '0601 V2: no twin car at 90%% is forecast below 0444''s rate; this file changed nothing';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0601_the_battery_forecast_charges_a_waiting_car_at_the_rate_its_battery_accepts', true, true,
  'G311, overnight review 2026-09-30. ottoq_forecast_ev_queue_kw passes each queued job LEAST(inlet, '
  'ottoq_queue_job_inlet_kw(car, soc)): the average power its battery accepts from its state of charge to target, by the '
  'twin''s rate function, so a car at 90% is forecast at ~15 kW, not 0444''s flat 60% of nameplate. On the smoke arm the '
  'next half hour was forecast at 1,752-2,222 kW on every tick from 11:25 while actual net load fell from 1,937 to 610. '
  'TRUE/TRUE with 0600: the day plan is its one caller and certification runs at the twin reach it.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
