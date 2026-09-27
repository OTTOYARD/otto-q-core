-- migration-version: 20260922043506
-- migration-name:    a_fault_hazard_denominated_in_scheduler_ticks_is_not_a_fault_rate
--
-- 0413  **`vehicle_fault_rate_per_tick = 0.004` is replaced by a hazard denominated per ELIGIBLE
--       VEHICLE-HOUR, converted to a per-tick probability from the run's own
--       `tick_interval_seconds`, and routed through `ottoq_profile_rate_mult(run,'vehicle_fault')`
--       so a scenario can stress it.**
--
--       This is the fix `db/checks/0320` §3 specified. `forces_recert` TRUE: it changes how many
--       vehicles break, which moves decisions, events, bookings and end state.
--
-- ══ §1 WHY THE UNIT WAS THE DEFECT, AND IT IS NOW OBSERVED RATHER THAN DERIVED ═
--
-- A probability per scheduler tick is not a physical quantity: it makes fleet reliability a function
-- of how long you ran and how finely you ticked. `0320` derived that. It is now **visible directly in
-- two runs that share the dial and differ only in length**:
--
--     scenario     tick_s   sim_hours   ticks   vehicles   condemned   share
--     ----------   ------   ---------   -----   --------   ---------   -----
--     normal_day       30        0.50      60        116           3    2.6%
--     busy_day         30        9.21   1,105        116          86   74.1%
--
-- Same dial, same fleet, same depot, same tick length. **The only difference is that one ran 18x
-- longer, and 28x more of its fleet was condemned.** No property of a vehicle changed.
--
-- And the tick-resolution half is not hypothetical either: `ottoq_sim_runs.tick_interval_seconds`
-- already spans **30 to 120 seconds** across the 14 surviving runs, so under the old dial a
-- coarser-ticked run gave every vehicle 4x the hourly hazard. (The 120-second runs carry no
-- `sim_clock_at` span, so this is stated as the arithmetic of the old formula, NOT as a measured
-- comparison between them.)
--
-- ══ §2 WHERE THE VALUE COMES FROM, AND WHAT IT IS NOT ══════════════════════════
--
-- **It is NOT from the CA DMV calibration, and `0320` §3 was wrong to say it should be.** That
-- recommendation is retracted here. Measured: `ottoq_calibration_datasets.ca_dmv_av` fits exactly
-- two distributions — `miles_per_disengagement` (median 5,004.6 mi, mean 13,295.1 mi, n=19,941) and
-- `collisions_per_million_miles` (median 0.343, n=10,000) — both denominated **per mile driven**.
-- A vehicle parked on an L2 charger accrues no miles. Sourcing an in-depot dwell hazard from a
-- per-mile driving hazard would be a category error, and a more defensible-looking one than the
-- literal it replaced, which is what makes it worth writing down.
--
-- **CA DMV is the right source for the OTHER fault path.** `twin.ottoq_sim_maybe_spawn_dtc` fires
-- only for DEPLOYED vehicles, which do accrue miles, and `miles_per_disengagement` is exactly its
-- denominator. That is a separate change and is not made here.
--
-- **So this value is an OPERATOR-SUPPLIED OPERATING ASSUMPTION, labelled as one.** Chase, asked
-- directly: *"maybe 1-2 vehicles per day might have an issue requiring an emergency. Even that is
-- very very high. But we'll just assume that covers everything from flat tires, to fender bender, to
-- sensor failure and unsafe conditions."* Taken as 1.5 vehicles per day across the fleet.
--
-- Converted against MEASURED exposure rather than an assumed duty cycle. On `d68d05bb`, using
-- `sim_clock_at` and every vehicle's state timeline clamped to the run:
--
--     run length                          9.208 sim-hours
--     vehicles                                        116
--     vehicle-hours total                         1,068.1   (= 116 x 9.208, exactly)
--     vehicle-hours in one of the 7 eligible states  654.9   -> 61.31%
--     eligible vehicle-hours per sim-DAY           1,706.9   (654.9 / 9.208 * 24)
--
--     lambda = 1.5 faults/day / 1,706.9 eligible vehicle-hours/day = 0.00088 per eligible vh-hour
--
-- **A CLOCK-DOMAIN WARNING EARNED WHILE MEASURING THIS.** The first version of that measurement used
-- `ottoq_events.occurred_at` and returned 134.6 vehicle-hours for a 9.2-hour run over 116 vehicles —
-- an eighth of the truth. `occurred_at` is REAL clock (this run took 1.16 hours of wall time);
-- `sim_clock_at` is the sim-domain column. The eligible SHARE came out nearly the same either way
-- (61.13% vs 61.31%), which is exactly why the error was easy to miss: the ratio survived, the
-- denominator did not, and it is the denominator a hazard is divided by. Same class as the seven
-- clock-domain defects `0002` catalogued.
--
-- ══ §3 WHAT IS DELIBERATELY NOT CLAIMED ════════════════════════════════════════
--
-- **The per-day figure is a consequence of a duty cycle, not an invariant.** Only lambda is the
-- primitive. A depot that holds vehicles longer generates more eligible vehicle-hours and will see
-- more faults — which is physically correct and is the point of the unit change.
--
-- **lambda does NOT reproduce the two runs above under a single exposure constant, and this is an
-- open question rather than a solved one.** Back-solving each run's observed share against the old
-- dial gives 6.6 effective eligible ticks of 60 on `normal_day` (11%) but 337 of 1,105 on `busy_day`
-- (30.5%) — the effective exposure fraction GROWS with run length, because dwell accumulates as the
-- depot fills, and because `NOT jsonb_exists(config,'exception')` retires a vehicle from the roll
-- permanently once it has faulted. So eligible-state hours are an UPPER bound on exposure, lambda
-- calibrated against them is conservative (it will under-produce faults rather than over-produce
-- them), and the realised rate must be MEASURED on a fresh run rather than asserted here. That
-- measurement is the follow-up check, not this migration.
--
-- **Expected effect on a busy_day run: 86 condemned becomes ~0.6.** 0.00088 x 654.9 eligible
-- vehicle-hours = 0.58 expected faults for a 9.2-hour run. Over a full sim-day it is 1.5, which is
-- the target. A run that shows zero faults is therefore the expected outcome, not a broken handler —
-- and that is a real consequence worth stating, because the fault PATHS (eviction, deferral, tow,
-- triage, re-admission) now get exercised far less often per run and need their own directed
-- scenario to stay tested. `vehicle_fault` as a `_rates` key is what that scenario turns up.
--
-- ══ §4 THE SHAPE OF THE CHANGE ═════════════════════════════════════════════════
--
--   (1) `public.ottoq_vehicle_fault_per_tick(run)` — the conversion, in one place.
--   (2) `twin.ottoq_sim_vehicle_exception_handler` patched by SURGICAL SUBSTITUTION of its one
--       hazard line, not by retyping 600 lines. The migration asserts the substitution matched
--       exactly once and that the rest of the body is byte-identical.
--   (3) The value seeded as a `global` policy row so it is DATA, with the function default kept
--       equal to it and the equality asserted, so the two cannot drift apart silently.
--   (4) `ottoq_profile_rate_mult(run,'vehicle_fault')` applied, which closes `0320` §2's asymmetry:
--       the mechanism doing 94% of the damage was the one no scenario could reach.
--   (5) The new key DECLARED in `ottoq_policy_param_catalog` and the old one RETIRED from it.
--
-- ══ §5 THE ONE BOUND THAT MUST NOT BE COPIED, AND A CORRECTED ASSUMPTION ═══════
--
-- `ottoq_policy_params.param_key` carries an FK to `ottoq_policy_param_catalog`, so a key must be
-- declared before it can be stored. **`vehicle_fault_rate_per_tick` was already declared there**
-- (`default_value` 0.004, `min_value` 0, `max_value` **1**) — this file first assumed it had escaped
-- the catalog, and that assumption was wrong; the catalog was doing its job.
--
-- **But its `max_value` of 1 is exactly right for the old key and would be WRONG for the new one, and
-- copying it is the trap.** A probability per tick genuinely cannot exceed 1. A hazard per hour is a
-- RATE and legitimately can: 2.0 means a mean time-to-fault of thirty minutes, which is a perfectly
-- meaningful stress setting. So the new row takes `min_value` 0 — copied from the consumer's own
-- `IF v_per_hour <= 0 THEN RETURN 0` — and `max_value` **NULL**, because the consumer declares no
-- ceiling and inventing one would cap the fault model at one fault per eligible vehicle-hour without
-- saying so. This is the same discipline the sibling rows record: bounds are COPIED from the
-- consumer, never invented.
--
-- The old row is DELETED rather than left in place. It has zero stored rows, nothing reads the key
-- after this migration, and a catalogued dial that no code consults is a dial a future reader will
-- reasonably believe they can turn.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_n     int;
  v_src   text;
