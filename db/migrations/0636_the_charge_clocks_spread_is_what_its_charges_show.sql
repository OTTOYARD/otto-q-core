-- migration-version: 20261009103417
-- migration-name:    the_charge_clocks_spread_is_what_its_charges_show
--
-- 0636  **The charge clock's spread is what its own charges show, by kind and length of charge.**
--       The clock gives every charge a spread (the log spread of a charge like it) and the check's futures draw each
--       charge's minutes from it. On fast chargers the spread is far too sure: a charge lands inside the clock's 80% band
--       about two times in three once the clock knows the run, at every length. The self-review ranks it third ("The
--       charge clock is surer than the charges on fast chargers", 15.1% of what made the check's verdicts wrong, G362),
--       the first open area 0627-0635 did not build. 0636 has each nightly fit measure, on the charges it learned from,
--       how wide a charge of each kind and length really runs against the spread the clock gives it, and the clock
--       widens (or narrows) its spread by that much.
--
-- ══ §1 WHY (measured 2026-10-09 07:55-08:12 UTC, 2:55-3:12 AM CT, on live, read-only) ═══════════════════════════════════════
--
--   (a) The yardstick is the self-review's own (ottoq_charge_clock_audit_v2): a charge is inside the 80% band when what
--       the clock leaves once it knows the run (its log residual less its run's mean) is within 1.2816 of the clock's
--       spread. On the twin depot's fine-tick charges since the fast-charge regime cut (2026-09-30 11:53 UTC), by the
--       length the clock forecast, on its fit 3 (spread 0.063-0.068 on fast chargers):
--         fast  under 15 min   117 charges  65.8% inside   the residuals' own 80% band 1.65 times the clock's
--               15-30          131          66.4%          1.72
--               30-45           67          56.7%          2.06
--               45 and over    362          65.2%          1.54     (6-13% beyond 3 spreads at every length)
--         L2    under 60 min   864          76.5%          1.05
--               60-120         337          73.6%          1.08
--               120-240        527          82.4%          0.94
--               240 and over   239          84.5%          0.87
--       So on fast chargers it is the spread itself, at every length, not only the long charges G362 first named; on L2
--       the short charges run a little wide and the long ones a little narrow.
--   (b) The cause is the narrowing. The clock gives a fast charge its class's spread (0.099-0.118) narrowed by the share
--       of it the car's level explains across runs (icc 0.698): about 0.065. Within a run the car's level does not take
--       that much: the residuals left once the run is known run about 0.107. The narrowing is right across runs and too
--       generous within one, and the futures sample within one.
--   (c) A calibration, not a new level: the fit's own residuals say how wide each kind and length runs against the spread
--       the clock gives, so the spread is scaled by that, and every reader of the clock (the check's futures, the agent's
--       board, the grader, the audit) reads the scaled spread. The minutes the clock forecasts do not move.
--   (d) Out of sample on live (08:05-08:12 UTC, read-only, on a temporary copy of the spread's fit): fitted through the
--       start of each of the twin depot's two latest runs with 30 or more fast charges, that run's charges inside the
--       band once the clock knows the run:
--         b2efcc07   fast 30 charges  43.3% -> 70.0%   (factors 1.61, 1.71, 1.97, 1.52)   L2 50  72.0% -> 72.0%
--         baf29c05   fast 57          61.4% -> 80.7%   (1.39, 1.39, 1.86, 1.37)           L2 77  92.2% -> 89.6%
--       Together, fast 55.2% -> 77.0% and L2 84.3% -> 82.7%. Two runs: a reading, not a range. Live's clock has no level
--       for the air yet (0632 applies first); the factors are measured on whatever the clock leaves, so they follow it.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_charge_clock_spread_fit(depot, params, through, window): on the fit's own charges (fine ticks,
--       completed, in the window, after the kind's regime cut where the fit applied one), each charge's residual on the
--       clock with the new levels, less its run's mean (runs of 5 or more charges of the kind; scaled by sqrt(n/(n-1)),
--       what subtracting a mean takes), over the spread the clock gives it: z. Per kind, z's 80% band in spreads ((the
--       90th percentile less the 10th) / 2.5631) for the kind and for each length of charge the clock forecasts (fast:
--       under 15, 15-30, 30-45, 45 minutes and over; L2: under 60, 60-120, 120-240, 240 and over), each length's shrunk
--       toward the kind's by n / (n + 30) and held within 0.5-4; a length with fewer than 10 charges takes the kind's. A kind
--       with fewer than 60 charges in 3 runs gets nothing. It says what share of those charges fell inside the band
--       before and after.
--   (b) ottoq_charge_time_v2_params adds it to every fit as `spread`, unless a person has turned it off at the depot (the
--       new dial charge_clock_spread_by_length, 1 by default, depot scope; at 0, 0632's params key for key).
--   (c) ottoq_charge_clock: with a fit carrying `spread` for the kind, the spread it gives a charge is scaled by its
--       length's factor (the minutes it forecasts, as it returns them, against the edges), and it says so (`sf`). Without
--       it, 0632's clock key for key. The minutes never move.
--   (d) ottoq_fit_charge_time_v2: its code md5 covers the spread's fit.
--   (e) The self-review: when the clock's latest fit carries the spread for a kind and the audit can read that kind only
--       in the fit's own charges, the band is history, built, with what the fit measured; once 30 charges come after the
--       fit, the audit grades it as before.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, no run running, no fit running. P1 the four bodies are the ones 0632-0635 left, the objects are
--   new. V1 the clock with a planted spread, by arithmetic, and each patch by meaning. V2 on the clock as it stood (no
--   spread), the clock reads exactly as before on the twin depot's latest runs. V3 the twin depot's clock refitted with
--   the spread. V4 out of sample: fitted through the start of the latest run with 30 or more charges of a kind, that run's
--   charges inside the band with and without the spread. V5 the self-review. Executed by
--   tests/test_agent_clock_spread_sql.py on the miniature depot.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE, as 0622, 0625 and 0632: the charge clock is read by the check on an
--   agent's charge order, its futures, the agent's board, the grader and the self-review; no kernel decision, dial or
--   seat reads it, and no certification arm runs the agent or the charge order. The dial is new and a person's.
--
-- ROLLBACK: set charge_clock_spread_by_length to 0 at the depot and refit (0632's clock, exactly), or EXECUTE each
--   `definition` in ottoq_schema_snapshots WHERE label = '0636_pre' AND object_kind = 'function'; then DROP FUNCTION
--   public.ottoq_charge_clock_spread_fit(uuid, jsonb, timestamptz, interval); DELETE FROM ottoq_policy_param_catalog WHERE
--   param_key = 'charge_clock_spread_by_length'; DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0636_the_charge_clocks_spread_is_what_its_charges_show'. The fits appended here stay (evidence); a person refits.

BEGIN;

-- ── P0: nothing in flight, no run running, no fit running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0636 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0636 P0: a run is running; its check reads the clock this changes. Apply between runs';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE pid <> pg_backend_pid() AND state = 'active' AND query ~ 'ottoq_fit_charge_time_v2\(') THEN
    RAISE EXCEPTION '0636 P0: a charge clock fit is running (the nightly refit); apply after it';
  END IF;
END $inflight$;

-- ── P1: the bodies are the ones 0632-0635 left; the objects are new ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)',  'dada1102af122305eae1ca4d6e1f62ae'),
    ('public.ottoq_charge_time_v2_params(uuid,timestamp with time zone,interval,numeric)',          'cf47e810b040d5f83736b3ffdb140c06'),
    ('public.ottoq_fit_charge_time_v2(uuid,timestamp with time zone,interval,numeric,text)',        'ed5c67a8bd5477abb9e2af46501cf389'),
    ('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)',              'ec698835f41677377d737f6dd76b3f7f'))
    AS t(sig, src_md5)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)) IS DISTINCT FROM r.src_md5 THEN
      RAISE EXCEPTION '0636 P1: % is not the body measured (md5 %); read it again', r.sig, left(r.src_md5, 8);
    END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_charge_clock_spread_fit(uuid,jsonb,timestamp with time zone,interval)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'charge_clock_spread_by_length')
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0636_the_charge_clocks_spread_is_what_its_charges_show') THEN
    RAISE EXCEPTION '0636 P1: already applied';
  END IF;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0636_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)'::regprocedure,
                 'public.ottoq_charge_time_v2_params(uuid,timestamp with time zone,interval,numeric)'::regprocedure,
                 'public.ottoq_fit_charge_time_v2(uuid,timestamp with time zone,interval,numeric,text)'::regprocedure,
                 'public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)'::regprocedure);

