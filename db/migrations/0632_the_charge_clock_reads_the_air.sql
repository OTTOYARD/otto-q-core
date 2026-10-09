-- migration-version: PENDING
-- migration-name:    the_charge_clock_reads_the_air
--
-- 0632  **The charge clock reads the air.**
--       The clock that times every charge for the kernel's check (0622) learned a run's level only from that run's own
--       charges, so a run's first charges were timed as if every day were the same. The twin's chargers run slower in
--       heat, and on a hot day the check's first hour was timed against a mild one. 0632 gives the clock a level for the
--       depot's air at each charge's start. Each nightly fit learns the level from its own evidence, in whichever shape
--       predicts each run best from the others: no level, one slope, or a slope that bends once. The clock reads the air
--       through the run's evidence, so every reader of it (the check, its futures, the agent's board, the grader's
--       replay) reads the air without being changed.
--
-- ══ §1 WHY (measured 2026-10-09 05:40-06:30 UTC, 12:40-1:30 AM CT) ═══════════════════════════════════════════════════════
--
--   (a) The self-review named it among the four open areas it first ranked (0626, G360-G364): "The charge clock does
--       not see the air temperature", on 15% of what made the check wrong. Its audit put the air at 41% of what the
--       clock leaves across runs on fast chargers and 28% on L2.
--   (b) The physics it misses. The twin times a charge at the battery's temperature: the depot's air at the session's
--       start, plus 5, plus up to 8 by the car, plus half a degree per minute of charging up to 15
--       (twin.ottoq_sim_advance_charge_sessions); above 35 °C the rate falls 2% per degree (ottoq_sim_compute_charge_rate).
--       So the effect is convex in the air: little on a cool day, steep on a hot one. On fit 3's own residuals, by
--       air at the charge's start (fine ticks, fast charges after 0573's change): 10-15 °C -0.072, 15-19 -0.049, 20-24
--       +0.025, 25-30 +0.130, 30.6 +0.283 in log; L2 -0.042, -0.010, +0.071, +0.185, +0.212.
--   (c) What a level buys, out of sample, read-only on live with a prototype (fit 3's levels, an air level fitted on
--       the 21 days before each run, the run's offset learned as the check learns it): over the 11 runs since 10-01 with
--       15 or more fast charges, mean absolute log error 0.0833 -> 0.0793 on 563 fast charges, and 0.0905 -> 0.0840 on
--       747 L2 charges over 12 runs. The hot runs carry it: b2efcc07 (26 °C) L2 0.1625 -> 0.1133 with its bias +0.110
--       -> +0.020, cde5a21c (26 °C) fast 0.1413 -> 0.1085 and L2 0.1379 -> 0.1043. Mild runs are near even.
--   (d) And where it hurts. A slope learned from too few runs extrapolates: on two early runs (10-02, two days after
--       0573's change had cut the fast-charge evidence to a few runs) a straight line made fast charges worse (0.0955
--       -> 0.1236 on 512404f7). And a bend placed where one side holds no run is collinear with the slope: a bend at
--       14 °C on evidence that started at 15 °C sent one prototype's error to 0.1235. So the shape is chosen by leaving
--       each run out in turn, a bend sits only where a tenth of the weight and three runs lie on each side, a level is
--       kept only from six runs and when it beats no level by 1% out of sample, and the air is held at the edge of what
--       the fit saw.
--   (e) The run's offset (0622) keeps learning a run's own level from its charges, now on what the air leaves; its
--       prior strength is fitted on that too, so it is not counted twice. In the prototype a level with fit 3's
--       strength did worse than the level alone on both kinds; refitted on what the air leaves, it is the run's
--       remainder.
--   (f) Rehearsed read-only on live with this file's own fit of the air (on fit 3's window, its class levels): fast
--       charges bend at 19 °C (+0.2% a degree below it, +2.1% above; 647 charges, 17 runs, 10.2-30.8 °C) and L2 at
--       20 °C (+0.8%, +2.3%; 1,917 charges, 37 runs), each run left out in turn reading 5.5% and 13.7% less squared
--       error than no level. A bend beat a straight line on both, as the physics says it should.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_charge_clock_evidence carries each charge's air (the ledger's depot_air_c), a new last attribute.
--   (b) ottoq_charge_time_v2_params_cut fits `air` per kind after the class levels: from the charges that carry the air,
--       no level, a slope, or a slope with one bend at a whole degree, chosen by each run's weighted squared error on the
--       fit to the other runs (outside a run, the day's charges are the unit). The level is centred on the evidence, so
--       it moves the clock with the air and leaves its centre where the levels above put it. Kept (usable) from six runs
--       and when it beats no level by 1%. What the level leaves is what the run, the car and the charge in progress are
--       fitted on; the ladder gains `after_air`. A cut set may carry {"air": false} (0625's trial): the fit without it,
--       0625's params key for key.
--   (c) public.ottoq_charge_clock_air(level, air): the level at an air temperature, the air held at the edge of what
--       the fit saw. The fit and the clock both read it here. public.ottoq_solve_sym3: the fit's 3x3 solve.
--   (d) ottoq_charge_clock adds the level when p_run carries air_c (lvl '+air', and the level as `air`); past the edge
--       of the air the fit saw, the spread widens by the level's steepest slope for every degree beyond.
--   (e) ottoq_charge_clock_run_evidence takes each charge's residual at its own air, and puts the depot's air at the
--       moment (public.ottoq_depot_air_c: what the charge ledger records, the run's weather, NULL when not known) as
--       air_c in each kind's block the model has a usable level for, with n 0 before the run's first charge of the
--       kind. On a model without an air level, 0622's evidence key for key.
--   (f) The audit within runs (0626) and the scan for a change in the clock's world (0625) read each charge at its own
--       air, so what they find is what the level leaves. The trial reports each arm's air level.
--   (g) The self-review: orders timed by a clock without the air, graded after the clock was given one, are history
--       (status built, as for a change in the clock's world, 0625); the air area says what the clock reads, or, if what
--       it leaves still moves with the air, that it reads the air and still misses it.
--   (h) The fit's code md5 covers the level and its solve. The twin depot's clock is refitted here, so every reader
--       reads the air from this apply on.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight, no run running, no fit running. P1 the eight bodies are the ones measured (the self-review's
--   after 0630), the type's attributes are the ones measured, the four objects are new. V1 the level and the solve by
--   arithmetic; the clock with a planted level, in range and beyond; each patch by meaning. V2 on the clock as it stood
--   (fit 3, no air level): the clock and the run's evidence read exactly as before, with and without the air.
--   V3 the fit with {"air": false} is 0625's fit key for key on a day's window (computed before the type changed).
--   V4 the refit: its air level per kind, its out-of-sample choice, the ladder, the run's prior strength before and
--   after. V5 the clock reads the air on the hottest recent run. V6 the audit and the self-review read it. Executed by
--   tests/test_agent_air_clock_sql.py on the miniature depot with a planted fleet whose charges slow above a bend (fast
--   charges at 22 °C, L2 at 18 °C).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE, as 0622 and 0625: the charge clock is read by the check on an
--   agent's charge order, its futures, the agent's board, the grader and the self-review. No kernel decision, dial or
--   seat reads it, and no certification arm runs the agent or the charge order (0615).
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0632_pre' AND object_kind = 'function';
--   then DROP FUNCTION public.ottoq_depot_air_c(uuid, timestamptz), public.ottoq_charge_clock_air(jsonb, numeric),
--   public.ottoq_solve_sym3(double precision, double precision, double precision, double precision, double precision,
--   double precision, double precision, double precision, double precision); ALTER TYPE
--   public.ottoq_charge_clock_evidence DROP ATTRIBUTE air; the fit appended here stays (evidence), and a person refits;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0632_the_charge_clock_reads_the_air'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe), no run running, no fit running ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0632 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0632 P0: a run is running; its check reads the clock this replaces. Apply between runs';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE pid <> pg_backend_pid() AND state = 'active' AND query ~ 'ottoq_fit_charge_time_v2\(') THEN
    RAISE EXCEPTION '0632 P0: a charge clock fit is running (the nightly refit); apply after it';
  END IF;
END $inflight$;

-- ── P1: the bodies are the ones measured; the type is the one measured; the objects are new ──
DO $premises$
DECLARE r record; v_attrs text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)', 'effce200fbbbb7313eb4a24ed2828c23'),
    ('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)',      '03dc08a04757b28cf06fb45796846c0d'),
    ('public.ottoq_charge_clock_run_evidence(jsonb,uuid,timestamp with time zone)',                     '314444ef731fa7a9f871b408fe42905f'),
    ('public.ottoq_charge_clock_audit_v2(uuid,timestamp with time zone,jsonb)',                         'aa709857b63e382345761f4adde03c7e'),
    ('public.ottoq_evidence_regime_scan(uuid,timestamp with time zone,jsonb)',                          'e19639b4af41d4c344f1eea515c4b466'),
    ('public.ottoq_charge_clock_trial(uuid,uuid[],timestamp with time zone,jsonb,jsonb,boolean)',       '9f90a8b251cee73bbe469efa16aa7741'),
    ('public.ottoq_fit_charge_time_v2(uuid,timestamp with time zone,interval,numeric,text)',            '10da7c3da9d44ad4a3057b3d4bd0e836'),
    ('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)',                  '8b4a099735a3d17272d46c668dc371da'))
    AS t(sig, src_md5)
  LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(r.sig)) IS DISTINCT FROM r.src_md5 THEN
      RAISE EXCEPTION '0632 P1: % is not the body measured (md5 %); read it again', r.sig, left(r.src_md5, 8);
    END IF;
  END LOOP;
  SELECT string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ', ' ORDER BY a.attnum) INTO v_attrs
    FROM pg_attribute a WHERE a.attrelid = 'public.ottoq_charge_clock_evidence'::regclass AND a.attnum > 0
     AND NOT a.attisdropped;
  IF v_attrs IS DISTINCT FROM 'sid uuid, run uuid, kind text, band text, who jsonb, cls text, mdl text, veh text, '
                              'lr double precision, w double precision, st timestamp with time zone, '
                              'en timestamp with time zone, bat numeric, s0 numeric, s1 numeric, ckw numeric, vkw numeric' THEN
    RAISE EXCEPTION '0632 P1: the clock''s evidence type is not the one measured: %', v_attrs;
  END IF;
  IF to_regprocedure('public.ottoq_charge_clock_air(jsonb,numeric)') IS NOT NULL
     OR to_regprocedure('public.ottoq_depot_air_c(uuid,timestamp with time zone)') IS NOT NULL
     OR to_regprocedure('public.ottoq_solve_sym3(double precision,double precision,double precision,double precision,'
                        'double precision,double precision,double precision,double precision,double precision)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0632_the_charge_clock_reads_the_air') THEN
    RAISE EXCEPTION '0632 P1: already applied';
  END IF;
  IF to_regclass('public.ottoq_charge_order_grades') IS NULL
     OR to_regclass('public.ottoq_charge_order_attributions') IS NULL THEN
    RAISE EXCEPTION '0632 P1: 0630 and 0631 come first (the self-review''s body is the one after them)';
  END IF;
  IF to_regclass('public.ottoq_charge_duration_ledger') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.ottoq_charge_duration_ledger'::regclass
                                               AND attname = 'depot_air_c' AND NOT attisdropped) THEN
    RAISE EXCEPTION '0632 P1: the charge ledger carries no depot_air_c';
  END IF;
