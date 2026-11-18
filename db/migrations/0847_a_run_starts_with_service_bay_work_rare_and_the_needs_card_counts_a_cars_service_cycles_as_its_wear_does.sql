-- migration-version: PENDING
-- migration-name:    0847_a_run_starts_with_service_bay_work_rare_and_the_needs_card_counts_a_cars_service_cycles_as_its_wear_does
--
-- 0847  **A run no longer starts with a fifth of the fleet owing the service bays. The needs profile draws open faults
--        for about 0.5% of cars, brake wear under the due line, and each car's place in its maintenance and calibration
--        cycles where the run's wear ledger puts it; and the needs card counts those two cycles as the wear ledger does,
--        in km and driving hours, instead of from a second draw and the calendar.** G555, CLAUDE.md rule 15.
--
-- WHY. Chase, the morning of 2026-11-18, on G555's proposal: "Sure, go fix those notes your proposed." Run 52dfc2d3 began
--   with 25 service-bay must-dos on 116 cars, against rule 15's two or three cars a day. Read on its seed
--   (8350472578738339482), on the needs card at 2b0c4017's clock, the twin depot, before this file:
--   - fault_repair, 12 cars. ottoq_seed_vehicle_need_profiles gives 5% of cars two open faults at severity 1 and 8% one at
--     severity 2 to 4: 14 cars with faults, 12 at severity 3 or worse, which the card makes must-do always.
--   - mechanical_pm, 6 cars. 4 come from the card's own count of km since maintenance: the seeder draws it up to 1.45
--     intervals, so 16 cars start past their interval and 4 past the 1.40 'critical' line. 3 come from brake wear at 82%
--     or more (drawn from 5% to 85%; 10 cars at or over the 80% due line). One car has both. G555 credited all six to
--     brake wear, which was wrong.
--   - sensor_calibration, 5 cars. The card counts calendar hours since the last calibration against calib_interval_h,
--     which the wear ledger counts in driving hours (0715), and the seeder puts the last calibration up to 1.5 intervals
--     back: 38 cars start past it and 5 past the 1.45 'critical' line.
--   - tire jobs, 2 cars (0842's rotation quarter and worn sets, at Chase's rates; not touched).
--   The run's wear ledger (ottoq_vehicle_wear, which ottoq_scenario_apply_fleet_overrides phases at a run's start when the
--   scenario asks, as busy_day does) starts every car at a uniformly random point inside both cycles. By its count no car
--   started past either: 0 of 116, the largest ratios 0.989 and just under 1. The arrival observers
--   (ottoq.ottoq_observe_asset, twin.ottoq_sim_observe_asset) and both recall functions already read the wear ledger
--   first. Only the needs card, which seats a car that is on the depot with no visit, read the profile's second draw.
--
-- §1 WHAT THIS DOES.
--   public.ottoq_seed_vehicle_need_profiles (profile_version 'v2'):
--     - open faults: two at severity 1 for r < 0.002, and one at severity 2 to 4 for r < 0.005. That is about 0.5% of
--       cars, not 13%: the steady state of the per-arrival rate that G555 proposed and Chase accepted, an assumption like
--       0838's two rates. The wear ledger's own DTC counts are read as before.
--     - brake wear: drawn from 5% to 79.9%, under the 80% due line, unless the car's maintenance is due (its km since
--       maintenance at or past its interval), when it is drawn from 5% to 85% as before.
--     - km since maintenance: the run's wear ledger's, when it has a row for the car; otherwise the point in the cycle that
--       the scenario's overrides give the wear ledger (the same seed, salt and interval), which is never past the
--       interval. Before, it was up to 1.45 intervals, plus the wear ledger's own count when there was a row.
--     - the last calibration: the same point in the calibration cycle the wear ledger is given, in hours before the draw.
--       Before, it was up to 1.5 intervals back.
--   public.ottoq_vehicle_needs_card: calib_ratio, pm_ratio and km_since_pm count as the wear ledger does when the card's
--     run has a row for the car: driving hours since the last calibration, and km since the last maintenance, against
--     the car's own intervals (its config first, as ottoq.ottoq_observe_asset reads them). With no row (production, or a
--     run whose scenario does not phase the ledger, before the car's first drive) they count from the profile as before.
--     calib_due_at is NULL when the ratio is in driving hours, because no calendar time is due then.
--   public.ottoq_service_reason (0846): the same counts, in the same words: "N driving hours since its last calibration,
--     due every M" and "N km since its last maintenance, due every M km".
--   Rules: nothing a car needs is skipped, deferred or shortened (9). A calibration or maintenance still falls due by its
--   own interval, a sensor under 89% or brakes at 80% still raise one, and a fault is always must-do. What changes is that
--   the starting draws are rare and the card measures an interval in the unit it is written in. No setting (10). One
--   demo run (12). No ceiling (13). No order across owners (14). Rule 15 is the reason for the file.
--   Not changed, and recorded as G556: a maintenance visit leaves brake_wear_pct as it was (ottoq_wear_mark_serviced resets
--   the km and the DTCs, never the brakes), so a car seated for its brakes would still read due after the visit. After
--   this file no car is drawn at the line (its km is never past its interval at a draw), and nothing raises brake wear
--   during a run, so the path cannot be reached. What a visit does to brake wear is Chase's to set.
--
-- §2 PRECONDITIONS AND CHECKS. P0 no certification in flight and no run at the twin depot running, paused or pending.
--   P1 the seeder's and the reason's bodies (md5 of prosrc) and the card's definition (md5 of pg_get_viewdef). P2 once.
--   V1 each anchor matched as often as written; the seeder stored as patched and, with its patches reversed, its
--   snapshot; the card's columns (names and types) unchanged, and its definition reads the wear ledger.
--   V2 a probe, rolled back, on the twin depot's newest run (none is live, P0), in three modes.
--     card: the needs card as it stands.
--     boot: what a run's start does, in its order (the boot draw seeds the profiles, then the scenario's overrides phase
--       the wear ledger), on that run's own seed and clock.
--     due: two cars put past their intervals by the wear ledger, one in driving hours since calibration and one in km
--       since maintenance.
--     Before: boot gives at least 5 service-bay must-dos from the starting draws. After: boot gives no calibration or
--     maintenance must-do, no car past either interval, no brakes at 80%, at most 3 fault repairs, the profile and the
--     wear ledger within 1 km and 1 hour of each other, and profile_version 'v2'; due makes both cars must-do, with the
--     reason in driving hours and in km. The card's read time is recorded before and after.
--
-- §3 CLASSIFICATION. forces_recert TRUE: the world each run starts from and the needs card's must-dos change, so every
--   canon re-certifies, as for 0837 and 0838. forces_dial_restart TRUE, likewise. Rule 12: nothing acts on either until
--   testing resumes. No evidence regime is recorded: ottoq_evidence_regimes is read only by the charge clock
--   (charge_time_v2), and nothing here changes a battery, a charger or the charge physics.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0847_pre'; DELETE FROM
--   public.ottoq_cert_lineage WHERE name LIKE '0847_%'. Profiles drawn after this file keep their 'v2' draw until the next
--   run re-seeds them.

