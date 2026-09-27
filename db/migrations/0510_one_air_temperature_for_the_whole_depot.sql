-- migration-version: 20260927030227
-- migration-name:    one_air_temperature_for_the_whole_depot
--
-- 0510  **A charge, a car on the road and a telemetry packet each drew their own air temperature from the whole year,
--       per car, and ignored the depot's weather (G241); and the depot's weather started every run on a whole-year
--       day (G242).** `db/checks/0376`.
--
-- ══ §1 WHAT WAS WRONG (measured 2026-09-27 on the nine surviving operator runs) ═════════════════════════════════
--
--   G241. `twin.ottoq_sim_start_charge_session`, `twin.ottoq_sim_advance_deployed_telemetry` and
--   `twin.ottoq_sim_emit_telemetry` each called `ottoq_sample_calibrated('ambient_temp_c', 'global', ...)` salted per
--   car and clock: noaa_nws's whole year, 17.5 C, SD 11.4, -13.3 to 38.3. On every operator run the charges' ambient
--   spanned about -13 to +38 C within one morning, uncorrelated with the depot's weather (-0.19 to +0.15). That draw set
--   each charge's battery temperature and so its pace, and each car's climate load on the road.
--
--   G242. The weather tick deals the day's temperature card with the month's segment, but `ottoq_run_boot_draw` deals
--   every run/day/block world card before tick 1 with the segment 'global', and `ottoq_twin_deal` returns the card
--   already dealt. 9 of 9 operator runs' day cards equal their seed's whole-year draw (-8.29 to 33.38 C); September's
--   would have been 15.1 to 28.0.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `twin.ottoq_sim_site_ambient_c(run, clock)`, new: the depot's air temperature at a sim clock, the one value
--       every car at the depot shares. The run's latest weather reading at or before the clock; before the run's first
--       reading, the day's temperature card (dealt at boot, now from the month). NULL outside a run, where each caller
--       keeps its own default.
--   (2) The charge start, the car on the road and the telemetry packet read it instead of drawing their own. A charge's
--       battery still starts at the air plus a per-car offset, and still warms as it charges: a battery's thermal
--       state varies by car; the air does not.
--   (3) The boot draw deals the temperature card from the month of the run's start in the depot's time zone, the
--       question the weather tick already asks. Every other world card is dealt as before.
--
--   The energy forecasts and orchestration read a session's recorded ambient, so they follow the session.
--
-- ══ §3 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   The day's weather, every charge's pace and every car's drain move on every column: energy, sessions, SDRs,
--   commands and decisions can all move. What moves is read in the sweep.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0510 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P1: no run is live (the world tick calls all four; V3 plants its cases on a stopped run, rolled back) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN
    RAISE EXCEPTION '0510 P1: a run is live; apply between runs';
  END IF;
END $live$;

-- ── P2: the bodies this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)'::regprocedure))
     <> '7347b461d79a189fd4abb06ed747c991' THEN
    RAISE EXCEPTION '0510 P2: twin.ottoq_sim_start_charge_session is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure))
     <> '9bd38c95d71a95a863129ebc2f6a072f' THEN
    RAISE EXCEPTION '0510 P2: twin.ottoq_sim_advance_deployed_telemetry is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('twin.ottoq_sim_emit_telemetry(uuid,uuid,timestamptz,numeric,numeric,numeric,numeric,text,text[],text)'::regprocedure))
     <> 'c4ab7ab5024c5ce3536d8667a6c6644c' THEN
    RAISE EXCEPTION '0510 P2: twin.ottoq_sim_emit_telemetry is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_run_boot_draw(uuid)'::regprocedure))
     <> '49df3b3781cda7cbcf39e48666b15482' THEN
    RAISE EXCEPTION '0510 P2: public.ottoq_run_boot_draw is not the body this file patches';
  END IF;
  IF to_regprocedure('twin.ottoq_sim_site_ambient_c(uuid,timestamptz)') IS NOT NULL THEN
    RAISE EXCEPTION '0510 P2: twin.ottoq_sim_site_ambient_c already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0510_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)'::regprocedure,
                 'twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure,
                 'twin.ottoq_sim_emit_telemetry(uuid,uuid,timestamptz,numeric,numeric,numeric,numeric,text,text[],text)'::regprocedure,
                 'public.ottoq_run_boot_draw(uuid)'::regprocedure);

