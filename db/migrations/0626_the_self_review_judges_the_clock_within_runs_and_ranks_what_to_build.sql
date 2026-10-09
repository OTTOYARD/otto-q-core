-- migration-version: 20261008225037
-- migration-name:    the_self_review_judges_the_clock_within_runs_and_ranks_what_to_build
--
-- 0626  **The self-review judges the clock within runs, finds what changed, and ranks what to build in plain words.**
--       0621 gave the check a nightly self-review and 0622 added the charge clock's audit to it. Read on 2026-10-08, it
--       named eighteen places to improve, and a person could act on few of them. It said air temperature explains 41% of
--       what the clock leaves on fast chargers; within runs it explains 6%, because a run is one day's weather and the
--       audit never took the run out first (G360). It said the futures sample arrivals too narrowly (spread 3.05); the
--       bulk is as wide as sampled and the misses are two tails. It named the outflow and the old clock's calibration as
--       open when both were rebuilt after the orders it graded. It ranked 2,510 arrivals against 18 decisions as though
--       they were one unit, wrote internal ids into its sentences, and said "a bar of 1.0 would have done better: 0
--       taken, 0 won, 0 lost". And 0625's scan, which finds a change in the clock's world by itself, had no place in it.
--       Chase, 2026-10-08: "if it can't technically do XYZ, I should probably build that in ... Ideally, after a while,
--       the system itself will pick up areas for self improvement." This is the instrument that picks them up: ranked by
--       how much of what made the check wrong each one touches, marked open or already built, and each with the action
--       a person would take. Rule 10 holds: it is read-only, and every area is for a person.
--
-- ══ §1 WHY (the twin depot's last 7 days, 12 runs, the 61 orders graded from run d9d49732; measured 2026-10-08
--    21:40-22:40 UTC, 4:40-5:40 PM CT) ══
--
--   (a) The audit took a run's level for a variable the clock misses (G360). On the clock's residuals (fit 3, 458 fast
--       charges, 613 L2), the share each variable explains as 0622's audit computes it, and within runs (each charge's
--       residual less its run's mean): air temperature 0.411 / 0.062 on fast chargers and 0.278 / 0.029 on L2; the run
--       itself 0.327 and 0.272 across, which the clock models (its run evidence); class 0.0095 / 0.0016 and make and
--       model 0.013 / -0.002 on fast chargers under fit 3 (0.236 and 0.260 under fit 1, the same within runs: the stale
--       levels 0625 removed). Every "misses run" and most of every "misses air temperature" the review printed was the
--       run's level.
--   (b) Air temperature is a real variable all the same, and a slope says so where a share cannot. Within runs a
--       charge ran 0.97% longer for each degree warmer on fast chargers (t 4.9) and 0.81% on L2 (t 2.8); between runs
--       (each run's mean residual on its mean temperature, weighted by its charges) 1.54% (R² 0.78 over 10 runs
--       averaging 14.4-27.3 °C) and 1.50% (R² 0.90 over 11 runs, 12.8-25.5 °C). Over the days the depot saw, that is
--       about 20% between its coolest and warmest runs. The twin derates a battery above 35 °C, and a charging battery
--       runs 5-28 °C above the air (0573's ottoq_sim_compute_charge_rate as twin.ottoq_sim_advance_charge_sessions calls
--       it); the clock has no level for it, so it learns each run's level from that run's own charges.
--   (c) The arrivals' misses are tails, not a narrow spread. Of 2,510 cars forecast home, 79.9% arrived inside the
--       80% band the futures sample, and the bulk (within 3 of its spreads) has a spread of 0.92 of what is sampled.
--       173 (6.9%) are past 3: 69 came home a mean 15.4 minutes early, before their battery reached the reserve, and
--       104 a mean 7.7 minutes late, on trips forecast 15.8 minutes to the reserve against 38.8 for the bulk: the
--       futures spread a return in proportion to the trip, so a few minutes' delay on a short trip reads as far off.
--       0621's area read "z sd 3.05 ... the futures are narrower than what comes" and pointed at the wrong fix.
--   (d) The review named as open what was already rebuilt: the outflow (0623) and the charge clock (0622) were built
--       after these orders were made (all 61 were timed by 0619's clock and carried no outflow), and its ranking was by
--       counts of different things. Its sentences carried internal ids (migration numbers, model names, class codes, a
--       dial's name) and its bar area read "a bar of 1.0 would have done better ... 0 taken, 0 won, 0 lost", which is
--       "taking none of these orders would have done better", on two orders.
--
-- ══ §2 WHAT ══
--
--   (a) `ottoq_charge_clock_audit_v2(depot, since, model)`: 0622's audit (the same charges, clocks and accuracy block)
--       judged within runs. Each covariate's adjusted eta squared is also computed on the residuals less their run's
--       mean (outside a run, the day's), on the N - U degrees of freedom the run means leave (`adj_eta2_within`); the
--       run is marked modelled and judged across runs only; the accuracy block adds the mean miss and the 80% band
--       within runs. Air temperature is also read as a slope (`air_temperature`): per degree within runs with its t,
--       and between runs (the charge-weighted regression of the runs' mean residuals on their mean temperatures, runs
--       of 5 or more charges) with its R² and the runs' range.
--   (b) `ottoq_review_words(what, key)`, `ottoq_review_change(ratio)`, `ottoq_review_ct(at)`: the review's words for
--       its own keys (a kind of charger, a covariate, a part, an agent's move, a dwell class, a vehicle class by its
--       maker from ottoq_vehicle_classes), a ratio as "68% shorter", and a moment in the depot's own time (rule 7).
--   (c) `ottoq_arbiter_self_assessment_v3(depot, since, p_trial)`: 0621's measurements and 0622's calibration as they
--       are, and areas rebuilt. Each carries `part` (of 0621's Shapley split) and `impact` (that part's share of the
--       verdict mass), `status` (open, or built: what it describes was rebuilt after the graded orders were made,
--       read from the clock the orders were timed by against the depot's clock now, the record of changes in the
--       clock's world, and whether the orders carried an outflow), `thin` (too little evidence to act on), `tier` (its
--       strength within its part), `title`, `finding` and `action` in plain words, and `rank`: open before built, strong
--       before thin, then impact, tier and weight. New areas: the arrivals' bulk and tails, diagnosed by case; the
--       clock's audit within runs, merged across kinds; air temperature by its slopes; the clock's band; a change in the
--       clock's world that the scan names, with the record a person would write and, with p_trial, the cut tried out of
--       sample on the latest completed run since (ottoq_charge_clock_trial); and the outflow's grade where ten or more
--       orders carried one (departures, the base rate, each dwell class against the one curve, returns, the curve's
--       shape). The part alone (when cars came home, faults, how long charges took) is named only where nothing above
--       names it. 0621's and 0622's reviews are left as they are.
--   (d) `ottoq_arbiter_assess` (same signature, same nightly job at 12:55 UTC, 7:55 AM CT) writes v3, with the trial,
--       and writes a review with nothing graded when it names a place to improve: the clock's audit and its world need
--       no graded order. Its code md5 covers v1, v3, the audit, the calibration, the scan and the words.
--   The audit, the words and the scan's review may be read as 0622's audit may; v3, which can run a trial, by the
--   service only. The tick path is untouched; nothing here writes a dial, a rule, the bar or a model.
--
-- ══ §3 CHECKS ══
--
--   P0: nothing in flight. P1: v1, the calibration, the audit 0622 wrote, the scan, the trial, the record's reader, the
--   clock and its keys, the base estimate, the band, the learned estimate, 0621's and 0624's forecast errors (whose
--   arrival and outflow keys v3 reads), and the assess are the bodies this file was written against (md5); nothing it
--   creates exists. Nothing here drops or deletes.
--   V1: on the twin depot's last 7 days the new audit is 0622's on every key they share: each kind's accuracy block,
--   and each covariate's groups, eta2 and adjusted eta2, but the run's (whose units now name a day for charges outside
--   a run).
--   V2: v3 on the twin depot (no trial): ranked 1..n in the stated order; every area carries its keys, a status and
--   kind from their sets, and an impact equal to its part's share; no title, finding or action carries an internal id
--   (a word with an underscore, dcfc, a lower-case l2, a migration number); graded and decisions are v1's; the run and
--   the binned air temperature are never named as a missed categorical.
--   V3: the review written at apply is v3, and with no trial run its areas are V2's.
--   tests/test_agent_self_review_sql.py executes the rest on the miniature depot.
--
-- ══ §4 RECERT ══
--
--   FALSE/FALSE. A read-only review of the check, written to an evidence table a person reads; no certification,
--   sweep or dial pair reads it, and the tick path is untouched.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0626_pre' (the assess as 0622 left it: it
--   writes v2 again); the reviews written since stay readable. DROP FUNCTION
--   public.ottoq_arbiter_self_assessment_v3(uuid, timestamptz, boolean), public.ottoq_charge_clock_audit_v2(uuid,
--   timestamptz, jsonb), public.ottoq_review_words(text, text), public.ottoq_review_change(numeric, text, text, integer),
--   public.ottoq_review_ct(timestamptz); DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0626_the_self_review_judges_the_clock_within_runs_and_ranks_what_to_build'.

BEGIN;

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0626 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_arbiter_self_assessment(uuid,timestamp with time zone)', '97d1401b', 'the review''s measurements (0621)'),
      ('public.ottoq_charge_clock_calibration(uuid,timestamp with time zone)', '8c11d790', 'the clock''s calibration (0622)'),
      ('public.ottoq_charge_clock_audit(uuid,timestamp with time zone,jsonb)', 'e2d4fa0b', 'the clock''s audit (0622)'),
      ('public.ottoq_evidence_regime_scan(uuid,timestamp with time zone,jsonb)', 'e19639b4', 'the scan (0625)'),
      ('public.ottoq_charge_clock_trial(uuid,uuid[],timestamp with time zone,jsonb,jsonb,boolean)', '9f90a8b2', 'the trial (0625)'),
      ('public.ottoq_evidence_regime_cuts(text,uuid,timestamp with time zone,timestamp with time zone)', '626ac79c', 'the record''s reader (0625)'),
      ('public.ottoq_charge_clock_model(uuid)', '5639032d', 'the depot''s clock (0622)'),
      ('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)', '03dc08a0', 'the clock (0622)'),
      ('public.ottoq_charge_clock_who(uuid,text,text,text)', '9d3ad357', 'the clock''s keys (0622)'),
      ('public.ottoq_charge_minutes_estimate(numeric,numeric,numeric,numeric,numeric)', '21f22ff8', 'the base estimate (0614)'),
      ('public.ottoq_charge_time_band(numeric)', '9212138a', 'the band (0619)'),
      ('public.ottoq_learned_estimate(uuid,text)', 'ff910870', 'the learned estimate (0619)'),
      ('public.ottoq_charge_order_forecast_errors(jsonb,jsonb)', '134f7426', 'the forecast errors (0621)'),
      ('public.ottoq_charge_order_forecast_errors(jsonb,jsonb,jsonb)', '2960ad9f', 'the outflow''s errors (0624)'),
      ('public.ottoq_arbiter_assess(uuid,integer)', 'cf8ed8d4', 'the nightly review (0622)'))
    AS x(sig, md5, what)
  LOOP
    IF left((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)), 8) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0626 P1: % is not the body this file was written against (md5 %); read it again', r.what, r.md5;
    END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_charge_clock_audit_v2(uuid,timestamp with time zone,jsonb)') IS NOT NULL
     OR to_regprocedure('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)') IS NOT NULL
     OR to_regprocedure('public.ottoq_review_words(text,text)') IS NOT NULL
     OR to_regprocedure('public.ottoq_review_change(numeric,text,text,integer)') IS NOT NULL
     OR to_regprocedure('public.ottoq_review_ct(timestamp with time zone)') IS NOT NULL THEN
    RAISE EXCEPTION '0626 P1: something this file creates already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0626_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_arbiter_assess(uuid,integer)'::regprocedure;

