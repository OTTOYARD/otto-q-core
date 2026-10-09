-- migration-version: 20261008132327
-- migration-name:    the_kernel_learns_how_long_a_charge_takes_and_when_a_car_comes_back
--
-- 0619  **The kernel learns how long a charge takes and when a car comes back, from its own evidence.** Two learned
--       estimates, fitted from ledgers the engine already keeps and refitted each morning after the overnight tests:
--       a charge-time model (by how much a charge on each kind of charger, from each band of battery, runs longer than
--       `ottoq_charge_minutes_estimate` says) and a return model (the battery level at which a working car is called
--       home, how fast a working car drains, and how long the drive back takes). Nothing on the tick path reads
--       either. 0620's check of the agent's charge order is the first reader and the agent's board the second.
--       CLAUDE.md rule 10: production OTTO-Q "overnight ... updates its estimates (how long charges take, when cars
--       return ...)". This is that, and it changes no rule, no dial and no decision.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0618's check projected the charge line with `ottoq_charge_minutes_estimate`, which 0614 wrote "for ORDERING and for
--   the agent's board only" and never compared with a real charge. Measured 2026-10-08 on the twin depot's charge
--   ledger (`ottoq_charge_duration_ledger`, completed charges, last 21 days, runs at ticks of 0.13-0.31 sim-minutes),
--   charges ran longer than the estimate by a median factor of
--
--       L2     1.35 below 45%   1.40 at 45-70%   1.43 at 70-85%   1.85 at 85% and above   (robust log sd 0.10-0.16)
--       DCFC   1.46 below 45%   1.81 at 45-70%   1.92 at 70-85%   2.38 at 85% and above   (robust log sd 0.29-0.52)
--
--   So the check read the median top-off on a fast charger as 17 minutes when the fitted factor puts it near 40, and a car
--   at 27% as 174 minutes on an L2 when it takes about 239 (the sessions of db/checks/0415's three runs say the same).
--   (Corrected after apply: the file as applied added "as long as on an L2", comparing the band's averages over two
--   different groups of cars; for the depot's average car (96.5 kWh) from 90% the fitted clock gives 31 minutes on a
--   350 kW fast charger against 56 on an L2.)
--   An order compared on that clock can look better than the kernel's and be worse. And the check saw no car coming
--   back, though the engine's own dispatches say when one will: on those three runs, 265 of 349 returns were a car
--   reaching its low-battery reserve, at 49.2% (p10 44.9, p90 50.0), after draining 0.69% a minute (sd 0.08) since it
--   left at 98%, with a 1.6-minute drive home; over the last 21 days of runs at fine ticks (18 runs, 1,376 returns),
--   1,205 were, at 49.9% with a 1.25-minute drive. When a working car comes back is a forecast the depot can make. 0618
--   made none. The other returns are not: over every run at the depot in those 21 days (22,509 returns, mostly the
--   overnight sweeps at 5-minute ticks), 79.2% were for a service interval, a wash cadence, a surplus on the road or
--   another reason no battery reading foretells: 83.5% at the sweeps, 12.4% at fine ticks. That share is reported with
--   each fit, as the size of what the forecast cannot see. (Corrected after apply: the file as applied said 83.5% of
--   every run, which is the sweeps' share alone; the fit's own `other_share_all_ticks` read 0.7917.)
--
-- ══ §2 WHAT ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `public.ottoq_learned_estimates`: append-only evidence, one row per fit: the depot, the model, the evidence
--       window, what was fitted (`params`), whether it is usable, the md5 of the code that fitted it, and from how many
--       charges or returns over how many runs. No run column: an estimate belongs to the depot and survives every purge.
--   (b) `ottoq_fit_charge_time_model(depot, through, window, note)`: from the charge ledger, per kind of charger and
--       band of starting battery (below 45, 45-70, 70-85, 85 and above), the median ratio of a completed charge's
--       minutes to `ottoq_charge_minutes_estimate`'s, its robust log spread (1.4826 x the median absolute deviation of
--       the log ratio) and its p10 and p90. A cell is fitted on charges recorded at ticks of a minute or less when it
--       has 30 of them (the regime nearest a real depot's continuous clock), else on every charge, and says which; a
--       cell with fewer than 30 in either is fitted but not usable. The kind's own cell (`dcfc:*`, `l2:*`) is fitted
--       the same way and is the fallback.
--   (c) `ottoq_fit_return_model(depot, through, window, note)`: from the engine's dispatches at the depot: the battery
--       level at which a working car is called home for its reserve (median `soc_at_decision` of `low_soc_reserve`
--       returns), the drain while working (median % a minute and its log spread), the drive home (median and p90
--       minutes), and the share and rate per working hour of returns for any other reason. Those are reported, never
--       forecast: a return the engine cannot see coming is a gap to name, not one to guess. Fitted on runs at ticks of a
--       minute or less when they hold 30 reserve returns (at 5-minute ticks a 1-minute drive reads as 5), else on all,
--       and says which; the other-reason share over every run rides along as `other_share_all_ticks`.
--   (d) `ottoq_learned_estimate(depot, model)`: the latest fit, as {estimate_id, fitted_at, usable, n_evidence,
--       params}.
--   (e) `ottoq_charge_minutes_learned_with(model, kind, battery kWh, soc from, soc to, charger kW, inlet kW)` and
--       `ottoq_charge_minutes_learned(depot, ...)`: `ottoq_charge_minutes_estimate` times the factor of the car's cell
--       (the band of the battery it starts from), else the kind's, else 1.0. Rule 9 is untouched: these are minutes
--       to the car's full target, and nothing reads them to shorten a charge.
--   (f) pg_cron 'ottoq-learn-estimates-nightly' at 11:20 UTC (6:20 AM CT), after the sweep window closes at 11:00
--       UTC, so a fit reads the night's runs: both fits for the twin depot only (rule 8). This file fits once on apply.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: `ottoq_charge_minutes_estimate` is 0614's body (md5), because every factor is a ratio to
--   it; every column the fits read exists; nothing this file creates exists yet.
--   V1: the learned minutes on a model written here: the cell's factor, the kind's when the cell is not usable, 1.0 with
--   no model; NULL with no battery size and 0 when nothing is owed, as 0614's estimate. V2: on the live ledger, each
--   usable charge-time cell has a factor in (0.2, 5) and a log spread at or above 0, and the return model, when usable,
--   a threshold in (5, 95), a drain above 0 and a drive of 0 or more; both are printed. V3: the job is scheduled.
--   tests/test_agent_arbiter_sql.py fits both models on charges and returns it writes and reads the learned minutes back.
--
-- ══ §4 RECERT ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   FALSE/FALSE. Nothing on the tick path, in a certification arm, a sweep or a dial pair reads the table or the
--   functions; the job writes only the table.
--
-- ROLLBACK: SELECT cron.unschedule('ottoq-learn-estimates-nightly');
--   DROP FUNCTION public.ottoq_charge_minutes_learned(uuid, text, numeric, numeric, numeric, numeric, numeric),
--                 public.ottoq_charge_minutes_learned_with(jsonb, text, numeric, numeric, numeric, numeric, numeric),
--                 public.ottoq_learned_estimate(uuid, text),
--                 public.ottoq_fit_return_model(uuid, timestamptz, interval, text),
--                 public.ottoq_fit_charge_time_model(uuid, timestamptz, interval, text),
--                 public.ottoq_charge_time_band(numeric);
--   DROP TABLE public.ottoq_learned_estimates; DROP FUNCTION public.ottoq_learned_estimates_append_only();
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0619_the_kernel_learns_how_long_a_charge_takes_and_when_a_car_comes_back'.

BEGIN;

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0619 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE v_missing text;
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'public.ottoq_charge_minutes_estimate(numeric,numeric,numeric,numeric,numeric)'::regprocedure)
     IS DISTINCT FROM '21f22ff887d40b57a3039f5d65e978af' THEN
    RAISE EXCEPTION '0619 P1: ottoq_charge_minutes_estimate is not 0614''s body (21f22ff8); every factor is a ratio to it';
  END IF;
  SELECT string_agg(x.t || '.' || x.c, ', ') INTO v_missing
    FROM (VALUES ('ottoq_charge_duration_ledger', 'depot_id'), ('ottoq_charge_duration_ledger', 'recorded_at'),
                 ('ottoq_charge_duration_ledger', 'stopped_reason'), ('ottoq_charge_duration_ledger', 'duration_min'),
                 ('ottoq_charge_duration_ledger', 'soc_start'), ('ottoq_charge_duration_ledger', 'soc_end'),
                 ('ottoq_charge_duration_ledger', 'battery_kwh'), ('ottoq_charge_duration_ledger', 'charger_kw'),
                 ('ottoq_charge_duration_ledger', 'vehicle_kw'), ('ottoq_charge_duration_ledger', 'charger_type'),
                 ('ottoq_charge_duration_ledger', 'tick_minutes'), ('ottoq_charge_duration_ledger', 'sim_run_id'),
                 ('ottoq_vehicle_dispatches', 'sim_run_id'), ('ottoq_vehicle_dispatches', 'created_at'),
                 ('ottoq_vehicle_dispatches', 'dispatched_at'), ('ottoq_vehicle_dispatches', 'returning_started_at'),
                 ('ottoq_vehicle_dispatches', 'actual_return_at'), ('ottoq_vehicle_dispatches', 'soc_at_dispatch_pct'),
                 ('ottoq_vehicle_dispatches', 'return_evidence'), ('ottoq_vehicle_dispatches', 'return_trigger'),
                 ('ottoq_sim_runs', 'depot_id')) AS x(t, c)
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns ic
                      WHERE ic.table_schema = 'public' AND ic.table_name = x.t AND ic.column_name = x.c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0619 P1: columns this file reads are missing: %', v_missing;
  END IF;
  IF to_regclass('public.ottoq_learned_estimates') IS NOT NULL
     OR to_regprocedure('public.ottoq_charge_time_band(numeric)') IS NOT NULL
     OR to_regprocedure('public.ottoq_learned_estimate(uuid,text)') IS NOT NULL THEN
    RAISE EXCEPTION '0619 P1: the table or a function this file creates already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-learn-estimates-nightly') THEN
    RAISE EXCEPTION '0619 P1: a cron job named ottoq-learn-estimates-nightly already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0619_the_kernel_learns_how_long_a_charge_takes_and_when_a_car_comes_back') THEN
    RAISE EXCEPTION '0619 P1: already applied';
  END IF;
