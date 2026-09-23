-- migration-version: 20260922080856
-- migration-name:    i_converted_the_hazard_with_the_metronome_cadence_instead_of_the_sim_time_the_tick_actually_advances
--
-- 0420  **`0413` fixed the fault hazard's units and then converted them with the wrong number.
--       `ottoq_sim_runs.tick_interval_seconds` is the REAL-TIME cadence between metronome beats. It is
--       not the sim time a tick advances, and it is neither playback mode's actual advance. Measured on
--       the live run: the hazard is overstated 3.80x in `live` mode and would be understated 60x in
--       `fixed` mode — the mode every certification and benchmark uses.**
--
--       Same defect class `0413` was written to close: a rate divided by a duration that was not the
--       duration it elapses over. Fourth instance in this area tonight, and the first one in code I
--       wrote rather than inherited.
--
--       **The engine already publishes the right number and says so in a comment.** `forces_recert`
--       **TRUE**, and §4 is explicit that certification outcomes change on purpose.
--
-- ══ §1 THE TWO NUMBERS, AND WHY I CONFLATED THEM ══════════════════════════════
--
-- `twin.ottoq_sim_advance_tick_world` computes the tick's sim-time advance in two branches:
--
--     playback_mode='live'   v_tick_minutes := LEAST(10, GREATEST(0,
--                              (clock_timestamp() - last_tick_at) * speed_x / 60))
--     playback_mode='fixed'  v_tick_minutes := (tick_interval_seconds * time_scale) / 60
--
-- So `tick_interval_seconds` appears in the FIXED branch only, multiplied by `time_scale`, and it is
-- written to `next_tick_due_at` as the real-time gap to the next beat. **It is the cadence.** In `live`
-- mode it does not enter the sim-time advance at all.
--
-- `0413`'s function reads it and divides by 3600 as though it were the sim-seconds a tick elapses. Its
-- own comment shows the mistake in progress — *"The RUN's own tick interval … is populated for all 14 and
-- is authoritative"* — authoritative for the cadence, which is not the quantity the hazard needed.
--
-- **Measured on run `61cedc05` (busy_day, seed 700001, live, speed_x 1.0), from
-- `ottoq_tick_clock_log.sim_advance_s`, which records it per tick:**
--
--     ticks logged                                 1,179
--     mean sim_advance_s                            7.90     (min 6.2, max 99.6)
--     what 0413 assumed                            30.00
--     => hazard overstated by                       3.80x
--
--     the same run's FIXED-mode advance would be   30 min = 1,800 s
--     => hazard would be understated by              60x
--
-- **Wrong in both modes and in opposite directions**, which is why no single run could have revealed it
-- by looking at outcomes alone.
--
-- ══ §2 THE FIX IS TO READ WHAT THE ENGINE ALREADY PUBLISHES FOR THIS EXACT PURPOSE ═
--
-- The world advancer writes, every tick:
--
--     payload = payload || jsonb_build_object('tick_minutes_actual', v_tick_minutes)
--
-- under a comment that names this consumer class precisely: *"LIVE-CLOCK COUPLING FIX 2026-08-01:
-- publish the ACTUAL elapsed sim-minutes **so every per-tick RATE cap downstream scales with the real
-- tick size.**"* The fault hazard is a per-tick rate cap. **It was the one that did not read it.**
--
-- **And the read is EXACT rather than one tick stale, which I checked rather than assumed.** Inside
-- `ottoq_sim_advance_tick_world` the `UPDATE ottoq_sim_runs … tick_minutes_actual` runs BEFORE the
-- `PERFORM ottoq_sim_vehicle_exception_handler(...)` that reaches this function, and both are in one
-- transaction, so the value read is the CURRENT tick's advance. P3 asserts that source ordering, because
-- if the calls were ever reordered the value would silently become the previous tick's — correct to
-- within a factor of one in live mode, and the whole point in fixed mode.
--
-- Fallback order, and each step is the engine's own rule rather than a number I chose:
--   1. `payload->>'tick_minutes_actual'` — authoritative, written every tick, **including a legitimate
--      zero** (live mode floors at 0 when no real time has elapsed; a zero-length tick must carry zero
--      hazard, so this is NOT coalesced away).
--   2. `(tick_interval_seconds * time_scale) / 60` — the advancer's own fixed branch, for the first tick
--      of a run before any `tick_minutes_actual` exists.
--   3. `0.5` minutes — 30 seconds, `0413`'s value, so the floor is no worse than today.
--
-- ══ §3 WHAT CHANGES, AND IT IS THE MODEL FINALLY DOING WHAT WAS ASKED ═════════
--
-- `0413`'s stated intent is Chase's operating assumption: **~1.5 vehicle faults per day, fleet-wide.**
--
--     mode    tick advance   per-tick hazard BEFORE   AFTER      effect
--     -----   ------------   ----------------------   --------   ------------------------------
--     live      7.9 s        7.33e-6                  1.93e-6    3.80x FEWER faults
--     fixed    30 min        7.33e-6                  4.40e-4    60x MORE faults
--
-- A 48-tick fixed-mode certification run spans 24 sim-hours. Before this fix, at ~100 eligible vehicles,
-- it expected **0.035** faults — so a cert covering a full simulated day saw essentially none, and the
-- fault model was invisible to exactly the runs meant to certify the engine's behaviour. After, it
-- expects about **2**, which is the 1.5/day assumption plus the eligible-share. **The fix does not
-- introduce faults into certification; it stops certification from silently excluding them.**
--
-- ══ §4 forces_recert TRUE, DELIBERATELY AND EXPENSIVELY ═══════════════════════
--
-- Fixed mode is what `run_by IN ('cert_harness','benchmark')` uses — `0258` refuses to let those runs use
-- `live` at all, precisely so a cert's tick size cannot be wall-clock. So this change moves cert
-- outcomes by 60x on the fault path: vehicles that never broke now break, and every downstream atom
-- (events, decisions, bookings, rules, end state) moves with them. **Every existing canon is invalidated
-- and that is correct** — a canon that encoded a 60x-suppressed fault rate was encoding the defect.
--
-- Determinism is unaffected in fixed mode: `tick_minutes_actual` there is a pure function of
-- `tick_interval_seconds * time_scale`, both stored on the run, so two arms of a pair compute the same
-- advance and the same hazard. **In live mode it is wall-clock and therefore not reproducible — which is
-- exactly why `0258` forbids live for certs, and why this fix makes the hazard MORE deterministic in the
-- certified path rather than less.**
--
-- ══ §5 WHAT I AM NOT DOING ════════════════════════════════════════════════════
--
-- **I am not re-tuning λ.** The 08:00 check-in's step 4 anticipated that the realised rate might come
-- back materially off 0.00088 and said to re-derive the denominator rather than tune silently. There is
-- now a stronger reason not to tune: **the realised rate has been running 3.80x high for a unit reason,
-- so any calibration against observed faults would be fitting λ to compensate for this bug.** Fix the
-- conversion first; measure λ afterwards, on a run whose hazard means what it says. `db/checks/0327`
-- records that the value check is still unavailable regardless (229 eligible vehicle-hours against the
-- ~1,700 needed).
--
-- **I am not touching the `live`-mode variability.** `sim_advance_s` ranges 6.2–99.6 s on this run,
-- because a stalled or slow beat advances more sim time. Reading `tick_minutes_actual` tracks that
-- faithfully, which is the correct behaviour for a hazard, and the 10-minute anti-teleport ceiling in
-- the advancer already bounds the worst case. A smoother clock is a twin-fidelity question, not a
-- hazard question.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_n   int;
  v_src text;