BEGIN;
SET LOCAL lock_timeout = '5s';

DO $pre$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION '0847 P0: a certification is in flight'; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE depot_id = '11111111-1111-1111-1111-111111111111'
                                                   AND status IN ('running', 'paused', 'pending')) THEN
    RAISE EXCEPTION '0847 P0: a run is live at the twin depot; apply between runs';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_seed_vehicle_need_profiles(uuid)'))
     IS DISTINCT FROM '272c63e65ab0f26d688192045fd5915d' THEN
    RAISE EXCEPTION '0847 P1: public.ottoq_seed_vehicle_need_profiles is not the body this file was written against';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid = to_regprocedure('public.ottoq_service_reason(uuid,text,timestamptz)'))
     IS DISTINCT FROM '12af06afde239b2744b283770705135e' THEN
    RAISE EXCEPTION '0847 P1: public.ottoq_service_reason is not the body this file was written against';
  END IF;
  IF md5(pg_get_viewdef('public.ottoq_vehicle_needs_card'::regclass, true)) IS DISTINCT FROM 'aee9c8180c6ac1666d21df5168706372' THEN
    RAISE EXCEPTION '0847 P1: public.ottoq_vehicle_needs_card is not the view this file was written against';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name LIKE '0847_%') THEN
    RAISE EXCEPTION '0847 P2: already applied';
  END IF;
END $pre$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0847_pre', 'function', 'public', f, pg_get_functiondef(to_regprocedure(f)), md5(pg_get_functiondef(to_regprocedure(f)))
  FROM unnest(ARRAY['public.ottoq_seed_vehicle_need_profiles(uuid)', 'public.ottoq_service_reason(uuid,text,timestamptz)']) AS f
UNION ALL
SELECT '0847_pre', 'view', 'public', 'public.ottoq_vehicle_needs_card',
       'CREATE OR REPLACE VIEW public.ottoq_vehicle_needs_card AS ' || pg_get_viewdef('public.ottoq_vehicle_needs_card'::regclass, true),
       md5(pg_get_viewdef('public.ottoq_vehicle_needs_card'::regclass, true));

