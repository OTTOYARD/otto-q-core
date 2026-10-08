-- migration-version: PENDING
-- migration-name:    the_check_reads_each_cars_open_work
--
-- 0624  **The check reads each car's open work.**
--       0623 gave the check's simulator the depot's own outflow: a charged car leaves after the learned dwell, works
--       down to the reserve and comes back owing a charge. Its dwell was one curve over every charged car, and the
--       grade that came with it said so: each car's chance of leaving inside an order's window scored a Brier of 0.128
--       on run d9d49732's 61 graded orders, worse than the 0.105 of giving every car the run's own share, and the curve
--       expected 0.83 of the departures (G356). Behind that one curve sit cars that leave at once and cars that wait for
--       a bay. 0624 reads, for every car the check models, what it has left to do, and gives each kind its own learned
--       curve on its own clock. Chase, 2026-10-08: "keep tightening the overall Superintelligence and learning of the
--       agent layer ... it can't technically do XYZ, so I should probably build that in." Rule 10 holds: the curves are
--       estimates refitted nightly from real departures, the check is engineering's change, and the one new dial is a
--       person's.
--
-- ══ §1 WHY (G356; run d9d49732, the eight twin runs of 2026-10-01 to 10-08, and the 21 days before each; measured
--    2026-10-08 19:35-20:05 UTC) ══════════════════════════════════════════════════════════════════════════════════════
--
--   (a) What one curve hides. In the 21 days before d9d49732 began, 1,501 charges completed on fine-tick runs. 482
--       ended with nothing left in a bay (`clear`): 479 of those cars left, half within 0.51 minutes of the charge's end
--       and 95% within 10.3. 399 ended owing a must-do service in a bay (`bay`): on each of the ten runs with ten or more
--       of them, the median car left 0.37 to 1.02 minutes after its last bay service was done, and the bays took a
--       median of 19 to 88 minutes after the charge, by run. 620 were cars in the depot since their run began, with no
--       visit (`boot`), which leave when the dispatcher pulls them: median 7.9 minutes. One curve over all three put the
--       median at 7.3 minutes for cars that leave in half a minute.
--   (b) Measured before building, out of sample (the curves fitted through d9d49732's start), on the 61 graded orders
--       and the same 2,712 car-rows 0623's V2 graded. They are 78 distinct cars: the orders are minutes apart and see
--       the same cars, so this is one run's evidence, not 2,712 observations. By class the dwell scores 0.101 against
--       the pooled 0.128 and the base rate's 0.105, and expects 0.88 of the departures (0.83); of the cars that left,
--       0.562 fell under their curve's median for their stretch and 0.800 under its 80th percentile (0.533, 0.799).
--       Rows, cars, pooled -> class: clear 798 of 43, 0.088 -> 0.0014; boot 1,201 of 51, 0.103 -> 0.091; new 85 of 7,
--       0.240 -> 0.234; bay 628 of 21, 0.211 -> 0.230. Bay is the one class the split did not help on this run: its
--       bays ran faster than the 21 days' did (the run's own median 19 minutes from charge to bay done), and the curve
--       expected 0.59 of its departures.
--   (c) Across runs, the test one run cannot be. For each of the eight twin runs from 2026-10-01 to 10-08, the curves
--       fitted through that run's start, each of its charged cars scored on whether it had left 10, 30 and 60 minutes
--       after its charge ended (a car still parked when its run ended before then is not scored there). At 30 minutes,
--       1,069 charges: Brier pooled 0.195, by class 0.100, the base rate 0.189; the classes beat the pooled curve on 8
--       of 8 runs and the base rate on 8 of 8. At 10 minutes 0.249 -> 0.109 (8 and 8 of 8); at 60, 0.147 -> 0.098 (8 of
--       8 against the pooled curve, 7 of 8 against the base rate: d9d49732 the eighth). For the bay cars alone the bay
--       curve beats the pooled one on 8 of 8 runs at 30 minutes (0.389 -> 0.185), 6 of 8 at 60. db/checks/0418 holds
--       the queries.
--   (d) Measured and not built. Grading d9d49732's bay cars on the pooled curve instead scored 0.0966 over its orders
--       (0.101 by class), a choice made after seeing that run, and the bay curve beats the pooled one for bay cars on
--       every run at 30 minutes: not built. What moves the bay curve between runs is the bays' own congestion (19 to 88
--       minutes at the median): a curve that reads the bay queue, or the run's own bay times so far, is G358, open.
--   (e) The class at the clock. A car out at work at the order has a next visit whose work nobody knows yet; 0623's
--       curve treated it like any other. 0624 gives it the visit cars' curve, clear and bay together (`new`): 85 rows of
--       7 cars on d9d49732, 0.240 -> 0.234. And a parked car whose work was done after its charge ended leaves on the
--       clear curve from when it was done, not from the charge: on d9d49732 the clear rows score 0.0014.
--
-- ══ §2 WHAT ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq_dwell_class(atoms, at)`: what a car has left to do at `at`. 'boot' with no visit (NULL atoms), 'bay' while
--       one of its visit's must-do services that needs a bay is open (not done or closed by `at`), else 'clear'.
--   (b) return_v1 learns the dwell by class. `ottoq_return_model_params` (same signature) adds `dwell_by`: the
--       Kaplan-Meier curve, exactly as `dwell` is built, by the car's class when its charge ended (its visit as of the
--       charge's start), and `new`, the visit cars together; each with its counts and the pooled curve's population.
--       One pass over the charges builds both; `dwell` reads only what 0623's read, and it and every other key are
--       0623's (V1). `ottoq_fit_return_model` writes it, unchanged, nightly (5.5 s on live over the 21 days to now).
--   (c) The state reads each car's work. `ottoq_charge_line_outflow` (same signature): with the fit's `dwell_by` and the
--       run's new dial `agent_charge_order_dwell_class` at 1 (its default), the outflow (v 2) carries `dwell_by` (each
--       class's curve that holds 30 departures; a class without them is left out, and its cars take the pooled curve),
--       each modelled car's class at the clock in `ret` (`dc`: 'new' when it is out at work, else its latest visit's),
--       and on each parked clear car `o`, how many minutes after its charge's end its must-do work was done. Without
--       them, 0623's state, key for key (V1).
--   (d) The draw. `ottoq_charge_line_return_draw` (same signature) reads p_car[7], when given, as how many minutes after
--       the charge's end the car's dwell clock starts; without it, 0623's draw.
--   (e) The simulator. `ottoq_charge_line_schedule` (same signature): each car's dwell on its class's curve from its
--       class's clock; the expected future spreads the dwells evenly within each class, so each class's cars cover their
--       own curve; with p_trace each return carries its class. Without `dwell_by`, 0623's result, key for key (V1).
--   (f) The grader. `ottoq_charge_order_forecast_errors(state, real, expected)` grades each car's dwell on its class's
--       curve and reports beside it the pooled curve's score on the same cars (`dwell_pooled`) and the score by class
--       (`dwell_by`), so the morning self-review can see, order by order, whether the classes still beat one curve.
--       Without `dwell_by`, 0623's result (V1). The grader's md5 covers it: the bodies it lists changed.
--   (g) A person's dial, catalogued, not agent-writable: `agent_charge_order_dwell_class` (1; 0 is 0623's pooled dwell).
--
--   The tick path is untouched. The check, the grader and the board run only on runs that take an agent's charge
--   order (0615); the fit writes one row a night.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: every body replaced or relied on is the one this file was written against (md5);
--   nothing this file creates exists. Nothing here drops or deletes anything.
--   V1: (i) the 20 latest stored snapshots, in the expected future and a sampled one, simulate and compare as before
--   this file; (ii) on six of d9d49732's graded orders, each state given 0623's outflow as of its clock (the fit
--   through the run's start): this file's outflow given 0623's fit returns the same state, and the schedule (the
--   expected future of the order that ran, and a sampled future of the agent's order) and the forecast errors on it
--   return what 0623's returned; (iii) the fit through d9d49732's start: every key 0623 computed is as it was, and
--   `dwell_by` is added.
--   V2: THE GATE. On d9d49732's graded orders (the fit through the run's start, so out of sample), each car's chance of
--   leaving inside the window, on its class's curve, must score a Brier under the pooled curve's on the same cars and
--   no worse than the run's base rate; of the cars that left, 40-60% under their curve's median for their stretch and
--   70-90% under its 80th percentile; the departures expected 0.75-1.33 times the real ones, and so the returns the
--   expected future of the order that ran puts inside the window; or nothing here is applied. Reported beside it: the
--   score by class.
--   V3: the fit at apply carries `dwell_by` for each class; the state on a running twin run carries the classes.
--   tests/test_agent_dwell_class_sql.py executes the rest on the miniature depot.
--
-- ══ §4 RECERT ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   FALSE/FALSE. The check, its grader and the board run only on operator_demo runs that take an agent's charge order
--   (0615); no certification, sweep or dial pair arms an order. Without `dwell_by` every reader returns what it returned
--   (V1); the new estimate key is evidence.
--
-- ROLLBACK: set agent_charge_order_dwell_class to 0 on the runs that should not see it (0623's dwell, exactly), or
--   EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0624_pre' (the fit, the outflow, the draw, the
--   schedule and the forecast errors as 0623 left them). DROP FUNCTION public.ottoq_dwell_class(jsonb, timestamptz);
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_dwell_class';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0624_the_check_reads_each_cars_open_work'. The return_v1 rows
--   written since keep their dwell_by key; nothing reads it once rolled back.

BEGIN;

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0624 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)', '43625d1d', 'the return fit''s parameters (0623)'),
      ('public.ottoq_fit_return_model(uuid,timestamp with time zone,interval,text)', '05f61d70', 'the return fit (0623)'),
      ('public.ottoq_charge_line_outflow(uuid,uuid,timestamp with time zone,jsonb,jsonb,jsonb,jsonb)', '4f37247d', 'the outflow (0623)'),
      ('public.ottoq_charge_line_return_draw(double precision[],double precision[],double precision[],double precision,double precision,double precision,integer,text,text,double precision,double precision,double precision,jsonb,double precision)', 'e1c2f4ff', 'the draw (0623)'),
      ('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 'af5ac92d', 'the schedule (0623)'),
      ('public.ottoq_charge_line_simulate(jsonb,jsonb,integer,text)', '265735b2', 'the simulator (0621)'),
      ('public.ottoq_charge_line_compare(jsonb,jsonb)', '5054e2dc', 'the comparison (0623)'),
      ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', '3b9fc780', 'the state (0623)'),
      ('public.ottoq_charge_line_realize(jsonb,jsonb,text[])', '4817598b', 'the realizer (0623)'),
      ('public.ottoq_charge_order_realized(bigint,numeric)', '62914504', 'the realized reader (0623)'),
      ('public.ottoq_charge_order_forecast_errors(jsonb,jsonb,jsonb)', 'ef96a1af', 'the outflow''s forecast errors (0623)'),
      ('public.ottoq_charge_order_forecast_errors(jsonb,jsonb)', '134f7426', 'the forecast errors (0621)'),
      ('public.ottoq_charge_order_grade(bigint,numeric)', 'cf987b52', 'the grade (0623)'),
      ('public.ottoq_hindsight_code_md5()', '322ee2fd', 'the grader''s md5 (0623)'),
      ('public.ottoq_outflow_dwell_cdf(double precision[],double precision,double precision,double precision)', 'e7111686', 'the dwell''s cdf (0623)'),
      ('public.ottoq_outflow_dwell_quantile(double precision[],double precision,double precision,double precision)', 'd857adc7', 'the dwell''s quantile (0623)'),
      ('public.ottoq_learned_estimate(uuid,text)', 'ff910870', 'the latest fit (0619)'),
      ('public.ottoq_charge_clock_run_evidence(jsonb,uuid,timestamp with time zone)', '314444ef', 'the run evidence (0622)'))
    AS x(sig, md5, what)
  LOOP
    IF left((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)), 8) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0624 P1: % is not the body this file was written against (md5 %); read it again', r.what, r.md5;
    END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_dwell_class(jsonb,timestamp with time zone)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_dwell_class') THEN
    RAISE EXCEPTION '0624 P1: something this file creates already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0624_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)'::regprocedure,
                 'public.ottoq_charge_line_outflow(uuid,uuid,timestamp with time zone,jsonb,jsonb,jsonb,jsonb)'::regprocedure,
                 'public.ottoq_charge_line_return_draw(double precision[],double precision[],double precision[],double precision,double precision,double precision,integer,text,text,double precision,double precision,double precision,jsonb,double precision)'::regprocedure,
                 'public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure,
                 'public.ottoq_charge_order_forecast_errors(jsonb,jsonb,jsonb)'::regprocedure);

-- V1's "before" (i): the 20 latest stored snapshots' simulations and comparisons (the expected future and a sampled one;
-- 20, not 0623's 40, so that the apply stays inside 0623's 42 s with the fit and V2's 61 orders: 12 s for 40 on live)
CREATE TEMP TABLE v0624_before ON COMMIT DROP AS
SELECT s.order_id, sc.sc,
       public.ottoq_charge_line_schedule(s.state, NULL, sc.sc, s.seed, true) AS k,
       public.ottoq_charge_line_schedule(s.state, s.agent_order, sc.sc, s.seed, true) AS a,
       public.ottoq_charge_line_compare(public.ottoq_charge_line_simulate(s.state, NULL, sc.sc, s.seed),
                                        public.ottoq_charge_line_simulate(s.state, s.agent_order, sc.sc, s.seed)) AS c
  FROM (SELECT * FROM public.ottoq_charge_order_snapshots ORDER BY order_id DESC LIMIT 20) s
 CROSS JOIN (VALUES (0), (3)) sc(sc);

-- V1's "before" (ii) and (iii): 0623's fit through d9d49732's start, and 0623's outflow, schedule and forecast errors
-- on six of its graded orders
CREATE TEMP TABLE v0624_fit (through timestamptz, params jsonb) ON COMMIT DROP;
CREATE TEMP TABLE v0624_fit_new (params jsonb) ON COMMIT DROP;
CREATE TEMP TABLE v0624_out (order_id bigint, run uuid, depot uuid, clock timestamptz, state0 jsonb, ct jsonb, rt0 jsonb,
                             ev jsonb, seed text, ord jsonb, agent_order jsonb, aug jsonb, rz jsonb, k0 jsonb, a3 jsonb,
                             fe jsonb) ON COMMIT DROP;
DO $before$
DECLARE
  c_run   constant uuid := 'd9d49732-cf28-42c3-aac9-9c3f606a2c92';
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_start timestamptz; v_rt jsonb; r record; v_ct jsonb; v_ev jsonb; v_aug jsonb; v_ret jsonb; v_rz jsonb; v_k jsonb;
BEGIN
  SELECT started_at INTO v_start FROM ottoq_sim_runs WHERE sim_run_id = c_run AND status = 'completed';
  IF v_start IS NULL OR NOT EXISTS (SELECT 1 FROM ottoq_charge_order_hindsight WHERE sim_run_id = c_run) THEN
    RETURN;
  END IF;
  INSERT INTO v0624_fit VALUES (v_start, public.ottoq_return_model_params(c_depot, v_start, interval '21 days'));
  v_rt := jsonb_build_object('usable', true, 'estimate_id', NULL, 'params', (SELECT params FROM v0624_fit));
  FOR r IN
    SELECT h.order_id, h.sim_clock, h.observed_min, h.taken, h.realized, s.state, s.seed, s.agent_order
      FROM ottoq_charge_order_hindsight h JOIN ottoq_charge_order_snapshots s USING (order_id)
     WHERE h.sim_run_id = c_run
     ORDER BY h.order_id
     LIMIT 6
  LOOP
    IF (r.state #>> '{models,charge_time_model}') = 'charge_time_v2' THEN
      SELECT jsonb_build_object('params', f.params) INTO v_ct FROM ottoq_charge_clock_fits f
       WHERE f.fit_id = (r.state #>> '{models,charge_time}')::bigint;
    ELSE
      SELECT jsonb_build_object('params', e.params) INTO v_ct FROM ottoq_learned_estimates e
       WHERE e.estimate_id = (r.state #>> '{models,charge_time}')::bigint;
    END IF;
    v_ev := public.ottoq_charge_clock_run_evidence(v_ct, c_run, r.sim_clock);
    v_aug := public.ottoq_charge_line_outflow(c_run, c_depot, r.sim_clock, r.state, v_ct, v_rt, v_ev);
    CONTINUE WHEN jsonb_typeof(v_aug -> 'outflow') IS DISTINCT FROM 'object';
    -- what each modelled car really did (0623 V2's rule)
    SELECT COALESCE(jsonb_object_agg(c.id, jsonb_strip_nulls(jsonb_build_object(
             'ce', CASE WHEN ce.at IS NOT NULL THEN round((extract(epoch FROM (ce.at - r.sim_clock)) / 60.0)::numeric, 2) END,
             'left', CASE WHEN d.dispatched_at IS NOT NULL
                          THEN round((extract(epoch FROM (d.dispatched_at - r.sim_clock)) / 60.0)::numeric, 2) END,
             'eta', CASE WHEN d.actual_return_at IS NOT NULL AND d.actual_return_at <= r.sim_clock + make_interval(secs => r.observed_min * 60)
                         THEN round((extract(epoch FROM (d.actual_return_at - r.sim_clock)) / 60.0)::numeric, 2) END,
             'soc', CASE WHEN d.actual_return_at IS NOT NULL AND d.actual_return_at <= r.sim_clock + make_interval(secs => r.observed_min * 60)
                         THEN round(d.soc_at_return_pct, 1) END))), '{}'::jsonb)
      INTO v_ret
      FROM (SELECT DISTINCT z.id FROM (
              SELECT x.value ->> 'id' AS id FROM jsonb_array_elements(v_aug -> 'cars') x
              UNION ALL SELECT x.value ->> 'id' FROM jsonb_array_elements(v_aug -> 'inbound') x
              UNION ALL SELECT x.value ->> 'car' FROM jsonb_array_elements(v_aug -> 'chargers') x WHERE x.value ? 'car'
              UNION ALL SELECT x.value ->> 'id' FROM jsonb_array_elements(v_aug #> '{outflow,leaving}') x) z
             WHERE z.id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') c
      LEFT JOIN LATERAL (SELECT dd.dispatched_at, dd.actual_return_at, dd.soc_at_return_pct FROM ottoq_vehicle_dispatches dd
                          WHERE dd.sim_run_id = c_run AND dd.vehicle_id = c.id::uuid
                            AND dd.dispatched_at > r.sim_clock
                            AND dd.dispatched_at <= r.sim_clock + make_interval(secs => r.observed_min * 60)
                          ORDER BY dd.dispatched_at LIMIT 1) d ON true
      LEFT JOIN LATERAL (SELECT max(dd.dispatched_at) AS at FROM ottoq_vehicle_dispatches dd
                          WHERE dd.sim_run_id = c_run AND dd.vehicle_id = c.id::uuid AND dd.dispatched_at <= r.sim_clock) lo ON true
      LEFT JOIN LATERAL (SELECT max(os.ended_at) AS at FROM ocpp_sessions os
                          WHERE os.sim_run_id = c_run AND os.vehicle_id = c.id::uuid AND os.stopped_reason = 'completed'
                            AND os.ended_at <= COALESCE(d.dispatched_at, r.sim_clock + make_interval(secs => r.observed_min * 60))
                            AND (lo.at IS NULL OR os.ended_at > lo.at)) ce ON true;
    v_rz := (r.realized || jsonb_build_object('returns', v_ret))
            || jsonb_build_object('appeared', COALESCE((
                 SELECT jsonb_agg(x.value ORDER BY x.o) FROM jsonb_array_elements(r.realized -> 'appeared') WITH ORDINALITY x(value, o)
                  WHERE NOT (v_ret ? (x.value ->> 'id'))), '[]'::jsonb));
    v_k := public.ottoq_charge_line_schedule(v_aug, CASE WHEN r.taken THEN r.agent_order END, 0, r.seed, true);
    INSERT INTO v0624_out VALUES (r.order_id, c_run, c_depot, r.sim_clock, r.state, v_ct, v_rt, v_ev, r.seed,
                                  CASE WHEN r.taken THEN r.agent_order END, r.agent_order, v_aug, v_rz, v_k,
                                  public.ottoq_charge_line_schedule(v_aug, r.agent_order, 3, r.seed, true),
                                  public.ottoq_charge_order_forecast_errors(v_aug, v_rz, v_k));
  END LOOP;
END $before$;

-- ══ (g) the dial ══════════════════════════════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, agent_writable, affects, description)
VALUES ('agent_charge_order_dwell_class', 0, 1, 1, false, 'ottoq_charge_line_outflow (0624 dwell by class)',
  '0624: whether the kernel''s check on an agent''s charge order times each charged car''s departure by what it has '
  'left to do (nothing, a service in a bay, a run-start car, a car out at work) on that class''s learned curve, or by '
  'one curve over every car. 1 by class; 0 is 0623''s check exactly. A person''s dial, never the agent''s (rule 10).');

-- ══ (a) what a car has left to do ═════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_dwell_class(p_atoms jsonb, p_at timestamptz)
RETURNS text
LANGUAGE sql
STABLE PARALLEL SAFE
AS $fn$
  -- 0624: what a car has left to do at p_at, for its dwell after a charge. 'boot' when it has no visit (p_atoms NULL: in
  -- the depot since its run began); 'bay' while one of its visit's must-do services that needs a bay is open (neither
  -- done nor closed by p_at): it leaves when the bay is done; else 'clear', nothing in a bay holds it. STABLE, not
  -- IMMUTABLE, only because it reads the atoms' times from text.
  SELECT CASE WHEN p_atoms IS NULL THEN 'boot'
              WHEN EXISTS (SELECT 1
                             FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_atoms) = 'array' THEN p_atoms ELSE '[]'::jsonb END) a
                            WHERE COALESCE((a ->> 'must_do')::boolean, false) AND a ->> 'concurrency' = 'bay'
                              AND COALESCE((a ->> 'done_at')::timestamptz, (a ->> 'closed_at')::timestamptz,
                                           'infinity'::timestamptz) > p_at)
              THEN 'bay' ELSE 'clear' END
$fn$;

-- ══ (b) the dwell by class, learned with the return cycle ═════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_return_model_params(p_depot uuid, p_through timestamptz DEFAULT NULL,
                                                 p_window interval DEFAULT interval '21 days')
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
/* 0623: return_v1's parameters for a depot from the evidence in (through - window, through] (real clock), read-only:
   0619's fit key for key (the reserve, the drain, the drive home, the other calls home), plus the dwell: the minutes
   from each completed charge to the car's next departure, Kaplan-Meier with a car still parked when its run ended
   censored at its run's last sim minute, as quantiles at 0, 0.05, ..., 0.95 (NULL past the curve's last step f_max)
   and the last departure seen (max_min). As every part of the fit, the runs at ticks of a minute or less when they hold
   30 departures, else every run.
   0624: and `dwell_by`, the same curve by what the car had left to do when its charge ended (ottoq_dwell_class on its
   visit as of the charge's start): 'clear', 'bay' and 'boot', and 'new', the visit cars together (clear and bay), for a
   car whose next visit's work is not known yet; each with its counts, from the pooled curve's population. Both come
   from one pass over the same rows, and the pooled `dwell` reads only what 0623's read: 0623's curve, unchanged. */
DECLARE
  c_min_n   constant int := 30;
  v_through timestamptz := COALESCE(p_through, now());
  v_from    timestamptz := COALESCE(p_through, now()) - COALESCE(p_window, interval '21 days');
  v_p       jsonb;
  v_dw      jsonb;
  v_dwb     jsonb;                                                                              -- 0624
BEGIN
  IF p_depot IS NULL THEN RAISE EXCEPTION 'ottoq_return_model_params: a depot is required'; END IF;

  -- 0619's fit, unchanged
  WITH a AS MATERIALIZED (
    SELECT x.sim_run_id, x.return_trigger, x.soc0, x.soc_dec, x.fine,
           extract(epoch FROM (x.returning_started_at - x.dispatched_at)) / 60.0 AS work_min,
           extract(epoch FROM (x.actual_return_at - x.returning_started_at)) / 60.0 AS trip_min
      FROM (SELECT d.sim_run_id, d.return_trigger, d.soc_at_dispatch_pct AS soc0, d.dispatched_at, d.returning_started_at,
                   d.actual_return_at,
                   CASE WHEN (d.return_evidence ->> 'soc_at_decision') ~ '^[0-9]+(\.[0-9]+)?$'
                        THEN (d.return_evidence ->> 'soc_at_decision')::numeric END AS soc_dec,
                   COALESCE(r.tick_count > 0 AND r.sim_clock_current IS NOT NULL AND r.sim_clock_start IS NOT NULL
                            AND extract(epoch FROM (r.sim_clock_current - r.sim_clock_start)) / 60.0 / r.tick_count <= 1,
                            false) AS fine
              FROM public.ottoq_vehicle_dispatches d
              JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
             WHERE r.depot_id = p_depot AND d.created_at > v_from AND d.created_at <= v_through
               AND d.actual_return_at IS NOT NULL AND d.returning_started_at IS NOT NULL
               AND COALESCE(d.return_trigger, '') NOT IN ('prime_inbound', 'run_stopped')) x
  ), pop AS (
    SELECT (count(*) FILTER (WHERE fine AND return_trigger = 'low_soc_reserve' AND soc_dec IS NOT NULL) >= c_min_n) AS use_fine
      FROM a
  ), d AS (
    SELECT a.* FROM a, pop WHERE a.fine OR NOT pop.use_fine
  ), low AS (
    SELECT * FROM d WHERE return_trigger = 'low_soc_reserve' AND soc_dec IS NOT NULL
  ), drain AS (
    SELECT ln(((soc0 - soc_dec) / work_min)::float8) AS ld FROM low WHERE work_min >= 5 AND soc0 > soc_dec
  ), dm AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY ld) AS m FROM drain
  )
  SELECT jsonb_build_object(
           'threshold_soc', round((SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY soc_dec) FROM low)::numeric, 2),
           'threshold_p10', round((SELECT percentile_cont(0.1) WITHIN GROUP (ORDER BY soc_dec) FROM low)::numeric, 2),
           'drain_pct_per_min', round((SELECT exp(m) FROM dm)::numeric, 4),
           'drain_log_sd', round((SELECT 1.4826 * percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(dr.ld - dm.m))
                                    FROM drain dr CROSS JOIN dm)::numeric, 4),
           'trip_min', round((SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY trip_min) FROM low WHERE trip_min >= 0)::numeric, 2),
           'trip_p90_min', round((SELECT percentile_cont(0.9) WITHIN GROUP (ORDER BY trip_min) FROM low WHERE trip_min >= 0)::numeric, 2),
           'n_low_soc', (SELECT count(*) FROM low),
           'n_drain', (SELECT count(*) FROM drain),
           'n_returns', (SELECT count(*) FROM d),
           'other_share', round((SELECT avg((return_trigger IS DISTINCT FROM 'low_soc_reserve')::int) FROM d)::numeric, 4),
           'other_per_work_hour', round((SELECT count(*) FILTER (WHERE return_trigger IS DISTINCT FROM 'low_soc_reserve')
                                                / NULLIF(sum(GREATEST(work_min, 0)) / 60.0, 0) FROM d)::numeric, 4),
           'other_triggers', COALESCE((SELECT jsonb_object_agg(t, n) FROM (
                                         SELECT COALESCE(return_trigger, 'unknown') AS t, count(*) AS n FROM d
                                          WHERE return_trigger IS DISTINCT FROM 'low_soc_reserve' GROUP BY 1) o), '{}'::jsonb),
           'population', CASE WHEN (SELECT use_fine FROM pop) THEN 'fine_ticks' ELSE 'all_ticks' END,
           'other_share_all_ticks', round((SELECT avg((return_trigger IS DISTINCT FROM 'low_soc_reserve')::int) FROM a)::numeric, 4),
           'n_returns_all_ticks', (SELECT count(*) FROM a),
           -- 0619's fit wrote these from its own counts; kept so a reader of either sees the same row
           'n_runs', (SELECT count(DISTINCT sim_run_id) FROM d))
    INTO v_p;

  -- the dwell: from a completed charge's end to the car's next departure in its run. 0624: and in the same pass the same
  -- curve by what each car had left to do when its charge ended (cls). A car leaves within about a minute of its last
  -- bay service on every run of the evidence, and at once when nothing holds it; one curve over both ran 7 minutes at
  -- its median for cars that leave in half a minute (db/checks/0418). The pooled curve reads t and ev only, as 0623's
  -- did, so it is the same curve from the same rows.
  WITH r AS (
    SELECT x.sim_run_id, COALESCE(x.sim_clock_current, x.sim_clock_start) AS run_end,
           COALESCE(x.tick_count > 0 AND x.sim_clock_current IS NOT NULL AND x.sim_clock_start IS NOT NULL
                    AND extract(epoch FROM (x.sim_clock_current - x.sim_clock_start)) / 60.0 / x.tick_count <= 1,
                    false) AS fine
      FROM public.ottoq_sim_runs x WHERE x.depot_id = p_depot
  ), s AS MATERIALIZED (
    SELECT r.fine, os.ended_at, r.run_end,
           (SELECT min(dd.dispatched_at) FROM public.ottoq_vehicle_dispatches dd
             WHERE dd.sim_run_id = os.sim_run_id AND dd.vehicle_id = os.vehicle_id AND dd.dispatched_at >= os.ended_at) AS next_out,
           (SELECT min(o2.started_at) FROM public.ocpp_sessions o2
             WHERE o2.sim_run_id = os.sim_run_id AND o2.vehicle_id = os.vehicle_id AND o2.started_at > os.ended_at) AS next_charge,
           -- 0624: the car's class when its charge ended, on its visit as of the charge's start
           public.ottoq_dwell_class((SELECT COALESCE(vn.atoms, '[]'::jsonb) FROM public.ottoq_visit_needs vn
                                      WHERE vn.sim_run_id = os.sim_run_id AND vn.vehicle_id = os.vehicle_id
                                        AND vn.arrived_at <= os.started_at
                                      ORDER BY vn.arrived_at DESC, vn.created_at DESC LIMIT 1), os.ended_at) AS cls
      FROM public.ocpp_sessions os
      JOIN r ON r.sim_run_id = os.sim_run_id
     WHERE os.stopped_reason = 'completed' AND os.ended_at IS NOT NULL AND os.vehicle_id IS NOT NULL
       AND os.created_at > v_from AND os.created_at <= v_through
  ), pop AS (
    SELECT (count(*) FILTER (WHERE s.fine AND s.next_out IS NOT NULL
                               AND (s.next_charge IS NULL OR s.next_out <= s.next_charge)) >= c_min_n) AS use_fine
      FROM s
  ), o AS (
    -- a departure before the car charged again is an event; a car that charged again first, or was still parked at
    -- its run's last minute, is censored there
    SELECT GREATEST(extract(epoch FROM (CASE WHEN s.next_out IS NOT NULL AND (s.next_charge IS NULL OR s.next_out <= s.next_charge)
                                             THEN s.next_out ELSE LEAST(COALESCE(s.next_charge, s.run_end), s.run_end) END
                                        - s.ended_at)) / 60.0, 0)::float8 AS t,
           (s.next_out IS NOT NULL AND (s.next_charge IS NULL OR s.next_out <= s.next_charge)) AS ev,
           s.cls
      FROM s, pop WHERE s.fine OR NOT pop.use_fine
  ), g AS (
    SELECT o.t, count(*) FILTER (WHERE o.ev) AS d, count(*) AS m FROM o GROUP BY o.t
  ), rk AS (
    SELECT g.t, g.d, sum(g.m) OVER (ORDER BY g.t DESC) AS at_risk FROM g
  ), km AS (
    SELECT rk.t, rk.d, 1 - exp(sum(ln(GREATEST(1 - rk.d::float8 / rk.at_risk, 1e-12))) OVER (ORDER BY rk.t)) AS f FROM rk
  ), lim AS (
    SELECT max(km.f) AS fmax, max(km.t) FILTER (WHERE km.d > 0) AS tmax FROM km
  ), k AS (
    -- 0624: each charge under its class, and a visit car's under 'new' too
    SELECT o.t, o.ev, kk.key
      FROM o CROSS JOIN LATERAL (SELECT o.cls UNION ALL SELECT 'new'::text WHERE o.cls IN ('clear', 'bay')) kk(key)
  ), gk AS (
    SELECT k.key, k.t, count(*) FILTER (WHERE k.ev) AS d, count(*) AS m FROM k GROUP BY k.key, k.t
  ), rkk AS (
    SELECT gk.key, gk.t, gk.d, sum(gk.m) OVER (PARTITION BY gk.key ORDER BY gk.t DESC) AS at_risk FROM gk
  ), kmk AS (
    SELECT rkk.key, rkk.t, rkk.d,
           1 - exp(sum(ln(GREATEST(1 - rkk.d::float8 / rkk.at_risk, 1e-12))) OVER (PARTITION BY rkk.key ORDER BY rkk.t)) AS f
      FROM rkk
  ), limk AS (
    SELECT kmk.key, max(kmk.f) AS fmax, max(kmk.t) FILTER (WHERE kmk.d > 0) AS tmax FROM kmk GROUP BY kmk.key
  )
  SELECT jsonb_build_object(
           'q', (SELECT jsonb_agg(CASE WHEN u.u <= lim.fmax
                                       THEN round((SELECT min(km.t) FROM km WHERE km.f >= u.u - 1e-9)::numeric, 2) END
                                  ORDER BY u.u)
                   FROM generate_series(0, 19) gs(i) CROSS JOIN LATERAL (SELECT gs.i / 20.0 AS u) u),
           'f_max', round(lim.fmax::numeric, 4),
           'max_min', round(lim.tmax::numeric, 2),
           'median_min', round((SELECT min(km.t) FROM km WHERE km.f >= 0.5)::numeric, 2),
           'n', (SELECT count(*) FROM o),
           'left', (SELECT count(*) FROM o WHERE o.ev),
           'censored', (SELECT count(*) FROM o WHERE NOT o.ev),
           'population', CASE WHEN (SELECT use_fine FROM pop) THEN 'fine_ticks' ELSE 'all_ticks' END),
         -- 0624
         (SELECT COALESCE(jsonb_object_agg(limk.key, jsonb_build_object(
                   'q', (SELECT jsonb_agg(CASE WHEN u.u <= limk.fmax
                                               THEN round((SELECT min(kmk.t) FROM kmk
                                                            WHERE kmk.key = limk.key AND kmk.f >= u.u - 1e-9)::numeric, 2) END
                                          ORDER BY u.u)
                           FROM generate_series(0, 19) gs(i) CROSS JOIN LATERAL (SELECT gs.i / 20.0 AS u) u),
                   'f_max', round(limk.fmax::numeric, 4),
                   'max_min', round(limk.tmax::numeric, 2),
                   'median_min', round((SELECT min(kmk.t) FROM kmk WHERE kmk.key = limk.key AND kmk.f >= 0.5)::numeric, 2),
                   'n', (SELECT count(*) FROM k WHERE k.key = limk.key),
                   'left', (SELECT count(*) FROM k WHERE k.key = limk.key AND k.ev),
                   'censored', (SELECT count(*) FROM k WHERE k.key = limk.key AND NOT k.ev),
                   'population', CASE WHEN (SELECT use_fine FROM pop) THEN 'fine_ticks' ELSE 'all_ticks' END)), '{}'::jsonb)
            FROM limk)
    INTO v_dw, v_dwb
    FROM lim;

  RETURN v_p || jsonb_build_object('dwell', v_dw, 'dwell_by', v_dwb);
END $fn$;

-- ══ (c) the state reads each car's work ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_charge_line_outflow(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz, p_state jsonb,
                                                 p_ct jsonb, p_rt jsonb, p_ev jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0623: p_state (ottoq_charge_line_state's shape) with the depot's outflow as of p_clock, or p_state unchanged when the
   return model (p_rt, return_v1) is not usable or has no dwell. Adds `outflow`: the learned cycle (reserve, drain,
   its spread, drive home, other calls home per minute), the dwell grid, the window (90), and `ret`, for every car it
   models, its target, its battery back at the reserve (reserve less the drive), and its minutes from there to its
   target on each kind on its own clock (p_ct, with the run's evidence p_ev), with the kinds it can plug into; and
   `leaving`, the cars charged this visit and still parked (how long since their charge ended, their battery). Each
   busy charger carries `car`, the car charging on it. Read from the session and dispatch ledgers as of p_clock, so a
   stored order's state reads as the live one did. Read-only.
   0624: with the fit's `dwell_by` and the run's agent_charge_order_dwell_class dial at 1 (its default), the outflow
   (v 2) also carries `dwell_by`, each class's curve that holds 30 departures (a class without them is left out and its
   cars take the pooled curve); each modelled car's class at the clock in `ret` (`dc`): 'new' when it is out at work
   (it left after its latest visit began, or has had none and has left, and is neither on a charger nor charged and
   parked: its next visit's work is not known), else its latest visit's (ottoq_dwell_class); and on each parked car
   that is clear, `o`, how many minutes after its charge's end its must-do work was done (its dwell clock starts then).
   Without them, 0623's state exactly. */
DECLARE
  v_thr numeric := (p_rt #>> '{params,threshold_soc}')::numeric;
  v_drain numeric := (p_rt #>> '{params,drain_pct_per_min}')::numeric;
  v_trip numeric := COALESCE((p_rt #>> '{params,trip_min}')::numeric, 0);
  v_dw jsonb := p_rt #> '{params,dwell}';
  v_kw_d numeric; v_kw_l numeric;
  v_ids text[]; v_ch jsonb; v_leave jsonb; v_ret jsonb;
  v_dwb jsonb := p_rt #> '{params,dwell_by}'; v_by jsonb; v_cl jsonb; v_here text[];             -- 0624
BEGIN
  IF NOT COALESCE((p_rt ->> 'usable')::boolean, false) OR v_thr IS NULL OR COALESCE(v_drain, 0) <= 0
     OR v_dw IS NULL OR jsonb_typeof(v_dw -> 'q') IS DISTINCT FROM 'array' OR COALESCE((v_dw ->> 'f_max')::numeric, 0) <= 0
     OR COALESCE((v_dw ->> 'left')::int, 0) < 30 OR p_state IS NULL THEN
    RETURN p_state;
  END IF;
  SELECT max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'dcfc'),
         max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'l2')
    INTO v_kw_d, v_kw_l
    FROM stalls s WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc', 'l2');

  -- each busy charger's car: the session on it at the clock
  SELECT COALESCE(jsonb_agg(CASE WHEN c.free > 0 AND ses.vid IS NOT NULL THEN c.e || jsonb_build_object('car', ses.vid)
                                 ELSE c.e END ORDER BY c.o), '[]'::jsonb)
    INTO v_ch
    FROM (SELECT x.value AS e, x.o, COALESCE((x.value ->> 'free')::numeric, 0) AS free, x.value ->> 'id' AS id
            FROM jsonb_array_elements(COALESCE(p_state -> 'chargers', '[]'::jsonb)) WITH ORDINALITY x(value, o)) c
    LEFT JOIN LATERAL (SELECT os.vehicle_id::text AS vid FROM ocpp_sessions os
                        WHERE c.free > 0 AND c.id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                          AND os.sim_run_id = p_sim_run_id AND os.stall_id = c.id::uuid AND os.vehicle_id IS NOT NULL
                          AND os.started_at <= p_clock AND (os.ended_at IS NULL OR os.ended_at > p_clock)
                        ORDER BY os.started_at DESC LIMIT 1) ses ON true;

  SELECT COALESCE(array_agg(DISTINCT z.id), '{}'::text[]) INTO v_ids
    FROM (SELECT x.value ->> 'id' AS id FROM jsonb_array_elements(COALESCE(p_state -> 'cars', '[]'::jsonb)) x
          UNION ALL SELECT x.value ->> 'id' FROM jsonb_array_elements(COALESCE(p_state -> 'inbound', '[]'::jsonb)) x
          UNION ALL SELECT x.value ->> 'car' FROM jsonb_array_elements(v_ch) x WHERE x.value ? 'car') z
   WHERE z.id IS NOT NULL;

  -- the cars charged this visit and still parked: a completed charge since they were last home, no departure since,
  -- not charging, and at their target
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p.id, 'e', round(p.e, 2), 'sdep', p.soc) ORDER BY p.id), '[]'::jsonb)
    INTO v_leave
    FROM (SELECT v.id::text AS id, extract(epoch FROM (p_clock - ls.ended_at)) / 60.0 AS e, ls.soc_end AS soc
            FROM vehicles v
            CROSS JOIN LATERAL (SELECT os.ended_at, os.soc_end FROM ocpp_sessions os
                                 WHERE os.sim_run_id = p_sim_run_id AND os.vehicle_id = v.id
                                   AND os.stopped_reason = 'completed' AND os.ended_at <= p_clock
                                 ORDER BY os.ended_at DESC LIMIT 1) ls
           WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous' AND v.id::text <> ALL (v_ids)
             AND ls.soc_end >= public.ottoq_effective_target_soc_at(v.id, p_clock) - 1
             AND NOT EXISTS (SELECT 1 FROM ocpp_sessions o2
                              WHERE o2.sim_run_id = p_sim_run_id AND o2.vehicle_id = v.id
                                AND o2.started_at <= p_clock AND (o2.ended_at IS NULL OR o2.ended_at > p_clock))
             AND NOT EXISTS (SELECT 1 FROM ottoq_vehicle_dispatches d
                              WHERE d.sim_run_id = p_sim_run_id AND d.vehicle_id = v.id
                                AND d.dispatched_at > ls.ended_at AND d.dispatched_at <= p_clock)) p;

  -- every modelled car's charge back from the reserve, on its own clock
  SELECT COALESCE(jsonb_object_agg(v.id::text, jsonb_build_object(
           'tg', tg.t, 'rs', round(rs.s, 2),
           'rmd', round((ck.cd ->> 'm')::numeric, 2), 'rml', round((ck.cl ->> 'm')::numeric, 2),
           'rsd', (ck.cd ->> 'sd')::numeric, 'rsl', (ck.cl ->> 'sd')::numeric,
           'dok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'dcfc'),
           'lok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2'))), '{}'::jsonb)
    INTO v_ret
    FROM vehicles v
    CROSS JOIN LATERAL (SELECT public.ottoq_effective_target_soc_at(v.id, p_clock) AS t) tg
    CROSS JOIN LATERAL (SELECT GREATEST(LEAST(v_thr, tg.t) - v_drain * v_trip, 0) AS s) rs
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who) wh
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(p_ct, 'dcfc', wh.who, v.battery_capacity_kwh, rs.s, tg.t, v_kw_d,
                                                         v.inlet_max_kw, p_ev -> 'dcfc') AS cd,
                               public.ottoq_charge_clock(p_ct, 'l2', wh.who, v.battery_capacity_kwh, rs.s, tg.t, v_kw_l,
                                                         v.inlet_max_kw, p_ev -> 'l2') AS cl) ck
   WHERE v.id::text = ANY (v_ids || ARRAY(SELECT x.value ->> 'id' FROM jsonb_array_elements(v_leave) x))
     AND v.battery_capacity_kwh IS NOT NULL AND (ck.cd ->> 'm') IS NOT NULL AND (ck.cl ->> 'm') IS NOT NULL;

  -- 0624: the dwell by what each car has left to do (above), unless a person has turned it off for this run
  IF jsonb_typeof(v_dwb) = 'object'
     AND COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_dwell_class', 1), 1) >= 1 THEN
    SELECT jsonb_object_agg(c.key, jsonb_build_object('q', c.value -> 'q', 'f_max', c.value -> 'f_max',
                                                      'max_min', c.value -> 'max_min', 'median_min', c.value -> 'median_min',
                                                      'left', c.value -> 'left'))
      INTO v_by
      FROM jsonb_each(v_dwb) c
     WHERE c.key IN ('clear', 'bay', 'boot', 'new') AND jsonb_typeof(c.value -> 'q') = 'array'
       AND COALESCE((c.value ->> 'f_max')::numeric, 0) > 0 AND COALESCE((c.value ->> 'left')::int, 0) >= 30;
  END IF;
  IF v_by IS NOT NULL THEN
    -- the cars here by construction: on a charger, or charged and parked
    v_here := ARRAY(SELECT x.value ->> 'car' FROM jsonb_array_elements(v_ch) x WHERE x.value ? 'car')
              || ARRAY(SELECT x.value ->> 'id' FROM jsonb_array_elements(v_leave) x);
    SELECT COALESCE(jsonb_object_agg(x.id, jsonb_build_object('dc', x.dc, 'rm', x.rm)), '{}'::jsonb)
      INTO v_cl
      FROM (SELECT k.id,
                   CASE WHEN lo.at IS NOT NULL AND (vn.arrived_at IS NULL OR vn.arrived_at < lo.at) AND NOT (k.id = ANY (v_here))
                        THEN 'new'
                        ELSE public.ottoq_dwell_class(vn.atoms, p_clock) END AS dc,
                   -- how many minutes before the clock its must-do work was last done
                   (SELECT extract(epoch FROM (p_clock - max(COALESCE((a ->> 'done_at')::timestamptz,
                                                                      (a ->> 'closed_at')::timestamptz)))) / 60.0
                      FROM jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) a
                     WHERE COALESCE((a ->> 'must_do')::boolean, false)
                       AND COALESCE((a ->> 'done_at')::timestamptz, (a ->> 'closed_at')::timestamptz) <= p_clock) AS rm
              FROM jsonb_object_keys(v_ret) k(id)
              LEFT JOIN LATERAL (SELECT max(d.dispatched_at) AS at FROM ottoq_vehicle_dispatches d
                                  WHERE d.sim_run_id = p_sim_run_id AND d.vehicle_id = k.id::uuid
                                    AND d.dispatched_at <= p_clock) lo ON true
              LEFT JOIN LATERAL (SELECT COALESCE(v.atoms, '[]'::jsonb) AS atoms, v.arrived_at FROM ottoq_visit_needs v
                                  WHERE v.sim_run_id = p_sim_run_id AND v.vehicle_id = k.id::uuid AND v.arrived_at <= p_clock
                                  ORDER BY v.arrived_at DESC, v.created_at DESC LIMIT 1) vn ON true) x;
    SELECT COALESCE(jsonb_object_agg(r.key, r.value || jsonb_build_object('dc', v_cl #>> ARRAY[r.key, 'dc'])), '{}'::jsonb)
      INTO v_ret FROM jsonb_each(v_ret) r;
    SELECT COALESCE(jsonb_agg(CASE WHEN v_cl #>> ARRAY[l.value ->> 'id', 'dc'] = 'clear'
                                        AND (v_cl #>> ARRAY[l.value ->> 'id', 'rm'])::numeric < (l.value ->> 'e')::numeric
                                   THEN l.value || jsonb_build_object('o', round((l.value ->> 'e')::numeric
                                                                                 - (v_cl #>> ARRAY[l.value ->> 'id', 'rm'])::numeric, 2))
                                   ELSE l.value END ORDER BY l.o), '[]'::jsonb)
      INTO v_leave FROM jsonb_array_elements(v_leave) WITH ORDINALITY l(value, o);
  END IF;

  RETURN p_state || jsonb_build_object(
    'chargers', v_ch,
    'outflow', jsonb_build_object(
      'v', CASE WHEN v_by IS NULL THEN 1 ELSE 2 END, 'return_model', p_rt -> 'estimate_id', 'window_min', 90,
      'thr', v_thr, 'drain', v_drain, 'dsd', COALESCE((p_rt #>> '{params,drain_log_sd}')::numeric, 0), 'trip', v_trip,
      'lam', round(COALESCE((p_rt #>> '{params,other_per_work_hour}')::numeric, 0) / 60.0, 6),
      'dwell', jsonb_build_object('q', v_dw -> 'q', 'f_max', v_dw -> 'f_max', 'max_min', v_dw -> 'max_min',
                                  'median_min', v_dw -> 'median_min'),
      'ret', v_ret, 'leaving', v_leave)
      || CASE WHEN v_by IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('dwell_by', v_by) END);
END $fn$;

-- ══ (d) the draw: a car's dwell clock can start after its charge ═══════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_charge_line_return_draw(p_out double precision[], p_q double precision[],
                                                     p_car double precision[], p_ready double precision,
                                                     p_e double precision, p_sdep double precision, p_scenario integer,
                                                     p_seed text, p_id text, p_ud double precision, p_uo double precision,
                                                     p_zd double precision, p_real jsonb, p_cut double precision)
RETURNS double precision[]
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
/* 0623: one car's departure and return, as [departure, arrival, battery at arrival, minutes back to its target on a fast
   charger, on an L2], in minutes from the state's clock; NULL when the car stays past every departure the evidence saw.
   p_out: [reserve, drain % per minute, drain log spread, drive home, other calls home per work minute, the dwell curve's
   f_max, its last departure]; p_q: the dwell grid; p_car: [target, battery back at the reserve, minutes from it on a fast
   charger and on an L2, their log spreads]. p_ready: when its charge here ends (or now, for a parked car); p_e: how long
   it has been parked already (its charge ended at p_ready - p_e); p_sdep: its battery when it leaves.
   The dwell (from the charge's end) is drawn from the curve past p_e at probability p_ud, and the work is the drain to the
   reserve (its rate the learned one times exp(spread * p_zd)) or another call home first, drawn at p_uo; NULL draws are
   the car's own hashed ones (a sampled future; the expected future passes stratified ones, so that across cars the draws
   cover each curve evenly).
   p_real (the grader's, for this car): ce, when its charge really ended; left, when it really left; eta and soc, when it
   came back and with what. What happened is kept as durations, so each side of a comparison keeps its own timing: a car
   that left did so its real dwell after its charge here ended, and one that came back did so its real time out after it
   left; a car not gone by the cut p_cut stayed at least as long as it had (the dwell is drawn past that), and one gone
   but not back was out at least that long. Pure.
   0624: p_car[7], when given, is how many minutes after its charge's end the car's dwell clock starts (a parked car
   whose work was done after its charge leaves on its class's curve from then): the dwell is drawn on that clock, past
   how long it has run, and returned as minutes after the charge's end. Without it, 0623's draw exactly. */
DECLARE
  v_sc   boolean := COALESCE(p_scenario, 0) > 0;
  v_key  text := COALESCE(p_seed, '') || ':' || COALESCE(p_scenario, 0) || ':' || COALESCE(p_id, '');
  v_thr  float8 := p_out[1]; v_drain float8 := p_out[2]; v_dsd float8 := COALESCE(p_out[3], 0);
  v_trip float8 := COALESCE(p_out[4], 0); v_lam float8 := COALESCE(p_out[5], 0);
  v_fmax float8 := p_out[6]; v_max float8 := p_out[7];
  v_tg   float8 := COALESCE(p_car[1], 100); v_rs float8 := p_car[2]; v_rmd float8 := p_car[3]; v_rml float8 := p_car[4];
  v_rsd  float8 := COALESCE(p_car[5], 0); v_rsl float8 := COALESCE(p_car[6], 0);
  v_sdep float8 := COALESCE(p_sdep, p_car[1], 100);
  v_e    float8 := GREATEST(COALESCE(p_e, 0), 0);
  v_ce   float8 := CASE WHEN jsonb_typeof(p_real -> 'ce') = 'number' THEN (p_real ->> 'ce')::float8 END;
  v_left float8 := CASE WHEN jsonb_typeof(p_real -> 'left') = 'number' THEN (p_real ->> 'left')::float8 END;
  v_reta float8 := CASE WHEN jsonb_typeof(p_real -> 'eta') = 'number' THEN (p_real ->> 'eta')::float8 END;
  v_o    float8 := GREATEST(COALESCE(p_car[7], 0), 0);                                          -- 0624
  v_u float8; v_past float8; v_fe float8; v_dw float8; v_dep float8; v_eta float8; v_dr float8; v_work float8;
  v_out float8; v_soc float8; v_frac float8; v_z float8;
BEGIN
  IF v_drain IS NULL OR v_drain <= 0 OR v_thr IS NULL OR v_rs IS NULL OR v_rmd IS NULL OR v_rml IS NULL
     OR p_ready IS NULL THEN
    RETURN NULL;
  END IF;
  v_dr := v_drain * exp(v_dsd * COALESCE(p_zd, CASE WHEN v_sc THEN public.ottoq_hash_normal(v_key || ':drain') ELSE 0 END));

  -- the dwell, from the end of its charge here
  IF v_left IS NOT NULL AND v_ce IS NOT NULL THEN
    v_dw := GREATEST(v_left - v_ce, v_e);                     -- what it really waited
  ELSE
    v_past := CASE WHEN v_o > 0 THEN GREATEST(v_e - v_o, 0) ELSE v_e END;    -- 0624: how long its dwell clock has run
    IF v_ce IS NOT NULL AND p_cut IS NOT NULL THEN
      -- not gone by the cut: at least that long
      v_past := GREATEST(v_past, CASE WHEN v_o > 0 THEN p_cut - v_ce - v_o ELSE p_cut - v_ce END);
    END IF;
    v_u := COALESCE(p_ud, public.ottoq_hash_uniform(v_key || ':dwell'));
    v_fe := public.ottoq_outflow_dwell_cdf(p_q, v_fmax, v_max, v_past);
    v_dw := public.ottoq_outflow_dwell_quantile(p_q, v_fmax, v_max, v_fe + v_u * (1 - v_fe));
    IF v_dw IS NULL THEN RETURN NULL; END IF;                 -- parked past every departure the evidence saw
    v_dw := GREATEST(v_dw, v_past);
    IF v_o > 0 THEN v_dw := v_dw + v_o; END IF;               -- 0624: back to minutes after the charge's end
  END IF;
  v_dep := p_ready - v_e + v_dw;

  -- the time out: the work to the reserve or another call home first, and the drive home
  v_work := GREATEST(v_sdep - v_thr, 0) / v_dr;
  IF v_lam > 0 THEN
    v_u := COALESCE(p_uo, public.ottoq_hash_uniform(v_key || ':other'));
    v_work := LEAST(v_work, -ln(1 - LEAST(v_u, 0.999999)) / v_lam);
  END IF;
  v_out := v_work + v_trip;
  IF v_reta IS NOT NULL AND v_left IS NOT NULL THEN
    v_out := GREATEST(v_reta - v_left, 0);                    -- what it really was out
  ELSIF v_left IS NOT NULL AND p_cut IS NOT NULL THEN
    v_out := GREATEST(v_out, p_cut - v_left);                 -- gone, not back by the cut: at least that long
  END IF;
  v_eta := v_dep + v_out;
  v_soc := CASE WHEN v_reta IS NOT NULL AND jsonb_typeof(p_real -> 'soc') = 'number' THEN (p_real ->> 'soc')::float8
                ELSE GREATEST(v_sdep - v_dr * v_out, v_thr - v_dr * v_trip, 0) END;

  -- its charge back to its target: the clock's minutes from the reserve, in proportion to what it owes now
  v_frac := CASE WHEN v_tg - v_rs > 0.5 THEN GREATEST(v_tg - v_soc, 0) / (v_tg - v_rs) ELSE 0 END;
  v_z := CASE WHEN v_sc THEN public.ottoq_hash_normal(v_key || ':charge1') ELSE 0 END;
  RETURN ARRAY[v_dep, v_eta, v_soc, v_rmd * v_frac * exp(v_rsd * v_z), v_rml * v_frac * exp(v_rsl * v_z)];
END $fn$;

-- ══ (e) the simulator: each car on its class's curve ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_charge_line_schedule(p_state jsonb, p_order jsonb, p_scenario integer, p_seed text,
                                                             p_trace boolean)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
/* 0621: 0620's ottoq_charge_line_simulate (which is now this with p_trace false), unchanged where it was, plus two things
   that act only when asked. p_trace adds 'seats': for each car its first seat (s0 minutes, k0 kind), its last kind and
   ready time (k, r), its arrival (a), whether it came home in the window (inb) and how many times a fault stopped its
   charge (x). And a charger carrying 'dn', a list of [from, until] minutes, goes down at from and is back at until: a
   car charging on it at from stops there and rejoins the line owing the rest of its charge, on whichever charger it
   takes next (rule 9: a car whose charger faulted is re-queued to finish; the twin's auto_rerouted). No state 0620 builds
   carries 'dn', and with p_trace false the result is 0620's, key for key. Pure: no table is read.
   0623: with an outflow block (ottoq_charge_line_outflow), cars also leave and come back. A car seated for its visit
   now leaves after its dwell once its charge ends and comes back owing its charge (ottoq_charge_line_return_draw); each
   busy charger's car and each parked car leave the same way from the start. A return joins the line as a car coming home
   does, and is the car's last visit: every car is compared over the same two, now and next. A fault that stops a charge
   undoes the car's departure until it is charged. Totals added: returns (inside the horizon and past it), stays,
   flow2_sum (minutes waiting and charging over the two visits; a return past the horizon owes only its charge) and
   out_min (minutes out at work inside the window); with p_trace, 'return_seats'. Without an outflow block, 0621's result,
   key for key.
   0624: with `dwell_by` in the outflow block, each car's dwell is drawn on its class's curve (its `dc` in `ret`; a class
   absent from dwell_by takes the pooled curve) from its class's clock (a parked clear car's `o`), and the expected future
   spreads the dwells evenly within each class, so each class's cars cover their own curve; with p_trace each return
   carries its class (dc). Without dwell_by, 0623's result, key for key. */
DECLARE
  v_ttl float8 := COALESCE((p_state ->> 'ttl_min')::float8, 0);
  v_pin float8 := COALESCE((p_state ->> 'pin_min')::float8, 90);
  v_hor float8 := COALESCE((p_state ->> 'horizon_min')::float8, 480);
  v_on  boolean := (p_order IS NOT NULL AND jsonb_typeof(p_order) = 'object' AND p_order <> '{}'::jsonb);
  c_id text[] := '{}'; c_idr int[] := '{}'; c_w0 float8[] := '{}'; c_g float8[] := '{}'; c_imm boolean[] := '{}';
  c_soc float8[] := '{}'; c_due float8[] := '{}'; c_dok boolean[] := '{}'; c_lok boolean[] := '{}';
  c_md float8[] := '{}'; c_ml float8[] := '{}'; c_av float8[] := '{}'; c_inb boolean[] := '{}';
  c_rank int[] := '{}'; c_okind text[] := '{}';
  c_ready float8[]; c_start float8[]; c_kind text[];
  c_gate float8[] := '{}'; c_s0 float8[]; c_k0 text[]; c_x int[];                                   -- 0621
  s_id text[] := '{}'; s_k text[] := '{}'; s_free float8[] := '{}'; s_car int[] := '{}';            -- 0621: s_car
  d_j int[] := '{}'; d_a float8[] := '{}'; d_b float8[] := '{}'; d_done boolean[] := '{}'; nd int := 0;   -- 0621
  n int := 0; m int := 0; i int; j int; best int; t float8 := 0; t_c float8; t_a float8; t_next float8;
  v_seated int := 0; v_any boolean; v_live boolean; v_mode text; v_dur float8; v_want text; z float8; v_free_n int;
  e jsonb; v_inbound boolean; v_rk text; v_order int[]; v_first text[] := '{}';
  v_out jsonb; v_dn float8; w jsonb; v_frac float8; q int;                                          -- 0621
  -- 0623: the outflow
  o_on boolean := COALESCE(jsonb_typeof(p_state -> 'outflow') = 'object', false);
  o_ret jsonb; o_real jsonb; o_cut float8; o_win float8; o_p float8[]; o_q float8[]; o_idr jsonb; o_u jsonb;
  c_vk int[] := '{}'; c_void boolean[] := '{}'; c_ret int[] := '{}'; c_dep float8[] := '{}';
  n0 int; n_live int; v_stays int := 0;
  p_car text[] := '{}'; p_ready float8[] := '{}'; p_e float8[] := '{}'; p_sdep float8[] := '{}'; p_par int[] := '{}';
  np int := 0; pi int := 0; v_r jsonb; v_rr float8[]; v_k int;
  -- 0624: the dwell by class
  o_cls boolean := false; o_qc float8[]; o_qb float8[]; o_qo float8[]; o_qn float8[];
  o_pc float8[]; o_pb float8[]; o_po float8[]; o_pn float8[]; v_qq float8[]; v_pp float8[]; v_dc text;
  p_o float8[] := '{}'; c_dc text[] := '{}';
BEGIN
  FOR v_inbound IN SELECT unnest(ARRAY[false, true]) LOOP
    FOR e IN SELECT x.value FROM jsonb_array_elements(COALESCE(p_state -> CASE WHEN v_inbound THEN 'inbound' ELSE 'cars' END,
                                                               '[]'::jsonb)) WITH ORDINALITY x(value, o) ORDER BY x.o
    LOOP
      CONTINUE WHEN (e ->> 'md') IS NULL OR (e ->> 'ml') IS NULL OR (e ->> 'id') IS NULL;
      n := n + 1;
      c_id[n] := e ->> 'id';
      c_w0[n] := COALESCE((e ->> 'w')::float8, 0);
      c_g[n] := GREATEST(COALESCE((e ->> 'g')::float8, 1), 1);
      c_imm[n] := COALESCE((e ->> 'imm')::boolean, false);
      c_soc[n] := COALESCE((e ->> 'soc')::float8, 0);
      c_due[n] := (e ->> 'due')::float8;
      c_dok[n] := COALESCE((e ->> 'dok')::boolean, true);
      c_lok[n] := COALESCE((e ->> 'lok')::boolean, true);
      c_md[n] := (e ->> 'md')::float8;
      c_ml[n] := (e ->> 'ml')::float8;
      c_inb[n] := v_inbound;
      c_av[n] := CASE WHEN v_inbound THEN GREATEST(COALESCE((e ->> 'eta')::float8, 0), 0) ELSE 0 END;
      IF COALESCE(p_scenario, 0) > 0 THEN
        z := public.ottoq_hash_normal(COALESCE(p_seed, '') || ':' || p_scenario || ':' || c_id[n] || ':charge');
        c_md[n] := c_md[n] * exp(COALESCE((e ->> 'sd')::float8, 0) * z);
        c_ml[n] := c_ml[n] * exp(COALESCE((e ->> 'sl')::float8, 0) * z);
        IF v_inbound AND e ->> 'src' = 'forecast' THEN
          z := public.ottoq_hash_normal(COALESCE(p_seed, '') || ':' || p_scenario || ':' || c_id[n] || ':arrival');
          c_av[n] := COALESCE((e ->> 'trip')::float8, 0)
                     + GREATEST(c_av[n] - COALESCE((e ->> 'trip')::float8, 0), 0) * exp(COALESCE((e ->> 'esd')::float8, 0) * z);
        END IF;
      END IF;
      c_gate[n] := c_av[n];   -- 0621: when the car may take a charger: its arrival, or when a fault put it back in line
      v_rk := CASE WHEN v_on AND p_order ? c_id[n] THEN p_order -> c_id[n] ->> 'rank' END;
      c_rank[n] := CASE WHEN v_rk IS NULL THEN NULL WHEN v_rk ~ '^[0-9]{1,6}$' THEN v_rk::int ELSE 999 END;
      c_okind[n] := CASE WHEN v_on AND p_order ? c_id[n] THEN p_order -> c_id[n] ->> 'kind' END;
      c_vk[n] := 0; c_void[n] := false; c_ret[n] := NULL; c_dep[n] := NULL;                      -- 0623
    END LOOP;
  END LOOP;
  n0 := n;
  n_live := n;

  -- the id's rank, the cursor's last key, computed once (comparing a uuid's text is comparing the uuid). 0623: with an
  -- outflow, over every car it models (a return keeps its car's rank); the order of the cars in the line is the same.
  IF o_on THEN
    o_ret := COALESCE(p_state #> '{outflow,ret}', '{}'::jsonb);
    o_real := p_state #> '{outflow,real}';
    o_cut := (p_state #>> '{outflow,cut}')::float8;
    o_win := COALESCE((p_state #>> '{outflow,window_min}')::float8, 90);
    o_p := ARRAY[(p_state #>> '{outflow,thr}')::float8, (p_state #>> '{outflow,drain}')::float8,
                 (p_state #>> '{outflow,dsd}')::float8, (p_state #>> '{outflow,trip}')::float8,
                 (p_state #>> '{outflow,lam}')::float8, (p_state #>> '{outflow,dwell,f_max}')::float8,
                 (p_state #>> '{outflow,dwell,max_min}')::float8];
    SELECT array_agg(CASE WHEN jsonb_typeof(x.value) = 'number' THEN (x.value #>> '{}')::float8 END ORDER BY x.o)
      INTO o_q FROM jsonb_array_elements(COALESCE(p_state #> '{outflow,dwell,q}', '[]'::jsonb)) WITH ORDINALITY x(value, o);
    -- 0624: each class's curve, as o_q and o_p are the pooled one's (a class dwell_by lacks takes the pooled curve)
    o_cls := COALESCE(jsonb_typeof(p_state #> '{outflow,dwell_by}') = 'object', false);
    IF o_cls THEN
      SELECT array_agg(CASE WHEN jsonb_typeof(x.value) = 'number' THEN (x.value #>> '{}')::float8 END ORDER BY x.o)
        INTO o_qc FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_state #> '{outflow,dwell_by,clear,q}') = 'array'
                                                 THEN p_state #> '{outflow,dwell_by,clear,q}' ELSE '[]'::jsonb END)
                       WITH ORDINALITY x(value, o);
      SELECT array_agg(CASE WHEN jsonb_typeof(x.value) = 'number' THEN (x.value #>> '{}')::float8 END ORDER BY x.o)
        INTO o_qb FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_state #> '{outflow,dwell_by,bay,q}') = 'array'
                                                 THEN p_state #> '{outflow,dwell_by,bay,q}' ELSE '[]'::jsonb END)
                       WITH ORDINALITY x(value, o);
      SELECT array_agg(CASE WHEN jsonb_typeof(x.value) = 'number' THEN (x.value #>> '{}')::float8 END ORDER BY x.o)
        INTO o_qo FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_state #> '{outflow,dwell_by,boot,q}') = 'array'
                                                 THEN p_state #> '{outflow,dwell_by,boot,q}' ELSE '[]'::jsonb END)
                       WITH ORDINALITY x(value, o);
      SELECT array_agg(CASE WHEN jsonb_typeof(x.value) = 'number' THEN (x.value #>> '{}')::float8 END ORDER BY x.o)
        INTO o_qn FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_state #> '{outflow,dwell_by,new,q}') = 'array'
                                                 THEN p_state #> '{outflow,dwell_by,new,q}' ELSE '[]'::jsonb END)
                       WITH ORDINALITY x(value, o);
      o_pc := o_p; o_pc[6] := (p_state #>> '{outflow,dwell_by,clear,f_max}')::float8;
      o_pc[7] := (p_state #>> '{outflow,dwell_by,clear,max_min}')::float8;
      o_pb := o_p; o_pb[6] := (p_state #>> '{outflow,dwell_by,bay,f_max}')::float8;
      o_pb[7] := (p_state #>> '{outflow,dwell_by,bay,max_min}')::float8;
      o_po := o_p; o_po[6] := (p_state #>> '{outflow,dwell_by,boot,f_max}')::float8;
      o_po[7] := (p_state #>> '{outflow,dwell_by,boot,max_min}')::float8;
      o_pn := o_p; o_pn[6] := (p_state #>> '{outflow,dwell_by,new,f_max}')::float8;
      o_pn[7] := (p_state #>> '{outflow,dwell_by,new,max_min}')::float8;
    END IF;
    SELECT COALESCE(jsonb_object_agg(r.id, r.rk), '{}'::jsonb) INTO o_idr
      FROM (SELECT u.id, rank() OVER (ORDER BY u.id) AS rk
              FROM (SELECT DISTINCT y.id FROM (SELECT unnest(c_id) AS id
                                               UNION ALL SELECT jsonb_object_keys(o_ret)) y) u) r;
    FOR i IN 1 .. n LOOP c_idr[i] := (o_idr ->> c_id[i])::int; END LOOP;
    -- the expected future's draws, stratified across the cars it models: each car's dwell, call home and drain at its
    -- own probability, evenly spaced over (0, 1) in the order of a hash of the car (the same on both sides of a
    -- comparison), so that together they cover the curves as the cars' futures would; a sampled future draws each by
    -- its own hash. 0624: with dwell_by, the dwells are spread within each class, so each class's cars cover their own
    -- curve (without it every car is one class, and the spread is 0623's)
    IF COALESCE(p_scenario, 0) = 0 THEN
      SELECT COALESCE(jsonb_object_agg(u.id, jsonb_build_array(
               (u.rd - 0.5) / u.nd, (u.ro - 0.5) / u.n, public.ottoq_normal_quantile((u.rz - 0.5) / u.n))), '{}'::jsonb)
        INTO o_u
        FROM (SELECT k.id, count(*) OVER () AS n,
                     count(*) OVER (PARTITION BY CASE WHEN o_cls THEN o_ret -> k.id ->> 'dc' END) AS nd,
                     row_number() OVER (PARTITION BY CASE WHEN o_cls THEN o_ret -> k.id ->> 'dc' END
                                        ORDER BY md5(COALESCE(p_seed, '') || ':' || k.id || ':dwell'), k.id) AS rd,
                     row_number() OVER (ORDER BY md5(COALESCE(p_seed, '') || ':' || k.id || ':other'), k.id) AS ro,
                     row_number() OVER (ORDER BY md5(COALESCE(p_seed, '') || ':' || k.id || ':drain'), k.id) AS rz
                FROM jsonb_object_keys(o_ret) k(id)) u;
    END IF;
  ELSIF n > 0 THEN
    SELECT array_agg(r.rk ORDER BY r.i) INTO c_idr
      FROM (SELECT u.i, rank() OVER (ORDER BY u.id) AS rk FROM unnest(c_id) WITH ORDINALITY AS u(id, i)) r;
  END IF;

  FOR e IN SELECT x.value FROM jsonb_array_elements(COALESCE(p_state -> 'chargers', '[]'::jsonb)) WITH ORDINALITY x(value, o)
            ORDER BY x.o
  LOOP
    CONTINUE WHEN (e ->> 'free') IS NULL OR (e ->> 'k') NOT IN ('dcfc', 'l2');
    m := m + 1;
    s_id[m] := e ->> 'id';
    s_k[m] := e ->> 'k';
    s_free[m] := GREATEST((e ->> 'free')::float8, 0);
    s_car[m] := NULL;
    IF COALESCE(p_scenario, 0) > 0 AND s_free[m] > 0 THEN
      z := public.ottoq_hash_normal(COALESCE(p_seed, '') || ':' || p_scenario || ':' || s_id[m] || ':running');
      s_free[m] := s_free[m] * exp(COALESCE((e ->> 'sd')::float8, 0) * z);
    END IF;
    -- 0621: the windows this charger is down, as given (never drawn)
    IF jsonb_typeof(e -> 'dn') = 'array' THEN
      FOR w IN SELECT x.value FROM jsonb_array_elements(e -> 'dn') WITH ORDINALITY x(value, o) ORDER BY x.o LOOP
        CONTINUE WHEN jsonb_typeof(w) <> 'array' OR (w ->> 0) IS NULL;
        nd := nd + 1;
        d_j[nd] := m;
        d_a[nd] := GREATEST((w ->> 0)::float8, 0);
        d_b[nd] := GREATEST(COALESCE((w ->> 1)::float8, v_hor + 1), d_a[nd]);
        d_done[nd] := false;
      END LOOP;
    END IF;
    -- 0623: the car charging on it leaves when its charge ends
    IF o_on AND s_free[m] > 0 AND (e ->> 'car') IS NOT NULL AND o_ret ? (e ->> 'car') THEN
      np := np + 1; p_car[np] := e ->> 'car'; p_ready[np] := s_free[m]; p_e[np] := 0; p_sdep[np] := NULL; p_par[np] := NULL;
      p_o[np] := 0;                                                                              -- 0624
    END IF;
  END LOOP;

  -- 0623: the cars charged and still parked leave from now, on what is left of their dwell
  IF o_on THEN
    FOR e IN SELECT x.value FROM jsonb_array_elements(COALESCE(p_state #> '{outflow,leaving}', '[]'::jsonb)) WITH ORDINALITY x(value, o)
              ORDER BY x.o
    LOOP
      CONTINUE WHEN (e ->> 'id') IS NULL OR NOT (o_ret ? (e ->> 'id'));
      np := np + 1; p_car[np] := e ->> 'id'; p_ready[np] := 0; p_e[np] := COALESCE((e ->> 'e')::float8, 0);
      p_sdep[np] := (e ->> 'sdep')::float8; p_par[np] := NULL;
      p_o[np] := CASE WHEN o_cls THEN GREATEST(COALESCE((e ->> 'o')::float8, 0), 0) ELSE 0 END;   -- 0624: its clock
    END LOOP;
  END IF;

  c_ready := array_fill(NULL::float8, ARRAY[GREATEST(n, 1)]);
  c_start := array_fill(NULL::float8, ARRAY[GREATEST(n, 1)]);
  c_kind  := array_fill(NULL::text, ARRAY[GREATEST(n, 1)]);
  c_s0    := array_fill(NULL::float8, ARRAY[GREATEST(n, 1)]);
  c_k0    := array_fill(NULL::text, ARRAY[GREATEST(n, 1)]);
  c_x     := array_fill(0, ARRAY[GREATEST(n, 1)]);

  LOOP
    -- 0623: the departures since the last pass become returns, each the car's next visit
    WHILE pi < np LOOP
      pi := pi + 1;
      v_r := o_ret -> p_car[pi];
      -- 0624: its class's curve and clock (the pooled curve for a class dwell_by lacks)
      v_dc := CASE WHEN o_cls THEN v_r ->> 'dc' END;
      v_qq := CASE v_dc WHEN 'clear' THEN o_qc WHEN 'bay' THEN o_qb WHEN 'boot' THEN o_qo WHEN 'new' THEN o_qn END;
      v_pp := CASE v_dc WHEN 'clear' THEN o_pc WHEN 'bay' THEN o_pb WHEN 'boot' THEN o_po WHEN 'new' THEN o_pn END;
      IF v_qq IS NULL THEN v_qq := o_q; v_pp := o_p; END IF;
      v_rr := public.ottoq_charge_line_return_draw(
                v_pp, v_qq,
                ARRAY[(v_r ->> 'tg')::float8, (v_r ->> 'rs')::float8, (v_r ->> 'rmd')::float8, (v_r ->> 'rml')::float8,
                      (v_r ->> 'rsd')::float8, (v_r ->> 'rsl')::float8]
                  || CASE WHEN o_cls THEN ARRAY[p_o[pi]] ELSE '{}'::float8[] END,
                p_ready[pi], p_e[pi], p_sdep[pi], p_scenario, p_seed, p_car[pi],
                (o_u #>> ARRAY[p_car[pi], '0'])::float8, (o_u #>> ARRAY[p_car[pi], '1'])::float8,
                (o_u #>> ARRAY[p_car[pi], '2'])::float8,
                CASE WHEN o_real IS NULL THEN NULL ELSE COALESCE(o_real -> p_car[pi], '{}'::jsonb) END, o_cut);
      IF v_rr IS NULL THEN
        v_stays := v_stays + 1;
        CONTINUE;
      END IF;
      CONTINUE WHEN v_rr[4] <= 0.01 AND v_rr[5] <= 0.01;      -- back with nothing owed: no visit
      n := n + 1;
      c_id[n] := p_car[pi]; c_idr[n] := (o_idr ->> p_car[pi])::int;
      c_w0[n] := 0; c_imm[n] := false; c_due[n] := NULL; c_inb[n] := true;
      c_soc[n] := v_rr[3]; c_g[n] := GREATEST(COALESCE((v_r ->> 'tg')::float8, 100) - v_rr[3], 1);
      c_dok[n] := COALESCE((v_r ->> 'dok')::boolean, true); c_lok[n] := COALESCE((v_r ->> 'lok')::boolean, true);
      c_md[n] := v_rr[4]; c_ml[n] := v_rr[5]; c_av[n] := v_rr[2]; c_gate[n] := v_rr[2];
      c_rank[n] := NULL; c_okind[n] := NULL;
      c_ready[n] := NULL; c_start[n] := NULL; c_kind[n] := NULL; c_s0[n] := NULL; c_k0[n] := NULL; c_x[n] := 0;
      c_vk[n] := CASE WHEN v_rr[2] <= v_hor THEN 1 ELSE 2 END;
      c_void[n] := false; c_ret[n] := NULL; c_dep[n] := v_rr[1];
      c_dc[n] := v_dc;                                                                           -- 0624
      IF c_vk[n] = 1 THEN n_live := n_live + 1; END IF;
      IF p_par[pi] IS NOT NULL THEN c_ret[p_par[pi]] := n; END IF;
    END LOOP;
    -- 0621: the next charger to go down, if one is still to (with no 'dn' this is NULL and the loop is 0620's)
    v_dn := NULL;
    IF nd > 0 THEN
      SELECT min(u.a) INTO v_dn FROM unnest(d_a, d_done) AS u(a, done) WHERE NOT u.done;
    END IF;
    EXIT WHEN m = 0 OR (v_seated >= n_live AND v_dn IS NULL);
    -- the first moment a charger is free and a car is waiting
    SELECT min(f) INTO t_c FROM unnest(s_free) f;
    SELECT min(u.a) INTO t_a FROM unnest(c_gate, c_ready, c_vk, c_void) AS u(a, r, vk, vd)
     WHERE u.r IS NULL AND u.vk < 2 AND NOT u.vd;
    IF v_dn IS NOT NULL AND (t_c IS NULL OR t_a IS NULL OR v_dn <= GREATEST(t, t_c, t_a)) THEN
      -- 0621: a charger goes down before the next seat: the charge on it stops, its car rejoins the line owing the rest
      EXIT WHEN v_dn > v_hor;
      FOR q IN 1 .. nd LOOP
        CONTINUE WHEN d_done[q] OR d_a[q] > v_dn;
        d_done[q] := true;
        j := d_j[q];
        i := s_car[j];
        IF i IS NOT NULL AND c_start[i] IS NOT NULL AND c_start[i] < d_a[q] AND c_ready[i] > d_a[q] THEN
          v_frac := (c_ready[i] - d_a[q]) / GREATEST(c_ready[i] - c_start[i], 0.01);
          c_md[i] := c_md[i] * v_frac;
          c_ml[i] := c_ml[i] * v_frac;
          c_ready[i] := NULL; c_start[i] := NULL; c_kind[i] := NULL;
          c_gate[i] := d_a[q];
          c_x[i] := c_x[i] + 1;
          v_seated := v_seated - 1;
          s_car[j] := NULL;
          s_free[j] := d_b[q];
          -- 0623: its departure is undone until it is charged
          IF c_ret[i] IS NOT NULL THEN
            IF NOT c_void[c_ret[i]] THEN
              c_void[c_ret[i]] := true;
              IF c_vk[c_ret[i]] = 1 THEN n_live := n_live - 1; END IF;
            END IF;
            c_ret[i] := NULL;
          END IF;
        ELSE
          s_free[j] := GREATEST(s_free[j], d_b[q]);
        END IF;
      END LOOP;
      CONTINUE;
    END IF;
    EXIT WHEN t_c IS NULL OR t_a IS NULL;
    t := GREATEST(t, t_c, t_a);
    EXIT WHEN t > v_hor;
    v_live := v_on AND t < v_ttl;
    -- the kinds free at t, read once, as the cursor reads them once a tick
    SELECT CASE WHEN bool_or(z2.k = 'dcfc') AND bool_or(z2.k = 'l2') THEN 'both'
                WHEN bool_or(z2.k = 'dcfc') THEN 'dcfc' ELSE 'l2' END
      INTO v_mode FROM unnest(s_k, s_free) AS z2(k, f) WHERE z2.f <= t;
    -- the cars waiting at t, in the cursor's order at t
    SELECT array_agg(u.i ORDER BY
             u.imm DESC,
             CASE WHEN v_live THEN u.w >= v_pin END DESC NULLS LAST,
             CASE WHEN v_live AND NOT (u.w >= v_pin) THEN
                    CASE WHEN u.rk IS NULL THEN 500
                         ELSE u.rk + CASE WHEN v_mode = 'dcfc' AND u.ok = 'l2' THEN 1000
                                          WHEN v_mode = 'l2' AND u.ok = 'dcfc' THEN 1000 ELSE 0 END END END ASC NULLS LAST,
             (u.w + u.g) / u.g DESC, u.soc ASC, u.idr ASC)
      INTO v_order
      FROM (SELECT z3.i, c_imm[z3.i] AS imm,
                   CASE WHEN c_inb[z3.i] THEN t - c_av[z3.i] ELSE c_w0[z3.i] + t END AS w,
                   c_g[z3.i] AS g, c_soc[z3.i] AS soc, c_idr[z3.i] AS idr, c_rank[z3.i] AS rk, c_okind[z3.i] AS ok
              FROM generate_subscripts(c_ready, 1) AS z3(i)
             WHERE z3.i <= n AND c_ready[z3.i] IS NULL AND c_gate[z3.i] <= t
               AND c_vk[z3.i] < 2 AND NOT c_void[z3.i]) u;
    v_any := false;
    SELECT count(*) INTO v_free_n FROM unnest(s_free) f WHERE f <= t;
    FOREACH i IN ARRAY COALESCE(v_order, '{}'::int[]) LOOP
      EXIT WHEN v_free_n = 0;     -- every charger free at t is taken: the rest wait for the next one
      v_want := CASE WHEN v_live AND NOT c_imm[i] AND c_okind[i] IN ('dcfc', 'l2') THEN c_okind[i]
                     WHEN c_soc[i] < 45 OR c_imm[i] THEN 'dcfc' ELSE 'l2' END;
      best := NULL;
      FOR j IN 1..m LOOP
        CONTINUE WHEN s_free[j] > t;
        CONTINUE WHEN (s_k[j] = 'dcfc' AND NOT c_dok[i]) OR (s_k[j] = 'l2' AND NOT c_lok[i]);
        IF best IS NULL OR (s_k[j] = v_want AND s_k[best] <> v_want) THEN best := j; END IF;
      END LOOP;
      CONTINUE WHEN best IS NULL;
      v_dur := CASE WHEN s_k[best] = 'dcfc' THEN c_md[i] ELSE c_ml[i] END;
      c_start[i] := t; c_ready[i] := t + v_dur; c_kind[i] := s_k[best];
      IF c_s0[i] IS NULL THEN c_s0[i] := t; c_k0[i] := s_k[best]; END IF;   -- 0621
      s_free[best] := t + GREATEST(v_dur, 0.01);
      s_car[best] := i;                                                     -- 0621
      v_seated := v_seated + 1; v_any := true; v_free_n := v_free_n - 1;
      IF t < v_ttl THEN
        v_first := v_first || (c_id[i] || '@' || s_k[best] || '@' || to_char(t, 'FM99990.00'));
      END IF;
      -- 0623: a car here for its visit now leaves once this charge ends
      IF o_on AND c_vk[i] = 0 AND o_ret ? c_id[i] THEN
        np := np + 1; p_car[np] := c_id[i]; p_ready[np] := c_ready[i]; p_e[np] := 0; p_sdep[np] := NULL; p_par[np] := i;
        p_o[np] := 0;                                                                            -- 0624
      END IF;
    END LOOP;
    IF NOT v_any THEN
      -- no car waiting can use a charger free at t: those chargers wait for the next charger to free, car to arrive,
      -- or (0621) charger to go down
      SELECT min(f) INTO t_c FROM unnest(s_free) f WHERE f > t;
      SELECT min(u.a) INTO t_a FROM unnest(c_gate, c_ready, c_vk, c_void) AS u(a, r, vk, vd)
       WHERE u.r IS NULL AND u.a > t AND u.vk < 2 AND NOT u.vd;
      t_next := LEAST(t_c, t_a, v_dn);
      EXIT WHEN t_next IS NULL;
      FOR j IN 1..m LOOP
        IF s_free[j] <= t THEN s_free[j] := t_next; END IF;
      END LOOP;
    END IF;
  END LOOP;

  -- 0623: no departure is left queued here: every exit above comes after the queue is drained at the loop's top, and a
  -- pass that seats a car always loops again
  SELECT jsonb_build_object(
           'cars', n0,
           'inbound', count(*) FILTER (WHERE c_inb[z.i]),
           'chargers', m,
           'seated', count(*) FILTER (WHERE c_ready[z.i] IS NOT NULL),
           'with_due', count(*) FILTER (WHERE c_due[z.i] IS NOT NULL),
           'on_time', count(*) FILTER (WHERE c_due[z.i] IS NOT NULL AND c_ready[z.i] IS NOT NULL AND c_ready[z.i] <= c_due[z.i]),
           'late_sum', round(COALESCE(sum(GREATEST(COALESCE(c_ready[z.i], v_hor + LEAST(c_md[z.i], c_ml[z.i])) - c_due[z.i], 0))
                                        FILTER (WHERE c_due[z.i] IS NOT NULL), 0)::numeric, 2),
           'flow_sum', round(COALESCE(sum(COALESCE(c_ready[z.i], v_hor + LEAST(c_md[z.i], c_ml[z.i])) - c_av[z.i]), 0)::numeric, 2),
           'line_flow_sum', round(COALESCE(sum(COALESCE(c_ready[z.i], v_hor + LEAST(c_md[z.i], c_ml[z.i])))
                                             FILTER (WHERE NOT c_inb[z.i]), 0)::numeric, 2),
           'on_dcfc', count(*) FILTER (WHERE c_kind[z.i] = 'dcfc'),
           'on_l2', count(*) FILTER (WHERE c_kind[z.i] = 'l2'),
           -- the seats made in the order's window, as a set: the same seats made in another order are the same seats
           'first', to_jsonb(ARRAY(SELECT f FROM unnest(v_first) f ORDER BY f)))
    INTO v_out
    FROM generate_subscripts(c_ready, 1) AS z(i)
   WHERE z.i <= n0;
  IF o_on THEN
    -- 0623: the second visits
    SELECT v_out || jsonb_build_object(
             'returns', count(*) FILTER (WHERE NOT c_void[z.i]),
             'returns_past_horizon', count(*) FILTER (WHERE NOT c_void[z.i] AND c_vk[z.i] = 2),
             'returns_seated', count(*) FILTER (WHERE NOT c_void[z.i] AND c_vk[z.i] = 1 AND c_ready[z.i] IS NOT NULL),
             'stays', v_stays,
             'flow2_sum', round((v_out ->> 'flow_sum')::numeric + COALESCE(sum(
                            CASE WHEN c_vk[z.i] = 2 THEN LEAST(c_md[z.i], c_ml[z.i])
                                 ELSE COALESCE(c_ready[z.i], v_hor + LEAST(c_md[z.i], c_ml[z.i])) - c_av[z.i] END)
                            FILTER (WHERE NOT c_void[z.i]), 0)::numeric, 2),
             'out_min', round(COALESCE(sum(GREATEST(LEAST(c_av[z.i], o_win) - c_dep[z.i], 0))
                                       FILTER (WHERE NOT c_void[z.i] AND c_dep[z.i] < o_win), 0)::numeric, 2),
             'window_min', o_win)
      INTO v_out
      FROM generate_series(n0 + 1, GREATEST(n, n0)) AS z(i)
     WHERE z.i > n0;
  END IF;
  IF COALESCE(p_trace, false) THEN
    v_out := v_out || jsonb_build_object('seats', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', c_id[z.i], 's0', round(c_s0[z.i]::numeric, 2), 'k0', c_k0[z.i],
               'r', round(c_ready[z.i]::numeric, 2), 'k', c_kind[z.i], 'a', round(c_av[z.i]::numeric, 2),
               'inb', c_inb[z.i], 'x', c_x[z.i]) ORDER BY z.i)
        FROM generate_subscripts(c_ready, 1) AS z(i) WHERE z.i <= n0), '[]'::jsonb));
    IF o_on THEN
      v_out := v_out || jsonb_build_object('return_seats', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                 'id', c_id[z.i], 'dep', round(c_dep[z.i]::numeric, 2), 'a', round(c_av[z.i]::numeric, 2),
                 'soc', round(c_soc[z.i]::numeric, 1), 's0', round(c_s0[z.i]::numeric, 2), 'k0', c_k0[z.i],
                 'r', round(c_ready[z.i]::numeric, 2), 'k', c_kind[z.i], 'past', c_vk[z.i] = 2)
                 || CASE WHEN o_cls THEN jsonb_build_object('dc', c_dc[z.i]) ELSE '{}'::jsonb END ORDER BY z.i)
          FROM generate_series(n0 + 1, GREATEST(n, n0)) AS z(i) WHERE z.i > n0 AND NOT c_void[z.i]), '[]'::jsonb));
    END IF;
  END IF;
  RETURN v_out;
END $fn$;

COMMENT ON FUNCTION public.ottoq_charge_line_schedule(jsonb, jsonb, integer, text, boolean) IS
'0621. The charge line as a list schedule (0620''s simulator): with p_trace, every car''s first seat, last kind and ready time; a charger carrying dn [[from, until], ...] goes down and back, its car re-queued to finish (rule 9). 0623: with an outflow block, cars leave after their charge and come back owing one (each car over its visit now and its next): returns, stays, flow2_sum and out_min, and with p_trace the returns. 0624: with dwell_by, each car''s dwell on its class''s curve from its class''s clock, spread within each class. Pure.';

-- ══ (f) the grader: each car on its class's curve, the pooled curve beside it ═════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_charge_order_forecast_errors(p_state jsonb, p_real jsonb, p_expected jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0623: 0621's forecast errors, and on a state with an outflow block the outflow's forecast against what came. Returns:
  -- for every car the state models, the return the expected future (p_expected: the traced schedule of the order that
  -- ran) put inside the window against the one the car really made (p_real.returns): modelled, real, hits (both, by
  -- car), the timing of the hits and the arrival times of each as sums. The dwell, for every car whose charge's end was
  -- seen, against the curve past how long it had already been parked: whether it was gone by the cut against the
  -- curve's chance of that (their sum and Brier score), and for the cars that went, where their dwell fell between the
  -- two (pit_*: under the curve's median of that stretch, under its 80th percentile, and the sum). A car still parked
  -- at the cut is graded only on the first, so the cut cannot tilt the second. And the unseen: cars nobody modelled
  -- that joined the line, and of them those that came home.
  -- 0624: on a state with `dwell_by`, each car's dwell is graded on its class's curve (its `dc`; the pooled curve where
  -- the class has none) from its class's clock (a parked clear car's `o`), and two more keys sit beside `dwell`:
  -- `dwell_pooled`, the pooled curve's score on the same cars from their charge's end (0623's grade), and `dwell_by`,
  -- the score by class (`pooled` for the cars graded on the pooled curve). So the self-review can see, order by order,
  -- whether the classes still beat one curve. Without dwell_by, 0623's result.
  SELECT public.ottoq_charge_order_forecast_errors(p_state, p_real)
         || CASE WHEN jsonb_typeof(p_state -> 'outflow') IS DISTINCT FROM 'object' THEN '{}'::jsonb ELSE jsonb_build_object('outflow', (
              WITH o AS (SELECT COALESCE((p_real ->> 'observed_min')::numeric, 0) AS w),
              g AS (SELECT ARRAY(SELECT CASE WHEN jsonb_typeof(x.value) = 'number' THEN (x.value #>> '{}')::float8 END
                                   FROM jsonb_array_elements(COALESCE(p_state #> '{outflow,dwell,q}', '[]'::jsonb))
                                        WITH ORDINALITY x(value, i) ORDER BY x.i) AS q,
                           (p_state #>> '{outflow,dwell,f_max}')::float8 AS fmax,
                           (p_state #>> '{outflow,dwell,max_min}')::float8 AS mx),
              -- 0624: each class's curve, as g is the pooled one's (none without dwell_by)
              cg AS (SELECT c.key, ARRAY(SELECT CASE WHEN jsonb_typeof(x.value) = 'number' THEN (x.value #>> '{}')::float8 END
                                           FROM jsonb_array_elements(c.value -> 'q') WITH ORDINALITY x(value, i) ORDER BY x.i) AS q,
                            (c.value ->> 'f_max')::float8 AS fmax, (c.value ->> 'max_min')::float8 AS mx
                       FROM jsonb_each(CASE WHEN jsonb_typeof(p_state #> '{outflow,dwell_by}') = 'object'
                                            THEN p_state #> '{outflow,dwell_by}' ELSE '{}'::jsonb END) c
                      WHERE jsonb_typeof(c.value -> 'q') = 'array'),
              lv AS (SELECT x.value ->> 'id' AS id, COALESCE((x.value ->> 'e')::float8, 0) AS e,
                            GREATEST(COALESCE((x.value ->> 'o')::float8, 0), 0) AS so
                       FROM jsonb_array_elements(COALESCE(p_state #> '{outflow,leaving}', '[]'::jsonb)) x),
              m AS (SELECT x.value ->> 'id' AS id, (x.value ->> 'a')::numeric AS a, (x.value ->> 'dep')::numeric AS dep
                      FROM jsonb_array_elements(COALESCE(p_expected -> 'return_seats', '[]'::jsonb)) x),
              rl AS (SELECT r.key AS id, (r.value ->> 'eta')::numeric AS eta, (r.value ->> 'left')::numeric AS lft,
                            (r.value ->> 'ce')::numeric AS ce
                       FROM jsonb_each(COALESCE(p_real -> 'returns', '{}'::jsonb)) r),
              j AS (SELECT COALESCE(m.id, rl.id) AS id, o.w, CASE WHEN m.a <= o.w THEN m.a END AS ma,
                           CASE WHEN m.dep <= o.w THEN m.dep END AS md, rl.eta AS ra, rl.lft AS rd
                      FROM m FULL JOIN rl ON rl.id = m.id CROSS JOIN o),
              -- the dwells: a car whose charge ended before the clock was parked -ce minutes then (only a car the state
              -- lists as parked; one back in the line is not dwelling); one whose charge ended after it, from 0
              dz AS (SELECT rl.lft IS NOT NULL AS ev, (rl.lft - rl.ce)::float8 AS d, (o.w - rl.ce)::float8 AS cens,
                            CASE WHEN rl.ce < 0 THEN COALESCE(lv.e, -rl.ce::float8) ELSE 0 END AS e,
                            CASE WHEN rl.ce < 0 THEN COALESCE(lv.so, 0) ELSE 0 END AS so,         -- 0624: its class's clock
                            p_state #>> ARRAY['outflow', 'ret', rl.id, 'dc'] AS dc                -- 0624: its class
                       FROM rl CROSS JOIN o LEFT JOIN lv ON lv.id = rl.id
                      WHERE rl.ce IS NOT NULL AND (rl.ce >= 0 OR lv.id IS NOT NULL)),
              dc AS (SELECT dz.ev, public.ottoq_outflow_dwell_cdf(g.q, g.fmax, g.mx, dz.e) AS fe,
                            public.ottoq_outflow_dwell_cdf(g.q, g.fmax, g.mx, dz.cens) AS fc,
                            CASE WHEN dz.ev THEN public.ottoq_outflow_dwell_cdf(g.q, g.fmax, g.mx, dz.d) END AS fd,
                            -- 0624: its class's curve on its class's clock
                            dz.dc, cg.key IS NOT NULL AS by_cls,
                            CASE WHEN cg.key IS NOT NULL
                                 THEN public.ottoq_outflow_dwell_cdf(cg.q, cg.fmax, cg.mx, GREATEST(dz.e - dz.so, 0)) END AS ke,
                            CASE WHEN cg.key IS NOT NULL
                                 THEN public.ottoq_outflow_dwell_cdf(cg.q, cg.fmax, cg.mx, dz.cens - dz.so) END AS kc,
                            CASE WHEN cg.key IS NOT NULL AND dz.ev
                                 THEN public.ottoq_outflow_dwell_cdf(cg.q, cg.fmax, cg.mx, dz.d - dz.so) END AS kd
                       FROM dz CROSS JOIN g LEFT JOIN cg ON cg.key = dz.dc),
              -- p: the curve's chance the car is gone by the cut, given how long it had been parked; v: for a car that
              -- went, where its dwell fell in the curve between those two (uniform on (0, 1) when the curve is right,
              -- whatever the cut: a car still parked at the cut never enters it, so the cut cannot bias it). 0624: on
              -- its class's curve where it has one (pp and pv: the pooled curve's, 0623's grade)
              dw AS (SELECT dc.ev, dc.dc, dc.by_cls,
                            CASE WHEN dc.by_cls
                                 THEN CASE WHEN dc.ke < 1 THEN GREATEST(dc.kc - dc.ke, 0) / (1 - dc.ke) ELSE 0 END
                                 ELSE CASE WHEN dc.fe < 1 THEN GREATEST(dc.fc - dc.fe, 0) / (1 - dc.fe) ELSE 0 END END AS p,
                            CASE WHEN dc.by_cls
                                 THEN CASE WHEN dc.ev AND dc.kc > dc.ke
                                           THEN LEAST(GREATEST((dc.kd - dc.ke) / (dc.kc - dc.ke), 0), 1) END
                                 ELSE CASE WHEN dc.ev AND dc.fc > dc.fe
                                           THEN LEAST(GREATEST((dc.fd - dc.fe) / (dc.fc - dc.fe), 0), 1) END END AS v,
                            CASE WHEN dc.fe < 1 THEN GREATEST(dc.fc - dc.fe, 0) / (1 - dc.fe) ELSE 0 END AS pp,
                            CASE WHEN dc.ev AND dc.fc > dc.fe
                                 THEN LEAST(GREATEST((dc.fd - dc.fe) / (dc.fc - dc.fe), 0), 1) END AS pv
                       FROM dc)
              SELECT jsonb_build_object(
                       'cars', (SELECT count(*) FROM rl),
                       'modelled', count(*) FILTER (WHERE j.ma IS NOT NULL),
                       'real', count(*) FILTER (WHERE j.ra IS NOT NULL),
                       'hits', count(*) FILTER (WHERE j.ma IS NOT NULL AND j.ra IS NOT NULL),
                       'sum_err', round(COALESCE(sum(j.ma - j.ra) FILTER (WHERE j.ma IS NOT NULL AND j.ra IS NOT NULL), 0), 2),
                       'sum_abs_err', round(COALESCE(sum(abs(j.ma - j.ra)) FILTER (WHERE j.ma IS NOT NULL AND j.ra IS NOT NULL), 0), 2),
                       'sum_a_modelled', round(COALESCE(sum(j.ma), 0), 2),
                       'sum_a_real', round(COALESCE(sum(j.ra), 0), 2),
                       'left_both', count(*) FILTER (WHERE j.md IS NOT NULL AND j.rd IS NOT NULL),
                       'left_sum_abs_err', round(COALESCE(sum(abs(j.md - j.rd)) FILTER (WHERE j.md IS NOT NULL AND j.rd IS NOT NULL), 0), 2),
                       'dwell', (SELECT jsonb_build_object(
                                   'seen', count(*),
                                   'left', count(*) FILTER (WHERE dw.ev),
                                   'p_left', round(COALESCE(sum(dw.p), 0)::numeric, 3),
                                   'brier', round(COALESCE(sum((dw.p - CASE WHEN dw.ev THEN 1 ELSE 0 END) ^ 2), 0)::numeric, 3),
                                   'pit_n', count(dw.v),
                                   'pit50', count(*) FILTER (WHERE dw.v <= 0.5),
                                   'pit80', count(*) FILTER (WHERE dw.v <= 0.8),
                                   'pit_sum', round(COALESCE(sum(dw.v), 0)::numeric, 3))
                                   FROM dw),
                       'unseen', jsonb_array_length(COALESCE(p_real -> 'appeared', '[]'::jsonb)),
                       'unseen_returned', (SELECT count(*) FROM jsonb_array_elements(COALESCE(p_real -> 'appeared', '[]'::jsonb)) x
                                            WHERE x.value ->> 'how' = 'returned'))
                     -- 0624: the pooled curve's score on the same cars, and the score by class
                     || CASE WHEN NOT EXISTS (SELECT 1 FROM cg) THEN '{}'::jsonb ELSE jsonb_build_object(
                          'dwell_pooled', (SELECT jsonb_build_object(
                                             'seen', count(*),
                                             'left', count(*) FILTER (WHERE dw.ev),
                                             'p_left', round(COALESCE(sum(dw.pp), 0)::numeric, 3),
                                             'brier', round(COALESCE(sum((dw.pp - CASE WHEN dw.ev THEN 1 ELSE 0 END) ^ 2), 0)::numeric, 3),
                                             'pit_n', count(dw.pv),
                                             'pit50', count(*) FILTER (WHERE dw.pv <= 0.5),
                                             'pit80', count(*) FILTER (WHERE dw.pv <= 0.8),
                                             'pit_sum', round(COALESCE(sum(dw.pv), 0)::numeric, 3))
                                             FROM dw),
                          'dwell_by', (SELECT COALESCE(jsonb_object_agg(x.k, x.j), '{}'::jsonb) FROM (
                                         SELECT CASE WHEN dw.by_cls THEN dw.dc ELSE 'pooled' END AS k,
                                                jsonb_build_object(
                                                  'seen', count(*),
                                                  'left', count(*) FILTER (WHERE dw.ev),
                                                  'p_left', round(COALESCE(sum(dw.p), 0)::numeric, 3),
                                                  'brier', round(COALESCE(sum((dw.p - CASE WHEN dw.ev THEN 1 ELSE 0 END) ^ 2), 0)::numeric, 3),
                                                  'brier_pooled', round(COALESCE(sum((dw.pp - CASE WHEN dw.ev THEN 1 ELSE 0 END) ^ 2), 0)::numeric, 3),
                                                  'pit_n', count(dw.v),
                                                  'pit50', count(*) FILTER (WHERE dw.v <= 0.5),
                                                  'pit80', count(*) FILTER (WHERE dw.v <= 0.8),
                                                  'pit_sum', round(COALESCE(sum(dw.v), 0)::numeric, 3)) AS j
                                           FROM dw GROUP BY 1) x)) END
                FROM j)) END
$fn$;

-- ══ grants ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
GRANT EXECUTE ON FUNCTION public.ottoq_dwell_class(jsonb, timestamptz) TO anon, authenticated, service_role;

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v1$
DECLARE v_n int; v_bad int; v_on int; v_obad int; v_sbad int; v_fbad int; v_old jsonb; v_new jsonb; v_through timestamptz;
BEGIN
  -- (i) the stored snapshots simulate and compare as before this file
  SELECT count(*), count(*) FILTER (WHERE b.k IS DISTINCT FROM public.ottoq_charge_line_schedule(s.state, NULL, b.sc, s.seed, true)
                                       OR b.a IS DISTINCT FROM public.ottoq_charge_line_schedule(s.state, s.agent_order, b.sc, s.seed, true)
                                       OR b.c IS DISTINCT FROM public.ottoq_charge_line_compare(
                                            public.ottoq_charge_line_simulate(s.state, NULL, b.sc, s.seed),
                                            public.ottoq_charge_line_simulate(s.state, s.agent_order, b.sc, s.seed)))
    INTO v_n, v_bad
    FROM v0624_before b JOIN public.ottoq_charge_order_snapshots s USING (order_id);
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0624 V1: % of % stored simulations and comparisons changed', v_bad, v_n;
  END IF;
  -- (ii) 0623's outflow: this file's outflow given 0623's fit returns the same state, and the schedule and the forecast
  -- errors on it return what 0623's did
  SELECT count(*),
         count(*) FILTER (WHERE o.aug IS DISTINCT FROM
                                public.ottoq_charge_line_outflow(o.run, o.depot, o.clock, o.state0, o.ct, o.rt0, o.ev)),
         count(*) FILTER (WHERE o.k0 IS DISTINCT FROM public.ottoq_charge_line_schedule(o.aug, o.ord, 0, o.seed, true)
                             OR o.a3 IS DISTINCT FROM public.ottoq_charge_line_schedule(o.aug, o.agent_order, 3, o.seed, true)),
         count(*) FILTER (WHERE o.fe IS DISTINCT FROM public.ottoq_charge_order_forecast_errors(o.aug, o.rz, o.k0))
    INTO v_on, v_obad, v_sbad, v_fbad
    FROM v0624_out o;
  IF v_obad > 0 OR v_sbad > 0 OR v_fbad > 0 THEN
    RAISE EXCEPTION '0624 V1: on % of 0623''s outflow states, % outflows, % schedules and % forecast errors changed',
      v_on, v_obad, v_sbad, v_fbad;
  END IF;
  -- (iii) the fit through d9d49732's start: every key 0623 computed as it was, and dwell_by added
  SELECT f.through, f.params INTO v_through, v_old FROM v0624_fit f;
  IF v_through IS NOT NULL THEN
    v_new := public.ottoq_return_model_params('11111111-1111-1111-1111-111111111111'::uuid, v_through, interval '21 days');
    INSERT INTO v0624_fit_new VALUES (v_new);
    IF (v_new - 'dwell_by') IS DISTINCT FROM v_old OR jsonb_typeof(v_new -> 'dwell_by') IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION '0624 V1: the fit through d9d49732''s start no longer computes 0623''s keys as it did, or carries no dwell_by';
    END IF;
  END IF;
  RAISE NOTICE '0624 V1: % stored simulations and comparisons (% snapshots x 2 futures) unchanged; on % of 0623''s outflow states the outflow, the schedule (both futures) and the forecast errors unchanged; the fit through d9d49732''s start keeps 0623''s keys (%)',
    v_n, v_n / 2, v_on, CASE WHEN v_through IS NULL THEN 'run not here' ELSE 'and adds dwell_by' END;
END $v1$;

DO $v2$
DECLARE
  c_run   constant uuid := 'd9d49732-cf28-42c3-aac9-9c3f606a2c92';
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_start timestamptz;
  v_rt    jsonb;
  r       record;
  v_t0    timestamptz := clock_timestamp();
  v_orders int := 0; v_m int := 0; v_real int := 0; v_hit int := 0; v_abs numeric := 0; v_am numeric := 0; v_ar numeric := 0;
  -- each car on its class's curve
  v_seen int := 0; v_left int := 0; v_pleft numeric := 0; v_brier numeric := 0; v_pn int := 0; v_p50 int := 0;
  v_p80 int := 0; v_psum numeric := 0;
  -- the pooled curve on the same cars
  v_qleft numeric := 0; v_qbrier numeric := 0; v_qn int := 0; v_q50 int := 0; v_q80 int := 0;
  v_by jsonb := '{}'::jsonb;
  v_ms int; v_ret jsonb; v_aug jsonb; v_ct jsonb; v_o jsonb; v_x jsonb; v_rz jsonb;
  v_c50 numeric; v_c80 numeric; v_dratio numeric; v_ratio numeric; v_bc numeric; v_bq numeric; v_bb numeric; v_share numeric;
BEGIN
  SELECT started_at INTO v_start FROM ottoq_sim_runs WHERE sim_run_id = c_run AND status = 'completed';
  IF v_start IS NULL OR NOT EXISTS (SELECT 1 FROM ottoq_charge_order_hindsight WHERE sim_run_id = c_run) THEN
    RAISE NOTICE '0624 V2: run d9d49732 is not here; the dwell by class is executed by the tests';
    RETURN;
  END IF;
  -- the return model as it would have been fitted the moment the run began: out of sample for every order on it
  v_rt := jsonb_build_object('usable', true, 'estimate_id', NULL,
                             'params', COALESCE((SELECT params FROM v0624_fit_new),
                                                public.ottoq_return_model_params(c_depot, v_start, interval '21 days')));
  FOR r IN
    SELECT h.order_id, h.sim_clock, h.observed_min, h.taken, h.realized, s.state, s.seed, s.agent_order
      FROM ottoq_charge_order_hindsight h JOIN ottoq_charge_order_snapshots s USING (order_id)
     WHERE h.sim_run_id = c_run
     ORDER BY h.order_id
  LOOP
    IF (r.state #>> '{models,charge_time_model}') = 'charge_time_v2' THEN
      SELECT jsonb_build_object('params', f.params) INTO v_ct FROM ottoq_charge_clock_fits f
       WHERE f.fit_id = (r.state #>> '{models,charge_time}')::bigint;
    ELSE
      SELECT jsonb_build_object('params', e.params) INTO v_ct FROM ottoq_learned_estimates e
       WHERE e.estimate_id = (r.state #>> '{models,charge_time}')::bigint;
    END IF;
    v_aug := public.ottoq_charge_line_outflow(c_run, c_depot, r.sim_clock, r.state, v_ct, v_rt,
                                              public.ottoq_charge_clock_run_evidence(v_ct, c_run, r.sim_clock));
    CONTINUE WHEN jsonb_typeof(v_aug #> '{outflow,dwell_by}') IS DISTINCT FROM 'object';
    v_orders := v_orders + 1;
    -- what each modelled car really did, by the realized reader's rule
    SELECT COALESCE(jsonb_object_agg(c.id, jsonb_strip_nulls(jsonb_build_object(
             'ce', CASE WHEN ce.at IS NOT NULL THEN round((extract(epoch FROM (ce.at - r.sim_clock)) / 60.0)::numeric, 2) END,
             'left', CASE WHEN d.dispatched_at IS NOT NULL
                          THEN round((extract(epoch FROM (d.dispatched_at - r.sim_clock)) / 60.0)::numeric, 2) END,
             'eta', CASE WHEN d.actual_return_at IS NOT NULL AND d.actual_return_at <= r.sim_clock + make_interval(secs => r.observed_min * 60)
                         THEN round((extract(epoch FROM (d.actual_return_at - r.sim_clock)) / 60.0)::numeric, 2) END,
             'soc', CASE WHEN d.actual_return_at IS NOT NULL AND d.actual_return_at <= r.sim_clock + make_interval(secs => r.observed_min * 60)
                         THEN round(d.soc_at_return_pct, 1) END))), '{}'::jsonb)
      INTO v_ret
      FROM (SELECT DISTINCT z.id FROM (
              SELECT x.value ->> 'id' AS id FROM jsonb_array_elements(v_aug -> 'cars') x
              UNION ALL SELECT x.value ->> 'id' FROM jsonb_array_elements(v_aug -> 'inbound') x
              UNION ALL SELECT x.value ->> 'car' FROM jsonb_array_elements(v_aug -> 'chargers') x WHERE x.value ? 'car'
              UNION ALL SELECT x.value ->> 'id' FROM jsonb_array_elements(v_aug #> '{outflow,leaving}') x) z
             WHERE z.id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') c
      LEFT JOIN LATERAL (SELECT dd.dispatched_at, dd.actual_return_at, dd.soc_at_return_pct FROM ottoq_vehicle_dispatches dd
                          WHERE dd.sim_run_id = c_run AND dd.vehicle_id = c.id::uuid
                            AND dd.dispatched_at > r.sim_clock
                            AND dd.dispatched_at <= r.sim_clock + make_interval(secs => r.observed_min * 60)
                          ORDER BY dd.dispatched_at LIMIT 1) d ON true
      LEFT JOIN LATERAL (SELECT max(dd.dispatched_at) AS at FROM ottoq_vehicle_dispatches dd
                          WHERE dd.sim_run_id = c_run AND dd.vehicle_id = c.id::uuid AND dd.dispatched_at <= r.sim_clock) lo ON true
      LEFT JOIN LATERAL (SELECT max(os.ended_at) AS at FROM ocpp_sessions os
                          WHERE os.sim_run_id = c_run AND os.vehicle_id = c.id::uuid AND os.stopped_reason = 'completed'
                            AND os.ended_at <= COALESCE(d.dispatched_at, r.sim_clock + make_interval(secs => r.observed_min * 60))
                            AND (lo.at IS NULL OR os.ended_at > lo.at)) ce ON true;
    -- the expected future of the order that ran (the agent's if it was taken, else the kernel's), graded against it
    v_x := public.ottoq_charge_line_schedule(v_aug, CASE WHEN r.taken THEN r.agent_order END, 0, r.seed, true);
    v_rz := (r.realized || jsonb_build_object('returns', v_ret))
            || jsonb_build_object('appeared', COALESCE((
                 SELECT jsonb_agg(x.value ORDER BY x.o) FROM jsonb_array_elements(r.realized -> 'appeared') WITH ORDINALITY x(value, o)
                  WHERE NOT (v_ret ? (x.value ->> 'id'))), '[]'::jsonb));
    v_o := public.ottoq_charge_order_forecast_errors(v_aug, v_rz, v_x) -> 'outflow';
    v_m := v_m + (v_o ->> 'modelled')::int;
    v_real := v_real + (v_o ->> 'real')::int;
    v_hit := v_hit + (v_o ->> 'hits')::int;
    v_abs := v_abs + (v_o ->> 'sum_abs_err')::numeric;
    v_am := v_am + (v_o ->> 'sum_a_modelled')::numeric;
    v_ar := v_ar + (v_o ->> 'sum_a_real')::numeric;
    v_seen := v_seen + (v_o #>> '{dwell,seen}')::int;
    v_left := v_left + (v_o #>> '{dwell,left}')::int;
    v_pleft := v_pleft + (v_o #>> '{dwell,p_left}')::numeric;
    v_brier := v_brier + (v_o #>> '{dwell,brier}')::numeric;
    v_pn := v_pn + (v_o #>> '{dwell,pit_n}')::int;
    v_p50 := v_p50 + (v_o #>> '{dwell,pit50}')::int;
    v_p80 := v_p80 + (v_o #>> '{dwell,pit80}')::int;
    v_psum := v_psum + (v_o #>> '{dwell,pit_sum}')::numeric;
    v_qleft := v_qleft + (v_o #>> '{dwell_pooled,p_left}')::numeric;
    v_qbrier := v_qbrier + (v_o #>> '{dwell_pooled,brier}')::numeric;
    v_qn := v_qn + (v_o #>> '{dwell_pooled,pit_n}')::int;
    v_q50 := v_q50 + (v_o #>> '{dwell_pooled,pit50}')::int;
    v_q80 := v_q80 + (v_o #>> '{dwell_pooled,pit80}')::int;
    -- the score by class, summed over the orders
    SELECT COALESCE(jsonb_object_agg(k.key, jsonb_build_object(
             'seen', COALESCE((v_by #>> ARRAY[k.key, 'seen'])::numeric, 0) + COALESCE((k.value ->> 'seen')::numeric, 0),
             'left', COALESCE((v_by #>> ARRAY[k.key, 'left'])::numeric, 0) + COALESCE((k.value ->> 'left')::numeric, 0),
             'p_left', COALESCE((v_by #>> ARRAY[k.key, 'p_left'])::numeric, 0) + COALESCE((k.value ->> 'p_left')::numeric, 0),
             'brier', COALESCE((v_by #>> ARRAY[k.key, 'brier'])::numeric, 0) + COALESCE((k.value ->> 'brier')::numeric, 0),
             'brier_pooled', COALESCE((v_by #>> ARRAY[k.key, 'brier_pooled'])::numeric, 0)
                             + COALESCE((k.value ->> 'brier_pooled')::numeric, 0))), '{}'::jsonb)
      INTO v_by
      FROM (SELECT b.key, b.value FROM jsonb_each(COALESCE(v_o -> 'dwell_by', '{}'::jsonb)) b
            UNION ALL
            SELECT b.key, '{}'::jsonb FROM jsonb_each(v_by) b WHERE NOT (COALESCE(v_o -> 'dwell_by', '{}'::jsonb) ? b.key)) k;
  END LOOP;
  v_ms := round(extract(epoch FROM clock_timestamp() - v_t0) * 1000);
  v_c50 := round(v_p50::numeric / NULLIF(v_pn, 0), 3);
  v_c80 := round(v_p80::numeric / NULLIF(v_pn, 0), 3);
  v_dratio := round(v_pleft / NULLIF(v_left, 0), 3);
  v_ratio := round(v_m::numeric / NULLIF(v_real, 0), 3);
  v_share := v_left::numeric / NULLIF(v_seen, 0);
  v_bc := v_brier / NULLIF(v_seen, 0);
  v_bq := v_qbrier / NULLIF(v_seen, 0);
  v_bb := v_share * (1 - v_share);
  RAISE NOTICE '0624 V2 (% graded orders of d9d49732, the curves fitted through the run''s start, % ms): of % cars whose charge''s end was seen, % left inside the window against % expected by class (ratio %) and % by the pooled curve (ratio %); Brier % by class against % pooled and % for the base rate',
    v_orders, v_ms, v_seen, v_left, round(v_pleft, 1), v_dratio, round(v_qleft, 1), round(v_qleft / NULLIF(v_left, 0), 3),
    round(v_bc, 4), round(v_bq, 4), round(v_bb, 4);
  RAISE NOTICE '0624 V2 of the % that left with the curve open, % fell under their curve''s median for that stretch (%), % under its 80th percentile (%), mean %; on the pooled curve % and %',
    v_pn, v_p50, v_c50, v_p80, v_c80, round(v_psum / NULLIF(v_pn, 0), 3),
    round(v_q50::numeric / NULLIF(v_qn, 0), 3), round(v_q80::numeric / NULLIF(v_qn, 0), 3);
  RAISE NOTICE '0624 V2 by class (cars seen, left, expected, Brier by class, Brier pooled): %',
    (SELECT string_agg(format('%s %s/%s/%s/%s/%s', k.key, (k.value ->> 'seen')::numeric, (k.value ->> 'left')::numeric,
                              round((k.value ->> 'p_left')::numeric, 1),
                              round((k.value ->> 'brier')::numeric / NULLIF((k.value ->> 'seen')::numeric, 0), 4),
                              round((k.value ->> 'brier_pooled')::numeric / NULLIF((k.value ->> 'seen')::numeric, 0), 4)),
                       ' | ' ORDER BY k.key)
       FROM jsonb_each(v_by) k);
  RAISE NOTICE '0624 V2 returns inside the window: % forecast, % real (ratio %), mean arrival % against % minutes; by car % hits (recall %, precision %), % minutes apart',
    v_m, v_real, v_ratio, round(v_am / NULLIF(v_m, 0), 1), round(v_ar / NULLIF(v_real, 0), 1), v_hit,
    round(v_hit::numeric / NULLIF(v_real, 0), 3), round(v_hit::numeric / NULLIF(v_m, 0), 3), round(v_abs / NULLIF(v_hit, 0), 2);
  IF v_orders = 0 OR v_bc IS NULL OR v_bc >= v_bq OR v_bc > v_bb
     OR v_c50 IS NULL OR v_c50 NOT BETWEEN 0.40 AND 0.60 OR v_c80 IS NULL OR v_c80 NOT BETWEEN 0.70 AND 0.90
     OR v_dratio IS NULL OR v_dratio NOT BETWEEN 0.75 AND 1.33 OR v_ratio IS NULL OR v_ratio NOT BETWEEN 0.75 AND 1.33 THEN
    RAISE EXCEPTION '0624 V2: the dwell by class does not beat one curve, or is not calibrated (Brier % against % pooled and % base rate; under its median %, under its 80th percentile %; departures expected over real %, returns forecast over real %): not applied',
      round(v_bc, 4), round(v_bq, 4), round(v_bb, 4), v_c50, v_c80, v_dratio, v_ratio;
  END IF;
END $v2$;

-- the first fit with the dwell by class, at apply (the nightly job already calls the fit)
SELECT public.ottoq_fit_return_model('11111111-1111-1111-1111-111111111111'::uuid, NULL, interval '21 days',
                                     '0624: the first fit with the dwell by class, at apply');

DO $v3$
DECLARE v_rt jsonb; r record; v_state jsonb; t0 timestamptz; v_ms numeric;
BEGIN
  v_rt := public.ottoq_learned_estimate('11111111-1111-1111-1111-111111111111'::uuid, 'return_v1');
  IF jsonb_typeof(v_rt #> '{params,dwell_by}') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION '0624 V3: the fit at apply carries no dwell_by';
  END IF;
  RAISE NOTICE '0624 V3: return_v1 estimate % (usable %): dwell by class (charges, left, median minutes): %',
    v_rt -> 'estimate_id', v_rt -> 'usable',
    (SELECT string_agg(format('%s %s/%s/%s', k.key, k.value ->> 'n', k.value ->> 'left', k.value ->> 'median_min'), ' | ' ORDER BY k.key)
       FROM jsonb_each(v_rt #> '{params,dwell_by}') k);
  SELECT x.sim_run_id, x.depot_id, x.sim_clock_current INTO r
    FROM ottoq_sim_runs x WHERE x.status = 'running' AND x.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY x.started_at DESC LIMIT 1;
  IF r.sim_run_id IS NULL THEN
    RAISE NOTICE '0624 V3: no twin run is running; the state is executed by the tests';
    RETURN;
  END IF;
  t0 := clock_timestamp();
  v_state := public.ottoq_charge_line_state(r.sim_run_id, r.depot_id, r.sim_clock_current);
  v_ms := round(extract(epoch FROM clock_timestamp() - t0) * 1000);
  RAISE NOTICE '0624 V3 on running run %: state % ms, outflow v %, classes %',
    r.sim_run_id, v_ms, v_state #> '{outflow,v}',
    (SELECT string_agg(format('%s %s', c.dc, c.n), ', ' ORDER BY c.dc)
       FROM (SELECT e.value ->> 'dc' AS dc, count(*) AS n
               FROM jsonb_each(COALESCE(v_state #> '{outflow,ret}', '{}'::jsonb)) e GROUP BY 1) c);
END $v3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0624_the_check_reads_each_cars_open_work', false, false,
  'The agent''s charge-order check times each charged car''s departure by what it has left to do: nothing (it leaves '
  'at once), a must-do service in a bay (it leaves when the bay is done), a run-start car, or a car out at work whose '
  'next visit is unknown, each on its own Kaplan-Meier curve refitted nightly with return_v1, a parked car''s clock '
  'starting when its work was done. The grader scores the curves by class beside the pooled one. Without dwell_by '
  'every reader returns what it returned (V1); a person''s dial turns it off. FALSE/FALSE: the tick path is untouched '
  'and orders exist only on operator_demo runs (0615).',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
