-- migration-version: PENDING
-- migration-name:    a_learned_model_knows_when_its_world_changed
--
-- 0625  **A learned model knows when its world changed, and finds the change itself.**
--       0622's clock learns each car's charge time from the depot's own charges over 21 days, newest heaviest. On
--       2026-09-30 at 11:53:08 UTC migration 0573 rebuilt the twin's fast-charge physics, and the clock has been learning
--       from charges on both sides of that line ever since: its fast-charge levels for Zoox and Tesla sit between two
--       worlds, and the self-review has said so every night as a "stale level" it could not explain. Nothing in the
--       engine could say "the world changed here; learn from what came after." 0625 gives it that, per model and per
--       kind of charger, as a record a person writes and every fit honours, and gives the system the instrument to find
--       such a change by itself, in its own evidence, with the migrations that landed while it happened beside it.
--       Chase, 2026-10-08: "if it can't technically do XYZ, I should probably build that in ... Ideally, after a while,
--       the system itself will pick up areas for self improvement." Rule 10 holds: the record is a person's (seeded here
--       by engineering for 0573), the scan only names a candidate, and the clock stays an estimate refitted nightly.
--
-- ══ §1 WHY (the clock's fits, the depot's completed charges and five runs after the change; measured 2026-10-08
--    20:40-23:30 UTC) ══
--
--   (a) The clock straddles a change it cannot see. Against the clock the depot uses (fit 1, through 2026-10-08 16:24),
--       the mean fast-charge residual by day: Zoox +0.78 to +1.19 on 09-27 to 09-29, then -0.11 to -0.17 every day
--       since; Waymo +0.05 to +0.31, then -0.06 to +0.06; Tesla -0.27 to 0.00, then -0.02 to +0.09. 0573 gave each
--       battery its own DC acceptance curve and corrected two cars' facts (the I-PACE to 84.7 kWh and 104 kW, the Zoox
--       to 133 kWh and 100 kW). With a 3-day half-life the charges before it still carry weight, and 588 of the fit's
--       fast charges are from 09-28/29: the Zoox fast-charge level is pulled 11-17% high on every charge since, and the
--       run spread the fit reads (0.186) is partly the two worlds, not the runs.
--   (b) Cut at the change, the clock is better out of sample on every run tried. Fitted through each run's start on the
--       charges after 0573 alone, against the 21-day fit, scored on the run's completed fast charges as the check times
--       them (the run's own evidence up to each charge): d9d49732 and baf29c05 (88 charges) mean absolute log error 0.110
--       -> 0.084 (-23%), Zoox bias -0.131 -> -0.026; fd6ed035 (56) 0.189 -> 0.106 (-44%), Zoox -0.226 -> +0.012; 0bbdcc07
--       (65) 0.131 -> 0.087 (-34%); 089f46bd (51) 0.131 -> 0.085 (-35%); ae8a4908 (88; 2.2 days after the change, 606
--       charges to learn from) 0.247 -> 0.112 (-55%), Zoox -0.345 -> -0.072.
--   (c) Only the fast chargers' world changed. 0573 left the L2 branch alone, and every car's limit on L2 is the 19.2 kW
--       charger. By day the L2 residual moves within +-0.15 with no step at 09-30, and cutting L2 at the same line helped
--       three of the five runs and cost two (ae8a4908 0.093 -> 0.107, +15%). So a change is recorded per kind of charger.
--   (d) Nor is a change in one model's world a change in another's. The departure dwell (0623/0624) fitted on the
--       evidence after 0573 alone graded worse on d9d49732's 61 orders (class Brier 0.101 -> 0.109; returns forecast over
--       real 1.19 -> 1.32): bay congestion drives the dwell, not the charge curve. So a change is recorded per model, and
--       a model reads the record only once a migration makes it.
--   (e) The system can find the change itself. Over the 21 days before 2026-10-08, with the run as the unit (its weather
--       and its draw are not a change), the fast charges split best between 09-29 01:18 and 09-30 12:58 UTC: q 777 on
--       3 classes, Zoox -1.14 (t -27), Waymo -0.21 (t -6.4), Tesla +0.09 (t 2.3). Of the 17 migrations applied in that
--       window, two create or replace a function about charging: 0570's ottoq_charge_slack_min and 0573's
--       ottoq_sim_compute_charge_rate. The L2 charges' best split is q 21.8 with no class past 0.098: not a change. After
--       0573 alone, the fast charges' best split is q 3.9 (largest shift 0.048): nothing more to find.
--   (f) The two worlds were also hiding inside the clock's structure. Fitted on the charges after 0573 alone (through
--       d9d49732's start), the fast-charge run spread falls from 0.184 to 0.055, the car's correlation across runs rises
--       from 0.28 to 0.55 and its correlation within a run falls from 0.91 to 0.50. Most of what 0622 §1(c) read as the
--       day a run is having (a run spread of 0.19) and as a car's condition carried from charge to charge was charges
--       from before and after the change sitting in different runs.
--
-- ══ §2 WHAT ══
--
--   (a) `public.ottoq_evidence_regimes`, append-only (override: ottoq.evidence_regimes_unlock=on), RLS read-only to
--       anon and authenticated: one row per change in a learned model's world, `model` (charge_time_v2 for now: a model
--       is added to the CHECK by the migration that makes it read the table), `scope` (dcfc, l2, or * for every kind),
--       `depot_id` (NULL for every depot), `starts_at`, `reason`, `source`, and who recorded it when. Seeded with 0573
--       for fast charges at the twin depot. `ottoq_evidence_regime_cuts(model, depot, from, through)`: the latest change
--       per scope inside a window.
--   (b) `ottoq_charge_time_v2_params_cut(depot, through, window, half_life, cuts)`: 0622's fit with the cuts an
--       explicit input. A kind cut inside the window is fitted on the charges recorded after the change alone, once
--       those carry the kind's pooled cell by themselves (30 charges, 10 effective, counted as the cell counts them);
--       until then on the whole window, as 0622 fits it, so a change recorded yesterday never leaves the depot on an
--       older fit. `regimes` in the params says which. `ottoq_charge_time_v2_params` now reads the record and calls it:
--       with nothing recorded inside the window, 0622's params key for key. `ottoq_fit_charge_time_v2` puts the cut
--       fit and the record's reader into its code md5. The nightly fit (11:22 UTC, 6:22 AM CT) honours the record.
--   (c) `ottoq_evidence_regime_scan(depot, since, model)`: has the clock's world changed inside the evidence it learns
--       from? Per kind, the completed fine-tick charges since the clock's window began and after the latest change
--       already recorded, each as its log ratio less the clock; each run's mean per class (3 charges or more; outside a
--       run, the day); every split of the runs in recorded order, each class's shift and its t on the pooled spread of
--       run means, summed into q. Named a change when q >= 10 per class and some class moved by 0.15 or more; the splits
--       within max(2 df + 2, 5% of q) of the best bound the window, and the migrations applied in it are listed, those
--       that create or replace a function about charging marked. A finding for a person, never a cut.
--   (d) `ottoq_charge_clock_trial(depot, runs, through, cuts_a, cuts_b, with_params)`: what a cut would have bought,
--       out of sample: the clock fitted through `through` under two sets of cuts, each scored on the runs' charges
--       recorded after it, as the check times them. An engineering instrument (V2 below is one call of it).
--   The record's reader and the scan may be called as 0622's audit may; the cut fit and the trial by the service only.
--
--   The tick path is untouched: the clock is read by the agent's charge-order check, board and grader on operator_demo
--   runs (0615) and by the nightly assessment. Nothing here writes a dial, a rule or the bar. 0619's charge_time_v1,
--   the clock's fallback and the assessment's baseline, is left as it is: it reads no record.
--
-- ══ §3 CHECKS ══
--
--   P0: nothing in flight. P1: the clock's params, fit, clock, run evidence, model, who, base estimate and band are the
--   bodies this file was written against (md5); nothing this file creates exists. Nothing here drops or deletes.
--   V0: before anything is recorded, the scan over the 21 days before 2026-10-08 names a change on fast chargers whose
--   window holds 0573's moment and lists 0573 among the migrations that redefine a charging function, and names none on
--   L2. (Skipped where the twin depot has no charges: the tests execute it on the miniature depot.)
--   V1: with no cut inside the window, the params are 0622's key for key: through 2026-09-30 11:53:00 over 2 days (the
--   record read, nothing inside), and through d9d49732's start over 21 days with no cuts. With the fast-charge cut, every
--   L2 key is unchanged, `regimes` holds dcfc alone, applied, its n_after the fast-charge pooled cell's n.
--   V2: THE GATE. ottoq_charge_clock_trial through d9d49732's start on d9d49732 and baf29c05: on fast chargers the cut's
--   mean absolute log error is at most 0.9 times the uncut's and its bias no worse by more than 0.02; on L2 every score
--   is identical. Or nothing here is applied.
--   V3: the fit at apply honours the record and is the depot's clock; after the record the scan finds nothing more on
--   fast chargers.
--   Dry run on the live database, 2026-10-08 23:52 UTC (rolled back), 25.4 s in all: the before-captures 4.9 s; V0 0.5 s,
--   fast chargers named (1,393 charges, 30 runs, q 777.2, window 09-29 01:18:36 to 09-30 12:58:00, 0570 and 0573 marked
--   among 17), L2 not (q 21.8); the trial 12.1 s; V1 passed, the cut carrying 559 fast charges (387.1 effective) of 1,305;
--   V2 on 88 fast charges 0.1098 -> 0.0843 (bias -0.0015 -> -0.0034), on 127 L2 charges 0.0852 either way; the fit 6.7 s,
--   usable on 647 fast charges after the change; V3's scan after the record q 6.6, largest shift 0.064, not named.
--   tests/test_agent_regime_sql.py executes the rest on the miniature depot.
--
-- ══ §4 RECERT ══
--
--   FALSE/FALSE. The clock is read by the agent's charge-order check, board and grader only, on operator_demo runs
--   (0615); no certification, sweep or dial pair arms an order. With nothing recorded inside its window every fit is
--   0622's (V1); the record and the fits are evidence.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0625_pre' (the params and the fit as 0622
--   left them); the fits written since keep their `regimes` key and stay readable. DROP FUNCTION
--   public.ottoq_charge_clock_trial(uuid, uuid[], timestamptz, jsonb, jsonb, boolean),
--   public.ottoq_evidence_regime_scan(uuid, timestamptz, jsonb),
--   public.ottoq_charge_time_v2_params_cut(uuid, timestamptz, interval, numeric, jsonb),
--   public.ottoq_evidence_regime_cuts(text, uuid, timestamptz, timestamptz); the table ottoq_evidence_regimes may stay
--   (nothing else reads it); DELETE FROM public.ottoq_cert_lineage WHERE name = '0625_a_learned_model_knows_when_its_world_changed'.

