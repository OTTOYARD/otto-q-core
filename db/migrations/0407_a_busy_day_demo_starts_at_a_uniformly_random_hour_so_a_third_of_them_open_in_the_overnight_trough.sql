-- migration-version: 20260921193848
-- migration-name:    a_busy_day_demo_starts_at_a_uniformly_random_hour_so_a_third_of_them_open_in_the_overnight_trough
--
-- 0407  **A demo run picks its hour of day uniformly at random. Nothing ties a scenario to the time
--       of day it is about.** Chase watched run `c23de1b8` and reported two things: vehicles arrive
--       and immediately park on the perimeter instead of going for service, and vehicles that finish
--       service do not egress. **Both are one bug, and it is this one.**
--
-- ══ THE MEASUREMENT ════════════════════════════════════════════════════════
--
-- `ottoq_start_demo_run` chooses the clock with:
--
--     v_offset_min := CASE
--       WHEN p_seed IS NOT NULL THEN (abs(hashtext(p_seed::text)) % 1440)
--       ELSE floor(random() * 1440)::int
--     END;
--
-- `% 1440` is every minute of a 24-hour day. Seed 700001 hashed to 277, so run `c23de1b8` — whose
-- scenario is *"Busy Day — Sustained Depot Pressure"* — ran from **23:37 to 03:52 America/Chicago.**
--
-- The deploy-target curve, `ottoq_deploy_target_fraction(hour, peak)`, measured at those hours
-- against the twin depot's 116 vehicles:
--
--     hour 23  0.066 ->  7 vehicles       hour 02  0.005 -> 0
--     hour 00  0.017 ->  1 vehicle        hour 03  0.005 -> 0
--     hour 01  0.008 ->  0 vehicles
--
-- **The deploy target was ZERO for the last three hours of the run.** 21 vehicles deployed anyway,
-- so the engine over-delivered against its own target. Measured trail: 87 arrivals, **79 of them
-- straight to `staged_awaiting_service`**; 103 reached `staged_for_departure` and **9 deployed from
-- there**; **320 of 555 stall bookings (58%) were parking holds**.
--
-- **Nothing was malfunctioning.** At 2 AM, parking returning vehicles on the perimeter is correct.
-- Chase named the mechanism himself before seeing any of this: *"long-term perimeter parking for all
-- vehicles is generally only occurring during early morning hours when there's no dispatch or ride
-- hail potential."* The twin agreed with him. It thought it was 2 AM. **The parking logic is right
-- and the clock is wrong**, and that distinction is the whole finding — a fix aimed at the staging
-- logic would have broken correct behaviour.
--
-- **AND IT IS NOT ONLY `busy_day`.** `charger_outage_morning_rush` — a scenario whose entire
-- identity is a time of day — picks its hour uniformly at random too. So does `heat_wave`. A
-- scenario library where the name asserts a time and the clock ignores it is the defect class, not
-- one bad constant.
--
-- ══ WHY THIS SURVIVED `0297`/G107, WHICH LOOKED AT EXACTLY THIS CODE ═══════
--
-- G107 fixed a real and different bug: the world was BUILT at one clock and TICKED from another,
-- 7h25m apart. `0297` closed it by moving world construction onto `v_new_start`, and its comment
-- says so: *"sim_clock_start keeps the same VALUE it always had … The clock did not move; the world
-- moved to meet it."* **Preserving the value was correct for coherence and is not retracted.**
-- Nobody asked whether the value was *sensible*, because the question G107 was answering was whether
-- the two halves agreed — and they now do, at 2 AM.
--
-- (An aside worth recording: the outer `date_trunc('day', …)` runs in the SESSION timezone, which is
-- UTC for the engine, so it discards the `+ interval '8 hours'` the comment describes. The effective
-- anchor today is midnight **UTC** plus the offset, not 08:00 Central plus the offset. The legacy
-- branch below reproduces that expression verbatim rather than quietly correcting it.)
--
-- ══ WHAT THIS DOES ═════════════════════════════════════════════════════════
--
-- Two nullable columns on `ottoq_scenarios` declaring a start window in **Central hours**, filled
-- for **all fourteen** scenarios, and a new `ottoq_demo_start_clock(scenario, seed)` that places the
-- start inside that window.
--
-- **Determinism and CRN survive by construction.** The seed still chooses the minute; it now chooses
-- it within a declared window instead of within the whole day. `hashtext` is unchanged, so the same
-- (scenario, seed) still yields the same clock, and two arms of a pair still agree.
--
-- **A scenario with no declared window keeps TODAY'S behaviour exactly** — the legacy branch
-- reproduces the old expression verbatim, `% 1440` and all. A new scenario added without a window
-- therefore does not silently acquire one; it behaves as it always did, and
-- `ottoq_assert_scenario_start_windows()` reports it. That is a disclosure, deliberately not a gate,
-- because refusing to start an undeclared scenario would be a worse failure than starting it the way
-- it starts today.
--
-- ══ THE WINDOWS, AND WHY EACH ═════════════════════════════════════════════
--
--   busy_day, bench_busy_day, normal_day, bench_normal_day,
--   heat_wave, bench_heat_wave, production                     04:00–06:00 CT
--       Chase's call. A 1440-minute run from ~05:00 climbs 0.154 -> 0.264 -> 0.396 -> 0.484 across
--       the morning, so the depot fills overnight-style and then flushes into the demand ramp. That
--       arc — return, service, egress — is the thing he asked to be able to watch.
--   charger_outage_morning_rush, bench_…                       05:00–07:00 CT
--       480 minutes from ~06:00 covers 06:00–14:00, which is the rush the scenario is named for.
--   aggressive_fleet_turnover, bench_…                         06:00–08:00 CT
--       720 minutes from ~07:00 sits inside the 0.48–0.55 plateau, which is what "turnover" needs.
--   grid_smoke, SMOKE.a1_verify, SMOKE.a4_2_charge             08:00–09:00 CT
--       Fixtures. A narrow daytime window makes them reproducible and keeps them out of the trough.
--
-- **`forces_recert` TRUE.** This changes `sim_clock_start` for every future demo run, which changes
-- the world the seed builds, which changes every hashed atom. It must land with `0400` and `0401`
-- in one batch and one recert sweep.

