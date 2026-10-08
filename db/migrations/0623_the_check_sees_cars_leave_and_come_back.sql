-- migration-version: PENDING
-- migration-name:    the_check_sees_cars_leave_and_come_back
--
-- 0623  **The check sees cars leave and come back.**
--       The first morning self-review (0621/0622, assessment 1, written 2026-10-08 16:46 UTC) named the outflow as the
--       largest single cause of the check's wrong forecasts: over the week's 61 graded orders, the cars the check never
--       saw coming carried 24% of the verdict mass (the exact Shapley split of 0621), and 532 of the 532 that came home
--       inside a window had left the depot after the order. The check's simulator has no departures. A car whose charge
--       ends is gone from it for good; in the depot it leaves, works its battery down to the learned reserve, and joins
--       the line again inside the same 90 minutes. 0623 models that: when a car leaves (the learned dwell after a charge),
--       when it is called home (the learned reserve and drain, or another call first), and what it owes when it is back,
--       for the cars in the line, the cars coming home, the cars charging now and the cars charged and still parked. And
--       it fixes what the finding said the objective would then need: every car is compared over the same two visits,
--       its visit now and its next one, so a faster turnaround is a gain and never "more cars in the line".
--       Chase, 2026-10-08: "When things get tight or congested, that's really when the agent layer should shine ... just
--       keep tightening the overall Superintelligence and learning of the agent layer ... it can't technically do XYZ, so
--       I should probably build that in." The self-review said what it could not do; this builds it. Rule 10 holds: the
--       dwell is an estimate refitted nightly from real departures, the check is engineering's change, and the one new
--       dial is a person's.
--
-- ══ §1 WHY (assessment 1; run d9d49732; the dispatch and session ledgers, measured 2026-10-08 17:10-17:30 UTC) ══════════
--
--   (a) What the check cannot see. Of the 532 cars that came home inside an order's window unseen, 243 were charging at
--       the order and 285 had finished charging and were still parked (their charge had ended a mean 16.8 minutes
--       before); 4 had neither. They left a mean 9.7 minutes after the order and came back about 70 minutes later, 467
--       of them at the battery reserve. The check saw none of them: its line drains and never refills.
--   (b) How long a charged car stays. Over 21 days of fine-tick runs, 1,716 completed charges: 1,490 cars left after
--       them and 226 were still parked when their run ended. Kaplan-Meier on those (the parked ones censored, not
--       dropped): 40% leave within 1.1 minutes, the median 7.5, p75 35, p90 134, and 3% stay past the last departure the
--       evidence saw (246 minutes at p95). Bimodal: a car with nothing left to do leaves at once; one with a service
--       waits for it, and some wait for the night.
--   (c) How long it is out. return_v1 (0619) already holds the cycle: called home at the reserve (49.9%), at a drain of
--       0.72% a minute, a 1.25-minute drive, and other calls home at 0.11 per work hour. From 100% that is 70 minutes
--       of work: inside one window.
--   (d) Why the objective had to change. 0620 compares the cars' minutes in the depot over their visit now. With
--       returns in the line, an order that gets cars out sooner brings them back sooner, and a sum over everything
--       inside a window counts that return against it. Counting each car over the same two visits (now and next) has no
--       such edge: the minutes a car spends waiting and charging, over both, are what the order changes, and every
--       minute out of them is a minute it can work.
--   (e) Measured before applying (V2's question, rolled back on live, 2026-10-08 17:40-18:10 UTC). On run d9d49732's
--       61 graded orders, out of sample (the dwell fitted through the run's start): of 2,712 cars whose charge's end
--       was seen, 2,390 left inside the window and the curve expected 1,986 (0.83). Of those that left, 53% did so
--       under the curve's median for their stretch and 80% under its 80th percentile (mean 0.457): where the window can
--       see it the curve's shape holds, and its level is low, because this run emptied its charged cars faster than
--       the depot's three weeks did (95% gone within 90 minutes, against the curve's 85%). The expected future of the
--       order that ran puts 594 returns inside the window against 544 real (1.09), a mean 74.4 minutes after the order
--       against 78.2. Car by car it is weak: its chance that each car leaves inside the window scores a Brier of 0.128,
--       worse than the 0.105 of giving every car the run's own share. The check's verdict agreed with hindsight on 40
--       of 61 orders and on 11 of the 18 that were decisions (39 and 8 as graded); with the drains spread as below, 39
--       and 10 (db/checks/0417 measures it again after the apply).
--   (f) Measured and not built. Moving the depot's curve toward the run's own departures so far (a life table pooling
--       the run's cars with the curve, which counted for 19 cars: the spread between 12 runs, estimated from the fit)
--       scored a Brier of 0.130 against 0.128 without it, and raised the departures expected only to 0.84. The dwell
--       swings inside a run: of the cars that left, 30% fell under the curve's median while the run had shown fewer
--       than 20 charges, and 72% once it had shown 20 to 50. A run's past dwells lag its next ones. What decides a
--       dwell is the car's own open work and the hour's demand, which no curve over all cars carries (G356).
--
-- ══ §2 WHAT ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) return_v1 learns the dwell. `ottoq_return_model_params(depot, through, window)` (read-only) is 0619's fit, key
--       for key, plus `dwell`: the Kaplan-Meier curve of the minutes from a completed charge to the car's next
--       departure, the car still parked when its run ended censored there, as quantiles at 0, 0.05, ..., 0.95 (NULL past
--       the curve's last step, f_max) and the last departure seen (max_min); fine ticks when they hold 30 departures.
--       `ottoq_fit_return_model` writes it (same signature, same nightly job, same usability test).
--   (b) The draws. `ottoq_hash_uniform(key)` (a uniform in (0,1), pure, as 0620's normal) and `ottoq_normal_quantile`
--       (the standard normal's inverse); `ottoq_outflow_dwell_cdf` and `ottoq_outflow_dwell_quantile` read the grid;
--       `ottoq_charge_line_return_draw` gives one car's departure, return, battery and charge back to its target: the
--       dwell after its charge (conditioned on how long it has already been parked), then the work to the reserve at the
--       learned drain (and its spread), or another call home first at the learned rate, then the drive. A sampled future
--       draws each of the three by the car's own hash. The expected future stratifies them: across the cars it models,
--       each car's dwell, call home and drain sit at its own probability, spaced evenly over (0, 1) in the order of a
--       hash of the car (the same on both sides of a comparison), so the cars together cover each curve as their
--       futures would; a single median for every car would send them all out, and bring them all back, at once. The
--       charge back stays at its median, as the line's own cars' do. When the grader puts in what happened, a car that
--       came back did so when it did, and one that had not by the cut does not come back before it.
--   (c) The state carries the outflow. `ottoq_charge_line_outflow(run, depot, clock, state, clock_model, return_model,
--       run_evidence)` (read-only) adds to a state `outflow`: the learned cycle, the dwell grid, the window (90), each
--       modelled car's charge back from the reserve on its own clock (`ret`), the cars charged and still parked
--       (`leaving`, with how long), and on each busy charger the car on it (`car`), all read from the session and
--       dispatch ledgers as of the clock, so it reads a live run and a stored order the same way.
--       `ottoq_charge_line_state` adds it when the run's `agent_charge_order_outflow` dial is 1 (its default).
--   (d) The simulator models it. `ottoq_charge_line_schedule` (0621's, same signature): with an outflow block, each
--       first visit spawns its return when it is seated, each charger's car and each parked car theirs at the start; a
--       return joins the line like a car coming home and is never sent past its next visit; a fault that stops a charge
--       undoes its departure until the car is charged. New totals: returns (inside the horizon, past it), stays,
--       `flow2_sum` (minutes waiting and charging over each car's two visits; a return past the horizon owes its charge,
--       never a wait) and `out_min` (minutes out at work inside the window, for reading). Without an outflow block the
--       result is 0621's, key for key (V1).
--   (e) The comparison weighs it. `ottoq_charge_line_compare`: when both sides carry `flow2_sum`, the third test is it
--       (d_flow is then its difference; d_flow1 and d_out are added). On time and lateness still come first (rule 9).
--   (f) Hindsight keeps up. `ottoq_charge_order_realized` reads, for a state with an outflow block, when each modelled
--       car left and came back inside the window (`returns`), and no longer counts those cars as appeared;
--       `ottoq_charge_line_realize` puts them in for the `appeared` part (the part is now "the outflow and the unseen").
--       `ottoq_charge_order_forecast_errors(state, real, expected)` grades the outflow forecast against them (returns
--       modelled and real, hits, timing; departures; the unseen), and `ottoq_charge_order_grade` passes it the expected
--       future of the order that ran. A state without an outflow block reads and grades as before (V1).
--   (g) A person's dial, catalogued, not agent-writable: `agent_charge_order_outflow` (1; 0 is 0622's check).
--
--   The tick path is untouched. The check, the grader and the board run only on runs that take an agent's charge
--   order (0615); the dwell fit writes one row a night.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: every body replaced or relied on is the one this file was written against (md5);
--   nothing this file creates exists. Nothing here drops or deletes anything.
--   V1: on the 40 latest stored snapshots (none carries an outflow block), in the expected future and a sampled one, the
--   schedule and the comparison return what they returned before this file, key for key; and ten graded orders read as
--   they were graded.
--   V2: THE GATE. On run d9d49732's graded orders, each stored state given the outflow as of its clock (the dwell fitted
--   through the run's start, so out of sample), against the session and dispatch ledgers. Of the cars that left inside
--   the window, the share whose dwell fell under the curve's median for its stretch (from how long the car had already
--   been parked to the cut) must be 40-60%, and under its 80th percentile 70-90%; a car still parked at the cut never
--   enters that test, so the cut cannot tilt it. (The test's first form counted such a car wherever the cut settled
--   it, which tilted both shares up: 0.605 and 0.961 on the same orders, a measurement fault, not the curve's.) The
--   departures the curve expects inside the window must be 0.75-1.33 times the real ones, and so must the returns the
--   expected future of the order that ran puts inside the window; or nothing here is applied. Reported beside it: each
--   car's chance of leaving scored (Brier) against the run's base rate, the returns car by car (which car is a draw, so
--   not gated) and their timing. The check's verdicts against hindsight, before and after, are db/checks/0417's.
--   V3: the first fit at apply carries a dwell; the state on a running twin run carries the outflow.
--   tests/test_agent_outflow_sql.py executes the rest on the miniature depot.
--
-- ══ §4 RECERT ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   FALSE/FALSE. The check, its grader and the board run only on operator_demo runs that take an agent's charge order
--   (0615); no certification, sweep or dial pair arms an order. Without an outflow block every reader returns what it
--   returned (V1); the new estimate keys are evidence.
--
-- ROLLBACK: set agent_charge_order_outflow to 0 on the runs that should not see it (0622's check, exactly), or EXECUTE
--   each `definition` in ottoq_schema_snapshots WHERE label = '0623_pre' (the state, schedule, comparison, realize,
--   realized reader, grade, hindsight md5 and return fit as 0622 left them). DROP FUNCTION
--   public.ottoq_charge_order_forecast_errors(jsonb, jsonb, jsonb), public.ottoq_charge_line_outflow(uuid, uuid,
--   timestamptz, jsonb, jsonb, jsonb, jsonb), public.ottoq_charge_line_return_draw(double precision[],
--   double precision[], double precision[], double precision, double precision, double precision, integer, text, text,
--   double precision, double precision, double precision, jsonb, double precision),
--   public.ottoq_outflow_dwell_quantile(double precision[], double precision, double precision, double precision),
--   public.ottoq_outflow_dwell_cdf(double precision[], double precision, double precision, double precision),
--   public.ottoq_return_model_params(uuid, timestamptz, interval), public.ottoq_normal_quantile(double precision),
--   public.ottoq_hash_uniform(text);
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_outflow';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0623_the_check_sees_cars_leave_and_come_back'. The return_v1
--   rows written since keep their dwell key; nothing else reads it.

BEGIN;

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0623 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', '059a6ce2', 'the schedule (0621)'),
      ('public.ottoq_charge_line_simulate(jsonb,jsonb,integer,text)', '265735b2', 'the simulator (0621)'),
      ('public.ottoq_charge_line_compare(jsonb,jsonb)', '4be5001b', 'the comparison (0620)'),
      ('public.ottoq_charge_line_rollout(jsonb,jsonb,integer,text)', '0fed8ccd', 'the rollout (0620)'),
      ('public.ottoq_charge_line_realize(jsonb,jsonb,text[])', '39dee936', 'the realizer (0621)'),
      ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', '60d98d58', 'the state (0622)'),
      ('public.ottoq_charge_order_realized(bigint,numeric)', '630faabf', 'the realized reader (0622)'),
      ('public.ottoq_charge_order_grade(bigint,numeric)', '65023ab7', 'the grade (0621)'),
      ('public.ottoq_charge_order_forecast_errors(jsonb,jsonb)', '134f7426', 'the forecast errors (0621)'),
      ('public.ottoq_hindsight_code_md5()', 'bf0ba326', 'the grader''s md5 (0621)'),
      ('public.ottoq_fit_return_model(uuid,timestamp with time zone,interval,text)', '296731c0', 'the return fit (0619)'),
      ('public.ottoq_learned_estimate(uuid,text)', 'ff910870', 'the latest fit (0619)'),
      ('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)', '03dc08a0', 'the clock (0622)'),
      ('public.ottoq_charge_clock_run_evidence(jsonb,uuid,timestamp with time zone)', '314444ef', 'the run evidence (0622)'),
      ('public.ottoq_hash_normal(text)', 'f9607267', 'the normal draw (0620)'),
      ('public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)', 'ca31180e', 'the door (0621)'),
      ('public.ottoq_charge_order_attribute(bigint)', 'c4d1ce64', 'the attribution (0621)'))
    AS x(sig, md5, what)
  LOOP
    IF left((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)), 8) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0623 P1: % is not the body this file was written against (md5 %); read it again', r.what, r.md5;
    END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_hash_uniform(text)') IS NOT NULL
     OR to_regprocedure('public.ottoq_normal_quantile(double precision)') IS NOT NULL
     OR to_regprocedure('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)') IS NOT NULL
     OR to_regprocedure('public.ottoq_charge_order_forecast_errors(jsonb,jsonb,jsonb)') IS NOT NULL
     OR to_regprocedure('public.ottoq_charge_line_outflow(uuid,uuid,timestamp with time zone,jsonb,jsonb,jsonb,jsonb)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_outflow') THEN
    RAISE EXCEPTION '0623 P1: something this file creates already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0623_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure,
                 'public.ottoq_charge_line_compare(jsonb,jsonb)'::regprocedure,
                 'public.ottoq_charge_line_realize(jsonb,jsonb,text[])'::regprocedure,
                 'public.ottoq_charge_order_realized(bigint,numeric)'::regprocedure,
                 'public.ottoq_charge_order_grade(bigint,numeric)'::regprocedure,
                 'public.ottoq_hindsight_code_md5()'::regprocedure,
                 'public.ottoq_fit_return_model(uuid,timestamp with time zone,interval,text)'::regprocedure);

-- V1's "before": the 40 latest stored snapshots' simulations and comparisons (the expected future and a sampled one), as
-- 0622 leaves them
CREATE TEMP TABLE v0623_before ON COMMIT DROP AS
SELECT s.order_id, sc.sc,
       public.ottoq_charge_line_schedule(s.state, NULL, sc.sc, s.seed, true) AS k,
       public.ottoq_charge_line_schedule(s.state, s.agent_order, sc.sc, s.seed, true) AS a,
       public.ottoq_charge_line_compare(public.ottoq_charge_line_simulate(s.state, NULL, sc.sc, s.seed),
                                        public.ottoq_charge_line_simulate(s.state, s.agent_order, sc.sc, s.seed)) AS c
  FROM (SELECT * FROM public.ottoq_charge_order_snapshots ORDER BY order_id DESC LIMIT 40) s
 CROSS JOIN (VALUES (0), (3)) sc(sc);

-- ══ (g) the dial ══════════════════════════════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, agent_writable, affects, description)
VALUES ('agent_charge_order_outflow', 0, 1, 1, false, 'ottoq_charge_line_state (0623 outflow)',
  '0623: whether the kernel''s check on an agent''s charge order sees the depot''s own outflow: cars that leave after '
  'their charge, work down to the reserve and come back owing a charge, each car compared over its visit now and its '
  'next. 1 sees it; 0 is 0622''s check exactly. A person''s dial, never the agent''s (rule 10).');

-- ══ (b) the draws ═════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_hash_uniform(p_key text)
RETURNS double precision
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0623: a uniform draw in (0, 1) that is a pure function of p_key: the first 32 bits of md5(p_key), as 0620's
  -- ottoq_hash_normal reads them. No sequence, no clock, no session state.
  SELECT ((('x' || substr(md5(p_key), 1, 8))::bit(32)::bigint)::float8 + 0.5) / 4294967296.0
$fn$;

CREATE FUNCTION public.ottoq_normal_quantile(p_p double precision)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
/* 0623: the standard normal's quantile at p_p (NULL outside (0, 1)): Acklam's rational approximation, relative error
   under 1.2e-9 across (0, 1). Pure. The expected future uses it to spread the cars' drains evenly over the learned
   spread, as it spreads their dwells and calls home. */
DECLARE
  q float8; r float8; v_lo constant float8 := 0.02425;
BEGIN
  IF p_p IS NULL OR p_p <= 0 OR p_p >= 1 THEN RETURN NULL; END IF;
  IF p_p < v_lo THEN
    q := sqrt(-2 * ln(p_p));
    RETURN (((((-7.784894002430293e-03 * q - 3.223964580411365e-01) * q - 2.400758277161838e+00) * q
              - 2.549732539343734e+00) * q + 4.374664141464968e+00) * q + 2.938163982698783e+00)
           / ((((7.784695709041462e-03 * q + 3.224671290700398e-01) * q + 2.445134137142996e+00) * q
              + 3.754408661907416e+00) * q + 1);
  ELSIF p_p <= 1 - v_lo THEN
    q := p_p - 0.5; r := q * q;
    RETURN (((((-3.969683028665376e+01 * r + 2.209460984245205e+02) * r - 2.759285104469687e+02) * r
              + 1.383577518672690e+02) * r - 3.066479806614716e+01) * r + 2.506628277459239e+00) * q
           / (((((-5.447609879822406e+01 * r + 1.615858368580409e+02) * r - 1.556989798598866e+02) * r
              + 6.680131188771972e+01) * r - 1.328068155288572e+01) * r + 1);
  ELSE
    q := sqrt(-2 * ln(1 - p_p));
    RETURN -(((((-7.784894002430293e-03 * q - 3.223964580411365e-01) * q - 2.400758277161838e+00) * q
               - 2.549732539343734e+00) * q + 4.374664141464968e+00) * q + 2.938163982698783e+00)
           / ((((7.784695709041462e-03 * q + 3.224671290700398e-01) * q + 2.445134137142996e+00) * q
              + 3.754408661907416e+00) * q + 1);
  END IF;
END $fn$;

CREATE FUNCTION public.ottoq_outflow_dwell_quantile(p_q double precision[], p_fmax double precision,
                                                    p_max double precision, p_u double precision)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
/* 0623: the minutes a charged car stays, at probability p_u, off the dwell's grid (p_q[k] at (k - 1) / 20, then p_max
   at p_fmax), linearly between points. NULL at or past p_fmax: the car stays past every departure the evidence saw. */
DECLARE
  k int; v_u float8 := GREATEST(COALESCE(p_u, 0), 0); v_lo float8; v_hi float8; v_ulo float8; v_uhi float8;
BEGIN
  IF p_q IS NULL OR COALESCE(array_length(p_q, 1), 0) = 0 OR p_fmax IS NULL OR v_u >= p_fmax THEN
    RETURN NULL;
  END IF;
  k := LEAST(floor(v_u * 20)::int + 1, array_length(p_q, 1));
  WHILE k > 1 AND p_q[k] IS NULL LOOP k := k - 1; END LOOP;
  v_lo := p_q[k];
  v_ulo := (k - 1) / 20.0;
  IF v_lo IS NULL THEN RETURN NULL; END IF;
  IF k < array_length(p_q, 1) AND p_q[k + 1] IS NOT NULL AND k / 20.0 <= p_fmax THEN
    v_hi := p_q[k + 1]; v_uhi := k / 20.0;
  ELSE
    v_hi := p_max; v_uhi := p_fmax;
  END IF;
  IF v_hi IS NULL OR v_uhi <= v_ulo OR v_hi < v_lo THEN RETURN v_lo; END IF;
  RETURN v_lo + (v_hi - v_lo) * (v_u - v_ulo) / (v_uhi - v_ulo);
END $fn$;

CREATE FUNCTION public.ottoq_outflow_dwell_cdf(p_q double precision[], p_fmax double precision, p_max double precision,
                                               p_min double precision)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
/* 0623: the share of charged cars gone by p_min minutes after their charge ended: the inverse of
   ottoq_outflow_dwell_quantile on the same grid; p_fmax at and past p_max, the last departure the evidence saw. */
DECLARE
  k int; v_n int := COALESCE(array_length(p_q, 1), 0); v_t float8 := GREATEST(COALESCE(p_min, 0), 0); v_last int := 1;
BEGIN
  IF v_n = 0 OR p_fmax IS NULL OR p_fmax <= 0 OR p_q[1] IS NULL OR v_t <= p_q[1] THEN RETURN 0; END IF;
  FOR k IN 2 .. v_n LOOP
    EXIT WHEN p_q[k] IS NULL OR (k - 1) / 20.0 > p_fmax;
    IF v_t < p_q[k] THEN
      RETURN (k - 2) / 20.0 + (v_t - p_q[k - 1]) / (p_q[k] - p_q[k - 1]) / 20.0;
    END IF;
    v_last := k;
  END LOOP;
  IF p_max IS NOT NULL AND v_t < p_max AND p_max > p_q[v_last] THEN
    RETURN (v_last - 1) / 20.0 + (p_fmax - (v_last - 1) / 20.0) * (v_t - p_q[v_last]) / (p_max - p_q[v_last]);
  END IF;
  RETURN p_fmax;
END $fn$;

CREATE FUNCTION public.ottoq_charge_line_return_draw(p_out double precision[], p_q double precision[],
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
   but not back was out at least that long. Pure. */
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
    v_past := v_e;
    IF v_ce IS NOT NULL AND p_cut IS NOT NULL THEN
      v_past := GREATEST(v_past, p_cut - v_ce);               -- not gone by the cut: at least that long
    END IF;
    v_u := COALESCE(p_ud, public.ottoq_hash_uniform(v_key || ':dwell'));
    v_fe := public.ottoq_outflow_dwell_cdf(p_q, v_fmax, v_max, v_past);
    v_dw := public.ottoq_outflow_dwell_quantile(p_q, v_fmax, v_max, v_fe + v_u * (1 - v_fe));
    IF v_dw IS NULL THEN RETURN NULL; END IF;                 -- parked past every departure the evidence saw
    v_dw := GREATEST(v_dw, v_past);
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

-- ══ (a) the dwell, learned with the return cycle ═════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_return_model_params(p_depot uuid, p_through timestamptz DEFAULT NULL,
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
   30 departures, else every run. */
DECLARE
  c_min_n   constant int := 30;
  v_through timestamptz := COALESCE(p_through, now());
  v_from    timestamptz := COALESCE(p_through, now()) - COALESCE(p_window, interval '21 days');
  v_p       jsonb;
  v_dw      jsonb;
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

  -- the dwell: from a completed charge's end to the car's next departure in its run
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
             WHERE o2.sim_run_id = os.sim_run_id AND o2.vehicle_id = os.vehicle_id AND o2.started_at > os.ended_at) AS next_charge
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
           (s.next_out IS NOT NULL AND (s.next_charge IS NULL OR s.next_out <= s.next_charge)) AS ev
      FROM s, pop WHERE s.fine OR NOT pop.use_fine
  ), g AS (
    SELECT o.t, count(*) FILTER (WHERE o.ev) AS d, count(*) AS m FROM o GROUP BY o.t
  ), rk AS (
    SELECT g.t, g.d, sum(g.m) OVER (ORDER BY g.t DESC) AS at_risk FROM g
  ), km AS (
    SELECT rk.t, rk.d, 1 - exp(sum(ln(GREATEST(1 - rk.d::float8 / rk.at_risk, 1e-12))) OVER (ORDER BY rk.t)) AS f FROM rk
  ), lim AS (
    SELECT max(km.f) AS fmax, max(km.t) FILTER (WHERE km.d > 0) AS tmax FROM km
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
           'population', CASE WHEN (SELECT use_fine FROM pop) THEN 'fine_ticks' ELSE 'all_ticks' END)
    INTO v_dw
    FROM lim;

  RETURN v_p || jsonb_build_object('dwell', v_dw);
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_fit_return_model(p_depot uuid, p_through timestamptz DEFAULT NULL,
                                                         p_window interval DEFAULT interval '21 days', p_note text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
/* 0619: fit return_v1 for a depot and write one row. 0623: the parameters are ottoq_return_model_params (0619's, key for
   key, and the dwell after a charge); the row, its counts and its usability test are 0619's. */
DECLARE
  c_min_n   constant int := 30;
  v_through timestamptz := COALESCE(p_through, now());
  v_from    timestamptz := COALESCE(p_through, now()) - COALESCE(p_window, interval '21 days');
  v_p       jsonb;
  v_id      bigint;
BEGIN
  IF p_depot IS NULL THEN RAISE EXCEPTION 'ottoq_fit_return_model: a depot is required'; END IF;
  v_p := public.ottoq_return_model_params(p_depot, v_through, COALESCE(p_window, interval '21 days'));
  INSERT INTO public.ottoq_learned_estimates
    (depot_id, model, evidence_from, evidence_through, n_evidence, n_runs, usable, params, code_md5, note)
  VALUES (p_depot, 'return_v1', v_from, v_through, COALESCE((v_p ->> 'n_returns')::int, 0), COALESCE((v_p ->> 'n_runs')::int, 0),
          COALESCE((v_p ->> 'n_low_soc')::int, 0) >= c_min_n AND (v_p ->> 'drain_pct_per_min') IS NOT NULL
            AND (v_p ->> 'threshold_soc') IS NOT NULL AND (v_p ->> 'trip_min') IS NOT NULL,
          (v_p - 'n_runs') || jsonb_build_object('min_n', c_min_n),
          md5(pg_get_functiondef('public.ottoq_fit_return_model(uuid,timestamptz,interval,text)'::regprocedure)
              || pg_get_functiondef('public.ottoq_return_model_params(uuid,timestamptz,interval)'::regprocedure)),
          p_note)
  RETURNING estimate_id INTO v_id;
  RETURN v_id;
END $fn$;

-- ══ (c) the outflow a state carries ═══════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_line_outflow(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz, p_state jsonb,
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
   stored order's state reads as the live one did. Read-only. */
DECLARE
  v_thr numeric := (p_rt #>> '{params,threshold_soc}')::numeric;
  v_drain numeric := (p_rt #>> '{params,drain_pct_per_min}')::numeric;
  v_trip numeric := COALESCE((p_rt #>> '{params,trip_min}')::numeric, 0);
  v_dw jsonb := p_rt #> '{params,dwell}';
  v_kw_d numeric; v_kw_l numeric;
  v_ids text[]; v_ch jsonb; v_leave jsonb; v_ret jsonb;
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

  RETURN p_state || jsonb_build_object(
    'chargers', v_ch,
    'outflow', jsonb_build_object(
      'v', 1, 'return_model', p_rt -> 'estimate_id', 'window_min', 90,
      'thr', v_thr, 'drain', v_drain, 'dsd', COALESCE((p_rt #>> '{params,drain_log_sd}')::numeric, 0), 'trip', v_trip,
      'lam', round(COALESCE((p_rt #>> '{params,other_per_work_hour}')::numeric, 0) / 60.0, 6),
      'dwell', jsonb_build_object('q', v_dw -> 'q', 'f_max', v_dw -> 'f_max', 'max_min', v_dw -> 'max_min',
                                  'median_min', v_dw -> 'median_min'),
      'ret', v_ret, 'leaving', v_leave));
END $fn$;

-- ══ (c) the state: 0622's, with the outflow when the run's dial says so ═══════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_charge_line_state(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0620: everything a charge-line rollout reads, once: the line (less a car holding a reserved charger, already
   assigned), the cars coming home within 180 minutes, the chargers (0618's gates), the order's life in minutes and the
   pin, every charge timed and spread by 0619's charge_time_v1. 0622: every charge is timed by the depot's charge clock
   (ottoq_charge_clock on ottoq_charge_clock_model: its charge_time_v2 when it has one, with this run's charges up to
   p_clock), a charge under way by what is left of it (ottoq_charge_clock_remaining); each car carries its class (cls) and
   the levels its clock used (lv). 0623: with the run's agent_charge_order_outflow dial at 1 (its default), the depot's
   outflow (ottoq_charge_line_outflow): the cars that leave and come back. Read-only. */
DECLARE
  c_horizon constant numeric := 480;
  c_window  constant numeric := 180;
  v_ct jsonb := public.ottoq_charge_clock_model(p_depot_id);
  v_rt jsonb := public.ottoq_learned_estimate(p_depot_id, 'return_v1');
  v_ev jsonb;
  v_kw_d numeric; v_kw_l numeric; v_tick numeric; v_ttl numeric; v_pin numeric;
  v_cars jsonb; v_inb jsonb; v_ch jsonb; v_state jsonb;
BEGIN
  v_ev := public.ottoq_charge_clock_run_evidence(v_ct, p_sim_run_id, p_clock);
  SELECT max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'dcfc'),
         max(s.connector_max_kw) FILTER (WHERE s.stall_type::text = 'l2')
    INTO v_kw_d, v_kw_l
    FROM stalls s WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc', 'l2');
  SELECT CASE WHEN r.tick_count > 0 AND r.sim_clock_start IS NOT NULL AND r.sim_clock_current > r.sim_clock_start
              THEN extract(epoch FROM (r.sim_clock_current - r.sim_clock_start)) / 60.0 / r.tick_count END
    INTO v_tick FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  v_tick := COALESCE(v_tick, 0.25);
  v_ttl := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_ttl_ticks', 15), 15) * v_tick;
  v_pin := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_pin_wait_min', 90), 90);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', x.id, 'w', round(x.wait_min, 2), 'g', round(x.gap, 2), 'imm', x.immediate, 'soc', x.soc,
           'due', x.due, 'dok', x.dok, 'lok', x.lok, 'md', (x.cd ->> 'm')::numeric, 'ml', (x.cl ->> 'm')::numeric,
           'sd', (x.cd ->> 'sd')::numeric, 'sl', (x.cl ->> 'sd')::numeric, 'cls', x.who ->> 'cls', 'lv', x.cd ->> 'lvl')
           ORDER BY x.kernel_pos), '[]'::jsonb)
    INTO v_cars
    FROM (SELECT k.vehicle_id AS id, k.kernel_pos, k.wait_min, k.gap, k.immediate, k.soc, wh.who,
                 round(extract(epoch FROM (vn.dispatch_due_at - p_clock)) / 60.0, 2) AS due,
                 public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'dcfc') AS dok,
                 public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2') AS lok,
                 public.ottoq_charge_clock(v_ct, 'dcfc', wh.who, v.battery_capacity_kwh, k.soc, tg.t, v_kw_d, v.inlet_max_kw,
                                           v_ev -> 'dcfc') AS cd,
                 public.ottoq_charge_clock(v_ct, 'l2', wh.who, v.battery_capacity_kwh, k.soc, tg.t, v_kw_l, v.inlet_max_kw,
                                           v_ev -> 'l2') AS cl
            FROM public.ottoq_charge_queue_kernel_order(p_sim_run_id, p_depot_id, p_clock) k
            JOIN vehicles v ON v.id = k.vehicle_id
            CROSS JOIN LATERAL (SELECT public.ottoq_effective_target_soc_at(v.id, p_clock) AS t) tg
            CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who) wh
            LEFT JOIN LATERAL (SELECT vn.dispatch_due_at FROM ottoq_visit_needs vn
                                WHERE vn.vehicle_id = v.id AND vn.status IN ('open', 'in_progress')
                                  AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                                    = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                                ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) vn ON true
           WHERE NOT k.holds_charger) x
   WHERE (x.cd ->> 'm') IS NOT NULL AND (x.cl ->> 'm') IS NOT NULL;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', i.vehicle_id, 'eta', i.eta_min, 'src', i.source, 'esd', i.eta_log_sd, 'trip', i.trip_min,
           'soc', i.soc_at_arrival, 'g', round(GREATEST(tg.t - i.soc_at_arrival, 1), 2), 'imm', false, 'w', 0,
           'dok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'dcfc'),
           'lok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2'),
           'md', (ck.cd ->> 'm')::numeric, 'ml', (ck.cl ->> 'm')::numeric,
           'sd', (ck.cd ->> 'sd')::numeric, 'sl', (ck.cl ->> 'sd')::numeric, 'cls', wh.who ->> 'cls', 'lv', ck.cd ->> 'lvl')
           ORDER BY i.eta_min, i.vehicle_id), '[]'::jsonb)
    INTO v_inb
    FROM public.ottoq_charge_line_inbound(p_sim_run_id, p_depot_id, p_clock, c_window, v_rt) i
    JOIN vehicles v ON v.id = i.vehicle_id
    CROSS JOIN LATERAL (SELECT public.ottoq_effective_target_soc_at(v.id, p_clock) AS t) tg
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who) wh
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(v_ct, 'dcfc', wh.who, v.battery_capacity_kwh, i.soc_at_arrival, tg.t,
                                                         v_kw_d, v.inlet_max_kw, v_ev -> 'dcfc') AS cd,
                               public.ottoq_charge_clock(v_ct, 'l2', wh.who, v.battery_capacity_kwh, i.soc_at_arrival, tg.t,
                                                         v_kw_l, v.inlet_max_kw, v_ev -> 'l2') AS cl) ck
   WHERE i.soc_at_arrival < tg.t - 1 AND v.battery_capacity_kwh IS NOT NULL;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', y.id, 'k', y.kind, 'free', y.free_at, 'sd', y.sd)
                            ORDER BY y.kind, y.free_at, y.id), '[]'::jsonb)
    INTO v_ch
    FROM (
      SELECT s.id, s.stall_type::text AS kind,
             CASE WHEN s.current_vehicle_id IS NULL THEN 0::numeric ELSE (rm.c ->> 'm')::numeric END AS free_at,
             CASE WHEN s.current_vehicle_id IS NULL THEN 0::numeric ELSE (rm.c ->> 'sd')::numeric END AS sd
        FROM stalls s
        JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
        LEFT JOIN vehicles cv ON cv.id = s.current_vehicle_id
        LEFT JOIN LATERAL (SELECT os.soc_start, os.started_at FROM ocpp_sessions os
                            WHERE os.stall_id = s.id AND os.status = 'active' AND os.vehicle_id = cv.id
                            ORDER BY os.started_at DESC LIMIT 1) ses ON cv.id IS NOT NULL
        LEFT JOIN LATERAL (SELECT public.ottoq_charge_clock_remaining(
                                    v_ct, s.stall_type::text,
                                    public.ottoq_charge_clock_who(cv.id, cv.vehicle_class_code, cv.make, cv.model),
                                    cv.battery_capacity_kwh, ses.soc_start, cv.current_soc,
                                    public.ottoq_effective_target_soc_at(cv.id, p_clock), s.connector_max_kw, cv.inlet_max_kw,
                                    extract(epoch FROM (p_clock - ses.started_at)) / 60.0,
                                    v_ev -> s.stall_type::text) AS c) rm ON cv.id IS NOT NULL
       WHERE s.depot_id = p_depot_id AND s.stall_type::text IN ('dcfc', 'l2')
         AND c.station_state IS DISTINCT FROM 'Faulted'
         AND (   (s.current_vehicle_id IS NULL
                  AND NOT (s.reserved_by IS NOT NULL AND COALESCE(s.reservation_expires_at, 'infinity'::timestamptz) > p_clock)
                  AND c.station_state = 'Available' AND c.last_heartbeat_at >= p_clock - interval '90 seconds'
                  AND NOT EXISTS (SELECT 1 FROM ottoq_stall_bookings b
                                   WHERE b.sim_run_id = p_sim_run_id AND b.stall_id = s.id
                                     AND b.state IN ('held', 'active', 'done', 'interrupted') AND b.during @> p_clock))
              OR cv.current_state::text IN ('charging_dcfc', 'charging_l2'))) y
   WHERE y.free_at IS NOT NULL;

  v_state := jsonb_build_object(
    'v', 1, 'clock', p_clock, 'tick_min', round(v_tick, 4), 'ttl_min', round(v_ttl, 3), 'pin_min', v_pin,
    'horizon_min', c_horizon, 'arrival_window_min', c_window,
    'models', jsonb_build_object('charge_time', v_ct -> 'estimate_id', 'charge_time_model', v_ct ->> 'model',
                                 'return', v_rt -> 'estimate_id',
                                 'return_usable', COALESCE((v_rt ->> 'usable')::boolean, false),
                                 'run_evidence', (SELECT jsonb_object_agg(e.key, e.value -> 'n') FROM jsonb_each(COALESCE(v_ev, '{}'::jsonb)) e)),
    'cars', v_cars, 'inbound', v_inb, 'chargers', v_ch);
  -- 0623: the outflow, unless a person has turned it off for this run
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_outflow', 1), 1) >= 1 THEN
    v_state := public.ottoq_charge_line_outflow(p_sim_run_id, p_depot_id, p_clock, v_state, v_ct, v_rt, v_ev);
  END IF;
  RETURN v_state;
