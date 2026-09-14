-- migration-version: PENDING
-- migration-name:    0313_the_predictive_recall_rung_takes_eight_values_and_none_of_them_is_the_vehicle
--
-- 0313  THE PREDICTIVE RECALL RUNG CANNOT SEE THE VEHICLE IT IS PREDICTING FOR
--
-- ---------------------------------------------------------------------------
-- THE DEFECT (measured; extends db/checks/0238)
--
-- public.ottoq_recall_naive_threshold_v1 has two safety rungs, checked in this
-- order:
--
--   line  54: v_burn_per_min := ottoq_policy_get(p_sim_run_id,'p99_burn_pct_per_min',0.25);
--   line  67: v_burn_guard   := v_burn_per_min * (v_eta_min + p_horizon_min);
--   line 120: IF v_soc <= v_reserve + v_burn_guard     THEN -> 'critical_reserve'   (PREDICTIVE)
--   line 129: IF v_soc <= v_reserve + v_reserve_margin THEN -> 'low_soc_reserve'    (FLAT)
--
-- The predictive rung asks the right question -- "will this vehicle run out
-- before it gets home?" -- and then answers it without consulting the vehicle.
-- EVERY input to v_burn_guard is a dial: a policy burn rate, a policy ETA
-- (ottoq_return_eta_minutes ignores both its vehicle and depot arguments and
-- returns a run constant), and a horizon parameter. The only term that could
-- vary per vehicle is the ETA, and it does not vary at all.
--
-- Measured from the engine's own return_evidence over 44,137 dispatches:
--   v_burn_guard   takes exactly 8 distinct values:
--                  6.04, 6.05, 6.06, 6.09, 6.40, 6.67, 12.00, 15.00
--   reserve_margin takes 2:  15, 25
--   depot-scope policy: p99_burn_pct_per_min = 0.20, reserve_margin_pct = 25
--     -> 0.20 * (30 + 30) = 12.00, against a flat margin of 25
--
-- Eight numbers for 44,137 vehicles. The guard is smaller than the flat margin
-- in essentially every configuration, so the flat rung fires first and the
-- predictive one is dominated: low_soc_reserve 3,355 firings against
-- critical_reserve 40. A per-run constant wearing a prediction's clothes.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS MIGRATION DOES **NOT** CLAIM, because an earlier draft got it wrong
--
-- It does NOT claim the p99 dial is mis-set. An earlier measurement of burn
-- rate taken across whole VEHICLE-RUNS (first packet to last, spanning several
-- trips and the charging between them) put the true p99 at 0.3015 and called
-- the 0.25 default a p95. That instrument was wrong -- it measured the wrong
-- population. Re-measured per DISPATCH (one trip: dispatched_at ->
-- returning_started_at, drop > 0, elapsed > 5 min), over 89,430 trips:
--
--   mean 0.1101 | p50 0.1078 | p90 0.1760 | p95 0.2015 | p99 0.2495 | max 0.5202
--   exceeding the 0.25 default:        886  (1.0%)
--   exceeding the 0.20 depot override: 4,922 (5.5%)
--
-- So the DEFAULT 0.25 is the true p99, correctly calibrated, and this migration
-- leaves it alone. What survives is (a) the depot override of 0.20 is really a
-- p94 under a name that says p99 -- noted, not changed here, it is a data row
-- and not this function's business -- and (b) the structural defect above.
--
-- ---------------------------------------------------------------------------
-- THE CHANGE, AND WHY IT IS MONOTONE-SAFER
--
-- A new function measures the vehicle's OWN burn over its CURRENT trip from
-- telemetry it already emits. The dial then becomes a FLOOR:
--
--   v_burn_per_min := GREATEST(COALESCE(measured, 0), dial)
--
-- so the guard can only ever GROW. No vehicle receives a smaller safety margin
-- than it does today; a vehicle burning faster than the fleet p99 gets a larger
-- one and is recalled earlier. That direction is the entire point of having a
-- predictive rung, and it makes the change strictly safety-increasing rather
-- than a behaviour trade.
--
-- The TIME half of the guard (v_eta_min) stays the constant 30 -- fixing it
-- requires vehicle position, and there is none: ottoq_telemetry_packets
-- .current_lat/.current_lng are the only latitude/longitude columns in the
-- database and both are NULL in all 406,054 rows. That is recorded as a
-- separate, unfixed gap; this migration does not pretend to close it.
--
-- ---------------------------------------------------------------------------
-- WHY THE EDIT IS A SERVER-SIDE SUBSTITUTION AND NOT A PASTED FUNCTION BODY
--
-- ottoq_recall_naive_threshold_v1 is 12,063 bytes of prosrc. Re-typing it into
-- this file to change one line invites a transcription defect in 12 KB of
-- text that no reviewer would catch. Instead this migration reads the live
-- definition, replaces ONE exact line, and executes the result -- after
-- asserting the line occurs EXACTLY ONCE (P2) and that the source is byte-for-
-- byte what this migration was written against (P1, prosrc md5). It is still a
-- CREATE OR REPLACE, and the diff a reviewer must check is the two lines
-- printed below rather than 12 KB of copied source.
--
--   OLD: '  v_burn_per_min   := ottoq_policy_get(p_sim_run_id,''p99_burn_pct_per_min'',0.25);'
--   NEW: the GREATEST(...) form, floor preserved
--
-- ---------------------------------------------------------------------------
-- DETERMINISM. ottoq_telemetry_packets is ottoq_run_scope_registry class
-- 'engine' -- run-scoped working data -- so an unscoped read of it is the
-- 0145/0146 defect class. The new function copies the scoping discipline of
-- the read ALREADY in this very function (its lines 34-39), which is correct
-- on all three counts: run-scoped, bounded by the SIM clock and never the wall
-- clock (G15), and ordered with a packet_seq tiebreak so ties cannot resolve
-- differently between two arms. Index idx_telem_vehicle_time
-- (vehicle_id, sim_clock_at DESC) already serves it.
--
-- forces_recert: TRUE. This changes recall behaviour inside the certified path
-- and the recall stream is one of the fourteen atoms. The floor will move to
-- this migration's stamp and every canon column must be re-earned. The lineage
-- row is written IN THIS FILE.
-- ===========================================================================