END $premises$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0632_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)'::regprocedure,
                 'public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)'::regprocedure,
                 'public.ottoq_charge_clock_run_evidence(jsonb,uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_charge_clock_audit_v2(uuid,timestamp with time zone,jsonb)'::regprocedure,
                 'public.ottoq_evidence_regime_scan(uuid,timestamp with time zone,jsonb)'::regprocedure,
                 'public.ottoq_charge_clock_trial(uuid,uuid[],timestamp with time zone,jsonb,jsonb,boolean)'::regprocedure,
                 'public.ottoq_fit_charge_time_v2(uuid,timestamp with time zone,interval,numeric,text)'::regprocedure,
                 'public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)'::regprocedure);

-- ── what V2 and V3 compare against, read before anything changes: the clock as it stood (its latest usable fit, no
--    air level), its readings and its run evidence on the twin depot's latest runs, and 0625's fit on a short window ──
CREATE TEMP TABLE _0632_model ON COMMIT DROP AS
SELECT public.ottoq_charge_clock_model('11111111-1111-1111-1111-111111111111') AS m;

CREATE TEMP TABLE _0632_runs ON COMMIT DROP AS
SELECT r.sim_run_id, r.sim_clock_start, r.sim_clock_current
  FROM public.ottoq_sim_runs r
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.purged_at IS NULL AND r.sim_clock_current IS NOT NULL
   AND EXISTS (SELECT 1 FROM public.ottoq_charge_duration_ledger l WHERE l.sim_run_id = r.sim_run_id
                AND l.stopped_reason = 'completed' AND l.tick_minutes <= 1)
 ORDER BY r.started_at DESC LIMIT 3;

CREATE TEMP TABLE _0632_pre_ev ON COMMIT DROP AS
SELECT r.sim_run_id, t.at, public.ottoq_charge_clock_run_evidence(m.m, r.sim_run_id, t.at) AS ev
  FROM _0632_runs r CROSS JOIN _0632_model m
 CROSS JOIN LATERAL (VALUES (r.sim_clock_start + (r.sim_clock_current - r.sim_clock_start) / 2), (r.sim_clock_current)) t(at);

CREATE TEMP TABLE _0632_pre_clock ON COMMIT DROP AS
SELECT l.session_id, l.charger_type AS kind, l.depot_air_c, w.j AS who, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
       l.vehicle_kw, e.ev -> l.charger_type AS run_block,
       public.ottoq_charge_clock(m.m, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw,
                                 NULL) AS c_none,
       public.ottoq_charge_clock(m.m, l.charger_type, w.j, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw,
                                 e.ev -> l.charger_type) AS c_run
  FROM _0632_runs r CROSS JOIN _0632_model m
  JOIN public.ottoq_charge_duration_ledger l ON l.sim_run_id = r.sim_run_id AND l.stopped_reason = 'completed'
   AND l.charger_type IN ('dcfc', 'l2')
  JOIN public.vehicles v ON v.id = l.vehicle_id
 CROSS JOIN LATERAL (SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) AS j) w
  JOIN _0632_pre_ev e ON e.sim_run_id = r.sim_run_id AND e.at = r.sim_clock_current;

CREATE TEMP TABLE _0632_pre_fit ON COMMIT DROP AS
SELECT public.ottoq_charge_time_v2_params_cut('11111111-1111-1111-1111-111111111111', '2026-10-08 18:00:00+00'::timestamptz,
                                              interval '1 day', 3, '{}'::jsonb) AS p;

-- ══ (a) the evidence carries the air ═════════════════════════════════════════════════════════════════════════════════════
ALTER TYPE public.ottoq_charge_clock_evidence ADD ATTRIBUTE air double precision;

-- ══ (c) the level, its solve, and the depot's air ══════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_solve_sym3(a11 double precision, a12 double precision, a13 double precision,
                                       a22 double precision, a23 double precision, a33 double precision,
                                       b1 double precision, b2 double precision, b3 double precision)