BEGIN;

-- ALTER TABLE ... ADD COLUMN needs an AccessExclusiveLock on ottoq_scenarios, and
-- ottoq-recert-runner (pg_cron, job 746) holds RowShare + AccessShare on that table for the whole
-- length of every determinism pair -- measured at 281 seconds and counting. Without this, the
-- request QUEUES, and an AccessExclusive request queued in front of new readers stalls the recert
-- runner itself. Failing fast and retrying in a gap is strictly better than blocking the thing
-- that certifies the engine. This is also why 0401 committed and this file did not: 0401 only does
-- CREATE OR REPLACE FUNCTION, which never takes a table lock.
SET LOCAL lock_timeout = '15s';

DO $preflight$
DECLARE v_n int;
BEGIN
  -- (1) The anchor this migration rewrites must be present exactly once. If ottoq_start_demo_run
  --     has been edited since, the replacement below would silently no-op and the file would report
  --     success while changing nothing.
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_start_demo_run'
     AND p.prosrc ~ 'v_offset_min := CASE';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0407 P1: expected exactly 1 ottoq_start_demo_run carrying the v_offset_min anchor, found %', v_n;
  END IF;

  -- (2) The curve this whole file is reasoning about must still exist and must still be a function
  --     of the hour. If it stops depending on the hour, the diagnosis above stops holding.
  IF to_regprocedure('public.ottoq_deploy_target_fraction(integer, numeric)') IS NULL THEN
    RAISE EXCEPTION '0407 P2: ottoq_deploy_target_fraction(int, numeric) is missing -- re-derive before pinning start hours';
  END IF;
  IF public.ottoq_deploy_target_fraction(2, 0.55) >= public.ottoq_deploy_target_fraction(8, 0.55) THEN
    RAISE EXCEPTION '0407 P3: the deploy curve no longer troughs overnight -- the premise of this migration has moved';
  END IF;

  -- (3) ottoq_scenarios is NOT in the run-scope registry (0 rows), so adding config columns to it
  --     needs no registry entry. Assert that, so a future registry expansion makes this loud.
  SELECT count(*) INTO v_n FROM public.ottoq_run_scope_registry WHERE table_name = 'ottoq_scenarios';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0407 P4: ottoq_scenarios now has % run-scope registry rows; classify the new columns before adding them', v_n;
  END IF;
END
$preflight$;

ALTER TABLE public.ottoq_scenarios
  ADD COLUMN IF NOT EXISTS start_window_lo_hour_ct smallint,
  ADD COLUMN IF NOT EXISTS start_window_hi_hour_ct smallint;