-- ══ (a) the clock's audit, within runs ══
CREATE FUNCTION public.ottoq_charge_clock_audit_v2(p_depot_id uuid, p_since timestamptz DEFAULT now() - interval '7 days',
                                                  p_model jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
SET timezone TO 'UTC'
AS $fn$
  -- 0626: 0622's audit (the same charges, clocks and accuracy block) judged within runs. The clock models a run's level
  -- (its run evidence) and the audit's residuals leave it in, so a variable that moves with the run (a run is one day's
  -- weather) took the run's share as its own (G360). Each charge's residual less its run's mean (outside a run, its
  -- day's) is what the clock leaves once it knows the run; every covariate's adjusted eta squared is computed on that too
  -- (adj_eta2_within, on the N - U degrees of freedom the run means leave), and the run, which the clock models, is
  -- judged across runs only. A variable the clock has no level for is also judged beyond the levels it has
  -- (adj_eta2_beyond: the within-run residual less, in turn, its class's, make and model's and band's means), so that a
  -- variable which only stands in for one of them (an hour of day that always meets the same band) is not named for it.
  -- Air temperature, which the clock does not model, is also read as a slope: per degree within runs (its t on the
  -- within-run residual) and between runs (the run means' charge-weighted regression, its R squared, over runs of 5 or
  -- more charges), with the spread of the runs' mean temperatures (10th to 90th percentile, by charge).
  WITH m AS (
    SELECT COALESCE(p_model, public.ottoq_charge_clock_model(p_depot_id)) AS j2,
           public.ottoq_learned_estimate(p_depot_id, 'charge_time_v1') AS j1
  ), e AS (
    SELECT l.session_id, l.sim_run_id AS run, l.charger_type AS kind, public.ottoq_charge_time_band(l.soc_start) AS band,
           COALESCE(l.sim_run_id::text, 'day ' || to_char(l.recorded_at, 'YYYY-MM-DD')) AS unit,
           w.j AS who, l.stall_id, l.ambient_temp_c, l.started_at, l.soc_end,
           ln((l.duration_min / est.m)::numeric) AS lr,
           public.ottoq_charge_clock(m.j2, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                     l.vehicle_kw, NULL) AS c2,
           public.ottoq_charge_clock(m.j1, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                     l.vehicle_kw, NULL) AS c1,
           l.recorded_at > COALESCE((m.j2 ->> 'fitted_at')::timestamptz, '-infinity'::timestamptz) AS oos
      FROM m, public.ottoq_charge_duration_ledger l
      JOIN public.vehicles v ON v.id = l.vehicle_id
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                      l.vehicle_kw) AS m) est
     WHERE l.depot_id = p_depot_id AND l.recorded_at >= p_since AND l.stopped_reason = 'completed'
       AND l.charger_type IN ('dcfc', 'l2') AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0
       AND l.tick_minutes IS NOT NULL AND l.tick_minutes <= 1
  ), pop AS (
    SELECT e.kind, count(*) FILTER (WHERE e.oos) >= 30 AS use_oos FROM e GROUP BY e.kind
  ), r0 AS (
    SELECT e.*, p.use_oos, e.lr - (e.c2 ->> 'f')::numeric AS res2, e.lr - (e.c1 ->> 'f')::numeric AS res1,
           (e.c2 ->> 'sd')::numeric AS sd2, (e.c1 ->> 'sd')::numeric AS sd1
      FROM e JOIN pop p USING (kind)
     WHERE e.oos OR NOT p.use_oos
  ), ra AS (    -- what the clock leaves once it knows the run: each residual less its run's mean
    SELECT r0.*, r0.res2 - avg(r0.res2) OVER (PARTITION BY r0.kind, r0.unit) AS rw FROM r0
  ), rb AS (    -- and beyond the levels the clock has: less, in turn, the class's, the make and model's and the band's means
    SELECT ra.*, ra.rw - avg(ra.rw) OVER (PARTITION BY ra.kind, ra.who ->> 'cls') AS rw1 FROM ra
  ), rc AS (
    SELECT rb.*, rb.rw1 - avg(rb.rw1) OVER (PARTITION BY rb.kind, rb.who ->> 'mdl') AS rw2 FROM rb
  ), r AS (
    SELECT rc.*, rc.rw2 - avg(rc.rw2) OVER (PARTITION BY rc.kind, rc.band) AS rwx FROM rc
  ), lv AS (    -- the degrees of freedom those levels take
    SELECT r.kind, count(DISTINCT r.who ->> 'cls') + count(DISTINCT r.who ->> 'mdl') + count(DISTINCT r.band) - 3 AS dfl
      FROM r GROUP BY r.kind
  ), un AS (
    SELECT r.kind, count(DISTINCT r.unit) AS u FROM r GROUP BY r.kind
  ), acc AS (
    SELECT r.kind, jsonb_build_object(
             'charges', count(*), 'out_of_sample', bool_and(r.use_oos), 'runs', max(un.u),
             'clock', jsonb_build_object(
               'model', (SELECT m.j2 ->> 'model' FROM m), 'estimate_id', (SELECT m.j2 -> 'estimate_id' FROM m),
               'mean_log_error', round(avg(r.res2), 4), 'mean_abs_log_error', round(avg(abs(r.res2)), 4),
               'mean_abs_log_error_within_run', round(avg(abs(r.rw)), 4),
               'in_80pct_band', round((count(*) FILTER (WHERE r.sd2 > 0 AND abs(r.res2 / r.sd2) <= 1.2816))::numeric / count(*), 3),
               'in_80pct_band_within_run', round((count(*) FILTER (WHERE r.sd2 > 0 AND abs(r.rw / r.sd2) <= 1.2816))::numeric / count(*), 3)),
             'v1', jsonb_build_object(
               'estimate_id', (SELECT m.j1 -> 'estimate_id' FROM m),
               'mean_log_error', round(avg(r.res1), 4), 'mean_abs_log_error', round(avg(abs(r.res1)), 4),
               'in_80pct_band', round((count(*) FILTER (WHERE r.sd1 > 0 AND abs(r.res1 / r.sd1) <= 1.2816))::numeric / count(*), 3))) AS j
      FROM r JOIN un USING (kind) GROUP BY r.kind
  ), cv AS (
    SELECT r.kind, x.cov, x.val, r.res2, r.rw, r.rwx
      FROM r CROSS JOIN LATERAL (VALUES
        ('class', r.who ->> 'cls'), ('model', r.who ->> 'mdl'), ('vehicle', r.who ->> 'veh'), ('band', r.band),
        ('run', r.unit), ('charger', r.stall_id::text),
        ('ambient_c', CASE WHEN r.ambient_temp_c IS NULL THEN 'unknown' ELSE (5 * floor(r.ambient_temp_c / 5))::int::text END),
        ('sim_hour', extract(hour FROM r.started_at)::int::text),
        ('to_full', CASE WHEN r.soc_end >= 99 THEN 'yes' ELSE 'no' END)) x(cov, val)
  ), g0 AS (
    SELECT cv.kind, cv.cov, cv.val, count(*) AS n FROM cv GROUP BY cv.kind, cv.cov, cv.val
  ), cv2 AS (
    SELECT cv.kind, cv.cov, CASE WHEN g0.n >= 5 THEN cv.val ELSE '(small groups)' END AS val, cv.res2, cv.rw, cv.rwx
      FROM cv JOIN g0 USING (kind, cov, val)
  ), g AS (
    SELECT cv2.kind, cv2.cov, cv2.val, count(*) AS n, avg(cv2.res2) AS m, avg(cv2.rw) AS mw, avg(cv2.rwx) AS mx
      FROM cv2 GROUP BY cv2.kind, cv2.cov, cv2.val
  ), t AS (
    SELECT cv2.kind, cv2.cov, count(*) AS n, avg(cv2.res2) AS m, avg(cv2.rw) AS mw, avg(cv2.rwx) AS mx,
           sum(cv2.res2 * cv2.res2) - count(*) * avg(cv2.res2) * avg(cv2.res2) AS sst,
           sum(cv2.rw * cv2.rw) - count(*) * avg(cv2.rw) * avg(cv2.rw) AS sstw,
           sum(cv2.rwx * cv2.rwx) - count(*) * avg(cv2.rwx) * avg(cv2.rwx) AS sstx
      FROM cv2 GROUP BY cv2.kind, cv2.cov
  ), eta AS (
    SELECT t.kind, t.cov, t.n, count(g.val) AS groups, sum(g.n * (g.m - t.m) ^ 2) AS ssb, sum(g.n * (g.mw - t.mw) ^ 2) AS ssbw,
           sum(g.n * (g.mx - t.mx) ^ 2) AS ssbx, max(t.sst) AS sst, max(t.sstw) AS sstw, max(t.sstx) AS sstx
      FROM t JOIN g USING (kind, cov) GROUP BY t.kind, t.cov, t.n
  ), adj AS (
    SELECT eta.*, un.u,
           CASE WHEN eta.sst > 0 THEN eta.ssb / eta.sst END AS eta2,
           CASE WHEN eta.sst > 0 AND eta.n > eta.groups
                THEN 1 - (1 - eta.ssb / eta.sst) * (eta.n - 1) / (eta.n - eta.groups) END AS adj_eta2,
           CASE WHEN eta.cov <> 'run' AND eta.sstw > 0 AND eta.n - un.u - eta.groups + 1 > 0
                THEN 1 - (1 - eta.ssbw / eta.sstw) * (eta.n - un.u) / (eta.n - un.u - eta.groups + 1) END AS adj_eta2_within,
           CASE WHEN eta.cov NOT IN ('run', 'class', 'model', 'vehicle', 'band') AND eta.sstx > 0
                     AND eta.n - un.u - lv.dfl - eta.groups + 1 > 0
                THEN 1 - (1 - eta.ssbx / eta.sstx) * (eta.n - un.u - lv.dfl) / (eta.n - un.u - lv.dfl - eta.groups + 1)
                END AS adj_eta2_beyond
      FROM eta JOIN un USING (kind) JOIN lv USING (kind)
  ), cov AS (
    SELECT adj.kind, jsonb_agg(jsonb_build_object(
             'covariate', adj.cov, 'modelled', adj.cov IN ('class', 'model', 'vehicle', 'band', 'run'),
             'judged', CASE WHEN adj.cov = 'run' THEN 'across_runs' ELSE 'within_runs' END,
             'groups', adj.groups, 'eta2', round(adj.eta2, 4), 'adj_eta2', round(adj.adj_eta2, 4),
             'adj_eta2_within', round(adj.adj_eta2_within, 4), 'adj_eta2_beyond', round(adj.adj_eta2_beyond, 4),
             'worst_groups', (SELECT jsonb_agg(jsonb_build_object('group', w.val, 'n', w.n, 'mean_log_error', round(w.m, 3),
                                                                  'mean_log_error_within_run', round(w.mw, 3))
                                               ORDER BY abs(w.mw) DESC, w.val)
                                FROM (SELECT g.* FROM g WHERE g.kind = adj.kind AND g.cov = adj.cov
                                       ORDER BY abs(g.mw) DESC, g.val LIMIT 3) w))
             ORDER BY COALESCE(adj.adj_eta2_within, adj.adj_eta2) DESC NULLS LAST, adj.cov) AS j
      FROM adj GROUP BY adj.kind
  ), tp AS (    -- air temperature as a slope: within runs, on the charges that carry one, and their runs' means
    SELECT r.kind, r.unit, r.ambient_temp_c::float8 AS x, r.res2::float8 AS y,
           avg(r.ambient_temp_c::float8) OVER (PARTITION BY r.kind, r.unit) AS xm,
           avg(r.res2::float8) OVER (PARTITION BY r.kind, r.unit) AS ym,
           count(*) OVER (PARTITION BY r.kind, r.unit) AS nu
      FROM r WHERE r.ambient_temp_c IS NOT NULL
  ), tw AS (
    SELECT tp.kind, count(*) AS n, count(DISTINCT tp.unit) AS u,
           sum((tp.x - tp.xm) * (tp.y - tp.ym)) AS sxy, sum((tp.x - tp.xm) ^ 2) AS sxx, sum((tp.y - tp.ym) ^ 2) AS syy
      FROM tp GROUP BY tp.kind
  ), tb AS (
    SELECT tp.kind, count(DISTINCT tp.unit) AS u, regr_slope(tp.ym, tp.xm) AS b, regr_r2(tp.ym, tp.xm) AS r2,
           percentile_cont(0.1) WITHIN GROUP (ORDER BY tp.xm) AS x10, percentile_cont(0.9) WITHIN GROUP (ORDER BY tp.xm) AS x90
      FROM tp WHERE tp.nu >= 5 GROUP BY tp.kind
  ), temp AS (
    SELECT tw.kind, jsonb_build_object(
             'charges', tw.n, 'runs', tw.u,
             'within', jsonb_build_object(
               'per_degree', round((tw.sxy / NULLIF(tw.sxx, 0))::numeric, 4),
               't', round(((tw.sxy / NULLIF(tw.sxx, 0))
                           / NULLIF(sqrt(GREATEST(tw.syy - tw.sxy * tw.sxy / NULLIF(tw.sxx, 0), 0)
                                         / NULLIF(tw.n - tw.u - 1, 0) / NULLIF(tw.sxx, 0)), 0))::numeric, 2),
               'r2', round((tw.sxy * tw.sxy / NULLIF(tw.sxx * tw.syy, 0))::numeric, 4),
               'sd_c', round(sqrt(tw.sxx / NULLIF(tw.n, 0))::numeric, 2)),
             'between', jsonb_build_object(
               'runs', tb.u, 'per_degree', round(tb.b::numeric, 4), 'r2', round(tb.r2::numeric, 3),
               'run_mean_c', jsonb_build_array(round(tb.x10::numeric, 1), round(tb.x90::numeric, 1)))) AS j
      FROM tw LEFT JOIN tb USING (kind)
  )
  SELECT jsonb_build_object(
    'v', 2, 'since', p_since,
    'by_kind', COALESCE((SELECT jsonb_object_agg(acc.kind, acc.j || jsonb_build_object(
                                  'covariates', COALESCE(cov.j, '[]'::jsonb),
                                  'air_temperature', temp.j))
                           FROM acc LEFT JOIN cov USING (kind) LEFT JOIN temp USING (kind)), '{}'::jsonb),
    'rule', 'each covariate''s adjusted eta squared on the clock''s residuals across runs (adj_eta2, as 0622) and within '
            'runs (adj_eta2_within: each residual less its run''s mean, outside a run its day''s; df N - U); a covariate '
            'the clock has no level for also beyond its levels (adj_eta2_beyond: less, in turn, the class''s, make and '
            'model''s and band''s means); the run is modelled (the clock''s run evidence) and judged across runs only; air '
            'temperature also as a slope within runs and between runs (runs of 5 or more charges, weighted by charges)')