END $premises$;

-- ══ (a) the ledger of fits ═════════════════════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.ottoq_learned_estimates (
  estimate_id      bigserial PRIMARY KEY,
  depot_id         uuid NOT NULL,
  model            text NOT NULL CHECK (model IN ('charge_time_v1', 'return_v1')),
  fitted_at        timestamptz NOT NULL DEFAULT now(),
  --: the real-clock window of evidence read (the ledgers' recorded_at / created_at), not a sim clock
  evidence_from    timestamptz,
  evidence_through timestamptz,
  n_evidence       integer NOT NULL,
  n_runs           integer NOT NULL,
  usable           boolean NOT NULL,
  params           jsonb NOT NULL,
  code_md5         text NOT NULL,
  fitted_by        text NOT NULL DEFAULT current_user,
  note             text
);

COMMENT ON TABLE public.ottoq_learned_estimates IS
'0619. One row per fit of a learned estimate for a depot: charge_time_v1 (per kind of charger and band of starting battery, the factor by which a completed charge runs longer than ottoq_charge_minutes_estimate, with its log spread) and return_v1 (the battery level a working car is called home at, its drain while working, the drive home, and the returns no forecast can see). Fitted from ottoq_charge_duration_ledger and ottoq_vehicle_dispatches by ottoq_fit_charge_time_model / ottoq_fit_return_model, nightly at 11:20 UTC. Read through ottoq_learned_estimate. An estimate, never a rule or a setting (CLAUDE.md rule 10). Append-only (override: ottoq.learned_estimates_unlock=on). No run column: it belongs to the depot and outlives every purge.';

CREATE INDEX ottoq_learned_estimates_latest_idx ON public.ottoq_learned_estimates (depot_id, model, estimate_id DESC);

CREATE FUNCTION public.ottoq_learned_estimates_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.learned_estimates_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_learned_estimates is append-only: % refused. A new fit is a new row. Set ottoq.learned_estimates_unlock=on in '
    'the session to override, and say why in a migration.', TG_OP
    USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_learned_estimates_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_learned_estimates
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_learned_estimates_append_only();

ALTER TABLE public.ottoq_learned_estimates ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_learned_estimates_read ON public.ottoq_learned_estimates FOR SELECT USING (true);
REVOKE ALL ON public.ottoq_learned_estimates FROM anon, authenticated;
GRANT SELECT ON public.ottoq_learned_estimates TO anon, authenticated;

-- ══ (b) the charge-time model ══════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_time_band(p_soc numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0619: the band of battery a charge starts from: a below 45%, b 45-70%, c 70-85%, d 85% and above.
  SELECT CASE WHEN p_soc IS NULL THEN NULL WHEN p_soc < 45 THEN 'a' WHEN p_soc < 70 THEN 'b'
              WHEN p_soc < 85 THEN 'c' ELSE 'd' END
$fn$;

CREATE FUNCTION public.ottoq_fit_charge_time_model(p_depot uuid, p_through timestamptz DEFAULT NULL,
                                                   p_window interval DEFAULT interval '21 days', p_note text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
/* 0619: fit charge_time_v1 for a depot from its completed charges in (through - window, through] (the ledger's
   recorded_at, a real clock). Per (kind, band) and per (kind, '*'): the median ratio of the charge's minutes to
   ottoq_charge_minutes_estimate's, its robust log spread and its p10/p90, on charges at ticks of a minute or less when
   the cell has 30 of them, else on every charge. Writes one row; returns its id. Deterministic for a given ledger. */
DECLARE
  c_min_n   constant int := 30;
  v_through timestamptz := COALESCE(p_through, now());
  v_from    timestamptz := COALESCE(p_through, now()) - COALESCE(p_window, interval '21 days');
  v_cells   jsonb;
  v_n       int;
  v_runs    int;
  v_usable  boolean;
  v_id      bigint;
BEGIN
  IF p_depot IS NULL THEN RAISE EXCEPTION 'ottoq_fit_charge_time_model: a depot is required'; END IF;

  WITH e AS MATERIALIZED (
    SELECT l.charger_type AS kind, public.ottoq_charge_time_band(l.soc_start) AS band,
           (l.tick_minutes IS NOT NULL AND l.tick_minutes <= 1) AS fine, ln((l.duration_min / est.m)::float8) AS lr,
           l.sim_run_id AS run
      FROM public.ottoq_charge_duration_ledger l
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end,
                                                                      l.charger_kw, l.vehicle_kw) AS m) est
     WHERE l.depot_id = p_depot AND l.recorded_at > v_from AND l.recorded_at <= v_through
       AND l.stopped_reason = 'completed' AND l.charger_type IN ('dcfc', 'l2')
       AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0
  ), src AS (
    SELECT kind, band, fine, lr, run FROM e
    UNION ALL
    SELECT kind, '*', fine, lr, run FROM e
  ), pop AS (
    SELECT kind, band, (count(*) FILTER (WHERE fine) >= c_min_n) AS use_fine FROM src GROUP BY kind, band
  ), used AS (
    SELECT s.kind, s.band, s.lr, s.run, p.use_fine FROM src s JOIN pop p USING (kind, band)
     WHERE s.fine OR NOT p.use_fine
  ), med AS (
    SELECT kind, band, percentile_cont(0.5) WITHIN GROUP (ORDER BY lr) AS m FROM used GROUP BY kind, band
  ), st AS (
    SELECT u.kind, u.band, bool_or(u.use_fine) AS use_fine, count(*) AS n, count(DISTINCT u.run) AS runs, md.m,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY abs(u.lr - md.m)) AS mad,
           percentile_cont(0.1) WITHIN GROUP (ORDER BY u.lr) AS p10,
           percentile_cont(0.9) WITHIN GROUP (ORDER BY u.lr) AS p90
      FROM used u JOIN med md USING (kind, band)
     GROUP BY u.kind, u.band, md.m
  )
  SELECT (SELECT jsonb_object_agg(st.kind || ':' || st.band, jsonb_build_object(
            'n', st.n, 'runs', st.runs, 'usable', st.n >= c_min_n,
            'population', CASE WHEN st.use_fine THEN 'fine_ticks' ELSE 'all_ticks' END,
            'factor', round(exp(st.m)::numeric, 4),
            'log_sd', round((1.4826 * st.mad)::numeric, 4),
            'p10', round(exp(st.p10)::numeric, 3), 'p90', round(exp(st.p90)::numeric, 3))) FROM st),
         (SELECT count(*) FROM e), (SELECT count(DISTINCT run) FROM e)
    INTO v_cells, v_n, v_runs;

  v_usable := COALESCE((SELECT bool_and(COALESCE((v_cells -> (k || ':*') ->> 'usable')::boolean, false))
                          FROM unnest(ARRAY['dcfc', 'l2']) k), false);

  INSERT INTO public.ottoq_learned_estimates
    (depot_id, model, evidence_from, evidence_through, n_evidence, n_runs, usable, params, code_md5, note)
  VALUES (p_depot, 'charge_time_v1', v_from, v_through, v_n, v_runs, v_usable,
          jsonb_build_object('cells', COALESCE(v_cells, '{}'::jsonb), 'bands', jsonb_build_array(45, 70, 85),
                             'base', 'ottoq_charge_minutes_estimate', 'min_cell_n', c_min_n,
                             'fine_tick_max_min', 1, 'stopped_reason', 'completed'),
          md5(pg_get_functiondef('public.ottoq_fit_charge_time_model(uuid,timestamptz,interval,text)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_minutes_estimate(numeric,numeric,numeric,numeric,numeric)'::regprocedure)),
          p_note)
  RETURNING estimate_id INTO v_id;
  RETURN v_id;