-- what V2 compares against: the clock as it stood (the depot's latest usable fit, no spread), on the twin depot's latest
-- three runs' completed charges, with no run evidence and with the run's evidence at its end
CREATE TEMP TABLE _0636_model ON COMMIT DROP AS
SELECT public.ottoq_charge_clock_model('11111111-1111-1111-1111-111111111111') AS m;

CREATE TEMP TABLE _0636_pre ON COMMIT DROP AS
SELECT l.session_id, l.charger_type AS kind, w.j AS who, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw,
       ev.ev -> l.charger_type AS run_block,
       public.ottoq_charge_clock(m.m, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw,
                                 NULL) AS c_none,
       public.ottoq_charge_clock(m.m, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw,
                                 ev.ev -> l.charger_type) AS c_run
  FROM (SELECT r.sim_run_id, r.sim_clock_current
          FROM public.ottoq_sim_runs r
         WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.purged_at IS NULL AND r.sim_clock_current IS NOT NULL
           AND EXISTS (SELECT 1 FROM public.ottoq_charge_duration_ledger l WHERE l.sim_run_id = r.sim_run_id
                        AND l.stopped_reason = 'completed' AND l.tick_minutes <= 1)
         ORDER BY r.started_at DESC LIMIT 3) r
  CROSS JOIN _0636_model m
  CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_run_evidence(m.m, r.sim_run_id, r.sim_clock_current) AS ev) ev
  JOIN public.ottoq_charge_duration_ledger l ON l.sim_run_id = r.sim_run_id AND l.stopped_reason = 'completed'
   AND l.charger_type IN ('dcfc', 'l2')
  JOIN public.vehicles v ON v.id = l.vehicle_id
 CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w;