$fn$;
-- ══ (b) the review's words ══
CREATE FUNCTION public.ottoq_review_words(p_what text, p_key text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0626: the self-review's words for its own keys, so a finding reads as a sentence and never as an internal id: a kind
  -- of charger, a covariate of the clock's audit, a part of what made the check wrong, an agent's move (as what the
  -- order did), a dwell class (as which cars), and a vehicle class by its maker's name from ottoq_vehicle_classes (maker
  -- and model where two active classes share a maker; the model where the maker is Generic). A key with no words reads
  -- with its underscores as spaces.
  SELECT COALESCE(
    CASE WHEN p_what = 'class' THEN (
           SELECT CASE WHEN c.oem_name IS NULL OR c.oem_name = 'Generic' THEN COALESCE(c.model, c.vehicle_class_code)
                       WHEN (SELECT count(*) FROM public.ottoq_vehicle_classes c2
                              WHERE c2.oem_name = c.oem_name AND c2.status = 'active') > 1
                       THEN c.oem_name || ' ' || regexp_replace(COALESCE(c.model, ''), '\s*\(.*\)\s*$', '')
                       ELSE c.oem_name END
             FROM public.ottoq_vehicle_classes c WHERE c.vehicle_class_code = p_key)
         ELSE (SELECT w.words FROM (VALUES
           ('kind', 'dcfc', 'fast chargers'), ('kind', 'l2', 'L2 chargers'), ('kind', '*', 'every charger'),
           ('covariate', 'class', 'the vehicle class'), ('covariate', 'model', 'make and model'),
           ('covariate', 'vehicle', 'each car''s own level'), ('covariate', 'band', 'the starting charge'),
           ('covariate', 'run', 'the run'), ('covariate', 'charger', 'the charger'),
           ('covariate', 'ambient_c', 'air temperature'), ('covariate', 'sim_hour', 'the hour of day'),
           ('covariate', 'to_full', 'charging to full'),
           ('part', 'arrivals', 'when cars came home'), ('part', 'appeared', 'cars it never saw coming'),
           ('part', 'running', 'charges already under way'), ('part', 'charge_times', 'how long charges took'),
           ('part', 'faults', 'chargers that faulted'),
           ('move', 'due_rescue_fast', 'made a car that would be late ready by its due time on a fast charger'),
           ('move', 'due_rescue', 'made a car that would be late ready by its due time on an L2 charger'),
           ('move', 'low_battery_on_l2', 'put a battery under 45% on an L2 charger'),
           ('move', 'top_off_ahead', 'seated a car already at 80% or more ahead of the kernel'),
           ('move', 'late_car_first', 'seated a car already past its due time first'),
           ('move', 'kind_swap', 'moved a car to the other kind of charger'),
           ('move', 'reorder_only', 'only reordered the line'),
           ('dwell', 'clear', 'cars with nothing left to do'), ('dwell', 'bay', 'cars waiting on a bay service'),
           ('dwell', 'boot', 'run-start cars with no visit'), ('dwell', 'new', 'cars out at work'),
           ('dwell', 'pooled', 'cars of a class with no curve of its own'))
           w(what, key, words) WHERE w.what = p_what AND w.key = p_key) END,
    replace(COALESCE(p_key, '?'), '_', ' '))