END $fn$;

-- ══ (c) the return model ═══════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_fit_return_model(p_depot uuid, p_through timestamptz DEFAULT NULL,
                                              p_window interval DEFAULT interval '21 days', p_note text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
/* 0619: fit return_v1 for a depot from the dispatches its runs made in (through - window, through] (created_at, a real
   clock) that came home. A car called home for its reserve (return_trigger low_soc_reserve) gives the threshold
   (soc_at_decision), the drain while working ((soc_at_dispatch - soc_at_decision) / minutes worked, over 5 minutes or
   more of work) and the drive home (returning_started_at to actual_return_at). Every other return, less the fixture's
   t=0 inbound cars and runs stopped mid-trip, is counted as one no forecast here can see. As the charge-time model, the
   fit reads runs at ticks of a minute or less (a run's sim minutes over its ticks) when they hold 30 reserve returns,
   else every run: at 5-minute ticks a 1-minute drive home reads as 5. Writes one row. */
DECLARE
  c_min_n   constant int := 30;
  v_through timestamptz := COALESCE(p_through, now());
  v_from    timestamptz := COALESCE(p_through, now()) - COALESCE(p_window, interval '21 days');
  v_p       jsonb;
  v_n       int;
  v_runs    int;
  v_low     int;
  v_id      bigint;
BEGIN
  IF p_depot IS NULL THEN RAISE EXCEPTION 'ottoq_fit_return_model: a depot is required'; END IF;

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
           -- the same share over every run, whichever population was fitted: how much the forecast cannot see
           'other_share_all_ticks', round((SELECT avg((return_trigger IS DISTINCT FROM 'low_soc_reserve')::int) FROM a)::numeric, 4),
           'n_returns_all_ticks', (SELECT count(*) FROM a)),
         (SELECT count(*) FROM d), (SELECT count(DISTINCT sim_run_id) FROM d), (SELECT count(*) FROM low)
    INTO v_p, v_n, v_runs, v_low;

  INSERT INTO public.ottoq_learned_estimates
    (depot_id, model, evidence_from, evidence_through, n_evidence, n_runs, usable, params, code_md5, note)
  VALUES (p_depot, 'return_v1', v_from, v_through, COALESCE(v_n, 0), COALESCE(v_runs, 0),
          COALESCE(v_low, 0) >= c_min_n AND (v_p ->> 'drain_pct_per_min') IS NOT NULL
            AND (v_p ->> 'threshold_soc') IS NOT NULL AND (v_p ->> 'trip_min') IS NOT NULL,
          v_p || jsonb_build_object('min_n', c_min_n),
          md5(pg_get_functiondef('public.ottoq_fit_return_model(uuid,timestamptz,interval,text)'::regprocedure)),
          p_note)
  RETURNING estimate_id INTO v_id;
  RETURN v_id;