DO $pre$
DECLARE v_md5 text; v_hits int; v_floor timestamptz; v_cols int;
BEGIN
  -- P1. THE SOURCE IS EXACTLY WHAT THIS MIGRATION WAS WRITTEN AGAINST.
  SELECT md5(p.prosrc) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_recall_naive_threshold_v1';
  IF v_md5 IS DISTINCT FROM '50b7bf11b14ae952b1f8326f37da58af' THEN
    RAISE EXCEPTION '0313 P1: ottoq_recall_naive_threshold_v1 prosrc md5 is %, expected '
                    '50b7bf11b14ae952b1f8326f37da58af; the function changed after this migration was written',
                    COALESCE(v_md5,'ABSENT');
  END IF;

  -- P2. THE LINE TO REPLACE OCCURS EXACTLY ONCE. A substitution that matched
  --     twice, or zero times, must not be guessed at.
  SELECT count(*) INTO v_hits FROM regexp_matches(
    (SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='ottoq_recall_naive_threshold_v1'),
    'v_burn_per_min\s+:=', 'g');
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0313 P2: expected exactly 1 assignment of v_burn_per_min, found %', v_hits;
  END IF;

  -- P3. THE CERTIFICATION IS NOT MID-FLIGHT AND IS HEALTHY BEFORE WE MOVE THE
  --     FLOOR. pg_stat_activity is the ONLY authority -- ottoq_sim_runs.status
  --     is MVCC-invisible to an uncommitted determinism pair.
  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE state='active' AND pid <> pg_backend_pid()
                AND (query ILIKE '%determinism_pair%' OR query ILIKE '%cert_arm%' OR query ILIKE '%ab_pair%')) THEN
    RAISE EXCEPTION '0313 P3: a certification pair is in flight; this migration moves the recert floor';
  END IF;
  SELECT count(*) INTO v_cols FROM public.ottoq_cert_matrix();
  IF v_cols < 1 THEN
    RAISE EXCEPTION '0313 P3: ottoq_cert_matrix() returns % columns; the matrix is already broken and this '
                    'migration would hide the cause', v_cols;
  END IF;
  SELECT public.ottoq_cert_recert_floor() INTO v_floor;
  RAISE NOTICE '0313: recert floor before this migration is % with % canon column(s); both will change', v_floor, v_cols;