-- (1) the depot's air temperature
CREATE FUNCTION twin.ottoq_sim_site_ambient_c(p_sim_run_id uuid, p_clock timestamptz)
RETURNS numeric
LANGUAGE sql STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
  /* 0510 (G241): the depot's air temperature at a sim clock, the one value every car at the depot shares: the run's
     latest weather reading at or before the clock; before the run's first reading, the day's temperature card, which
     the boot draw deals from the month (G242) and the weather tick shapes from. NULL outside a run. */
  SELECT COALESCE(
    (SELECT w.ambient_temp_c FROM public.ottoq_weather_snapshots w
      WHERE w.sim_run_id = p_sim_run_id AND w.sim_clock_at <= p_clock
      ORDER BY w.sim_clock_at DESC LIMIT 1),
    (SELECT c.value FROM public.ottoq_variability_cards c
      WHERE c.sim_run_id = p_sim_run_id AND c.var_key = 'ambient_temp_c' AND c.scope_instance = 'global'
        AND c.bucket_key = 'day:' || (p_clock::date - DATE '2020-01-01')))
$fn$;
REVOKE ALL ON FUNCTION twin.ottoq_sim_site_ambient_c(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION twin.ottoq_sim_site_ambient_c(uuid, timestamptz) TO service_role;

-- (2) the three consumers
DO $patch2$
DECLARE
  v_sigs text[] := ARRAY[
    'twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)',
    'twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)',
    'twin.ottoq_sim_emit_telemetry(uuid,uuid,timestamptz,numeric,numeric,numeric,numeric,text,text[],text)'];
  v_old text[] := ARRAY[
    $o1$  v_ambient_temp := ottoq_sample_calibrated('ambient_temp_c', 'global',
    abs(hashtextextended(COALESCE((SELECT random_seed::text FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), '42'), 42)), 'ambient:' || p_vehicle_id::text || ':' || twin.ottoq_sim_clock_salt(p_sim_run_id, v_clock));$o1$,
    $o2$    v_ambient := COALESCE(
      ottoq_sample_calibrated('ambient_temp_c','global', v_seed, 'amb:'||v_salt),
      22);$o2$,
    $o3$  -- Sample real ambient from NOAA calibration
  v_ambient_temp := ottoq_sample_calibrated('ambient_temp_c', 'global', v_seed,
    'amb:' || p_sim_clock::text);$o3$];
  v_new text[] := ARRAY[
    $n1$  -- 0510 (G241): the air a car charges in is the depot's, as its weather reads it, not a per-car draw from the whole
  -- year. The battery's own offset below still varies by car.
  v_ambient_temp := twin.ottoq_sim_site_ambient_c(p_sim_run_id, v_clock);$n1$,
    $n2$    v_ambient := COALESCE(
      twin.ottoq_sim_site_ambient_c(p_sim_run_id, p_sim_clock_now),   -- 0510 (G241): the depot's air, not a per-car draw
      22);$n2$,
    $n3$  -- 0510 (G241): the depot's air temperature, as its weather reads it
  v_ambient_temp := twin.ottoq_sim_site_ambient_c(p_sim_run_id, p_sim_clock);$n3$];
  v_def text; i int; n int;
BEGIN
  FOR i IN 1 .. 3 LOOP
    v_def := pg_get_functiondef(v_sigs[i]::regprocedure);
    n := (length(v_def) - length(replace(v_def, v_old[i], ''))) / length(v_old[i]);
    IF n <> 1 THEN RAISE EXCEPTION '0510: consumer patch % (%) matched % times, not once', i, v_sigs[i], n; END IF;
    EXECUTE replace(v_def, v_old[i], v_new[i]);
  END LOOP;
END $patch2$;

-- (3) the boot draw deals the temperature card from the month
DO $patch3$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_run_boot_draw(uuid)'::regprocedure);
  v_old text := $o$        ottoq_twin_deal(p_sim_run_id, v_key, 'global', v_run.sim_clock_start,
                        (v_run.sim_clock_start::date - DATE '2020-01-01'), 0, 'global'));$o$;
  v_new text := $n$        ottoq_twin_deal(p_sim_run_id, v_key, 'global', v_run.sim_clock_start,
                        (v_run.sim_clock_start::date - DATE '2020-01-01'), 0,
                        -- 0510 (G242): the day's temperature card is dealt from the month of the run's start, the
                        -- question the weather tick asks; a card dealt here is the one the weather tick then holds.
                        CASE WHEN v_key = 'ambient_temp_c'
                             THEN 'month:' || to_char(v_run.sim_clock_start AT TIME ZONE 'America/Chicago', 'MM')
                             ELSE 'global' END));$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0510: the boot draw''s world deal matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch3$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_start  text := pg_get_functiondef('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)'::regprocedure);
  v_depl   text := pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure);
  v_emit   text := pg_get_functiondef('twin.ottoq_sim_emit_telemetry(uuid,uuid,timestamptz,numeric,numeric,numeric,numeric,text,text[],text)'::regprocedure);
  v_boot   text := pg_get_functiondef('public.ottoq_run_boot_draw(uuid)'::regprocedure);
  v_all    text;