END $fn$;

-- ══ (d) the simulator: 0621's schedule, with cars that leave and come back ════════════════════════════════════════════
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
   key for key. */
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
    SELECT COALESCE(jsonb_object_agg(r.id, r.rk), '{}'::jsonb) INTO o_idr
      FROM (SELECT u.id, rank() OVER (ORDER BY u.id) AS rk
              FROM (SELECT DISTINCT y.id FROM (SELECT unnest(c_id) AS id
                                               UNION ALL SELECT jsonb_object_keys(o_ret)) y) u) r;
    FOR i IN 1 .. n LOOP c_idr[i] := (o_idr ->> c_id[i])::int; END LOOP;
    -- the expected future's draws, stratified across the cars it models: each car's dwell, call home and drain at its
    -- own probability, evenly spaced over (0, 1) in the order of a hash of the car (the same on both sides of a
    -- comparison), so that together they cover the curves as the cars' futures would; a sampled future draws each by
    -- its own hash
    IF COALESCE(p_scenario, 0) = 0 THEN
      SELECT COALESCE(jsonb_object_agg(u.id, jsonb_build_array(
               (u.rd - 0.5) / u.n, (u.ro - 0.5) / u.n, public.ottoq_normal_quantile((u.rz - 0.5) / u.n))), '{}'::jsonb)
        INTO o_u
        FROM (SELECT k.id, count(*) OVER () AS n,
                     row_number() OVER (ORDER BY md5(COALESCE(p_seed, '') || ':' || k.id || ':dwell'), k.id) AS rd,
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
      v_rr := public.ottoq_charge_line_return_draw(
                o_p, o_q,
                ARRAY[(v_r ->> 'tg')::float8, (v_r ->> 'rs')::float8, (v_r ->> 'rmd')::float8, (v_r ->> 'rml')::float8,
                      (v_r ->> 'rsd')::float8, (v_r ->> 'rsl')::float8],
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
                 'r', round(c_ready[z.i]::numeric, 2), 'k', c_kind[z.i], 'past', c_vk[z.i] = 2) ORDER BY z.i)
          FROM generate_series(n0 + 1, GREATEST(n, n0)) AS z(i) WHERE z.i > n0 AND NOT c_void[z.i]), '[]'::jsonb));
    END IF;
  END IF;
  RETURN v_out;