END $pre$;

-- ---------------------------------------------------------------------------
-- (1) THE MEASUREMENT. New function, so there is no replacement risk here.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_measured_burn_pct_per_min(
  p_vehicle_id uuid, p_sim_run_id uuid, p_sim_clock_now timestamp with time zone)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_from timestamptz; v_s0 numeric; v_t0 timestamptz;
  v_s1 numeric; v_t1 timestamptz; v_min numeric;
BEGIN
  -- THIS TRIP ONLY. Measuring across a whole vehicle-run spans several trips
  -- and the charging between them, which is exactly the instrument error the
  -- header retracts; the window starts at the current dispatch.
  SELECT d.dispatched_at INTO v_from
    FROM public.ottoq_vehicle_dispatches d
   WHERE d.vehicle_id = p_vehicle_id
     AND d.sim_run_id = p_sim_run_id              -- run-scoped: class 'engine'
     AND d.status IN ('active','returning')
     AND d.dispatched_at IS NOT NULL
   ORDER BY d.dispatched_at DESC, d.dispatch_id DESC   -- deterministic tiebreak
   LIMIT 1;
  IF v_from IS NULL THEN RETURN NULL; END IF;

  SELECT tp.soc_pct, tp.sim_clock_at INTO v_s0, v_t0
    FROM public.ottoq_telemetry_packets tp
   WHERE tp.vehicle_id = p_vehicle_id
     AND tp.sim_run_id = p_sim_run_id
     AND tp.sim_clock_at >= v_from
     AND tp.sim_clock_at <= p_sim_clock_now       -- SIM clock, never the wall clock
     AND tp.soc_pct IS NOT NULL
   ORDER BY tp.sim_clock_at ASC, tp.packet_seq ASC
   LIMIT 1;

  SELECT tp.soc_pct, tp.sim_clock_at INTO v_s1, v_t1
    FROM public.ottoq_telemetry_packets tp
   WHERE tp.vehicle_id = p_vehicle_id
     AND tp.sim_run_id = p_sim_run_id
     AND tp.sim_clock_at >= v_from
     AND tp.sim_clock_at <= p_sim_clock_now
     AND tp.soc_pct IS NOT NULL
   ORDER BY tp.sim_clock_at DESC, tp.packet_seq DESC
   LIMIT 1;

  IF v_s0 IS NULL OR v_s1 IS NULL OR v_t1 <= v_t0 THEN RETURN NULL; END IF;

  v_min := EXTRACT(EPOCH FROM (v_t1 - v_t0))/60.0;

  -- A validity guard, not a tunable: below this the ratio is dominated by the
  -- SoC quantisation rather than by the burn. Deliberately NOT a dial -- the
  -- catalogue (0302/0304/0305) gates every dial and a new one would need a row;
  -- 10 minutes is twice the 5-minute floor used in the measurement quoted in
  -- this migration's header.
  IF v_min < 10.0 THEN RETURN NULL; END IF;

  -- Charged or flat over the window: no burn signal to report. Returning 0
  -- here would be a measurement, not an absence, and the caller's GREATEST
  -- would treat it as one.
  IF (v_s0 - v_s1) <= 0 THEN RETURN NULL; END IF;

  RETURN round((v_s0 - v_s1) / v_min, 4);