COMMENT ON COLUMN public.ottoq_scenarios.start_window_lo_hour_ct IS
'Earliest America/Chicago hour a demo run of this scenario may start, inclusive. With '
'start_window_hi_hour_ct it bounds the seed-derived start minute, so a scenario named for a time of '
'day actually runs at that time of day. NULL means no declared window and ottoq_demo_start_clock '
'falls back to the legacy uniform-over-24h behaviour verbatim. 0407.';
COMMENT ON COLUMN public.ottoq_scenarios.start_window_hi_hour_ct IS
'Latest America/Chicago hour a demo run of this scenario may start, EXCLUSIVE. See '
'start_window_lo_hour_ct. 0407.';

UPDATE public.ottoq_scenarios SET start_window_lo_hour_ct = 4, start_window_hi_hour_ct = 6
 WHERE scenario_code IN ('busy_day','bench_busy_day','normal_day','bench_normal_day',
                         'heat_wave','bench_heat_wave','production');
UPDATE public.ottoq_scenarios SET start_window_lo_hour_ct = 5, start_window_hi_hour_ct = 7
 WHERE scenario_code IN ('charger_outage_morning_rush','bench_charger_outage_morning_rush');
UPDATE public.ottoq_scenarios SET start_window_lo_hour_ct = 6, start_window_hi_hour_ct = 8
 WHERE scenario_code IN ('aggressive_fleet_turnover','bench_aggressive_fleet_turnover');
UPDATE public.ottoq_scenarios SET start_window_lo_hour_ct = 8, start_window_hi_hour_ct = 9
 WHERE scenario_code IN ('grid_smoke','SMOKE.a1_verify','SMOKE.a4_2_charge');

CREATE OR REPLACE FUNCTION public.ottoq_demo_start_clock(p_scenario text, p_seed bigint)
RETURNS timestamptz
LANGUAGE plpgsql VOLATILE
SET search_path = twin, ottoq, public, extensions
AS $fn$
DECLARE
  v_lo int;
  v_hi int;
  v_span int;
  v_off int;
BEGIN
  SELECT s.start_window_lo_hour_ct, s.start_window_hi_hour_ct
    INTO v_lo, v_hi
    FROM public.ottoq_scenarios s
   WHERE s.scenario_code = p_scenario
   ORDER BY (s.status = 'active') DESC, s.scenario_id
   LIMIT 1;

  IF v_lo IS NULL OR v_hi IS NULL OR v_hi <= v_lo THEN
    -- LEGACY BRANCH, reproduced verbatim from ottoq_start_demo_run so an undeclared scenario
    -- behaves EXACTLY as it does today rather than silently acquiring a new clock. The outer
    -- date_trunc runs in the session timezone and discards the 8-hour term; that is preserved,
    -- not corrected, because correcting it here would change scenarios this file did not consider.
    v_off := CASE WHEN p_seed IS NOT NULL THEN (abs(hashtext(p_seed::text)) % 1440)
                  ELSE floor(random() * 1440)::int END;
    RETURN date_trunc('day',
             ((date_trunc('day', now() AT TIME ZONE 'America/Chicago') + interval '8 hours')
               AT TIME ZONE 'America/Chicago'))
           + make_interval(mins => v_off);
  END IF;

  -- Declared window. The seed still chooses the minute -- it now chooses within the window instead
  -- of within the whole day -- so determinism and CRN pairing are unchanged by construction.
  v_span := GREATEST(1, (v_hi - v_lo) * 60);
  v_off  := v_lo * 60 + CASE WHEN p_seed IS NOT NULL THEN (abs(hashtext(p_seed::text)) % v_span)
                             ELSE floor(random() * v_span)::int END;

  -- Anchored to LOCAL midnight, so the window means the same wall-clock hours across DST. The
  -- deploy curve reads EXTRACT(HOUR FROM clock AT TIME ZONE 'America/Chicago'), so the anchor and
  -- the consumer must agree on the zone or the window lands an hour off twice a year.
  RETURN (date_trunc('day', now() AT TIME ZONE 'America/Chicago') AT TIME ZONE 'America/Chicago')
         + make_interval(mins => v_off);
END
$fn$;

COMMENT ON FUNCTION public.ottoq_demo_start_clock(text, bigint) IS
'The sim_clock_start a demo run of this scenario should begin at: local midnight plus a '
'seed-derived minute inside the scenario declared start window (ottoq_scenarios.'
'start_window_lo_hour_ct / _hi_hour_ct, Central hours, hi exclusive). Replaces a uniform '
'abs(hashtext(seed)) % 1440 that put roughly a third of demo runs in the overnight trough, where '
'ottoq_deploy_target_fraction is 0.005-0.066 and correct behaviour is to park every returning '
'vehicle on the perimeter -- which is what run c23de1b8 did, from 23:37 to 03:52 Central, and what '
'Chase reported as a defect. The parking logic was right; the clock was wrong. A scenario with no '
'declared window falls through to the legacy expression verbatim. 0407 / db/checks/0315.';

