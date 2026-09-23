-- migration-version: 20260923042610
-- migration-name:    the_twins_september_afternoon_was_hotter_than_nashvilles_record_because_it_widened_around_the_yearly_mean
--
-- 0449  **The twin's September afternoon reached 45.3 °C, 4.7 °C past Nashville's record for the month, because the
--       run profile widened each hour's temperature around the all-year mean instead of the month's normal for that
--       hour.** `twin.ottoq_sim_advance_weather_and_solar` draws one ambient value per sim day from the month's NOAA
--       1991–2020 normal, adds the diurnal swing, and shapes the result through the run's variability profile:
--       `ottoq_apply_profile(run, 'ambient_temp_c', value)`. With no centre passed, `ottoq_apply_profile` widens around
--       the calibration's `segment='global'` mean, 17.53 °C, which is an all-year figure. busy_day sets
--       `_global.spread_mult` 1.4, so every September hour is pushed up by 0.4 × (T − 17.53), and the diurnal swing is
--       widened with it. FINDINGS G180.
--
-- ══ §1 MEASURED 2026-09-23 ON RUN 324eb0f1 (busy_day, twin depot) ════════════════════════════════════════════════
--
--   - The day card for sim 2026-09-22 (`ottoq_variability_cards`, `ambient_temp_c`, `day:2456`) is 31.1 °C against a
--     September mean of 22.8 °C and sigma of 3.3 °C (`ottoq_feed_plan('ambient_temp_c')->'monthly'->'09'`). That is a
--     +2.5 sigma draw. It is legitimate sampling and this file leaves it alone: busy_day's fixed seed always lands on
--     this hot day.
--   - The shaped values: 29.0 °C at 04:00 CT, 42.7 °C at 11:00 and 44.1 °C at 12:00. The DR call at 14:01 CT logged
--     45.3 °C. By the formula above, 14:00 is 17.53 + (31.1 + 6.25 − 17.53) × 1.4 = 45.28 °C. The month's record is
--     40.6 °C (`record_hi`, and `hard_max` on the `month:09` calibration row).
--   - What it moved (G180, G183): the charge model derates about 2% per °C of battery temperature above 35 °C, so
--     hot-afternoon DCFC delivered 35–50% of nominal. The battery's pack target is ambient + 3 + 12 × |p| / max, so
--     above about 45 °C it could not discharge at all without crossing the 48 °C hold. It sat out 120 of 147 commands
--     of a DR call at 91% SoC.
--
-- ══ §2 WHAT THIS DOES ════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) The widening is centred on the month's normal for the hour: `mean_c + diurnal_half_c × cos(15° × (h − 14))`.
--       That is the same diurnal term the function adds a few lines above. So the spread scales the day's anomaly (the
--       weather regime the day card models) and preserves the diurnal shape, which the sun fixes. The alternative,
--       centring on `mean_c` alone, would also widen the diurnal swing by 1.4. That doubles the stress in a way no
--       dataset behind the feed plan describes, so this file does not do it.
--   (2) The shaped value is then held inside the month's record (`record_lo`..`record_hi`). The clamp is skipped
--       when the run's profile declares its own `ambient_temp_c` knobs. A deliberate heat-wave or cold-snap profile
--       keeps its shift, floor and ceiling, and today no profile or scenario declares one. The variance widening can
--       no longer produce a day the historical record does not contain. A scenario that asks for one still can.
--   (3) The stale comment ("uses calibrated mean 23.24 for variance widening") goes with the call it described.
--   Unchanged: the day draw, the AR(1) chaining, the diurnal term, every other shaped variable, and
--   `ottoq_apply_profile` itself. Its other callers pass their own centres, so its generic semantics stay as they are.
--
--   Expected on busy_day's seed: 14:00 CT becomes 22.8 + 6.25 + (31.1 − 22.8) × 1.4 = 40.67 °C, which the clamp holds
--   at 40.6 °C. The 04:00 value barely moves (29.0 °C), because the day is hot all day. That is the +2.5 sigma draw,
--   not the widening.
--
-- ══ §3 forces_recert TRUE ════════════════════════════════════════════════════════════════════════════════════
--
--   Every canon run is shaped by this function. Any run with a spread profile changes its temperature, and with it
--   solar output, charge rates and battery thermal state.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0449 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%' OR query ILIKE '%ottoq_dial_experiment_runner%'
          OR query ILIKE '%ottoq_ab_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0449 P0: a pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0449 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: the weather function as read on 2026-09-23, the anchor unique; the feed plan carries what (1) and (2) read ──