$fn$;

CREATE FUNCTION public.ottoq_review_change(p_ratio numeric, p_less text DEFAULT 'shorter', p_more text DEFAULT 'longer',
                                           p_digits integer DEFAULT 0)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0626: a ratio as the self-review says it: 0.32 is "68% shorter", 1.093 is "9% longer", and with p_digits 1, 1.0155
  -- is "1.6% longer"; a change that rounds to nothing is "no different".
  SELECT CASE WHEN p_ratio IS NULL OR p_ratio <= 0 THEN 'by an unknown amount'
              WHEN round(100 * abs(p_ratio - 1), GREATEST(COALESCE(p_digits, 0), 0)) = 0 THEN 'no different'
              ELSE abs(round(100 * (p_ratio - 1), GREATEST(COALESCE(p_digits, 0), 0)))::text || '% '
                   || CASE WHEN p_ratio < 1 THEN p_less ELSE p_more END END
$fn$;

CREATE FUNCTION public.ottoq_review_ct(p_at timestamptz)
RETURNS text
LANGUAGE sql
STABLE PARALLEL SAFE
AS $fn$
  -- 0626: a real-clock moment as the self-review says it, in the depot's own time (CLAUDE.md rule 7): "Sep 30, 6:53 AM CT".
  SELECT CASE WHEN p_at IS NULL THEN 'an unknown moment'
              ELSE to_char(p_at AT TIME ZONE 'America/Chicago', 'Mon FMDD, FMHH12:MI AM') || ' CT' END