REVOKE EXECUTE ON FUNCTION public.ottoq_demo_start_clock(text, bigint) FROM anon;
REVOKE EXECUTE ON FUNCTION public.ottoq_demo_start_clock(text, bigint) FROM PUBLIC;

-- Rewrite ottoq_start_demo_run's clock block IN PLACE against the live source, rather than
-- transcribing 3,672 characters by hand. Everything outside the anchor is preserved byte-identically
-- by construction, and the assertions refuse a silent no-op. CREATE OR REPLACE keeps the owner and
-- the existing ACL (postgres, service_role -- anon was already revoked by 0198).
DO $rewrite$
DECLARE
  v_src  text;
  v_new  text;
  v_args text;
  v_ndef int;
  v_ndef_after int;
BEGIN
  -- pg_get_function_ARGUMENTS, never pg_get_function_IDENTITY_arguments. The identity form STRIPS
  -- parameter defaults. ottoq_start_demo_run carries FOUR of them -- p_scenario DEFAULT
  -- 'normal_day', p_speed DEFAULT 1.0, p_days DEFAULT 1, p_seed DEFAULT NULL -- and it has seven
  -- callers that rely on them. CREATE OR REPLACE without them fails with 42P13 rather than
  -- silently dropping them, which is how 0401 caught this first; the assertion below makes the
  -- guarantee explicit rather than relying on Postgres to object.
  SELECT p.prosrc, pg_get_function_arguments(p.oid), p.pronargdefaults
    INTO v_src, v_args, v_ndef
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_start_demo_run';

  v_new := regexp_replace(
    v_src,
    'v_offset_min := CASE.*?\+ make_interval\(mins => v_offset_min\);',
    'v_new_start := public.ottoq_demo_start_clock(p_scenario, p_seed);');

  IF v_new = v_src THEN
    RAISE EXCEPTION '0407 P5: the clock block was not replaced -- anchor did not match, refusing a silent no-op';
  END IF;
  IF v_new !~ 'ottoq_demo_start_clock\(p_scenario, p_seed\)' THEN
    RAISE EXCEPTION '0407 P6: the replacement text is absent from the rewritten source';
  END IF;
  IF v_new ~ 'hashtext\(p_seed::text\)\) % 1440' THEN
    RAISE EXCEPTION '0407 P7: the uniform-over-24h expression survives in ottoq_start_demo_run';
  END IF;
  IF length(v_src) - length(v_new) < 200 THEN
    RAISE EXCEPTION '0407 P8: replacement removed only % chars; the regex matched less than the whole block', length(v_src) - length(v_new);
  END IF;

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public.ottoq_start_demo_run(%s) RETURNS jsonb '
    'LANGUAGE plpgsql SECURITY DEFINER SET search_path = twin, ottoq, public, extensions AS %L',
    v_args, v_new);

  SELECT p.pronargdefaults INTO v_ndef_after
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_start_demo_run';
  IF v_ndef_after <> v_ndef THEN
    RAISE EXCEPTION '0407 P9: parameter defaults went from % to % -- seven callers depend on them; refusing a signature change', v_ndef, v_ndef_after;
  END IF;

  RAISE NOTICE '0407: ottoq_start_demo_run rewritten, % chars -> % chars, % defaults preserved',
    length(v_src), length(v_new), v_ndef_after;
END
$rewrite$;

CREATE OR REPLACE FUNCTION public.ottoq_assert_scenario_start_windows()
RETURNS TABLE (scenario_code text, status text, note text)
LANGUAGE sql STABLE AS $$
  SELECT s.scenario_code::text, s.status::text,
         'no declared start window -- demo runs of this scenario still pick a uniformly random hour'
    FROM public.ottoq_scenarios s
   WHERE s.status = 'active'
     AND (s.start_window_lo_hour_ct IS NULL OR s.start_window_hi_hour_ct IS NULL)
  UNION ALL
  SELECT s.scenario_code::text, s.status::text,
         format('window is empty or inverted (lo=%s hi=%s); ottoq_demo_start_clock falls back to legacy uniform',
                s.start_window_lo_hour_ct, s.start_window_hi_hour_ct)
    FROM public.ottoq_scenarios s
   WHERE s.start_window_lo_hour_ct IS NOT NULL
     AND s.start_window_hi_hour_ct IS NOT NULL
     AND s.start_window_hi_hour_ct <= s.start_window_lo_hour_ct