-- V2: the probe. It raises to roll its writes back; the answer comes back as the exception's detail.
CREATE FUNCTION pg_temp._0847_probe(p_mode text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  c_bay constant text[] := ARRAY['sensor_calibration', 'mechanical_pm', 'fault_repair', 'tire_rotation', 'tire_replacement',
                                 'cosmetic_repair'];
  v_run uuid; v_clock timestamptz; v_r jsonb; v_t0 timestamptz; v_ms numeric; v_detail text;
  v_a uuid; v_b uuid;
BEGIN
  BEGIN
    -- the run the needs card reads at the twin depot: the newest, a running one first (none is live, P0)
    SELECT r.sim_run_id, COALESCE(r.sim_clock_current, r.sim_clock_start) INTO v_run, v_clock
      FROM public.ottoq_sim_runs r WHERE r.depot_id = c_depot
     ORDER BY (r.status = 'running') DESC, r.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0847 V2: no run at the twin depot to probe with'; END IF;
    IF p_mode = 'boot' THEN
      -- a run's start, in ottoq_sim_run_scenario's order: the boot draw seeds the profiles, then the scenario's overrides
      -- phase the wear ledger
      DELETE FROM public.ottoq_vehicle_wear WHERE sim_run_id = v_run;
      PERFORM public.ottoq_seed_vehicle_need_profiles(v_run);
      PERFORM public.ottoq_scenario_apply_fleet_overrides(v_run);
    ELSIF p_mode = 'due' THEN
      SELECT min(x.vehicle_id::text)::uuid, max(x.vehicle_id::text)::uuid INTO v_a, v_b
        FROM (SELECT w.vehicle_id FROM public.ottoq_vehicle_wear w JOIN public.vehicles v ON v.id = w.vehicle_id
               WHERE w.sim_run_id = v_run AND v.home_depot_id = c_depot ORDER BY v.display_name LIMIT 2) x;
      IF v_a IS NULL OR v_a = v_b THEN RAISE EXCEPTION '0847 V2: the run has no two wear rows to put past an interval'; END IF;
      -- A half an interval past its calibration in driving hours; B half an interval past its maintenance in km
      UPDATE public.ottoq_vehicle_wear w
         SET hours_at_last_calibration = w.drive_hours_total - 1.5 * (
               SELECT COALESCE(NULLIF(v.config ->> 'calib_interval_h', '')::numeric, p.calib_interval_h)
                 FROM public.vehicles v JOIN public.vehicle_need_profile p ON p.vehicle_id = v.id WHERE v.id = v_a)
       WHERE w.vehicle_id = v_a AND w.sim_run_id = v_run;
      UPDATE public.ottoq_vehicle_wear w
         SET km_at_last_pm = w.drive_km_total - 1.5 * (
               SELECT COALESCE(NULLIF(v.config ->> 'pm_interval_km', '')::numeric, p.pm_interval_km)
                 FROM public.vehicles v JOIN public.vehicle_need_profile p ON p.vehicle_id = v.id WHERE v.id = v_b)
       WHERE w.vehicle_id = v_b AND w.sim_run_id = v_run;
    END IF;
    v_t0 := clock_timestamp();
    PERFORM count(*) FROM public.ottoq_vehicle_needs_card c WHERE c.depot_id = c_depot;
    v_ms := round(EXTRACT(EPOCH FROM clock_timestamp() - v_t0) * 1000);
    SELECT jsonb_build_object(
             'run', left(v_run::text, 8), 'ms', v_ms, 'cars', count(*),
             'wear_rows', (SELECT count(*) FROM public.ottoq_vehicle_wear w WHERE w.sim_run_id = v_run),
             'calib_must', count(*) FILTER (WHERE 'sensor_calibration' = ANY (c.must_do_now)),
             'pm_must', count(*) FILTER (WHERE 'mechanical_pm' = ANY (c.must_do_now)),
             'fault_must', count(*) FILTER (WHERE 'fault_repair' = ANY (c.must_do_now)),
             'tire_must', count(*) FILTER (WHERE c.must_do_now && ARRAY['tire_rotation', 'tire_replacement']),
             'bay_must_cars', count(*) FILTER (WHERE c.must_do_now && c_bay),
             'calib_past', count(*) FILTER (WHERE c.calib_ratio >= 1),
             'pm_past', count(*) FILTER (WHERE c.pm_ratio >= 1),
             'calib_ratio_max', max(c.calib_ratio), 'pm_ratio_max', max(c.pm_ratio),
             'calib_due_at_null', count(*) FILTER (WHERE c.calib_due_at IS NULL),
             'brake_ge_80', count(*) FILTER (WHERE c.brake_wear_pct >= 80),
             'with_faults', count(*) FILTER (WHERE COALESCE(array_length(c.open_fault_codes, 1), 0) > 0))
      INTO v_r
      FROM public.ottoq_vehicle_needs_card c WHERE c.depot_id = c_depot;
    IF p_mode = 'boot' THEN
      -- where the profile and the wear ledger put each car in its two cycles
      v_r := v_r || (
        SELECT jsonb_build_object(
                 'pm_gap_km_max', round(max(abs((p.odometer_km - p.km_at_last_pm) - (w.drive_km_total - COALESCE(w.km_at_last_pm, 0)))), 3),
                 'calib_gap_h_max', round(max(abs(EXTRACT(EPOCH FROM (p.drawn_at_sim_clock - p.last_calibration_at)) / 3600.0
                                                  - (w.drive_hours_total - COALESCE(w.hours_at_last_calibration, 0)))), 3),
                 'profile_version', min(p.profile_version), 'profiles', count(*))
          FROM public.vehicle_need_profile p
          JOIN public.ottoq_vehicle_wear w ON w.vehicle_id = p.vehicle_id AND w.sim_run_id = v_run
         WHERE p.drawn_for_run = v_run);
    ELSIF p_mode = 'due' THEN
      v_r := v_r || jsonb_build_object(
        'a_must', (SELECT to_jsonb(c.must_do_now) FROM public.ottoq_vehicle_needs_card c WHERE c.vehicle_id = v_a),
        'a_calib_ratio', (SELECT c.calib_ratio FROM public.ottoq_vehicle_needs_card c WHERE c.vehicle_id = v_a),
        'a_why', public.ottoq_service_reason(v_a, 'sensor_calibration', v_clock),
        'b_must', (SELECT to_jsonb(c.must_do_now) FROM public.ottoq_vehicle_needs_card c WHERE c.vehicle_id = v_b),
        'b_pm_ratio', (SELECT c.pm_ratio FROM public.ottoq_vehicle_needs_card c WHERE c.vehicle_id = v_b),
        'b_why', public.ottoq_service_reason(v_b, 'mechanical_pm', v_clock));
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'OQ847', MESSAGE = '0847 V2 probe', DETAIL = v_r::text;
  EXCEPTION WHEN SQLSTATE 'OQ847' THEN
    GET STACKED DIAGNOSTICS v_detail = PG_EXCEPTION_DETAIL;
    RETURN v_detail::jsonb;
  END;
END $f$;

CREATE TEMP TABLE _0847_out (phase text, r jsonb) ON COMMIT DROP;

DO $v2a$
DECLARE v_r jsonb := jsonb_build_object('card', pg_temp._0847_probe('card'), 'boot', pg_temp._0847_probe('boot'),
                                        'due', pg_temp._0847_probe('due'));
BEGIN
  INSERT INTO _0847_out VALUES ('before', v_r);
  IF COALESCE((v_r #>> '{boot,calib_must}')::int, 0) + COALESCE((v_r #>> '{boot,pm_must}')::int, 0)
     + COALESCE((v_r #>> '{boot,fault_must}')::int, 0) < 5 THEN
    RAISE EXCEPTION '0847 V2a: the starting draws were not as this file was written against: %', v_r;
  END IF;
  RAISE NOTICE '0847 V2a (before): %', v_r;
END $v2a$;

CREATE TEMP TABLE _0847_patch (fn text, ord int, n_expected int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0847_patch VALUES
-- the needs profile's starting draws
('public.ottoq_seed_vehicle_need_profiles(uuid)', 1, 1,
$o$c.id, 'v1', p_sim_run_id$o$,
$n$c.id, 'v2', p_sim_run_id$n$),
('public.ottoq_seed_vehicle_need_profiles(uuid)', 2, 1,
$o$round((1.50 * d.r_calib * d.cal_int)::numeric, 0)$o$,
$n$round((ottoq_sim_seeded_random(v_seed, 'calphase:' || d.id::text) * d.cal_int)::numeric, 0) /* 0847 (G555): where the run's wear ledger starts the car in its calibration cycle (ottoq_scenario_apply_fleet_overrides), never past it */$n$),
('public.ottoq_seed_vehicle_need_profiles(uuid)', 3, 1,
$o$round((1.45 * d.r_pm * d.pm_int$o$,
$n$round((CASE WHEN d.drive_km_total IS NOT NULL THEN d.drive_km_total - COALESCE(d.w_km_pm, 0)
                    ELSE ottoq_sim_seeded_random(v_seed, 'pmphase:' || d.id::text) * d.pm_int END  -- 0847 (G555): the wear ledger's km since maintenance when the run has a row for the car, else where ottoq_scenario_apply_fleet_overrides starts the car in its cycle (the same draw), never past it$n$),
('public.ottoq_seed_vehicle_need_profiles(uuid)', 4, 1,
$o$+ GREATEST(0, COALESCE(d.drive_km_total, 0) - COALESCE(d.w_km_pm, 0)))::numeric, 0) AS km_since_pm,$o$,
$n$)::numeric, 0) AS km_since_pm,$n$),
('public.ottoq_seed_vehicle_need_profiles(uuid)', 5, 1,
$o$round((5 + 80 * c.r_brake)::numeric, 1),$o$,
$n$CASE WHEN c.km_since_pm >= c.pm_int THEN round((5 + 80 * c.r_brake)::numeric, 1)
         ELSE round((5 + 74.9 * c.r_brake)::numeric, 1) END,   -- 0847 (G555): under the 80% due line unless the car's maintenance is due$n$),
('public.ottoq_seed_vehicle_need_profiles(uuid)', 6, 1,
$o$OR c.r_fault < 0.05
$o$,
$n$OR c.r_fault < 0.002   -- 0847 (G555): about 0.5% of cars start with an open fault (0.2% two at severity 1, 0.3% one at 2 to 4), not 13%
$n$),
('public.ottoq_seed_vehicle_need_profiles(uuid)', 7, 1,
$o$OR c.r_fault < 0.13
$o$,
$n$OR c.r_fault < 0.005
$n$),
('public.ottoq_seed_vehicle_need_profiles(uuid)', 8, 1,
$o$OR c.r_fault < 0.05 THEN 1$o$,
$n$OR c.r_fault < 0.002 THEN 1$n$),
('public.ottoq_seed_vehicle_need_profiles(uuid)', 9, 1,
$o$OR c.r_fault < 0.13 THEN$o$,
$n$OR c.r_fault < 0.005 THEN$n$),
-- the needs card counts the two cycles on the run's wear ledger when it has a row for the car
('public.ottoq_vehicle_needs_card', 1, 1,
$o$COALESCE(r_1.sim_clock, now()) AS sim_clock$o$,
$n$COALESCE(r_1.sim_clock, now()) AS sim_clock,
            wv.drive_hours_total AS w_drive_hours_total,
            wv.hours_at_last_calibration AS w_hours_at_last_calibration,
            wv.drive_km_total AS w_drive_km_total,
            wv.km_at_last_pm AS w_km_at_last_pm,
            NULLIF(v.config ->> 'calib_interval_h', '')::numeric AS cfg_calib_interval_h,
            NULLIF(v.config ->> 'pm_interval_km', '')::numeric AS cfg_pm_interval_km$n$),
('public.ottoq_vehicle_needs_card', 2, 1,
$o$LEFT JOIN run r_1 ON r_1.depot_id = v.home_depot_id$o$,
$n$LEFT JOIN run r_1 ON r_1.depot_id = v.home_depot_id
             LEFT JOIN public.ottoq_vehicle_wear wv ON wv.vehicle_id = p.vehicle_id AND wv.sim_run_id = r_1.sim_run_id$n$),
('public.ottoq_vehicle_needs_card', 3, 1,
$o$round(EXTRACT(epoch FROM b.sim_clock - b.last_calibration_at) / 3600.0 / NULLIF(b.calib_interval_h, 0::numeric), 3) AS calib_ratio$o$,
$n$round(CASE WHEN b.w_drive_hours_total IS NOT NULL
                  THEN (b.w_drive_hours_total - COALESCE(b.w_hours_at_last_calibration, 0::numeric))
                       / NULLIF(COALESCE(b.cfg_calib_interval_h, b.calib_interval_h), 0::numeric)
                  ELSE EXTRACT(epoch FROM b.sim_clock - b.last_calibration_at) / 3600.0 / NULLIF(b.calib_interval_h, 0::numeric)
             END, 3) AS calib_ratio$n$),
('public.ottoq_vehicle_needs_card', 4, 1,
$o$round(GREATEST(0::numeric, b.odometer_km - COALESCE(b.km_at_last_pm, 0::numeric)) / NULLIF(b.pm_interval_km, 0::numeric), 3) AS pm_ratio$o$,
$n$round(CASE WHEN b.w_drive_km_total IS NOT NULL
                  THEN (b.w_drive_km_total - COALESCE(b.w_km_at_last_pm, 0::numeric))
                       / NULLIF(COALESCE(b.cfg_pm_interval_km, b.pm_interval_km), 0::numeric)
                  ELSE GREATEST(0::numeric, b.odometer_km - COALESCE(b.km_at_last_pm, 0::numeric)) / NULLIF(b.pm_interval_km, 0::numeric)
             END, 3) AS pm_ratio$n$),
('public.ottoq_vehicle_needs_card', 5, 1,
$o$b.last_calibration_at + make_interval(hours => COALESCE(b.calib_interval_h, 250::numeric)::integer) AS calib_due_at$o$,
$n$CASE WHEN b.w_drive_hours_total IS NULL
                 THEN b.last_calibration_at + make_interval(hours => COALESCE(b.calib_interval_h, 250::numeric)::integer)
            END AS calib_due_at$n$),
('public.ottoq_vehicle_needs_card', 6, 1,
$o$GREATEST(0::numeric, b.odometer_km - COALESCE(b.km_at_last_pm, 0::numeric)) AS km_since_pm$o$,
$n$CASE WHEN b.w_drive_km_total IS NOT NULL THEN b.w_drive_km_total - COALESCE(b.w_km_at_last_pm, 0::numeric)
                 ELSE GREATEST(0::numeric, b.odometer_km - COALESCE(b.km_at_last_pm, 0::numeric))
            END AS km_since_pm$n$);

DO $seed$
DECLARE p record; v_def text; v_back text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_seed_vehicle_need_profiles(uuid)'::regprocedure);
  FOR p IN SELECT * FROM _0847_patch WHERE fn = 'public.ottoq_seed_vehicle_need_profiles(uuid)' ORDER BY ord LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> p.n_expected THEN
      RAISE EXCEPTION '0847 V1: the seeder''s anchor % matches % times, not %', p.ord, n, p.n_expected;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_seed_vehicle_need_profiles(uuid)'::regprocedure) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0847 V1: the seeder is not stored as patched';
  END IF;
  v_back := v_def;
  FOR p IN SELECT * FROM _0847_patch WHERE fn = 'public.ottoq_seed_vehicle_need_profiles(uuid)' ORDER BY ord DESC LOOP
    v_back := replace(v_back, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_back) IS DISTINCT FROM
     (SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0847_pre'
         AND object_name = 'public.ottoq_seed_vehicle_need_profiles(uuid)' ORDER BY snapshot_id DESC LIMIT 1) THEN
    RAISE EXCEPTION '0847 V1: the seeder with its patches reversed is not its snapshot';
  END IF;
END $seed$;

DO $card$
DECLARE p record; v_def text; v_cols_before text; v_cols_after text; n int;
BEGIN
  v_def := pg_get_viewdef('public.ottoq_vehicle_needs_card'::regclass, true);
  SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum) INTO v_cols_before
    FROM pg_attribute a WHERE a.attrelid = 'public.ottoq_vehicle_needs_card'::regclass AND a.attnum > 0 AND NOT a.attisdropped;
  FOR p IN SELECT * FROM _0847_patch WHERE fn = 'public.ottoq_vehicle_needs_card' ORDER BY ord LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> p.n_expected THEN
      RAISE EXCEPTION '0847 V1: the card''s anchor % matches % times, not %', p.ord, n, p.n_expected;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE 'CREATE OR REPLACE VIEW public.ottoq_vehicle_needs_card AS ' || rtrim(btrim(v_def), ';');
  SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum) INTO v_cols_after
    FROM pg_attribute a WHERE a.attrelid = 'public.ottoq_vehicle_needs_card'::regclass AND a.attnum > 0 AND NOT a.attisdropped;
  IF v_cols_after IS DISTINCT FROM v_cols_before THEN
    RAISE EXCEPTION '0847 V1: the card''s columns changed: % -> %', v_cols_before, v_cols_after;
  END IF;
  IF pg_get_viewdef('public.ottoq_vehicle_needs_card'::regclass, true) !~ 'ottoq_vehicle_wear'
     OR pg_get_viewdef('public.ottoq_vehicle_needs_card'::regclass, true) !~ 'w_drive_hours_total' THEN
    RAISE EXCEPTION '0847 V1: the card does not read the wear ledger';
  END IF;
END $card$;

COMMENT ON VIEW public.ottoq_vehicle_needs_card IS
  'One row per vehicle: every need dimension (energy / cleanliness / sensor+software / mechanical / operational commitment '
  '/ items) with a value AND a due/urgency signal, plus must_do_now escalation and whether the work fits before '
  'next_deploy_at. Run column is run_id (never sim_run_id) so ottoq_purge_prior_runs cannot target it. 0847: calib_ratio, '
  'pm_ratio and km_since_pm count driving hours and km on the run''s wear ledger when it has a row for the car (as '
  'ottoq.ottoq_observe_asset counts them), else from the profile; calib_due_at is NULL when the ratio is in driving hours.';
COMMENT ON FUNCTION public.ottoq_seed_vehicle_need_profiles(uuid) IS
  'Deterministically seeds public.vehicle_need_profile for every active autonomous vehicle at the run depot, from the run '
  'random_seed. Idempotent: same run+seed => same profile. 0847 (G555, profile_version v2): open faults for about 0.5% of '
  'cars, brake wear under the 80% due line unless maintenance is due, and each car''s place in its maintenance and '
  'calibration cycles where the run''s wear ledger puts it.';

CREATE OR REPLACE FUNCTION public.ottoq_service_reason(p_vehicle_id uuid, p_svc text, p_clock timestamptz) RETURNS text
LANGUAGE plpgsql STABLE SET search_path = pg_catalog, public AS $f$
-- 0846: why the needs card asks for a service-bay job, in plain words, from the inputs and lines it grades on
-- (public.ottoq_vehicle_needs_card). Several reasons are joined with '; '. NULL when it has nothing to say.
-- 0847: calibration and maintenance are counted as the card counts them: on the run's wear ledger when it has a row for
-- the car (driving hours and km, against the car's config intervals first), else from the profile as before.
DECLARE
  p public.vehicle_need_profile%ROWTYPE;
  w public.ottoq_vehicle_wear%ROWTYPE;
  v_parts text[] := '{}';
  v_h numeric; v_n int; v_cfg jsonb; v_km numeric; v_ratio numeric; v_codes text; v_int numeric;
BEGIN
  SELECT * INTO p FROM public.vehicle_need_profile WHERE vehicle_id = p_vehicle_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT v.config INTO v_cfg FROM public.vehicles v WHERE v.id = p_vehicle_id;
  -- 0847: the wear row the card reads, on the newest run at the car's depot, a running one first
  SELECT wr.* INTO w
    FROM public.ottoq_vehicle_wear wr
   WHERE wr.vehicle_id = p_vehicle_id
     AND wr.sim_run_id = (SELECT r.sim_run_id
                            FROM public.ottoq_sim_runs r JOIN public.vehicles v ON v.home_depot_id = r.depot_id
                           WHERE v.id = p_vehicle_id
                           ORDER BY (r.status = 'running') DESC, r.started_at DESC LIMIT 1);
  IF p_svc = 'fault_repair' THEN
    v_n := COALESCE(array_length(p.open_fault_codes, 1), 0);
    IF v_n > 0 THEN
      v_codes := CASE WHEN v_n = 1 THEN p.open_fault_codes[1]
                      ELSE array_to_string(p.open_fault_codes[1:v_n - 1], ', ') || ' and ' || p.open_fault_codes[v_n] END;
      v_parts := v_parts || format('%s %s%s', CASE WHEN v_n = 1 THEN 'open fault' ELSE 'open faults' END, v_codes,
                                   CASE WHEN p.worst_fault_severity BETWEEN 1 AND 5
                                        THEN format(', the worst at severity %s, where 1 is the most severe', p.worst_fault_severity)
                                        ELSE '' END);
    END IF;
    IF COALESCE(public.ottoq_vehicle_fault_open(v_cfg), false) THEN
      v_parts := v_parts || 'a vehicle fault is reported open'::text;
    END IF;
  ELSIF p_svc = 'sensor_calibration' THEN
    v_int := COALESCE(NULLIF(v_cfg ->> 'calib_interval_h', '')::numeric, p.calib_interval_h);
    IF w.drive_hours_total IS NOT NULL THEN
      IF COALESCE(v_int, 0) > 0 THEN
        v_h := w.drive_hours_total - COALESCE(w.hours_at_last_calibration, 0);
        IF public.ottoq_service_urgency('sensor_calibration', round(v_h / v_int, 3)) IN ('due', 'overdue', 'critical') THEN
          v_parts := v_parts || format('%s driving hours since its last calibration, due every %s', round(v_h), round(v_int));
        END IF;
      END IF;
    ELSIF p.last_calibration_at IS NOT NULL AND COALESCE(p.calib_interval_h, 0) > 0 AND p_clock IS NOT NULL THEN
      v_h := EXTRACT(EPOCH FROM (p_clock - p.last_calibration_at)) / 3600.0;
      IF public.ottoq_service_urgency('sensor_calibration', round(v_h / p.calib_interval_h, 3)) IN ('due', 'overdue', 'critical') THEN
        v_parts := v_parts || format('%s since its last calibration, due every %s',
                                     public.ottoq_span_words(v_h), public.ottoq_span_words(p.calib_interval_h));
      END IF;
    END IF;
    IF p.sensor_health_pct < 89 THEN
      v_parts := v_parts || format('sensor health %s%%, under the 89%% line', round(p.sensor_health_pct, 1));
    END IF;
  ELSIF p_svc = 'mechanical_pm' THEN
    v_int := COALESCE(NULLIF(v_cfg ->> 'pm_interval_km', '')::numeric, p.pm_interval_km);
    IF w.drive_km_total IS NOT NULL THEN
      IF COALESCE(v_int, 0) > 0 THEN
        v_km := w.drive_km_total - COALESCE(w.km_at_last_pm, 0);
        IF public.ottoq_service_urgency('mechanical_pm', round(v_km / v_int, 3)) IN ('due', 'overdue', 'critical') THEN
          v_parts := v_parts || format('%s km since its last maintenance, due every %s km', round(v_km), round(v_int));
        END IF;
      END IF;
    ELSIF COALESCE(p.pm_interval_km, 0) > 0 AND p.odometer_km IS NOT NULL THEN
      v_km := GREATEST(0, p.odometer_km - COALESCE(p.km_at_last_pm, 0));
      IF public.ottoq_service_urgency('mechanical_pm', round(v_km / p.pm_interval_km, 3)) IN ('due', 'overdue', 'critical') THEN
        v_parts := v_parts || format('%s km since its last maintenance, due every %s km', round(v_km), round(p.pm_interval_km));
      END IF;
    END IF;
    IF p.brake_wear_pct >= 80 THEN
      v_parts := v_parts || format('brake wear %s%%, at or over the 80%% line', round(p.brake_wear_pct));
    END IF;
  ELSIF p_svc = 'tire_replacement' THEN
    IF public.ottoq_tire_replacement_due(p.tire_tread_mm) THEN
      v_parts := v_parts || format('tread %s mm, under the 3.0 mm line', p.tire_tread_mm);
    END IF;
  ELSIF p_svc = 'tire_rotation' THEN
    v_ratio := public.ottoq_tire_rotation_ratio(p.last_tire_rotation_at, p_clock);
    IF v_ratio IS NOT NULL THEN
      v_h := EXTRACT(EPOCH FROM (p_clock - p.last_tire_rotation_at)) / 3600.0;
      v_parts := v_parts || CASE
        WHEN public.ottoq_service_urgency('tire_rotation', v_ratio) IN ('due', 'overdue', 'critical')
          THEN format('%s since its last rotation, due every %s',
                      public.ottoq_span_words(v_h), public.ottoq_span_words(public.ottoq_tire_rotation_interval_h()))
        ELSE format('due in %s, done now while the car is in the bay for its other work',
                    public.ottoq_span_words(public.ottoq_tire_rotation_interval_h() - v_h)) END;
    END IF;
  ELSIF p_svc = 'cosmetic_repair' THEN
    v_parts := v_parts || 'body damage was reported'::text;
  END IF;
  RETURN NULLIF(array_to_string(v_parts, '; '), '');
END $f$;

COMMENT ON FUNCTION public.ottoq_service_reason(uuid, text, timestamptz) IS
  '0846: why the needs card asks for a service-bay job, in plain words, from the inputs and lines it grades on. Read by '
  'the twin snapshot''s bay_seat.why and the needs card''s booking. Changes no decision. 0847: calibration and '
  'maintenance counted as the card counts them (driving hours and km on the run''s wear ledger when it has a row).';

DO $v2b$
DECLARE v_r jsonb := jsonb_build_object('card', pg_temp._0847_probe('card'), 'boot', pg_temp._0847_probe('boot'),
                                        'due', pg_temp._0847_probe('due'));
        v_before jsonb := (SELECT r FROM _0847_out WHERE phase = 'before');
BEGIN
  INSERT INTO _0847_out VALUES ('after', v_r);
  IF (v_r #>> '{boot,calib_must}')::int <> 0 OR (v_r #>> '{boot,pm_must}')::int <> 0
     OR (v_r #>> '{boot,calib_past}')::int <> 0 OR (v_r #>> '{boot,pm_past}')::int <> 0
     OR (v_r #>> '{boot,brake_ge_80}')::int <> 0 OR (v_r #>> '{boot,fault_must}')::int > 3 THEN
    RAISE EXCEPTION '0847 V2b boot: a run still starts with service-bay work drawn at its start: %', v_r;
  END IF;
  IF (v_r #>> '{boot,wear_rows}')::int > 0
     AND (COALESCE((v_r #>> '{boot,pm_gap_km_max}')::numeric, 99) > 1 OR COALESCE((v_r #>> '{boot,calib_gap_h_max}')::numeric, 99) > 1) THEN
    RAISE EXCEPTION '0847 V2b boot: the profile and the wear ledger put the cars at different points in their cycles: %', v_r;
  END IF;
  IF (v_r #>> '{boot,profile_version}') IS DISTINCT FROM 'v2' THEN
    RAISE EXCEPTION '0847 V2b boot: the profiles were not drawn by this file: %', v_r;
  END IF;
  IF NOT COALESCE((v_r #> '{due,a_must}') ? 'sensor_calibration', false)
     OR COALESCE(v_r #>> '{due,a_why}', '') NOT LIKE '% driving hours since its last calibration, due every %'
     OR NOT COALESCE((v_r #> '{due,b_must}') ? 'mechanical_pm', false)
     OR COALESCE(v_r #>> '{due,b_why}', '') NOT LIKE '% km since its last maintenance, due every % km%' THEN
    RAISE EXCEPTION '0847 V2b due: a car past its interval on the wear ledger is not must-do with its reason: %', v_r;
  END IF;
  IF (v_r #>> '{card,ms}')::numeric > 2 * (v_before #>> '{card,ms}')::numeric + 250 THEN
    RAISE EXCEPTION '0847 V2b card: the needs card reads in % ms, against % ms before', v_r #>> '{card,ms}', v_before #>> '{card,ms}';
  END IF;
  RAISE NOTICE '0847 V2b (after): %', v_r;
END $v2b$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0847_a_run_starts_with_service_bay_work_rare_and_the_needs_card_counts_a_cars_service_cycles_as_its_wear_does',
        true, true,
        'G555: the needs profile draws open faults for about 0.5% of cars (was 13%), brake wear under the 80% due line '
        || 'unless maintenance is due, and each car''s place in its maintenance and calibration cycles where the run''s wear '
        || 'ledger puts it (was up to 1.45 and 1.5 intervals); the needs card counts calibration in driving hours and '
        || 'maintenance in km on the wear ledger when it has a row for the car; ottoq_service_reason says so. Every run starts '
        || 'from a different world and the card''s must-dos change. Pre-image 0847_pre.', now());
COMMIT;