END $fn$;

REVOKE ALL ON FUNCTION public.ottoq_fit_charge_time_model(uuid, timestamptz, interval, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_fit_return_model(uuid, timestamptz, interval, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_fit_charge_time_model(uuid, timestamptz, interval, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_fit_return_model(uuid, timestamptz, interval, text) TO service_role;

-- ══ (d) the latest fit ═════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_learned_estimate(p_depot uuid, p_model text)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0619: the latest fit of a learned estimate for a depot, or NULL when there is none.
  SELECT jsonb_build_object('estimate_id', e.estimate_id, 'model', e.model, 'fitted_at', e.fitted_at,
                            'usable', e.usable, 'n_evidence', e.n_evidence, 'n_runs', e.n_runs, 'params', e.params)
    FROM public.ottoq_learned_estimates e
   WHERE e.depot_id = p_depot AND e.model = p_model
   ORDER BY e.estimate_id DESC
   LIMIT 1
$fn$;

-- ══ (e) the learned minutes ════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_minutes_learned_with(p_model jsonb, p_kind text, p_batt_kwh numeric,
                                                         p_soc_from numeric, p_soc_to numeric, p_charger_kw numeric,
                                                         p_inlet_kw numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0619: minutes to charge from p_soc_from to p_soc_to (the car's full target: rule 9) on a charger of p_kind, as
  -- 0614's ottoq_charge_minutes_estimate times the learned factor of the band the charge starts from, else the kind's,
  -- else 1.0 (no model, or no usable cell). NULL when the battery size is unknown; 0 when nothing is owed.
  SELECT CASE WHEN x.base IS NULL THEN NULL
              WHEN x.base = 0 THEN 0
              ELSE round(x.base * COALESCE(
                     CASE WHEN (p_model #>> ARRAY['params', 'cells', p_kind || ':' || x.band, 'usable']) = 'true'
                          THEN (p_model #>> ARRAY['params', 'cells', p_kind || ':' || x.band, 'factor'])::numeric END,
                     CASE WHEN (p_model #>> ARRAY['params', 'cells', p_kind || ':*', 'usable']) = 'true'
                          THEN (p_model #>> ARRAY['params', 'cells', p_kind || ':*', 'factor'])::numeric END,
                     1.0), 1) END
    FROM (SELECT public.ottoq_charge_minutes_estimate(p_batt_kwh, p_soc_from, p_soc_to, p_charger_kw, p_inlet_kw) AS base,
                 public.ottoq_charge_time_band(p_soc_from) AS band) x
$fn$;

CREATE FUNCTION public.ottoq_charge_minutes_learned(p_depot uuid, p_kind text, p_batt_kwh numeric, p_soc_from numeric,
                                                    p_soc_to numeric, p_charger_kw numeric, p_inlet_kw numeric)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0619: ottoq_charge_minutes_learned_with on the depot's latest charge_time_v1 fit.
  SELECT public.ottoq_charge_minutes_learned_with(public.ottoq_learned_estimate(p_depot, 'charge_time_v1'), p_kind,
                                                  p_batt_kwh, p_soc_from, p_soc_to, p_charger_kw, p_inlet_kw)
$fn$;

GRANT EXECUTE ON FUNCTION public.ottoq_learned_estimate(uuid, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_minutes_learned_with(jsonb, text, numeric, numeric, numeric, numeric, numeric)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_minutes_learned(uuid, text, numeric, numeric, numeric, numeric, numeric)
  TO anon, authenticated, service_role;

-- ══ (f) the first fit, and the nightly one ═════════════════════════════════════════════════════════════════════════════
SELECT public.ottoq_fit_charge_time_model('11111111-1111-1111-1111-111111111111'::uuid, NULL, interval '21 days',
                                          '0619: the first fit, at apply');
SELECT public.ottoq_fit_return_model('11111111-1111-1111-1111-111111111111'::uuid, NULL, interval '21 days',
                                     '0619: the first fit, at apply');

SELECT cron.schedule('ottoq-learn-estimates-nightly', '20 11 * * *',
  $cron$SELECT public.ottoq_fit_charge_time_model('11111111-1111-1111-1111-111111111111'::uuid, NULL, interval '21 days', 'nightly'), public.ottoq_fit_return_model('11111111-1111-1111-1111-111111111111'::uuid, NULL, interval '21 days', 'nightly');$cron$);

-- ══ V ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
DO $v1$
DECLARE
  m jsonb := '{"params": {"cells": {"l2:d": {"usable": true, "factor": 1.85}, "l2:*": {"usable": true, "factor": 1.4},
                                    "dcfc:a": {"usable": false, "factor": 9}, "dcfc:*": {"usable": true, "factor": 1.5}}}}';
  base_l2_d numeric := public.ottoq_charge_minutes_estimate(75, 90, 100, 19.2, 250);
  base_l2_a numeric := public.ottoq_charge_minutes_estimate(75, 30, 100, 19.2, 250);
  base_dc_a numeric := public.ottoq_charge_minutes_estimate(75, 30, 100, 150, 250);
BEGIN
  IF public.ottoq_charge_minutes_learned_with(m, 'l2', 75, 90, 100, 19.2, 250) IS DISTINCT FROM round(base_l2_d * 1.85, 1)
     OR public.ottoq_charge_minutes_learned_with(m, 'l2', 75, 30, 100, 19.2, 250) IS DISTINCT FROM round(base_l2_a * 1.4, 1)
     OR public.ottoq_charge_minutes_learned_with(m, 'dcfc', 75, 30, 100, 150, 250) IS DISTINCT FROM round(base_dc_a * 1.5, 1)
     OR public.ottoq_charge_minutes_learned_with(NULL, 'dcfc', 75, 30, 100, 150, 250) IS DISTINCT FROM round(base_dc_a, 1)
     OR public.ottoq_charge_minutes_learned_with(m, 'l2', NULL, 30, 100, 19.2, 250) IS NOT NULL
     OR public.ottoq_charge_minutes_learned_with(m, 'l2', 75, 100, 100, 19.2, 250) IS DISTINCT FROM 0
     OR public.ottoq_charge_time_band(44.9) <> 'a' OR public.ottoq_charge_time_band(45) <> 'b'
     OR public.ottoq_charge_time_band(85) <> 'd' OR public.ottoq_charge_time_band(NULL) IS NOT NULL THEN
    RAISE EXCEPTION '0619 V1: the learned minutes do not apply the cell, the kind and the fallback as written';
  END IF;
END $v1$;

DO $v2$
DECLARE c jsonb; r jsonb; k text; bad text;
BEGIN
  c := public.ottoq_learned_estimate('11111111-1111-1111-1111-111111111111', 'charge_time_v1');
  r := public.ottoq_learned_estimate('11111111-1111-1111-1111-111111111111', 'return_v1');
  IF c IS NULL OR r IS NULL THEN RAISE EXCEPTION '0619 V2: the first fits were not written'; END IF;
  SELECT string_agg(key, ', ') INTO bad
    FROM jsonb_each(c #> '{params,cells}')
   WHERE (value ->> 'usable')::boolean
     AND NOT ((value ->> 'factor')::numeric > 0.2 AND (value ->> 'factor')::numeric < 5 AND (value ->> 'log_sd')::numeric >= 0);
  IF bad IS NOT NULL THEN RAISE EXCEPTION '0619 V2: charge-time cells out of range: %', bad; END IF;
  IF (r ->> 'usable')::boolean AND NOT ((r #>> '{params,threshold_soc}')::numeric > 5 AND (r #>> '{params,threshold_soc}')::numeric < 95
                                       AND (r #>> '{params,drain_pct_per_min}')::numeric > 0 AND (r #>> '{params,trip_min}')::numeric >= 0) THEN
    RAISE EXCEPTION '0619 V2: the return model is out of range: %', r -> 'params';
  END IF;
  FOR k IN SELECT key FROM jsonb_each(c #> '{params,cells}') ORDER BY key LOOP
    RAISE NOTICE '0619 V2 charge_time %: %', k, c #> ARRAY['params', 'cells', k];
  END LOOP;
  RAISE NOTICE '0619 V2 charge_time usable=% from % charges over % runs', c ->> 'usable', c ->> 'n_evidence', c ->> 'n_runs';
  RAISE NOTICE '0619 V2 return usable=% from % returns over % runs: %', r ->> 'usable', r ->> 'n_evidence', r ->> 'n_runs', r -> 'params';
END $v2$;

DO $v3$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ottoq-learn-estimates-nightly' AND schedule = '20 11 * * *') THEN
    RAISE EXCEPTION '0619 V3: the nightly fit is not scheduled';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0619_the_kernel_learns_how_long_a_charge_takes_and_when_a_car_comes_back', false, false,
  'Learned estimates for a depot, fitted from its own ledgers and refitted nightly at 11:20 UTC: how much longer a '
  'charge runs than ottoq_charge_minutes_estimate per kind and band of battery, and when a working car comes home. '
  'FALSE/FALSE: nothing on the tick path or in a certification arm reads them; the job writes only its own table.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