DO $$
DECLARE v_src text; v_n int; v_a text; v_mo jsonb;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_weather_and_solar'::regproc;
  IF md5(v_src) <> '268e5c9be17bf63a9a60dc558c9dcaa4' THEN
    RAISE EXCEPTION '0449 P1: twin.ottoq_sim_advance_weather_and_solar md5 is %', md5(v_src);
  END IF;
  v_a := E'  -- A.8: shape ambient through the profile (uses calibrated mean 23.24 for\n'
      || E'  -- variance widening; honors shift/floor/ceiling from heat_wave/winter_storm).\n'
      || E'  v_ambient_c := ottoq_apply_profile(p_sim_run_id, ''ambient_temp_c'', v_ambient_c);\n';
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0449 P1: anchor matched % times', v_n; END IF;
  IF (SELECT count(*) FROM regexp_matches(v_src, 'ottoq_apply_profile\(p_sim_run_id, ''ambient_temp_c''', 'g')) <> 1 THEN
    RAISE EXCEPTION '0449 P1: ambient_temp_c is shaped somewhere this file does not cover';
  END IF;
  IF position(E'* COS(RADIANS(15.0 * (v_hour_of_day - 14)))' IN v_src) = 0 THEN
    RAISE EXCEPTION '0449 P1: the diurnal term this file mirrors is not the one in the function';
  END IF;
  FOR v_mo IN SELECT value FROM jsonb_each(public.ottoq_feed_plan('ambient_temp_c') -> 'monthly') LOOP
    IF (v_mo ->> 'mean_c') IS NULL OR (v_mo ->> 'diurnal_half_c') IS NULL
       OR (v_mo ->> 'record_lo') IS NULL OR (v_mo ->> 'record_hi') IS NULL
       OR (v_mo ->> 'record_lo')::numeric >= (v_mo ->> 'record_hi')::numeric THEN
      RAISE EXCEPTION '0449 P1: a month of the ambient feed plan lacks mean_c/diurnal_half_c/record_lo/record_hi: %', v_mo;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM jsonb_object_keys(public.ottoq_feed_plan('ambient_temp_c') -> 'monthly')) <> 12 THEN
    RAISE EXCEPTION '0449 P1: the ambient feed plan does not cover twelve months';
  END IF;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0449_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_advance_weather_and_solar'::regproc;

