-- migration-version: PENDING
-- migration-name:    the_twins_afternoon_peaked_at_eight_pm_because_a_sine_was_written_where_its_comment_meant_a_cosine
--
-- 0436  **The twin's temperature is coldest at 08:00 and hottest at 20:00, because the diurnal swing is written as
--       a sine where its own comment asks for a 2 PM peak.** FINDINGS G171. Found while building 0435 (whose DR
--       reserve is season-gated rather than temperature-gated because of this).
--
-- ══ §1 WHAT IS WRONG ═════════════════════════════════════════════════════════
--
--   `twin.ottoq_sim_advance_weather_and_solar` adds the monthly NOAA half-range (`diurnal_half_c`, 6.25 °C for
--   September in `ottoq_feed_plan('ambient_temp_c')`) as
--       `diurnal_half_c * SIN(RADIANS(15.0 * (v_hour_of_day - 14)))   -- peak ~2 PM`.
--   sin(15°·(h−14)) is ZERO at 14:00, −1 at 08:00 and +1 at 20:00. So the swing peaks six hours late, and the
--   trough falls at 08:00, after sunrise, instead of before it.
--   Measured on run `7a42982a` (`ottoq_weather_snapshots`, hourly means, °C):
--       04 32.2 · 05 30.3 · 06 29.0 · 07 28.1 · 08 27.8 · 09 28.1 · 10 29.0 · 11 30.3 · 12 32.2
--   That is exactly symmetric about 08:00 — the sine's trough — and still rising at noon. With the fitted
--   amplitude (≈ 8.9 °C after the run's variability profile widens it), the same curve reaches its maximum at
--   20:00.
--   What it touches: the DR generator's hot-afternoon window (14–19 CT, ≥ 32 °C), building HVAC load, PV cell
--   temperature, and the charge thermal model. Each one sees the afternoon's heat about six hours late.
--
-- ══ §2 WHAT THIS DOES ═══════════════════════════════════════════════════════
--
--   SIN → COS on that one line. The swing now peaks at 14:00 and bottoms at 02:00, which is the comment's stated
--   intent. The integer hour, the amplitude source and the profile shaping are all unchanged.
--
-- ══ §3 forces_recert TRUE ══════════════════════════════════════════════════
--
--   Weather feeds every run, and so every atom downstream of energy and charging.
--
-- ══ §4 WHAT THIS DOES NOT DO ═══════════════════════════════════════════════════
--
--   1. The swing is still applied BEFORE `ottoq_apply_profile(run, 'ambient_temp_c', …)`, so a variability
--      profile that widens day-to-day spread widens the physical diurnal swing too: 6.25 °C becomes ≈ 8.9 °C on
--      `7a42982a`. Whether a "busy_day" should have a wider diurnal range is a calibration question, recorded in
--      G171(b), not answered here.
--   2. A cosine is symmetric; the real diurnal curve rises fast after sunrise and decays slowly after ~15:00.
--      Fitting that asymmetry needs hourly NOAA normals, which the feed plan does not carry.
--   3. The step is still hourly (integer `v_hour_of_day`).
--
-- ══ §5 PRE-FLIGHT, CHANGE, VERIFICATION ══════════════════════════════════════

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0436 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0436 P0: a determinism pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0436 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: md5 guard, and the anchor occurs exactly once ──
DO $$
DECLARE v_src text; v_n int;
        v_a text := E'* SIN(RADIANS(15.0 * (v_hour_of_day - 14)));   -- peak ~2 PM\n';
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_weather_and_solar';
  IF md5(v_src) <> '9bd0c9d99c8d929f4ae9a28e3836ceb7' THEN
    RAISE EXCEPTION '0436 P1: twin.ottoq_sim_advance_weather_and_solar md5 is % -- it changed since this file read it', md5(v_src);
  END IF;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  IF v_n <> 1 THEN RAISE EXCEPTION '0436 P1: anchor matched % times', v_n; END IF;
  -- no other function carries a diurnal sine of this shape
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq') AND p.proname <> 'ottoq_sim_advance_weather_and_solar'
     AND p.prosrc ~* 'SIN\(RADIANS\(15(\.0)?\s*\*\s*\(v_hour';
  IF v_n <> 0 THEN RAISE EXCEPTION '0436 P1: % other function(s) carry the same diurnal sine', v_n; END IF;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0436_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_weather_and_solar';

-- ── THE CHANGE ──
DO $splice$
DECLARE v_def text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_weather_and_solar';
  v_new := replace(v_def,
    E'* SIN(RADIANS(15.0 * (v_hour_of_day - 14)));   -- peak ~2 PM\n',
    E'* COS(RADIANS(15.0 * (v_hour_of_day - 14)));   -- peak 2 PM, trough 2 AM (0436: was SIN, which peaked at 8 PM)\n');
  IF v_new = v_def THEN RAISE EXCEPTION '0436: splice did not apply'; END IF;
  EXECUTE v_new;
END $splice$;

-- ── V1: the installed swing has its extremes where the comment says ──
DO $$
DECLARE v_src text; v_hmax int; v_hmin int;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_weather_and_solar';
  IF position('COS(RADIANS(15.0 * (v_hour_of_day - 14)))' IN v_src) = 0
  OR position('SIN(RADIANS(15.0 * (v_hour_of_day - 14)))' IN v_src) > 0 THEN
    RAISE EXCEPTION '0436 V1: the installed body does not carry the cosine';
  END IF;
  -- the same expression, evaluated over the 24 integer hours the function feeds it
  SELECT h INTO v_hmax FROM generate_series(0, 23) h ORDER BY cos(radians(15.0 * (h - 14))) DESC, h LIMIT 1;
  SELECT h INTO v_hmin FROM generate_series(0, 23) h ORDER BY cos(radians(15.0 * (h - 14))) ASC,  h LIMIT 1;
  IF v_hmax <> 14 OR v_hmin <> 2 THEN RAISE EXCEPTION '0436 V1: extremes at % and %, expected 14 and 2', v_hmax, v_hmin; END IF;
END $$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0436_the_twins_afternoon_peaked_at_eight_pm_because_a_sine_was_written_where_its_comment_meant_a_cosine',
   true,
   'Diurnal temperature swing SIN -> COS in twin.ottoq_sim_advance_weather_and_solar: peak 14:00, trough 02:00 '
   '(was 20:00 / 08:00). Weather feeds every run: recert.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- forces_recert TRUE: apply in the same window as other recert-forcing migrations so one sweep covers them.
-- After a fresh run: hourly means of ottoq_weather_snapshots.ambient_temp_c should peak at 14:00 CT.
-- Rollback: restore from ottoq_schema_snapshots label '0436_pre'.
