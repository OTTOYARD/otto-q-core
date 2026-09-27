-- 0376  **G241: a charge, a car on the road and a telemetry packet each draw their own air temperature, from the whole
--       year's distribution, per car, and none of them reads the depot's weather. G242: the depot's weather itself
--       starts every run on a whole-year day, because the boot draw deals the day's temperature card from the all-year
--       segment before the weather tick can deal it from the month.**
--
--       Found on 2026-09-27 (02:50-03:25 UTC) while testing what could fill the early gap in the charging card's ETA
--       (0375 §6(c)): the "ambient" that sets each charge's pace was uncorrelated with the depot's weather. Read across
--       the nine operator runs that survive (2026-09-25 to 27, busy_day, twin depot).

-- ══ §1 A CHARGE'S AIR TEMPERATURE AGAINST THE DEPOT'S WEATHER ═══════════════════════════════════════════════════

\echo '=== 0376 §1 — each charge''s recorded ambient against the depot''s weather at its start, per operator run ==='
WITH s AS (
  SELECT os.sim_run_id, os.started_at, os.ambient_temp_c AS session_ambient,
         (SELECT w.ambient_temp_c FROM public.ottoq_weather_snapshots w
           WHERE w.sim_run_id = os.sim_run_id AND w.sim_clock_at <= os.started_at
           ORDER BY w.sim_clock_at DESC LIMIT 1) AS weather_ambient
    FROM public.ocpp_sessions os
    JOIN public.stalls st ON st.id = os.stall_id AND st.depot_id = '11111111-1111-1111-1111-111111111111'
    JOIN public.ottoq_sim_runs r ON r.sim_run_id = os.sim_run_id AND r.run_by = 'operator_demo'
   WHERE os.stopped_reason IS NOT NULL)
SELECT left(sim_run_id::text, 8) AS run, count(*) AS sessions, count(weather_ambient) AS with_weather,
       round(min(session_ambient), 1) AS min_session, round(max(session_ambient), 1) AS max_session,
       round(stddev(session_ambient), 1) AS sd_session,
       round(min(weather_ambient), 1) AS min_weather, round(max(weather_ambient), 1) AS max_weather,
       round(corr(session_ambient, weather_ambient)::numeric, 2) AS corr
  FROM s GROUP BY 1 ORDER BY 1;
-- READ (2026-09-27 03:05 UTC): on every run the charges' ambient spans roughly -13 to +38 C within one morning (SD
--   10.7-12.0 C) while the depot's weather moves 3-5 C, and the two are uncorrelated (-0.19 to +0.15):
--     run        sessions  session ambient     weather           corr
--     317d4331     104     -9.1 .. 37.5       37.6 .. 40.6      -0.15
--     394e1e83      98    -11.8 .. 38.3       13.7 .. 18.1      -0.11
--     3dbe16db     105     -9.4 .. 37.3        2.2 ..  2.2      -0.09
--     461c79fa      70     -5.4 .. 36.0       35.9 .. 39.0      -0.02
--     49c45bd4      90    -10.7 .. 37.1       18.1 .. 22.5      -0.19
--     5344fc12      95    -11.0 .. 37.4       18.6 .. 23.0      -0.01
--     689095e2      82    -13.0 .. 37.7        9.8 .. 12.6       0.03
--     964cf17b     106     -8.8 .. 37.4       19.7 .. 24.1       0.11
--     b0fdc92b     103     -8.3 .. 37.9        2.2 ..  2.2       0.15
--   Two cars plugging in at the same minute can be charging in -9 C and in 37 C air. The charge model derates on the
--   battery's temperature, which the twin builds from this ambient, so this draw sets a charge's pace, and it is the
--   temperature 0375 §6(c) found moving the charge durations.

-- ══ §2 WHERE THE TWIN'S AIR TEMPERATURES COME FROM ══════════════════════════════════════════════════════════════