BEGIN;

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0625 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_charge_time_v2_params(uuid,timestamp with time zone,interval,numeric)', '456b356f', 'the clock''s params (0622)'),
      ('public.ottoq_fit_charge_time_v2(uuid,timestamp with time zone,interval,numeric,text)', 'afbed035', 'the clock''s fit (0622)'),
      ('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)', '03dc08a0', 'the clock (0622)'),
      ('public.ottoq_charge_clock_run_evidence(jsonb,uuid,timestamp with time zone)', '314444ef', 'the run''s evidence (0622)'),
      ('public.ottoq_charge_clock_model(uuid)', '5639032d', 'the depot''s clock (0622)'),
      ('public.ottoq_charge_clock_who(uuid,text,text,text)', '9d3ad357', 'the clock''s keys (0622)'),
      ('public.ottoq_charge_minutes_estimate(numeric,numeric,numeric,numeric,numeric)', '21f22ff8', 'the base estimate (0614)'),
      ('public.ottoq_charge_time_band(numeric)', '9212138a', 'the band (0619)'))
    AS x(sig, md5, what)
  LOOP
    IF left((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)), 8) IS DISTINCT FROM r.md5 THEN
      RAISE EXCEPTION '0625 P1: % is not the body this file was written against (md5 %); read it again', r.what, r.md5;
    END IF;
  END LOOP;
  IF to_regclass('public.ottoq_evidence_regimes') IS NOT NULL
     OR to_regprocedure('public.ottoq_evidence_regime_cuts(text,uuid,timestamp with time zone,timestamp with time zone)') IS NOT NULL
     OR to_regprocedure('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)') IS NOT NULL
     OR to_regprocedure('public.ottoq_evidence_regime_scan(uuid,timestamp with time zone,jsonb)') IS NOT NULL
     OR to_regprocedure('public.ottoq_charge_clock_trial(uuid,uuid[],timestamp with time zone,jsonb,jsonb,boolean)') IS NOT NULL THEN
    RAISE EXCEPTION '0625 P1: something this file creates already exists';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0625_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_charge_time_v2_params(uuid,timestamp with time zone,interval,numeric)'::regprocedure,
                 'public.ottoq_fit_charge_time_v2(uuid,timestamp with time zone,interval,numeric,text)'::regprocedure);

-- V1's "before": 0622's params through a moment just before 0573 over 2 days, and through d9d49732's start over 21 days
CREATE TEMP TABLE v0625_before ON COMMIT DROP AS
SELECT 'pre_boundary'::text AS what,
       public.ottoq_charge_time_v2_params('11111111-1111-1111-1111-111111111111'::uuid, '2026-09-30 11:53:00+00'::timestamptz,
                                          interval '2 days', 3) AS j
UNION ALL
SELECT 'd9d49732', public.ottoq_charge_time_v2_params(r.depot_id, r.started_at, interval '21 days', 3)
  FROM public.ottoq_sim_runs r
 WHERE r.sim_run_id = 'd9d49732-cf28-42c3-aac9-9c3f606a2c92' AND r.status = 'completed';
CREATE TEMP TABLE v0625_trial (j jsonb) ON COMMIT DROP;