BEGIN
  v_all := v_start || v_depl || v_emit;
  -- V1: no consumer draws its own air any more, each reads the depot's once, and the boot draw asks for the month.
  IF v_all ~ 'ottoq_sample_calibrated\(\s*''ambient_temp_c'''
     OR (length(v_start) - length(replace(v_start, 'twin.ottoq_sim_site_ambient_c(', ''))) / length('twin.ottoq_sim_site_ambient_c(') <> 1
     OR (length(v_depl)  - length(replace(v_depl,  'twin.ottoq_sim_site_ambient_c(', ''))) / length('twin.ottoq_sim_site_ambient_c(') <> 1
     OR (length(v_emit)  - length(replace(v_emit,  'twin.ottoq_sim_site_ambient_c(', ''))) / length('twin.ottoq_sim_site_ambient_c(') <> 1
     OR position($m$THEN 'month:' || to_char(v_run.sim_clock_start AT TIME ZONE 'America/Chicago', 'MM')$m$ IN v_boot) = 0
     OR (SELECT provolatile FROM pg_proc WHERE oid = 'twin.ottoq_sim_site_ambient_c(uuid,timestamptz)'::regprocedure) <> 's' THEN
    RAISE EXCEPTION '0510 V1: a patched body is not the body this file leaves';
  END IF;
  -- V2: privileges, security definer and settings kept on the four patched functions (CREATE OR REPLACE keeps the ACL).
  IF EXISTS (
       SELECT 1 FROM pg_proc p
        WHERE p.oid IN ('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)'::regprocedure,
                        'twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure,
                        'twin.ottoq_sim_emit_telemetry(uuid,uuid,timestamptz,numeric,numeric,numeric,numeric,text,text[],text)'::regprocedure)
          AND (array_to_string(p.proacl, ',') <> 'postgres=X/postgres,service_role=X/postgres'
               OR NOT p.prosecdef
               OR array_to_string(p.proconfig, ',') <> 'search_path=twin, ottoq, public, extensions'))
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'public.ottoq_run_boot_draw(uuid)'::regprocedure)
          <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres'
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_run_boot_draw(uuid)'::regprocedure)
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = 'public.ottoq_run_boot_draw(uuid)'::regprocedure)
          <> 'search_path=twin, ottoq, public, extensions'
     OR has_function_privilege('anon', 'twin.ottoq_sim_site_ambient_c(uuid,timestamptz)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'twin.ottoq_sim_site_ambient_c(uuid,timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION '0510 V2: a function''s privileges or settings are not what this file leaves';
  END IF;
END $verify$;

-- V3: planted on the newest stopped operator run, then rolled back.
--   (a) the helper reads the run's weather: at a clock after a reading it returns that reading exactly; at a clock
--       before the run's first reading it returns the run's day card.
--   (b) a charge started on that run at a clock after a reading records the depot's air as its ambient, and a second
--       car started at the same clock records the same air.
--   (c) the boot draw, run again on that run with its temperature card taken away, deals the card the month gives
--       for the run's seed and day, not the whole year's.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  v_seed bigint; v_start timestamptz; v_first timestamptz; w record; v_clock timestamptz;
  v_card numeric; v_got numeric; v_c1 uuid; v_c2 uuid; v_s1 uuid; v_s2 uuid; st1 uuid; st2 uuid;
  a1 numeric; a2 numeric; v_bucket text; v_month_draw numeric; v_year_draw numeric;
BEGIN
  BEGIN
    SELECT sr.sim_run_id, COALESCE(sr.random_seed, 42), sr.sim_clock_start INTO v_run, v_seed, v_start
      FROM public.ottoq_sim_runs sr
     WHERE sr.depot_id = v_depot AND sr.validation_status IS NULL AND sr.status = 'completed'
       AND sr.sim_clock_current IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.ottoq_weather_snapshots ws WHERE ws.sim_run_id = sr.sim_run_id)
     ORDER BY sr.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0510 V3 FAILED: no stopped operator run with weather to plant on'; END IF;

    -- (a)
    SELECT min(sim_clock_at) INTO v_first FROM public.ottoq_weather_snapshots WHERE sim_run_id = v_run;
    SELECT ws.sim_clock_at, ws.ambient_temp_c INTO w FROM public.ottoq_weather_snapshots ws
     WHERE ws.sim_run_id = v_run ORDER BY ws.sim_clock_at OFFSET 10 LIMIT 1;
    v_clock := w.sim_clock_at + interval '10 seconds';
    v_got := twin.ottoq_sim_site_ambient_c(v_run, v_clock);
    IF v_got IS DISTINCT FROM (SELECT ws.ambient_temp_c FROM public.ottoq_weather_snapshots ws
                                 WHERE ws.sim_run_id = v_run AND ws.sim_clock_at <= v_clock
                                 ORDER BY ws.sim_clock_at DESC LIMIT 1) THEN
      RAISE EXCEPTION '0510 V3 FAILED (a): at % the helper read %, the weather %', v_clock, v_got, w.ambient_temp_c;
    END IF;
    v_bucket := 'day:' || (v_start::date - DATE '2020-01-01');
    SELECT c.value INTO v_card FROM public.ottoq_variability_cards c
     WHERE c.sim_run_id = v_run AND c.var_key = 'ambient_temp_c' AND c.scope_instance = 'global' AND c.bucket_key = v_bucket;
    IF v_first > v_start AND twin.ottoq_sim_site_ambient_c(v_run, v_start) IS DISTINCT FROM v_card THEN
      RAISE EXCEPTION '0510 V3 FAILED (a): before the first reading the helper read %, the day card is %',
        twin.ottoq_sim_site_ambient_c(v_run, v_start), v_card;
    END IF;

    -- (b) two cars of the depot on two charger stalls at the same clock
    SELECT v.id INTO v_c1 FROM public.vehicles v
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.is_active ORDER BY v.id LIMIT 1;
    SELECT v.id INTO v_c2 FROM public.vehicles v
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous' AND v.is_active AND v.id <> v_c1 ORDER BY v.id LIMIT 1;
    SELECT s.id INTO st1 FROM public.stalls s
     WHERE s.depot_id = v_depot AND s.stall_type = 'dcfc' AND s.ocpp_charger_id IS NOT NULL ORDER BY s.id LIMIT 1;
    SELECT s.id INTO st2 FROM public.stalls s
     WHERE s.depot_id = v_depot AND s.stall_type = 'l2' AND s.ocpp_charger_id IS NOT NULL ORDER BY s.id LIMIT 1;
    v_s1 := twin.ottoq_sim_start_charge_session(v_c1, st1, v_run, NULL, v_clock);
    v_s2 := twin.ottoq_sim_start_charge_session(v_c2, st2, v_run, NULL, v_clock);
    SELECT ambient_temp_c INTO a1 FROM public.ocpp_sessions WHERE id = v_s1;
    SELECT ambient_temp_c INTO a2 FROM public.ocpp_sessions WHERE id = v_s2;
    IF a1 IS DISTINCT FROM v_got OR a2 IS DISTINCT FROM v_got THEN
      RAISE EXCEPTION '0510 V3 FAILED (b): two charges started at % recorded % and %, the depot''s air is %', v_clock, a1, a2, v_got;
    END IF;

    -- (c) the boot draw deals the temperature card from the month
    DELETE FROM public.ottoq_variability_cards WHERE sim_run_id = v_run AND var_key = 'ambient_temp_c';
    PERFORM public.ottoq_run_boot_draw(v_run);
    SELECT c.value INTO v_card FROM public.ottoq_variability_cards c
     WHERE c.sim_run_id = v_run AND c.var_key = 'ambient_temp_c' AND c.scope_instance = 'global' AND c.bucket_key = v_bucket;
    v_month_draw := public.ottoq_sample_calibrated('ambient_temp_c',
                      'month:' || to_char(v_start AT TIME ZONE 'America/Chicago', 'MM'), v_seed,
                      'ambient_temp_c|global|' || v_bucket);
    v_year_draw := public.ottoq_sample_calibrated('ambient_temp_c', 'global', v_seed, 'ambient_temp_c|global|' || v_bucket);
    IF v_card IS NULL OR v_card IS DISTINCT FROM v_month_draw OR v_card = v_year_draw THEN
      RAISE EXCEPTION '0510 V3 FAILED (c): the boot draw dealt %, the month gives %, the whole year %', v_card, v_month_draw, v_year_draw;
    END IF;

    RAISE EXCEPTION '0510 V3 PASSED: (a) % C at % from the weather; (b) two charges both at % C; (c) day card % C from the month (the whole year gave %)',
      v_got, v_clock, a1, v_card, v_year_draw;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0510 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0510 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: restore the four functions from ottoq_schema_snapshots label '0510_pre' (CREATE OR REPLACE, ACL kept) and
-- DROP FUNCTION twin.ottoq_sim_site_ambient_c(uuid, timestamptz).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0510_one_air_temperature_for_the_whole_depot', true,
  'A charge, a car on the road and a telemetry packet read the depot''s air temperature instead of a per-car whole-year '
  'draw, and the boot draw deals the day''s temperature card from the month. The day''s weather, every charge''s pace '
  'and every car''s drain move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