BEGIN
  -- P1. The function to fix exists and still divides by the cadence. If someone already fixed it, this
  --     migration would be re-fixing something else.
  SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^' || chr(10) || ']*','','g')
    INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_vehicle_fault_per_tick';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0420 P1: ottoq_vehicle_fault_per_tick does not exist -- apply 0413 first';
  END IF;
  IF v_src NOT LIKE '%tick_interval_seconds%' OR v_src NOT LIKE '%v_tick_s / 3600.0%' THEN
    RAISE EXCEPTION '0420 P1: the function no longer converts with tick_interval_seconds / 3600. '
                    'Someone has already changed it -- read it before replacing it';
  END IF;

  -- P2. THE PUBLISHED VALUE EXISTS. The whole fix depends on the world advancer writing
  --     tick_minutes_actual; if it stopped, this migration would fall through to the fixed-mode formula
  --     on every tick and silently be wrong in live mode again.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_advance_tick_world'
     AND p.prosrc LIKE '%tick_minutes_actual%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0420 P2: ottoq_sim_advance_tick_world no longer publishes tick_minutes_actual';
  END IF;

  -- P3. THE ORDERING THAT MAKES THE READ EXACT RATHER THAN ONE TICK STALE (§2). The payload write must
  --     come BEFORE the exception-handler call in the advancer's body. Compared on position, which is
  --     the only way to assert an order from source.
  SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^' || chr(10) || ']*','','g')
    INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_sim_advance_tick_world';
  IF position('tick_minutes_actual' in v_src) = 0
     OR position('ottoq_sim_vehicle_exception_handler' in v_src) = 0
     OR position('tick_minutes_actual' in v_src) > position('ottoq_sim_vehicle_exception_handler' in v_src)
  THEN
    RAISE EXCEPTION '0420 P3: in ottoq_sim_advance_tick_world the tick_minutes_actual write no longer '
                    'precedes the vehicle exception handler call, so this function would read the '
                    'PREVIOUS tick''s advance. Re-read §2 before applying';
  END IF;

  -- P4. The fixed-mode fallback is computable: both inputs are stored on the run.
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_sim_runs'
     AND column_name IN ('tick_interval_seconds','time_scale','payload');
  IF v_n <> 3 THEN
    RAISE EXCEPTION '0420 P4: ottoq_sim_runs is missing one of tick_interval_seconds/time_scale/payload '
                    '(found %)', v_n;
  END IF;

  RAISE NOTICE '0420 preflight: function still converts by cadence, advancer publishes '
               'tick_minutes_actual before the handler runs, fallback inputs present';
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- THE FIX. Same signature, same STABLE contract, same policy key and scenario
-- hook. Only the duration the rate is elapsed over changes.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_vehicle_fault_per_tick(p_sim_run_id uuid)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_per_hour  numeric;
  v_tick_min  numeric;
  v_published text;
  v_int_s     numeric;
  v_scale     numeric;
  v_mult      numeric;
