-- migration-version: PENDING
-- migration-name:    the_futures_call_cars_home_the_way_the_kernel_does
--
-- 0627  **The futures call cars home the way the kernel does.**
--       0626's first self-review ranked the arrivals first: 22% of what made the check's verdicts wrong. 80% of the
--       2,510 cars the futures expected home came inside their 80% band, but 104 came far late and 69 far early (G363,
--       db/checks/0420). Both tails are the kernel's own recall decision, read wrongly. The futures called every working
--       car home at one reserve, the median the depot's returns show (49.9%). The kernel calls each car home at its own
--       reserve rung, its reserve plus the run's margin, and 16 of the depot's 116 cars carry a reserve of 15, not 20: they
--       turn home at 45%, minutes later than forecast. And the kernel recalls a car at once when its telemetry goes stale
--       or a rider flags it, which the futures never did for a car already at work. 0627 forecasts each working car at its
--       own reserve rung, samples the other calls home at the rate the depot's returns show, and gives the forecast the
--       drive's own spread in minutes. Chase, 2026-10-08: "Ideally, after a while, the system itself will pick up areas
--       for self improvement." This is the first area the system ranked, built. Rule 10 holds: the reserve rung is the
--       kernel's own rule, read; the rates and spreads are estimates refitted nightly from real returns; the one new dial
--       is a person's.
--
-- ══ §1 WHY (G363; run d9d49732's 61 graded orders, and the 21 days of returns before them; measured 2026-10-08
--    23:09 to 23:37 UTC, 6:09-6:37 PM CT) ════════════════════════════════════════════════════════════════════════════
--
--   (a) The late tail is a reserve read wrongly. Of the 104 cars that came home more than 3 spreads late, 87 were reserve
--       returns 12.5 minutes from the reserve at the order, and the kernel recalled them at a mean 46.6% charge, not the
--       49.9% the futures used. The recall decision's own ledger (ottoq_recall_decisions) shows why on one of them
--       (b2222222-...-0005 on d9d49732): evaluated every tick from 60.1% down, it said no at 49.9 and below and yes at 44.9,
--       its reserve 15 plus the run's margin of 30. 16 of the twin depot's 116 cars carry min_soc_threshold 15 and 100
--       carry 20, and no operator contract sets a return reserve. The margin is per run: 30 on the 82 twin runs of the 21
--       days that set it so, 25 on 70 others.
--   (b) The early tail is a call home the futures never make for a car at work. Of the 69 cars far early, 54 were recalled
--       on stale telemetry (comms_stale: the last packet older than 3 ticks, and the twin drops a packet 3% of the time)
--       and 3 on a rider's cleaning flag. The return fit already learned these calls (other_per_work_hour, 0.109 an hour
--       of work on the fit of 2026-10-08) and the outflow used them for the cars it sends out (0623); a car already at
--       work at the order did not get them.
--   (c) Measured before building, on the same 2,503 forecast arrivals, with each car's own reserve rung from the
--       evaluator's own record at the order and the learned drain: the late tail 104 -> 31, the early tail 68 -> 56 (its
--       calls are not the reserve's), inside the 80% band 79.9% -> 84.7%, the mean absolute error 3.23 -> 2.64 minutes.
--       Each car's own drain measured since its dispatch did worse than the learned drain: 12.41 against 2.16 minutes of
--       absolute error on the reserve returns. Not built.
--   (d) What is left of the late tail is a spread in proportion to a wait of a minute or two: 28 reserve returns 1.3
--       minutes from their rung, a mean 1.0 minute late (the drive took 2.09 minutes against the forecast's 1.25). The
--       error's robust spread is 0.40 minutes under a 2-minute wait, 1.97 minutes (7.2% of the wait) at 15-40 minutes and
--       3.52 (7.0%) beyond. The drive home's own spread is 0.170 minutes (robust, over 1,422 reserve returns). A drive after
--       another call is a median 1.64 minutes and a p90 20.2 (193 returns), against 1.24 and 1.72 for the reserve's.
--   (e) Rehearsed whole on live at 23:48 UTC (6:48 PM CT) and rolled back, in 30 seconds: on the same 2,503
--       arrivals V2 measures the late tail 104 -> 9, the early tail 68 -> 2, the mean absolute error 3.229 -> 2.633
--       minutes, and 79.9% -> 85.1% inside the 80% band. Left: 5 reserve returns late, 4 on stale telemetry late and 2
--       early. The rung equals the recall decision's own record on 7,600 of 7,600 decisions across 152 runs.
--
-- ══ §2 WHAT ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq_recall_threshold_soc(vehicle, run, clock)`: the battery at which the kernel's own recall decision turns a
--       working car home on its reserve rung: ottoq_effective_reserve_soc plus the run's reserve_margin_pct, for an
--       implementation with that rung that still decides (naive_threshold_v1; interval_scheduled_v1 is retired), else
--       NULL. P1 reads the rung in the evaluator's source; V3 holds the values to its own record.
--   (b) `ottoq_normal_cdf(x)`, the inverse of ottoq_normal_quantile. (c) `ottoq_inbound_arrival_z(entry, recall, act)`:
--       where an arrival fell in the futures' own forecast of it, as a z; without a recall block, 0621's z exactly.
--   (d) `ottoq_charge_line_inbound` (same signature): with the run's new dial `agent_charge_order_recall_rule` at 1 (its
--       default), a car at work is forecast home at its own reserve rung, its spread the drain's and the drive's own in
--       minutes together: sqrt(dsd^2 + (trip_sd / max(wait, 0.25))^2). With the dial at 0, 0620's forecast exactly.
--   (e) return_v1 learns the drives (`ottoq_return_model_params`, same signature): trip_sd_min, trip_other_min and its
--       p90, and each other call's rate per work hour (other_by_trigger). Every other key is 0624's (V1).
--   (f) The state (same signature): each forecast car carries its rung (`thr`), and the state carries `recall`: the other
--       calls' rate per minute (lam), the drive after one (trip_o), the drain, and the drive's spread (asd). (g) The
--       outflow (same signature): each car it sends out carries its own rung in `ret`, and its battery back from there;
--       the block carries trip_o. (h) The draw (same signature): p_out[8], the drive after another call.
--   (i) The simulator (same signature): a sampled future calls each car at work home on another call when that comes
--       before its reserve, at lam and then trip_o, back with the charge it did not use; a car the outflow sends out
--       turns home at its own rung. The expected future keeps each car's median arrival. Without `recall`, a `thr` or a
--       `trip_o`, 0624's result, key for key (V1).
--   (j) The self-review places each arrival in the forecast the futures made of it, and marks the arrivals built while
--       the graded orders were made without the rule; its writer's code md5 covers the z.
--   (k) A person's dial, catalogued, not agent-writable: `agent_charge_order_recall_rule` (1; 0 is 0626's check).
--
--   The tick path is untouched, and so is the recall decision: the check reads it. The check, the grader and the board
--   run only on runs that take an agent's charge order (0615); the fit writes one row a night.
--
-- ══ §3 CHECKS ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: every body replaced or relied on is the one this file was written against (md5);
--   nothing this file creates exists. Nothing here drops or deletes anything.
--   V1: (i) the 20 latest stored snapshots, in the expected future and a sampled one, simulate and compare as before
--   this file (their states carry no recall block, no rung and no trip_o); (ii) on every graded order of the 21 days, the
--   z of each forecast arrival through ottoq_inbound_arrival_z equals 0621's (their states carry no recall block); (iii)
--   the fit through d9d49732's start: every key 0624 computed is as it was, and the drives are added.
--   V2: THE GATE, out of sample (the fit through d9d49732's start; the rung needs no fit). On d9d49732's graded orders,
--   each forecast car that came home is forecast again as this file forecasts it, from its battery at the order (the
--   recall decision's own record) and the order's own drain and drive: the late tail (z > 3) at most half what it was,
--   the early tail no larger, the mean absolute error lower, and 75-90% inside the 80% band; or nothing here is applied.
--   Reported beside it: the tails by the trigger of each car's return. The other calls home explain an early arrival, so
--   the tails seldom decide: a wrong rung shows in the error (the tests: cars that came home at the one reserve double
--   it on a miniature d9d49732 and hold the gate back).
--   V3: the rung equals the evaluator's own threshold on the latest recall decisions of each twin run of the 21 days; the
--   fit at apply carries the drives; the state on a running twin run carries the rungs and the recall block.
--   tests/test_agent_recall_rule_sql.py executes the rest on the miniature depot.
--
-- ══ §4 RECERT ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   FALSE/FALSE. The check, its grader and the board run only on runs that take an agent's charge order (0615); no
--   certification, sweep or dial pair arms an order, and the review reads grades. Without the dial, a recall block, a rung
--   or a trip_o every reader returns what it returned (V1); the new estimate keys are evidence.
--
-- ROLLBACK: set agent_charge_order_recall_rule to 0 on the runs that should not see it (0626's check, exactly), or
--   EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0627_pre' (the inbound forecast, the fit, the
--   state, the outflow, the draw, the schedule, the review and its writer as 0626 left them). DROP FUNCTION
--   public.ottoq_recall_threshold_soc(uuid, uuid, timestamptz), public.ottoq_inbound_arrival_z(jsonb, jsonb, double
--   precision), public.ottoq_normal_cdf(double precision); DELETE FROM public.ottoq_policy_param_catalog WHERE param_key =
--   'agent_charge_order_recall_rule'; DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0627_the_futures_call_cars_home_the_way_the_kernel_does'. The return_v1 rows written since keep their new keys;
--   nothing reads them once rolled back.

BEGIN;

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0627 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_charge_line_inbound(uuid,uuid,timestamp with time zone,numeric,jsonb)', '7b3d205a', 'the inbound forecast (0620)'),
      ('public.ottoq_return_model_params(uuid,timestamp with time zone,interval)', 'e108150a', 'the return fit''s parameters (0624)'),
      ('public.ottoq_fit_return_model(uuid,timestamp with time zone,interval,text)', '05f61d70', 'the return fit (0623)'),
      ('public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)', '3b9fc780', 'the state (0623)'),
      ('public.ottoq_charge_line_outflow(uuid,uuid,timestamp with time zone,jsonb,jsonb,jsonb,jsonb)', '686cc9ba', 'the outflow (0624)'),
      ('public.ottoq_charge_line_return_draw(double precision[],double precision[],double precision[],double precision,double precision,double precision,integer,text,text,double precision,double precision,double precision,jsonb,double precision)', '31eafc5d', 'the draw (0624)'),
      ('public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)', 'e615980b', 'the schedule (0624)'),
      ('public.ottoq_charge_line_simulate(jsonb,jsonb,integer,text)', '265735b2', 'the simulator (0621)'),
      ('public.ottoq_charge_line_compare(jsonb,jsonb)', '5054e2dc', 'the comparison (0623)'),
      ('public.ottoq_charge_line_realize(jsonb,jsonb,text[])', '4817598b', 'the realizer (0623)'),
      ('public.ottoq_charge_order_realized(bigint,numeric)', '62914504', 'the realized reader (0623)'),
      ('public.ottoq_charge_order_grade(bigint,numeric)', 'cf987b52', 'the grade (0623)'),
      ('public.ottoq_hindsight_code_md5()', '322ee2fd', 'the grader''s md5 (0623)'),
      ('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', '96f00933', 'the self-review (0626)'),
      ('public.ottoq_arbiter_assess(uuid,integer)', '86cddce2', 'the review''s writer (0626)'),
      ('public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)', 'd926a480', 'the board (0620)'),
      ('public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)', 'ca31180e', 'the order''s recorder (0620)'),
      ('public.ottoq_effective_reserve_soc(uuid,timestamp with time zone)', 'c6ec26b6', 'a car''s reserve'),
      ('public.ottoq_learned_estimate(uuid,text)', 'ff910870', 'the latest fit (0619)'),
      ('public.ottoq_normal_quantile(double precision)', '6237242a', 'the normal quantile (0623)'),
      ('public.ottoq_hash_uniform(text)', '3fd35975', 'the hashed uniform (0623)'),
      ('public.ottoq_hash_normal(text)', 'f9607267', 'the hashed normal (0620)'))
    AS x(sig, md5, what)
  LOOP
    IF left((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)), 8) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0627 P1: % is not the body this file was written against (md5 %); read it again', r.what, r.md5;
    END IF;
  END LOOP;
  -- the rung this file reads is the one the recall decision applies (V3 holds the values to its own record)
  SELECT p.prosrc AS src INTO r FROM pg_proc p
   WHERE p.oid = to_regprocedure('public.ottoq_recall_naive_threshold_v1(uuid,uuid,timestamp with time zone,numeric,numeric)');
  IF COALESCE(position('v_reserve := ottoq_effective_reserve_soc(p_vehicle_id, p_sim_clock_now);' IN r.src), 0) = 0
     OR COALESCE(position('v_reserve_margin := ottoq_policy_get(p_sim_run_id,''reserve_margin_pct'',15);' IN r.src), 0) = 0
     OR COALESCE(position('IF v_soc <= v_reserve + v_reserve_margin THEN' IN r.src), 0) = 0 THEN
    RAISE EXCEPTION '0627 P1: the recall decision''s reserve rung is not its reserve plus the run''s margin';
  END IF;
  IF to_regprocedure('public.ottoq_recall_threshold_soc(uuid,uuid,timestamp with time zone)') IS NOT NULL
     OR to_regprocedure('public.ottoq_normal_cdf(double precision)') IS NOT NULL
     OR to_regprocedure('public.ottoq_inbound_arrival_z(jsonb,jsonb,double precision)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_recall_rule') THEN
    RAISE EXCEPTION '0627 P1: something this file creates already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0627_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_charge_line_inbound(uuid,uuid,timestamp with time zone,numeric,jsonb)'::regprocedure,
                 'public.ottoq_return_model_params(uuid,timestamp with time zone,interval)'::regprocedure,
                 'public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_charge_line_outflow(uuid,uuid,timestamp with time zone,jsonb,jsonb,jsonb,jsonb)'::regprocedure,
                 'public.ottoq_charge_line_return_draw(double precision[],double precision[],double precision[],double precision,double precision,double precision,integer,text,text,double precision,double precision,double precision,jsonb,double precision)'::regprocedure,
                 'public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)'::regprocedure,
                 'public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)'::regprocedure,
                 'public.ottoq_arbiter_assess(uuid,integer)'::regprocedure);

-- V1's "before" (i): the 20 latest stored snapshots' simulations and comparisons (the expected future and a sampled one)
CREATE TEMP TABLE v0627_before ON COMMIT DROP AS
SELECT s.order_id, sc.sc,
       public.ottoq_charge_line_schedule(s.state, NULL, sc.sc, s.seed, true) AS k,
       public.ottoq_charge_line_schedule(s.state, s.agent_order, sc.sc, s.seed, true) AS a,
       public.ottoq_charge_line_compare(public.ottoq_charge_line_simulate(s.state, NULL, sc.sc, s.seed),
                                        public.ottoq_charge_line_simulate(s.state, s.agent_order, sc.sc, s.seed)) AS c
  FROM (SELECT * FROM public.ottoq_charge_order_snapshots ORDER BY order_id DESC LIMIT 20) s
 CROSS JOIN (VALUES (0), (3)) sc(sc);

-- V1's "before" (iii): 0624's fit through d9d49732's start
CREATE TEMP TABLE v0627_fit (through timestamptz, params jsonb) ON COMMIT DROP;
INSERT INTO v0627_fit
SELECT r.started_at, public.ottoq_return_model_params('11111111-1111-1111-1111-111111111111'::uuid, r.started_at, interval '21 days')
  FROM public.ottoq_sim_runs r
 WHERE r.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND r.status = 'completed'
   AND EXISTS (SELECT 1 FROM public.ottoq_charge_order_hindsight h WHERE h.sim_run_id = r.sim_run_id);

-- ══ (k) the dial ════════════════════════════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, agent_writable, affects, description)
VALUES ('agent_charge_order_recall_rule', 0, 1, 1, false,
  'ottoq_charge_line_inbound, ottoq_charge_line_state, ottoq_charge_line_outflow (0627 the recall rule)',
  '0627: whether the kernel''s check on an agent''s charge order calls each working car home where the kernel''s own '
  'recall decision calls it (its reserve plus the run''s margin), with the other calls home the depot''s returns show, '
  'or at the one reserve its returns show on average with no other call for a car already at work. 1 the rule; 0 is '
  '0626''s check exactly. A person''s dial, never the agent''s (rule 10).');

-- ══ (a) where the kernel's own recall decision turns a working car home ══════════════════════════════════════════════
CREATE FUNCTION public.ottoq_recall_threshold_soc(p_vehicle_id uuid, p_sim_run_id uuid, p_clock timestamptz)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
  /* 0627: the battery at which the kernel's own recall decision turns a working car home on its reserve rung, as the
     run's recall implementation reads it (ottoq_evaluate_return_need): the car's reserve (ottoq_effective_reserve_soc,
     its operator's contract or its own floor) plus the run's reserve_margin_pct. NULL when the run's implementation has
     no such rung or decides no recall (retired), so a caller falls back to the reserve the depot's returns show.
     Read-only. */
  SELECT CASE WHEN i.status <> 'retired' AND i.implementation IN ('naive_threshold_v1', 'interval_scheduled_v1')
              THEN public.ottoq_effective_reserve_soc(p_vehicle_id, p_clock)
                   + COALESCE(public.ottoq_policy_get(p_sim_run_id, 'reserve_margin_pct', 15), 15) END
    FROM public.ottoq_recall_implementations i
   WHERE i.impl_id = COALESCE(public.ottoq_policy_get(p_sim_run_id, 'recall_implementation_id', 1), 1)::int
$fn$;

-- ══ (b) the normal distribution's own probability ═══════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_normal_cdf(p_x double precision)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
/* 0627: the standard normal's probability below p_x (Abramowitz and Stegun 26.2.17, absolute error under 7.5e-8), the
   inverse of ottoq_normal_quantile. NULL for NULL. Pure. */
DECLARE
  v_t float8; v_p float8;
BEGIN
  IF p_x IS NULL THEN RETURN NULL; END IF;
  IF p_x > 38 THEN RETURN 1; END IF;
  IF p_x < -38 THEN RETURN 0; END IF;
  v_t := 1 / (1 + 0.2316419 * abs(p_x));
  v_p := exp(-p_x * p_x / 2) / sqrt(2 * pi())
         * v_t * (0.319381530 + v_t * (-0.356563782 + v_t * (1.781477937 + v_t * (-1.821255978 + v_t * 1.330274429))));
  RETURN CASE WHEN p_x >= 0 THEN 1 - v_p ELSE v_p END;
END $fn$;

-- ══ (c) where a car's arrival fell in the futures' own forecast of it ═══════════════════════════════════════════════
CREATE FUNCTION public.ottoq_inbound_arrival_z(p_entry jsonb, p_recall jsonb, p_act double precision)
RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE PARALLEL SAFE
AS $fn$
/* 0627: where a working car's real arrival (p_act, minutes after the order) fell in the futures' own forecast of it, as
   a z: the forecast's probability that the car is home by then, through the normal quantile, so 0 is the forecast's
   median and +-1.2816 its 80% band. The futures send the car home at its reserve (p_entry's eta less its drive, spread
   log-normally by esd) or, with a recall block (ottoq_charge_line_state, 0627), earlier on another call home, at lam per
   minute and then the drive trip_o, whichever comes first. Without the block, or with lam 0, 0621's z exactly:
   ln((act - trip) / (eta - trip)) / esd. With them, a z past 6 spreads either way reads about 6: the probability it
   comes from carries no more digits, and either way the arrival is in a tail. NULL when the entry has no spread, the car
   is due at its drive, or it came no later than its drive. Pure. */
DECLARE
  v_eta  float8 := (p_entry ->> 'eta')::float8;
  v_trip float8 := COALESCE((p_entry ->> 'trip')::float8, 0);
  v_esd  float8 := (p_entry ->> 'esd')::float8;
  v_lam  float8 := COALESCE((p_recall ->> 'lam')::float8, 0);
  v_to   float8;
  v_zr float8; v_f float8;
BEGIN
  IF p_act IS NULL OR v_eta IS NULL OR v_esd IS NULL OR v_esd <= 0 OR v_eta <= v_trip OR p_act <= v_trip THEN
    RETURN NULL;
  END IF;
  v_zr := ln((p_act - v_trip) / (v_eta - v_trip)) / v_esd;
  IF v_lam <= 0 THEN
    RETURN v_zr;
  END IF;
  v_to := COALESCE((p_recall ->> 'trip_o')::float8, v_trip);
  -- home by p_act unless both the reserve and every other call come later
  v_f := 1 - (1 - public.ottoq_normal_cdf(v_zr)) * exp(-v_lam * GREATEST(p_act - v_to, 0));
  RETURN public.ottoq_normal_quantile(LEAST(GREATEST(v_f, 1e-9), 1 - 1e-9));
END $fn$;

-- ══ (d) a working car turns home where the kernel turns it ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_charge_line_inbound(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz,
                                                 p_window_min numeric DEFAULT 180, p_return_model jsonb DEFAULT NULL)
RETURNS TABLE(vehicle_id uuid, eta_min numeric, soc_at_arrival numeric, source text, eta_log_sd numeric, trip_min numeric)
LANGUAGE sql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0620: a car driving home arrives at its dispatch's scheduled_return_at (distance over speed, 0320); a car at work is
  -- called home when its live battery reaches the learned reserve (0619 return_v1), at the learned drain, then drives the
  -- learned trip. With no usable return model, only the cars already driving home. Read-only.
  -- 0627: with the run's agent_charge_order_recall_rule dial at 1 (its default), a car at work is called home where the
  -- kernel's own recall decision calls it, at its own reserve rung (ottoq_recall_threshold_soc: its reserve plus the run's
  -- margin), not at the reserve the depot's returns show on average; and its spread carries the drive's own, in minutes
  -- (the fit's trip_sd_min), beside the drain's, so a car minutes from its reserve is not forecast to the second. With
  -- the dial at 0, 0620's forecast exactly.
  WITH m AS (
    SELECT COALESCE(p_return_model, public.ottoq_learned_estimate(p_depot_id, 'return_v1')) AS j
  ), p AS (
    SELECT COALESCE((m.j ->> 'usable')::boolean, false) AS usable,
           (m.j #>> '{params,threshold_soc}')::numeric AS thr,
           (m.j #>> '{params,drain_pct_per_min}')::numeric AS drain,
           COALESCE((m.j #>> '{params,drain_log_sd}')::numeric, 0) AS dsd,
           COALESCE((m.j #>> '{params,trip_min}')::numeric, 0) AS trip,
           COALESCE((m.j #>> '{params,trip_sd_min}')::numeric, 0) AS asd,
           COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_recall_rule', 1), 1) >= 1 AS rule
      FROM m
  ), d AS (
    SELECT DISTINCT ON (d.vehicle_id) d.vehicle_id, d.status, d.scheduled_return_at, v.current_soc::numeric AS soc
      FROM public.ottoq_vehicle_dispatches d
      JOIN public.vehicles v ON v.id = d.vehicle_id
     WHERE d.sim_run_id = p_sim_run_id AND d.status IN ('active', 'returning') AND d.actual_return_at IS NULL
       AND v.home_depot_id = p_depot_id AND v.category = 'autonomous' AND v.current_soc IS NOT NULL
     ORDER BY d.vehicle_id, d.dispatched_at DESC
  )
  SELECT x.vehicle_id, round(x.eta, 2), round(GREATEST(x.soc, 0), 1), x.source, round(x.sd, 4), round(x.trip, 2)
    FROM (
      SELECT d.vehicle_id, GREATEST(extract(epoch FROM (d.scheduled_return_at - p_clock)) / 60.0, 0) AS eta,
             d.soc - COALESCE(p.drain, 0) * GREATEST(extract(epoch FROM (d.scheduled_return_at - p_clock)) / 60.0, 0) AS soc,
             'returning'::text AS source, 0::numeric AS sd, 0::numeric AS trip
        FROM d, p WHERE d.status = 'returning'
      UNION ALL
      SELECT d.vehicle_id, GREATEST((d.soc - t.thr) / p.drain, 0) + p.trip AS eta,
             LEAST(d.soc, t.thr) - p.drain * p.trip AS soc,
             'forecast'::text AS source,
             CASE WHEN p.rule AND p.asd > 0
                  THEN sqrt(p.dsd ^ 2 + (p.asd / GREATEST((d.soc - t.thr) / p.drain, 0.25)) ^ 2) ELSE p.dsd END AS sd,
             p.trip AS trip
        FROM d
        CROSS JOIN p
        CROSS JOIN LATERAL (SELECT CASE WHEN p.rule
                                        THEN COALESCE(public.ottoq_recall_threshold_soc(d.vehicle_id, p_sim_run_id, p_clock), p.thr)
                                        ELSE p.thr END AS thr) t
       WHERE d.status = 'active' AND p.usable AND p.drain > 0 AND p.thr IS NOT NULL
    ) x
   WHERE x.eta <= COALESCE(p_window_min, 180)
$fn$;

-- ══ (e) the return fit learns the drives: its own spread at the reserve, and after another call ════════════════════
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
   from one pass over the same rows, and the pooled `dwell` reads only what 0623's read: 0623's curve, unchanged.
   0627: and the drive home's own spread at the reserve (trip_sd_min: 1.4826 times the median absolute distance of the
   reserve returns' drives from their median), the drive after another call home (trip_other_min, its p90), and each
   other call's rate per work hour (other_by_trigger). Every other key is 0624's. */
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
           -- 0627: the drive home's own spread at the reserve, and the drive after another call, with each call's rate
           'trip_sd_min', round((SELECT 1.4826 * percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(l.trip_min - tm.m))
                                   FROM low l, (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY trip_min) AS m
                                                  FROM low WHERE trip_min >= 0) tm
                                  WHERE l.trip_min >= 0)::numeric, 3),
           'trip_other_min', round((SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY trip_min) FROM d
                                     WHERE return_trigger IS DISTINCT FROM 'low_soc_reserve' AND trip_min >= 0)::numeric, 2),
           'trip_other_p90_min', round((SELECT percentile_cont(0.9) WITHIN GROUP (ORDER BY trip_min) FROM d
                                         WHERE return_trigger IS DISTINCT FROM 'low_soc_reserve' AND trip_min >= 0)::numeric, 2),
           'other_by_trigger', COALESCE((SELECT jsonb_object_agg(o.t, jsonb_build_object('n', o.n,
                                                  'per_work_hour', round((o.n / NULLIF(w.h, 0))::numeric, 4)))
                                          FROM (SELECT COALESCE(return_trigger, 'unknown') AS t, count(*) AS n FROM d
                                                 WHERE return_trigger IS DISTINCT FROM 'low_soc_reserve' GROUP BY 1) o,
                                               (SELECT sum(GREATEST(work_min, 0)) / 60.0 AS h FROM d) w), '{}'::jsonb),
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

-- ══ (f) the state: each car at work at its own reserve rung, and the other calls home ══════════════════════════
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
   outflow (ottoq_charge_line_outflow): the cars that leave and come back. Read-only.
   0627: with the run's agent_charge_order_recall_rule dial at 1 (its default), each car at work carries `thr`, the reserve
   rung the kernel's own recall decision calls it home at (ottoq_charge_line_inbound forecasts from it), and the state
   carries `recall`: the other calls home a car at work can get before its reserve, at the depot's rate per minute (lam),
   with the drive after one (trip_o), the drain, and the drive's own spread (asd). With the dial at 0, 0623's state. */
DECLARE
  c_horizon constant numeric := 480;
  c_window  constant numeric := 180;
  v_ct jsonb := public.ottoq_charge_clock_model(p_depot_id);
  v_rt jsonb := public.ottoq_learned_estimate(p_depot_id, 'return_v1');
  v_ev jsonb;
  v_kw_d numeric; v_kw_l numeric; v_tick numeric; v_ttl numeric; v_pin numeric;
  v_cars jsonb; v_inb jsonb; v_ch jsonb; v_state jsonb;
  v_rule boolean := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_recall_rule', 1), 1) >= 1;   -- 0627
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
           || CASE WHEN th.r IS NOT NULL THEN jsonb_build_object('thr', th.r) ELSE '{}'::jsonb END   -- 0627
           ORDER BY i.eta_min, i.vehicle_id), '[]'::jsonb)
    INTO v_inb
    FROM public.ottoq_charge_line_inbound(p_sim_run_id, p_depot_id, p_clock, c_window, v_rt) i
    JOIN vehicles v ON v.id = i.vehicle_id
    -- 0627: the reserve rung the forecast called it home at (ottoq_charge_line_inbound's own)
    CROSS JOIN LATERAL (SELECT CASE WHEN v_rule AND i.source = 'forecast'
                                    THEN COALESCE(public.ottoq_recall_threshold_soc(v.id, p_sim_run_id, p_clock),
                                                  (v_rt #>> '{params,threshold_soc}')::numeric) END AS r) th
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
  -- 0627: the other calls home a car at work can get before its reserve, unless a person has turned it off for this run
  IF v_rule AND COALESCE((v_rt ->> 'usable')::boolean, false) AND (v_rt #>> '{params,drain_pct_per_min}') IS NOT NULL THEN
    v_state := v_state || jsonb_build_object('recall', jsonb_build_object(
      'v', 1, 'return_model', v_rt -> 'estimate_id',
      'lam', round(COALESCE((v_rt #>> '{params,other_per_work_hour}')::numeric, 0) / 60.0, 6),
      'trip_o', COALESCE((v_rt #>> '{params,trip_other_min}')::numeric, (v_rt #>> '{params,trip_min}')::numeric, 0),
      'drain', (v_rt #>> '{params,drain_pct_per_min}')::numeric,
      'asd', COALESCE((v_rt #>> '{params,trip_sd_min}')::numeric, 0)));
  END IF;
  -- 0623: the outflow, unless a person has turned it off for this run
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_outflow', 1), 1) >= 1 THEN
    v_state := public.ottoq_charge_line_outflow(p_sim_run_id, p_depot_id, p_clock, v_state, v_ct, v_rt, v_ev);
  END IF;
  RETURN v_state;
END $fn$;

-- ══ (g) the outflow: each car it sends out turns home at its own reserve rung ════════════════════════════════════
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
   Without them, 0623's state exactly.
   0627: with the run's agent_charge_order_recall_rule dial at 1 (its default), each modelled car carries `thr` in `ret`,
   the reserve rung the kernel's own recall decision calls it home at (ottoq_recall_threshold_soc), and its battery back
   (`rs`) is from there; and the outflow carries `trip_o`, the drive after another call home (the fit's trip_other_min).
   With the dial at 0, 0624's state exactly. */
DECLARE
  v_thr numeric := (p_rt #>> '{params,threshold_soc}')::numeric;
  v_drain numeric := (p_rt #>> '{params,drain_pct_per_min}')::numeric;
  v_trip numeric := COALESCE((p_rt #>> '{params,trip_min}')::numeric, 0);
  v_dw jsonb := p_rt #> '{params,dwell}';
  v_kw_d numeric; v_kw_l numeric;
  v_ids text[]; v_ch jsonb; v_leave jsonb; v_ret jsonb;
  v_dwb jsonb := p_rt #> '{params,dwell_by}'; v_by jsonb; v_cl jsonb; v_here text[];             -- 0624
  v_rule boolean := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'agent_charge_order_recall_rule', 1), 1) >= 1;   -- 0627
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
           'lok', public.ottoq_charge_kind_compatible(v.id, p_depot_id, 'l2'))
           || CASE WHEN th.r IS NOT NULL THEN jsonb_build_object('thr', th.r) ELSE '{}'::jsonb END), '{}'::jsonb)   -- 0627
    INTO v_ret
    FROM vehicles v
    CROSS JOIN LATERAL (SELECT public.ottoq_effective_target_soc_at(v.id, p_clock) AS t) tg
    -- 0627: the reserve rung the kernel's own recall decision calls it home at
    CROSS JOIN LATERAL (SELECT CASE WHEN v_rule THEN public.ottoq_recall_threshold_soc(v.id, p_sim_run_id, p_clock) END AS r) th
    CROSS JOIN LATERAL (SELECT GREATEST(LEAST(COALESCE(th.r, v_thr), tg.t) - v_drain * v_trip, 0) AS s) rs
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
      || CASE WHEN v_by IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('dwell_by', v_by) END
      || CASE WHEN v_rule AND (p_rt #>> '{params,trip_other_min}') IS NOT NULL                    -- 0627
              THEN jsonb_build_object('trip_o', (p_rt #>> '{params,trip_other_min}')::numeric) ELSE '{}'::jsonb END);
END $fn$;

-- ══ (h) the draw: the drive after another call home ════════════════════════════════════════════════════════════
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
   how long it has run, and returned as minutes after the charge's end. Without it, 0623's draw exactly.
   0627: p_out[8], when given, is the drive home after another call (a car called home on stale telemetry or a rider's
   flag is wherever its work took it, not at the reserve's drive); without it, that drive is the reserve's, as 0623. */
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
  v_trip_o float8 := COALESCE(p_out[8], p_out[4], 0); v_te float8;                                 -- 0627
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
  v_out := v_work + v_trip;
  IF v_lam > 0 THEN
    v_u := COALESCE(p_uo, public.ottoq_hash_uniform(v_key || ':other'));
    v_te := -ln(1 - LEAST(v_u, 0.999999)) / v_lam;
    IF v_te < v_work THEN                                     -- 0627: another call first, then its own drive
      v_work := v_te;
      v_out := v_te + v_trip_o;
    END IF;
  END IF;
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

-- ══ (i) the simulator: the other calls home, and each car at its own reserve rung ══════════════════════════════
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
   carries its class (dc). Without dwell_by, 0623's result, key for key.
   0627: with a `recall` block (ottoq_charge_line_state, the run's agent_charge_order_recall_rule dial at 1), a sampled
   future also calls each car at work home on another call, at the depot's rate per minute (lam) and then the drive
   (trip_o), when that comes before its reserve: the car is back with the charge it did not use and owes that much less,
   in proportion, as a returning car's charge is (0623). A car the outflow sends out turns home at its own reserve rung
   (its `thr` in `ret`) and drives trip_o after another call. The expected future keeps each car's median arrival.
   Without the block, a `thr` or a `trip_o`, 0624's result, key for key. */
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
  -- 0627: the other calls home for a car at work
  r_on boolean := COALESCE(jsonb_typeof(p_state -> 'recall') = 'object', false);
  r_lam float8 := 0; r_to float8 := 0; r_dr float8 := 0; v_te float8; v_e0 float8; v_owe float8;
BEGIN
  IF r_on THEN                                                                                     -- 0627
    r_lam := GREATEST(COALESCE((p_state #>> '{recall,lam}')::float8, 0), 0);
    r_to := GREATEST(COALESCE((p_state #>> '{recall,trip_o}')::float8, 0), 0);
    r_dr := GREATEST(COALESCE((p_state #>> '{recall,drain}')::float8, 0), 0);
  END IF;
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
          v_e0 := c_av[n];                                                                         -- 0627: its median
          z := public.ottoq_hash_normal(COALESCE(p_seed, '') || ':' || p_scenario || ':' || c_id[n] || ':arrival');
          c_av[n] := COALESCE((e ->> 'trip')::float8, 0)
                     + GREATEST(c_av[n] - COALESCE((e ->> 'trip')::float8, 0), 0) * exp(COALESCE((e ->> 'esd')::float8, 0) * z);
          -- 0627: or called home first on another call, then the drive: it worked less, so it is back with more charge
          IF r_lam > 0 THEN
            v_te := -ln(1 - LEAST(public.ottoq_hash_uniform(COALESCE(p_seed, '') || ':' || p_scenario || ':' || c_id[n]
                                                            || ':early'), 0.999999)) / r_lam + r_to;
            IF v_te < c_av[n] THEN
              v_owe := GREATEST(c_g[n] - r_dr * GREATEST(v_e0 - v_te, 0), 1);
              c_md[n] := c_md[n] * v_owe / c_g[n];
              c_ml[n] := c_ml[n] * v_owe / c_g[n];
              c_soc[n] := c_soc[n] + (c_g[n] - v_owe);
              c_g[n] := v_owe;
              c_av[n] := v_te;
            END IF;
          END IF;
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
                 (p_state #>> '{outflow,dwell,max_min}')::float8,
                 (p_state #>> '{outflow,trip_o}')::float8];                                      -- 0627: [8], the drive after another call
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
      IF jsonb_typeof(v_r -> 'thr') = 'number' THEN v_pp[1] := (v_r ->> 'thr')::float8; END IF;    -- 0627: its own reserve rung
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

-- ══ (j) the self-review judges arrivals against the forecast the futures make ══════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_arbiter_self_assessment_v3(p_depot_id uuid, p_since timestamptz DEFAULT now() - interval '7 days',
                                                       p_trial boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
SET timezone TO 'UTC'
AS $fn$
/* 0626: the check's self-review, rebuilt so that each place it falls short is ranked by how much of what made the check
   wrong it touches and is said in words a person can act on. 0621's measurements (ottoq_arbiter_self_assessment) and
   0622's calibration stay as they are; the clock is audited within runs (ottoq_charge_clock_audit_v2), its world is
   scanned for a change (0625's ottoq_evidence_regime_scan, and with p_trial a change it names is tried out of sample on
   the latest run since: ottoq_charge_clock_trial), the arrivals' misses are split into the bulk and the tails, and the
   outflow forecast is graded where the orders carried one. Each area carries: area (a stable code), kind, part (the
   part of 0621's Shapley split it belongs to, or none), impact (that part's share of the verdict mass), status (open: to
   act on; built: what it describes was rebuilt after the graded orders were made, so it is history until new orders are
   graded), thin (the evidence is too small to act on), title, finding, action (what a person would build or decide),
   weight (its evidence count), tier (its strength within its part), evidence, and rank. Ranked open before built,
   strong before thin, by impact, then tier, then weight. Read-only; every area is for a person (CLAUDE.md rule 10).
   0627: each arrival is placed in the forecast the futures made of it (ottoq_inbound_arrival_z: with the order's other
   calls home when its state carried them), and orders made without the recall rule (each car at work called home at the
   reserve its returns show on average, with no other call) mark the arrivals built: history until new orders are
   graded. */
DECLARE
  c_tail    constant numeric := 3;
  v_a       jsonb := public.ottoq_arbiter_self_assessment(p_depot_id, p_since);
  v_cal     jsonb := public.ottoq_charge_clock_calibration(p_depot_id, p_since);
  v_aud     jsonb := public.ottoq_charge_clock_audit_v2(p_depot_id, p_since, NULL);
  v_scan    jsonb := public.ottoq_evidence_regime_scan(p_depot_id, NULL, NULL);
  v_now     jsonb := public.ottoq_charge_clock_model(p_depot_id);
  v_n       int;
  v_dec     int;
  v_parts   jsonb;
  v_attr    int;
  v_used    jsonb;
  v_rebuilt text;
  v_arr_built boolean := false;                                                                    -- 0627
  c_arr_note constant text := ' These orders were made before the futures called each car home at its own reserve rung, '
                              'with the other calls home beside it, so this is history until new orders are graded.';
  c_arr_act constant text := 'Grade the next armed run''s orders: the futures now call each car home at its own reserve '
                             'rung, with the other calls home beside it.';
  v_note    text := '';
  v_tails   jsonb;
  v_flow    jsonb;
  v_out     jsonb;
  v_carried int;
  v_trials  jsonb := '{}'::jsonb;
  v_areas   jsonb := '[]'::jsonb;
  v_ranked  jsonb;
  v         jsonb;
  w         jsonb;
  x         record;
  y         record;
  v_title   text;
  v_txt     text;
  v_act     text;
  v_list    text;
  v_status  text;
  v_cur     numeric;
  v_t       timestamptz;
  v_run     record;
  v_mig     jsonb;
  v_cuts    jsonb;
  -- arrivals
  v_nz int; v_ib numeric; v_cm numeric; v_csd numeric; v_e int; v_l int; v_em numeric; v_lm numeric; v_eh numeric;
  v_lh numeric; v_ch numeric; v_heavy boolean; v_narrow boolean; v_wide boolean; v_biased boolean; v_short boolean;
BEGIN
  v_n := COALESCE((v_a ->> 'graded')::int, 0);
  v_dec := COALESCE((v_a ->> 'decisions')::int, 0);
  v_parts := COALESCE(v_a #> '{what_made_the_check_wrong,parts}', '{}'::jsonb);
  v_attr := COALESCE((v_a #>> '{what_made_the_check_wrong,orders_attributed}')::int, 0);

  -- ── the clocks: the one the graded orders were timed by, and the depot's now ──────────────────────────────────────
  SELECT jsonb_build_object(
           'orders', count(*),
           'last_snapshot_at', max(s.recorded_at),
           'models', COALESCE(jsonb_agg(DISTINCT jsonb_build_object(
                       'model', COALESCE(s.state #>> '{models,charge_time_model}', 'charge_time_v1'),
                       'estimate_id', s.state #> '{models,charge_time}')), '[]'::jsonb),
           'last_model', (array_agg(COALESCE(s.state #>> '{models,charge_time_model}', 'charge_time_v1')
                                    ORDER BY s.recorded_at DESC))[1])
    INTO v_used
    FROM public.ottoq_charge_order_hindsight h JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
   WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since;
  IF v_n > 0 AND v_now IS NOT NULL THEN
    IF v_used ->> 'last_model' IS DISTINCT FROM v_now ->> 'model' THEN
      v_rebuilt := 'model';
      v_note := ' These orders were timed by an earlier charge clock, since replaced by one learned per car, so this is '
                'history until new orders are graded.';
    ELSIF EXISTS (SELECT 1 FROM public.ottoq_evidence_regimes r
                   WHERE r.model = v_now ->> 'model' AND (r.depot_id IS NULL OR r.depot_id = p_depot_id)
                     AND r.recorded_at > (v_used ->> 'last_snapshot_at')::timestamptz
                     AND r.recorded_at <= (v_now ->> 'fitted_at')::timestamptz) THEN
      v_rebuilt := 'regime';
      v_note := ' Since these orders, a change in the charge clock''s world was recorded and the clock refitted to it, so '
                'this is history until new orders are graded.';
    END IF;
  END IF;

  -- ── the arrivals: the bulk and the tails (0621's z: the real time to the reserve over the forecast, in its spreads) ─
  WITH h AS (
    SELECT h.realized, s.state
      FROM public.ottoq_charge_order_hindsight h JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
     WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since
  ), ar AS (
    SELECT ib.value AS e, h.state -> 'recall' AS rc,
           ib.value ->> 'src' AS src, (ib.value ->> 'eta')::numeric AS fc, COALESCE((ib.value ->> 'trip')::numeric, 0) AS trip,
           COALESCE((ib.value ->> 'esd')::numeric, 0) AS esd,
           COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false) AS arrived,
           (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::numeric AS act
      FROM h CROSS JOIN LATERAL jsonb_array_elements(COALESCE(h.state -> 'inbound', '[]'::jsonb)) ib
  ), z AS (
    -- 0627: where each arrival fell in the forecast the futures made of it, the other calls home included when the
    -- order's state carried them (ottoq_inbound_arrival_z; without them 0621's z)
    SELECT ar.act - ar.fc AS err, ar.fc - ar.trip AS hz,
           public.ottoq_inbound_arrival_z(ar.e, ar.rc, ar.act::float8)::numeric AS z
      FROM ar WHERE ar.arrived AND ar.src = 'forecast' AND ar.esd > 0 AND ar.act > ar.trip AND ar.fc > ar.trip
  )
  SELECT jsonb_build_object(
           'n', count(*),
           'in_80pct_band', round(count(*) FILTER (WHERE abs(z.z) <= 1.2816)::numeric / NULLIF(count(*), 0), 3),
           'tail_at', c_tail,
           'bulk', jsonb_build_object(
             'n', count(*) FILTER (WHERE abs(z.z) <= c_tail),
             'mean_z', round(avg(z.z) FILTER (WHERE abs(z.z) <= c_tail), 3),
             'sd_z', round(stddev_samp(z.z) FILTER (WHERE abs(z.z) <= c_tail), 3),
             'mean_minutes_to_reserve', round(avg(z.hz) FILTER (WHERE abs(z.z) <= c_tail), 1)),
           'early', jsonb_build_object(
             'n', count(*) FILTER (WHERE z.z < -c_tail),
             'mean_minutes', round(avg(z.err) FILTER (WHERE z.z < -c_tail), 1),
             'mean_minutes_to_reserve', round(avg(z.hz) FILTER (WHERE z.z < -c_tail), 1)),
           'late', jsonb_build_object(
             'n', count(*) FILTER (WHERE z.z > c_tail),
             'mean_minutes', round(avg(z.err) FILTER (WHERE z.z > c_tail), 1),
             'mean_minutes_to_reserve', round(avg(z.hz) FILTER (WHERE z.z > c_tail), 1)))
    INTO v_tails FROM z;
  -- 0627: orders made without the recall rule (before 0627, or with its dial off) forecast each car at work at the reserve
  -- its returns show on average, with no other call home: their arrivals are history until new orders are graded
  v_arr_built := to_regprocedure('public.ottoq_recall_threshold_soc(uuid,uuid,timestamp with time zone)') IS NOT NULL
                 AND NOT EXISTS (SELECT 1 FROM public.ottoq_charge_order_hindsight h
                                   JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
                                  WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since
                                    AND jsonb_typeof(s.state -> 'recall') = 'object');

  -- ── the outflow forecast's grade, summed over the orders that carried one (0623/0624) ─────────────────────────────
  WITH o AS (
    SELECT h.forecast -> 'outflow' AS o FROM public.ottoq_charge_order_hindsight h
     WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since
       AND jsonb_typeof(h.forecast -> 'outflow') = 'object'
  )
  SELECT jsonb_build_object(
           'orders', count(*),
           'modelled', COALESCE(sum((o.o ->> 'modelled')::numeric), 0), 'real', COALESCE(sum((o.o ->> 'real')::numeric), 0),
           'hits', COALESCE(sum((o.o ->> 'hits')::numeric), 0),
           'unseen', COALESCE(sum((o.o ->> 'unseen')::numeric), 0),
           'unseen_returned', COALESCE(sum((o.o ->> 'unseen_returned')::numeric), 0),
           'dwell', jsonb_build_object(
             'seen', COALESCE(sum((o.o #>> '{dwell,seen}')::numeric), 0), 'left', COALESCE(sum((o.o #>> '{dwell,left}')::numeric), 0),
             'p_left', round(COALESCE(sum((o.o #>> '{dwell,p_left}')::numeric), 0), 2),
             'brier', round(COALESCE(sum((o.o #>> '{dwell,brier}')::numeric), 0), 3),
             'pit_n', COALESCE(sum((o.o #>> '{dwell,pit_n}')::numeric), 0),
             'pit50', COALESCE(sum((o.o #>> '{dwell,pit50}')::numeric), 0),
             'pit80', COALESCE(sum((o.o #>> '{dwell,pit80}')::numeric), 0)),
           'dwell_pooled_brier', round(sum((o.o #>> '{dwell_pooled,brier}')::numeric), 3),
           'dwell_by', (SELECT COALESCE(jsonb_object_agg(c.k, c.j), '{}'::jsonb) FROM (
                          SELECT c.key AS k, jsonb_build_object(
                                   'seen', sum((c.value ->> 'seen')::numeric), 'left', sum((c.value ->> 'left')::numeric),
                                   'p_left', round(sum((c.value ->> 'p_left')::numeric), 2),
                                   'brier', round(sum((c.value ->> 'brier')::numeric), 3),
                                   'brier_pooled', round(sum((c.value ->> 'brier_pooled')::numeric), 3)) AS j
                            FROM o CROSS JOIN LATERAL jsonb_each(CASE WHEN jsonb_typeof(o.o -> 'dwell_by') = 'object'
                                                                      THEN o.o -> 'dwell_by' ELSE '{}'::jsonb END) c
                           GROUP BY c.key) c))
    INTO v_flow FROM o;
  v_carried := COALESCE((v_flow ->> 'orders')::int, 0);

  -- ── 0622's count of the cars that came home unseen: had they left after the order? ────────────────────────────────
  SELECT jsonb_build_object(
           'orders', count(DISTINCT h.order_id), 'appeared_returned', count(*),
           'per_order', round(count(*)::numeric / NULLIF(count(DISTINCT h.order_id), 0), 2),
           'left_after_the_order', count(*) FILTER (WHERE d.dispatched_at > h.sim_clock),
           'left_before', count(*) FILTER (WHERE d.dispatched_at <= h.sim_clock),
           'dispatch_not_found', count(*) FILTER (WHERE d.dispatched_at IS NULL),
           'mean_eta_min', round(avg((ap.value ->> 'eta')::numeric), 1))
    INTO v_out
    FROM public.ottoq_charge_order_hindsight h
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(h.realized -> 'appeared', '[]'::jsonb)) ap
    LEFT JOIN LATERAL (SELECT dd.dispatched_at FROM public.ottoq_vehicle_dispatches dd
                        WHERE dd.sim_run_id = h.sim_run_id AND dd.vehicle_id::text = ap.value ->> 'id'
                          AND dd.actual_return_at > h.sim_clock
                          AND dd.actual_return_at <= h.sim_clock + make_interval(secs => h.observed_min * 60)
                        ORDER BY dd.actual_return_at LIMIT 1) d ON true
   WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since AND ap.value ->> 'how' = 'returned';

  -- ══ the areas ══════════════════════════════════════════════════════════════════════════════════════════════════════

  -- (1) when cars came home: the bulk against the tails
  v_nz := COALESCE((v_tails ->> 'n')::int, 0);
  IF v_nz >= 30 THEN
    v_ib := (v_tails ->> 'in_80pct_band')::numeric;
    v_cm := COALESCE((v_tails #>> '{bulk,mean_z}')::numeric, 0);
    v_csd := COALESCE((v_tails #>> '{bulk,sd_z}')::numeric, 1);
    v_e := COALESCE((v_tails #>> '{early,n}')::int, 0);
    v_l := COALESCE((v_tails #>> '{late,n}')::int, 0);
    v_em := (v_tails #>> '{early,mean_minutes}')::numeric;
    v_lm := (v_tails #>> '{late,mean_minutes}')::numeric;
    v_eh := (v_tails #>> '{early,mean_minutes_to_reserve}')::numeric;
    v_lh := (v_tails #>> '{late,mean_minutes_to_reserve}')::numeric;
    v_ch := (v_tails #>> '{bulk,mean_minutes_to_reserve}')::numeric;
    v_narrow := v_ib < 0.6 OR v_csd > 1.5;                     -- too narrow throughout: the band misses everywhere
    v_wide := v_ib > 0.92 AND v_csd < 0.67;
    v_biased := abs(v_cm) > 0.5;
    v_heavy := (v_e + v_l)::numeric / v_nz >= 0.01 AND v_ib >= 0.7 AND NOT v_narrow;   -- a normal spread puts 0.27% past 3
    v_short := v_l::numeric / v_nz >= 0.005 AND v_lh < 0.6 * v_ch;
    IF v_heavy OR v_narrow OR v_wide OR v_biased THEN
      v_title := CASE WHEN v_biased THEN 'Cars come home ' || CASE WHEN v_cm > 0 THEN 'later' ELSE 'earlier' END
                                         || ' than it forecasts'
                      WHEN v_narrow THEN 'Cars come home with more spread than its futures sample'
                      WHEN v_wide THEN 'Its futures spread the arrivals wider than they come'
                      ELSE 'A few cars come home far from their forecast' END;
      v_txt := round(100 * v_ib) || '% of the ' || to_char(v_nz, 'FM999,999,990') || ' cars it expected home arrived inside the 80% band its futures '
               || 'sample, against 80%. '
               || CASE WHEN v_narrow THEN 'Arrivals spread wider than the futures sample: within 3 of their spreads, '
                                          || v_csd || ' times as wide, and ' || round(100.0 * (v_e + v_l) / v_nz, 1)
                                          || '% further out. '
                       WHEN v_wide THEN 'The futures sample a wider spread than arrivals show: ' || v_csd || ' times as wide. '
                       ELSE 'The bulk is as wide as the futures sample (' || v_csd || ' of their spread). ' END
               || CASE WHEN v_biased THEN 'The bulk comes ' || abs(round(v_cm, 2)) || ' spreads '
                                          || CASE WHEN v_cm > 0 THEN 'late' ELSE 'early' END || '. ' ELSE '' END
               || CASE WHEN v_heavy THEN 'The misses are in the tails: ' || v_e || ' cars ('
                                         || round(100.0 * v_e / v_nz, 1) || '%) came home a mean ' || abs(COALESCE(v_em, 0))
                                         || ' minutes early, before their battery reached the reserve, and ' || v_l || ' ('
                                         || round(100.0 * v_l / v_nz, 1) || '%) a mean ' || COALESCE(v_lm, 0) || ' minutes late.'
                       ELSE '' END
               || CASE WHEN v_heavy AND v_short THEN ' The late ones were on short trips, a mean ' || v_lh || ' minutes from '
                                                     || 'the reserve against ' || v_ch || ' for the rest: the futures spread a '
                                                     || 'return in proportion to the trip, so a few minutes'' delay on a short '
                                                     || 'one reads as far off.'
                       ELSE '' END;
      v_act := array_to_string(ARRAY[
                 CASE WHEN v_heavy AND v_e::numeric / v_nz >= 0.005
                      THEN 'sample an early call home in the futures, at the rate the depot''s own returns show' END,
                 CASE WHEN v_heavy AND v_short THEN 'add a delay in minutes to each return, not only a share of the trip' END,
                 CASE WHEN v_narrow THEN 'widen the futures'' return spread to what arrivals show' END,
                 CASE WHEN v_wide THEN 'narrow the futures'' return spread to what arrivals show' END,
                 CASE WHEN v_biased THEN 'refit the drain; if it persists, the return forecast misses a variable' END], '; ');
      v_areas := v_areas || jsonb_build_object(
        'area', 'arrival_spread', 'kind', CASE WHEN v_heavy AND NOT (v_narrow OR v_wide OR v_biased) THEN 'capability_gap'
                                               ELSE 'calibration' END,
        'part', 'arrivals', 'status', CASE WHEN v_arr_built THEN 'built' ELSE 'open' END, 'thin', false, 'tier', 2,
        'weight', v_nz,
        'title', v_title, 'finding', v_txt || CASE WHEN v_arr_built THEN c_arr_note ELSE '' END,
        'action', CASE WHEN v_arr_built THEN c_arr_act ELSE upper(left(v_act, 1)) || substr(v_act, 2) || '.' END,
        'evidence', v_tails || jsonb_build_object('summed', v_a #> '{forecasts,arrivals}'));
    END IF;
  END IF;

  -- (2) the charge clock: calibration of the forecasts the orders were made with, by kind with the makes that were off
  FOR x IN SELECT c.key AS k, c.value AS j FROM jsonb_each(COALESCE(v_cal -> 'by_kind', '{}'::jsonb)) c
            WHERE (c.value ->> 'charges')::int >= 10 ORDER BY c.key
  LOOP
    SELECT string_agg(public.ottoq_review_words('class', split_part(c.key, '|', 2)) || ' '
                      || public.ottoq_review_change((c.value ->> 'factor_off_by')::numeric)
                      || ' (' || (c.value ->> 'finished') || ')', ', '
                      ORDER BY abs(ln(COALESCE(NULLIF((c.value ->> 'factor_off_by')::numeric, 0), 1))) DESC, c.key)
      INTO v_list
      FROM jsonb_each(COALESCE(v_cal -> 'by_class', '{}'::jsonb)) c
     WHERE split_part(c.key, '|', 1) = x.k AND split_part(c.key, '|', 2) <> '?' AND (c.value ->> 'finished')::int >= 10
       AND abs(COALESCE((c.value ->> 'z_mean')::numeric, 0)) > 0.5;
    v_cur := COALESCE(NULLIF((x.j ->> 'factor_off_by')::numeric, 0), 1);
    IF abs(ln(v_cur)) > 0.15 OR COALESCE((x.j ->> 'z_sd')::numeric, 0) > 1.5
       OR COALESCE((x.j ->> 'in_80pct_band')::numeric, 1) < 0.6 OR v_list IS NOT NULL THEN
      v_areas := v_areas || jsonb_build_object(
        'area', 'charge_clock_' || x.k, 'kind', 'calibration', 'part', 'charge_times',
        'status', CASE WHEN v_rebuilt IS NULL THEN 'open' ELSE 'built' END,
        'thin', (x.j ->> 'charges')::int < 30, 'tier', 3, 'weight', (x.j ->> 'charges')::int,
        'title', CASE WHEN abs(ln(v_cur)) > 0.15
                      THEN 'Charges on ' || public.ottoq_review_words('kind', x.k) || ' ran '
                           || public.ottoq_review_change(v_cur) || ' than it forecast'
                      WHEN COALESCE((x.j ->> 'z_sd')::numeric, 0) > 1.5 OR COALESCE((x.j ->> 'in_80pct_band')::numeric, 1) < 0.6
                      THEN 'Its charge forecasts on ' || public.ottoq_review_words('kind', x.k) || ' were surer than the charges'
                      ELSE 'Some makes'' charges on ' || public.ottoq_review_words('kind', x.k) || ' ran off its forecast' END,
        'finding', 'On ' || (x.j ->> 'charges') || ' charges on ' || public.ottoq_review_words('kind', x.k)
                   || ' (the check''s last forecast before each began), they ran ' || public.ottoq_review_change(v_cur)
                   || ' than forecast; ' || round(100 * COALESCE((x.j ->> 'in_80pct_band')::numeric, 0))
                   || '% fell inside its 80% band, and ' || (x.j ->> 'overran') || ' ran past its 90th percentile.'
                   || CASE WHEN v_list IS NOT NULL THEN ' By make: ' || v_list || '.' ELSE '' END || v_note,
        'action', CASE WHEN v_rebuilt IS NOT NULL THEN 'Nothing until orders timed by the rebuilt clock are graded.'
                       ELSE 'The nightly refit absorbs a level that moved; if this persists, the clock''s audit names the variable it misses.' END,
        'evidence', x.j || jsonb_build_object('classes', (SELECT jsonb_object_agg(c.key, c.value)
                                                            FROM jsonb_each(COALESCE(v_cal -> 'by_class', '{}'::jsonb)) c
                                                           WHERE split_part(c.key, '|', 1) = x.k)));
    END IF;
  END LOOP;

  -- (3) the charge clock now: what it leaves once it knows the run (0626's audit), merged across kinds per covariate
  -- (a modelled level is judged within runs; a variable with no level beyond the levels the clock has, so that a proxy
  -- for one of them is not named for it)
  FOR x IN SELECT c.value ->> 'covariate' AS cov, (c.value ->> 'modelled')::boolean AS md,
                  jsonb_agg(jsonb_build_object('kind', k.key, 'charges', (k.value ->> 'charges')::int, 'share', s.sh,
                                               'adj_eta2_within', c.value -> 'adj_eta2_within', 'adj_eta2', c.value -> 'adj_eta2',
                                               'adj_eta2_beyond', c.value -> 'adj_eta2_beyond',
                                               'worst_groups', c.value -> 'worst_groups')
                            ORDER BY s.sh DESC, k.key) AS by_kind,
                  string_agg(round(100 * s.sh) || '% of what it leaves on ' || public.ottoq_review_words('kind', k.key),
                             ' and ' ORDER BY s.sh DESC, k.key) AS said,
                  sum((k.value ->> 'charges')::int) AS n,
                  max(s.sh) AS top
             FROM jsonb_each(COALESCE(v_aud -> 'by_kind', '{}'::jsonb)) k
             CROSS JOIN LATERAL jsonb_array_elements(COALESCE(k.value -> 'covariates', '[]'::jsonb)) c
             CROSS JOIN LATERAL (SELECT CASE WHEN (c.value ->> 'modelled')::boolean
                                             THEN (c.value ->> 'adj_eta2_within')::numeric
                                             ELSE LEAST((c.value ->> 'adj_eta2_within')::numeric,
                                                        (c.value ->> 'adj_eta2_beyond')::numeric) END AS sh) s
            WHERE (k.value ->> 'charges')::int >= 30 AND c.value ->> 'covariate' NOT IN ('run', 'ambient_c')
              AND COALESCE(s.sh, 0) >= 0.05
            GROUP BY 1, 2 ORDER BY 1
  LOOP
    w := x.by_kind -> 0 -> 'worst_groups' -> 0;
    v_areas := v_areas || jsonb_build_object(
      'area', CASE WHEN x.md THEN 'charge_clock_stale_' ELSE 'charge_clock_misses_' END || x.cov,
      'kind', CASE WHEN x.md THEN 'calibration' ELSE 'capability_gap' END, 'part', 'charge_times',
      'status', 'open', 'thin', false, 'tier', 2, 'weight', round(x.n * x.top),
      'title', CASE WHEN x.md THEN 'The charge clock''s level for ' || public.ottoq_review_words('covariate', x.cov) || ' has drifted'
                    ELSE 'The charge clock does not see ' || public.ottoq_review_words('covariate', x.cov) END,
      'finding', CASE WHEN x.md
                      THEN 'The clock learns ' || public.ottoq_review_words('covariate', x.cov) || ', yet once it knows the run, '
                           || public.ottoq_review_words('covariate', x.cov) || ' still explains ' || x.said || '.'
                      ELSE 'Beyond the run and the levels the clock has, ' || public.ottoq_review_words('covariate', x.cov)
                           || ' still explains ' || x.said || ', and the clock has no level for it.' END
                 || CASE WHEN x.cov IN ('class', 'model') AND w IS NOT NULL AND jsonb_typeof(w -> 'mean_log_error_within_run') = 'number'
                         THEN ' Most off: ' || CASE WHEN x.cov = 'class' THEN public.ottoq_review_words('class', w ->> 'group')
                                                    ELSE replace(w ->> 'group', '|', ' ') END
                              || ' charges ran ' || public.ottoq_review_change(exp((w ->> 'mean_log_error_within_run')::numeric))
                              || ' than it says.'
                         ELSE '' END,
      'action', CASE WHEN x.md THEN 'The nightly refit should absorb it; if it lasts more than a few nights, the clock''s world '
                                    || 'has likely changed: see whether the scan names a change.'
                     ELSE 'Give the clock a level for ' || public.ottoq_review_words('covariate', x.cov) || ', fitted within runs.' END,
      'evidence', jsonb_build_object('covariate', x.cov, 'modelled', x.md, 'by_kind', x.by_kind));
  END LOOP;

  -- (3b) air temperature, which moves with the run: a slope within runs, and between them
  SELECT jsonb_agg(jsonb_build_object('kind', k.key, 'charges', (k.value ->> 'charges')::int) || (k.value -> 'air_temperature')
                   ORDER BY k.key),
         string_agg(public.ottoq_review_words('kind', k.key) || ' ran '
                    || CASE WHEN s.bb IS NOT NULL AND COALESCE(s.ru, 0) >= 2
                            THEN public.ottoq_review_change(exp(s.bb), 'shorter', 'longer', 1)
                                 || ' for each degree warmer between runs (' || s.ru
                                 || ' runs averaging ' || (k.value #>> '{air_temperature,between,run_mean_c,0}') || ' to '
                                 || (k.value #>> '{air_temperature,between,run_mean_c,1}') || ' °C, R² '
                                 || (k.value #>> '{air_temperature,between,r2}') || ') and '
                                 || public.ottoq_review_change(exp(s.bw), 'shorter', 'longer', 1) || ' within them (t ' || s.tw || ')'
                            ELSE public.ottoq_review_change(exp(s.bw), 'shorter', 'longer', 1)
                                 || ' for each degree warmer within runs (t ' || s.tw || ')' END,
                    '; ' ORDER BY k.key),
         sum((k.value ->> 'charges')::int)
    INTO v, v_list, v_cur
    FROM jsonb_each(COALESCE(v_aud -> 'by_kind', '{}'::jsonb)) k
    CROSS JOIN LATERAL (SELECT (k.value #>> '{air_temperature,within,per_degree}')::numeric AS bw,
                               (k.value #>> '{air_temperature,within,t}')::numeric AS tw,
                               (k.value #>> '{air_temperature,within,sd_c}')::numeric AS sdw,
                               (k.value #>> '{air_temperature,between,per_degree}')::numeric AS bb,
                               (k.value #>> '{air_temperature,between,r2}')::numeric AS r2,
                               (k.value #>> '{air_temperature,between,runs}')::int AS ru,
                               (k.value #>> '{air_temperature,between,run_mean_c,1}')::numeric
                                 - (k.value #>> '{air_temperature,between,run_mean_c,0}')::numeric AS span) s
   WHERE (k.value ->> 'charges')::int >= 30 AND s.bw IS NOT NULL AND s.tw IS NOT NULL
     AND (abs(s.tw) >= 3 OR (COALESCE(s.ru, 0) >= 6 AND COALESCE(s.r2, 0) >= 0.5 AND sign(s.bb) = sign(s.bw) AND abs(s.tw) >= 2))
     -- the effect across what the depot saw: the runs' mean temperatures, or the spread within runs (10th to 90th)
     AND GREATEST(abs(COALESCE(s.bb, 0)) * COALESCE(s.span, 0), abs(s.bw) * 2.5631 * COALESCE(s.sdw, 0)) >= 0.05;
  IF v IS NOT NULL THEN
    v_areas := v_areas || jsonb_build_object(
      'area', 'charge_clock_misses_air_temperature', 'kind', 'capability_gap', 'part', 'charge_times',
      'status', 'open', 'thin', false, 'tier', 2, 'weight', v_cur,
      'title', 'The charge clock does not see the air temperature',
      'finding', 'Charges on ' || v_list || '. The clock has no level for the air temperature, so it learns a run''s level '
                 || 'only from that run''s own charges, and a run''s first charges are timed as if every day were the same.',
      'action', 'Give the clock a level for the air temperature, fitted within runs, so it knows a run''s level before its '
                || 'first charge.',
      'evidence', jsonb_build_object('by_kind', v));
  END IF;

  -- (3c) the clock out of sample against the one it replaced, and its band
  FOR x IN SELECT k.key AS k, k.value AS j FROM jsonb_each(COALESCE(v_aud -> 'by_kind', '{}'::jsonb)) k
            WHERE (k.value ->> 'charges')::int >= 30 ORDER BY k.key
  LOOP
    IF (x.j ->> 'out_of_sample')::boolean
       AND (x.j #>> '{clock,mean_abs_log_error}')::numeric > (x.j #>> '{v1,mean_abs_log_error}')::numeric THEN
      v_areas := v_areas || jsonb_build_object(
        'area', 'charge_clock_worse_than_v1_' || x.k, 'kind', 'calibration', 'part', 'charge_times',
        'status', 'open', 'thin', false, 'tier', 2, 'weight', (x.j ->> 'charges')::int,
        'title', 'The charge clock does worse than the one before it on ' || public.ottoq_review_words('kind', x.k),
        'finding', 'On ' || (x.j ->> 'charges') || ' charges on ' || public.ottoq_review_words('kind', x.k)
                   || ' recorded since it was fitted, the clock misses by a mean '
                   || round(100 * (x.j #>> '{clock,mean_abs_log_error}')::numeric, 1) || '% against '
                   || round(100 * (x.j #>> '{v1,mean_abs_log_error}')::numeric, 1) || '% for the clock it replaced.',
        'action', 'Find the level that is fitting noise or has gone stale: the audit''s covariates, and the scan.',
        'evidence', x.j - 'covariates' - 'air_temperature');
    END IF;
    IF COALESCE((x.j #>> '{clock,in_80pct_band}')::numeric, 0.8) < 0.7
       AND COALESCE((x.j #>> '{clock,in_80pct_band_within_run}')::numeric, 0.8) < 0.7 THEN
      v_areas := v_areas || jsonb_build_object(
        'area', 'charge_clock_band_' || x.k, 'kind', 'calibration', 'part', 'charge_times',
        'status', 'open', 'thin', false, 'tier', 2, 'weight', (x.j ->> 'charges')::int,
        'title', 'The charge clock is surer than the charges on ' || public.ottoq_review_words('kind', x.k),
        'finding', round(100 * (x.j #>> '{clock,in_80pct_band}')::numeric) || '% of ' || (x.j ->> 'charges')
                   || ' charges on ' || public.ottoq_review_words('kind', x.k) || ' fell inside the clock''s 80% band, and '
                   || round(100 * (x.j #>> '{clock,in_80pct_band_within_run}')::numeric)
                   || '% once it knows the run: the futures sample charge times narrower than they come.',
        'action', 'Widen the clock''s spread on ' || public.ottoq_review_words('kind', x.k) || ' to what its own residuals show.',
        'evidence', x.j - 'covariates' - 'air_temperature');
    END IF;
  END LOOP;

  -- (4) the clock's world: a change the scan names, tried out of sample on the latest run since (p_trial)
  FOR x IN SELECT k.key AS k, k.value AS j FROM jsonb_each(COALESCE(v_scan -> 'by_kind', '{}'::jsonb)) k
            WHERE COALESCE((k.value ->> 'named')::boolean, false) ORDER BY k.key
  LOOP
    SELECT m.value INTO v_mig
      FROM jsonb_array_elements(COALESCE(x.j #> '{split,migrations}', '[]'::jsonb)) m
     WHERE COALESCE((m.value ->> 'charging')::boolean, false)
     ORDER BY m.value ->> 'version' DESC LIMIT 1;
    v_t := COALESCE(CASE WHEN v_mig ->> 'version' ~ '^\d{14}$' THEN to_timestamp(v_mig ->> 'version', 'YYYYMMDDHH24MISS') END,
                    (x.j #>> '{split,window,1}')::timestamptz);
    SELECT string_agg(public.ottoq_review_words('class', c.key) || ' '
                      || public.ottoq_review_change(exp((c.value ->> 'shift')::numeric)), ', '
                      ORDER BY abs((c.value ->> 'shift')::numeric) DESC, c.key)
      INTO v_list
      FROM jsonb_each(COALESCE(x.j #> '{split,classes}', '{}'::jsonb)) c
     WHERE abs((c.value ->> 'shift')::numeric) >= 0.05;
    v := NULL;
    IF p_trial AND v_t IS NOT NULL THEN
      SELECT r.sim_run_id, r.started_at INTO v_run
        FROM public.ottoq_sim_runs r
       WHERE r.depot_id = p_depot_id AND r.status = 'completed' AND r.started_at > v_t
         AND (SELECT count(*) FROM public.ottoq_charge_duration_ledger l
               WHERE l.sim_run_id = r.sim_run_id AND l.charger_type = x.k AND l.stopped_reason = 'completed') >= 10
       ORDER BY r.started_at DESC LIMIT 1;
      IF FOUND THEN
        v_cuts := public.ottoq_evidence_regime_cuts('charge_time_v2', p_depot_id, v_run.started_at - interval '21 days',
                                                    v_run.started_at);
        v := public.ottoq_charge_clock_trial(p_depot_id, ARRAY[v_run.sim_run_id], v_run.started_at, v_cuts,
                                             v_cuts || jsonb_build_object(x.k, v_t), false);
        v_trials := v_trials || jsonb_build_object(x.k, v);
      ELSE
        v_trials := v_trials || jsonb_build_object(x.k, jsonb_build_object('skipped', 'no completed run since the change with 10 '
                                                                             || 'or more completed charges of the kind'));
      END IF;
    END IF;
    v_txt := 'Between ' || public.ottoq_review_ct((x.j #>> '{split,between,0}')::timestamptz) || ' and '
             || public.ottoq_review_ct((x.j #>> '{split,between,1}')::timestamptz) || ', charges on '
             || public.ottoq_review_words('kind', x.k) || ' changed: ' || COALESCE(v_list, 'every class moved a little')
             || ', against what the clock says (' || (x.j #>> '{split,q}') || ' on ' || (x.j #>> '{split,df}')
             || ' classes, where 10 a class names a change). The clock still learns from both sides of it. '
             || jsonb_array_length(COALESCE(x.j #> '{split,migrations}', '[]'::jsonb))
             || ' changes to the engine were applied in that window, '
             || (SELECT count(*) FROM jsonb_array_elements(COALESCE(x.j #> '{split,migrations}', '[]'::jsonb)) m
                  WHERE COALESCE((m.value ->> 'charging')::boolean, false)) || ' of them to how charging works.'
             || CASE WHEN v IS NULL THEN ''
                     WHEN NOT COALESCE((v #>> ARRAY['regimes_b', x.k, 'applied'])::boolean, false)
                     THEN ' Too few charges since ' || public.ottoq_review_ct(v_t) || ' to fit the clock on them alone yet.'
                     ELSE ' Fitted only on what came after ' || public.ottoq_review_ct(v_t) || ', the clock''s mean miss on the '
                          || 'latest run''s ' || (v #>> ARRAY['by_kind', x.k, 'charges']) || ' charges on '
                          || public.ottoq_review_words('kind', x.k) || ' would go from '
                          || round(100 * (v #>> ARRAY['by_kind', x.k, 'mae_a'])::numeric, 1) || '% to '
                          || round(100 * (v #>> ARRAY['by_kind', x.k, 'mae_b'])::numeric, 1) || '%.' END;
    v_act := CASE WHEN v IS NOT NULL AND COALESCE((v #>> ARRAY['regimes_b', x.k, 'applied'])::boolean, false)
                       AND (v #>> ARRAY['by_kind', x.k, 'mae_b'])::numeric >= (v #>> ARRAY['by_kind', x.k, 'mae_a'])::numeric
                  THEN 'A cut at ' || public.ottoq_review_ct(v_t) || ' would not help the latest run: look for the variable '
                       || 'that moved instead of recording a change.'
                  ELSE 'If a change in the engine explains it, record it for ' || public.ottoq_review_words('kind', x.k)
                       || ' from ' || public.ottoq_review_ct(v_t) || ': the clock learns from it that night.' END;
    v_areas := v_areas || jsonb_build_object(
      'area', 'charge_clock_world_changed_' || x.k, 'kind', 'world_changed', 'part', 'charge_times',
      'status', 'open', 'thin', false, 'tier', 1, 'weight', (x.j ->> 'charges')::int,
      'title', 'The charge clock''s world changed on ' || public.ottoq_review_words('kind', x.k),
      'finding', v_txt, 'action', v_act,
      'evidence', jsonb_build_object('scan', x.j, 'trial', v,
                                     'record', jsonb_build_object('model', 'charge_time_v2', 'scope', x.k, 'depot_id', p_depot_id,
                                                                  'starts_at', v_t,
                                                                  'source', COALESCE('migration ' || (v_mig ->> 'version') || ' '
                                                                                     || (v_mig ->> 'name'), 'the scan''s window'))));
  END LOOP;

  -- (5) charges already under way at the order
  IF COALESCE((v_parts #>> '{running,verdict_mass}')::numeric, 0) >= 1 AND COALESCE((v_parts #>> '{running,orders_moved}')::int, 0) >= 1 THEN
    v := v_a #> '{forecasts,running}';
    v_cur := COALESCE((v ->> 'mean_err_min')::numeric, 0);
    v_areas := v_areas || jsonb_build_object(
      'area', 'forecast_running', 'kind', 'forecast', 'part', 'running',
      'status', CASE WHEN v_rebuilt IS NULL THEN 'open' ELSE 'built' END, 'thin', false, 'tier', 2,
      'weight', (v_parts #>> '{running,orders_moved}')::int,
      'title', CASE WHEN abs(v_cur) >= 2 THEN 'Charges under way ended ' || CASE WHEN v_cur < 0 THEN 'sooner' ELSE 'later' END
                                              || ' than it expected'
                    ELSE 'Charges already under way moved its verdicts' END,
      'finding', 'Charges already under way at the order explain ' || round(100 * (v_parts #>> '{running,verdict_share}')::numeric)
                 || '% of what made its verdicts wrong and moved ' || (v_parts #>> '{running,orders_moved}') || ' of '
                 || v_attr || '. They ended a mean ' || abs(v_cur) || ' minutes '
                 || CASE WHEN v_cur < 0 THEN 'sooner' ELSE 'later' END || ' than it expected, missing by a mean '
                 || COALESCE(v ->> 'mae_min', '?') || ' minutes over '
                 || COALESCE(to_char((v ->> 'n')::numeric, 'FM999,999,990'), '?') || ' charges.' || v_note,
      'action', CASE WHEN v_rebuilt IS NOT NULL THEN 'Nothing until orders timed by the rebuilt clock are graded.'
                     ELSE 'Measure how much of a charge''s remaining part its done part predicts, by kind of charger, and '
                          || 'whether the clock''s level for the car was right.' END,
      'evidence', jsonb_build_object('part', v_parts -> 'running', 'forecast', v));
  END IF;

  -- (6) cars it never saw coming: the outflow's grade where the orders carried one, else the 0622 count
  IF v_carried >= 10 THEN
    v := v_flow -> 'dwell';
    -- departures: expected against real
    IF (v ->> 'seen')::numeric >= 30 AND (v ->> 'p_left')::numeric > 0
       AND abs(ln(GREATEST((v ->> 'left')::numeric, 0.5) / (v ->> 'p_left')::numeric)) > 0.15 THEN
      v_cur := (v ->> 'left')::numeric / (v ->> 'p_left')::numeric;
      v_areas := v_areas || jsonb_build_object(
        'area', 'outflow_departures', 'kind', 'calibration', 'part', 'appeared', 'status', 'open', 'thin', false, 'tier', 2,
        'weight', (v ->> 'seen')::int,
        'title', CASE WHEN v_cur > 1 THEN 'More charged cars left than it expected' ELSE 'Fewer charged cars left than it expected' END,
        'finding', 'Of ' || (v ->> 'seen') || ' charged cars it modelled, it expected ' || round((v ->> 'p_left')::numeric)
                   || ' to leave inside their windows and ' || (v ->> 'left') || ' did (' || round(v_cur, 2) || ' of expected).',
        'action', 'The dwell curves are refit nightly; if this persists, condition the dwell on the hour''s demand.',
        'evidence', v_flow - 'dwell_by');
    END IF;
    -- whether a car leaves: against the base rate
    IF (v ->> 'seen')::numeric >= 30
       AND (v ->> 'brier')::numeric / (v ->> 'seen')::numeric
           >= ((v ->> 'left')::numeric / (v ->> 'seen')::numeric) * (1 - (v ->> 'left')::numeric / (v ->> 'seen')::numeric) THEN
      v_areas := v_areas || jsonb_build_object(
        'area', 'outflow_dwell_base_rate', 'kind', 'calibration', 'part', 'appeared', 'status', 'open', 'thin', false, 'tier', 2,
        'weight', (v ->> 'seen')::int,
        'title', 'Its departure forecast does no better than the base rate',
        'finding', 'Whether a charged car leaves inside the window scored a Brier of '
                   || round((v ->> 'brier')::numeric / (v ->> 'seen')::numeric, 4) || ' over ' || (v ->> 'seen')
                   || ' cars, against ' || round(((v ->> 'left')::numeric / (v ->> 'seen')::numeric)
                                                 * (1 - (v ->> 'left')::numeric / (v ->> 'seen')::numeric), 4)
                   || ' for giving every car the share that left.',
        'action', 'Condition the dwell on what moves it here: each car''s open work is in; the hour''s demand is not.',
        'evidence', v_flow - 'dwell_by');
    END IF;
    -- a class that does worse on its own curve than on the one curve
    FOR y IN SELECT c.key AS k, c.value AS j FROM jsonb_each(COALESCE(v_flow -> 'dwell_by', '{}'::jsonb)) c
              WHERE c.key <> 'pooled' AND (c.value ->> 'seen')::numeric >= 30
                AND (c.value ->> 'brier')::numeric > (c.value ->> 'brier_pooled')::numeric ORDER BY c.key
    LOOP
      v_areas := v_areas || jsonb_build_object(
        'area', 'outflow_dwell_class_' || y.k, 'kind', 'calibration', 'part', 'appeared', 'status', 'open', 'thin', false,
        'tier', 2, 'weight', (y.j ->> 'seen')::int,
        'title', 'Its departure curve for ' || public.ottoq_review_words('dwell', y.k) || ' does worse than one curve for all',
        'finding', 'Of ' || (y.j ->> 'seen') || ' ' || public.ottoq_review_words('dwell', y.k) || ', whether each left inside '
                   || 'the window scored a Brier of ' || round((y.j ->> 'brier')::numeric / (y.j ->> 'seen')::numeric, 4)
                   || ' on their own curve and ' || round((y.j ->> 'brier_pooled')::numeric / (y.j ->> 'seen')::numeric, 4)
                   || ' on the curve for all cars.',
        'action', CASE y.k WHEN 'bay' THEN 'Time a bay car''s departure from the bays'' own queue and service times, not from '
                                           || 'past runs'' curve.'
                           WHEN 'boot' THEN 'Time a run-start car''s departure from the dispatcher''s pull.'
                           ELSE 'Refit the class''s curve over more runs, or merge it back into the one curve.' END,
        'evidence', y.j);
    END LOOP;
    -- returns: the expected future's against the real
    IF (v_flow ->> 'real')::numeric >= 20 AND (v_flow ->> 'modelled')::numeric > 0
       AND abs(ln((v_flow ->> 'modelled')::numeric / (v_flow ->> 'real')::numeric)) > ln(1.25) THEN
      v_areas := v_areas || jsonb_build_object(
        'area', 'outflow_returns', 'kind', 'calibration', 'part', 'appeared', 'status', 'open', 'thin', false, 'tier', 2,
        'weight', (v_flow ->> 'real')::int,
        'title', CASE WHEN (v_flow ->> 'modelled')::numeric > (v_flow ->> 'real')::numeric
                      THEN 'It brings cars back sooner than they come' ELSE 'It brings fewer cars back than come' END,
        'finding', 'Its expected futures brought ' || (v_flow ->> 'modelled') || ' cars home inside the windows; '
                   || (v_flow ->> 'real') || ' came.',
        'action', 'Check the reserve and the drain the returns are drawn from against the run''s own returns.',
        'evidence', v_flow - 'dwell_by');
    END IF;
    -- the curve's shape: where the cars that left fell in it
    IF (v ->> 'pit_n')::numeric >= 30
       AND (abs((v ->> 'pit50')::numeric / (v ->> 'pit_n')::numeric - 0.5) > 0.1
            OR abs((v ->> 'pit80')::numeric / (v ->> 'pit_n')::numeric - 0.8) > 0.1) THEN
      v_areas := v_areas || jsonb_build_object(
        'area', 'outflow_dwell_shape', 'kind', 'calibration', 'part', 'appeared', 'status', 'open', 'thin', false, 'tier', 2,
        'weight', (v ->> 'pit_n')::int,
        'title', CASE WHEN (v ->> 'pit50')::numeric / (v ->> 'pit_n')::numeric > 0.5
                      THEN 'Cars leave sooner after a charge than its curves say'
                      ELSE 'Cars leave later after a charge than its curves say' END,
        'finding', 'Of ' || (v ->> 'pit_n') || ' cars that left, ' || round(100 * (v ->> 'pit50')::numeric / (v ->> 'pit_n')::numeric)
                   || '% left before their curve''s median and ' || round(100 * (v ->> 'pit80')::numeric / (v ->> 'pit_n')::numeric)
                   || '% before its 80th percentile, against 50% and 80%.',
        'action', 'Refit the dwell curves on recent runs; if the shape stays off, the class split is missing a variable.',
        'evidence', v);
    END IF;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_areas) a WHERE a.value ->> 'part' = 'appeared')
     AND ((COALESCE((v_parts #>> '{appeared,verdict_mass}')::numeric, 0) >= 1
           AND COALESCE((v_parts #>> '{appeared,orders_moved}')::int, 0) >= 1)
          OR COALESCE((v_out ->> 'per_order')::numeric, 0) >= 1) THEN
    v_status := CASE WHEN v_carried >= 10 OR to_regproc('public.ottoq_charge_line_outflow') IS NULL THEN 'open' ELSE 'built' END;
    v_areas := v_areas || jsonb_build_object(
      'area', 'forecast_appeared', 'kind', 'capability_gap', 'part', 'appeared', 'status', v_status, 'thin', false, 'tier', 4,
      'weight', COALESCE((v_out ->> 'appeared_returned')::int, (v_parts #>> '{appeared,orders_moved}')::int, 0),
      'title', 'Cars it never saw coming moved its verdicts',
      'finding', CASE WHEN v_parts ? 'appeared'
                      THEN 'Cars it never saw coming explain ' || round(100 * (v_parts #>> '{appeared,verdict_share}')::numeric)
                           || '% of what made its verdicts wrong and moved ' || (v_parts #>> '{appeared,orders_moved}')
                           || ' of ' || v_attr || '. ' ELSE '' END
                 || CASE WHEN COALESCE((v_out ->> 'appeared_returned')::int, 0) > 0
                         THEN (v_out ->> 'per_order') || ' cars a window came home unseen; '
                              || to_char((v_out ->> 'left_after_the_order')::numeric, 'FM999,999,990')
                              || ' of ' || to_char((v_out ->> 'appeared_returned')::numeric, 'FM999,999,990')
                              || ' had left after the order, a mean '
                              || (v_out ->> 'mean_eta_min') || ' minutes before they came back. ' ELSE '' END
                 || CASE v_status
                      WHEN 'built' THEN 'The check now sends charged cars out and brings them back, and '
                                        || CASE WHEN v_carried = 0 THEN 'none' ELSE v_carried::text END || ' of the '
                                        || v_n || ' orders graded here carried it, so this is history until new orders are graded.'
                      WHEN 'open' THEN CASE WHEN v_carried >= 10
                                            THEN 'Its outflow forecast passes its own grade, so these are cars it does not model at all.'
                                            ELSE 'It sees only cars already out at the order.' END END,
      'action', CASE v_status
                  WHEN 'built' THEN 'Grade the next armed run''s orders: the outflow''s grade will say whether it sees them now.'
                  ELSE CASE WHEN v_carried >= 10 THEN 'Find where the unseen cars come from (a bay, a hold, a run start) and model it.'
                            ELSE 'Model the depot''s own outflow: when charged cars leave, and their return at the learned reserve.' END END,
      'evidence', jsonb_build_object('part', v_parts -> 'appeared', 'unseen_returns', v_out, 'orders_with_an_outflow', v_carried));
  END IF;

  -- (7) when cars came home, chargers that faulted, how long charges took: the part alone, where nothing above names it
  FOR x IN SELECT p.key AS part, p.value AS j FROM jsonb_each(v_parts) p
            WHERE p.key IN ('arrivals', 'faults', 'charge_times')
              AND COALESCE((p.value ->> 'verdict_mass')::numeric, 0) >= 1 AND COALESCE((p.value ->> 'orders_moved')::int, 0) >= 1
            ORDER BY p.key
  LOOP
    CONTINUE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(v_areas) a WHERE a.value ->> 'part' = x.part);
    v_status := CASE WHEN x.part = 'charge_times' AND v_rebuilt IS NOT NULL THEN 'built'
                     WHEN x.part = 'arrivals' AND v_arr_built THEN 'built' ELSE 'open' END;           -- 0627
    v_areas := v_areas || jsonb_build_object(
      'area', 'forecast_' || x.part,
      'kind', CASE x.part WHEN 'faults' THEN 'capability_gap' ELSE 'forecast' END,
      'part', x.part, 'status', v_status, 'thin', false, 'tier', 4, 'weight', (x.j ->> 'orders_moved')::int,
      'title', CASE x.part WHEN 'arrivals' THEN 'When cars came home moved its verdicts'
                           WHEN 'faults' THEN 'Charger faults it never sampled moved its verdicts'
                           ELSE 'How long charges took moved its verdicts' END,
      'finding', initcap(left(public.ottoq_review_words('part', x.part), 1)) || substr(public.ottoq_review_words('part', x.part), 2)
                 || ' explain ' || round(100 * (x.j ->> 'verdict_share')::numeric) || '% of what made its verdicts wrong and '
                 || 'moved ' || (x.j ->> 'orders_moved') || ' of ' || v_attr || '. '
                 || CASE x.part
                      WHEN 'faults' THEN 'Its futures never take a charger down: a fault inside the window is a surprise to every one of them.'
                      WHEN 'arrivals' THEN 'The return forecast''s spread holds, so this is the arrivals'' own variation.'
                      ELSE 'The clock''s audit finds nothing it misses: what is left is each charge''s own noise.' END
                 || CASE WHEN v_status = 'built' THEN CASE WHEN x.part = 'arrivals' THEN c_arr_note ELSE v_note END
                         ELSE '' END,
      'action', CASE x.part
                  WHEN 'faults' THEN 'Sample charger faults in the futures at the depot''s own fault rate and repair time.'
                  WHEN 'arrivals' THEN CASE WHEN v_status = 'built' THEN c_arr_act
                                            ELSE 'More futures sample this variation better; nothing to rebuild.' END
                  ELSE CASE WHEN v_status = 'built' THEN 'Nothing until orders timed by the rebuilt clock are graded.'
                            ELSE 'Nothing to rebuild; more futures sample this noise better.' END END,
      'evidence', jsonb_build_object('part', x.j));
  END LOOP;

  -- (8) the simulator itself, given what happened
  IF COALESCE((v_a #>> '{simulator,cars_compared}')::numeric, 0) >= 20 AND (v_a #>> '{simulator,mae_min}')::numeric > 10 THEN
    v_areas := v_areas || jsonb_build_object(
      'area', 'simulator_structure', 'kind', 'capability_gap', 'part', NULL, 'status', 'open', 'thin', false, 'tier', 5,
      'weight', (v_a #>> '{simulator,cars_compared}')::int,
      'title', 'Its simulator places a plug-in ' || round((v_a #>> '{simulator,mae_min}')::numeric) || ' minutes off, even given what happened',
      'finding', 'Replayed with what really happened, its simulator still puts a car''s plug-in a mean '
                 || (v_a #>> '{simulator,mae_min}') || ' minutes from when it really plugged in (bias '
                 || (v_a #>> '{simulator,bias_min}') || ' minutes; ' || round(100 * (v_a #>> '{simulator,within_5_min}')::numeric)
                 || '% within 5 minutes), over ' || to_char((v_a #>> '{simulator,cars_compared}')::numeric, 'FM999,999,990')
                 || ' cars, with '
                 || (v_a #>> '{simulator,missed}') || ' plug-ins it missed and ' || (v_a #>> '{simulator,phantom}')
                 || ' it invented. It does not model bays, holds, the stall pick beyond the kind of charger, or the next '
                 || 'order taking over, and no forecast can remove that error.',
      'action', 'Measure which of the four costs the most, then model that one in the check''s simulator.',
      'evidence', v_a -> 'simulator');
  END IF;
  IF COALESCE((v_a #>> '{forecasts,unmodeled_sessions_per_order}')::numeric, 0) >= 1 THEN
    v_areas := v_areas || jsonb_build_object(
      'area', 'chargers_left_out', 'kind', 'capability_gap', 'part', NULL, 'status', 'open', 'thin', false, 'tier', 5,
      'weight', v_n,
      'title', 'It never adds back a charger whose hold ends',
      'finding', 'Chargers it left out at the order (held for a car, booked, or faulted) served '
                 || (v_a #>> '{forecasts,unmodeled_sessions_per_order}') || ' charges a window that it never modelled.',
      'action', 'Add a held or booked charger back to the line at the minute its hold ends.',
      'evidence', jsonb_build_object('unmodeled_sessions_per_order', v_a #> '{forecasts,unmodeled_sessions_per_order}'));
  END IF;

  -- (9) the win probability, and the bar
  IF v_dec >= 10 AND (v_a #>> '{calibration,brier}') IS NOT NULL
     AND (v_a #>> '{calibration,brier}')::numeric >= (v_a #>> '{calibration,brier_of_base_rate}')::numeric THEN
    v_areas := v_areas || jsonb_build_object(
      'area', 'futures_uninformative', 'kind', 'calibration', 'part', NULL, 'status', 'open', 'thin', v_dec < 30, 'tier', 5,
      'weight', v_dec,
      'title', 'Its odds of winning predict no better than the base rate',
      'finding', 'Its win probability (the share of futures an order won) scored a Brier of ' || (v_a #>> '{calibration,brier}')
                 || ' against hindsight over ' || v_dec || ' decisions, against ' || (v_a #>> '{calibration,brier_of_base_rate}')
                 || ' for always saying the share that won.'
                 || CASE WHEN v_dec < 30 THEN ' On ' || v_dec || ' decisions the two are within each other''s noise.' ELSE '' END,
      'action', 'Fix the forecasts ranked above; more futures do not help a spread that is wrong.',
      'evidence', v_a -> 'calibration');
  END IF;
  SELECT b.value INTO v
    FROM jsonb_array_elements(COALESCE(v_a #> '{bar,sweep}', '[]'::jsonb)) b
   ORDER BY (b.value ->> 'd_on_time')::numeric DESC, (b.value ->> 'd_late')::numeric ASC, (b.value ->> 'd_flow')::numeric ASC,
            abs((b.value ->> 'win_frac')::numeric - COALESCE((v_a #>> '{bar,current_win_frac}')::numeric, 0.8)) ASC
   LIMIT 1;
  v_cur := COALESCE((v_a #>> '{bar,current_win_frac}')::numeric, 0.8);
  SELECT b.value INTO w FROM jsonb_array_elements(COALESCE(v_a #> '{bar,sweep}', '[]'::jsonb)) b
   ORDER BY abs((b.value ->> 'win_frac')::numeric - v_cur) LIMIT 1;
  IF v_dec >= 10 AND v IS NOT NULL AND (v ->> 'win_frac')::numeric IS DISTINCT FROM v_cur THEN
    v_areas := v_areas || jsonb_build_object(
      'area', CASE WHEN (v ->> 'win_frac')::numeric < v_cur THEN 'bar_looser' ELSE 'bar_stricter' END,
      'kind', 'threshold', 'part', NULL, 'status', 'open',
      'thin', abs((v ->> 'taken')::int - COALESCE((w ->> 'taken')::int, 0)) < 5, 'tier', 5, 'weight', v_dec,
      'title', CASE WHEN (v ->> 'taken')::int = 0 THEN 'Taking none of these orders would have done better'
                    WHEN (v ->> 'win_frac')::numeric < v_cur THEN 'A looser bar would have done better on these orders'
                    ELSE 'A stricter bar would have done better on these orders' END,
      'finding', CASE WHEN (v ->> 'taken')::int = 0
                      THEN 'In hindsight, taking none of these orders would have done better than the bar it ran under ('
                           || v_cur || ' of the futures), which took ' || COALESCE(w ->> 'taken', '?') || ' ('
                           || COALESCE(w ->> 'won', '?') || ' won, ' || COALESCE(w ->> 'lost', '?') || ' lost)'
                           || CASE WHEN COALESCE((w ->> 'd_late')::numeric, 0) > 0
                                   THEN ' and added ' || round((w ->> 'd_late')::numeric) || ' minutes of lateness' ELSE '' END || '.'
                      ELSE 'In hindsight a bar of ' || (v ->> 'win_frac') || ' would have done better than ' || v_cur || ': it takes '
                           || (v ->> 'taken') || ' (' || (v ->> 'won') || ' won, ' || (v ->> 'lost') || ' lost) where '
                           || v_cur || ' took ' || COALESCE(w ->> 'taken', '?') || ' (' || COALESCE(w ->> 'won', '?') || ' won, '
                           || COALESCE(w ->> 'lost', '?') || ' lost).' END
                 || ' Orders overlap, so this ranks bars; it is not a day''s gain.'
                 || CASE WHEN abs((v ->> 'taken')::int - COALESCE((w ->> 'taken')::int, 0)) < 5
                         THEN ' It rests on ' || abs((v ->> 'taken')::int - COALESCE((w ->> 'taken')::int, 0))
                              || ' orders, too few to move the bar.' ELSE '' END,
      'action', CASE WHEN abs((v ->> 'taken')::int - COALESCE((w ->> 'taken')::int, 0)) < 5
                     THEN 'Leave the bar; grade more armed runs.'
                     ELSE 'Test a bar of ' || (v ->> 'win_frac') || ' in a paired twin run: the bar is a person''s dial.' END,
      'evidence', jsonb_build_object('best', v, 'current', w, 'current_win_frac', v_cur, 'dial', 'agent_charge_order_win_frac'));
  END IF;

  -- (10) the agent's moves
  FOR x IN SELECT m.key AS tag, m.value AS j FROM jsonb_each(COALESCE(v_a -> 'moves', '{}'::jsonb)) m
            WHERE (m.value ->> 'orders')::int >= 3 ORDER BY m.key
  LOOP
    IF (x.j ->> 'lost')::numeric / (x.j ->> 'orders')::numeric >= 0.6 THEN
      v_areas := v_areas || jsonb_build_object(
        'area', 'agent_move_loses_' || x.tag, 'kind', 'agent', 'part', NULL, 'status', 'open',
        'thin', (x.j ->> 'orders')::int < 10, 'tier', 5, 'weight', (x.j ->> 'orders')::int,
        'title', 'The agent''s orders that ' || public.ottoq_review_words('move', x.tag) || ' keep losing',
        'finding', 'Orders that ' || public.ottoq_review_words('move', x.tag) || ' lost to the kernel''s own order in hindsight '
                   || (x.j ->> 'lost') || ' times of ' || (x.j ->> 'orders') || ' (won ' || (x.j ->> 'won') || '); the check took '
                   || (x.j ->> 'taken') || '.',
        'action', 'The agent sees this in its track record; if it persists, its prompt should say to stop.',
        'evidence', x.j);
    ELSIF (x.j ->> 'won')::numeric / (x.j ->> 'orders')::numeric >= 0.7 AND (x.j ->> 'orders')::int - (x.j ->> 'taken')::int >= 2 THEN
      v_areas := v_areas || jsonb_build_object(
        'area', 'agent_move_wins_refused_' || x.tag, 'kind', 'agent', 'part', NULL, 'status', 'open',
        'thin', (x.j ->> 'orders')::int < 10, 'tier', 5, 'weight', (x.j ->> 'orders')::int,
        'title', 'The check keeps refusing orders that ' || public.ottoq_review_words('move', x.tag),
        'finding', 'Orders that ' || public.ottoq_review_words('move', x.tag) || ' beat the kernel''s own order in hindsight '
                   || (x.j ->> 'won') || ' times of ' || (x.j ->> 'orders') || ', and the check refused '
                   || ((x.j ->> 'orders')::int - (x.j ->> 'taken')::int) || ' of them.',
        'action', 'Find what its futures miss about this move: replay the refused ones with what happened.',
        'evidence', x.j);
    END IF;
  END LOOP;

  -- ══ impact, then rank ══════════════════════════════════════════════════════════════════════════════════════════════
  SELECT COALESCE(jsonb_agg(a.value || jsonb_build_object('impact', (v_parts #>> ARRAY[a.value ->> 'part', 'verdict_share'])::numeric)),
                  '[]'::jsonb)
    INTO v_areas FROM jsonb_array_elements(v_areas) a;
  SELECT COALESCE(jsonb_agg(r.value || jsonb_build_object('rank', r.rn) ORDER BY r.rn), '[]'::jsonb)
    INTO v_ranked
    FROM (SELECT a.value, row_number() OVER (
                   ORDER BY a.value ->> 'status' = 'built', (a.value ->> 'thin')::boolean,
                            (a.value ->> 'impact')::numeric DESC NULLS LAST, (a.value ->> 'tier')::int,
                            (a.value ->> 'weight')::numeric DESC NULLS LAST, a.value ->> 'area') AS rn
            FROM jsonb_array_elements(v_areas) a) r;

  RETURN (v_a - 'improvement_areas') || jsonb_build_object(
    'v', 3,
    'clocks', jsonb_build_object('graded_orders', v_used, 'rebuilt_since', v_rebuilt,
                                 'now', jsonb_build_object('model', v_now -> 'model', 'estimate_id', v_now -> 'estimate_id',
                                                           'fitted_at', v_now -> 'fitted_at')),
    'charge_clock', v_cal, 'clock_audit', v_aud, 'world', v_scan, 'world_trials', v_trials,
    'arrival_tails', v_tails, 'outflow', v_out, 'outflow_grade', v_flow,
    'areas_open', (SELECT count(*) FROM jsonb_array_elements(v_ranked) a WHERE a.value ->> 'status' = 'open'),
    'areas_built', (SELECT count(*) FROM jsonb_array_elements(v_ranked) a WHERE a.value ->> 'status' = 'built'),
    'improvement_areas', v_ranked,
    'ranking', 'open before built (built: rebuilt after these orders were made), strong before thin, then by impact (the '
               'share of what made the check wrong that the area''s part carries; the clock also feeds charges under way), '
               'then tier (1 a change in the world, 2 a measured diagnosis, 3 a calibration of the forecasts made, 4 a part '
               'alone, 5 the rest), then weight');
END $fn$;

-- ══ (j) the review's writer: its code md5 covers the arrivals' z ═══════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_arbiter_assess(p_depot_id uuid, p_days integer DEFAULT 7)
RETURNS bigint
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $fn$
/* 0621: the day's self-assessment of the check at a depot, written to ottoq_arbiter_assessments; NULL when nothing was
   graded in the window. A finding for a person, never a change (rule 10). 0622: the assessment is
   ottoq_arbiter_self_assessment_v2 (the clock's own calibration and audit, and the outflow). 0626: it is
   ottoq_arbiter_self_assessment_v3, which tries a change the scan names out of sample; and a review with nothing graded
   is written when it names a place to improve, since the clock's audit and its world need no graded order. 0627: the
   code md5 also covers where each arrival fell in its forecast (ottoq_inbound_arrival_z, ottoq_normal_cdf). */
DECLARE v jsonb; v_since timestamptz := now() - make_interval(days => GREATEST(COALESCE(p_days, 7), 1)); v_id bigint;
BEGIN
  v := public.ottoq_arbiter_self_assessment_v3(p_depot_id, v_since, true);
  IF COALESCE((v ->> 'graded')::int, 0) = 0
     AND jsonb_array_length(COALESCE(v -> 'improvement_areas', '[]'::jsonb)) = 0 THEN
    RETURN NULL;
  END IF;
  INSERT INTO ottoq_arbiter_assessments (depot_id, since, n_graded, n_decisions, assessment, improvement_areas, code_md5)
  VALUES (p_depot_id, v_since, COALESCE((v ->> 'graded')::int, 0), COALESCE((v ->> 'decisions')::int, 0),
          v - 'improvement_areas', COALESCE(v -> 'improvement_areas', '[]'::jsonb),
          md5(pg_get_functiondef('public.ottoq_arbiter_self_assessment(uuid,timestamptz)'::regprocedure)
              || pg_get_functiondef('public.ottoq_arbiter_self_assessment_v3(uuid,timestamptz,boolean)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_clock_audit_v2(uuid,timestamptz,jsonb)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_clock_calibration(uuid,timestamptz)'::regprocedure)
              || pg_get_functiondef('public.ottoq_evidence_regime_scan(uuid,timestamptz,jsonb)'::regprocedure)
              || pg_get_functiondef('public.ottoq_review_words(text,text)'::regprocedure)
              || pg_get_functiondef('public.ottoq_inbound_arrival_z(jsonb,jsonb,double precision)'::regprocedure)
              || pg_get_functiondef('public.ottoq_normal_cdf(double precision)'::regprocedure)))
  RETURNING assessment_id INTO v_id;
  RETURN v_id;
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_recall_threshold_soc(uuid, uuid, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ottoq_recall_threshold_soc(uuid, uuid, timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_normal_cdf(double precision) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_inbound_arrival_z(jsonb, jsonb, double precision) TO anon, authenticated, service_role;

-- ══ V1: what carries no recall block, no rung and no trip_o is what it was ══════════════════════════════════════════
DO $v1$
DECLARE v_bad int; v_n int; v_z int; v_zbad int; v_old jsonb; v_new jsonb; v_keys int;
BEGIN
  -- (i) the stored snapshots
  SELECT count(*), count(*) FILTER (
           WHERE b.k IS DISTINCT FROM public.ottoq_charge_line_schedule(s.state, NULL, b.sc, s.seed, true)
              OR b.a IS DISTINCT FROM public.ottoq_charge_line_schedule(s.state, s.agent_order, b.sc, s.seed, true)
              OR b.c IS DISTINCT FROM public.ottoq_charge_line_compare(public.ottoq_charge_line_simulate(s.state, NULL, b.sc, s.seed),
                                                                       public.ottoq_charge_line_simulate(s.state, s.agent_order, b.sc, s.seed)))
    INTO v_n, v_bad
    FROM v0627_before b JOIN public.ottoq_charge_order_snapshots s USING (order_id);
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0627 V1: % of % stored simulations or comparisons changed', v_bad, v_n;
  END IF;
  RAISE NOTICE '0627 V1: % stored simulations and comparisons (% snapshots x 2 futures) unchanged', v_n, v_n / 2;

  -- (ii) the self-review's z on every graded order of the 21 days, against 0621's
  SELECT count(*), count(*) FILTER (WHERE abs(z.z_new - z.z_old) > 1e-9 OR z.z_new IS NULL)
    INTO v_z, v_zbad
    FROM (SELECT public.ottoq_inbound_arrival_z(ib.value, s.state -> 'recall', a.act) AS z_new,
                 ln((a.act - (ib.value ->> 'trip')::float8) / ((ib.value ->> 'eta')::float8 - (ib.value ->> 'trip')::float8))
                   / (ib.value ->> 'esd')::float8 AS z_old
            FROM public.ottoq_charge_order_hindsight h
            JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
            CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
            CROSS JOIN LATERAL (SELECT (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act,
                                       COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false) AS arrived) a
           WHERE h.graded_at >= now() - interval '21 days' AND jsonb_typeof(s.state -> 'recall') IS DISTINCT FROM 'object'
             AND a.arrived AND ib.value ->> 'src' = 'forecast' AND COALESCE((ib.value ->> 'esd')::float8, 0) > 0
             AND a.act > COALESCE((ib.value ->> 'trip')::float8, 0)
             AND (ib.value ->> 'eta')::float8 > COALESCE((ib.value ->> 'trip')::float8, 0)) z;
  IF v_zbad > 0 THEN
    RAISE EXCEPTION '0627 V1: % of % arrivals'' z differ from 0621''s', v_zbad, v_z;
  END IF;
  RAISE NOTICE '0627 V1: % graded arrivals of the 21 days, each z as 0621''s', v_z;

  -- (iii) the fit through d9d49732's start: 0624's keys as they were, and the drives added
  IF NOT EXISTS (SELECT 1 FROM v0627_fit) THEN
    RAISE NOTICE '0627 V1: run d9d49732 is not here; the fit is executed by the tests';
    RETURN;
  END IF;
  SELECT f.params, public.ottoq_return_model_params('11111111-1111-1111-1111-111111111111'::uuid, f.through, interval '21 days')
    INTO v_old, v_new FROM v0627_fit f;
  SELECT count(*) INTO v_keys FROM jsonb_object_keys(v_old) k;
  IF (v_new - ARRAY['trip_sd_min', 'trip_other_min', 'trip_other_p90_min', 'other_by_trigger']) IS DISTINCT FROM v_old THEN
    RAISE EXCEPTION '0627 V1: the fit through d9d49732''s start changed a key 0624 computed';
  END IF;
  IF (v_new ->> 'trip_sd_min') IS NULL OR (v_new ->> 'trip_other_min') IS NULL OR jsonb_typeof(v_new -> 'other_by_trigger') <> 'object' THEN
    RAISE EXCEPTION '0627 V1: the fit through d9d49732''s start learned no drives: %', v_new - 'dwell' - 'dwell_by';
  END IF;
  CREATE TEMP TABLE v0627_fit_new ON COMMIT DROP AS SELECT v_new AS params;
  RAISE NOTICE '0627 V1: the fit through d9d49732''s start keeps 0624''s % keys and adds the drives: trip_sd % min, other % (p90 %) min, other calls %',
    v_keys, v_new -> 'trip_sd_min', v_new -> 'trip_other_min', v_new -> 'trip_other_p90_min',
    (SELECT string_agg(format('%s %s/%s', o.key, o.value ->> 'n', o.value ->> 'per_work_hour'), ', ' ORDER BY o.key)
       FROM jsonb_each(v_new -> 'other_by_trigger') o);
END $v1$;

-- ══ V2: THE GATE, out of sample on d9d49732's graded orders ═════════════════════════════════════════════════════════
DO $v2$
DECLARE
  c_run   constant uuid := 'd9d49732-cf28-42c3-aac9-9c3f606a2c92';
  v_fit   jsonb;
  v_rc    jsonb;
  g       record;
  v_trig  text;
BEGIN
  IF to_regclass('pg_temp.v0627_fit_new') IS NULL THEN
    RAISE NOTICE '0627 V2: run d9d49732 is not here; the gate is executed by the tests';
    RETURN;
  END IF;
  SELECT params INTO v_fit FROM v0627_fit_new;
  v_rc := jsonb_build_object('lam', round(COALESCE((v_fit ->> 'other_per_work_hour')::numeric, 0) / 60.0, 6),
                             'trip_o', COALESCE((v_fit ->> 'trip_other_min')::numeric, (v_fit ->> 'trip_min')::numeric, 0));
  CREATE TEMP TABLE v0627_gate ON COMMIT DROP AS
  WITH ar AS (
    SELECT h.order_id, s.sim_run_id AS run, s.sim_clock AS clock, ib.value AS e, (ib.value ->> 'id')::uuid AS vid,
           (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::float8 AS act,
           (ib.value ->> 'eta')::float8 AS fc, COALESCE((ib.value ->> 'trip')::float8, 0) AS trip,
           le.params AS mp
      FROM public.ottoq_charge_order_hindsight h
      JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
      JOIN public.ottoq_learned_estimates le ON le.estimate_id = (s.state #>> '{models,return}')::bigint
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(s.state -> 'inbound', '[]'::jsonb)) ib
     WHERE h.sim_run_id = c_run AND ib.value ->> 'src' = 'forecast'
       AND COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false)
       AND COALESCE((ib.value ->> 'esd')::float8, 0) > 0
  ), b AS (
    -- the car's battery at the order, as the recall decision recorded it, and its rung
    SELECT ar.*, rd.soc0, public.ottoq_recall_threshold_soc(ar.vid, ar.run, ar.clock)::float8 AS thr,
           (ar.mp ->> 'drain_pct_per_min')::float8 AS dr, COALESCE((ar.mp ->> 'drain_log_sd')::float8, 0) AS dsd
      FROM ar
      CROSS JOIN LATERAL (SELECT r.soc_override::float8 AS soc0 FROM public.ottoq_recall_decisions r
                           WHERE r.sim_run_id = ar.run AND r.vehicle_id = ar.vid AND r.decided_at_sim <= ar.clock
                             AND r.inputs ? 'reserve'
                           ORDER BY r.decided_at_sim DESC LIMIT 1) rd
     WHERE ar.act > ar.trip AND ar.fc > ar.trip
  ), f AS (
    SELECT b.*, GREATEST((b.soc0 - b.thr) / b.dr, 0) AS hz FROM b WHERE b.dr > 0 AND b.thr IS NOT NULL
  )
  SELECT f.order_id, f.vid, f.run, f.clock, f.act, f.fc, f.trip, f.hz,
         public.ottoq_inbound_arrival_z(f.e, NULL, f.act) AS z_old,
         public.ottoq_inbound_arrival_z(
           jsonb_build_object('eta', f.hz + f.trip, 'trip', f.trip,
                              'esd', sqrt(f.dsd ^ 2 + (COALESCE((v_fit ->> 'trip_sd_min')::float8, 0) / GREATEST(f.hz, 0.25)) ^ 2)),
           v_rc, f.act) AS z_new
    FROM f;
  SELECT count(*) AS n, count(*) FILTER (WHERE z_new IS NULL) AS due_now,
         count(*) FILTER (WHERE z_old > 3) AS late_old, count(*) FILTER (WHERE z_new > 3) AS late_new,
         count(*) FILTER (WHERE z_old < -3) AS early_old, count(*) FILTER (WHERE z_new < -3) AS early_new,
         round(avg(abs(act - fc))::numeric, 3) AS mae_old, round(avg(abs(act - trip - hz))::numeric, 3) AS mae_new,
         round(avg((abs(z_old) <= 1.2816)::int)::numeric, 3) AS band_old,
         round(avg((abs(z_new) <= 1.2816)::int) FILTER (WHERE z_new IS NOT NULL)::numeric, 3) AS band_new
    INTO g FROM v0627_gate;
  IF g.n < 100 THEN
    RAISE NOTICE '0627 V2: only % forecast arrivals with a recorded battery on d9d49732; the gate is executed by the tests', g.n;
    RETURN;
  END IF;
  SELECT string_agg(format('%s %s', x.tail || ' ' || COALESCE(x.trig, '(none)'), x.n), ', ' ORDER BY x.tail, x.n DESC) INTO v_trig
    FROM (SELECT CASE WHEN q.z_new > 3 THEN 'late' ELSE 'early' END AS tail, d.return_trigger AS trig, count(*) AS n
            FROM v0627_gate q
            LEFT JOIN LATERAL (SELECT dd.return_trigger FROM public.ottoq_vehicle_dispatches dd
                                WHERE dd.sim_run_id = q.run AND dd.vehicle_id = q.vid AND dd.dispatched_at <= q.clock
                                ORDER BY dd.dispatched_at DESC LIMIT 1) d ON true
           WHERE abs(q.z_new) > 3 GROUP BY 1, 2) x;
  RAISE NOTICE '0627 V2: % forecast arrivals (% due at the order): late % -> %, early % -> %, absolute error % -> % minutes, inside the 80%% band % -> %; the tails left: %',
    g.n, g.due_now, g.late_old, g.late_new, g.early_old, g.early_new, g.mae_old, g.mae_new, g.band_old, g.band_new,
    COALESCE(v_trig, 'none');
  IF g.late_new > g.late_old / 2.0 OR g.early_new > g.early_old OR g.mae_new >= g.mae_old
     OR g.band_new < 0.75 OR g.band_new > 0.90 THEN
    RAISE EXCEPTION '0627 V2: the gate holds back: late % -> %, early % -> %, error % -> %, band %', g.late_old, g.late_new,
      g.early_old, g.early_new, g.mae_old, g.mae_new, g.band_new;
  END IF;
END $v2$;

-- ══ V3: the rung is the evaluator's own; the fit at apply learns the drives; a running run's state carries them ═══════
DO $v3$
DECLARE v_n int; v_bad int; v_runs int; v_rt jsonb; r record; v_state jsonb; t0 timestamptz; v_ms numeric;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE public.ottoq_recall_threshold_soc(d.vehicle_id, d.sim_run_id, d.decided_at_sim)
                                           IS DISTINCT FROM (d.inputs ->> 'reserve')::numeric + (d.inputs ->> 'reserve_margin')::numeric),
         count(DISTINCT d.sim_run_id)
    INTO v_n, v_bad, v_runs
    FROM public.ottoq_sim_runs x
    CROSS JOIN LATERAL (SELECT rd.vehicle_id, rd.sim_run_id, rd.decided_at_sim, rd.inputs FROM public.ottoq_recall_decisions rd
                         WHERE rd.sim_run_id = x.sim_run_id AND rd.inputs ? 'reserve' AND rd.inputs ? 'reserve_margin'
                         ORDER BY rd.decided_at_sim DESC LIMIT 50) d
   WHERE x.depot_id = '11111111-1111-1111-1111-111111111111' AND x.started_at >= now() - interval '21 days';
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0627 V3: the rung differs from the recall decision''s own record on % of % decisions', v_bad, v_n;
  END IF;
  RAISE NOTICE '0627 V3: the rung equals the recall decision''s own record on % of % decisions, across % runs', v_n - v_bad, v_n, v_runs;

  PERFORM public.ottoq_fit_return_model('11111111-1111-1111-1111-111111111111'::uuid, NULL, NULL, '0627: the drives');
  v_rt := public.ottoq_learned_estimate('11111111-1111-1111-1111-111111111111'::uuid, 'return_v1');
  IF COALESCE((v_rt #>> '{params,n_low_soc}')::int, 0) > 0 AND (v_rt #>> '{params,trip_sd_min}') IS NULL THEN
    RAISE EXCEPTION '0627 V3: the fit at apply has % reserve returns and learned no drive spread', v_rt #>> '{params,n_low_soc}';
  END IF;
  IF COALESCE((v_rt #>> '{params,n_low_soc}')::int, 0) = 0 THEN
    RAISE NOTICE '0627 V3: the fit at apply has no reserve returns to learn the drives from; the fit is executed by the tests';
  END IF;
  RAISE NOTICE '0627 V3: return_v1 estimate % (usable %): drive spread % min, after another call % min (p90 %), other calls % an hour',
    v_rt -> 'estimate_id', v_rt -> 'usable', v_rt #> '{params,trip_sd_min}', v_rt #> '{params,trip_other_min}',
    v_rt #> '{params,trip_other_p90_min}', v_rt #> '{params,other_per_work_hour}';

  SELECT x.sim_run_id, x.depot_id, x.sim_clock_current INTO r
    FROM public.ottoq_sim_runs x WHERE x.status = 'running' AND x.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY x.started_at DESC LIMIT 1;
  IF r.sim_run_id IS NULL THEN
    RAISE NOTICE '0627 V3: no twin run is running; the state is executed by the tests';
    RETURN;
  END IF;
  t0 := clock_timestamp();
  v_state := public.ottoq_charge_line_state(r.sim_run_id, r.depot_id, r.sim_clock_current);
  v_ms := round(extract(epoch FROM clock_timestamp() - t0) * 1000);
  RAISE NOTICE '0627 V3 on running run %: state % ms, recall %, forecast cars with a rung % of %', r.sim_run_id, v_ms,
    v_state -> 'recall',
    (SELECT count(*) FROM jsonb_array_elements(v_state -> 'inbound') e WHERE e.value ->> 'src' = 'forecast' AND e.value ? 'thr'),
    (SELECT count(*) FROM jsonb_array_elements(v_state -> 'inbound') e WHERE e.value ->> 'src' = 'forecast');
END $v3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0627_the_futures_call_cars_home_the_way_the_kernel_does', false, false,
  'The kernel''s check on an agent''s charge order calls each working car home where the kernel''s own recall decision '
  'calls it (ottoq_recall_threshold_soc: its reserve plus the run''s margin), samples the other calls home at the rate '
  'the depot''s returns show, and spreads each arrival by the drain and the drive''s own minutes; the self-review places '
  'each arrival in that forecast. FALSE/FALSE: the check, its grader and the board run only on runs that take an agent''s '
  'charge order; the recall decision and the tick path are untouched.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