RETURNS double precision[]
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0632: x in A x = b for a symmetric 3x3 A (Cramer's rule): the charge clock fits its level for the air with it. NULL
  -- when A is singular to working precision.
  SELECT CASE WHEN d.d IS NULL OR abs(d.d) <= 1e-12 * GREATEST(abs(a11 * a22 * a33), 1e-300) THEN NULL
              ELSE ARRAY[(b1 * (a22 * a33 - a23 * a23) - a12 * (b2 * a33 - a23 * b3) + a13 * (b2 * a23 - a22 * b3)) / d.d,
                         (a11 * (b2 * a33 - a23 * b3) - b1 * (a12 * a33 - a23 * a13) + a13 * (a12 * b3 - b2 * a13)) / d.d,
                         (a11 * (a22 * b3 - b2 * a23) - a12 * (a12 * b3 - b2 * a13) + b1 * (a12 * a23 - a22 * a13)) / d.d] END
    FROM (SELECT a11 * (a22 * a33 - a23 * a23) - a12 * (a12 * a33 - a23 * a13) + a13 * (a12 * a23 - a22 * a13) AS d) d
$fn$;

CREATE FUNCTION public.ottoq_charge_clock_air(p_level jsonb, p_air numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $fn$
  -- 0632: a charge clock fit's level for the air (params.air.<kind>) at an air temperature, in log: its slope from the
  -- evidence's centre (b1, c1) and, past its bend (knee), the bend's own slope (b2, from its centre c2), with the air
  -- held at the edge of what the fit saw (lo, hi). Centred, so over the fit's own evidence it averages zero. NULL when
  -- the level is not usable or the air is not known. The fit and the clock both read it here, so they cannot disagree.
  SELECT CASE WHEN p_air IS NULL OR NOT COALESCE((p_level ->> 'usable')::boolean, false) THEN NULL
              ELSE COALESCE((p_level ->> 'b1')::numeric, 0) * (a.x - COALESCE((p_level ->> 'c1')::numeric, 0))
                   + CASE WHEN jsonb_typeof(p_level -> 'knee') = 'number'
                          THEN COALESCE((p_level ->> 'b2')::numeric, 0)
                               * (GREATEST(a.x - (p_level ->> 'knee')::numeric, 0) - COALESCE((p_level ->> 'c2')::numeric, 0))
                          ELSE 0 END END
    FROM (SELECT LEAST(GREATEST(p_air, COALESCE((p_level ->> 'lo')::numeric, p_air)),
                       COALESCE((p_level ->> 'hi')::numeric, p_air)) AS x) a
$fn$;

CREATE FUNCTION public.ottoq_depot_air_c(p_sim_run_id uuid, p_at timestamptz)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
/* 0632: the depot's air temperature at a moment of a run, as the charge ledger records it for a charge that starts then
   (ottoq_capture_charge_duration reads twin.ottoq_sim_site_ambient_c: the run's latest weather reading at or before the
   moment; before its first, the day's temperature card). NULL when it is not known, and never an error: the charge
   clock reads it, and a clock without the air is the clock before 0632. */
BEGIN
  IF p_sim_run_id IS NULL OR p_at IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN twin.ottoq_sim_site_ambient_c(p_sim_run_id, p_at);
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END $fn$;

-- ══ (b) (d) (f) (g) (h) the anchored patches: each anchor once, the stored definition after ════════════════════════════════
CREATE TEMP TABLE _0632_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;

INSERT INTO _0632_patch VALUES
-- (b) the fit
('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)', 1,
$old$With no cut inside the window, 0622's params, key for key. */$old$,
$new$With no cut inside the window, 0622's params, key for key.
   0632: and the air. After the class levels, per kind, from the charges that carry the depot's air at their start
   (`air`, the ledger's depot_air_c): no level, one slope, or a slope that bends once at a whole degree with a tenth of
   the weight and three runs on each side, whichever predicts each run best from the others (each run left out in turn,
   its weighted squared error on the fit to the rest; outside a run the day's charges are the unit). The level is
   centred on the evidence (ottoq_charge_clock_air) and kept (usable) from c_air_min_runs runs and when it beats no level
   by c_air_min_gain out of sample. What it leaves is what the run, the car and the charge in progress are fitted on.
   p_cuts may carry {"air": false}: the fit without the air, 0625's params key for key. */$new$),
('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)', 2,
$old$  c_min_pairs constant int := 20;$old$,
$new$  c_min_pairs constant int := 20;
  c_air_min_runs constant int := 6;          -- 0632
  c_air_min_gain constant float8 := 0.01;$new$),
('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)', 3,
$old$  v_runs      int;
BEGIN$old$,
$new$  v_runs      int;
  v_air_on    boolean;    -- 0632: whether this fit learns the air (p_cuts' "air", default true)
  v_air       jsonb := '{}'::jsonb;
BEGIN$new$),
('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)', 4,
$old$              WHERE c.key NOT IN ('dcfc', 'l2', '*') OR jsonb_typeof(c.value) <> 'string') THEN
    RAISE EXCEPTION 'ottoq_charge_time_v2_params_cut: a cut is {kind: timestamptz} with kind dcfc, l2 or *, not %', p_cuts;$old$,
$new$              WHERE c.key NOT IN ('dcfc', 'l2', '*', 'air')
                 OR jsonb_typeof(c.value) <> CASE WHEN c.key = 'air' THEN 'boolean' ELSE 'string' END) THEN
    RAISE EXCEPTION 'ottoq_charge_time_v2_params_cut: a cut is {kind: timestamptz} with kind dcfc, l2 or *, or {"air": '
                    'boolean} (0632), not %', p_cuts;$new$),
('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)', 5,
$old$   WHERE (c.value #>> '{}')::timestamptz > v_from AND (c.value #>> '{}')::timestamptz <= v_through;$old$,
$new$   WHERE CASE WHEN c.key = 'air' THEN false     -- 0632: not a cut
              ELSE (c.value #>> '{}')::timestamptz > v_from AND (c.value #>> '{}')::timestamptz <= v_through END;
  v_air_on := COALESCE((p_cuts ->> 'air')::boolean, true);$new$),
('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)', 6,
$old$           l.started_at, l.ended_at, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw,$old$,
$new$           l.started_at, l.ended_at, l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw,
           l.depot_air_c::float8 AS air,                                                                      -- 0632$new$),
('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)', 7,
$old$b.charger_kw::numeric, b.vehicle_kw::numeric)::public.ottoq_charge_clock_evidence$old$,
$new$b.charger_kw::numeric, b.vehicle_kw::numeric, b.air::float8)::public.ottoq_charge_clock_evidence$new$),
('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)', 8,
$old$  -- ── the run: how far a run's mean departs beyond sampling (its prior strength), and its shrunk offsets ──$old$,
$new$  -- ── 0632: the air, after the class levels: per kind, no level, a slope, or a slope with one bend, whichever predicts
  --    each run best from the others; kept from c_air_min_runs runs and when it beats no level by c_air_min_gain ──
  IF v_air_on THEN
    WITH e AS (
      SELECT x.kind, COALESCE(x.run::text, 'day ' || to_char(x.st AT TIME ZONE 'UTC', 'YYYY-MM-DD')) AS g, x.w, x.air AS a,
             v_r[x.ordinality] AS y
        FROM unnest(v_e) WITH ORDINALITY x WHERE x.air IS NOT NULL
    ), ctr AS (   -- each kind's centre (its weighted mean air) and the air it saw
      SELECT e.kind, sum(e.w * e.a) / sum(e.w) AS c1, min(e.a) AS lo, max(e.a) AS hi, count(*) AS n,
             count(DISTINCT e.g) AS groups
        FROM e GROUP BY e.kind
    ), kn AS (    -- the bends it may try: a whole degree with a tenth of the weight and three runs on each side
      SELECT e.kind, k.k::float8 AS knee
        FROM e CROSS JOIN generate_series(-40, 60) k(k)
       GROUP BY e.kind, k.k
      HAVING sum(e.w) FILTER (WHERE e.a < k.k) >= 0.1 * sum(e.w) AND sum(e.w) FILTER (WHERE e.a >= k.k) >= 0.1 * sum(e.w)
         AND count(DISTINCT e.g) FILTER (WHERE e.a < k.k) >= 3 AND count(DISTINCT e.g) FILTER (WHERE e.a >= k.k) >= 3
    ), cand AS (
      SELECT ctr.kind, s.shape, NULL::float8 AS knee FROM ctr CROSS JOIN (VALUES ('none'), ('linear')) s(shape)
      UNION ALL
      SELECT kn.kind, 'hinge', kn.knee FROM kn
    ), cc AS (    -- each bend's centre: the weighted mean of the part past it
      SELECT cand.kind, cand.shape, cand.knee,
             CASE WHEN cand.shape = 'hinge' THEN sum(e.w * GREATEST(e.a - cand.knee, 0)) / sum(e.w) ELSE 0 END AS c2
        FROM cand JOIN e USING (kind) GROUP BY cand.kind, cand.shape, cand.knee
    ), gs AS (    -- per shape and run: the weighted sums of the design (1, air - c1, (air - knee)+ - c2) and the residual
      SELECT cc.kind, cc.shape, cc.knee, e.g,
             sum(e.w) AS s11, sum(e.w * z.x1) AS s12, sum(e.w * z.x2) AS s13, sum(e.w * z.x1 * z.x1) AS s22,
             sum(e.w * z.x1 * z.x2) AS s23, sum(e.w * z.x2 * z.x2) AS s33,
             sum(e.w * e.y) AS t1, sum(e.w * z.x1 * e.y) AS t2, sum(e.w * z.x2 * e.y) AS t3, sum(e.w * e.y * e.y) AS tyy
        FROM cc JOIN ctr USING (kind) JOIN e USING (kind)
        CROSS JOIN LATERAL (SELECT CASE WHEN cc.shape = 'none' THEN 0 ELSE e.a - ctr.c1 END AS x1,
                                   CASE WHEN cc.shape = 'hinge' THEN GREATEST(e.a - cc.knee, 0) - cc.c2 ELSE 0 END AS x2) z
       GROUP BY cc.kind, cc.shape, cc.knee, e.g
    ), tot AS (
      SELECT gs.kind, gs.shape, gs.knee, sum(gs.s11) AS s11, sum(gs.s12) AS s12, sum(gs.s13) AS s13,
             sum(gs.s22) AS s22, sum(gs.s23) AS s23, sum(gs.s33) AS s33, sum(gs.t1) AS t1, sum(gs.t2) AS t2,
             sum(gs.t3) AS t3
        FROM gs GROUP BY gs.kind, gs.shape, gs.knee
    ), cv AS (    -- each run left out in turn: its weighted squared error on the fit to the others (a column a shape does
                  -- not use is held at zero by a unit diagonal)
      SELECT gs.kind, gs.shape, gs.knee,
             sum(gs.tyy - 2 * (f.b[1] * gs.t1 + f.b[2] * gs.t2 + f.b[3] * gs.t3)
                 + f.b[1] * f.b[1] * gs.s11 + f.b[2] * f.b[2] * gs.s22 + f.b[3] * f.b[3] * gs.s33
                 + 2 * (f.b[1] * f.b[2] * gs.s12 + f.b[1] * f.b[3] * gs.s13 + f.b[2] * f.b[3] * gs.s23))
               / sum(gs.s11) AS mse,
             count(*) FILTER (WHERE f.b IS NULL) AS singular
        FROM gs JOIN tot USING (kind, shape)
        CROSS JOIN LATERAL (SELECT public.ottoq_solve_sym3(
                   tot.s11 - gs.s11, tot.s12 - gs.s12, tot.s13 - gs.s13,
                   tot.s22 - gs.s22 + CASE WHEN gs.shape = 'none' THEN 1 ELSE 0 END, tot.s23 - gs.s23,
                   tot.s33 - gs.s33 + CASE WHEN gs.shape = 'hinge' THEN 0 ELSE 1 END,
                   tot.t1 - gs.t1, tot.t2 - gs.t2, tot.t3 - gs.t3) AS b) f
       WHERE tot.knee IS NOT DISTINCT FROM gs.knee
       GROUP BY gs.kind, gs.shape, gs.knee
    ), best AS (  -- each shape's best (a bend's best knee), solvable on every run left out
      SELECT DISTINCT ON (cv.kind, cv.shape) cv.* FROM cv WHERE cv.singular = 0 AND cv.mse IS NOT NULL
       ORDER BY cv.kind, cv.shape, cv.mse, cv.knee
    ), pick AS (
      SELECT DISTINCT ON (b.kind) b.kind, b.shape, b.knee, b.mse,
             (SELECT n.mse FROM best n WHERE n.kind = b.kind AND n.shape = 'none') AS mse_none
        FROM best b
       ORDER BY b.kind, b.mse, CASE b.shape WHEN 'none' THEN 0 WHEN 'linear' THEN 1 ELSE 2 END
    ), fin AS (   -- the shape picked, fitted on every run
      SELECT pick.*, ctr.c1, ctr.lo, ctr.hi, ctr.n, ctr.groups, cc.c2,
             public.ottoq_solve_sym3(tot.s11, tot.s12, tot.s13,
                                     tot.s22 + CASE WHEN pick.shape = 'none' THEN 1 ELSE 0 END, tot.s23,
                                     tot.s33 + CASE WHEN pick.shape = 'hinge' THEN 0 ELSE 1 END,
                                     tot.t1, tot.t2, tot.t3) AS b,
             (SELECT jsonb_object_agg(bb.shape, round(bb.mse::numeric, 6)) FROM best bb WHERE bb.kind = pick.kind) AS cvs,
             (SELECT bb.knee FROM best bb WHERE bb.kind = pick.kind AND bb.shape = 'hinge') AS best_knee
        FROM pick JOIN ctr USING (kind)
        JOIN tot ON tot.kind = pick.kind AND tot.shape = pick.shape AND tot.knee IS NOT DISTINCT FROM pick.knee
        JOIN cc ON cc.kind = pick.kind AND cc.shape = pick.shape AND cc.knee IS NOT DISTINCT FROM pick.knee
    ), lv AS (
      SELECT fin.kind, fin.shape, fin.knee, fin.lo, fin.hi, fin.n, fin.groups, fin.cvs, fin.best_knee, fin.mse, fin.mse_none,
             round(fin.c1::numeric, 4) AS c1, round(fin.c2::numeric, 4) AS c2,
             CASE WHEN fin.shape = 'none' THEN 0 ELSE round(fin.b[2]::numeric, 6) END AS b1,
             CASE WHEN fin.shape = 'hinge' THEN round(fin.b[3]::numeric, 6) ELSE 0 END AS b2
        FROM fin WHERE fin.b IS NOT NULL
    )
    SELECT COALESCE(jsonb_object_agg(lv.kind, jsonb_strip_nulls(jsonb_build_object(
             'shape', lv.shape, 'b1', lv.b1, 'b2', lv.b2, 'knee', lv.knee, 'c1', lv.c1, 'c2', lv.c2,
             'lo', round(lv.lo::numeric, 2), 'hi', round(lv.hi::numeric, 2), 'g', GREATEST(abs(lv.b1), abs(lv.b1 + lv.b2)),
             'n', lv.n, 'runs', lv.groups, 'cv', lv.cvs, 'hinge_knee', lv.best_knee,
             'gain', round((1 - lv.mse / NULLIF(lv.mse_none, 0))::numeric, 4),
             'usable', lv.shape <> 'none' AND lv.groups >= c_air_min_runs
                       AND lv.mse <= (1 - c_air_min_gain) * lv.mse_none))), '{}'::jsonb)
      INTO v_air
      FROM lv;
    v_p := v_p || jsonb_build_object('air', v_air);
    v_m := jsonb_build_object('params', v_p);
    -- what the level leaves, as the clock will leave it (the level as stored, read where the clock reads it)
    v_r := ARRAY(SELECT v_r[x.ordinality] - COALESCE(public.ottoq_charge_clock_air(v_air -> x.kind, x.air::numeric)::float8, 0)
                   FROM unnest(v_e) WITH ORDINALITY x ORDER BY x.ordinality);
    v_ladder := v_ladder || jsonb_build_object('after_air',
                  (SELECT jsonb_object_agg(z.kind, z.rms) FROM (
                     SELECT x.kind, round(sqrt(sum(x.w * v_r[x.ordinality] ^ 2) / sum(x.w))::numeric, 4) AS rms
                       FROM unnest(v_e) WITH ORDINALITY x GROUP BY x.kind) z));
  END IF;

  -- ── the run: how far a run's mean departs beyond sampling (its prior strength), and its shrunk offsets ──$new$),
('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)', 9,
$old$             - (public.ottoq_charge_clock(v_m, mv.kind, mv.who, mv.bat, mv.s0, mv.soc_at, mv.ckw, mv.vkw, NULL) ->> 'f')::numeric AS x,$old$,
$new$             - (public.ottoq_charge_clock(v_m, mv.kind, mv.who, mv.bat, mv.s0, mv.soc_at, mv.ckw, mv.vkw,
                                          jsonb_build_object('air_c', mv.air)) ->> 'f')::numeric AS x,   -- 0632: at its air$new$),
('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)', 10,
$old$             - (public.ottoq_charge_clock(v_m, mv.kind, mv.who, mv.bat, mv.soc_at, mv.s1, mv.ckw, mv.vkw, NULL) ->> 'f')::numeric AS y,$old$,
$new$             - (public.ottoq_charge_clock(v_m, mv.kind, mv.who, mv.bat, mv.soc_at, mv.s1, mv.ckw, mv.vkw,
                                          jsonb_build_object('air_c', mv.air)) ->> 'f')::numeric AS y,$new$),
-- (d) the clock
('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)', 1,
$old$m is NULL when the battery size is unknown and 0
   when nothing is owed. */$old$,
$new$m is NULL when the battery size is unknown and 0
   when nothing is owed.
   0632: with p_run's air_c (the depot's air, which the run's evidence carries), the fit's level for the air
   (ottoq_charge_clock_air: lvl '+air', and the level as `air`); past the edge of the air the fit saw, the spread
   widened by the level's steepest slope for every degree beyond. */$new$),
('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)', 2,
$old$  v_expl   numeric := 0;
BEGIN$old$,
$new$  v_expl   numeric := 0;
  v_al     jsonb;           -- 0632: the fit's level for the air on this kind
  v_air    numeric;
  v_out    numeric := 0;
BEGIN$new$),
('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)', 3,
$old$  IF p_run IS NOT NULL THEN$old$,
$new$  -- 0632: the depot's air at the charge
  v_al := v_p #> ARRAY['air', p_kind];
  IF v_al IS NOT NULL AND jsonb_typeof(p_run -> 'air_c') = 'number' THEN
    v_air := public.ottoq_charge_clock_air(v_al, (p_run ->> 'air_c')::numeric);
    IF v_air IS NOT NULL THEN
      v_f := v_f + v_air;
      v_out := GREATEST((p_run ->> 'air_c')::numeric - (v_al ->> 'hi')::numeric,
                        (v_al ->> 'lo')::numeric - (p_run ->> 'air_c')::numeric, 0);
      v_lvl := v_lvl || '+air';
    END IF;
  END IF;
  IF p_run IS NOT NULL THEN$new$),
('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)', 4,
$old$  v_sd := v_sd * sqrt(1 - LEAST(GREATEST(v_expl, 0), 0.95));$old$,
$new$  v_sd := v_sd * sqrt(1 - LEAST(GREATEST(v_expl, 0), 0.95));
  IF v_out > 0 THEN   -- 0632: an air the fit never saw
    v_sd := sqrt(v_sd * v_sd + power(COALESCE((v_al ->> 'g')::numeric, 0) * v_out, 2));
  END IF;$new$),
('public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)', 5,
$old$    'sd', round(v_sd, 4), 'f', round(v_f, 4), 'lvl', v_lvl);$old$,
$new$    'sd', round(v_sd, 4), 'f', round(v_f, 4), 'lvl', v_lvl)
    || CASE WHEN v_air IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('air', round(v_air, 4)) END;   -- 0632$new$),
-- (f) the audit, the scan and the trial
('public.ottoq_charge_clock_audit_v2(uuid,timestamp with time zone,jsonb)', 1,
$old$  -- more charges), with the spread of the runs' mean temperatures (10th to 90th percentile, by charge).$old$,
$new$  -- more charges), with the spread of the runs' mean temperatures (10th to 90th percentile, by charge).
  -- 0632: the clock reads each charge at its own air (its fit's level for the air), so the slope is what it leaves.$new$),
('public.ottoq_charge_clock_audit_v2(uuid,timestamp with time zone,jsonb)', 2,
$old$                                     l.vehicle_kw, NULL) AS c2,$old$,
$new$                                     l.vehicle_kw, jsonb_build_object('air_c', l.depot_air_c)) AS c2,$new$),
('public.ottoq_evidence_regime_scan(uuid,timestamp with time zone,jsonb)', 1,
$old$   A finding, never a cut: a person records the change, and the clock learns from it that night (CLAUDE.md rule 10). */$old$,
$new$   A finding, never a cut: a person records the change, and the clock learns from it that night (CLAUDE.md rule 10).
   0632: each charge is read at its own air (the clock's level for it), so a hot week is not taken for a change. */$new$),
('public.ottoq_evidence_regime_scan(uuid,timestamp with time zone,jsonb)', 2,
$old$                                          l.vehicle_kw, NULL) ->> 'f')::float8 AS r$old$,
$new$                                          l.vehicle_kw, jsonb_build_object('air_c', l.depot_air_c)) ->> 'f')::float8 AS r$new$),
('public.ottoq_charge_clock_trial(uuid,uuid[],timestamp with time zone,jsonb,jsonb,boolean)', 1,
$old$   mean absolute log error and mean log error. An engineering instrument; production never calls it, and it writes
   nothing. */$old$,
$new$   mean absolute log error and mean log error. An engineering instrument; production never calls it, and it writes
   nothing. 0632: a cut set may carry {"air": false}, the fit without its level for the air; each arm's level is
   reported (air_a, air_b). */$new$),