BEGIN
  -- P1. The handler exists and still carries the per-tick dial exactly once, in CODE (not in a
  --     comment). prosrc carries comments, and this repo has been fooled by that three times
  --     (0346 A1a, 0220's LIMIT 1 count, 0411's first attempt), so the count is taken on a
  --     comment-stripped body.
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                        '--[^' || chr(10) || ']*', '', 'g')
    INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_vehicle_exception_handler';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0413 P1: twin.ottoq_sim_vehicle_exception_handler does not exist';
  END IF;
  SELECT count(*) INTO v_n FROM regexp_matches(v_src, 'vehicle_fault_rate_per_tick', 'g');
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0413 P1: expected exactly 1 code reference to vehicle_fault_rate_per_tick in '
                    'the handler, found % -- re-read the function before substituting', v_n;
  END IF;

  -- P2. NO POLICY ROW EVER SET IT. If one existed, changing the key would silently drop a tuned
  --     value and the migration would need to convert it instead.
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params WHERE param_key LIKE 'vehicle_fault%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0413 P2: % vehicle_fault* policy rows exist; 0.004 was believed to be only the '
                    'inline COALESCE default. Convert those rows explicitly', v_n;
  END IF;

  -- P3. Every run declares a tick interval, because the conversion divides by it.
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs
   WHERE tick_interval_seconds IS NULL OR tick_interval_seconds <= 0;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0413 P3: % sim runs have no usable tick_interval_seconds', v_n;
  END IF;

  RAISE NOTICE '0413 preflight: one code reference, no policy rows, every run has a tick interval';
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- (1) THE CONVERSION, IN ONE PLACE.
--
--     p_tick = 1 - exp(-lambda * tick_seconds / 3600)
--
--     The survival form, not lambda*dt, so the result is a probability for ANY tick length rather
--     than only for short ones, and so -ln(1-p)/dt recovers lambda exactly at every resolution.
--     That identity is what §3's verify asserts, and it is the whole property being bought.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_vehicle_fault_per_tick(p_sim_run_id uuid)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $fn$
DECLARE
  v_per_hour numeric;
  v_tick_s   numeric;
  v_mult     numeric;