-- ══ (b) the dial ══════════════════════════════════════════════════════════════════════════════════════════════════════════
INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, agent_writable, affects, description)
VALUES ('charge_clock_spread_by_length', 0, 1, 1, false,
  'ottoq_charge_time_v2_params, ottoq_charge_clock (0636 the spread by kind and length)',
  '0636: whether each charge clock fit at a depot measures how wide each kind and length of charge runs against the '
  'spread the clock gives it (ottoq_charge_clock_spread_fit) and the clock scales its spread by that. Read at fit time at '
  'depot scope. 1 measures it; 0 is 0632''s fit, key for key. A person''s dial, never the agent''s (rule 10).');

-- ══ (a) the spread's fit ══════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_charge_clock_spread_fit(p_depot uuid, p_params jsonb,
                                                     p_through timestamptz DEFAULT NULL,
                                                     p_window interval DEFAULT '21 days')
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions'
SET "TimeZone" TO 'UTC'
AS $fn$
  /* 0636: how wide each kind and length of charge runs against the spread the clock gives it, on a fit's own charges:
     the depot's completed fine-tick charges recorded in (through - window, through], after the kind's regime cut where
     the fit applied one (p_params' `regimes`). Each charge's residual on the clock with p_params (less any `spread`),
     less its run's mean (outside a run, its day's; units of 5 or more charges of the kind; times sqrt(n / (n - 1)), what
     subtracting a mean takes), over the spread the clock gives it: z. The kind's factor is z's 80% band in spreads ((the
     90th percentile less the 10th) / 2.5631); each length's (by the minutes the clock forecasts; fast: under 15, 15-30,
     30-45, 45 and over; L2: under 60, 60-120, 120-240, 240 and over) is its own band shrunk toward the kind's by
     n / (n + 30) and held within 0.5-4, the kind's where it has fewer than 10 charges. A kind with fewer than 60 charges
     in 3 units gets none, and with neither kind it is NULL. Read-only. */
  WITH k AS (
    SELECT * FROM (VALUES ('dcfc', ARRAY[15, 30, 45]::numeric[]), ('l2', ARRAY[60, 120, 240]::numeric[])) k(kind, edges)
  ), m AS (
    SELECT jsonb_build_object('params', COALESCE(p_params, '{}'::jsonb) - 'spread') AS j
  ), e AS (
    SELECT l.charger_type AS kind, COALESCE(l.sim_run_id::text, 'day ' || to_char(l.recorded_at, 'YYYY-MM-DD')) AS unit,
           ln((l.duration_min / est.m)::numeric) AS lr,
           public.ottoq_charge_clock(m.j, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                     l.vehicle_kw, jsonb_build_object('air_c', l.depot_air_c)) AS c
      FROM m, public.ottoq_charge_duration_ledger l
      JOIN public.vehicles v ON v.id = l.vehicle_id
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                      l.vehicle_kw) AS m) est
     WHERE l.depot_id = p_depot
       AND l.recorded_at > COALESCE(p_through, now()) - COALESCE(p_window, interval '21 days')
       AND l.recorded_at <= COALESCE(p_through, now())
       AND l.recorded_at > COALESCE(CASE WHEN COALESCE((p_params #>> ARRAY['regimes', l.charger_type, 'applied'])::boolean, false)
                                         THEN (p_params #>> ARRAY['regimes', l.charger_type, 'starts_at'])::timestamptz END,
                                    '-infinity'::timestamptz)
       AND l.stopped_reason = 'completed' AND l.charger_type IN ('dcfc', 'l2') AND l.duration_min > 0
       AND l.soc_end > l.soc_start AND est.m > 0 AND l.tick_minutes IS NOT NULL AND l.tick_minutes <= 1
  ), r AS (
    SELECT e.kind, e.unit, e.lr - (e.c ->> 'f')::numeric AS res, (e.c ->> 'sd')::numeric AS sd, (e.c ->> 'm')::numeric AS pm,
           count(*) OVER (PARTITION BY e.kind, e.unit) AS nu
      FROM e WHERE (e.c ->> 'sd')::numeric > 0 AND (e.c ->> 'm')::numeric > 0
  ), z AS (
    SELECT r.kind, r.unit, 1 + (SELECT count(*) FROM unnest(k.edges) x WHERE x <= r.pm)::int AS bin,
           ((r.res - avg(r.res) OVER (PARTITION BY r.kind, r.unit)) * sqrt(r.nu / (r.nu - 1.0)) / r.sd)::float8 AS z
      FROM r JOIN k ON k.kind = r.kind
     WHERE r.nu >= 5
  ), kk AS (
    SELECT z.kind, count(*) AS n, count(DISTINCT z.unit) AS units,
           (percentile_cont(0.9) WITHIN GROUP (ORDER BY z.z) - percentile_cont(0.1) WITHIN GROUP (ORDER BY z.z)) / 2.5631 AS s
      FROM z GROUP BY z.kind
  ), bb AS (
    SELECT z.kind, z.bin, count(*) AS n,
           (percentile_cont(0.9) WITHIN GROUP (ORDER BY z.z) - percentile_cont(0.1) WITHIN GROUP (ORDER BY z.z)) / 2.5631 AS s_raw
      FROM z GROUP BY z.kind, z.bin
  ), sb AS (
    SELECT k.kind, k.edges, g.bin, COALESCE(bb.n, 0) AS n, bb.s_raw, kk.n AS n_kind, kk.units, kk.s AS s_kind,
           LEAST(GREATEST(CASE WHEN COALESCE(bb.n, 0) >= 10 THEN (bb.n * bb.s_raw + 30 * kk.s) / (bb.n + 30) ELSE kk.s END,
                          0.5), 4) AS s
      FROM k JOIN kk ON kk.kind = k.kind
      CROSS JOIN LATERAL generate_series(1, cardinality(k.edges) + 1) g(bin)
      LEFT JOIN bb ON bb.kind = k.kind AND bb.bin = g.bin
     WHERE kk.n >= 60 AND kk.units >= 3
  ), cov AS (
    SELECT z.kind, avg((abs(z.z) <= 1.2816)::int) AS before, avg((abs(z.z) <= 1.2816 * sb.s)::int) AS after
      FROM z JOIN sb ON sb.kind = z.kind AND sb.bin = z.bin GROUP BY z.kind
  ), kj AS (
    SELECT sb.kind, jsonb_build_object(
             'edges', to_jsonb(max(sb.edges)),
             's', jsonb_agg(round(sb.s::numeric, 4) ORDER BY sb.bin),
             'n_by_length', jsonb_agg(sb.n ORDER BY sb.bin),
             's_raw', jsonb_agg(round(sb.s_raw::numeric, 4) ORDER BY sb.bin),
             's_kind', round(max(sb.s_kind)::numeric, 4), 'n', max(sb.n_kind), 'units', max(sb.units),
             'in_band_before', round(max(cov.before)::numeric, 3), 'in_band_after', round(max(cov.after)::numeric, 3)) AS j
      FROM sb JOIN cov ON cov.kind = sb.kind GROUP BY sb.kind
  )
  SELECT CASE WHEN count(*) = 0 THEN NULL
              ELSE jsonb_object_agg(kj.kind, kj.j) || jsonb_build_object('v', 1,
                     'rule', 'z: a charge''s log residual on the clock, less its run''s mean, over the spread the clock gives '
                             'it; the factor is z''s 80% band in spreads, per kind and per length shrunk toward the kind''s') END
    FROM kj
$fn$;

COMMENT ON FUNCTION public.ottoq_charge_clock_spread_fit(uuid, jsonb, timestamptz, interval) IS
'0636. How wide each kind and length of charge runs against the spread the charge clock gives it, on a fit''s own charges once the clock knows the run: the factor ottoq_charge_clock scales its spread by. Read-only; written into every charge_time_v2 fit as `spread` by ottoq_charge_time_v2_params unless charge_clock_spread_by_length is 0 at the depot.';

-- ══ (b) (c) (d) (e) the anchored patches: each anchor once, the stored definition after ═══════════════════════════════════
CREATE TEMP TABLE _0636_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;

INSERT INTO _0636_patch VALUES
-- (c) the clock
('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)', 1,
$old$   widened by the level's steepest slope for every degree beyond. */$old$,
$new$   widened by the level's steepest slope for every degree beyond.
   0636: with p_model's `spread` for the kind (ottoq_charge_clock_spread_fit, written by the fit), the spread is scaled by
   the factor for the charge's length (the minutes returned, against the kind's edges), and `sf` says by how much. The
   minutes never move. Without it, 0632's clock, key for key. */$new$),
('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)', 2,
$old$  v_out    numeric := 0;$old$,
$new$  v_out    numeric := 0;
  v_sp     jsonb;           -- 0636: the fit's spread for this kind
  v_sf     numeric;$new$),
('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)', 3,
$old$  IF v_out > 0 THEN   -- 0632: an air the fit never saw
    v_sd := sqrt(v_sd * v_sd + power(COALESCE((v_al ->> 'g')::numeric, 0) * v_out, 2));
  END IF;$old$,
$new$  IF v_out > 0 THEN   -- 0632: an air the fit never saw
    v_sd := sqrt(v_sd * v_sd + power(COALESCE((v_al ->> 'g')::numeric, 0) * v_out, 2));
  END IF;
  -- 0636: as wide as a charge of this kind and length runs against the spread the clock gives it
  v_sp := v_p #> ARRAY['spread', p_kind];
  IF jsonb_typeof(v_sp) = 'object' AND jsonb_typeof(v_sp -> 's') = 'array' AND v_base IS NOT NULL AND v_base > 0 THEN
    v_sf := (v_sp -> 's' ->> (SELECT count(*)::int FROM jsonb_array_elements_text(COALESCE(v_sp -> 'edges', '[]'::jsonb)) x
                               WHERE x::numeric <= round(v_base * exp(v_f), 1)))::numeric;
    IF v_sf IS NOT NULL AND v_sf > 0 THEN
      v_sd := v_sd * v_sf;
    ELSE
      v_sf := NULL;
    END IF;
  END IF;$new$),
('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)', 4,
$old$    || CASE WHEN v_air IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('air', round(v_air, 4)) END;   -- 0632$old$,
$new$    || CASE WHEN v_air IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('air', round(v_air, 4)) END    -- 0632
    || CASE WHEN v_sf IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('sf', round(v_sf, 4)) END;     -- 0636$new$),
-- (b) the fit's params
('public.ottoq_charge_time_v2_params(uuid,timestamp with time zone,interval,numeric)', 1,
$old$  -- key for key. Read-only; deterministic for a given ledger, record and through.
  SELECT public.ottoq_charge_time_v2_params_cut($old$,
$new$  -- key for key. Read-only; deterministic for a given ledger, record and through.
  -- 0636: and the spread each kind and length of charge shows against the clock's (ottoq_charge_clock_spread_fit), as
  -- `spread`, unless a person has set charge_clock_spread_by_length to 0 at the depot: then 0632's params, key for key.
  SELECT x.p || CASE WHEN s.s IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('spread', s.s) END
    FROM (SELECT public.ottoq_charge_time_v2_params_cut($new$),
('public.ottoq_charge_time_v2_params(uuid,timestamp with time zone,interval,numeric)', 2,
$old$                                             COALESCE(p_through, now())))$old$,
$new$                                             COALESCE(p_through, now()))) AS p) x
    CROSS JOIN LATERAL (
      SELECT CASE WHEN COALESCE((SELECT pp.param_value FROM public.ottoq_policy_params pp
                                  WHERE pp.scope_type = 'depot' AND pp.scope_id = p_depot
                                    AND pp.param_key = 'charge_clock_spread_by_length'), 1) >= 1
                  THEN public.ottoq_charge_clock_spread_fit(p_depot, x.p, p_through, p_window) END AS s) s$new$),