END;
$function$;

COMMENT ON FUNCTION public.ottoq_measured_burn_pct_per_min(uuid,uuid,timestamptz) IS
'This vehicle''s own state-of-charge burn rate in percent per minute, measured over its CURRENT trip from '
'telemetry it already emits. Returns NULL rather than a number when the measurement would not be honest: '
'no active dispatch, fewer than two usable packets, under 10 minutes elapsed, or a non-negative SoC delta '
'(charged or flat). Callers must treat NULL as "unknown" and fall back, never as zero. Run-scoped and '
'bounded by the SIM clock because ottoq_telemetry_packets is run-scope class ''engine''; ordered with a '
'packet_seq tiebreak so two certification arms cannot resolve a tie differently. Added by 0313 so the '
'predictive recall rung in ottoq_recall_naive_threshold_v1 can distinguish one vehicle from another -- '
'before 0313 its guard took 8 distinct values across 44,137 dispatches. Fleet reference, measured per '
'dispatch over 89,430 trips: p50 0.1078, p90 0.1760, p99 0.2495, max 0.5202.';

-- ---------------------------------------------------------------------------
-- (2) THE ONE-LINE SUBSTITUTION, asserted rather than assumed.
-- ---------------------------------------------------------------------------
DO $swap$
DECLARE
  v_def text; v_new text;
  c_old CONSTANT text := '  v_burn_per_min   := ottoq_policy_get(p_sim_run_id,''p99_burn_pct_per_min'',0.25);';
  c_new CONSTANT text :=
    '  -- 0313: the vehicle''s OWN measured burn, with the p99 dial as a FLOOR.' || E'\n' ||
    '  -- GREATEST, never LEAST: the guard may only grow, so no vehicle ever gets' || E'\n' ||
    '  -- a smaller safety margin than it had before 0313. NULL (unmeasurable)' || E'\n' ||
    '  -- collapses to the dial via COALESCE.' || E'\n' ||
    '  v_burn_per_min   := GREATEST(' || E'\n' ||
    '    COALESCE(public.ottoq_measured_burn_pct_per_min(p_vehicle_id, p_sim_run_id, p_sim_clock_now), 0),' || E'\n' ||
    '    ottoq_policy_get(p_sim_run_id,''p99_burn_pct_per_min'',0.25));';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_recall_naive_threshold_v1';

  IF position(c_old in v_def) = 0 THEN
    RAISE EXCEPTION '0313 SWAP: the exact target line was not found in the live definition';
  END IF;
  -- Count LITERAL occurrences by length arithmetic. An earlier draft escaped
  -- c_old into a regex to use regexp_matches; escaping a 78-character line
  -- containing parentheses, quotes and a dot into a correct regex is exactly
  -- the kind of cleverness that fails silently and passes. This cannot.
  IF (length(v_def) - length(replace(v_def, c_old, ''))) / length(c_old) <> 1 THEN
    RAISE EXCEPTION '0313 SWAP: the target line does not occur exactly once';
  END IF;

  v_new := replace(v_def, c_old, c_new);
  IF v_new = v_def THEN
    RAISE EXCEPTION '0313 SWAP: substitution produced an identical definition';
  END IF;
  EXECUTE v_new;
END $swap$;