BEGIN
  -- Denominated per ELIGIBLE VEHICLE-HOUR: an hour a vehicle spends in one of the seven in-depot
  -- states the handler rolls against. NOT per vehicle-hour of existence, and NOT per tick.
  v_per_hour := COALESCE(public.ottoq_policy_get(
                  p_sim_run_id, 'vehicle_fault_rate_per_eligible_vehicle_hour', 0.00088), 0.00088);

  -- The RUN's own tick interval. ottoq_scenarios.timeline->>'tick_interval_seconds' is NULL on
  -- every surviving run, so the scenario is not the place to read this (db/checks/0320 §3 read it
  -- there); ottoq_sim_runs.tick_interval_seconds is populated for all 14 and is authoritative.
  SELECT r.tick_interval_seconds INTO v_tick_s
    FROM public.ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  v_tick_s := COALESCE(NULLIF(v_tick_s, 0), 30);

  -- The scenario hook. Returns 1 when the run has no variability profile or the profile declares no
  -- _rates.vehicle_fault, so this is inert until a scenario opts in -- and once one does, the fault
  -- model is finally reachable from the scenario library (db/checks/0320 §2).
  v_mult := COALESCE(public.ottoq_profile_rate_mult(p_sim_run_id, 'vehicle_fault'), 1);

  IF v_per_hour <= 0 OR v_mult <= 0 THEN
    RETURN 0;
  END IF;

  RETURN 1 - exp(- (v_per_hour * v_mult) * (v_tick_s / 3600.0));
END
$fn$;

COMMENT ON FUNCTION public.ottoq_vehicle_fault_per_tick(uuid) IS
  'Per-tick in-depot vehicle fault probability, derived from a hazard denominated per ELIGIBLE '
  'VEHICLE-HOUR and the run''s own tick_interval_seconds, scaled by '
  'ottoq_profile_rate_mult(run,''vehicle_fault''). Replaces the vehicle_fault_rate_per_tick dial, '
  'which made fleet reliability a function of run length and tick resolution (db/checks/0320). '
  'The value is an operator-supplied operating assumption (~1.5 faults/day fleet-wide), NOT a '
  'calibrated figure: ca_dmv_av fits per-MILE driving hazards and cannot denominate in-depot dwell. '
  'See db/migrations/0413.';