-- (d) the fit's code md5
('public.ottoq_fit_charge_time_v2(uuid,timestamp with time zone,interval,numeric,text)', 1,
$old$   the function that applies them. 0632: and the level for the air and the solve that fits it. */$old$,
$new$   the function that applies them. 0632: and the level for the air and the solve that fits it. 0636: and the spread's
   fit. */$new$),
('public.ottoq_fit_charge_time_v2(uuid,timestamp with time zone,interval,numeric,text)', 2,
$old$double precision,double precision,double precision)'::regprocedure)),$old$,
$new$double precision,double precision,double precision)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_clock_spread_fit(uuid,jsonb,timestamp with time zone,interval)'::regprocedure)),$new$),
-- (e) the self-review
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 1,
$old$  v_flt_built boolean := false; v_flt_carried boolean := false;                                     -- 0635$old$,
$new$  v_flt_built boolean := false; v_flt_carried boolean := false;                                     -- 0635
  v_sp jsonb;                                                                                       -- 0636$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 2,
$old$        'action', 'Widen the clock''s spread on ' || public.ottoq_review_words('kind', x.k) || ' to what its own residuals show.',
        'evidence', x.j - 'covariates' - 'air_temperature');
    END IF;$old$,
$new$        'action', 'Widen the clock''s spread on ' || public.ottoq_review_words('kind', x.k) || ' to what its own residuals show.',
        'evidence', x.j - 'covariates' - 'air_temperature');
    -- 0636: a fit that measured the spread, read only in its own charges so far: the band is history until 30 charges
    -- come after the fit
    ELSIF NOT COALESCE((x.j ->> 'out_of_sample')::boolean, false)
          AND jsonb_typeof(public.ottoq_charge_clock_model(p_depot_id) #> ARRAY['params', 'spread', x.k]) = 'object' THEN
      v_sp := public.ottoq_charge_clock_model(p_depot_id) #> ARRAY['params', 'spread', x.k];
      v_areas := v_areas || jsonb_build_object(
        'area', 'charge_clock_band_' || x.k, 'kind', 'calibration', 'part', 'charge_times',
        'status', 'built', 'thin', false, 'tier', 2, 'weight', (x.j ->> 'charges')::int,
        'title', 'The charge clock''s spread on ' || public.ottoq_review_words('kind', x.k) || ' is what its charges show',
        'finding', round(100 * (v_sp ->> 'in_band_before')::numeric) || '% of the ' || (v_sp ->> 'n') || ' charges on '
                   || public.ottoq_review_words('kind', x.k) || ' it was fitted on fell inside its 80% band once it knows '
                   || 'the run, and ' || round(100 * (v_sp ->> 'in_band_after')::numeric) || '% with the spread each length '
                   || 'of charge shows. These are the charges it learned from, so this is history until 30 charges come '
                   || 'after the fit.',
        'action', 'Grade the band on the charges that come after the fit: the audit reads them once there are 30.',
        'evidence', v_sp);
    END IF;$new$);