-- ══ (a) the record ══
CREATE TABLE public.ottoq_evidence_regimes (
  regime_id   bigserial PRIMARY KEY,
  --: the learned model whose world changed; one that reads this table (a migration adds it here when it makes it)
  model       text NOT NULL CHECK (model IN ('charge_time_v2')),
  --: the part of the model's world that changed: for charge_time_v2 a kind of charger, or * for every kind
  scope       text NOT NULL DEFAULT '*',
  --: the depot whose world changed, or NULL for every depot
  depot_id    uuid,
  --: the real-clock moment the change took effect (evidence recorded after it is the new world's)
  starts_at   timestamptz NOT NULL,
  reason      text NOT NULL CHECK (length(btrim(reason)) >= 20),
  --: what made the change, or how it was found: a migration and its version, an incident, a scan
  source      text NOT NULL CHECK (length(btrim(source)) >= 3),
  recorded_by text NOT NULL DEFAULT current_user,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ottoq_evidence_regimes_scope CHECK (model <> 'charge_time_v2' OR scope IN ('*', 'dcfc', 'l2'))
);

COMMENT ON TABLE public.ottoq_evidence_regimes IS
'0625. One row per change in a learned model''s world: from starts_at the evidence of `scope` (a kind of charger, or * for all) at `depot_id` (NULL: every depot) is the new world''s, and a fit of `model` learns from it alone once it carries the fit by itself. Read through ottoq_evidence_regime_cuts by ottoq_charge_time_v2_params (charge_time_v2, 0622). Written by a person, or by a migration that changes the world a model learns from; ottoq_evidence_regime_scan finds candidates and never writes here (CLAUDE.md rule 10). Append-only (override: ottoq.evidence_regimes_unlock=on). No run column: it belongs to the depot and outlives every purge.';

CREATE INDEX ottoq_evidence_regimes_lookup_idx ON public.ottoq_evidence_regimes (model, starts_at DESC);

CREATE FUNCTION public.ottoq_evidence_regimes_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF COALESCE(current_setting('ottoq.evidence_regimes_unlock', true), '') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION
    'ottoq_evidence_regimes is append-only: % refused. A change of mind is a new row. Set '
    'ottoq.evidence_regimes_unlock=on in the session to override, and say why in a migration.', TG_OP
    USING ERRCODE = '42501';
END $fn$;

CREATE TRIGGER ottoq_evidence_regimes_append_only_trg
  BEFORE UPDATE OR DELETE ON public.ottoq_evidence_regimes
  FOR EACH ROW EXECUTE FUNCTION public.ottoq_evidence_regimes_append_only();

ALTER TABLE public.ottoq_evidence_regimes ENABLE ROW LEVEL SECURITY;
CREATE POLICY ottoq_evidence_regimes_read ON public.ottoq_evidence_regimes FOR SELECT USING (true);
REVOKE ALL ON public.ottoq_evidence_regimes FROM anon, authenticated;
GRANT SELECT ON public.ottoq_evidence_regimes TO anon, authenticated;

CREATE FUNCTION public.ottoq_evidence_regime_cuts(p_model text, p_depot uuid, p_from timestamptz, p_through timestamptz)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
SET timezone TO 'UTC'
AS $fn$
  -- 0625: for a fit of p_model at p_depot on evidence recorded in (p_from, p_through], the latest recorded change in each
  -- part of the model's world inside that window, {scope: starts_at}; '{}' when there is none. A change recorded for
  -- every depot (depot_id NULL) counts at each. The table records when the world changed, not when it was written down:
  -- a change recorded late still cuts a later fit, and each fit's params name the cut it used.
  SELECT COALESCE(jsonb_object_agg(x.scope, x.starts_at), '{}'::jsonb)
    FROM (SELECT r.scope, max(r.starts_at) AS starts_at
            FROM public.ottoq_evidence_regimes r
           WHERE r.model = p_model AND (r.depot_id IS NULL OR r.depot_id = p_depot)
             AND r.starts_at > p_from AND r.starts_at <= p_through
           GROUP BY r.scope) x
$fn$;

-- ══ (b) the clock's fit honours it ══
CREATE FUNCTION public.ottoq_charge_time_v2_params_cut(p_depot uuid, p_through timestamptz, p_window interval,
                                                       p_half_life_days numeric, p_cuts jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
/* 0622: the params of a charge_time_v2 fit for a depot from its completed charges recorded in (through - window,
   through], without writing anything: the evidence is held in an array of ottoq_charge_clock_evidence and each stage's
   residuals in an array beside it. Every charge weighs 0.5^(age in days / half-life). Each level is a robust weighted
   median of what the levels above left (the residual is computed by ottoq_charge_clock itself, so the fit and every
   reader agree by construction), shrunk toward zero by k = within-level variance over between-group variance (method of
   moments, floor 2). Then the run's prior strength, the across-run and in-run correlations of a car's residuals, and the
   in-session regression from the MeterValues of completed charges. Deterministic for a given ledger and through.
   0625: and for the given cuts. p_cuts names, per kind ('dcfc', 'l2', or '*' for both), when its world last changed
   ({kind: timestamptz}); ottoq_charge_time_v2_params passes the changes recorded in ottoq_evidence_regimes and
   ottoq_charge_clock_trial any it is asked to try. A cut outside the window is ignored. A kind cut inside it is fitted
   on the charges recorded after the change alone, once they carry the kind's pooled cell by themselves (c_min_cell
   charges and c_min_neff effective ones, counted as the cell counts them); until then on the whole window as 0622 fitted
   it. Either way `regimes` says which. With no cut inside the window, 0622's params, key for key. */
DECLARE
  c_min_fine  constant int := 100;
  c_min_cell  constant int := 30;
  c_min_neff  constant numeric := 10;
  c_k_floor   constant float8 := 2;
  c_min_pairs constant int := 20;
  v_through   timestamptz := COALESCE(p_through, now());
  v_from      timestamptz := COALESCE(p_through, now()) - COALESCE(p_window, interval '21 days');
  v_cut       jsonb;      -- 0625: per kind, where a change in its world cuts the window
  v_reg       jsonb;      -- 0625: what each cut did
  v_h         float8 := GREATEST(COALESCE(p_half_life_days, 3), 0.25)::float8;
  v_e         public.ottoq_charge_clock_evidence[];
  v_r         float8[];   -- each charge's residual once the class levels are out, aligned with v_e
  v_r2        float8[];   -- ... and its run's offset
  v_r3        float8[];   -- ... and its car's offset across runs
  v_pop       jsonb;
  v_p         jsonb;
  v_m         jsonb;
  v_lvl       jsonb;
  v_rms       jsonb;
  v_level     text;
  v_ladder    jsonb := '{}'::jsonb;
  v_icc       jsonb := '{}'::jsonb;
  v_run       jsonb := '{}'::jsonb;
  v_veh       jsonb;
  v_sess      jsonb := '{}'::jsonb;
  v_within    jsonb;
  v_n         int;
  v_runs      int;
BEGIN
  IF p_depot IS NULL THEN RAISE EXCEPTION 'ottoq_charge_time_v2_params: a depot is required'; END IF;
  -- 0625: the cuts inside (from, through]; a kind the clock does not know is a mistake, not a cut to ignore
  IF EXISTS (SELECT 1 FROM jsonb_each(COALESCE(p_cuts, '{}'::jsonb)) c
              WHERE c.key NOT IN ('dcfc', 'l2', '*') OR jsonb_typeof(c.value) <> 'string') THEN
    RAISE EXCEPTION 'ottoq_charge_time_v2_params_cut: a cut is {kind: timestamptz} with kind dcfc, l2 or *, not %', p_cuts;
  END IF;
  SELECT COALESCE(jsonb_object_agg(c.key, c.value), '{}'::jsonb) INTO v_cut
    FROM jsonb_each(COALESCE(p_cuts, '{}'::jsonb)) c
   WHERE (c.value #>> '{}')::timestamptz > v_from AND (c.value #>> '{}')::timestamptz <= v_through;

  -- the evidence and its population: a kind with c_min_fine charges at ticks of a minute or less fits on those alone (a
  -- 5-minute tick rounds every charge up to the next tick, 0619)
  WITH b0 AS (
    SELECT l.session_id, l.sim_run_id, l.charger_type AS kind, w.j AS who,
           (l.tick_minutes IS NOT NULL AND l.tick_minutes <= 1) AS fine,
           ln((l.duration_min / est.m)::float8) AS lr,
           power(0.5::float8, GREATEST(extract(epoch FROM (v_through - l.recorded_at))::float8, 0) / 86400.0 / v_h) AS w,
           l.started_at, l.ended_at, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw,
           -- 0625: recorded after the latest change in this kind's world inside the window (every charge, with none)
           l.recorded_at > GREATEST(COALESCE((v_cut ->> l.charger_type)::timestamptz, v_from),
                                    COALESCE((v_cut ->> '*')::timestamptz, v_from)) AS after
      FROM ottoq_charge_duration_ledger l
      JOIN vehicles v ON v.id = l.vehicle_id
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                      l.vehicle_kw) AS m) est
     WHERE l.depot_id = p_depot AND l.recorded_at > v_from AND l.recorded_at <= v_through
       AND l.stopped_reason = 'completed' AND l.charger_type IN ('dcfc', 'l2')
       AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0
  ), pa AS (   -- 0625: the population the charges after a change would have by themselves
    SELECT b0.kind, count(*) FILTER (WHERE b0.after AND b0.fine) >= c_min_fine AS fine FROM b0 GROUP BY b0.kind
  ), ka AS (   -- 0625: ... and whether they carry the kind's pooled cell by themselves, counted as the cell counts
    SELECT pa.kind, count(*) FILTER (WHERE b0.after AND (b0.fine OR NOT pa.fine)) AS n,
           sum(b0.w) FILTER (WHERE b0.after AND (b0.fine OR NOT pa.fine)) AS sw,
           sum(b0.w * b0.w) FILTER (WHERE b0.after AND (b0.fine OR NOT pa.fine)) AS sw2
      FROM pa JOIN b0 USING (kind) GROUP BY pa.kind
  ), kc AS (
    SELECT ka.kind, ka.n, ka.sw * ka.sw / NULLIF(ka.sw2, 0) AS neff,
           ka.n >= c_min_cell AND COALESCE(ka.sw * ka.sw / NULLIF(ka.sw2, 0), 0) >= c_min_neff AS carries
      FROM ka
  ), b AS (    -- 0625: a kind is cut only when the charges after its change carry it alone
    SELECT b0.* FROM b0 JOIN kc USING (kind) WHERE b0.after OR NOT kc.carries
  ), pop AS (
    SELECT b.kind, CASE WHEN count(*) FILTER (WHERE b.fine) >= c_min_fine THEN 'fine_ticks' ELSE 'all_ticks' END AS p
      FROM b GROUP BY b.kind
  )
  SELECT (SELECT COALESCE(jsonb_object_agg(pop.kind, pop.p), '{}'::jsonb) FROM pop),
         (SELECT array_agg(ROW(b.session_id::uuid, b.sim_run_id::uuid, b.kind::text,
                               public.ottoq_charge_time_band(b.soc_start)::text, b.who, (b.who ->> 'cls')::text,
                               (b.who ->> 'mdl')::text, (b.who ->> 'veh')::text, b.lr, b.w, b.started_at::timestamptz,
                               b.ended_at::timestamptz, b.battery_kwh::numeric, b.soc_start::numeric, b.soc_end::numeric,
                               b.charger_kw::numeric, b.vehicle_kw::numeric)::public.ottoq_charge_clock_evidence
                           ORDER BY b.session_id)
            FROM b JOIN pop USING (kind)
           WHERE b.fine OR pop.p = 'all_ticks'),
         (SELECT COALESCE(jsonb_object_agg(k.kind, jsonb_build_object(
                   'starts_at', CASE WHEN COALESCE((v_cut ->> k.kind)::timestamptz, '-infinity'::timestamptz)
                                          >= COALESCE((v_cut ->> '*')::timestamptz, '-infinity'::timestamptz)
                                     THEN v_cut -> k.kind ELSE v_cut -> '*' END,
                   'applied', COALESCE(kc.carries, false), 'n_after', COALESCE(kc.n, 0),
                   'n_eff_after', COALESCE(round(kc.neff::numeric, 1), 0))), '{}'::jsonb)
            FROM (VALUES ('dcfc'), ('l2')) k(kind) LEFT JOIN kc USING (kind)
           WHERE v_cut ? k.kind OR v_cut ? '*')
    INTO v_pop, v_e, v_reg;
  v_e := COALESCE(v_e, '{}'::public.ottoq_charge_clock_evidence[]);
  SELECT count(*), count(DISTINCT x.run) INTO v_n, v_runs FROM unnest(v_e) x;

  -- ── the pooled cells: per kind and band, and per kind: the weighted median, the weighted MAD, n, n_eff ──
  WITH src AS (
    SELECT x.kind, x.band AS cell, x.lr, x.w, x.sid, x.run FROM unnest(v_e) x
    UNION ALL
    SELECT x.kind, '*', x.lr, x.w, x.sid, x.run FROM unnest(v_e) x
  ), o AS (
    SELECT src.*, sum(src.w) OVER (PARTITION BY src.kind, src.cell ORDER BY src.lr, src.sid) AS cw,
           sum(src.w) OVER (PARTITION BY src.kind, src.cell) AS tw
      FROM src
  ), med AS (
    SELECT o.kind, o.cell, min(o.lr) FILTER (WHERE o.cw >= o.tw / 2) AS mu, count(*) AS n, count(DISTINCT o.run) AS runs,
           sum(o.w) AS sw, sum(o.w * o.w) AS sw2
      FROM o GROUP BY o.kind, o.cell
  ), od AS (
    SELECT src.kind, src.cell, abs(src.lr - med.mu) AS dv,
           sum(src.w) OVER (PARTITION BY src.kind, src.cell ORDER BY abs(src.lr - med.mu), src.sid) AS cw,
           sum(src.w) OVER (PARTITION BY src.kind, src.cell) AS tw
      FROM src JOIN med ON med.kind = src.kind AND med.cell = src.cell
  ), mad AS (
    SELECT od.kind, od.cell, min(od.dv) FILTER (WHERE od.cw >= od.tw / 2) AS mad FROM od GROUP BY od.kind, od.cell
  )
  SELECT COALESCE(jsonb_object_agg(med.kind || ':' || med.cell, jsonb_build_object(
           'factor', round(exp(med.mu)::numeric, 4), 'log_sd', round((1.4826 * mad.mad)::numeric, 4),
           'n', med.n, 'n_eff', round((med.sw * med.sw / NULLIF(med.sw2, 0))::numeric, 1), 'runs', med.runs,
           'usable', med.n >= c_min_cell AND med.sw * med.sw / NULLIF(med.sw2, 0) >= c_min_neff)), '{}'::jsonb)
    INTO v_lvl
    FROM med JOIN mad USING (kind, cell);

  v_p := jsonb_build_object('cells', v_lvl, 'class_cells', '{}'::jsonb, 'model_cells', '{}'::jsonb,
                            'vehicle_cells', '{}'::jsonb);
  v_m := jsonb_build_object('params', v_p);

  -- ── class, model, class and band: each a shrunk robust offset on what the levels above left ──
  FOREACH v_level IN ARRAY ARRAY['class', 'model', 'class_band'] LOOP
    WITH e AS (
      SELECT x.kind, x.sid, x.w,
             CASE v_level WHEN 'class' THEN x.cls WHEN 'model' THEN x.mdl ELSE x.cls || '|' || x.band END AS grp,
             x.lr - (public.ottoq_charge_clock(v_m, x.kind, x.who, x.bat, x.s0, x.s1, x.ckw, x.vkw, NULL) ->> 'f')::float8 AS r
        FROM unnest(v_e) x
    ), o AS (
      SELECT e.*, sum(e.w) OVER (PARTITION BY e.kind, e.grp ORDER BY e.r, e.sid) AS cw,
             sum(e.w) OVER (PARTITION BY e.kind, e.grp) AS tw
        FROM e
    ), g AS (
      SELECT o.kind, o.grp, min(o.r) FILTER (WHERE o.cw >= o.tw / 2) AS d, count(*) AS n,
             sum(o.w) * sum(o.w) / NULLIF(sum(o.w * o.w), 0) AS neff
        FROM o GROUP BY o.kind, o.grp
    ), sw AS (   -- the within-group variance of the residual, per kind
      SELECT e.kind, sum(e.w * (e.r - g.d) ^ 2) / NULLIF(sum(e.w), 0) AS s2
        FROM e JOIN g ON g.kind = e.kind AND g.grp = e.grp GROUP BY e.kind
    ), tb AS (   -- the between-group variance beyond what sampling explains (method of moments)
      SELECT g.kind,
             GREATEST(sum(g.neff * (g.d - x.dbar) ^ 2) / NULLIF(sum(g.neff), 0) - avg(sw.s2 / NULLIF(g.neff, 0)), 1e-4) AS t2
        FROM g JOIN sw USING (kind)
        JOIN (SELECT g2.kind, sum(g2.neff * g2.d) / NULLIF(sum(g2.neff), 0) AS dbar FROM g g2 GROUP BY g2.kind) x USING (kind)
       GROUP BY g.kind
    ), kk AS (
      SELECT sw.kind, GREATEST(sw.s2 / tb.t2, c_k_floor) AS k FROM sw JOIN tb USING (kind)
    )
    SELECT (SELECT COALESCE(jsonb_object_agg(g.kind || '|' || g.grp, jsonb_build_object(
                     'off', round((g.d * g.neff / (g.neff + kk.k))::numeric, 4), 'raw', round(g.d::numeric, 4), 'n', g.n,
                     'n_eff', round(g.neff::numeric, 1), 'k', round(kk.k::numeric, 2))), '{}'::jsonb)
              FROM g JOIN kk USING (kind)
             WHERE g.d IS NOT NULL AND g.neff > 0),
           (SELECT jsonb_object_agg(z.kind, z.rms)
              FROM (SELECT e.kind, round(sqrt(sum(e.w * e.r * e.r) / sum(e.w))::numeric, 4) AS rms FROM e GROUP BY e.kind) z)
      INTO v_lvl, v_rms;
    v_ladder := v_ladder || jsonb_build_object('before_' || v_level, v_rms);
    IF v_level = 'model' THEN
      v_p := jsonb_set(v_p, '{model_cells}', v_lvl);
    ELSE
      v_p := jsonb_set(v_p, '{class_cells}', (v_p -> 'class_cells') || v_lvl);
    END IF;
    v_m := jsonb_build_object('params', v_p);
  END LOOP;

  -- ── each class's own spread: the robust weighted spread of what the class levels leave, shrunk toward the kind's ──
  v_r := ARRAY(SELECT x.lr - (public.ottoq_charge_clock(v_m, x.kind, x.who, x.bat, x.s0, x.s1, x.ckw, x.vkw, NULL) ->> 'f')::float8
                 FROM unnest(v_e) WITH ORDINALITY x ORDER BY x.ordinality);
  v_ladder := v_ladder || jsonb_build_object('after_class_levels',
                (SELECT jsonb_object_agg(z.kind, z.rms) FROM (
                   SELECT x.kind, round(sqrt(sum(x.w * v_r[x.ordinality] ^ 2) / sum(x.w))::numeric, 4) AS rms
                     FROM unnest(v_e) WITH ORDINALITY x GROUP BY x.kind) z));
  WITH e AS (
    SELECT x.kind, x.cls, x.w, x.sid, v_r[x.ordinality] AS r FROM unnest(v_e) WITH ORDINALITY x
  ), src AS (
    SELECT e.kind, e.cls AS grp, abs(e.r) AS dv, e.w, e.sid FROM e
    UNION ALL
    SELECT e.kind, '*', abs(e.r), e.w, e.sid FROM e
  ), o AS (
    SELECT src.*, sum(src.w) OVER (PARTITION BY src.kind, src.grp ORDER BY src.dv, src.sid) AS cw,
           sum(src.w) OVER (PARTITION BY src.kind, src.grp) AS tw
      FROM src
  ), s AS (
    SELECT o.kind, o.grp, 1.4826 * min(o.dv) FILTER (WHERE o.cw >= o.tw / 2) AS sd,
           sum(o.w) * sum(o.w) / NULLIF(sum(o.w * o.w), 0) AS neff
      FROM o GROUP BY o.kind, o.grp
  )
  SELECT jsonb_object_agg(s.kind || '|' || s.grp,
           round(((s.neff * s.sd + 10 * k.sd) / (s.neff + 10))::numeric, 4))
    INTO v_within
    FROM s JOIN s k ON k.kind = s.kind AND k.grp = '*';
  SELECT COALESCE(jsonb_object_agg(c.key, c.value || jsonb_build_object('sd', v_within -> c.key)), '{}'::jsonb)
    INTO v_lvl
    FROM jsonb_each(v_p -> 'class_cells') c
   WHERE array_length(string_to_array(c.key, '|'), 1) = 2 AND v_within ? c.key;
  v_p := jsonb_set(v_p, '{class_cells}', (v_p -> 'class_cells') || v_lvl);
  v_m := jsonb_build_object('params', v_p);

  -- ── the run: how far a run's mean departs beyond sampling (its prior strength), and its shrunk offsets ──
  WITH e AS (
    SELECT x.kind, x.run, x.w, v_r[x.ordinality] AS r FROM unnest(v_e) WITH ORDINALITY x WHERE x.run IS NOT NULL
  ), ru AS (
    SELECT e.kind, e.run, avg(e.r) AS u, count(*) AS n FROM e GROUP BY e.kind, e.run
  ), sw AS (
    SELECT e.kind, sum(e.w * e.r * e.r) / NULLIF(sum(e.w), 0) AS s2 FROM e GROUP BY e.kind
  ), t AS (
    SELECT ru.kind, count(*) AS runs, GREATEST(var_samp(ru.u) - avg(sw.s2 / ru.n), 0) AS t2, max(sw.s2) AS s2
      FROM ru JOIN sw USING (kind) WHERE ru.n >= 3 GROUP BY ru.kind
  )
  SELECT COALESCE(jsonb_object_agg(t.kind, jsonb_build_object(
           'k', round(LEAST(GREATEST(CASE WHEN t.t2 > 1e-4 THEN t.s2 / t.t2 ELSE 1000 END, 1), 1000)::numeric, 2),
           'tau', round(sqrt(t.t2)::numeric, 4), 'runs', t.runs)), '{}'::jsonb)
    INTO v_run
    FROM t;
  v_r2 := ARRAY(
    SELECT v_r[x.ordinality] - COALESCE(ru.u * ru.n / (ru.n + COALESCE((v_run #>> ARRAY[x.kind, 'k'])::float8, 1000)), 0)
      FROM unnest(v_e) WITH ORDINALITY x
      LEFT JOIN (SELECT y.kind, y.run, avg(v_r[y.ordinality]) AS u, count(*) AS n
                   FROM unnest(v_e) WITH ORDINALITY y WHERE y.run IS NOT NULL GROUP BY y.kind, y.run) ru
        ON ru.kind = x.kind AND ru.run = x.run
     ORDER BY x.ordinality);
  v_ladder := v_ladder || jsonb_build_object('after_run',
                (SELECT jsonb_object_agg(z.kind, z.rms) FROM (
                   SELECT x.kind, round(sqrt(sum(x.w * v_r2[x.ordinality] ^ 2) / sum(x.w))::numeric, 4) AS rms
                     FROM unnest(v_e) WITH ORDINALITY x GROUP BY x.kind) z));

  -- ── the car across runs: the correlation of its run means, and its offset shrunk by Spearman-Brown ──
  WITH e AS (
    SELECT x.kind, x.veh, x.run, x.st, x.sid, x.w, v_r2[x.ordinality] AS r FROM unnest(v_e) WITH ORDINALITY x
  ), vr AS (
    SELECT e.kind, e.veh, e.run, avg(e.r) AS m, max(e.w) AS w FROM e GROUP BY e.kind, e.veh, e.run
  ), pr AS (
    SELECT a.kind, a.m AS x, b.m AS y, a.w * b.w AS w
      FROM vr a JOIN vr b ON a.kind = b.kind AND a.veh = b.veh AND a.run < b.run
  ), rho AS (
    SELECT pr.kind, count(*) AS pairs,
           (sum(pr.w * pr.x * pr.y) / sum(pr.w) - (sum(pr.w * pr.x) / sum(pr.w)) * (sum(pr.w * pr.y) / sum(pr.w)))
             / NULLIF(sqrt(GREATEST(sum(pr.w * pr.x * pr.x) / sum(pr.w) - (sum(pr.w * pr.x) / sum(pr.w)) ^ 2, 0))
                      * sqrt(GREATEST(sum(pr.w * pr.y * pr.y) / sum(pr.w) - (sum(pr.w * pr.y) / sum(pr.w)) ^ 2, 0)), 0) AS c
      FROM pr GROUP BY pr.kind
  ), one AS (   -- single charges of the same car in different runs (each run's first), for the share of a charge's spread
    SELECT DISTINCT ON (e.kind, e.veh, e.run) e.kind, e.veh, e.run, e.r, e.w FROM e ORDER BY e.kind, e.veh, e.run, e.st, e.sid
  ), prs AS (
    SELECT a.kind, a.r AS x, b.r AS y, a.w * b.w AS w FROM one a JOIN one b ON a.kind = b.kind AND a.veh = b.veh AND a.run < b.run
  ), rhos AS (
    SELECT prs.kind,
           (sum(prs.w * prs.x * prs.y) / sum(prs.w) - (sum(prs.w * prs.x) / sum(prs.w)) * (sum(prs.w * prs.y) / sum(prs.w)))
             / NULLIF(sqrt(GREATEST(sum(prs.w * prs.x * prs.x) / sum(prs.w) - (sum(prs.w * prs.x) / sum(prs.w)) ^ 2, 0))
                      * sqrt(GREATEST(sum(prs.w * prs.y * prs.y) / sum(prs.w) - (sum(prs.w * prs.y) / sum(prs.w)) ^ 2, 0)), 0) AS c
      FROM prs GROUP BY prs.kind
  )
  SELECT COALESCE(jsonb_object_agg(k.kind, jsonb_build_object(
           'vehicle', round(CASE WHEN COALESCE(rho.pairs, 0) >= c_min_pairs THEN LEAST(GREATEST(rho.c, 0), 0.9) ELSE 0 END::numeric, 4),
           'vehicle_single', round(CASE WHEN COALESCE(rho.pairs, 0) >= c_min_pairs THEN LEAST(GREATEST(rhos.c, 0), 0.9) ELSE 0 END::numeric, 4),
           'vehicle_pairs', COALESCE(rho.pairs, 0))), '{}'::jsonb)
    INTO v_icc
    FROM (SELECT DISTINCT e.kind FROM e) k LEFT JOIN rho USING (kind) LEFT JOIN rhos USING (kind);
  WITH vr AS (
    SELECT x.kind, x.veh, x.run, avg(v_r2[x.ordinality]) AS m, max(x.w) AS w
      FROM unnest(v_e) WITH ORDINALITY x GROUP BY x.kind, x.veh, x.run
  ), v AS (
    SELECT vr.kind, vr.veh, sum(vr.w * vr.m) / NULLIF(sum(vr.w), 0) AS g, sum(vr.w) * sum(vr.w) / NULLIF(sum(vr.w * vr.w), 0) AS reff,
           count(*) AS runs, COALESCE((v_icc #>> ARRAY[vr.kind, 'vehicle'])::float8, 0) AS rho
      FROM vr GROUP BY vr.kind, vr.veh
  )
  SELECT COALESCE(jsonb_object_agg(v.kind || '|' || v.veh, jsonb_build_object(
           's', round((v.reff * v.rho / (1 + (v.reff - 1) * v.rho))::numeric, 4),
           'off', round((v.reff * v.rho / (1 + (v.reff - 1) * v.rho) * v.g)::numeric, 4),
           'runs', v.runs, 'r_eff', round(v.reff::numeric, 2))), '{}'::jsonb)
    INTO v_veh
    FROM v WHERE v.rho > 0 AND v.g IS NOT NULL;
  v_p := jsonb_set(v_p, '{vehicle_cells}', v_veh);
  v_m := jsonb_build_object('params', v_p);

  -- ── the car in its run: consecutive charges of the same car in the same run, once the car's cross-run offset is out ──
  v_r3 := ARRAY(SELECT v_r2[x.ordinality] - COALESCE((v_veh #>> ARRAY[x.kind || '|' || x.veh, 'off'])::float8, 0)
                  FROM unnest(v_e) WITH ORDINALITY x ORDER BY x.ordinality);
  v_ladder := v_ladder || jsonb_build_object('after_vehicle',
                (SELECT jsonb_object_agg(z.kind, z.rms) FROM (
                   SELECT x.kind, round(sqrt(sum(x.w * v_r3[x.ordinality] ^ 2) / sum(x.w))::numeric, 4) AS rms
                     FROM unnest(v_e) WITH ORDINALITY x GROUP BY x.kind) z));
  WITH e AS (
    SELECT x.kind, x.veh, x.run, x.st, x.sid, x.w, v_r3[x.ordinality] AS r FROM unnest(v_e) WITH ORDINALITY x
  ), s AS (
    SELECT e.kind, e.r AS x, lead(e.r) OVER (PARTITION BY e.kind, e.veh, e.run ORDER BY e.st, e.sid) AS y,
           LEAST(e.w, lead(e.w) OVER (PARTITION BY e.kind, e.veh, e.run ORDER BY e.st, e.sid)) AS w
      FROM e
  ), c AS (
    SELECT s.kind, count(*) AS pairs,
           (sum(s.w * s.x * s.y) / sum(s.w) - (sum(s.w * s.x) / sum(s.w)) * (sum(s.w * s.y) / sum(s.w)))
             / NULLIF(sqrt(GREATEST(sum(s.w * s.x * s.x) / sum(s.w) - (sum(s.w * s.x) / sum(s.w)) ^ 2, 0))
                      * sqrt(GREATEST(sum(s.w * s.y * s.y) / sum(s.w) - (sum(s.w * s.y) / sum(s.w)) ^ 2, 0)), 0) AS rho
      FROM s WHERE s.y IS NOT NULL GROUP BY s.kind
  )
  SELECT COALESCE(jsonb_object_agg(k.key, k.value || jsonb_build_object(
           'in_run', round(CASE WHEN COALESCE(c.pairs, 0) >= c_min_pairs THEN LEAST(GREATEST(c.rho, 0), 0.95) ELSE 0 END::numeric, 4),
           'in_run_pairs', COALESCE(c.pairs, 0))), '{}'::jsonb)
    INTO v_icc
    FROM jsonb_each(v_icc) k LEFT JOIN c ON c.kind = k.key;

  -- ── the charge in progress: the remaining part's residual on the done part's, at a quarter, half, three quarters ──
  v_p := v_p || jsonb_build_object('icc', v_icc, 'run', v_run);
  v_m := jsonb_build_object('params', v_p);
  WITH cut AS (
    SELECT x.*, q.frac, x.s0 + q.frac * (x.s1 - x.s0) AS soc_cut
      FROM unnest(v_e) x CROSS JOIN (VALUES (0.25::numeric), (0.5), (0.75)) q(frac)
     WHERE x.s1 - x.s0 >= 8
  ), mv AS (
    SELECT cut.*, m.t_at, m.soc_at
      FROM cut
      CROSS JOIN LATERAL (
        SELECT mm.sim_clock_at AS t_at, (mm.payload -> 'sampledValue' -> 1 ->> 'value')::numeric AS soc_at
          FROM ottoq_ocpp_messages mm
         WHERE mm.ocpp_session_id = cut.sid AND mm.message_type = 'MeterValues'
           AND (mm.payload -> 'sampledValue' -> 1 ->> 'measurand') = 'SoC'
           AND (mm.payload -> 'sampledValue' -> 1 ->> 'value')::numeric >= cut.soc_cut
         ORDER BY mm.message_at
         LIMIT 1) m
  ), xy AS (
    SELECT mv.kind, mv.w,
           ln((extract(epoch FROM (mv.t_at - mv.st)) / 60.0 / b1.m)::numeric)
             - (public.ottoq_charge_clock(v_m, mv.kind, mv.who, mv.bat, mv.s0, mv.soc_at, mv.ckw, mv.vkw, NULL) ->> 'f')::numeric AS x,
           ln((extract(epoch FROM (mv.en - mv.t_at)) / 60.0 / b2.m)::numeric)
             - (public.ottoq_charge_clock(v_m, mv.kind, mv.who, mv.bat, mv.soc_at, mv.s1, mv.ckw, mv.vkw, NULL) ->> 'f')::numeric AS y,
           mv.sid
      FROM mv
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(mv.bat, mv.s0, mv.soc_at, mv.ckw, mv.vkw) AS m) b1
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(mv.bat, mv.soc_at, mv.s1, mv.ckw, mv.vkw) AS m) b2
     WHERE mv.t_at > mv.st AND mv.en > mv.t_at AND mv.soc_at < mv.s1 AND b1.m >= 3 AND b2.m >= 3
  ), mom AS (
    SELECT xy.kind, count(*) AS n, count(DISTINCT xy.sid) AS sessions, sum(xy.w) AS sw,
           sum(xy.w * xy.x) / sum(xy.w) AS mx, sum(xy.w * xy.y) / sum(xy.w) AS my,
           sum(xy.w * xy.x * xy.x) / sum(xy.w) AS mxx, sum(xy.w * xy.x * xy.y) / sum(xy.w) AS mxy
      FROM xy GROUP BY xy.kind
  ), fit AS (
    SELECT mom.*, LEAST(GREATEST((mom.mxy - mom.mx * mom.my) / NULLIF(mom.mxx - mom.mx * mom.mx, 0), 0), 1) AS b FROM mom
  ), fit2 AS (
    SELECT fit.*, fit.my - fit.b * fit.mx AS a FROM fit
  ), res AS (
    SELECT fit2.kind, sqrt(sum(xy.w * (xy.y - fit2.a - fit2.b * xy.x) ^ 2) / sum(xy.w)) AS s,
           sqrt(sum(xy.w * (xy.y - fit2.my) ^ 2) / sum(xy.w)) AS s0
      FROM xy JOIN fit2 USING (kind) GROUP BY fit2.kind
  )
  SELECT COALESCE(jsonb_object_agg(fit2.kind, jsonb_build_object(
           'a', round(fit2.a::numeric, 4), 'b', round(COALESCE(fit2.b, 0)::numeric, 4), 's', round(res.s::numeric, 4),
           's_without', round(res.s0::numeric, 4), 'n', fit2.n, 'sessions', fit2.sessions, 'min_frac', 0.15,
           'cuts', jsonb_build_array(0.25, 0.5, 0.75))), '{}'::jsonb)
    INTO v_sess
    FROM fit2 JOIN res USING (kind)
   WHERE fit2.n >= 30;

  RETURN v_p || jsonb_build_object(
    'session', v_sess,
    'base', 'ottoq_charge_minutes_estimate', 'bands', jsonb_build_array(45, 70, 85),
    'half_life_days', v_h, 'window_days', round((extract(epoch FROM (v_through - v_from)) / 86400.0)::numeric, 2),
    'population', v_pop, 'min_cell_n', c_min_cell, 'min_cell_n_eff', c_min_neff, 'k_floor', c_k_floor,
    'stopped_reason', 'completed', 'fine_tick_max_min', 1,
    'diagnostics', jsonb_build_object('n', v_n, 'runs', v_runs, 'rms_ladder', v_ladder, 'within_sd', v_within))
    || CASE WHEN v_reg = '{}'::jsonb THEN '{}'::jsonb ELSE jsonb_build_object('regimes', v_reg) END;   -- 0625
END $fn$;

CREATE OR REPLACE FUNCTION public.ottoq_charge_time_v2_params(p_depot uuid, p_through timestamptz DEFAULT NULL,
                                                   p_window interval DEFAULT interval '21 days',
                                                   p_half_life_days numeric DEFAULT 3)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0625: the params of a charge_time_v2 fit for a depot from its completed charges recorded in (through - window,
  -- through] (0622's, computed by ottoq_charge_time_v2_params_cut), with each kind's evidence cut where
  -- ottoq_evidence_regimes records a change in its world inside the window. With none recorded there, 0622's params,
  -- key for key. Read-only; deterministic for a given ledger, record and through.
  SELECT public.ottoq_charge_time_v2_params_cut(
           p_depot, p_through, p_window, p_half_life_days,
           public.ottoq_evidence_regime_cuts('charge_time_v2', p_depot,
                                             COALESCE(p_through, now()) - COALESCE(p_window, interval '21 days'),
                                             COALESCE(p_through, now())))
$fn$;

CREATE OR REPLACE FUNCTION public.ottoq_fit_charge_time_v2(p_depot uuid, p_through timestamptz DEFAULT NULL,
                                                p_window interval DEFAULT interval '21 days',
                                                p_half_life_days numeric DEFAULT 3, p_note text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
/* 0622: fit charge_time_v2 for a depot (ottoq_charge_time_v2_params) and append it to ottoq_charge_clock_fits; returns
   its fit_id. Usable when both kinds have a usable pooled cell. 0625: its code md5 covers the cuts the fit reads and
   the function that applies them. */
DECLARE
  v_through timestamptz := COALESCE(p_through, now());
  v_window  interval := COALESCE(p_window, interval '21 days');
  v_p       jsonb;
  v_id      bigint;
BEGIN
  v_p := public.ottoq_charge_time_v2_params(p_depot, v_through, v_window, p_half_life_days);
  INSERT INTO public.ottoq_charge_clock_fits
    (depot_id, model, evidence_from, evidence_through, n_evidence, n_runs, usable, params, code_md5, note)
  VALUES (p_depot, 'charge_time_v2', v_through - v_window, v_through,
          COALESCE((v_p #>> '{diagnostics,n}')::int, 0), COALESCE((v_p #>> '{diagnostics,runs}')::int, 0),
          COALESCE((v_p #>> '{cells,dcfc:*,usable}')::boolean, false) AND COALESCE((v_p #>> '{cells,l2:*,usable}')::boolean, false),
          v_p,
          md5(pg_get_functiondef('public.ottoq_charge_time_v2_params(uuid,timestamp with time zone,interval,numeric)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_clock_who(uuid,text,text,text)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_minutes_estimate(numeric,numeric,numeric,numeric,numeric)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)'::regprocedure)
              || pg_get_functiondef('public.ottoq_evidence_regime_cuts(text,uuid,timestamp with time zone,timestamp with time zone)'::regprocedure)),
          p_note)
  RETURNING fit_id INTO v_id;
  RETURN v_id;
END $fn$;

-- ══ (c) the system looks for a change in its own evidence ══
CREATE FUNCTION public.ottoq_evidence_regime_scan(p_depot uuid, p_since timestamptz DEFAULT NULL,
                                                  p_model jsonb DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
SET timezone TO 'UTC'
AS $fn$
/* 0625: has the charge clock's world changed inside the evidence it learns from? For each kind of charger: the depot's
   completed fine-tick charges recorded since p_since (default: the clock's window back from now) and after the latest
   change already recorded for the kind in ottoq_evidence_regimes, each as its log ratio less the clock (p_model, default
   the depot's clock, without the run's evidence). The run is the unit, so that a run's weather and draw are not taken
   for a change: each run's mean per class from 3 or more of its charges (outside a run, the day's). For every split of
   those runs in the order they were recorded (3 or more on each side, per class): each class's shift, and its t on the
   pooled spread of the run means within the two sides (floor 0.02); their squares summed over the classes as q, on df
   classes. The best split is named a change when q >= 10 df and some class moved by 0.15 or more in log (about 16%).
   The splits within max(2 df + 2, 5% of q) of it bound when it happened (`window`), and the migrations applied in that
   window are listed, those that create or replace a function about charging marked: the likely causes, for a person.
   A finding, never a cut: a person records the change, and the clock learns from it that night (CLAUDE.md rule 10). */
DECLARE
  c_min_charges constant int := 3;
  c_min_runs    constant int := 3;
  c_sd_floor    constant float8 := 0.02;
  c_q_per_df    constant float8 := 10;
  c_min_shift   constant float8 := 0.15;
  v_m      jsonb;
  v_since  timestamptz;
  v_out    jsonb;
  v_kind   text;
  v_mig    jsonb;
BEGIN
  IF p_depot IS NULL THEN RAISE EXCEPTION 'ottoq_evidence_regime_scan: a depot is required'; END IF;
  v_m := COALESCE(p_model, public.ottoq_charge_clock_model(p_depot));
  v_since := COALESCE(p_since, now() - COALESCE((v_m #>> '{params,window_days}')::numeric, 21) * interval '1 day');
  WITH c AS (   -- per kind, where the scan starts: after the latest change already recorded for it
    SELECT k.kind, r.recorded, GREATEST(v_since, COALESCE(r.recorded, v_since)) AS t0
      FROM (VALUES ('dcfc'), ('l2')) k(kind)
      LEFT JOIN LATERAL (
        SELECT max(x.starts_at) AS recorded FROM public.ottoq_evidence_regimes x
         WHERE x.model = 'charge_time_v2' AND (x.depot_id IS NULL OR x.depot_id = p_depot)
           AND x.scope IN (k.kind, '*') AND x.starts_at <= now()) r ON true
  ), e AS MATERIALIZED (
    SELECT l.charger_type AS kind, l.recorded_at, w.j ->> 'cls' AS cls,
           COALESCE(l.sim_run_id::text, 'day ' || to_char(l.recorded_at, 'YYYY-MM-DD')) AS run,
           ln((l.duration_min / est.m)::float8)
             - (public.ottoq_charge_clock(v_m, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                          l.vehicle_kw, NULL) ->> 'f')::float8 AS r
      FROM c
      JOIN public.ottoq_charge_duration_ledger l ON l.charger_type = c.kind AND l.recorded_at > c.t0
      JOIN public.vehicles v ON v.id = l.vehicle_id
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                      l.vehicle_kw) AS m) est
     WHERE l.depot_id = p_depot AND l.recorded_at <= now() AND l.stopped_reason = 'completed'
       AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0
       AND l.tick_minutes IS NOT NULL AND l.tick_minutes <= 1
  ), rc AS (    -- each run's mean per kind and class
    SELECT e.kind, e.cls, e.run, count(*) AS n, avg(e.r) AS mr, min(e.recorded_at) AS t_first, max(e.recorded_at) AS t_last
      FROM e GROUP BY e.kind, e.cls, e.run HAVING count(*) >= c_min_charges
  ), rk AS (    -- the runs that count, in the order they were recorded
    SELECT x.kind, x.run, x.t_first, x.t_last, row_number() OVER (PARTITION BY x.kind ORDER BY x.t_first, x.run) AS o
      FROM (SELECT rc.kind, rc.run, min(rc.t_first) AS t_first, max(rc.t_last) AS t_last
              FROM rc GROUP BY rc.kind, rc.run) x
  ), ru AS (
    SELECT rc.*, rk.o FROM rc JOIN rk USING (kind, run)
  ), st AS (    -- every split (the runs before run s against run s on), per class: each side's runs, mean, sum of squares
    SELECT sp.kind, sp.o AS s, ru.cls,
           count(*) FILTER (WHERE ru.o < sp.o) AS kb, count(*) FILTER (WHERE ru.o >= sp.o) AS ka,
           avg(ru.mr) FILTER (WHERE ru.o < sp.o) AS mb, avg(ru.mr) FILTER (WHERE ru.o >= sp.o) AS ma,
           sum(ru.mr * ru.mr) FILTER (WHERE ru.o < sp.o) AS qb, sum(ru.mr * ru.mr) FILTER (WHERE ru.o >= sp.o) AS qa
      FROM rk sp JOIN ru ON ru.kind = sp.kind
     WHERE sp.o > 1
     GROUP BY sp.kind, sp.o, ru.cls
  ), tq AS (    -- the class's shift, and its t on the pooled spread of run means within the two sides
    SELECT st.*, st.ma - st.mb AS shift,
           (st.ma - st.mb)
             / (GREATEST(sqrt(GREATEST(st.qb - st.kb * st.mb * st.mb + st.qa - st.ka * st.ma * st.ma, 0)
                              / (st.kb + st.ka - 2)), c_sd_floor) * sqrt(1.0 / st.kb + 1.0 / st.ka)) AS t
      FROM st WHERE st.kb >= c_min_runs AND st.ka >= c_min_runs
  ), q AS (
    SELECT tq.kind, tq.s, sum(tq.t * tq.t) AS q, count(*) AS df, max(abs(tq.shift)) AS max_shift
      FROM tq GROUP BY tq.kind, tq.s
  ), best AS (
    SELECT DISTINCT ON (q.kind) q.* FROM q ORDER BY q.kind, q.q DESC, q.s
  ), near AS (  -- the splits nearly as good as the best: when it happened is bounded by them
    SELECT q.kind, min(q.s) AS s_lo, max(q.s) AS s_hi
      FROM q JOIN best b USING (kind)
     WHERE q.q >= b.q - GREATEST(2 * b.df + 2, 0.05 * b.q)
     GROUP BY q.kind
  )
  SELECT jsonb_object_agg(c.kind, jsonb_build_object(
           'since', c.t0, 'recorded', c.recorded,
           'charges', (SELECT count(*) FROM e WHERE e.kind = c.kind),
           'runs', (SELECT count(*) FROM rk WHERE rk.kind = c.kind),
           'named', COALESCE(b.q >= c_q_per_df * b.df AND b.max_shift >= c_min_shift, false),
           'split', CASE WHEN b.kind IS NULL THEN NULL ELSE jsonb_build_object(
             'q', round(b.q::numeric, 1), 'df', b.df, 'max_shift', round(b.max_shift::numeric, 3),
             'last_run_before', (SELECT r.run FROM rk r WHERE r.kind = c.kind AND r.o = b.s - 1),
             'first_run_after', (SELECT r.run FROM rk r WHERE r.kind = c.kind AND r.o = b.s),
             'between', jsonb_build_array((SELECT max(r.t_last) FROM rk r WHERE r.kind = c.kind AND r.o < b.s),
                                          (SELECT r.t_first FROM rk r WHERE r.kind = c.kind AND r.o = b.s)),
             'window', jsonb_build_array((SELECT max(r.t_last) FROM rk r WHERE r.kind = c.kind AND r.o < n.s_lo),
                                         (SELECT r.t_first FROM rk r WHERE r.kind = c.kind AND r.o = n.s_hi)),
             'classes', (SELECT jsonb_object_agg(tq.cls, jsonb_build_object(
                                  'shift', round(tq.shift::numeric, 3), 't', round(tq.t::numeric, 1),
                                  'before', round(tq.mb::numeric, 3), 'after', round(tq.ma::numeric, 3),
                                  'runs_before', tq.kb, 'runs_after', tq.ka))
                           FROM tq WHERE tq.kind = c.kind AND tq.s = b.s)) END))
    INTO v_out
    FROM c LEFT JOIN best b USING (kind) LEFT JOIN near n USING (kind);

  -- the migrations applied in each window, where the database keeps them
  IF to_regclass('supabase_migrations.schema_migrations') IS NOT NULL THEN
    FOR v_kind IN SELECT k.key FROM jsonb_each(v_out) k WHERE jsonb_typeof(k.value #> '{split,window}') = 'array' LOOP
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'version', sm.version, 'name', sm.name,
               'charging', COALESCE(array_to_string(sm.statements, ' ') ~* '(create|replace)\s+function\s+[a-z_."]*charg', false))
               ORDER BY sm.version), '[]'::jsonb)
        INTO v_mig
        FROM supabase_migrations.schema_migrations sm
       WHERE sm.version > to_char((v_out #>> ARRAY[v_kind, 'split', 'window', '0'])::timestamptz, 'YYYYMMDDHH24MISS')
         AND sm.version <= to_char((v_out #>> ARRAY[v_kind, 'split', 'window', '1'])::timestamptz, 'YYYYMMDDHH24MISS');
      v_out := jsonb_set(v_out, ARRAY[v_kind, 'split', 'migrations'], v_mig);
    END LOOP;
  END IF;
  RETURN jsonb_build_object(
    'model', jsonb_build_object('estimate_id', v_m -> 'estimate_id', 'model', v_m -> 'model', 'fitted_at', v_m -> 'fitted_at'),
    'since', v_since, 'at', now(), 'by_kind', v_out,
    'rule', jsonb_build_object('min_charges_per_run', c_min_charges, 'min_runs_each_side', c_min_runs,
                               'sd_floor', c_sd_floor, 'q_per_df', c_q_per_df, 'min_shift', c_min_shift));
END $fn$;

-- ══ (d) what a cut would have bought ══
CREATE FUNCTION public.ottoq_charge_clock_trial(p_depot uuid, p_runs uuid[], p_through timestamptz,
                                                p_cuts_a jsonb, p_cuts_b jsonb, p_with_params boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
SET timezone TO 'UTC'
AS $fn$
/* 0625: what a cut in the clock's evidence would have bought, out of sample. The clock fitted through p_through
   (default: the earliest start of the runs; a 21-day window and a 3-day half-life, as nightly) under cuts A and under
   cuts B (ottoq_charge_time_v2_params_cut), each scored on the runs' completed charges recorded after p_through, timed
   as the check times them (the run's own evidence up to each charge's start): per kind, the charges, and each fit's
   mean absolute log error and mean log error. An engineering instrument; production never calls it, and it writes
   nothing. */
DECLARE
  v_through timestamptz;
  v_a       jsonb;
  v_b       jsonb;
  v_res     jsonb;
BEGIN
  v_through := COALESCE(p_through, (SELECT min(r.started_at) FROM public.ottoq_sim_runs r WHERE r.sim_run_id = ANY (p_runs)));
  IF p_depot IS NULL OR v_through IS NULL THEN
    RAISE EXCEPTION 'ottoq_charge_clock_trial: a depot, and a time or runs that started, are required';
  END IF;
  v_a := jsonb_build_object('params', public.ottoq_charge_time_v2_params_cut(p_depot, v_through, interval '21 days', 3,
                                                                            COALESCE(p_cuts_a, '{}'::jsonb)));
  v_b := jsonb_build_object('params', public.ottoq_charge_time_v2_params_cut(p_depot, v_through, interval '21 days', 3,
                                                                            COALESCE(p_cuts_b, '{}'::jsonb)));
  WITH e AS (
    SELECT l.charger_type AS kind, ln((l.duration_min / est.m)::numeric) AS lr,
           (public.ottoq_charge_clock(v_a, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                      l.vehicle_kw,
                                      public.ottoq_charge_clock_run_evidence(v_a, l.sim_run_id, l.started_at) -> l.charger_type)
              ->> 'f')::numeric AS fa,
           (public.ottoq_charge_clock(v_b, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                      l.vehicle_kw,
                                      public.ottoq_charge_clock_run_evidence(v_b, l.sim_run_id, l.started_at) -> l.charger_type)
              ->> 'f')::numeric AS fb
      FROM public.ottoq_charge_duration_ledger l
      JOIN public.vehicles v ON v.id = l.vehicle_id
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                      l.vehicle_kw) AS m) est
     WHERE l.sim_run_id = ANY (p_runs) AND l.depot_id = p_depot AND l.recorded_at > v_through
       AND l.stopped_reason = 'completed' AND l.charger_type IN ('dcfc', 'l2') AND l.duration_min > 0
       AND l.soc_end > l.soc_start AND est.m > 0
  )
  SELECT jsonb_build_object(
           'through', v_through, 'runs', to_jsonb(p_runs),
           'cuts_a', COALESCE(p_cuts_a, '{}'::jsonb), 'cuts_b', COALESCE(p_cuts_b, '{}'::jsonb),
           'regimes_a', v_a #> '{params,regimes}', 'regimes_b', v_b #> '{params,regimes}',
           'by_kind', COALESCE((SELECT jsonb_object_agg(x.kind, jsonb_build_object(
                                  'charges', x.n, 'mae_a', round(x.mae_a, 4), 'mae_b', round(x.mae_b, 4),
                                  'bias_a', round(x.bias_a, 4), 'bias_b', round(x.bias_b, 4)))
                                FROM (SELECT e.kind, count(*) AS n, avg(abs(e.lr - e.fa)) AS mae_a,
                                             avg(abs(e.lr - e.fb)) AS mae_b, avg(e.lr - e.fa) AS bias_a,
                                             avg(e.lr - e.fb) AS bias_b
                                        FROM e GROUP BY e.kind) x), '{}'::jsonb))
         || CASE WHEN p_with_params THEN jsonb_build_object('params_a', v_a -> 'params', 'params_b', v_b -> 'params')
                 ELSE '{}'::jsonb END
    INTO v_res;
  RETURN v_res;
END $fn$;

-- ══ who may call what: the record's reader and the scan as the audit is (0622); a fit and the trial the service only ══
GRANT EXECUTE ON FUNCTION public.ottoq_evidence_regime_cuts(text, uuid, timestamptz, timestamptz) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_evidence_regime_scan(uuid, timestamptz, jsonb) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.ottoq_charge_time_v2_params_cut(uuid, timestamptz, interval, numeric, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_charge_clock_trial(uuid, uuid[], timestamptz, jsonb, jsonb, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_time_v2_params_cut(uuid, timestamptz, interval, numeric, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_clock_trial(uuid, uuid[], timestamptz, jsonb, jsonb, boolean) TO service_role;

-- ══ V0: the scan finds 0573 by itself, before anything is recorded ══
DO $v0$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_t0 timestamptz := clock_timestamp();
  v_s  jsonb;
  v_d  jsonb;
  v_l  jsonb;
  v_ms int;
BEGIN
  v_s := public.ottoq_evidence_regime_scan(c_depot, '2026-09-17 00:00:00+00'::timestamptz, NULL);
  v_ms := round(extract(epoch FROM clock_timestamp() - v_t0) * 1000);
  v_d := v_s #> '{by_kind,dcfc}';
  v_l := v_s #> '{by_kind,l2}';
  IF COALESCE((v_d ->> 'charges')::int, 0) < 500 THEN
    RAISE NOTICE '0625 V0: the twin depot has % fast charges to scan; the scan is executed by the tests', v_d ->> 'charges';
    RETURN;
  END IF;
  RAISE NOTICE '0625 V0 (% ms, clock %): fast chargers % charges, % runs, named %, q % on % classes, largest shift %, between % and %, window % to %; classes %',
    v_ms, v_s #>> '{model,estimate_id}', v_d ->> 'charges', v_d ->> 'runs', v_d ->> 'named', v_d #>> '{split,q}',
    v_d #>> '{split,df}', v_d #>> '{split,max_shift}', v_d #>> '{split,between,0}', v_d #>> '{split,between,1}',
    v_d #>> '{split,window,0}', v_d #>> '{split,window,1}', v_d #> '{split,classes}';
  RAISE NOTICE '0625 V0: the migrations in that window that redefine a charging function: %; all: %',
    (SELECT string_agg(m ->> 'version' || ' ' || (m ->> 'name'), ', ') FROM jsonb_array_elements(v_d #> '{split,migrations}') m
      WHERE (m ->> 'charging')::boolean),
    jsonb_array_length(COALESCE(v_d #> '{split,migrations}', '[]'::jsonb));
  RAISE NOTICE '0625 V0: L2 % charges, % runs, named %, q % on % classes, largest shift %',
    v_l ->> 'charges', v_l ->> 'runs', v_l ->> 'named', v_l #>> '{split,q}', v_l #>> '{split,df}', v_l #>> '{split,max_shift}';
  IF NOT (v_d ->> 'named')::boolean
     OR NOT ('2026-09-30 11:53:08+00'::timestamptz BETWEEN (v_d #>> '{split,window,0}')::timestamptz
                                                       AND (v_d #>> '{split,window,1}')::timestamptz)
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v_d #> '{split,migrations}', '[]'::jsonb)) m
                     WHERE m ->> 'version' = '20260930115308' AND (m ->> 'charging')::boolean)
     OR (v_l ->> 'named')::boolean THEN
    RAISE EXCEPTION '0625 V0: the scan does not find 0573 by itself (fast chargers named %, window % to %; L2 named %)',
      v_d ->> 'named', v_d #>> '{split,window,0}', v_d #>> '{split,window,1}', v_l ->> 'named';
  END IF;
END $v0$;

-- ══ the record: 0573, for fast charges at the twin depot ══
INSERT INTO public.ottoq_evidence_regimes (model, scope, depot_id, starts_at, reason, source)
VALUES ('charge_time_v2', 'dcfc', '11111111-1111-1111-1111-111111111111', '2026-09-30 11:53:08+00',
        '0573 rebuilt the twin''s fast-charge physics: each battery''s DC acceptance curve (the Tesla Model Y''s measured, '
        'the Jaguar I-PACE''s fitted to its published times, the median of 99 measured curves for every other car) and two '
        'cars'' facts (the I-PACE to 84.7 kWh and 104 kW, the Zoox to 133 kWh and 100 kW). Fast charges before it ran on '
        'the old shape and facts: against the clock, Zoox 1.14, Waymo 0.21 and Tesla -0.09 in log above the charges since. '
        'Its L2 branch was not touched, and 19.2 kW is every car''s limit on L2.',
        'migration 0573 (20260930115308); found by ottoq_evidence_regime_scan (0625 V0); recorded by 0625');

-- ══ the trial V1 and V2 read: through d9d49732's start, no cuts against the fast-charge cut ══
DO $trial$
DECLARE
  c_run   constant uuid := 'd9d49732-cf28-42c3-aac9-9c3f606a2c92';
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_start timestamptz;
  v_runs  uuid[];
  v_t0    timestamptz := clock_timestamp();
BEGIN
  SELECT started_at INTO v_start FROM public.ottoq_sim_runs WHERE sim_run_id = c_run AND status = 'completed';
  IF v_start IS NULL THEN RETURN; END IF;
  v_runs := ARRAY(SELECT r.sim_run_id FROM public.ottoq_sim_runs r
                   WHERE r.depot_id = c_depot AND r.status = 'completed'
                     AND (r.sim_run_id = c_run OR r.sim_run_id::text LIKE 'baf29c05%')
                   ORDER BY r.started_at);
  INSERT INTO v0625_trial
  SELECT public.ottoq_charge_clock_trial(c_depot, v_runs, v_start, '{}'::jsonb,
                                         jsonb_build_object('dcfc', '2026-09-30 11:53:08+00'::timestamptz), true)
         || jsonb_build_object('ms', round(extract(epoch FROM clock_timestamp() - v_t0) * 1000));
END $trial$;

-- ══ V1: with no cut inside the window, 0622's params; with the fast-charge cut, every L2 key unchanged ══
DO $v1$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_t   jsonb := (SELECT j FROM v0625_trial);
  v_old jsonb := (SELECT j FROM v0625_before WHERE what = 'd9d49732');
  v_a   jsonb;
  v_b   jsonb;
  v_bad text[] := '{}';
  k     text;
BEGIN
  -- (a) the record read, nothing inside the window: through a moment before 0573, over 2 days
  IF public.ottoq_charge_time_v2_params(c_depot, '2026-09-30 11:53:00+00'::timestamptz, interval '2 days', 3)
     IS DISTINCT FROM (SELECT j FROM v0625_before WHERE what = 'pre_boundary') THEN
    RAISE EXCEPTION '0625 V1(a): through 2026-09-30 11:53:00 over 2 days the params are not 0622''s';
  END IF;
  IF v_t IS NULL THEN
    RAISE NOTICE '0625 V1(a): through 2026-09-30 11:53:00 over 2 days, 0622''s params key for key; run d9d49732 is not here, so (b) and (c) are executed by the tests';
    RETURN;
  END IF;
  v_a := v_t -> 'params_a';
  v_b := v_t -> 'params_b';
  -- (b) through d9d49732's start with no cuts: 0622's params, key for key
  IF v_a IS DISTINCT FROM v_old THEN
    RAISE EXCEPTION '0625 V1(b): through d9d49732''s start with no cuts the params are not 0622''s (keys that differ: %)',
      (SELECT string_agg(x.key, ', ') FROM jsonb_each(v_a) x WHERE x.value IS DISTINCT FROM v_old -> x.key);
  END IF;
  -- (c) with the fast-charge cut: every L2 key as it was, and the cut applied to fast charges alone
  FOREACH k IN ARRAY ARRAY['cells', 'class_cells', 'model_cells', 'vehicle_cells'] LOOP
    IF (SELECT jsonb_object_agg(x.key, x.value) FROM jsonb_each(v_b -> k) x WHERE x.key LIKE 'l2%')
       IS DISTINCT FROM (SELECT jsonb_object_agg(x.key, x.value) FROM jsonb_each(v_a -> k) x WHERE x.key LIKE 'l2%') THEN
      v_bad := v_bad || k;
    END IF;
  END LOOP;
  FOREACH k IN ARRAY ARRAY['icc', 'run', 'session', 'population'] LOOP
    IF (v_b #> ARRAY[k, 'l2']) IS DISTINCT FROM (v_a #> ARRAY[k, 'l2']) THEN v_bad := v_bad || k; END IF;
  END LOOP;
  IF (SELECT jsonb_object_agg(x.key, x.value) FROM jsonb_each(v_b #> '{diagnostics,within_sd}') x WHERE x.key LIKE 'l2%')
     IS DISTINCT FROM (SELECT jsonb_object_agg(x.key, x.value) FROM jsonb_each(v_a #> '{diagnostics,within_sd}') x WHERE x.key LIKE 'l2%')
     OR (SELECT jsonb_object_agg(x.key, x.value -> 'l2') FROM jsonb_each(v_b #> '{diagnostics,rms_ladder}') x)
        IS DISTINCT FROM (SELECT jsonb_object_agg(x.key, x.value -> 'l2') FROM jsonb_each(v_a #> '{diagnostics,rms_ladder}') x) THEN
    v_bad := v_bad || 'diagnostics'::text;
  END IF;
  IF (v_b - ARRAY['cells', 'class_cells', 'model_cells', 'vehicle_cells', 'icc', 'run', 'session', 'population',
                  'diagnostics', 'regimes'])
     IS DISTINCT FROM (v_a - ARRAY['cells', 'class_cells', 'model_cells', 'vehicle_cells', 'icc', 'run', 'session',
                                   'population', 'diagnostics']) THEN
    v_bad := v_bad || 'the rest'::text;
  END IF;
  IF cardinality(v_bad) > 0 THEN
    RAISE EXCEPTION '0625 V1(c): with the fast-charge cut these L2 parts changed: %', array_to_string(v_bad, ', ');
  END IF;
  IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(COALESCE(v_b -> 'regimes', '{}'::jsonb)) x) IS DISTINCT FROM ARRAY['dcfc']
     OR NOT (v_b #>> '{regimes,dcfc,applied}')::boolean
     OR (v_b #>> '{regimes,dcfc,n_after}')::int IS DISTINCT FROM (v_b #>> '{cells,dcfc:*,n}')::int
     OR (v_b #>> '{cells,dcfc:*,n}')::int >= (v_a #>> '{cells,dcfc:*,n}')::int
     OR v_a ? 'regimes' THEN
    RAISE EXCEPTION '0625 V1(c): the cut is not what it should be: regimes %, fast-charge pooled n % against % uncut',
      v_b -> 'regimes', v_b #>> '{cells,dcfc:*,n}', v_a #>> '{cells,dcfc:*,n}';
  END IF;
  RAISE NOTICE '0625 V1: 0622''s params key for key through 2026-09-30 11:53:00 (2 days, the record read) and through d9d49732''s start (21 days, no cuts); with the fast-charge cut every L2 key unchanged and regimes %',
    v_b -> 'regimes';
  RAISE NOTICE '0625 V1 fast chargers, uncut -> cut: pooled n % -> %, factor % -> %; class offsets % -> %; run tau % -> %; car across runs % -> %, in run % -> %',
    v_a #>> '{cells,dcfc:*,n}', v_b #>> '{cells,dcfc:*,n}', v_a #>> '{cells,dcfc:*,factor}', v_b #>> '{cells,dcfc:*,factor}',
    (SELECT jsonb_object_agg(split_part(x.key, '|', 2), x.value -> 'off') FROM jsonb_each(v_a -> 'class_cells') x WHERE x.key ~ '^dcfc\|[^|]+$'),
    (SELECT jsonb_object_agg(split_part(x.key, '|', 2), x.value -> 'off') FROM jsonb_each(v_b -> 'class_cells') x WHERE x.key ~ '^dcfc\|[^|]+$'),
    v_a #>> '{run,dcfc,tau}', v_b #>> '{run,dcfc,tau}', v_a #>> '{icc,dcfc,vehicle}', v_b #>> '{icc,dcfc,vehicle}',
    v_a #>> '{icc,dcfc,in_run}', v_b #>> '{icc,dcfc,in_run}';
END $v1$;

-- ══ V2: THE GATE ══
DO $v2$
DECLARE
  v_t jsonb := (SELECT j FROM v0625_trial);
  v_d jsonb;
  v_l jsonb;
BEGIN
  IF v_t IS NULL THEN
    RAISE NOTICE '0625 V2: run d9d49732 is not here; the trial is executed by the tests';
    RETURN;
  END IF;
  v_d := v_t #> '{by_kind,dcfc}';
  v_l := v_t #> '{by_kind,l2}';
  RAISE NOTICE '0625 V2 (% ms, through %, runs %): fast chargers % charges, mean absolute log error % -> %, bias % -> %; L2 % charges, % -> %, bias % -> %',
    v_t ->> 'ms', v_t ->> 'through', v_t -> 'runs', v_d ->> 'charges', v_d ->> 'mae_a', v_d ->> 'mae_b', v_d ->> 'bias_a',
    v_d ->> 'bias_b', v_l ->> 'charges', v_l ->> 'mae_a', v_l ->> 'mae_b', v_l ->> 'bias_a', v_l ->> 'bias_b';
  IF COALESCE((v_d ->> 'charges')::int, 0) < 30
     OR (v_d ->> 'mae_b')::numeric > 0.9 * (v_d ->> 'mae_a')::numeric
     OR abs((v_d ->> 'bias_b')::numeric) > abs((v_d ->> 'bias_a')::numeric) + 0.02
     OR (v_l ->> 'mae_b') IS DISTINCT FROM (v_l ->> 'mae_a') OR (v_l ->> 'bias_b') IS DISTINCT FROM (v_l ->> 'bias_a') THEN
    RAISE EXCEPTION '0625 V2: the cut does not earn its place out of sample (fast chargers % charges, % -> %, bias % -> %; L2 % -> %): not applied',
      v_d ->> 'charges', v_d ->> 'mae_a', v_d ->> 'mae_b', v_d ->> 'bias_a', v_d ->> 'bias_b', v_l ->> 'mae_a', v_l ->> 'mae_b';
  END IF;
END $v2$;

-- ══ the fit at apply: the clock learns from the record now, not at 11:22 UTC ══
SELECT public.ottoq_fit_charge_time_v2('11111111-1111-1111-1111-111111111111'::uuid, now(), interval '21 days', 3,
                                       '0625: the first fit to honour a recorded change (0573, fast charges)');

-- ══ V3: the fit at apply honours the record and is the depot's clock; after the record the scan finds nothing more ══
DO $v3$
DECLARE
  c_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_f  record;
  v_m  jsonb := public.ottoq_charge_clock_model(c_depot);
  v_s  jsonb;
  v_t0 timestamptz;
BEGIN
  SELECT * INTO v_f FROM public.ottoq_charge_clock_fits WHERE depot_id = c_depot ORDER BY fit_id DESC LIMIT 1;
  IF v_f.note IS DISTINCT FROM '0625: the first fit to honour a recorded change (0573, fast charges)' THEN
    RAISE EXCEPTION '0625 V3: the fit at apply was not written';
  END IF;
  IF NOT v_f.usable THEN
    RAISE NOTICE '0625 V3: the fit at apply (%) is not usable here (% charges); the depot keeps its clock', v_f.fit_id, v_f.n_evidence;
    RETURN;
  END IF;
  IF (v_m ->> 'estimate_id')::bigint IS DISTINCT FROM v_f.fit_id
     OR (v_f.params #> '{regimes,dcfc,starts_at}') IS DISTINCT FROM to_jsonb('2026-09-30T11:53:08+00:00'::text)
     OR NOT (v_f.params #>> '{regimes,dcfc,applied}')::boolean OR v_f.params #> '{regimes,l2}' IS NOT NULL THEN
    RAISE EXCEPTION '0625 V3: the fit at apply (%) is not the depot''s clock or does not honour the record: %',
      v_f.fit_id, v_f.params -> 'regimes';
  END IF;
  v_t0 := clock_timestamp();
  v_s := public.ottoq_evidence_regime_scan(c_depot, NULL, NULL);
  RAISE NOTICE '0625 V3: fit % usable, the depot''s clock, regimes %; fast-charge class offsets %; run tau %, car across runs %; after the record the scan (% ms) on fast chargers since %: % charges, % runs, named %, q %, largest shift %; on L2 named %, q %, largest shift %',
    v_f.fit_id, v_f.params -> 'regimes',
    (SELECT jsonb_object_agg(split_part(x.key, '|', 2), x.value -> 'off') FROM jsonb_each(v_f.params -> 'class_cells') x WHERE x.key ~ '^dcfc\|[^|]+$'),
    v_f.params #>> '{run,dcfc,tau}', v_f.params #>> '{icc,dcfc,vehicle}',
    round(extract(epoch FROM clock_timestamp() - v_t0) * 1000), v_s #>> '{by_kind,dcfc,since}', v_s #>> '{by_kind,dcfc,charges}',
    v_s #>> '{by_kind,dcfc,runs}', v_s #>> '{by_kind,dcfc,named}', v_s #>> '{by_kind,dcfc,split,q}',
    v_s #>> '{by_kind,dcfc,split,max_shift}', v_s #>> '{by_kind,l2,named}', v_s #>> '{by_kind,l2,split,q}',
    v_s #>> '{by_kind,l2,split,max_shift}';
  IF (v_s #>> '{by_kind,dcfc,named}')::boolean
     OR (v_s #>> '{by_kind,dcfc,since}')::timestamptz IS DISTINCT FROM '2026-09-30 11:53:08+00'::timestamptz THEN
    RAISE EXCEPTION '0625 V3: after the record the scan still names a change on fast chargers, or does not start at it: %',
      v_s #> '{by_kind,dcfc}';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0625_a_learned_model_knows_when_its_world_changed', false, false,
  'The charge clock''s fit (charge_time_v2) learns a kind of charger from the charges recorded after the latest change in '
  'its world recorded in ottoq_evidence_regimes (seeded with 0573 for fast charges at the twin depot), once those carry '
  'it alone; ottoq_evidence_regime_scan names candidate changes in the clock''s own evidence for a person, and '
  'ottoq_charge_clock_trial measures a cut out of sample. With nothing recorded inside its window every fit is 0622''s '
  '(V1). FALSE/FALSE: the tick path is untouched and the clock is read by the charge-order check, board and grader on '
  'operator_demo runs (0615) and the nightly assessment.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