$fn$;
-- ══ (c) the review ══
CREATE FUNCTION public.ottoq_arbiter_self_assessment_v3(p_depot_id uuid, p_since timestamptz DEFAULT now() - interval '7 days',
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
   strong before thin, by impact, then tier, then weight. Read-only; every area is for a person (CLAUDE.md rule 10). */
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
    SELECT ib.value ->> 'src' AS src, (ib.value ->> 'eta')::numeric AS fc, COALESCE((ib.value ->> 'trip')::numeric, 0) AS trip,
           COALESCE((ib.value ->> 'esd')::numeric, 0) AS esd,
           COALESCE((h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'arrived'])::boolean, false) AS arrived,
           (h.realized #>> ARRAY['inbound', ib.value ->> 'id', 'eta'])::numeric AS act
      FROM h CROSS JOIN LATERAL jsonb_array_elements(COALESCE(h.state -> 'inbound', '[]'::jsonb)) ib
  ), z AS (
    SELECT ar.act - ar.fc AS err, ar.fc - ar.trip AS hz, ln((ar.act - ar.trip) / (ar.fc - ar.trip)) / ar.esd AS z
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
        'part', 'arrivals', 'status', 'open', 'thin', false, 'tier', 2, 'weight', v_nz,
        'title', v_title, 'finding', v_txt,
        'action', upper(left(v_act, 1)) || substr(v_act, 2) || '.',
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
    v_status := CASE WHEN x.part = 'charge_times' AND v_rebuilt IS NOT NULL THEN 'built' ELSE 'open' END;
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
                 || CASE WHEN v_status = 'built' THEN v_note ELSE '' END,
      'action', CASE x.part
                  WHEN 'faults' THEN 'Sample charger faults in the futures at the depot''s own fault rate and repair time.'
                  WHEN 'arrivals' THEN 'More futures sample this variation better; nothing to rebuild.'
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

-- ══ (d) the nightly review writes v3 ══
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
   is written when it names a place to improve, since the clock's audit and its world need no graded order. */
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
              || pg_get_functiondef('public.ottoq_review_words(text,text)'::regprocedure)))
  RETURNING assessment_id INTO v_id;
  RETURN v_id;