-- ── (1)+(2)+(3) WIDEN AROUND THE HOUR'S NORMAL, INSIDE THE MONTH'S RECORD ──
DO $splice$
DECLARE v_def text; v_new text;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_sim_advance_weather_and_solar'::regproc);
  v_new := replace(v_def,
    E'  -- A.8: shape ambient through the profile (uses calibrated mean 23.24 for\n'
    || E'  -- variance widening; honors shift/floor/ceiling from heat_wave/winter_storm).\n'
    || E'  v_ambient_c := ottoq_apply_profile(p_sim_run_id, ''ambient_temp_c'', v_ambient_c);\n',
    E'  /* A.8, as 0449 (G180) re-centred it: shape ambient through the run''s profile around this month''s normal for\n'
    || E'     this hour (the feed plan''s mean_c plus the diurnal term above), not the all-year calibration mean (17.5 C),\n'
    || E'     which pushed every September hour up by 0.4 x (T - 17.5) under busy_day''s spread 1.4. Then hold the value\n'
    || E'     inside the month''s record, unless the profile declares its own ambient knobs: a deliberate heat or cold\n'
    || E'     scenario keeps its shift/floor/ceiling; variance widening alone never makes a day the record lacks. */\n'
    || E'  DECLARE\n'
    || E'    v_mo_t   jsonb := ottoq_feed_plan(''ambient_temp_c'') -> ''monthly''\n'
    || E'                        -> to_char(p_sim_clock_now AT TIME ZONE ''America/Chicago'', ''MM'');\n'
    || E'    v_clim_c numeric;\n'
    || E'    v_amb_kn jsonb;\n'
    || E'  BEGIN\n'
    || E'    v_clim_c := (v_mo_t ->> ''mean_c'')::numeric\n'
    || E'              + COALESCE((v_mo_t ->> ''diurnal_half_c'')::numeric, 5.0) * COS(RADIANS(15.0 * (v_hour_of_day - 14)));\n'
    || E'    v_ambient_c := ottoq_apply_profile(p_sim_run_id, ''ambient_temp_c'', v_ambient_c, v_clim_c);\n'
    || E'    SELECT knobs -> ''ambient_temp_c'' INTO v_amb_kn FROM ottoq_variability_profiles WHERE sim_run_id = p_sim_run_id;\n'
    || E'    IF v_mo_t IS NOT NULL AND COALESCE(v_amb_kn, ''{}''::jsonb) = ''{}''::jsonb THEN\n'
    || E'      v_ambient_c := LEAST(GREATEST(v_ambient_c, (v_mo_t ->> ''record_lo'')::numeric),\n'
    || E'                           (v_mo_t ->> ''record_hi'')::numeric);\n'
    || E'    END IF;\n'
    || E'  END;\n');
  IF v_new = v_def OR position('ottoq_apply_profile(p_sim_run_id, ''ambient_temp_c'', v_ambient_c, v_clim_c)' IN v_new) = 0 THEN
    RAISE EXCEPTION '0449: the weather splice did not apply';
  END IF;
  EXECUTE v_new;
END $splice$;

-- ── V1: what shipped is what the header says (comment-stripped) ──
DO $$
DECLARE v_src text;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_weather_and_solar'::regproc;
  IF position('ottoq_apply_profile(p_sim_run_id, ''ambient_temp_c'', v_ambient_c, v_clim_c)' IN v_src) = 0
     OR position('ottoq_apply_profile(p_sim_run_id, ''ambient_temp_c'', v_ambient_c);' IN v_src) > 0
     OR position('(v_mo_t ->> ''record_hi'')::numeric' IN v_src) = 0
     OR position('(v_mo_t ->> ''record_lo'')::numeric' IN v_src) = 0
     OR position('ottoq_apply_profile(p_sim_run_id, ''ambient_temp_c''' IN v_src)
        < position('* COS(RADIANS(15.0 * (v_hour_of_day - 14)));' IN v_src) THEN
    RAISE EXCEPTION '0449 V1: the weather function does not centre and clamp ambient as the header says';
  END IF;
END $$;

-- ── V2: the function itself, on the latest finished spread-profiled twin run with an ambient day card, at 04:00 and
--        14:00 CT of that card's day. Rolled back. The expectation is computed from the card, the feed plan and the
--        profile, not copied from a run.
DO $v2$
DECLARE
  r record; v_mo jsonb; v_clock timestamptz; v_h int; v_got numeric; v_want numeric; v_clim numeric; v_card numeric;