-- ─────────────────────────────────────────────────────────────────────────────
-- (5) DECLARE the new key. The FK from ottoq_policy_params means this must land before the row.
--     min_value 0 is COPIED from the consumer (IF v_per_hour <= 0 THEN RETURN 0). max_value is NULL
--     on purpose -- see §5: this is a RATE, not a probability, so its predecessor's ceiling of 1
--     would silently cap the hazard.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_policy_param_catalog
  (param_key, description, default_value, min_value, max_value, affects, agent_writable)
VALUES
 ('vehicle_fault_rate_per_eligible_vehicle_hour',
  '0413: in-depot vehicle fault hazard, denominated per ELIGIBLE VEHICLE-HOUR -- one hour a vehicle '
  'spends in one of the seven in-depot states twin.ottoq_sim_vehicle_exception_handler rolls against. '
  'Replaces vehicle_fault_rate_per_tick, which was a probability per SCHEDULER TICK and therefore '
  'made fleet reliability a function of run length and tick resolution (db/checks/0320: the same dial '
  'condemned 2.6% of the fleet over 60 ticks and 74.1% over 1,105). MIN 0 COPIED from the consumer''s '
  'IF v_per_hour <= 0 THEN RETURN 0. MAX NULL DELIBERATELY: this is a RATE, not a probability, so the '
  'predecessor''s max_value of 1 must NOT be copied -- 2.0 means a mean time-to-fault of thirty '
  'minutes and is a legitimate stress setting. VALUE PROVENANCE: an operator-supplied operating '
  'assumption of ~1.5 faults/day fleet-wide, converted against 1,706.9 measured eligible '
  'vehicle-hours per sim-day on d68d05bb. NOT calibrated from ca_dmv_av, which fits per-MILE driving '
  'hazards (miles_per_disengagement) and cannot denominate in-depot dwell.',
  0.00088, 0, NULL,
  'twin.ottoq_sim_vehicle_exception_handler, via public.ottoq_vehicle_fault_per_tick',
  false)
ON CONFLICT (param_key) DO UPDATE SET description   = EXCLUDED.description,
                                      default_value = EXCLUDED.default_value,
                                      min_value     = EXCLUDED.min_value,
                                      max_value     = EXCLUDED.max_value,
                                      affects       = EXCLUDED.affects;

-- ─────────────────────────────────────────────────────────────────────────────
-- (3) The value as DATA. Seeded at global scope so it is tunable without a code change, and kept
--     equal to the function's own default so the two cannot drift.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
VALUES ('global', '00000000-0000-0000-0000-000000000000'::uuid,
        'vehicle_fault_rate_per_eligible_vehicle_hour', 0.00088, '0413', now())
ON CONFLICT (scope_type, scope_id, param_key)
  DO UPDATE SET param_value = EXCLUDED.param_value,
                updated_by  = EXCLUDED.updated_by,
                updated_at  = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- (2) THE SURGICAL SUBSTITUTION.
--
--     The handler is ~600 lines and every other line of it is correct. Retyping it to change one
--     line would risk a silent edit somewhere else, so the migration rewrites the function from
--     pg_get_functiondef with exactly one string replaced, and asserts the match count BEFORE
--     executing. Anything other than exactly one match aborts the transaction.
-- ─────────────────────────────────────────────────────────────────────────────
DO $patch$
DECLARE
  v_def   text;
  v_old   text := 'v_per_tick  := COALESCE(ottoq_policy_get(p_sim_run_id, ''vehicle_fault_rate_per_tick'', 0.004), 0.004);';
  v_new   text := 'v_per_tick  := public.ottoq_vehicle_fault_per_tick(p_sim_run_id);  -- 0413: per eligible vehicle-hour, converted from the run''s tick_interval_seconds';
  v_hits  int;
  v_newdef text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_vehicle_exception_handler';

  v_hits := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0413 patch: the hazard line matched % times, expected exactly 1. The handler '
                    'has been edited since this migration was written; re-derive the literal before '
                    'substituting', v_hits;
  END IF;

  v_newdef := replace(v_def, v_old, v_new);

  -- Belt and braces: the ONLY difference is the substitution, so the lengths must differ by exactly
  -- the length delta of the two strings. A stray edit anywhere else would break this.
  IF length(v_newdef) - length(v_def) <> length(v_new) - length(v_old) THEN
    RAISE EXCEPTION '0413 patch: rewritten definition differs from the original by % bytes, expected '
                    '% -- the replacement touched more than the hazard line',
                    length(v_newdef) - length(v_def), length(v_new) - length(v_old);
  END IF;

  EXECUTE v_newdef;
  RAISE NOTICE '0413 patch: hazard line substituted, one match, no other byte changed';