DO $patch$
DECLARE f record; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0636_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0636_patch WHERE fn = f.fn ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0636 %: anchor % matches % times, not 1', f.fn, p.seq, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    -- V1: the stored definition is the pre-image with exactly these replacements
    IF pg_get_functiondef(to_regprocedure(f.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0636 V1: % is not stored as patched', f.fn;
    END IF;
  END LOOP;
END $patch$;

-- ══ V1: the clock with a planted spread, by arithmetic; each patch by meaning ══════════════════════════════════════════════
DO $v1$
DECLARE
  c_model constant jsonb := '{"params": {"cells": {"dcfc:*": {"usable": true, "factor": 1, "log_sd": 0.05},
                                                   "l2:*": {"usable": true, "factor": 1, "log_sd": 0.1}},
                                         "class_cells": {}}}';
  v_sp constant jsonb := '{"dcfc": {"edges": [15, 30, 45], "s": [1.1, 1.2, 1.3, 1.4]}}';
  a jsonb; b jsonb; c jsonb; d jsonb;
BEGIN
  -- a fast charge from 70% (28 minutes on 0614's estimate) takes the 15-30 factor; from 20% (48) the 45-and-over; the
  -- minutes do not move; an L2 charge, which the planted block does not name, keeps its spread and says nothing
  a := public.ottoq_charge_clock(c_model, 'dcfc', '{}'::jsonb, 75, 70, 100, 150, 250, NULL);
  b := public.ottoq_charge_clock(jsonb_set(c_model, '{params,spread}', v_sp), 'dcfc', '{}'::jsonb, 75, 70, 100, 150, 250, NULL);
  c := public.ottoq_charge_clock(jsonb_set(c_model, '{params,spread}', v_sp), 'dcfc', '{}'::jsonb, 75, 20, 100, 150, 250, NULL);
  d := public.ottoq_charge_clock(jsonb_set(c_model, '{params,spread}', v_sp), 'l2', '{}'::jsonb, 75, 70, 100, 19.2, 250, NULL);
  IF (b ->> 'm') IS DISTINCT FROM (a ->> 'm') OR (a ->> 'm')::numeric <> 28
     OR abs((b ->> 'sd')::numeric - 0.05 * 1.2) > 1e-9 OR (b ->> 'sf')::numeric <> 1.2
     OR abs((c ->> 'sd')::numeric - 0.05 * 1.4) > 1e-9 OR (c ->> 'sf')::numeric <> 1.4
     OR (d ->> 'sd')::numeric <> 0.1 OR d ? 'sf' OR a ? 'sf' THEN
    RAISE EXCEPTION '0636 V1: the clock with a planted spread reads % / % / % / %', a, b, c, d;
  END IF;
  IF strpos(pg_get_functiondef('public.ottoq_charge_time_v2_params(uuid,timestamp with time zone,interval,numeric)'::regprocedure),
            'public.ottoq_charge_clock_spread_fit(p_depot, x.p, p_through, p_window)') = 0
     OR strpos(pg_get_functiondef('public.ottoq_fit_charge_time_v2(uuid,timestamp with time zone,interval,numeric,text)'::regprocedure),
               'ottoq_charge_clock_spread_fit(uuid,jsonb,timestamp with time zone,interval)') = 0
     OR strpos(pg_get_functiondef('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)'::regprocedure),
               '''params'', ''spread'', x.k') = 0 THEN
    RAISE EXCEPTION '0636 V1: the fit, its md5 or the self-review is not as meant';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'charge_clock_spread_by_length'
                    AND default_value = 1 AND NOT agent_writable) THEN
    RAISE EXCEPTION '0636 V1: the dial is not catalogued as a person''s, default 1';
  END IF;
  RAISE NOTICE '0636 V1: a fast charge of % minutes takes the 15-30 factor (spread % -> %), one of % the 45-and-over (%); an L2 charge the block does not name keeps %; the fit, its md5, the self-review and the dial as meant',
    a ->> 'm', a ->> 'sd', b ->> 'sd', c ->> 'm', c ->> 'sd', d ->> 'sd';
END $v1$;

-- ══ V2: on the clock as it stood (no spread), the clock reads exactly as before ════════════════════════════════════════════
DO $v2$
DECLARE v_n int; v_diff int;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE public.ottoq_charge_clock(m.m, p.kind, p.who, p.battery_kwh, p.soc_start, p.soc_end, p.charger_kw,
                                                          p.vehicle_kw, NULL) IS DISTINCT FROM p.c_none
                             OR public.ottoq_charge_clock(m.m, p.kind, p.who, p.battery_kwh, p.soc_start, p.soc_end, p.charger_kw,
                                                          p.vehicle_kw, p.run_block) IS DISTINCT FROM p.c_run)
    INTO v_n, v_diff
    FROM _0636_pre p CROSS JOIN _0636_model m;
  IF v_diff > 0 THEN
    RAISE EXCEPTION '0636 V2: % of % charges read differently on the clock as it stood', v_diff, v_n;
  END IF;
  RAISE NOTICE '0636 V2: on the clock as it stood (fit %, no spread), % charges read exactly as before, with and without the run''s evidence',
    (SELECT m.m ->> 'estimate_id' FROM _0636_model m), v_n;
END $v2$;

-- ══ V3: the twin depot's clock refitted with the spread ═══════════════════════════════════════════════════════════════════
DO $v3$
DECLARE c_twin constant uuid := '11111111-1111-1111-1111-111111111111'; v_id bigint; v_m jsonb; v_t timestamptz := clock_timestamp();
BEGIN
  v_id := public.ottoq_fit_charge_time_v2(c_twin, now(), interval '21 days', 3,
                                          '0636: the first fit to measure the spread each kind and length of charge shows');
  SELECT jsonb_build_object('usable', f.usable, 'spread', f.params -> 'spread') INTO v_m
    FROM public.ottoq_charge_clock_fits f WHERE f.fit_id = v_id;
  RAISE NOTICE '0636 V3: fit % in % s, usable %. The spread: %', v_id, round(extract(epoch FROM clock_timestamp() - v_t)::numeric, 1),
    v_m ->> 'usable',
    COALESCE((SELECT string_agg(k.key || ' x' || (k.value ->> 's_kind') || ' by length ' || (k.value ->> 's')
                                || ' (n ' || (k.value ->> 'n_by_length') || '); inside the band '
                                || round(100 * (k.value ->> 'in_band_before')::numeric, 1) || '% -> '
                                || round(100 * (k.value ->> 'in_band_after')::numeric, 1) || '% on '
                                || (k.value ->> 'n') || ' charges in ' || (k.value ->> 'units') || ' runs', '; ' ORDER BY k.key)
                FROM jsonb_each(v_m -> 'spread') k WHERE jsonb_typeof(k.value) = 'object'), 'none');
END $v3$;

-- ══ V4: out of sample, on the latest run with 30 or more charges of a kind ══════════════════════════════════════════════
DO $v4$
DECLARE
  c_twin constant uuid := '11111111-1111-1111-1111-111111111111';
  g record; v_p jsonb; v_out text := '';
BEGIN
  FOR g IN
    SELECT x.kind, x.run, x.t0 FROM (
      SELECT l.charger_type AS kind, l.sim_run_id AS run, min(l.recorded_at) AS t0, max(l.recorded_at) AS t1,
             row_number() OVER (PARTITION BY l.charger_type ORDER BY max(l.recorded_at) DESC) AS rk
        FROM public.ottoq_charge_duration_ledger l
       WHERE l.depot_id = c_twin AND l.stopped_reason = 'completed' AND l.tick_minutes <= 1
         AND l.charger_type IN ('dcfc', 'l2') AND l.sim_run_id IS NOT NULL AND l.recorded_at > now() - interval '21 days'
       GROUP BY 1, 2 HAVING count(*) >= 30) x
     WHERE x.rk = 1 ORDER BY x.kind
  LOOP
    v_p := public.ottoq_charge_time_v2_params(c_twin, g.t0 - interval '1 second', interval '21 days', 3);
    SELECT v_out || format('%s on run %s (%s charges, fitted through its first): inside the band %s%% -> %s%%; ', g.kind,
                           left(g.run::text, 8), count(*),
                           round(100.0 * avg((abs(z.w / z.sd0) <= 1.2816)::int), 1),
                           round(100.0 * avg((abs(z.w / z.sd1) <= 1.2816)::int), 1))
      INTO v_out
      FROM (SELECT y.lr - y.f0 - avg(y.lr - y.f0) OVER () AS w, y.sd0, y.sd1
              FROM (SELECT ln((l.duration_min / est.m)::numeric) AS lr,
                           (c0.c ->> 'f')::numeric AS f0, (c0.c ->> 'sd')::numeric AS sd0, (c1.c ->> 'sd')::numeric AS sd1
                      FROM public.ottoq_charge_duration_ledger l
                      JOIN public.vehicles v ON v.id = l.vehicle_id
                      CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
                      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end,
                                                                                      l.charger_kw, l.vehicle_kw) AS m) est
                      CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(jsonb_build_object('params', v_p - 'spread'), l.charger_type,
                                                   w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw,
                                                   jsonb_build_object('air_c', l.depot_air_c)) AS c) c0
                      CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock(jsonb_build_object('params', v_p), l.charger_type,
                                                   w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw,
                                                   jsonb_build_object('air_c', l.depot_air_c)) AS c) c1
                     WHERE l.sim_run_id = g.run AND l.charger_type = g.kind AND l.stopped_reason = 'completed'
                       AND l.tick_minutes <= 1 AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0) y
             WHERE y.sd0 > 0 AND y.sd1 > 0) z;
  END LOOP;
  RAISE NOTICE '0636 V4: out of sample, %', COALESCE(NULLIF(v_out, ''), 'no run has 30 charges of a kind; executed by the tests');
END $v4$;

-- ══ V5: the self-review reads it ═══════════════════════════════════════════════════════════════════════════════════════════
DO $v5$
DECLARE c_twin constant uuid := '11111111-1111-1111-1111-111111111111'; v jsonb; v_t timestamptz := clock_timestamp();
BEGIN
  v := public.ottoq_arbiter_self_assessment_v3(c_twin, now() - interval '7 days', false);
  RAISE NOTICE '0636 V5: the self-review in % ms; its band areas: %', round(extract(epoch FROM clock_timestamp() - v_t) * 1000),
    COALESCE((SELECT string_agg((x.value ->> 'status') || ' ' || (x.value ->> 'area') || ': ' || left(x.value ->> 'finding', 200), ' | ')
                FROM jsonb_array_elements(v -> 'improvement_areas') x WHERE x.value ->> 'area' LIKE 'charge_clock_band_%'), 'none');
END $v5$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0636_the_charge_clocks_spread_is_what_its_charges_show', false, false,
  'every charge clock fit measures, on its own charges once the clock knows the run, how wide each kind and length of '
  'charge runs against the spread the clock gives it (ottoq_charge_clock_spread_fit) and writes it as `spread`, behind the '
  'person''s dial charge_clock_spread_by_length (depot scope, 1; 0 is 0632''s fit); the clock scales its spread by the '
  'length''s factor and never moves its minutes; the self-review marks the band built until 30 charges come after the '
  'fit; the twin depot''s clock is refitted. FALSE/FALSE as 0622, 0625 and 0632: the clock is read by the check on an '
  'agent''s charge order, its futures, the agent''s board, the grader and the self-review; no kernel decision, dial or '
  'seat reads it, and no certification arm runs the agent or the charge order.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