BEGIN
  SELECT s.sim_run_id, s.depot_id, (s.sim_clock_start AT TIME ZONE 'America/Chicago')::date AS day_ct,
         (vp.knobs #>> '{_global,spread_mult}')::numeric AS spread, c.value AS card, c.bucket_key
    INTO r
    FROM public.ottoq_sim_runs s
    JOIN public.ottoq_variability_profiles vp ON vp.sim_run_id = s.sim_run_id
    JOIN public.ottoq_variability_cards c ON c.sim_run_id = s.sim_run_id AND c.var_key = 'ambient_temp_c'
                                         AND c.scope_instance = 'global'
                                         AND c.bucket_key = 'day:' || ((s.sim_clock_start AT TIME ZONE 'America/Chicago')::date
                                                                       - DATE '2020-01-01')
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111' AND s.status NOT IN ('running','paused')
     AND (vp.knobs #>> '{_global,spread_mult}')::numeric > 1
     AND COALESCE(vp.knobs -> 'ambient_temp_c', '{}'::jsonb) = '{}'::jsonb
   ORDER BY s.started_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RAISE NOTICE '0449 V2: no finished spread-profiled twin run with an ambient day card to probe; V1 stands alone';
    RETURN;
  END IF;
  v_mo := public.ottoq_feed_plan('ambient_temp_c') -> 'monthly' -> to_char(r.day_ct, 'MM');
  BEGIN
    FOREACH v_h IN ARRAY ARRAY[4, 14] LOOP
      v_clock := (r.day_ct + make_interval(hours => v_h)) AT TIME ZONE 'America/Chicago';
      -- the probe must read the stored day card, so it is dealt on that card's own UTC day
      IF 'day:' || (v_clock::date - DATE '2020-01-01') <> r.bucket_key THEN
        RAISE NOTICE '0449 V2: % CT falls on another card day; skipped', v_h;
        CONTINUE;
      END IF;
      PERFORM twin.ottoq_sim_advance_weather_and_solar(p_depot_id => r.depot_id, p_sim_run_id => r.sim_run_id,
                                                       p_sim_clock_now => v_clock);
      SELECT w.ambient_temp_c INTO v_got FROM public.ottoq_weather_snapshots w
       WHERE w.sim_run_id = r.sim_run_id AND w.depot_id = r.depot_id AND w.sim_clock_at = v_clock
       ORDER BY w.snapshot_id DESC LIMIT 1;
      SELECT c.value INTO v_card FROM public.ottoq_variability_cards c
       WHERE c.sim_run_id = r.sim_run_id AND c.var_key = 'ambient_temp_c' AND c.scope_instance = 'global'
         AND c.bucket_key = r.bucket_key;
      -- clim + (raw - clim) x spread, where raw = card + diurnal and clim = mean_c + diurnal; held inside the record
      v_clim := (v_mo ->> 'mean_c')::numeric + (v_mo ->> 'diurnal_half_c')::numeric * COS(RADIANS(15.0 * (v_h - 14)));
      v_want := LEAST(GREATEST(v_clim + (v_card + (v_mo ->> 'diurnal_half_c')::numeric * COS(RADIANS(15.0 * (v_h - 14)))
                                         - v_clim) * r.spread,
                               (v_mo ->> 'record_lo')::numeric),
                      (v_mo ->> 'record_hi')::numeric);
      IF v_got IS NULL OR abs(v_got - v_want) > 0.051 OR v_got > (v_mo ->> 'record_hi')::numeric THEN
        RAISE EXCEPTION '0449 V2: run % at % CT wrote %, expected % (card %, spread %)',
          r.sim_run_id, v_h, v_got, round(v_want, 2), v_card, r.spread;
      END IF;
      RAISE NOTICE '0449 V2: run % at %:00 CT -> % C (expected %, card %, spread %, record %)',
        left(r.sim_run_id::text, 8), v_h, v_got, round(v_want, 2), v_card, r.spread, v_mo ->> 'record_hi';
    END LOOP;
    RAISE EXCEPTION USING MESSAGE = '0449_probe_rollback';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> '0449_probe_rollback' THEN RAISE; END IF;
  END;
END $v2$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0449_the_twins_september_afternoon_was_hotter_than_nashvilles_record_because_it_widened_around_the_yearly_mean',
   true,
   'G180: twin.ottoq_sim_advance_weather_and_solar passes ottoq_apply_profile the month''s normal for the hour '
   '(mean_c + diurnal term) as the widening centre, instead of letting it fall back to the all-year calibration '
   'mean, and holds the result inside the month''s record_lo..record_hi unless the run profile declares its own '
   'ambient knobs. TRUE: every run with a spread profile changes temperature, and with it solar, charge rates and '
   'battery thermal state.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- forces_recert TRUE. Live proof on the next busy_day demo run: the hourly mean at 14:00 CT is at or below 40.6 °C, and
-- no ottoq_weather_snapshots row exceeds the month's record_hi. Rollback: restore the weather function from
-- ottoq_schema_snapshots label '0449_pre'.