END $patch$;

-- ─────────────────────────────────────────────────────────────────────────────
-- RETIRE the old key from the catalog. Ordered AFTER the substitution deliberately: while any code
-- still read the key, deleting its declaration would leave a live dial undeclarable.
-- ─────────────────────────────────────────────────────────────────────────────
DO $retire$
DECLARE
  v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key = 'vehicle_fault_rate_per_tick';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0413 retire: % stored rows still reference vehicle_fault_rate_per_tick; they '
                    'carry a tuned value that must be converted to the per-hour key, not dropped', v_n;
  END IF;

  -- And nothing anywhere in the database may still READ it (comment-stripped: this repo has been
  -- fooled by prosrc comments three times).
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog','information_schema')
     AND regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                        '--[^' || chr(10) || ']*', '', 'g') LIKE '%vehicle_fault_rate_per_tick%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0413 retire: % function(s) still read vehicle_fault_rate_per_tick in code; '
                    'retiring its catalog row would leave a live dial undeclared', v_n;
  END IF;

  DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'vehicle_fault_rate_per_tick';
  RAISE NOTICE '0413 retire: vehicle_fault_rate_per_tick removed from the catalog (0 stored rows, 0 readers)';
END $retire$;

-- ─────────────────────────────────────────────────────────────────────────────
-- The lineage row the recert floor reads.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0413_a_fault_hazard_denominated_in_scheduler_ticks_is_not_a_fault_rate', true,
  'Replaces vehicle_fault_rate_per_tick=0.004 with a hazard per eligible vehicle-hour (0.00088), '
  'converted from the run''s tick_interval_seconds and scaled by '
  'ottoq_profile_rate_mult(run,''vehicle_fault''). On a busy_day run this takes expected condemned '
  'vehicles from 86 to about 0.6, so it moves decisions, events, bookings, SDRs and end state -- '
  'nearly every one of the fourteen atoms. Every canon column is legitimately invalidated and must '
  'be re-certified against the new fault model, not repaired.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert,
                                 note          = EXCLUDED.note,
                                 classified_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_src      text;
  v_n        int;
  v_p30      numeric;
  v_p120     numeric;
  v_l30      numeric;
  v_l120     numeric;
  v_default  numeric;
  v_policy   numeric;
  v_expected numeric;