('public.ottoq_charge_clock_trial(uuid,uuid[],timestamp with time zone,jsonb,jsonb,boolean)', 2,
$old$           'regimes_a', v_a #> '{params,regimes}', 'regimes_b', v_b #> '{params,regimes}',$old$,
$new$           'regimes_a', v_a #> '{params,regimes}', 'regimes_b', v_b #> '{params,regimes}',
           'air_a', v_a #> '{params,air}', 'air_b', v_b #> '{params,air}',                                   -- 0632$new$),
-- (h) the fit's code md5
('public.ottoq_fit_charge_time_v2(uuid,timestamp with time zone,interval,numeric,text)', 1,
$old$   the function that applies them. */$old$,
$new$   the function that applies them. 0632: and the level for the air and the solve that fits it. */$new$),
('public.ottoq_fit_charge_time_v2(uuid,timestamp with time zone,interval,numeric,text)', 2,
$old$              || pg_get_functiondef('public.ottoq_evidence_regime_cuts(text,uuid,timestamp with time zone,timestamp with time zone)'::regprocedure)),$old$,
$new$              || pg_get_functiondef('public.ottoq_evidence_regime_cuts(text,uuid,timestamp with time zone,timestamp with time zone)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_clock_air(jsonb,numeric)'::regprocedure)
              || pg_get_functiondef('public.ottoq_solve_sym3(double precision,double precision,double precision,double precision,double precision,double precision,double precision,double precision,double precision)'::regprocedure)),$new$),