$$;

COMMENT ON FUNCTION public.ottoq_assert_scenario_start_windows() IS
'DISCLOSURE, not a gate. Lists active scenarios with no declared start window, or an inverted one. '
'Such a scenario still starts at a uniformly random hour -- the 0407 legacy branch -- which is the '
'behaviour that put run c23de1b8 in the overnight trough. It is a disclosure rather than a gate '
'because refusing to start an undeclared scenario is a worse failure than starting it the way it '
'starts today. Expected empty; a new row means someone added a scenario without saying what time of '
'day it is about. 0407.';

REVOKE EXECUTE ON FUNCTION public.ottoq_assert_scenario_start_windows() FROM anon;
REVOKE EXECUTE ON FUNCTION public.ottoq_assert_scenario_start_windows() FROM PUBLIC;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0407_a_busy_day_demo_starts_at_a_uniformly_random_hour_so_a_third_of_them_open_in_the_overnight_trough',
        TRUE,
        'Chase watched run c23de1b8 and reported that vehicles arrive and immediately perimeter-park '
        'instead of going for service, and that vehicles finishing service do not egress. Both are '
        'ONE bug: ottoq_start_demo_run picked the hour of day with abs(hashtext(seed)) % 1440, '
        'uniform over 24 hours, with nothing tying a scenario to the time of day it is about. Seed '
        '700001 hashed to 277, so a scenario titled "Busy Day - Sustained Depot Pressure" ran from '
        '23:37 to 03:52 America/Chicago. Measured on ottoq_deploy_target_fraction against 116 '
        'vehicles: hour 23 -> 7 target, hour 00 -> 1, hours 01/02/03 -> ZERO. 21 deployed anyway, so '
        'the engine over-delivered against its own target. Trail: 87 arrivals, 79 straight to '
        'staged_awaiting_service; 103 reached staged_for_departure and 9 deployed; 320 of 555 stall '
        'bookings were parking holds. NOTHING WAS MALFUNCTIONING -- at 2 AM parking returning '
        'vehicles on the perimeter is correct, and Chase named that mechanism himself before seeing '
        'the code. The parking logic is right and the clock is wrong, which matters because a fix '
        'aimed at the staging logic would have broken correct behaviour. Not only busy_day: '
        'charger_outage_morning_rush, a scenario whose entire identity is a time of day, picks its '
        'hour at random too. Adds ottoq_scenarios.start_window_lo_hour_ct/_hi_hour_ct (Central '
        'hours, hi exclusive) filled for ALL FOURTEEN scenarios, and ottoq_demo_start_clock() which '
        'places the start at local midnight plus a seed-derived minute inside that window. '
        'Determinism and CRN survive by construction: the seed still chooses the minute, now within '
        'a window instead of within a day, and hashtext is unchanged. An undeclared scenario falls '
        'through to the legacy expression VERBATIM so it behaves exactly as today rather than '
        'silently acquiring a new clock; ottoq_assert_scenario_start_windows() reports any such '
        'scenario as a disclosure, deliberately not a gate. Anchored to LOCAL midnight because the '
        'consumer reads EXTRACT(HOUR FROM clock AT TIME ZONE America/Chicago) and an anchor in a '
        'different zone lands an hour off twice a year. WHY 0297/G107 DID NOT CATCH THIS: G107 fixed '
        'a different and real bug -- the world was built at one clock and ticked from another, 7h25m '
        'apart -- and closed it by preserving the VALUE while moving the world to meet it. That was '
        'correct and is not retracted; nobody asked whether the value was sensible. Aside recorded '
        'in the file: the outer date_trunc runs in the session timezone (UTC) and discards the '
        '8-hour term the old comment describes, so the effective legacy anchor is midnight UTC, not '
        '08:00 Central; the legacy branch reproduces that verbatim rather than quietly correcting '
        'it. ottoq_start_demo_run is rewritten IN PLACE against its live source with four assertions '
        'that refuse a silent no-op, so everything outside the anchor is preserved byte-identically. '
        'Both new functions have anon and PUBLIC revoked per 0406. forces_recert TRUE: this changes '
        'sim_clock_start for every future demo run, which changes the world the seed builds, which '
        'changes every hashed atom -- it must land with 0400 and 0401 in one batch and one sweep.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

COMMIT;