DO $post$
DECLARE v_md5 text; v_src text; v_n int; v_nonnull int; v_max numeric; v_min numeric;
BEGIN
  SELECT md5(p.prosrc), p.prosrc INTO v_md5, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_recall_naive_threshold_v1';

  -- A1. THE SWAP LANDED and the dial survived as the floor.
  IF v_md5 = '50b7bf11b14ae952b1f8326f37da58af' THEN
    RAISE EXCEPTION '0313 A1: prosrc md5 unchanged; the replacement did not take';
  END IF;
  IF position('ottoq_measured_burn_pct_per_min' in v_src) = 0 THEN
    RAISE EXCEPTION '0313 A1: the new definition does not call the measurement function';
  END IF;
  IF position('p99_burn_pct_per_min' in v_src) = 0 THEN
    RAISE EXCEPTION '0313 A1: the p99 dial vanished; it must remain as the FLOOR, not be replaced';
  END IF;
  IF position('GREATEST(' in v_src) = 0 THEN
    RAISE EXCEPTION '0313 A1: GREATEST is absent; the guard could now shrink below the dial';
  END IF;

  -- A2. THE FUNCTION STILL COMPILES AND STILL HAS ONE DEFINITION.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_recall_naive_threshold_v1') <> 1 THEN
    RAISE EXCEPTION '0313 A2: ottoq_recall_naive_threshold_v1 is no longer a single definition';
  END IF;

  -- A3. THE MEASUREMENT ACTUALLY MEASURES. Run it over every vehicle currently
  --     deployed: it must not error, it must return a real number for at least
  --     one of them, and every number must be physically sane. A function that
  --     returned NULL for everything would pass A1 and change nothing.
  SELECT count(*), count(x.burn), max(x.burn), min(x.burn)
    INTO v_n, v_nonnull, v_max, v_min
    FROM (SELECT public.ottoq_measured_burn_pct_per_min(
                   d.vehicle_id, d.sim_run_id,
                   COALESCE(r.sim_clock_current, r.sim_clock_start)) AS burn
            FROM public.ottoq_vehicle_dispatches d
            JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
           WHERE d.status IN ('active','returning')
             AND COALESCE(r.sim_clock_current, r.sim_clock_start) IS NOT NULL) x;

  IF v_n = 0 THEN
    RAISE NOTICE '0313 A3: no deployed vehicles to measure right now; measurement unexercised at apply time';
  ELSE
    IF v_nonnull = 0 THEN
      RAISE EXCEPTION '0313 A3: the measurement returned NULL for all % deployed vehicles; '
                      'the guard would silently stay exactly as it was', v_n;
    END IF;
    IF v_max > 2.0 OR v_min < 0 THEN
      RAISE EXCEPTION '0313 A3: measured burn out of physical range (min %, max % pct/min)', v_min, v_max;
    END IF;
    RAISE NOTICE '0313 A3 OK -- % of % deployed vehicles yielded a measured burn, range % to % pct/min',
                 v_nonnull, v_n, v_min, v_max;
  END IF;

  RAISE NOTICE '0313 applied. ottoq_recall_naive_threshold_v1 prosrc md5 is now %. '
               'RECERT REQUIRED: every canon column must be re-earned.', v_md5;
END $post$;

-- The lineage row, IN THIS FILE.
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0313_the_predictive_recall_rung_takes_eight_values_and_none_of_them_is_the_vehicle', true,
   'The predictive recall rung''s guard (v_burn_guard = burn_rate * (eta + horizon)) was built entirely '
   'from dials and so took exactly 8 distinct values across 44,137 dispatches, smaller than the flat '
   'reserve margin in nearly every configuration -- low_soc_reserve fired 3,355 times against '
   'critical_reserve 40. 0313 adds ottoq_measured_burn_pct_per_min and makes the p99 dial a FLOOR under '
   'the vehicle''s own measured burn (GREATEST, so the guard may only grow and no vehicle loses margin). '
   'This changes recall behaviour inside the certified path and the recall stream is one of the fourteen '
   'atoms, so forces_recert=true: the floor moves and every canon column must be re-earned. The p99 '
   'default 0.25 is NOT changed -- re-measured per dispatch over 89,430 trips it is the true p99 (0.2495) '
   'and is correctly calibrated; an earlier vehicle-run measurement that called it a p95 was the wrong '
   'instrument and is retracted in this migration''s header.',
   now())
ON CONFLICT (name) DO NOTHING;