-- (g) the self-review
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 1,
$old$  v_cls_built boolean := false;$old$,
$new$  v_cls_built boolean := false;
  v_air_now boolean := false;                                                                      -- 0632
  v_air_timed boolean := false;$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 2,
$old$  IF v_n > 0 AND v_now IS NOT NULL THEN
    IF v_used ->> 'last_model' IS DISTINCT FROM v_now ->> 'model' THEN$old$,
$new$  -- 0632: whether the depot's clock reads the air now (its fit has a usable level for it), and whether any graded order
  -- was timed by a fit that did
  v_air_now := EXISTS (SELECT 1 FROM jsonb_each(COALESCE(v_now #> '{params,air}', '{}'::jsonb)) a
                        WHERE jsonb_typeof(a.value) = 'object' AND COALESCE((a.value ->> 'usable')::boolean, false));
  v_air_timed := EXISTS (SELECT 1 FROM public.ottoq_charge_order_grades h
                           JOIN public.ottoq_charge_order_snapshots s ON s.order_id = h.order_id
                           JOIN public.ottoq_charge_clock_fits f
                             ON f.fit_id = CASE WHEN s.state #>> '{models,charge_time_model}' = 'charge_time_v2'
                                                     AND (s.state #>> '{models,charge_time}') ~ '^[0-9]+$'
                                                THEN (s.state #>> '{models,charge_time}')::bigint END
                          WHERE h.depot_id IS NOT DISTINCT FROM p_depot_id AND h.graded_at >= p_since
                            AND EXISTS (SELECT 1 FROM jsonb_each(COALESCE(f.params -> 'air', '{}'::jsonb)) a
                                         WHERE jsonb_typeof(a.value) = 'object'
                                           AND COALESCE((a.value ->> 'usable')::boolean, false)));
  IF v_n > 0 AND v_now IS NOT NULL THEN
    IF v_used ->> 'last_model' IS DISTINCT FROM v_now ->> 'model' THEN$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 3,
$old$      v_note := ' Since these orders, a change in the charge clock''s world was recorded and the clock refitted to it, so '
                'this is history until new orders are graded.';
    END IF;$old$,
$new$      v_note := ' Since these orders, a change in the charge clock''s world was recorded and the clock refitted to it, so '
                'this is history until new orders are graded.';
    ELSIF v_air_now AND NOT v_air_timed THEN                                                       -- 0632
      v_rebuilt := 'air';
      v_note := ' These orders were timed by a charge clock that did not read the air, since given a level for it, so '
                'this is history until new orders are graded.';
    END IF;$new$),
('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)', 4,
$old$  IF v IS NOT NULL THEN
    v_areas := v_areas || jsonb_build_object(
      'area', 'charge_clock_misses_air_temperature', 'kind', 'capability_gap', 'part', 'charge_times',$old$,
$new$  -- 0632: the clock's level for the air, in words
  SELECT string_agg(public.ottoq_review_words('kind', a.key) || ' run '
                    || CASE WHEN a.value ->> 'shape' = 'hinge'
                            THEN public.ottoq_review_change(exp((a.value ->> 'b1')::numeric + (a.value ->> 'b2')::numeric),
                                                            'shorter', 'longer', 1)
                                 || ' for each degree warmer above ' || (a.value ->> 'knee') || ' °C and '
                                 || public.ottoq_review_change(exp((a.value ->> 'b1')::numeric), 'shorter', 'longer', 1)
                                 || ' below it'
                            ELSE public.ottoq_review_change(exp((a.value ->> 'b1')::numeric), 'shorter', 'longer', 1)
                                 || ' for each degree warmer' END
                    || ' (learned on ' || (a.value ->> 'runs') || ' runs at ' || (a.value ->> 'lo') || ' to '
                    || (a.value ->> 'hi') || ' °C)', '; ' ORDER BY a.key)
    INTO v_txt
    FROM jsonb_each(COALESCE(v_now #> '{params,air}', '{}'::jsonb)) a
   WHERE v_air_now AND jsonb_typeof(a.value) = 'object' AND COALESCE((a.value ->> 'usable')::boolean, false);
  IF v IS NOT NULL AND v_air_now THEN                                                              -- 0632
    v_areas := v_areas || jsonb_build_object(
      'area', 'charge_clock_misses_air_temperature', 'kind', 'calibration', 'part', 'charge_times',
      'status', 'open', 'thin', false, 'tier', 2, 'weight', v_cur,
      'title', 'The charge clock reads the air, and still misses it',
      'finding', 'Charges on ' || v_list || ', after the clock''s own level for the air: ' || COALESCE(v_txt, 'none') || '.',
      'action', 'Let the nightly refit learn the air from more runs; if it lasts, give the level more shape (a second bend, '
                || 'or the air through the charge rather than at its start).',
      'evidence', jsonb_build_object('by_kind', v, 'level', v_now #> '{params,air}'));
  ELSIF v IS NULL AND v_air_now AND v_rebuilt = 'air' THEN                                         -- 0632
    v_areas := v_areas || jsonb_build_object(
      'area', 'charge_clock_misses_air_temperature', 'kind', 'capability_gap', 'part', 'charge_times',
      'status', 'built', 'thin', false, 'tier', 2,
      'weight', (SELECT COALESCE(sum((a.value ->> 'n')::int), 0)
                   FROM jsonb_each(COALESCE(v_now #> '{params,air}', '{}'::jsonb)) a
                  WHERE jsonb_typeof(a.value) = 'object' AND COALESCE((a.value ->> 'usable')::boolean, false)),
      'title', 'The charge clock reads the air',
      'finding', 'The clock has a level for the depot''s air at each charge''s start: ' || COALESCE(v_txt, 'none') || '.'
                 || v_note,
      'action', 'Nothing until orders timed by the clock that reads the air are graded.',
      'evidence', jsonb_build_object('level', v_now #> '{params,air}'));
  ELSIF v IS NOT NULL THEN
    v_areas := v_areas || jsonb_build_object(
      'area', 'charge_clock_misses_air_temperature', 'kind', 'capability_gap', 'part', 'charge_times',$new$);

DO $patch$
DECLARE f record; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0632_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(to_regprocedure(f.fn));
    FOR p IN SELECT * FROM _0632_patch WHERE fn = f.fn ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0632 %: anchor % matches % times, not 1', f.fn, p.seq, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    -- V1: the stored definition is the pre-image with exactly these replacements
    IF pg_get_functiondef(to_regprocedure(f.fn)) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0632 V1: % is not stored as patched', f.fn;
    END IF;
  END LOOP;
END $patch$;

-- ══ (e) the run's evidence ═══════════════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_charge_clock_run_evidence(p_model jsonb, p_sim_run_id uuid, p_asof timestamptz)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0622: what a run's own completed charges, up to sim time p_asof, say about its clock, per kind: {n, off, s, veh: {car:
  -- {n, off, s}}}. Each charge's residual is its log ratio less the cross-run clock (no run evidence); the run's offset is
  -- their mean shrunk by n / (n + k_run); a car's offset is the mean of its own residuals less the run's, shrunk by
  -- Spearman-Brown on the model's measured in-run correlation. NULL on a model without the levels (0619).
  -- 0632: each residual is taken on the clock at the charge's own air (the ledger's depot_air_c), so the run's offset is
  -- what the model's level for the air leaves; and each kind the model has a usable level for carries the depot's air at
  -- p_asof (ottoq_depot_air_c) as air_c, with n 0 before the run's first charge of the kind, so the clock reads the air
  -- from the run's first minute. On a model without a level for the air, 0622's evidence key for key.
  WITH ok AS (
    SELECT (p_model #> '{params,class_cells}') IS NOT NULL AND p_sim_run_id IS NOT NULL AND p_asof IS NOT NULL AS go
  ), c AS (
    SELECT l.charger_type AS kind, l.vehicle_id::text AS veh,
           ln((l.duration_min / est.m)::numeric)
             - (public.ottoq_charge_clock(p_model, l.charger_type,
                                          public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model),
                                          l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw, l.vehicle_kw,
                                          jsonb_build_object('air_c', l.depot_air_c)) ->> 'f')::numeric AS res
      FROM ok
      JOIN public.ottoq_charge_duration_ledger l ON ok.go
      JOIN public.vehicles v ON v.id = l.vehicle_id
      CROSS JOIN LATERAL (SELECT public.ottoq_charge_minutes_estimate(l.battery_kwh, l.soc_start, l.soc_end, l.charger_kw,
                                                                      l.vehicle_kw) AS m) est
     WHERE l.sim_run_id = p_sim_run_id AND l.stopped_reason = 'completed' AND l.ended_at <= p_asof
       AND l.charger_type IN ('dcfc', 'l2') AND l.duration_min > 0 AND l.soc_end > l.soc_start AND est.m > 0
  ), k AS (
    SELECT c.kind, count(*) AS n, avg(c.res) AS mres,
           GREATEST(COALESCE((p_model #>> ARRAY['params', 'run', c.kind, 'k'])::numeric, 1000), 0.5) AS kr,
           LEAST(GREATEST(COALESCE((p_model #>> ARRAY['params', 'icc', c.kind, 'in_run'])::numeric, 0), 0), 0.95) AS rho
      FROM c GROUP BY c.kind
  ), ko AS (
    SELECT k.kind, k.n, k.rho, k.n / (k.n + k.kr) AS s, k.n / (k.n + k.kr) * k.mres AS off FROM k
  ), vv AS (
    SELECT c.kind, c.veh, count(*) AS n, avg(c.res - ko.off) AS mres, max(ko.rho) AS rho
      FROM c JOIN ko USING (kind) GROUP BY c.kind, c.veh
  ), da AS (    -- 0632: the depot's air at p_asof, read only for a model with a level for it
    SELECT CASE WHEN (SELECT go FROM ok) AND jsonb_typeof(p_model #> '{params,air}') = 'object'
                THEN public.ottoq_depot_air_c(p_sim_run_id, p_asof) END AS a
  ), air AS (   -- 0632: the kinds the model has a usable level for
    SELECT k.kind, da.a FROM (VALUES ('dcfc'), ('l2')) k(kind) CROSS JOIN da
     WHERE da.a IS NOT NULL AND COALESCE((p_model #>> ARRAY['params', 'air', k.kind, 'usable'])::boolean, false)
  )
  SELECT CASE WHEN (SELECT go FROM ok) THEN COALESCE((
    SELECT jsonb_object_agg(kk.kind,
             CASE WHEN ko.kind IS NULL THEN jsonb_build_object('n', 0, 's', 0, 'off', 0, 'veh', '{}'::jsonb)
                  ELSE jsonb_build_object(
                         'n', ko.n, 's', round(ko.s, 4), 'off', round(ko.off, 4),
                         'veh', COALESCE((SELECT jsonb_object_agg(vv.veh, jsonb_build_object(
                                                   'n', vv.n,
                                                   's', round(vv.n * vv.rho / (1 + (vv.n - 1) * vv.rho), 4),
                                                   'off', round(vv.n * vv.rho / (1 + (vv.n - 1) * vv.rho) * vv.mres, 4)))
                                            FROM vv WHERE vv.kind = ko.kind AND vv.rho > 0), '{}'::jsonb)) END
             || CASE WHEN air.a IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('air_c', round(air.a, 2)) END)
      FROM (SELECT ko.kind FROM ko UNION SELECT air.kind FROM air) kk
      LEFT JOIN ko ON ko.kind = kk.kind
      LEFT JOIN air ON air.kind = kk.kind), '{}'::jsonb) END
$fn$;

-- who may call what: the level, the solve and the depot's air as the clock is (every reader); the fit as it was
GRANT EXECUTE ON FUNCTION public.ottoq_charge_clock_air(jsonb, numeric) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_solve_sym3(double precision, double precision, double precision, double precision,
                                                 double precision, double precision, double precision, double precision,
                                                 double precision) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_depot_air_c(uuid, timestamptz) TO anon, authenticated, service_role;

-- ══ V1: the level and the solve by arithmetic; the clock with a planted level, in range and beyond; each patch by meaning
DO $v1$
DECLARE
  c_lv constant jsonb := '{"shape": "hinge", "b1": 0.01, "b2": 0.02, "knee": 20, "c1": 18, "c2": 1, "lo": 10, "hi": 30,
                           "g": 0.03, "usable": true}';
  v_m jsonb; v_who jsonb; a jsonb; b jsonb; c jsonb; x double precision[]; v_def text;
BEGIN
  -- the level: 0.01 (25 - 18) + 0.02 (5 - 1) = 0.15; held at 30 above it and at 10 below it; nothing when not usable
  IF public.ottoq_charge_clock_air(c_lv, 25) <> 0.15 OR public.ottoq_charge_clock_air(c_lv, 35) <> 0.30
     OR public.ottoq_charge_clock_air(c_lv, 5) <> -0.10
     OR public.ottoq_charge_clock_air(c_lv || '{"usable": false}', 25) IS NOT NULL
     OR public.ottoq_charge_clock_air(c_lv, NULL) IS NOT NULL
     OR public.ottoq_charge_clock_air(c_lv - 'knee', 25) <> 0.07 THEN
    RAISE EXCEPTION '0632 V1: the level reads % % % (want 0.15 0.30 -0.10)', public.ottoq_charge_clock_air(c_lv, 25),
      public.ottoq_charge_clock_air(c_lv, 35), public.ottoq_charge_clock_air(c_lv, 5);
  END IF;
  -- the solve: [[4,2,0],[2,3,1],[0,1,2]] x = [6,6,3] has x = [1,1,1]; a singular matrix has none
  x := public.ottoq_solve_sym3(4, 2, 0, 3, 1, 2, 6, 6, 3);
  IF x IS NULL OR abs(x[1] - 1) > 1e-9 OR abs(x[2] - 1) > 1e-9 OR abs(x[3] - 1) > 1e-9
     OR public.ottoq_solve_sym3(1, 1, 1, 1, 1, 1, 1, 1, 1) IS NOT NULL THEN
    RAISE EXCEPTION '0632 V1: the solve reads %', x;
  END IF;
  -- the clock: a per-car clock with no levels but this one planted on L2, a 75 kWh car from 40% to 100% on 19.2 kW
  v_m := jsonb_build_object('params', jsonb_build_object('cells', '{}'::jsonb, 'class_cells', '{}'::jsonb,
                                                         'model_cells', '{}'::jsonb, 'vehicle_cells', '{}'::jsonb,
                                                         'air', jsonb_build_object('l2', c_lv)));
  v_who := public.ottoq_charge_clock_who('00000000-0000-0000-0000-000000000632', 'x', 'X', 'One');
  a := public.ottoq_charge_clock(v_m, 'l2', v_who, 75, 40, 100, 19.2, 250, NULL);
  b := public.ottoq_charge_clock(v_m, 'l2', v_who, 75, 40, 100, 19.2, 250, '{"air_c": 25}');
  c := public.ottoq_charge_clock(v_m, 'l2', v_who, 75, 40, 100, 19.2, 250, '{"air_c": 35}');
  IF abs((b ->> 'f')::numeric - (a ->> 'f')::numeric - 0.15) > 0.0002 OR (b ->> 'lvl') <> (a ->> 'lvl') || '+air'
     OR (b ->> 'air')::numeric <> 0.15 OR (b ->> 'sd') <> (a ->> 'sd') OR a ? 'air'
     OR abs((c ->> 'f')::numeric - (a ->> 'f')::numeric - 0.30) > 0.0002
     OR abs((c ->> 'sd')::numeric - round(sqrt(power((a ->> 'sd')::numeric, 2) + 0.0225), 4)) > 0.0002 THEN
    RAISE EXCEPTION '0632 V1: the clock with a planted level reads % / % / %', a, b, c;
  END IF;
  -- each patch by meaning
  v_def := pg_get_functiondef('public.ottoq_charge_time_v2_params_cut(uuid,timestamp with time zone,interval,numeric,jsonb)'::regprocedure);
  IF strpos(v_def, 'b.vehicle_kw::numeric, b.air::float8)::public.ottoq_charge_clock_evidence') = 0
     OR strpos(v_def, 'IF v_air_on THEN') = 0 OR strpos(v_def, 'IF v_air_on THEN') > strpos(v_def, '-- ── the run: how far')
     OR strpos(v_def, 'jsonb_build_object(''air_c'', mv.air)') = 0 THEN
    RAISE EXCEPTION '0632 V1: the fit is not patched as meant';
  END IF;
  IF (SELECT string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ', ' ORDER BY a.attnum DESC)
        FROM (SELECT * FROM pg_attribute WHERE attrelid = 'public.ottoq_charge_clock_evidence'::regclass AND attnum > 0
                AND NOT attisdropped ORDER BY attnum DESC LIMIT 1) a) <> 'air double precision' THEN
    RAISE EXCEPTION '0632 V1: the evidence does not end with its air';
  END IF;
  RAISE NOTICE '0632 V1: the level, the solve and the clock with a planted level read as meant (L2 from 40%%: % min, at 25 °C % min, at 35 °C % min with spread % against %)',
    a ->> 'm', b ->> 'm', c ->> 'm', c ->> 'sd', a ->> 'sd';
END $v1$;

-- ══ V2: on the clock as it stood (no level for the air), the clock and the run's evidence read exactly as before ════════════
DO $v2$
DECLARE v_bad int; v_n int; v_ev int;
BEGIN
  SELECT count(*), count(*) FILTER (
           WHERE public.ottoq_charge_clock(m.m, p.kind, p.who, p.battery_kwh, p.soc_start, p.soc_end, p.charger_kw,
                                           p.vehicle_kw, NULL) IS DISTINCT FROM p.c_none
              OR public.ottoq_charge_clock(m.m, p.kind, p.who, p.battery_kwh, p.soc_start, p.soc_end, p.charger_kw,
                                           p.vehicle_kw, jsonb_build_object('air_c', COALESCE(p.depot_air_c, 30)))
                   IS DISTINCT FROM p.c_none
              OR public.ottoq_charge_clock(m.m, p.kind, p.who, p.battery_kwh, p.soc_start, p.soc_end, p.charger_kw,
                                           p.vehicle_kw, p.run_block || jsonb_build_object('air_c', 30))
                   IS DISTINCT FROM p.c_run)
    INTO v_n, v_bad
    FROM _0632_pre_clock p CROSS JOIN _0632_model m;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0632 V2: % of % charges read differently on the clock as it stood', v_bad, v_n;
  END IF;
  SELECT count(*), count(*) FILTER (WHERE public.ottoq_charge_clock_run_evidence(m.m, e.sim_run_id, e.at) IS DISTINCT FROM e.ev)
    INTO v_ev, v_bad
    FROM _0632_pre_ev e CROSS JOIN _0632_model m;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0632 V2: % of % run evidences read differently on the clock as it stood', v_bad, v_ev;
  END IF;
  RAISE NOTICE '0632 V2: on fit % (no level for the air), % charges and % run evidences read exactly as before, with and without the air',
    (SELECT m -> 'estimate_id' FROM _0632_model), v_n, v_ev;
END $v2$;

-- ══ V3: without the air the fit is 0625's, key for key ════════════════════════════════════════════════════════════════════
DO $v3$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
  SELECT p INTO v_old FROM _0632_pre_fit;
  v_new := public.ottoq_charge_time_v2_params_cut('11111111-1111-1111-1111-111111111111', '2026-10-08 18:00:00+00'::timestamptz,
                                                  interval '1 day', 3, '{"air": false}');
  IF v_new IS DISTINCT FROM v_old THEN
    RAISE EXCEPTION '0632 V3: without the air the fit is not 0625''s: keys %',
      (SELECT string_agg(k.key, ',') FROM jsonb_each(v_new) k WHERE k.value IS DISTINCT FROM v_old -> k.key);
  END IF;
  RAISE NOTICE '0632 V3: without the air, 0625''s fit key for key on the day to 2026-10-08 18:00 UTC (% charges)',
    v_old #> '{diagnostics,n}';
END $v3$;

-- ══ V4: the twin depot's clock refitted, reading the air ══════════════════════════════════════════════════════════════════
DO $v4$
DECLARE v_t timestamptz := clock_timestamp(); v_id bigint; f record; v_before jsonb;
BEGIN
  SELECT m -> 'params' INTO v_before FROM _0632_model;
  v_id := public.ottoq_fit_charge_time_v2('11111111-1111-1111-1111-111111111111', now(), interval '21 days', 3,
                                          '0632: the first fit to read the air');
  SELECT * INTO f FROM public.ottoq_charge_clock_fits WHERE fit_id = v_id;
  IF NOT f.usable OR jsonb_typeof(f.params -> 'air') <> 'object' THEN
    RAISE EXCEPTION '0632 V4: the refit % is not usable or has no air: %', v_id, f.params -> 'air';
  END IF;
  RAISE NOTICE '0632 V4: fit % in % s on % charges over % runs. The air: %. The ladder after the class levels %, after the air %. The run''s prior strength before % after %',
    v_id, round(extract(epoch FROM clock_timestamp() - v_t)::numeric, 1), f.n_evidence, f.n_runs, f.params -> 'air',
    f.params #> '{diagnostics,rms_ladder,after_class_levels}', f.params #> '{diagnostics,rms_ladder,after_air}',
    v_before -> 'run', f.params -> 'run';
END $v4$;

-- ══ V5: the clock reads the air on the twin depot's latest runs ═════════════════════════════════════════════════════════════
DO $v5$
DECLARE r record; v_m jsonb := public.ottoq_charge_clock_model('11111111-1111-1111-1111-111111111111'); v_ev jsonb;
        v_who jsonb; a jsonb; b jsonb; v_out text := '';
BEGIN
  SELECT public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model) INTO v_who
    FROM public.vehicles v WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.battery_capacity_kwh > 0
   ORDER BY v.id LIMIT 1;
  FOR r IN SELECT * FROM _0632_runs ORDER BY sim_clock_current DESC LOOP
    v_ev := public.ottoq_charge_clock_run_evidence(v_m, r.sim_run_id, r.sim_clock_start);
    a := public.ottoq_charge_clock(v_m, 'l2', v_who, 75, 40, 100, 19.2, 250, NULL);
    b := public.ottoq_charge_clock(v_m, 'l2', v_who, 75, 40, 100, 19.2, 250, v_ev -> 'l2');
    v_out := v_out || format('%s at its first minute (%s °C): L2 from 40%% %s min without the air, %s with it (%s); ',
                             left(r.sim_run_id::text, 8), COALESCE(v_ev #>> '{l2,air_c}', v_ev #>> '{dcfc,air_c}', 'unknown'),
                             a ->> 'm', b ->> 'm', b ->> 'lvl');
  END LOOP;
  RAISE NOTICE '0632 V5: %', v_out;
END $v5$;

-- ══ V6: the audit and the self-review read it ═════════════════════════════════════════════════════════════════════════════
DO $v6$
DECLARE c_twin constant uuid := '11111111-1111-1111-1111-111111111111'; v jsonb; v_aud jsonb; v_t timestamptz := clock_timestamp();
BEGIN
  v_aud := public.ottoq_charge_clock_audit_v2(c_twin, now() - interval '7 days', NULL);
  v := public.ottoq_arbiter_self_assessment_v3(c_twin, now() - interval '7 days', false);
  RAISE NOTICE '0632 V6: the audit''s air slopes on what the clock leaves: %. The self-review in % ms: its air area %; rebuilt %',
    (SELECT jsonb_object_agg(k.key, k.value -> 'air_temperature') FROM jsonb_each(COALESCE(v_aud -> 'by_kind', '{}'::jsonb)) k),
    round(extract(epoch FROM clock_timestamp() - v_t) * 1000),
    COALESCE((SELECT (x.value ->> 'status') || ': ' || (x.value ->> 'title') || ' :: ' || left(x.value ->> 'finding', 300)
                FROM jsonb_array_elements(v -> 'improvement_areas') x
               WHERE x.value ->> 'area' = 'charge_clock_misses_air_temperature'), 'none'),
    v #> '{clocks,rebuilt_since}';
END $v6$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0632_the_charge_clock_reads_the_air', false, false,
  'the charge clock''s fit (ottoq_charge_time_v2_params_cut) learns a level for the depot''s air at each charge''s start '
  '(none, a slope, or a slope with one bend, chosen by leaving each run out; ottoq_charge_clock_air), the clock adds it '
  'when the run''s evidence carries the air (ottoq_charge_clock_run_evidence, ottoq_depot_air_c), and the run, the car '
  'and the charge in progress are fitted on what it leaves; the audit, the scan and the self-review read it; the twin '
  'depot''s clock is refitted. FALSE/FALSE as 0622 and 0625: the clock is read by the check on an agent''s charge order, '
  'its futures, the agent''s board, the grader and the self-review; no kernel decision, dial or seat reads it, and no '
  'certification arm runs the agent or the charge order.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