\echo '=== 0376 §2 — functions that draw ambient_temp_c themselves, and the segment they draw from ==='
SELECT n.nspname || '.' || p.proname AS fn,
       (SELECT string_agg(trim(m[1]), ' | ') FROM regexp_matches(pg_get_functiondef(p.oid),
          '(ottoq_sample_calibrated\(\s*''ambient_temp_c''\s*,\s*''[a-z:0-9]+'')', 'g') AS m) AS draws
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.prokind = 'f' AND n.nspname IN ('public', 'ottoq', 'twin')
   AND pg_get_functiondef(p.oid) ~ 'ottoq_sample_calibrated\(\s*''ambient_temp_c'''
 ORDER BY 1;
-- READ (before 0510): three twin functions draw the air temperature themselves, all from the 'global' segment, each
--   salted per entity: `twin.ottoq_sim_start_charge_session` (per car and clock; the session's ambient, and so its
--   battery temperature and pace), `twin.ottoq_sim_advance_deployed_telemetry` (per car and tick on the road; the
--   discharge model's climate load, so the SoC a car arrives with) and `twin.ottoq_sim_emit_telemetry` (per packet).
--   The energy forecasts and orchestration read the session's recorded ambient, so they inherit the charge's draw.

\echo '=== 0376 §2(b) — the calibration those draws read: the whole year against the month ==='
SELECT dataset_code, segment, sample_count, round(mean_value, 2) AS mean, round(stddev_value, 2) AS sd,
       round(min_value, 1) AS min, round(max_value, 1) AS max
  FROM public.ottoq_calibration_distributions
 WHERE variable_name = 'ambient_temp_c' AND segment IN ('global', 'month:08', 'month:09')
 ORDER BY 1, 2;
-- READ: `global` is noaa_nws's whole year, mean 17.53 C, SD 11.38, -13.3 to 38.3 (724 samples): exactly the range the
--   charges show in §1. `month:09` is NOAA's 1991-2020 September, 22.8 C, SD 3.3, 2.2 to 40.6 (810 days); `month:08`
--   26.5 C, SD 2.4. The twin's own weather feed plan names the month segments as its source.

-- ══ §3 G242: THE DEPOT'S WEATHER STARTS EVERY RUN ON A WHOLE-YEAR DAY ════════════════════════════════════════════
--
--   The weather tick deals the day's temperature card with `ottoq_twin_deal(run, 'ambient_temp_c', 'global', clock,
--   day, 0, 'month:' || MM)`: the third argument is the card's scope instance and the last is the calibration
--   segment, so it asks for the month. But `ottoq_run_boot_draw` deals every run/day/block world card before tick 1
--   (its "WORLD DAY-0 DRAW") with the segment 'global', and `ottoq_twin_deal` returns a card already dealt for the
--   same scope and day. So the month-aware call never deals day 0, and day 0 is the whole of an operator run.

\echo '=== 0376 §3 — each operator run''s day card against the all-year and the September draw for its own seed ==='
SELECT left(c.sim_run_id::text, 8) AS run, c.bucket_key, round(c.value, 2) AS stored_card,
       round(public.ottoq_sample_calibrated('ambient_temp_c', 'global', COALESCE(r.random_seed, 42),
                                            'ambient_temp_c|global|' || c.bucket_key), 2) AS all_year_draw,
       round(public.ottoq_sample_calibrated('ambient_temp_c', 'month:09', COALESCE(r.random_seed, 42),
                                            'ambient_temp_c|global|' || c.bucket_key), 2) AS september_draw
  FROM public.ottoq_variability_cards c
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = c.sim_run_id AND r.run_by = 'operator_demo'
 WHERE c.var_key = 'ambient_temp_c'
 ORDER BY r.started_at;
-- READ (2026-09-27 03:20 UTC): 9 of 9 stored day cards equal the all-year draw for the run's seed to the hundredth of
--   a degree: 16.70, 33.38, 19.46, -8.29, 32.17, 16.32, 3.20, 19.81, 20.60 C. The September draws for the same seeds
--   would have been 22.06, 27.97, 22.89, 15.10, 27.18, 21.99, 19.20, 22.94, 23.14. The two runs whose weather sat at
--   2.2 C all morning (3dbe16db, b0fdc92b) had cards of -8.29 and 3.20, held at September's record low by 0449's clamp;
--   the two near the record high (317d4331, 461c79fa) had 33.38 and 32.17.
--   This corrects G180's reading of the canon's 31.1 C day as "legitimate sampling" of September: it was the boot
--   draw's whole-year card too.

\echo '=== 0376 §3(b) — the month segment samples as NOAA says (400 seeds on one salt) ==='
WITH d AS (
  SELECT public.ottoq_sample_calibrated('ambient_temp_c', 'month:09', 1555674948722399031 + g, 'ambient_temp_c|global|day:2460') AS v_month,
         public.ottoq_sample_calibrated('ambient_temp_c', 'global',   1555674948722399031 + g, 'ambient_temp_c|global|day:2460') AS v_global
    FROM generate_series(1, 400) g)
SELECT round(avg(v_month), 2) AS mean_month, round(stddev(v_month), 2) AS sd_month, round(min(v_month), 1) AS min_month,
       round(max(v_month), 1) AS max_month, round(avg(v_global), 2) AS mean_all_year, round(stddev(v_global), 2) AS sd_all_year,
       round(min(v_global), 1) AS min_all_year, round(max(v_global), 1) AS max_all_year
  FROM d;
-- READ: September 22.86 C, SD 3.18, 14.4 to 31.0; the whole year 17.84 C, SD 11.29, -12.7 to 37.9. The sampler is
--   right; the boot draw asks it the wrong question.

-- ══ §4 THE APPLY (0510), AND THE CANON UNDER IT ═════════════════════════════════════════════════════════════════
--
--   0510 (`one_air_temperature_for_the_whole_depot`): `twin.ottoq_sim_site_ambient_c(run, clock)` returns the depot's
--   air temperature (the run's latest weather reading at or before the clock, else the day's temperature card); the
--   charge start, the car on the road and the telemetry packet read it; and the boot draw deals the temperature card
--   from the month of the run's start.

\echo '=== 0376 §4 — 0510 as applied ==='
SELECT m.version, m.name, md5(m.statements[1]) AS stored_md5
  FROM supabase_migrations.schema_migrations m
 WHERE m.name = 'one_air_temperature_for_the_whole_depot';
-- READ: 20260927030227 (10:02 PM CT), md5 22180866acb2ae1ba4466c26e6cc7043, equal to the file's body; forces_recert
--   TRUE. Dry-run first between runs, rolled back, with V3 passing on 964cf17b: (a) at sim 8:08 AM the helper read
--   19.7 C, the run's weather reading at that clock; (b) a DCFC charge and an L2 charge, two cars started at that clock,
--   both recorded 19.7 C; (c) the boot draw, run again with the run's temperature card taken away, dealt 23.14 C, the
--   September draw for the run's seed, where the stored card was the whole year's 20.60. Applied with the same V3.

\echo '=== 0376 §4(b) — the canon since 0510, and what moved against its verdicts under 0508 ==='
WITH now_v AS (
  SELECT DISTINCT ON (scenario, seed, ticks) verdict_id, scenario, seed, ticks, equal, verdict->'arm_a' AS a
    FROM public.ottoq_determinism_verdict_ledger
   WHERE certified_at > '2026-09-27 03:02:27+00'
   ORDER BY scenario, seed, ticks, verdict_id DESC),
before_v AS (
  SELECT DISTINCT ON (scenario, seed, ticks) verdict_id, scenario, seed, ticks, verdict->'arm_a' AS a
    FROM public.ottoq_determinism_verdict_ledger
   WHERE verdict_id BETWEEN 448 AND 456
   ORDER BY scenario, seed, ticks, verdict_id DESC)
SELECT n.scenario || '/' || n.seed || '/' || n.ticks AS col, b.verdict_id AS was, n.verdict_id AS now, n.equal,
       (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(n.a) k
         WHERE (k LIKE 'h\_%' OR k IN ('fp','endst'))
           AND n.a->>k IS DISTINCT FROM b.a->>k) AS moved
  FROM now_v n LEFT JOIN before_v b USING (scenario, seed, ticks)
 ORDER BY 1;
-- READ: pending (the sweep began at the apply).

-- ══ §5 THE NEXT VALIDATION RUN, PREDICTED BEFORE IT STARTS ══════════════════════════════════════════════════════
--
--   PREDICTED on the next busy_day operator run: (a) every charge records the depot's air at its start: the weather
--   reading at or before it, or the day card before the first reading, with 0 exceptions; (b) the run's temperature
--   card is its seed's September draw (NOAA 22.8 +/- 3.3 C), not the whole year's; (c) within the run the charges'
--   ambient spreads no wider than the weather's own morning range (a few degrees, where every run before read an SD of
--   10.7-12.0 C); (d) a charge's duration against the nominal model spreads less than §1's runs did (0375 §6(c) read an
--   RMS log error of 0.215 DCFC and 0.222 L2), because the largest source of its noise is gone. (d) is a direction, and
--   one run is one draw of the weather.

\echo '=== 0376 §5(a) — charges whose recorded ambient is not the depot''s air at their start ==='
SELECT count(*) AS sessions,
       count(*) FILTER (WHERE os.ambient_temp_c IS DISTINCT FROM twin.ottoq_sim_site_ambient_c(os.sim_run_id, os.started_at)) AS not_the_depots_air
  FROM public.ocpp_sessions os
 WHERE os.sim_run_id = :'run';
-- READ: pending.

\echo '=== 0376 §5(b)-(c) — the run''s temperature card, and the charges'' ambient against the weather ==='
SELECT (SELECT round(c.value, 2) FROM public.ottoq_variability_cards c
         WHERE c.sim_run_id = :'run' AND c.var_key = 'ambient_temp_c' ORDER BY c.bucket_key LIMIT 1) AS day_card,
       (SELECT round(public.ottoq_sample_calibrated('ambient_temp_c', 'month:' || to_char(r.sim_clock_start AT TIME ZONE 'America/Chicago', 'MM'),
                                                    COALESCE(r.random_seed, 42),
                                                    'ambient_temp_c|global|day:' || (r.sim_clock_start::date - DATE '2020-01-01')), 2)
          FROM public.ottoq_sim_runs r WHERE r.sim_run_id = :'run') AS month_draw,
       (SELECT round(min(w.ambient_temp_c), 1) || ' .. ' || round(max(w.ambient_temp_c), 1)
          FROM public.ottoq_weather_snapshots w WHERE w.sim_run_id = :'run') AS weather_range,
       (SELECT round(min(os.ambient_temp_c), 1) || ' .. ' || round(max(os.ambient_temp_c), 1) || ' (sd ' || round(stddev(os.ambient_temp_c), 1) || ')'
          FROM public.ocpp_sessions os WHERE os.sim_run_id = :'run') AS charges_ambient;
-- READ: pending.

\echo '=== 0376 §5(d) — the charges'' duration against the nominal model ==='
SELECT st.stall_type::text AS stype, count(*) AS sessions,
       round(sqrt(avg(ln((EXTRACT(epoch FROM os.ended_at - os.started_at)/60)
                  / public.ottoq_charge_minutes_between(os.soc_start, os.soc_end, ch.max_kw, v.inlet_max_kw, v.battery_capacity_kwh, 95, 22, 0.5))^2))::numeric, 3) AS rms_log_nominal
  FROM public.ocpp_sessions os
  JOIN public.stalls st ON st.id = os.stall_id
  JOIN public.ottoq_ocpp_chargers ch ON ch.charger_id = st.ocpp_charger_id
  JOIN public.vehicles v ON v.id = os.vehicle_id
 WHERE os.sim_run_id = :'run' AND os.stopped_reason = 'completed'
   AND os.ended_at - os.started_at >= interval '10 minutes' AND os.soc_end >= os.soc_start + 2
 GROUP BY 1 ORDER BY 1;
-- READ: pending.