END $fn$;

COMMENT ON FUNCTION public.ottoq_charge_line_schedule(jsonb, jsonb, integer, text, boolean) IS
'0621. The charge line as a list schedule (0620''s simulator): with p_trace, every car''s first seat, last kind and ready time; a charger carrying dn [[from, until], ...] goes down and back, its car re-queued to finish (rule 9). 0623: with an outflow block, cars leave after their charge and come back owing one (each car over its visit now and its next): returns, stays, flow2_sum and out_min, and with p_trace the returns. Pure.';

-- ══ (e) the comparison ════════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_charge_line_compare(p_kernel jsonb, p_agent jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0620: is the agent's side better (+1), worse (-1) or no different (0)? The owner's requirement first (rule 9): cars
  -- ready by their due time; then summed lateness (half a minute of rounding); then summed minutes in the depot (one).
  -- 0623: when both sides carry the outflow (flow2_sum), the minutes in the depot are each car's over its visit now and
  -- its next, so a car out sooner counts as a gain; d_flow is then that difference, with d_flow1 (the visits now alone)
  -- and d_out (minutes out at work inside the window) beside it. Without it, 0620's comparison exactly.
  SELECT jsonb_build_object('cmp', x.cmp, 'by', x.by, 'd_on_time', x.dot, 'd_late', x.dl, 'd_flow', x.df)
         || CASE WHEN x.two THEN jsonb_build_object('d_flow1', x.df1, 'd_out', x.dout) ELSE '{}'::jsonb END
    FROM (SELECT CASE WHEN s.ao > s.ko THEN 1 WHEN s.ao < s.ko THEN -1
                      WHEN s.al < s.kl - 0.5 THEN 1 WHEN s.al > s.kl + 0.5 THEN -1
                      WHEN s.af < s.kf - 1.0 THEN 1 WHEN s.af > s.kf + 1.0 THEN -1 ELSE 0 END AS cmp,
                 CASE WHEN s.ao <> s.ko THEN 'on_time' WHEN abs(s.al - s.kl) > 0.5 THEN 'lateness'
                      WHEN abs(s.af - s.kf) > 1.0 THEN 'flow' ELSE 'tie' END AS by,
                 s.ao - s.ko AS dot, round(s.al - s.kl, 2) AS dl, round(s.af - s.kf, 2) AS df,
                 s.two, round(s.af1 - s.kf1, 2) AS df1, round(s.aout - s.kout, 2) AS dout
            FROM (SELECT COALESCE((p_kernel ->> 'on_time')::int, 0) AS ko, COALESCE((p_agent ->> 'on_time')::int, 0) AS ao,
                         COALESCE((p_kernel ->> 'late_sum')::numeric, 0) AS kl, COALESCE((p_agent ->> 'late_sum')::numeric, 0) AS al,
                         y.two,
                         CASE WHEN y.two THEN (p_kernel ->> 'flow2_sum')::numeric
                              ELSE COALESCE((p_kernel ->> 'flow_sum')::numeric, 0) END AS kf,
                         CASE WHEN y.two THEN (p_agent ->> 'flow2_sum')::numeric
                              ELSE COALESCE((p_agent ->> 'flow_sum')::numeric, 0) END AS af,
                         COALESCE((p_kernel ->> 'flow_sum')::numeric, 0) AS kf1, COALESCE((p_agent ->> 'flow_sum')::numeric, 0) AS af1,
                         COALESCE((p_kernel ->> 'out_min')::numeric, 0) AS kout, COALESCE((p_agent ->> 'out_min')::numeric, 0) AS aout
                    FROM (SELECT (jsonb_typeof(p_kernel -> 'flow2_sum') = 'number'
                                  AND jsonb_typeof(p_agent -> 'flow2_sum') = 'number') AS two) y) s) x
$fn$;

-- ══ (f) hindsight: the realizer puts the outflow in ═════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_charge_line_realize(p_state jsonb, p_real jsonb, p_parts text[])
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
/* 0621: p_state (ottoq_charge_line_state, as the check read it) with the named parts of what happened (p_real, from
   ottoq_charge_order_realized) in place of what the check expected. arrivals: when each car the check saw coming home
   arrived, with its battery, its minutes at that battery on the check's own clock, and its due time; appeared: the cars
   the check did not see that joined the line, when they did; charge_times: each charge's real minutes on the kind it
   took; running: when each charge under way at the order ended; faults: each charger's down windows, and the chargers
   back from a repair. Every other number is the check's. Pure.
   0623: on a state with an outflow block, appeared is the outflow and the unseen: each modelled car's dwell and time out
   as they happened (p_real.returns, kept as durations, so each side keeps its own timing; ottoq_charge_line_return_draw),
   and the cars nobody modelled that joined the line. */
DECLARE
  v_a boolean := 'arrivals' = ANY (COALESCE(p_parts, '{}'::text[]));
  v_u boolean := 'appeared' = ANY (COALESCE(p_parts, '{}'::text[]));
  v_d boolean := 'charge_times' = ANY (COALESCE(p_parts, '{}'::text[]));
  v_r boolean := 'running' = ANY (COALESCE(p_parts, '{}'::text[]));
  v_f boolean := 'faults' = ANY (COALESCE(p_parts, '{}'::text[]));
  v_cars jsonb := '[]'::jsonb; v_inb jsonb := '[]'::jsonb; v_ch jsonb := '[]'::jsonb; e jsonb; r jsonb;
  v_out jsonb;
BEGIN
  IF p_real IS NULL OR NOT (v_a OR v_u OR v_d OR v_r OR v_f) THEN
    RETURN p_state;
  END IF;
  FOR e IN SELECT x.value FROM jsonb_array_elements(COALESCE(p_state -> 'cars', '[]'::jsonb)) WITH ORDINALITY x(value, o)
            ORDER BY x.o
  LOOP
    IF v_d THEN e := public.ottoq_charge_line_real_minutes(e, p_real #> ARRAY['cars', e ->> 'id']); END IF;
    v_cars := v_cars || jsonb_build_array(e);
  END LOOP;
  FOR e IN SELECT x.value FROM jsonb_array_elements(COALESCE(p_state -> 'inbound', '[]'::jsonb)) WITH ORDINALITY x(value, o)
            ORDER BY x.o
  LOOP
    r := p_real #> ARRAY['inbound', e ->> 'id'];
    IF v_a AND r IS NOT NULL THEN
      e := e || jsonb_strip_nulls(jsonb_build_object('eta', r -> 'eta', 'soc', r -> 'soc', 'g', r -> 'g', 'md', r -> 'md',
                                                     'ml', r -> 'ml', 'sd', r -> 'sd', 'sl', r -> 'sl', 'due', r -> 'due',
                                                     'imm', r -> 'imm'));
      IF COALESCE((r ->> 'arrived')::boolean, false) THEN
        e := e || jsonb_build_object('src', 'arrived', 'esd', 0);
      END IF;
    END IF;
    IF v_d THEN e := public.ottoq_charge_line_real_minutes(e, r); END IF;
    v_inb := v_inb || jsonb_build_array(e);
  END LOOP;
  IF v_u THEN
    FOR e IN SELECT x.value FROM jsonb_array_elements(COALESCE(p_real -> 'appeared', '[]'::jsonb)) WITH ORDINALITY x(value, o)
              ORDER BY x.o
    LOOP
      IF v_d THEN e := public.ottoq_charge_line_real_minutes(e, e); END IF;
      v_inb := v_inb || jsonb_build_array(e - ARRAY['s0', 'k0', 'm', 'cen', 'end', 'how']);
    END LOOP;
  END IF;
  FOR e IN SELECT x.value FROM jsonb_array_elements(COALESCE(p_state -> 'chargers', '[]'::jsonb)) WITH ORDINALITY x(value, o)
            ORDER BY x.o
  LOOP
    r := p_real #> ARRAY['chargers', e ->> 'id'];
    IF v_r AND jsonb_typeof(r -> 'free') = 'number' THEN e := e || jsonb_build_object('free', r -> 'free'); END IF;
    IF v_f AND jsonb_typeof(r -> 'dn') = 'array' THEN e := e || jsonb_build_object('dn', r -> 'dn'); END IF;
    v_ch := v_ch || jsonb_build_array(e);
  END LOOP;
  IF v_f THEN
    v_ch := v_ch || COALESCE(p_real -> 'back', '[]'::jsonb);
  END IF;
  -- 0623: the outflow as it happened
  IF v_u AND jsonb_typeof(p_state -> 'outflow') = 'object' THEN
    v_out := (p_state -> 'outflow') || jsonb_build_object('real', COALESCE(p_real -> 'returns', '{}'::jsonb),
                                                          'cut', COALESCE(p_real -> 'observed_min', to_jsonb(0)));
    RETURN p_state || jsonb_build_object('cars', v_cars, 'inbound', v_inb, 'chargers', v_ch, 'outflow', v_out);
  END IF;
  RETURN p_state || jsonb_build_object('cars', v_cars, 'inbound', v_inb, 'chargers', v_ch);
END $fn$;

-- ══ (f) what happened: the realized reader reads the outflow ═══════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_charge_order_realized(p_order_id bigint, p_window_min numeric DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0621: what actually happened in the p_window_min sim-minutes after a checked order (ottoq_charge_order_snapshots), from
   the run's own records, shaped as the order's state is, in minutes from the order's clock. cars / inbound: each car
   the check saw, keyed by id: its first charge after the order (s0 when, k0 on which kind, m how long, cen true when the
   charge was still running at the cut (m is then a lower bound) or ended any way but completed, end how it ended; m is
   NULL for a charge cut by a fault, which is the faults' part); and for a car the check saw coming home, when it arrived
   (eta; when it had not by the cut, no sooner than the cut), its battery, its due time and immediacy, and its minutes at
   that battery on the check's own charge clock (the snapshot's model, by id). appeared: the cars the check did not see
   that joined the line, as state entries: home inside the window owing a charge (how = returned), or in the depot at
   the order and charged on a charger the check modelled (how = at_depot, joining when it plugged in). chargers: for each
   charger the check modelled, when the charge under way at the order ended (free) and when it was down (dn: from the
   charger's faulted sessions, until the repair on the fault's event). back: the chargers the check left out that came
   back from a repair inside the window. faults: faults inside the window; unmodeled_sessions: charges inside the window
   on chargers the check left out. Read-only.
   0622: "the check's own charge clock" is ottoq_charge_clock on the snapshot's model, with the run's own charges as of the
   order (ottoq_charge_clock_run_evidence): on a 0619 snapshot, exactly what 0621 returned (V5).
   0623: on a state with an outflow block, the cars it models leaving (each busy charger's car and the parked ones) are
   no longer appeared, and returns gives, for every car the state models, when the charge before its first trip after
   the order ended (ce), when it left on that trip (left) and when it came back (eta, with its battery soc), each inside
   the window or absent. A state without one reads exactly as before (V1). */
DECLARE
  s record; v_clock timestamptz; v_status text; v_t0 timestamptz; v_cut timestamptz; v_obs numeric;
  v_model jsonb; v_kw_d numeric; v_kw_l numeric; v_ids text[]; v_ch_ids text[]; v_back_ids text[];
  v_cars jsonb; v_inb jsonb; v_app jsonb; v_ch jsonb; v_back jsonb; v_faults int; v_unmod int; v_fs jsonb; v_ev jsonb;
  v_mod text[]; v_ret jsonb;   -- 0623
BEGIN
  SELECT * INTO s FROM ottoq_charge_order_snapshots x WHERE x.order_id = p_order_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT r.sim_clock_current, r.status INTO v_clock, v_status FROM ottoq_sim_runs r WHERE r.sim_run_id = s.sim_run_id;
  v_t0 := s.sim_clock;
  v_cut := GREATEST(LEAST(v_t0 + make_interval(secs => GREATEST(COALESCE(p_window_min, 90), 1) * 60),
                          COALESCE(v_clock, v_t0)), v_t0);
  v_obs := round((extract(epoch FROM (v_cut - v_t0)) / 60.0)::numeric, 2);
  -- the snapshot's clock, by id: a charge_time_v2 fit (0622) or, on every snapshot before it, a charge_time_v1 estimate
  IF (s.state #>> '{models,charge_time}') ~ '^[0-9]+$' THEN
    IF (s.state #>> '{models,charge_time_model}') = 'charge_time_v2' THEN
      SELECT jsonb_build_object('params', f.params) INTO v_model
        FROM ottoq_charge_clock_fits f WHERE f.fit_id = (s.state #>> '{models,charge_time}')::bigint;
    ELSE
      SELECT jsonb_build_object('params', e.params) INTO v_model
        FROM ottoq_learned_estimates e WHERE e.estimate_id = (s.state #>> '{models,charge_time}')::bigint;
    END IF;
  END IF;
  v_ev := public.ottoq_charge_clock_run_evidence(v_model, s.sim_run_id, v_t0);
  SELECT max(st.connector_max_kw) FILTER (WHERE st.stall_type::text = 'dcfc'),
         max(st.connector_max_kw) FILTER (WHERE st.stall_type::text = 'l2')
    INTO v_kw_d, v_kw_l
    FROM stalls st WHERE st.depot_id = s.depot_id AND st.stall_type::text IN ('dcfc', 'l2');
  SELECT COALESCE(array_agg(x.value ->> 'id'), '{}'::text[]) INTO v_ids
    FROM (SELECT value FROM jsonb_array_elements(COALESCE(s.state -> 'cars', '[]'::jsonb))
          UNION ALL
          SELECT value FROM jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb))) x;
  SELECT COALESCE(array_agg(x.value ->> 'id'), '{}'::text[]) INTO v_ch_ids
    FROM jsonb_array_elements(COALESCE(s.state -> 'chargers', '[]'::jsonb)) x;
  -- 0623: the cars the outflow models leaving: each busy charger's car and the parked ones (none on an older state)
  SELECT COALESCE(array_agg(z.id), '{}'::text[]) INTO v_mod
    FROM (SELECT x.value ->> 'car' AS id FROM jsonb_array_elements(COALESCE(s.state -> 'chargers', '[]'::jsonb)) x
           WHERE jsonb_typeof(s.state -> 'outflow') = 'object' AND x.value ? 'car'
          UNION
          SELECT x.value ->> 'id' FROM jsonb_array_elements(COALESCE(s.state #> '{outflow,leaving}', '[]'::jsonb)) x
           WHERE jsonb_typeof(s.state -> 'outflow') = 'object') z
   WHERE z.id IS NOT NULL;

  -- the chargers the check left out that came back from a repair inside the window
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', b.id, 'k', b.kind, 'free', round(b.back::numeric, 2), 'sd', 0)
                            ORDER BY b.kind, b.back, b.id), '[]'::jsonb),
         COALESCE(array_agg(b.id), '{}'::text[])
    INTO v_back, v_back_ids
    FROM (SELECT DISTINCT ON (os.stall_id) os.stall_id::text AS id, st.stall_type::text AS kind,
                 extract(epoch FROM (COALESCE(ev.at, os.ended_at) + make_interval(secs => COALESCE(ev.rep, 0) * 60) - v_t0)) / 60.0 AS back
            FROM ocpp_sessions os
            JOIN stalls st ON st.id = os.stall_id
            LEFT JOIN LATERAL (SELECT e.sim_clock_at AS at, (e.payload ->> 'repair_minutes')::numeric AS rep
                                 FROM ottoq_events e
                                WHERE e.entity_type = 'ocpp_session' AND e.entity_id = os.id
                                  AND e.event_type = 'charge.session_faulted'
                                ORDER BY e.occurred_at DESC LIMIT 1) ev ON true
           WHERE os.sim_run_id = s.sim_run_id AND os.status::text = 'faulted' AND os.ended_at IS NOT NULL
             AND st.depot_id = s.depot_id AND st.stall_type::text IN ('dcfc', 'l2')
             AND os.stall_id::text <> ALL (v_ch_ids)
             AND COALESCE(ev.at, os.ended_at) < v_t0
           ORDER BY os.stall_id, COALESCE(ev.at, os.ended_at) DESC) b
   WHERE b.back > 0 AND b.back <= v_obs;

  -- the chargers the check modelled: when the charge under way ended, and when each was down
  SELECT COALESCE(jsonb_object_agg(c.id, jsonb_strip_nulls(jsonb_build_object(
           'free', CASE WHEN rs.stall_id IS NULL THEN NULL
                        WHEN rs.ended_at IS NOT NULL AND rs.ended_at <= v_cut
                        THEN round((extract(epoch FROM (rs.ended_at - v_t0)) / 60.0)::numeric, 2)
                        ELSE GREATEST(v_obs, c.free) END,
           'cen', CASE WHEN rs.stall_id IS NOT NULL THEN NOT (rs.ended_at IS NOT NULL AND rs.ended_at <= v_cut) END,
           'dn', dn.w)))
           FILTER (WHERE rs.stall_id IS NOT NULL OR dn.w IS NOT NULL), '{}'::jsonb)
    INTO v_ch
    FROM (SELECT x.value ->> 'id' AS id, COALESCE((x.value ->> 'free')::numeric, 0) AS free
            FROM jsonb_array_elements(COALESCE(s.state -> 'chargers', '[]'::jsonb)) x
           WHERE (x.value ->> 'id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') c
    LEFT JOIN LATERAL (SELECT os.stall_id, os.ended_at FROM ocpp_sessions os
                        WHERE c.free > 0 AND os.sim_run_id = s.sim_run_id AND os.stall_id = c.id::uuid
                          AND os.started_at < v_t0 AND (os.ended_at IS NULL OR os.ended_at > v_t0)
                        ORDER BY os.started_at DESC LIMIT 1) rs ON true
    LEFT JOIN LATERAL (SELECT jsonb_agg(jsonb_build_array(round(f.a::numeric, 2), round((f.a + f.rep)::numeric, 2))
                                        ORDER BY f.a) AS w
                         FROM (SELECT extract(epoch FROM (COALESCE(ev.at, os.ended_at) - v_t0)) / 60.0 AS a,
                                      COALESCE(ev.rep, 0) AS rep
                                 FROM ocpp_sessions os
                                 LEFT JOIN LATERAL (SELECT e.sim_clock_at AS at, (e.payload ->> 'repair_minutes')::numeric AS rep
                                                      FROM ottoq_events e
                                                     WHERE e.entity_type = 'ocpp_session' AND e.entity_id = os.id
                                                       AND e.event_type = 'charge.session_faulted'
                                                     ORDER BY e.occurred_at DESC LIMIT 1) ev ON true
                                WHERE os.sim_run_id = s.sim_run_id AND os.stall_id = c.id::uuid
                                  AND os.status::text = 'faulted' AND os.ended_at IS NOT NULL
                                  AND COALESCE(ev.at, os.ended_at) >= v_t0 AND COALESCE(ev.at, os.ended_at) < v_cut) f) dn ON true;

  SELECT count(*) INTO v_faults
    FROM ocpp_sessions os JOIN stalls st ON st.id = os.stall_id
   WHERE os.sim_run_id = s.sim_run_id AND os.status::text = 'faulted' AND os.ended_at >= v_t0 AND os.ended_at < v_cut
     AND st.depot_id = s.depot_id;
  SELECT count(*) INTO v_unmod
    FROM ocpp_sessions os JOIN stalls st ON st.id = os.stall_id
   WHERE os.sim_run_id = s.sim_run_id AND os.started_at >= v_t0 AND os.started_at < v_cut
     AND st.depot_id = s.depot_id AND st.stall_type::text IN ('dcfc', 'l2')
     AND os.stall_id::text <> ALL (v_ch_ids || v_back_ids);

  -- every car's first charge after the order, keyed by vehicle: {j: the car's record, stall, started_at, soc_start}
  SELECT COALESCE(jsonb_object_agg(f.id, jsonb_build_object(
           'j', jsonb_build_object(
                  's0', round((extract(epoch FROM (f.started_at - v_t0)) / 60.0)::numeric, 2),
                  'k0', f.kind,
                  'm', CASE WHEN f.status = 'faulted' OR COALESCE(f.stopped_reason, '') LIKE 'fault.%' THEN NULL
                            ELSE round((extract(epoch FROM (LEAST(COALESCE(f.ended_at, v_cut), v_cut) - f.started_at)) / 60.0)::numeric, 2) END,
                  'cen', NOT (f.ended_at IS NOT NULL AND f.ended_at <= v_cut AND f.stopped_reason = 'completed'),
                  'end', CASE WHEN f.ended_at IS NULL OR f.ended_at > v_cut THEN 'running'
                              ELSE COALESCE(f.stopped_reason, f.status) END),
           'stall', f.stall, 'started_at', f.started_at, 'soc_start', f.soc_start)), '{}'::jsonb)
    INTO v_fs
    FROM (SELECT DISTINCT ON (os.vehicle_id) os.vehicle_id::text AS id, os.started_at, os.ended_at, os.stopped_reason,
                 os.status::text AS status, os.stall_id::text AS stall, st.stall_type::text AS kind, os.soc_start
            FROM ocpp_sessions os JOIN stalls st ON st.id = os.stall_id
           WHERE os.sim_run_id = s.sim_run_id AND os.vehicle_id IS NOT NULL
             AND os.started_at >= v_t0 AND os.started_at < v_cut AND st.stall_type::text IN ('dcfc', 'l2')
           ORDER BY os.vehicle_id, os.started_at, os.id) f;

  SELECT COALESCE(jsonb_object_agg(c.id, COALESCE(v_fs #> ARRAY[c.id, 'j'], jsonb_build_object('s0', NULL))), '{}'::jsonb)
    INTO v_cars
    FROM (SELECT x.value ->> 'id' AS id FROM jsonb_array_elements(COALESCE(s.state -> 'cars', '[]'::jsonb)) x) c;

  SELECT COALESCE(jsonb_object_agg(i.id, q.j), '{}'::jsonb)
    INTO v_inb
    FROM (SELECT x.value AS e, x.value ->> 'id' AS id
            FROM jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) x) i
    JOIN vehicles v ON v.id::text = i.id
    LEFT JOIN LATERAL (SELECT d.actual_return_at, d.soc_at_return_pct FROM ottoq_vehicle_dispatches d
                        WHERE d.sim_run_id = s.sim_run_id AND d.vehicle_id = v.id AND d.dispatched_at <= v_t0
                        ORDER BY d.dispatched_at DESC LIMIT 1) d ON true
    CROSS JOIN LATERAL (SELECT (d.actual_return_at IS NOT NULL AND d.actual_return_at >= v_t0
                                AND d.actual_return_at <= v_cut) AS arrived) a
    CROSS JOIN LATERAL (SELECT CASE WHEN a.arrived THEN COALESCE(d.soc_at_return_pct, (i.e ->> 'soc')::numeric)
                                    ELSE (i.e ->> 'soc')::numeric END AS soc,
                               public.ottoq_effective_target_soc_at(v.id, v_t0) AS tgt) b
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who) wh
    CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(v_model, 'dcfc', wh.who, v.battery_capacity_kwh, b.soc, b.tgt, v_kw_d,
                                                         v.inlet_max_kw, v_ev -> 'dcfc') AS cd,
                               public.ottoq_charge_clock(v_model, 'l2', wh.who, v.battery_capacity_kwh, b.soc, b.tgt, v_kw_l,
                                                         v.inlet_max_kw, v_ev -> 'l2') AS cl) ck
    LEFT JOIN LATERAL (SELECT vn.dispatch_due_at, vn.urgency FROM ottoq_visit_needs vn
                        WHERE a.arrived AND vn.vehicle_id = v.id AND vn.sim_run_id = s.sim_run_id
                          AND vn.arrived_at >= d.actual_return_at - interval '2 minutes' AND vn.arrived_at <= v_cut
                        ORDER BY vn.arrived_at, vn.created_at LIMIT 1) vn ON true
    CROSS JOIN LATERAL (SELECT COALESCE(v_fs #> ARRAY[i.id, 'j'], '{}'::jsonb) || jsonb_build_object(
        'arrived', a.arrived,
        'eta', CASE WHEN a.arrived THEN round((extract(epoch FROM (d.actual_return_at - v_t0)) / 60.0)::numeric, 2)
                    ELSE round(GREATEST(COALESCE((i.e ->> 'eta')::numeric, 0), v_obs), 2) END,
        'soc', round(b.soc, 1),
        'g', round(GREATEST(b.tgt - b.soc, 1), 2),
        'md', (ck.cd ->> 'm')::numeric,
        'ml', (ck.cl ->> 'm')::numeric,
        'sd', (ck.cd ->> 'sd')::numeric,
        'sl', (ck.cl ->> 'sd')::numeric,
        'due', CASE WHEN vn.dispatch_due_at IS NOT NULL
                    THEN round((extract(epoch FROM (vn.dispatch_due_at - v_t0)) / 60.0)::numeric, 2) END,
        'imm', COALESCE(vn.urgency = 'immediate_dispatch', false)) AS j) q;

  -- the cars the check did not see that joined the line: home inside the window owing a charge, or in the depot and
  -- charged on a charger the check modelled
  SELECT COALESCE(jsonb_agg(z.j ORDER BY (z.j ->> 'eta')::numeric, z.j ->> 'id'), '[]'::jsonb)
    INTO v_app
    FROM (
      SELECT COALESCE(fs.f -> 'j', '{}'::jsonb) || jsonb_build_object(
               'id', v.id::text, 'src', 'appeared', 'how', CASE WHEN rt.actual_return_at IS NOT NULL THEN 'returned' ELSE 'at_depot' END,
               'eta', round((extract(epoch FROM (COALESCE(rt.actual_return_at, fs.plug_at) - v_t0)) / 60.0)::numeric, 2),
               'esd', 0, 'trip', 0, 'w', 0, 'soc', round(b.soc, 1), 'g', round(GREATEST(b.tgt - b.soc, 1), 2),
               'imm', COALESCE(vn.urgency = 'immediate_dispatch', false),
               'due', CASE WHEN vn.dispatch_due_at IS NOT NULL
                           THEN round((extract(epoch FROM (vn.dispatch_due_at - v_t0)) / 60.0)::numeric, 2) END,
               'dok', public.ottoq_charge_kind_compatible(v.id, s.depot_id, 'dcfc'),
               'lok', public.ottoq_charge_kind_compatible(v.id, s.depot_id, 'l2'),
               'md', (ck.cd ->> 'm')::numeric,
               'ml', (ck.cl ->> 'm')::numeric,
               'sd', (ck.cd ->> 'sd')::numeric,
               'sl', (ck.cl ->> 'sd')::numeric) AS j
        FROM (SELECT k.key AS id FROM jsonb_each(v_fs) k
               WHERE k.key <> ALL (v_ids || v_mod)
                 AND ((k.value ->> 'stall') = ANY (v_ch_ids) OR (k.value ->> 'stall') = ANY (v_back_ids))
              UNION
              SELECT d.vehicle_id::text FROM ottoq_vehicle_dispatches d
               WHERE d.sim_run_id = s.sim_run_id AND d.actual_return_at > v_t0 AND d.actual_return_at <= v_cut
                 AND d.vehicle_id::text <> ALL (v_ids || v_mod)
                 -- a car whose first charge was on a charger the check left out never competed for the ones it modelled
                 AND NOT (v_fs ? d.vehicle_id::text
                          AND NOT ((v_fs #>> ARRAY[d.vehicle_id::text, 'stall']) = ANY (v_ch_ids)
                                   OR (v_fs #>> ARRAY[d.vehicle_id::text, 'stall']) = ANY (v_back_ids)))) cand
        JOIN vehicles v ON v.id::text = cand.id AND v.home_depot_id = s.depot_id AND v.category = 'autonomous'
        CROSS JOIN LATERAL (SELECT v_fs -> cand.id AS f, (v_fs #>> ARRAY[cand.id, 'started_at'])::timestamptz AS plug_at,
                                   (v_fs #>> ARRAY[cand.id, 'soc_start'])::numeric AS soc_start) fs
        LEFT JOIN LATERAL (SELECT d.actual_return_at, d.soc_at_return_pct FROM ottoq_vehicle_dispatches d
                            WHERE d.sim_run_id = s.sim_run_id AND d.vehicle_id = v.id AND d.actual_return_at > v_t0
                              AND d.actual_return_at <= COALESCE(fs.plug_at, v_cut)
                            ORDER BY d.actual_return_at DESC LIMIT 1) rt ON true
        CROSS JOIN LATERAL (SELECT COALESCE(rt.soc_at_return_pct, fs.soc_start) AS soc,
                                   public.ottoq_effective_target_soc_at(v.id, v_t0) AS tgt) b
        CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS who) wh
        CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(v_model, 'dcfc', wh.who, v.battery_capacity_kwh, b.soc, b.tgt,
                                                             v_kw_d, v.inlet_max_kw, v_ev -> 'dcfc') AS cd,
                                   public.ottoq_charge_clock(v_model, 'l2', wh.who, v.battery_capacity_kwh, b.soc, b.tgt,
                                                             v_kw_l, v.inlet_max_kw, v_ev -> 'l2') AS cl) ck
        LEFT JOIN LATERAL (SELECT vn.dispatch_due_at, vn.urgency FROM ottoq_visit_needs vn
                            WHERE vn.vehicle_id = v.id AND vn.sim_run_id = s.sim_run_id
                              AND vn.arrived_at <= COALESCE(rt.actual_return_at, fs.plug_at) + interval '2 minutes'
                            ORDER BY vn.arrived_at DESC, vn.created_at DESC LIMIT 1) vn ON true
       WHERE COALESCE(rt.actual_return_at, fs.plug_at) IS NOT NULL AND b.soc IS NOT NULL AND b.soc < b.tgt - 1
         AND v.battery_capacity_kwh IS NOT NULL) z;

  -- 0623: for a state with an outflow block, each modelled car's first trip after the order, inside the window: when
  -- the charge before it ended (ce: the car's last completed charge since its last departure before the order, by its
  -- departure or the cut), when it left, and when it came back and with what
  IF jsonb_typeof(s.state -> 'outflow') = 'object' THEN
    SELECT COALESCE(jsonb_object_agg(c.id, jsonb_strip_nulls(jsonb_build_object(
             'ce', CASE WHEN ce.at IS NOT NULL THEN round((extract(epoch FROM (ce.at - v_t0)) / 60.0)::numeric, 2) END,
             'left', CASE WHEN d.dispatched_at IS NOT NULL
                          THEN round((extract(epoch FROM (d.dispatched_at - v_t0)) / 60.0)::numeric, 2) END,
             'eta', CASE WHEN d.actual_return_at IS NOT NULL AND d.actual_return_at <= v_cut
                         THEN round((extract(epoch FROM (d.actual_return_at - v_t0)) / 60.0)::numeric, 2) END,
             'soc', CASE WHEN d.actual_return_at IS NOT NULL AND d.actual_return_at <= v_cut
                         THEN round(d.soc_at_return_pct, 1) END))), '{}'::jsonb)
      INTO v_ret
      FROM (SELECT DISTINCT u.id FROM unnest(v_ids || v_mod) u(id)
             WHERE u.id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') c
      LEFT JOIN LATERAL (SELECT dd.dispatched_at, dd.actual_return_at, dd.soc_at_return_pct
                           FROM ottoq_vehicle_dispatches dd
                          WHERE dd.sim_run_id = s.sim_run_id AND dd.vehicle_id = c.id::uuid
                            AND dd.dispatched_at > v_t0 AND dd.dispatched_at <= v_cut
                          ORDER BY dd.dispatched_at LIMIT 1) d ON true
      LEFT JOIN LATERAL (SELECT max(dd.dispatched_at) AS at FROM ottoq_vehicle_dispatches dd
                          WHERE dd.sim_run_id = s.sim_run_id AND dd.vehicle_id = c.id::uuid
                            AND dd.dispatched_at <= v_t0) lo ON true
      LEFT JOIN LATERAL (SELECT max(os.ended_at) AS at FROM ocpp_sessions os
                          WHERE os.sim_run_id = s.sim_run_id AND os.vehicle_id = c.id::uuid
                            AND os.stopped_reason = 'completed'
                            AND os.ended_at <= COALESCE(d.dispatched_at, v_cut)
                            AND (lo.at IS NULL OR os.ended_at > lo.at)) ce ON true;
  END IF;

  RETURN jsonb_build_object(
    'v', 1, 'order_id', p_order_id, 'window_min', COALESCE(p_window_min, 90), 'observed_min', v_obs,
    'run_status', v_status, 'cut', v_cut,
    'cars', v_cars, 'inbound', v_inb, 'appeared', v_app, 'chargers', v_ch, 'back', v_back,
    'faults', v_faults, 'unmodeled_sessions', v_unmod)
    || CASE WHEN v_ret IS NOT NULL THEN jsonb_build_object('returns', v_ret) ELSE '{}'::jsonb END;
END $fn$;

CREATE FUNCTION public.ottoq_charge_order_forecast_errors(p_state jsonb, p_real jsonb, p_expected jsonb)
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
  SELECT public.ottoq_charge_order_forecast_errors(p_state, p_real)
         || CASE WHEN jsonb_typeof(p_state -> 'outflow') IS DISTINCT FROM 'object' THEN '{}'::jsonb ELSE jsonb_build_object('outflow', (
              WITH o AS (SELECT COALESCE((p_real ->> 'observed_min')::numeric, 0) AS w),
              g AS (SELECT ARRAY(SELECT CASE WHEN jsonb_typeof(x.value) = 'number' THEN (x.value #>> '{}')::float8 END
                                   FROM jsonb_array_elements(COALESCE(p_state #> '{outflow,dwell,q}', '[]'::jsonb))
                                        WITH ORDINALITY x(value, i) ORDER BY x.i) AS q,
                           (p_state #>> '{outflow,dwell,f_max}')::float8 AS fmax,
                           (p_state #>> '{outflow,dwell,max_min}')::float8 AS mx),
              lv AS (SELECT x.value ->> 'id' AS id, COALESCE((x.value ->> 'e')::float8, 0) AS e
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
                            CASE WHEN rl.ce < 0 THEN COALESCE(lv.e, -rl.ce::float8) ELSE 0 END AS e
                       FROM rl CROSS JOIN o LEFT JOIN lv ON lv.id = rl.id
                      WHERE rl.ce IS NOT NULL AND (rl.ce >= 0 OR lv.id IS NOT NULL)),
              dc AS (SELECT dz.ev, public.ottoq_outflow_dwell_cdf(g.q, g.fmax, g.mx, dz.e) AS fe,
                            public.ottoq_outflow_dwell_cdf(g.q, g.fmax, g.mx, dz.cens) AS fc,
                            CASE WHEN dz.ev THEN public.ottoq_outflow_dwell_cdf(g.q, g.fmax, g.mx, dz.d) END AS fd
                       FROM dz CROSS JOIN g),
              -- p: the curve's chance the car is gone by the cut, given how long it had been parked; v: for a car that
              -- went, where its dwell fell in the curve between those two (uniform on (0, 1) when the curve is right,
              -- whatever the cut: a car still parked at the cut never enters it, so the cut cannot bias it)
              dw AS (SELECT dc.ev, CASE WHEN dc.fe < 1 THEN GREATEST(dc.fc - dc.fe, 0) / (1 - dc.fe) ELSE 0 END AS p,
                            CASE WHEN dc.ev AND dc.fc > dc.fe
                                 THEN LEAST(GREATEST((dc.fd - dc.fe) / (dc.fc - dc.fe), 0), 1) END AS v
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
                FROM j)) END
$fn$;

CREATE OR REPLACE FUNCTION public.ottoq_charge_order_grade(p_order_id bigint, p_window_min numeric DEFAULT 90)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0621: one checked order, graded once: the check's expected future (scenario 0 of its own rollout) and the world that
   came, each replayed both ways by the same simulator from the same state; the outcome; what the order changed; how
   each forecast fared; how close the simulator came given the real inputs. Writes only its own ledger.
   0623: the forecast errors grade the outflow too, against the expected future of the order that ran; the stored
   sides leave out their traces. */
DECLARE
  v_row jsonb; s record; o record; v_real jsonb; v_full jsonb; ek jsonb; ea jsonb; hk jsonb; ha jsonb;
  v_exp jsonb; v_hind jsonb; v_reason text; v_taken boolean; v_decision boolean; v_outcome text; v_hc int;
  v_futures int; v_wins int; v_need int; v_w numeric := GREATEST(COALESCE(p_window_min, 90), 1);
BEGIN
  SELECT to_jsonb(h) INTO v_row FROM ottoq_charge_order_hindsight h WHERE h.order_id = p_order_id;
  IF v_row IS NOT NULL THEN RETURN v_row; END IF;
  SELECT * INTO s FROM ottoq_charge_order_snapshots x WHERE x.order_id = p_order_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO o FROM ottoq_agent_charge_orders x WHERE x.order_id = p_order_id;
  v_reason := COALESCE(o.projection ->> 'reason', 'unknown');
  v_taken := COALESCE(o.status IN ('accepted', 'partial'), false);
  v_decision := v_reason IN ('worse_in_expected_future', 'no_better_in_expected_future', 'not_enough_futures_won',
                             'wins_most_futures');
  v_futures := CASE WHEN (o.projection ->> 'futures') ~ '^[0-9]+$' THEN (o.projection ->> 'futures')::int END;
  v_wins := CASE WHEN (o.projection ->> 'wins') ~ '^[0-9]+$' THEN (o.projection ->> 'wins')::int END;
  v_need := CASE WHEN (o.projection ->> 'need') ~ '^[0-9]+$' THEN (o.projection ->> 'need')::int END;

  v_real := public.ottoq_charge_order_realized(p_order_id, v_w);
  ek := public.ottoq_charge_line_schedule(s.state, NULL, 0, s.seed, true);
  ea := public.ottoq_charge_line_schedule(s.state, s.agent_order, 0, s.seed, true);
  v_full := public.ottoq_charge_line_realize(s.state, v_real,
                                             ARRAY['arrivals', 'appeared', 'charge_times', 'running', 'faults']);
  hk := public.ottoq_charge_line_schedule(v_full, NULL, 0, s.seed, true);
  ha := public.ottoq_charge_line_schedule(v_full, s.agent_order, 0, s.seed, true);
  v_exp := public.ottoq_charge_line_compare(ek, ea);
  v_hind := public.ottoq_charge_line_compare(hk, ha);
  v_hc := (v_hind ->> 'cmp')::int;
  v_outcome := CASE WHEN NOT v_decision THEN
                      CASE WHEN (hk -> 'first') IS NOT DISTINCT FROM (ha -> 'first') THEN 'no_decision'
                           ELSE 'no_decision_mattered' END
                    WHEN v_taken AND v_hc > 0 THEN 'right_take'
                    WHEN v_taken AND v_hc = 0 THEN 'neutral_take'
                    WHEN v_taken THEN 'wrong_take'
                    WHEN v_hc > 0 THEN 'missed_win'
                    ELSE 'right_refusal' END;

  INSERT INTO ottoq_charge_order_hindsight
    (order_id, sim_run_id, depot_id, sim_clock, window_min, observed_min, status, reason, taken, decision, futures,
     wins, need, p_win, expected, hindsight, outcome, moves, forecast, fidelity, realized, code_md5)
  VALUES (p_order_id, s.sim_run_id, s.depot_id, s.sim_clock, v_w, COALESCE((v_real ->> 'observed_min')::numeric, 0),
          o.status, v_reason, v_taken, v_decision, v_futures, v_wins, v_need,
          CASE WHEN v_decision AND v_futures > 0 THEN round(v_wins::numeric / v_futures, 4) END,
          v_exp || jsonb_build_object('kernel', ek - ARRAY['first', 'seats', 'return_seats'], 'agent', ea - ARRAY['first', 'seats', 'return_seats']),
          v_hind || jsonb_build_object('kernel', hk - ARRAY['first', 'seats', 'return_seats'], 'agent', ha - ARRAY['first', 'seats', 'return_seats']),
          v_outcome,
          CASE WHEN v_decision OR v_outcome = 'no_decision_mattered'
               THEN public.ottoq_charge_order_moves(s.state, ek, ea) ELSE '{}'::text[] END,
          public.ottoq_charge_order_forecast_errors(s.state, v_real, CASE WHEN v_taken THEN ea ELSE ek END),
          public.ottoq_charge_order_fidelity(CASE WHEN v_taken THEN ha ELSE hk END, v_real),
          COALESCE(v_real, '{}'::jsonb), public.ottoq_hindsight_code_md5())
  ON CONFLICT (order_id) DO NOTHING;
  SELECT to_jsonb(h) INTO v_row FROM ottoq_charge_order_hindsight h WHERE h.order_id = p_order_id;
  RETURN v_row;
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_hindsight_code_md5()
RETURNS text
LANGUAGE sql
STABLE
AS $fn$
  -- 0621: the md5 of the code that grades: the simulator, the comparison, the realizer, the reader and the grade's parts.
  -- 0623: and the outflow's draws and its forecast errors.
  SELECT md5(string_agg(pg_get_functiondef(p::regprocedure), '' ORDER BY p))
    FROM unnest(ARRAY['public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)',
                      'public.ottoq_charge_line_compare(jsonb,jsonb)',
                      'public.ottoq_charge_line_real_minutes(jsonb,jsonb)',
                      'public.ottoq_charge_line_realize(jsonb,jsonb,text[])',
                      'public.ottoq_charge_order_realized(bigint,numeric)',
                      'public.ottoq_charge_order_moves(jsonb,jsonb,jsonb)',
                      'public.ottoq_charge_order_forecast_errors(jsonb,jsonb)',
                      'public.ottoq_charge_order_forecast_errors(jsonb,jsonb,jsonb)',
                      'public.ottoq_charge_order_fidelity(jsonb,jsonb)',
                      'public.ottoq_charge_order_grade(bigint,numeric)',
                      'public.ottoq_charge_order_attribute(bigint)',
                      'public.ottoq_charge_line_return_draw(double precision[],double precision[],double precision[],double precision,double precision,double precision,integer,text,text,double precision,double precision,double precision,jsonb,double precision)',
                      'public.ottoq_normal_quantile(double precision)',
                      'public.ottoq_outflow_dwell_quantile(double precision[],double precision,double precision,double precision)',
                      'public.ottoq_outflow_dwell_cdf(double precision[],double precision,double precision,double precision)',
                      'public.ottoq_hash_uniform(text)']) p
$fn$;

-- ══ grants ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
GRANT EXECUTE ON FUNCTION public.ottoq_hash_uniform(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_outflow_dwell_quantile(double precision[], double precision, double precision, double precision)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_outflow_dwell_cdf(double precision[], double precision, double precision, double precision)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_line_return_draw(double precision[], double precision[], double precision[],
  double precision, double precision, double precision, integer, text, text, double precision, double precision,
  double precision, jsonb, double precision) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_normal_quantile(double precision) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_order_forecast_errors(jsonb, jsonb, jsonb) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_return_model_params(uuid, timestamptz, interval) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_charge_line_outflow(uuid, uuid, timestamptz, jsonb, jsonb, jsonb, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_return_model_params(uuid, timestamptz, interval) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_line_outflow(uuid, uuid, timestamptz, jsonb, jsonb, jsonb, jsonb) TO service_role;

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v1$
DECLARE v_n int; v_bad int; v_rn int := 0; r record; v_now jsonb;
BEGIN
  -- the stored snapshots (none carries an outflow block) simulate and compare as before this file
  SELECT count(*), count(*) FILTER (WHERE b.k IS DISTINCT FROM public.ottoq_charge_line_schedule(s.state, NULL, b.sc, s.seed, true)
                                       OR b.a IS DISTINCT FROM public.ottoq_charge_line_schedule(s.state, s.agent_order, b.sc, s.seed, true)
                                       OR b.c IS DISTINCT FROM public.ottoq_charge_line_compare(
                                            public.ottoq_charge_line_simulate(s.state, NULL, b.sc, s.seed),
                                            public.ottoq_charge_line_simulate(s.state, s.agent_order, b.sc, s.seed)))
    INTO v_n, v_bad
    FROM v0623_before b JOIN public.ottoq_charge_order_snapshots s USING (order_id);
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0623 V1: % of % stored simulations changed without an outflow block', v_bad, v_n;
  END IF;
  -- and the graded orders read as they were graded
  FOR r IN
    SELECT h.order_id, h.window_min, h.realized
      FROM ottoq_charge_order_hindsight h JOIN ottoq_sim_runs x ON x.sim_run_id = h.sim_run_id
     WHERE h.observed_min = h.window_min AND x.status = 'completed' AND h.graded_at < x.ended_at
     ORDER BY h.order_id DESC LIMIT 10
  LOOP
    v_now := public.ottoq_charge_order_realized(r.order_id, r.window_min);
    IF (v_now - 'run_status') IS DISTINCT FROM (r.realized - 'run_status') THEN
      RAISE EXCEPTION '0623 V1: order % no longer reads as it was graded', r.order_id;
    END IF;
    v_rn := v_rn + 1;
  END LOOP;
  RAISE NOTICE '0623 V1: % stored simulations and comparisons (% snapshots x 2 futures) and % graded orders read as before',
    v_n, v_n / 2, v_rn;
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
  v_seen int := 0; v_left int := 0; v_pleft numeric := 0; v_brier numeric := 0; v_pn int := 0; v_p50 int := 0;
  v_p80 int := 0; v_psum numeric := 0; v_dratio numeric;
  v_ms int; v_ret jsonb; v_aug jsonb; v_ct jsonb; v_o jsonb; v_x jsonb; v_rz jsonb;
  v_c50 numeric; v_c80 numeric; v_ratio numeric;
BEGIN
  SELECT started_at INTO v_start FROM ottoq_sim_runs WHERE sim_run_id = c_run AND status = 'completed';
  IF v_start IS NULL OR NOT EXISTS (SELECT 1 FROM ottoq_charge_order_hindsight WHERE sim_run_id = c_run) THEN
    RAISE NOTICE '0623 V2: run d9d49732 is not here; the outflow forecast is executed by the tests';
    RETURN;
  END IF;
  -- the return model as it would have been fitted the moment the run began: out of sample for every order on it
  v_rt := jsonb_build_object('usable', true, 'estimate_id', NULL,
                             'params', public.ottoq_return_model_params(c_depot, v_start, interval '21 days'));
  FOR r IN
    SELECT h.order_id, h.sim_clock, h.observed_min, h.taken, h.decision, h.realized, h.expected, h.hindsight,
           s.state, s.seed, s.agent_order
      FROM ottoq_charge_order_hindsight h JOIN ottoq_charge_order_snapshots s USING (order_id)
     WHERE h.sim_run_id = c_run
     ORDER BY h.order_id
  LOOP
    -- the snapshot's own clock, and the outflow as of its clock
    IF (r.state #>> '{models,charge_time_model}') = 'charge_time_v2' THEN
      SELECT jsonb_build_object('params', f.params) INTO v_ct FROM ottoq_charge_clock_fits f
       WHERE f.fit_id = (r.state #>> '{models,charge_time}')::bigint;
    ELSE
      SELECT jsonb_build_object('params', e.params) INTO v_ct FROM ottoq_learned_estimates e
       WHERE e.estimate_id = (r.state #>> '{models,charge_time}')::bigint;
    END IF;
    v_aug := public.ottoq_charge_line_outflow(c_run, c_depot, r.sim_clock, r.state, v_ct, v_rt,
                                              public.ottoq_charge_clock_run_evidence(v_ct, c_run, r.sim_clock));
    CONTINUE WHEN jsonb_typeof(v_aug -> 'outflow') IS DISTINCT FROM 'object';
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
  END LOOP;
  v_ms := round(extract(epoch FROM clock_timestamp() - v_t0) * 1000);
  v_c50 := round(v_p50::numeric / NULLIF(v_pn, 0), 3);
  v_c80 := round(v_p80::numeric / NULLIF(v_pn, 0), 3);
  v_dratio := round(v_pleft / NULLIF(v_left, 0), 3);
  v_ratio := round(v_m::numeric / NULLIF(v_real, 0), 3);
  RAISE NOTICE '0623 V2 (% graded orders of d9d49732, the dwell fitted through the run''s start, % ms): of % cars whose charge''s end was seen, % left inside the window against % the curve expected (ratio %; Brier % against % for the base rate)',
    v_orders, v_ms, v_seen, v_left, round(v_pleft, 1), v_dratio, round(v_brier / NULLIF(v_seen, 0), 4),
    round((v_left::numeric / NULLIF(v_seen, 0)) * (1 - v_left::numeric / NULLIF(v_seen, 0)), 4);
  RAISE NOTICE '0623 V2 of the % that left with the curve open, % fell under its median for that stretch (%), % under its 80th percentile (%), mean %',
    v_pn, v_p50, v_c50, v_p80, v_c80, round(v_psum / NULLIF(v_pn, 0), 3);
  RAISE NOTICE '0623 V2 returns inside the window: % forecast, % real (ratio %), mean arrival % against % minutes; by car % hits (recall %, precision %), % minutes apart',
    v_m, v_real, v_ratio, round(v_am / NULLIF(v_m, 0), 1), round(v_ar / NULLIF(v_real, 0), 1), v_hit,
    round(v_hit::numeric / NULLIF(v_real, 0), 3), round(v_hit::numeric / NULLIF(v_m, 0), 3), round(v_abs / NULLIF(v_hit, 0), 2);
  IF v_orders = 0 OR v_c50 IS NULL OR v_c50 NOT BETWEEN 0.40 AND 0.60 OR v_c80 IS NULL OR v_c80 NOT BETWEEN 0.70 AND 0.90
     OR v_dratio IS NULL OR v_dratio NOT BETWEEN 0.75 AND 1.33 OR v_ratio IS NULL OR v_ratio NOT BETWEEN 0.75 AND 1.33 THEN
    RAISE EXCEPTION '0623 V2: the outflow forecast is not calibrated (dwell under its median %, under its 80th percentile %, departures expected over real %, returns forecast over real %): not applied',
      v_c50, v_c80, v_dratio, v_ratio;
  END IF;
END $v2$;

-- the first fit with the dwell, at apply (the nightly job already calls the fit)
SELECT public.ottoq_fit_return_model('11111111-1111-1111-1111-111111111111'::uuid, NULL, interval '21 days',
                                     '0623: the first fit with the dwell, at apply');

DO $v3$
DECLARE v_rt jsonb; r record; v_state jsonb; t0 timestamptz; v_ms numeric;
BEGIN
  v_rt := public.ottoq_learned_estimate('11111111-1111-1111-1111-111111111111'::uuid, 'return_v1');
  IF v_rt #> '{params,dwell}' IS NULL THEN
    RAISE EXCEPTION '0623 V3: the fit at apply carries no dwell';
  END IF;
  RAISE NOTICE '0623 V3: return_v1 estimate % (usable %): dwell from % charges (% left, % still parked), median % min, f_max %, population %',
    v_rt -> 'estimate_id', v_rt -> 'usable', v_rt #> '{params,dwell,n}', v_rt #> '{params,dwell,left}',
    v_rt #> '{params,dwell,censored}', v_rt #> '{params,dwell,median_min}', v_rt #> '{params,dwell,f_max}',
    v_rt #> '{params,dwell,population}';
  SELECT x.sim_run_id, x.depot_id, x.sim_clock_current INTO r
    FROM ottoq_sim_runs x WHERE x.status = 'running' AND x.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY x.started_at DESC LIMIT 1;
  IF r.sim_run_id IS NULL THEN
    RAISE NOTICE '0623 V3: no twin run is running; the state is executed by the tests';
    RETURN;
  END IF;
  t0 := clock_timestamp();
  v_state := public.ottoq_charge_line_state(r.sim_run_id, r.depot_id, r.sim_clock_current);
  v_ms := round(extract(epoch FROM clock_timestamp() - t0) * 1000);
  RAISE NOTICE '0623 V3 on running run %: state % ms, outflow %: % cars modelled, % parked, % busy chargers with their car',
    r.sim_run_id, v_ms, jsonb_typeof(v_state -> 'outflow'),
    (SELECT count(*) FROM jsonb_object_keys(COALESCE(v_state #> '{outflow,ret}', '{}'::jsonb))),
    jsonb_array_length(COALESCE(v_state #> '{outflow,leaving}', '[]'::jsonb)),
    (SELECT count(*) FROM jsonb_array_elements(v_state -> 'chargers') c WHERE c.value ? 'car');
END $v3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0623_the_check_sees_cars_leave_and_come_back', false, false,
  'The agent''s charge-order check sees the depot''s own outflow: cars leave after the learned dwell (Kaplan-Meier, '
  'refitted nightly with return_v1), work to the reserve or are called home first, and come back owing a charge; each '
  'car is compared over its visit now and its next. The grader grades the outflow forecast. Without an outflow block '
  'every reader returns what it returned (V1); a person''s dial turns it off. FALSE/FALSE: the tick path is untouched '
  'and orders exist only on operator_demo runs (0615).',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