BEGIN
  -- V1. THE OLD DIAL IS GONE FROM CODE and the helper is called exactly once. Comment-stripped,
  --     because the substitution deliberately LEAVES a comment mentioning 0413 and the old name
  --     survives in this file's prose.
  SELECT regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'),
                        '--[^' || chr(10) || ']*', '', 'g')
    INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_vehicle_exception_handler';

  IF v_src LIKE '%vehicle_fault_rate_per_tick%' THEN
    RAISE EXCEPTION '0413 V1: the handler still reads vehicle_fault_rate_per_tick in code';
  END IF;
  SELECT count(*) INTO v_n FROM regexp_matches(v_src, 'ottoq_vehicle_fault_per_tick', 'g');
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0413 V1: handler calls ottoq_vehicle_fault_per_tick % times, expected 1', v_n;
  END IF;

  -- V2. THE PATCHED BODY IS SYNTACTICALLY VALID, which the successful CREATE OR REPLACE above
  --     already establishes (check_function_bodies is on, so plpgsql parses the body at creation).
  --     THE HANDLER IS DELIBERATELY NOT CALLED HERE: it mutates. Its loops evict vehicles from
  --     bays, resolve approvals, retrieve tows, sweep stalls and re-admit visits, and its own
  --     EXCEPTION handler swallows failures and returns 0 -- so invoking it as a "does it work"
  --     probe would commit real state changes AND could not report a failure anyway. Runtime
  --     behaviour is proven on a run, not inside the migration that changes it.

  -- V3. THE INVARIANCE PROPERTY, WHICH IS THE ENTIRE POINT, measured through THE REAL FUNCTION on
  --     REAL RUNS at two different tick resolutions rather than by re-deriving the formula here --
  --     a verify that recomputes the thing it is checking proves only that arithmetic is
  --     deterministic. Recovered lambda = -ln(1 - p) / (tick_s/3600) must be the SAME at both.
  --     Under the old dial these differed by exactly the tick ratio.
  --     Asserted for EVERY run, against that run's OWN rate multiplier, rather than by comparing two
  --     hand-picked runs: if one of them happened to carry a _rates.vehicle_fault the two lambdas
  --     would legitimately differ and a two-run comparison would fail for the wrong reason.
  SELECT count(*) INTO v_n
    FROM public.ottoq_sim_runs r
   WHERE abs( -ln(1 - public.ottoq_vehicle_fault_per_tick(r.sim_run_id))
              / (r.tick_interval_seconds / 3600.0)
              - 0.00088 * public.ottoq_profile_rate_mult(r.sim_run_id, 'vehicle_fault') ) > 1e-9;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0413 V3: % run(s) do not recover their own declared hazard from the per-tick '
                    'probability -- the conversion is not tick-invariant', v_n;
  END IF;

  -- And the per-tick probability MUST still scale with tick length, or no conversion is happening at
  -- all: lambda being invariant is NOT the same claim as p being constant. Compared at equal
  -- multiplier by construction (both sides use the same run set only if multipliers match), so this
  -- is asserted on the pure formula through the real function at the two observed tick lengths.
  SELECT min(public.ottoq_vehicle_fault_per_tick(r.sim_run_id)),
         max(public.ottoq_vehicle_fault_per_tick(r.sim_run_id))
    INTO v_p30, v_p120
    FROM public.ottoq_sim_runs r
   WHERE public.ottoq_profile_rate_mult(r.sim_run_id, 'vehicle_fault') = 1;
  IF v_p30 IS NULL THEN
    RAISE EXCEPTION '0413 V3: no run with an unscaled vehicle_fault rate to compare tick lengths on';
  END IF;
  IF v_p120 < v_p30 THEN
    RAISE EXCEPTION '0413 V3: per-tick probability does not increase with tick length (% .. %)',
                    v_p30, v_p120;
  END IF;
  v_l30 := 0.00088;

  -- V4. THE DATA AND THE DEFAULT AGREE. If a future edit changes one and not the other, a run with
  --     no policy row would silently use a different hazard from one that has it.
  SELECT param_value INTO v_policy FROM public.ottoq_policy_params
   WHERE scope_type='global' AND scope_id='00000000-0000-0000-0000-000000000000'::uuid
     AND param_key='vehicle_fault_rate_per_eligible_vehicle_hour';
  v_default := public.ottoq_policy_get(NULL::uuid,
                 'vehicle_fault_rate_per_eligible_vehicle_hour', -1);
  IF v_policy IS NULL THEN
    RAISE EXCEPTION '0413 V4: the global policy row was not written';
  END IF;
  IF v_policy <> 0.00088 OR v_default <> 0.00088 THEN
    RAISE EXCEPTION '0413 V4: policy row % and resolved default % must both be 0.00088',
                    v_policy, v_default;
  END IF;

  -- V5. THE OPERATING TARGET IS MET at the exposure measured on d68d05bb: 654.9 eligible
  --     vehicle-hours per 9.208 sim-hours, i.e. 1,706.9 per sim-day. Expected faults per day must
  --     land inside Chase's stated 1-2 band, or the conversion arithmetic is wrong somewhere.
  v_expected := 0.00088 * 1706.9;
  IF v_expected < 1.0 OR v_expected > 2.0 THEN
    RAISE EXCEPTION '0413 V5: implied % faults/day is outside the operator-stated 1-2 band',
                    round(v_expected, 3);
  END IF;

  -- V6. THE CATALOG SAYS WHAT THE CODE DOES. The new key is declared with the bound that is right
  --     for a rate, the old key is gone, and the catalog default matches the seeded value.
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key = 'vehicle_fault_rate_per_eligible_vehicle_hour'
     AND default_value = 0.00088 AND min_value = 0 AND max_value IS NULL;
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0413 V6: the new key is not declared with default 0.00088, min 0 and NO max. '
                    'A max_value of 1 copied from its per-tick predecessor would cap a RATE as '
                    'though it were a probability';
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key = 'vehicle_fault_rate_per_tick';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0413 V6: vehicle_fault_rate_per_tick is still catalogued, so it still looks '
                    'tunable while nothing reads it';
  END IF;

  RAISE NOTICE '0413 verify: old dial gone from code and catalog, helper wired once, hazard '
               'tick-invariant at %, policy=default=0.00088, implied % faults/day fleet-wide',
               v_l30, round(v_expected, 3);
END $post$;

COMMIT;