BEGIN
  -- Denominated per ELIGIBLE VEHICLE-HOUR: an hour a vehicle spends in one of the seven in-depot
  -- states the handler rolls against. NOT per vehicle-hour of existence, and NOT per tick.
  v_per_hour := COALESCE(public.ottoq_policy_get(
                  p_sim_run_id, 'vehicle_fault_rate_per_eligible_vehicle_hour', 0.00088), 0.00088);

  -- ═══════════ 0420: THE SIM TIME THIS TICK ACTUALLY ADVANCES ═══════════
  -- 0413 read `tick_interval_seconds` here. That is the REAL-TIME cadence between metronome beats: it
  -- enters the sim-time advance only in the FIXED branch of twin.ottoq_sim_advance_tick_world, and
  -- there only multiplied by time_scale. Measured, 0413's reading overstated the hazard 3.80x in live
  -- mode and would have understated it 60x in fixed mode -- the mode every cert and benchmark uses.
  --
  -- `tick_minutes_actual` is written by the advancer every tick, under a comment stating it exists "so
  -- every per-tick RATE cap downstream scales with the real tick size". This is such a cap. The write
  -- precedes the handler call that reaches this function (asserted by 0420 P3), so the value is THIS
  -- tick's advance, not the previous one's.
  SELECT r.payload->>'tick_minutes_actual', r.tick_interval_seconds, r.time_scale
    INTO v_published, v_int_s, v_scale
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;

  IF v_published IS NOT NULL THEN
    -- Taken as-is, INCLUDING ZERO: live mode floors the advance at 0 when no real time has elapsed,
    -- and a tick in which the world did not age must carry no hazard. COALESCE-ing a legitimate 0 away
    -- would substitute a fabricated tick length for a real one.
    v_tick_min := v_published::numeric;
  ELSE
    -- First tick of a run, before any advance has been published. The advancer's own fixed-mode
    -- formula; 0.5 minutes (= 0413's 30 seconds) only if the run carries neither input.
    v_tick_min := COALESCE((v_int_s * v_scale) / 60.0, 0.5);
  END IF;

  -- The scenario hook. Returns 1 when the run has no variability profile or no _rates.vehicle_fault,
  -- so this is inert until a scenario opts in (db/checks/0320 §2).
  v_mult := COALESCE(public.ottoq_profile_rate_mult(p_sim_run_id, 'vehicle_fault'), 1);

  IF v_per_hour <= 0 OR v_mult <= 0 OR v_tick_min IS NULL OR v_tick_min <= 0 THEN
    RETURN 0;
  END IF;

  RETURN 1 - exp(- (v_per_hour * v_mult) * (v_tick_min / 60.0));
END
$function$;

COMMENT ON FUNCTION public.ottoq_vehicle_fault_per_tick(uuid) IS
'db/migrations/0413, corrected by 0420. Converts the per-eligible-vehicle-hour fault hazard into a '
'per-tick probability using the sim time the tick ACTUALLY advances, read from '
'ottoq_sim_runs.payload->>''tick_minutes_actual'' which twin.ottoq_sim_advance_tick_world publishes every '
'tick for exactly this class of consumer. 0413 used tick_interval_seconds, which is the real-time '
'metronome CADENCE and enters the sim advance only in the fixed branch, multiplied by time_scale: that '
'overstated the hazard 3.80x in live mode and would have understated it 60x in fixed mode. A published '
'advance of zero is honoured, not coalesced -- a tick in which the world did not age carries no hazard.';

-- ─────────────────────────────────────────────────────────────────────────────
-- LINEAGE
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0420_i_converted_the_hazard_with_the_metronome_cadence_instead_of_the_sim_time_the_tick_actually_advances',
  true,
  'Corrects ottoq_vehicle_fault_per_tick (0413) to elapse the per-eligible-vehicle-hour hazard over the '
  'sim time a tick actually advances, read from payload->>tick_minutes_actual, instead of over '
  'tick_interval_seconds -- which is the real-time metronome cadence and enters the sim advance only in '
  'the fixed branch, multiplied by time_scale. Measured on run 61cedc05: 3.80x overstatement in live '
  'mode (mean sim_advance_s 7.90 against an assumed 30) and a 60x understatement in fixed mode (a tick '
  'advances 30 sim-MINUTES there). TRUE because fixed mode is what run_by cert_harness/benchmark uses '
  '(0258 forbids live for those), so the fault path moves 60x on every certified run: a 48-tick cert '
  'spanning 24 sim-hours expected 0.035 faults before and about 2 after. Every canon that encoded the '
  'suppressed rate encoded the defect. Determinism is unaffected in fixed mode -- the advance there is a '
  'pure function of two stored run columns, so both arms of a pair compute the same hazard.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert,
                                 note          = EXCLUDED.note,
                                 classified_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_run      uuid;
  v_p_new    numeric;
  v_p_old    numeric;
  v_adv_s    numeric;
  v_ratio    numeric;
  v_src      text;
  v_n        int;
BEGIN
  -- V1. The cadence is gone from the conversion and the published advance is in it.
  SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^' || chr(10) || ']*','','g')
    INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_vehicle_fault_per_tick';
  IF v_src LIKE '%v_tick_s / 3600.0%' THEN
    RAISE EXCEPTION '0420 V1: the old cadence conversion is still present';
  END IF;
  IF v_src NOT LIKE '%tick_minutes_actual%' OR v_src NOT LIKE '%v_tick_min / 60.0%' THEN
    RAISE EXCEPTION '0420 V1: the new conversion is not present';
  END IF;

  -- V2. ON THE LIVE RUN, THE HAZARD FALLS BY THE RATIO §1 MEASURED. Computed, not asserted from the
  --     header: the new probability against the old formula's, and the drop must equal the ratio of the
  --     two durations to within rounding. This is the assertion that would catch an inverted fix.
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE status='running' ORDER BY started_at DESC LIMIT 1;

  IF v_run IS NULL THEN
    RAISE NOTICE '0420 V2: no running sim run to exercise against; V3 still checks both modes '
                 'arithmetically.';
  ELSE
    v_p_new := public.ottoq_vehicle_fault_per_tick(v_run);
    SELECT (r.payload->>'tick_minutes_actual')::numeric * 60 INTO v_adv_s
      FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run;
    -- The old formula, reconstructed inline so the comparison needs no dropped function.
    SELECT 1 - exp(- 0.00088 * (COALESCE(NULLIF(r.tick_interval_seconds,0),30) / 3600.0))
      INTO v_p_old FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run;

    IF v_adv_s IS NULL THEN
      RAISE NOTICE '0420 V2: run % has published no tick_minutes_actual yet; fell back to the fixed '
                   'formula, new hazard %', v_run, v_p_new;
    ELSE
      v_ratio := v_p_old / NULLIF(v_p_new, 0);
      RAISE NOTICE '0420 V2: run % advances % sim-seconds per tick (0413 assumed 30). Hazard per tick '
                   '% -> % , a factor of %.',
                   v_run, round(v_adv_s,2), v_p_old, v_p_new, round(v_ratio, 2);
      -- The drop must track the duration ratio. Both probabilities are tiny so exp() is ~linear and the
      -- ratio of probabilities must equal the ratio of durations within 1%.
      IF abs(v_ratio - (30.0 / v_adv_s)) > 0.01 * (30.0 / v_adv_s) THEN
        RAISE EXCEPTION '0420 V2: hazard changed by %x but the tick durations differ by %x -- the '
                        'conversion is not tracking the tick size',
                        round(v_ratio,3), round(30.0/v_adv_s,3);
      END IF;
    END IF;
  END IF;

  -- V3. BOTH MODES, ARITHMETICALLY, because V2 can only ever exercise whichever mode happens to be
  --     running and the fixed-mode direction is the one that moves certification.
  --     fixed: tick advance = tick_interval_seconds * time_scale seconds.
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs r
   WHERE r.tick_interval_seconds IS NOT NULL AND r.time_scale IS NOT NULL
     AND r.tick_interval_seconds > 0 AND r.time_scale > 0
     -- a fixed-mode tick must advance MORE sim time than 0413's assumed 30 s whenever time_scale > 1,
     -- which is the 60x understatement of §1 stated as an invariant
     AND (r.tick_interval_seconds::numeric * r.time_scale) < 30;
  RAISE NOTICE '0420 V3: % run(s) whose fixed-mode tick would advance LESS than 0413''s assumed 30 s '
               '(expected 0 where time_scale >= 1)', v_n;

  RAISE NOTICE '0420 verify: cadence conversion removed, published advance in use, hazard tracks the '
               'measured tick size, forces_recert TRUE recorded';
END $post$;

COMMIT;