END $fn$;

-- ══ who may call what: the audit and the words as 0622's audit may be; v3, which can run a trial, the service only ══
GRANT EXECUTE ON FUNCTION public.ottoq_charge_clock_audit_v2(uuid, timestamptz, jsonb) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_review_words(text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_review_change(numeric, text, text, integer) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_review_ct(timestamptz) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_arbiter_self_assessment_v3(uuid, timestamptz, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_arbiter_self_assessment_v3(uuid, timestamptz, boolean) TO service_role;

-- ══ V1: the new audit is 0622's on every key they share, but the run's ══
DO $v1$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_since timestamptz := now() - interval '7 days';
  v_old   jsonb := public.ottoq_charge_clock_audit(c_depot, v_since, NULL);
  v_new   jsonb := public.ottoq_charge_clock_audit_v2(c_depot, v_since, NULL);
  v_bad   text;
BEGIN
  SELECT string_agg(x.k || ': ' || x.what, '; ') INTO v_bad
    FROM (SELECT o.key AS k, 'accuracy' AS what
            FROM jsonb_each(COALESCE(v_old -> 'by_kind', '{}'::jsonb)) o
           WHERE (o.value - 'covariates') IS DISTINCT FROM
                 jsonb_build_object('charges', v_new #> ARRAY['by_kind', o.key, 'charges'],
                                    'out_of_sample', v_new #> ARRAY['by_kind', o.key, 'out_of_sample'],
                                    'clock', (v_new #> ARRAY['by_kind', o.key, 'clock']) - 'mean_abs_log_error_within_run'
                                             - 'in_80pct_band_within_run',
                                    'v1', v_new #> ARRAY['by_kind', o.key, 'v1'])
          UNION ALL
          SELECT o.key, 'covariate ' || (c.value ->> 'covariate')
            FROM jsonb_each(COALESCE(v_old -> 'by_kind', '{}'::jsonb)) o
            CROSS JOIN LATERAL jsonb_array_elements(o.value -> 'covariates') c
            LEFT JOIN LATERAL (SELECT n.value FROM jsonb_array_elements(v_new #> ARRAY['by_kind', o.key, 'covariates']) n
                                WHERE n.value ->> 'covariate' = c.value ->> 'covariate') n ON true
           WHERE c.value ->> 'covariate' <> 'run'
             AND (n.value IS NULL OR (c.value -> 'groups', c.value -> 'eta2', c.value -> 'adj_eta2')
                                     IS DISTINCT FROM (n.value -> 'groups', n.value -> 'eta2', n.value -> 'adj_eta2'))
          UNION ALL
          SELECT n.key, 'a kind 0622''s audit has not'
            FROM jsonb_each(COALESCE(v_new -> 'by_kind', '{}'::jsonb)) n WHERE NOT (v_old -> 'by_kind') ? n.key) x;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0626 V1: the new audit is not 0622''s on the keys they share: %', v_bad;
  END IF;
  RAISE NOTICE '0626 V1: the audit within runs keeps 0622''s accuracy and shares on % kinds; within runs on fast chargers %, on L2 %; air temperature %',
    (SELECT count(*) FROM jsonb_object_keys(COALESCE(v_new -> 'by_kind', '{}'::jsonb))),
    (SELECT jsonb_object_agg(c.value ->> 'covariate', c.value -> 'adj_eta2_within')
       FROM jsonb_array_elements(COALESCE(v_new #> '{by_kind,dcfc,covariates}', '[]'::jsonb)) c),
    (SELECT jsonb_object_agg(c.value ->> 'covariate', c.value -> 'adj_eta2_within')
       FROM jsonb_array_elements(COALESCE(v_new #> '{by_kind,l2,covariates}', '[]'::jsonb)) c),
    (SELECT jsonb_object_agg(k.key, k.value -> 'air_temperature') FROM jsonb_each(COALESCE(v_new -> 'by_kind', '{}'::jsonb)) k);
END $v1$;

-- ══ V2: the review, ranked and in words ══
CREATE TEMP TABLE v0626_review ON COMMIT DROP AS
SELECT public.ottoq_arbiter_self_assessment_v3('11111111-1111-1111-1111-111111111111'::uuid, now() - interval '7 days', false) AS j,
       public.ottoq_arbiter_self_assessment('11111111-1111-1111-1111-111111111111'::uuid, now() - interval '7 days') AS j1;

DO $v2$
DECLARE
  v      jsonb := (SELECT j FROM v0626_review);
  v1     jsonb := (SELECT j1 FROM v0626_review);
  v_bad  text;
  v_n    int;
BEGIN
  v_n := jsonb_array_length(v -> 'improvement_areas');
  SELECT string_agg(a.value ->> 'area' || ': ' || x.what, '; ') INTO v_bad
    FROM jsonb_array_elements(v -> 'improvement_areas') WITH ORDINALITY a(value, i)
    CROSS JOIN LATERAL (VALUES
      (CASE WHEN (a.value ->> 'rank')::int IS DISTINCT FROM a.i::int THEN 'ranked ' || COALESCE(a.value ->> 'rank', 'null')
                                                                          || ' at place ' || a.i END),
      (CASE WHEN NOT a.value ?& ARRAY['area', 'kind', 'part', 'impact', 'status', 'thin', 'tier', 'weight', 'title', 'finding',
                                      'action', 'evidence', 'rank'] THEN 'a key is missing' END),
      (CASE WHEN a.value ->> 'status' NOT IN ('open', 'built') THEN 'status ' || (a.value ->> 'status') END),
      (CASE WHEN a.value ->> 'kind' NOT IN ('capability_gap', 'calibration', 'forecast', 'threshold', 'agent', 'world_changed')
            THEN 'kind ' || (a.value ->> 'kind') END),
      (CASE WHEN (a.value -> 'impact') IS DISTINCT FROM COALESCE(v #> ARRAY['what_made_the_check_wrong', 'parts', a.value ->> 'part',
                                                                             'verdict_share'], 'null'::jsonb)
            THEN 'impact is not its part''s share' END),
      (CASE WHEN concat_ws(' ', a.value ->> 'title', a.value ->> 'finding', a.value ->> 'action')
                 ~ '(\m[a-z0-9]+_[a-z0-9_]+\M|\mdcfc\M|\ml2\M|\m0[4-6][0-9][0-9]\M|charge_time)'
            THEN 'an internal id in its words: '
                 || substring(concat_ws(' ', a.value ->> 'title', a.value ->> 'finding', a.value ->> 'action')
                              FROM '(\m[a-z0-9]+_[a-z0-9_]+\M|\mdcfc\M|\ml2\M|\m0[4-6][0-9][0-9]\M|charge_time)') END),
      (CASE WHEN a.value ->> 'area' IN ('charge_clock_misses_run', 'charge_clock_misses_ambient_c', 'charge_clock_stale_run')
            THEN 'the run or the binned air temperature named as a variable' END),
      (CASE WHEN length(COALESCE(a.value ->> 'title', '')) < 10 OR length(COALESCE(a.value ->> 'finding', '')) < 20
                 OR length(COALESCE(a.value ->> 'action', '')) < 10 THEN 'words missing' END)) x(what)
   WHERE x.what IS NOT NULL;
  IF v_bad IS NULL THEN       -- the order is the stated one
    SELECT string_agg('the order breaks at ' || (b.value ->> 'rank'), '; ') INTO v_bad
      FROM jsonb_array_elements(v -> 'improvement_areas') b
      JOIN jsonb_array_elements(v -> 'improvement_areas') c ON (c.value ->> 'rank')::int = (b.value ->> 'rank')::int + 1
     WHERE (b.value ->> 'status' = 'built', (b.value ->> 'thin')::boolean, -COALESCE((b.value ->> 'impact')::numeric, -1),
            (b.value ->> 'tier')::int, -COALESCE((b.value ->> 'weight')::numeric, 0))
         > (c.value ->> 'status' = 'built', (c.value ->> 'thin')::boolean, -COALESCE((c.value ->> 'impact')::numeric, -1),
            (c.value ->> 'tier')::int, -COALESCE((c.value ->> 'weight')::numeric, 0));
  END IF;
  IF v_bad IS NOT NULL OR (v ->> 'graded') IS DISTINCT FROM (v1 ->> 'graded') OR (v ->> 'decisions') IS DISTINCT FROM (v1 ->> 'decisions')
     OR (v ->> 'v')::int IS DISTINCT FROM 3 THEN
    RAISE EXCEPTION '0626 V2: the review is not ranked or not in words: %', COALESCE(v_bad, 'graded or decisions differ from 0621''s');
  END IF;
  RAISE NOTICE '0626 V2: % graded, % areas (% open, % built), in words; ranked: %',
    v ->> 'graded', v_n, v ->> 'areas_open', v ->> 'areas_built',
    (SELECT string_agg((a.value ->> 'rank') || '. [' || (a.value ->> 'status') || CASE WHEN (a.value ->> 'thin')::boolean THEN ', thin' ELSE '' END
                       || COALESCE(', ' || round(100 * (a.value ->> 'impact')::numeric) || '%', '') || '] ' || (a.value ->> 'title'),
                       ' | ' ORDER BY (a.value ->> 'rank')::int)
       FROM jsonb_array_elements(v -> 'improvement_areas') a);
END $v2$;

-- ══ V3: the review written at apply is v3 ══
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_id   bigint := public.ottoq_arbiter_assess(c_depot, 7);
  v_row  record;
  v      jsonb := (SELECT j FROM v0626_review);
BEGIN
  IF v_id IS NULL THEN
    IF jsonb_array_length(v -> 'improvement_areas') > 0 OR COALESCE((v ->> 'graded')::int, 0) > 0 THEN
      RAISE EXCEPTION '0626 V3: the review names % places and none was written', jsonb_array_length(v -> 'improvement_areas');
    END IF;
    RAISE NOTICE '0626 V3: nothing graded and nothing to name here: no review written';
    RETURN;
  END IF;
  SELECT * INTO v_row FROM public.ottoq_arbiter_assessments WHERE assessment_id = v_id;
  IF (v_row.assessment ->> 'v')::int IS DISTINCT FROM 3
     OR (jsonb_typeof(v_row.assessment -> 'world_trials') = 'object' AND v_row.assessment -> 'world_trials' = '{}'::jsonb
         AND v_row.improvement_areas IS DISTINCT FROM v -> 'improvement_areas') THEN
    RAISE EXCEPTION '0626 V3: the review written (%) is not v3, or with no trial run its areas are not V2''s', v_id;
  END IF;
  RAISE NOTICE '0626 V3: review % written, v3, % areas, trials %', v_id, jsonb_array_length(v_row.improvement_areas),
    v_row.assessment -> 'world_trials';
END $v3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0626_the_self_review_judges_the_clock_within_runs_and_ranks_what_to_build', false, false,
  'The check''s nightly self-review is ottoq_arbiter_self_assessment_v3: the charge clock audited within runs '
  '(ottoq_charge_clock_audit_v2, with air temperature as a slope within and between runs), a change in the clock''s '
  'world named by the scan and tried out of sample, the arrivals'' bulk and tails, the outflow''s grade, and every area '
  'ranked by the share of what made the check wrong its part carries, marked open or built, in plain words with an '
  'action for a person. FALSE/FALSE: read-only, written to an evidence table; the tick path is untouched.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
