-- migration-version: PENDING
-- migration-name:    a_site_that_divides_its_power_is_judged_by_the_limit_it_holds
--
-- 0729  **A site that divides its power is judged by the limit it holds.** With `dc_power_managed` at 1 beside 0726's
--       `dc_power_sharing`, a test day's fast chargers sit behind a site controller that holds every charge at the
--       shield's own engineering cap, and EN.001 judges a charge start against that held limit instead of adding the
--       car's whole rating to the meter. Off by default: at 0 every start is judged exactly as before. Research wing,
--       rule 10; the open half of G445.
--
-- ══ §1 WHY (db/checks/0451 §2 (c), G445) ═════════════════════════════════════════════════════════════════════════════
--
--   EN.001.grid_capacity_ceiling (safety_critical, block) refuses a charge start when the site meter plus the car's
--   rating, LEAST(charger kW, inlet kW), passes dcfc_max_concurrent_kw x (1 - dcfc_safety_margin_pct / 100); the
--   charge start has been an enforcing checkpoint since 0428 (ottoq_shield_probe_posture: `enforced`, one caller,
--   honouring). That is the right question for chargers that each draw what they like, and tonight's baseline arms show
--   it working: 3 refusals on normal_day arm 83 and 9 on busy_day arm 82, at a largest after_kw of 1,836 and 1,953
--   against a cap of 1,620. On a site whose cabinets divide a held limit the sum is not a load the site can reach: a
--   new car takes a share and the aggregate stays at the limit. The rule then refuses cars the hardware would serve,
--   exactly when the site is busiest, and the car waits unplugged with a robot beside it. 0728's `shared` cell measures
--   that: sharing behind a shield admission at 90%.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) The dial `dc_power_managed`, catalogued 0..1, default 0, not agent-writable, read per run. Meaningful only with
--       dc_power_sharing 1: it says a site controller holds the pool, not merely that the cabinets share it.
--   (b) twin.ottoq_sim_dc_pool_plan, one anchored insertion: under the dial the cabinet term is the engineering cap
--       EN.001 judges against, dcfc_max_concurrent_kw x (1 - dcfc_safety_margin_pct / 100), less this tick's L2 demand,
--       because the rule counts every charge against that cap. So the controller holds the whole site meter at the
--       cap, by the rule's own arithmetic, and below the cabinets' rating.
--   (c) twin.ottoq_sim_dc_managed_context(run, clock, stall_type): under both dials, on a fast-charger stall, the
--       limit the controller holds this tick (the plan's pool plus its L2 demand) as {managed_limit_kw, managed_by}.
--       '{}' otherwise, and '{}' ON ANY ERROR: the charge start's probe sits in a block that skips the whole shield if
--       anything in it raises, so a failure here must leave the start judged by EN.001's own sum, never unjudged.
--   (d) twin.ottoq_sim_start_charge_session, one anchored insertion: the probe's context gains (c). requested_kw is
--       unchanged, so EN.002, EN.004, EN.005 and HW.002, which read the same context, see exactly what they saw.
--   (e) public.ottoq_eval_en_001_grid_capacity, one guarded insertion: when the context carries a numeric
--       managed_limit_kw, the aggregate after the start is the lower of the sum and the limit, and never below what the
--       meter already reads. A limit claimed above the engineering cap buys nothing past it, and a site already over
--       the cap still reads over it and is refused. Without the key the evaluator is byte for byte what it was.
--   (f) The three build-outs whose `enforced` note says dcfc_max_concurrent_kw is "never enforced" (0724's) get the
--       corrected note. Documentation only: ottoq_site_buildout_apply, the table's one reader, never reads `basis`.
--   (g) Sweep dcfc40_managed_normal_2026_10_17: normal_day from 6 AM CT, 144 ticks of 5 minutes, value_2026_09_30's
--       first seed, priority 15, arm budget 5,400 s, one cell, dcfc40_cab2400.managed {deploy_peak_fraction 0.90,
--       dc_power_sharing 1, dc_power_managed 1, enforce_site_charge_cap 0}. Beside 0728's dcfc40_cab2400.shared it
--       differs in dc_power_managed alone, which moves two things together: the pool falls from 2,400 kW to the
--       engineering cap (2,160 less L2), and the shield stops counting a new car's rating on top of it.
--   Rule 9: this decides only whether a charge start is refused. It never stops, slows or shortens a charge. The
--   grid-event hard stop (EN.005) reads no kW at all and is untouched.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the three bodies are the ones read on 2026-10-17 (EN.001 prosrc md5 696445a7..., the
--   plan 3d224cf3..., the charge start 5a9a9960...); 0726-0728 applied; the dial and the helper absent. P2: the sweep is
--   absent. Pre-images to ottoq_schema_snapshots as '0729_pre'. V1: EACH BODY LESS ITS 0729 INSERTION IS ITS PRE-IMAGE,
--   so every start on a run without both dials, and every EN.001 evaluation whose context has no managed_limit_kw, is
--   computed as before. V2: EN.001 on synthetic contexts at the twin depot: the same over-cap request refused without a
--   managed limit, passed under one at the cap less 1 kW, refused under a claimed limit 500 kW over the cap, and refused
--   when the limit is a string. V3: the helper answers '{}' for a run with no dials and for an L2 stall. V4: the dial,
--   the grants, the corrected notes, the sweep and its cell.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. No canon cell sets dc_power_sharing or dc_power_managed, so no
--   canon context ever carries managed_limit_kw; V1 proves each changed body equal to its pre-image without its
--   insertion.
--
-- ROLLBACK: EXECUTE each `definition` in ottoq_schema_snapshots WHERE label = '0729_pre' AND object_kind = 'function';
--   DROP FUNCTION twin.ottoq_sim_dc_managed_context(uuid, timestamptz, text);
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'dc_power_managed';
--   before the sweep has run: DELETE its cell and sweep rows; once it has run, its arm is evidence and stays.
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0729_a_site_that_divides_its_power_is_judged_by_the_limit_it_holds'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0729 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies read, 0726-0728 applied, the dial and the helper absent ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_eval_en_001_grid_capacity(text,uuid,jsonb,jsonb)'))
     IS DISTINCT FROM '696445a7f0e8f991f55bbfed188f49f3' THEN
    RAISE EXCEPTION '0729 P1: ottoq_eval_en_001_grid_capacity is not the body read on 2026-10-17 (md5 696445a7)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('twin.ottoq_sim_dc_pool_plan(uuid,timestamp with time zone,bigint)'))
     IS DISTINCT FROM '3d224cf3ac43dc77b7cb68e6e762327e' THEN
    RAISE EXCEPTION '0729 P1: twin.ottoq_sim_dc_pool_plan is not 0726''s body (md5 3d224cf3)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamp with time zone)'))
     IS DISTINCT FROM '5a9a9960af6c8d40bee32b20ff790a4d' THEN
    RAISE EXCEPTION '0729 P1: twin.ottoq_sim_start_charge_session is not the body read on 2026-10-17 (md5 5a9a9960)';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_cert_lineage
       WHERE name IN ('0726_a_shared_power_cabinet_divides_its_power_and_the_twin_can_model_one',
                      '0727_the_site_power_gate_can_read_the_meter_instead_of_guessing',
                      '0728_forty_robotic_chargers_on_todays_service_through_shared_cabinets')) <> 3
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_site_buildouts WHERE buildout_code = 'dcfc40_cab2400') THEN
    RAISE EXCEPTION '0729 P1: 0726, 0727 and 0728 are not all applied';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'dc_power_managed')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'dc_power_managed')
     OR to_regprocedure('twin.ottoq_sim_dc_managed_context(uuid,timestamp with time zone,text)') IS NOT NULL THEN
    RAISE EXCEPTION '0729 P1: dc_power_managed or its helper already exists';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'dcfc40_managed_normal_2026_10_17') THEN
    RAISE EXCEPTION '0729 P2: already applied';
  END IF;
END $once$;

-- ── the pre-images ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0729_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_eval_en_001_grid_capacity(text,uuid,jsonb,jsonb)'::regprocedure,
                 'twin.ottoq_sim_dc_pool_plan(uuid,timestamp with time zone,bigint)'::regprocedure,
                 'twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamp with time zone)'::regprocedure);

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('dc_power_managed',
        '0729: with dc_power_sharing 1, the test day''s fast chargers sit behind a site controller that holds every '
        'charge at the shield''s engineering cap (dcfc_max_concurrent_kw less the depot''s safety margin, less the L2 '
        'load), and the charge start''s probe tells EN.001 that limit, so a new car is judged as taking a share of it '
        'rather than adding its rating. 0 = the cabinets share up to dcfc_max_concurrent_kw and EN.001 adds the car''s '
        'rating to the meter (0726). Decides only whether a start is refused; never stops, slows or shortens a charge. '
        'Research days only.',
        0, 0, 1, 'twin.ottoq_sim_dc_pool_plan, twin.ottoq_sim_start_charge_session, ottoq_eval_en_001_grid_capacity',
        false);

-- ── (c) the limit the controller holds, for the probe ──
CREATE OR REPLACE FUNCTION twin.ottoq_sim_dc_managed_context(p_sim_run_id uuid, p_sim_clock_now timestamptz,
                                                              p_stall_type text)
RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path = twin, ottoq, public, extensions
AS $fn$
-- 0729: '{}' unless the run sets both dc_power_sharing and dc_power_managed and the stall is a fast charger; then the
-- limit the site controller holds this tick, the plan's pool plus its L2 demand, which is the most the site meter can
-- read while it holds. '{}' on any error: the charge start's probe skips the whole shield if anything in it raises, so
-- a failure here must leave the start judged by EN.001's own sum, never unjudged.
DECLARE v_plan jsonb; v_seed bigint;
BEGIN
  IF p_stall_type IS DISTINCT FROM 'dcfc'
     OR COALESCE(public.ottoq_policy_get(p_sim_run_id, 'dc_power_sharing', 0), 0) < 1
     OR COALESCE(public.ottoq_policy_get(p_sim_run_id, 'dc_power_managed', 0), 0) < 1 THEN
    RETURN '{}'::jsonb;
  END IF;
  v_seed := abs(hashtextextended(COALESCE((SELECT r.random_seed::text FROM public.ottoq_sim_runs r
                                            WHERE r.sim_run_id = p_sim_run_id), '42'), 42));
  v_plan := twin.ottoq_sim_dc_pool_plan(p_sim_run_id, p_sim_clock_now, v_seed);
  IF jsonb_typeof(v_plan -> 'pool_kw') IS DISTINCT FROM 'number' THEN
    RETURN '{}'::jsonb;
  END IF;
  RETURN jsonb_build_object(
    'managed_limit_kw', round((v_plan ->> 'pool_kw')::numeric + COALESCE((v_plan ->> 'l2_demand_kw')::numeric, 0), 1),
    'managed_by', 'twin_dc_pool');
EXCEPTION WHEN OTHERS THEN
  RETURN '{}'::jsonb;
END
$fn$;

REVOKE ALL ON FUNCTION twin.ottoq_sim_dc_managed_context(uuid, timestamptz, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION twin.ottoq_sim_dc_managed_context(uuid, timestamptz, text) TO service_role;

-- ══ (b) (d) (e): one anchored insertion in each of three bodies, each anchor once ══════════════════════════════════════
CREATE TEMP TABLE _0729_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0729_patch VALUES
(1, 'twin.ottoq_sim_dc_pool_plan(uuid,timestamp with time zone,bigint)'::regprocedure,
$old$  SELECT d.dcfc_max_concurrent_kw INTO v_dc_cap FROM public.depots d WHERE d.id = v_depot;
$old$,
$new$  SELECT d.dcfc_max_concurrent_kw INTO v_dc_cap FROM public.depots d WHERE d.id = v_depot;
  -- 0729: under dc_power_managed a site controller holds every charge at the engineering cap EN.001 judges against
  -- (the cabinets' rating less the depot's safety margin), so the fast chargers' share of it is that cap less this
  -- tick's L2, which the rule counts against the same cap
  IF COALESCE(public.ottoq_policy_get(p_sim_run_id, 'dc_power_managed', 0), 0) >= 1 AND v_dc_cap IS NOT NULL THEN
    SELECT GREATEST(0, v_dc_cap * (1 - COALESCE(d.dcfc_safety_margin_pct, 10.0) / 100.0) - v_l2_sum) INTO v_dc_cap
      FROM public.depots d WHERE d.id = v_depot;
  END IF;
$new$),
(2, 'twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamp with time zone)'::regprocedure,
$old$                                   'requested_kw',  LEAST(v_charger.max_kw, v_vehicle.inlet_max_kw),
                                   'now_ts',        v_clock::text),
$old$,
$new$                                   'requested_kw',  LEAST(v_charger.max_kw, v_vehicle.inlet_max_kw),
                                   'now_ts',        v_clock::text)
                                 || twin.ottoq_sim_dc_managed_context(p_sim_run_id, v_clock, v_stall.stall_type::text),  -- 0729
$new$),
(3, 'public.ottoq_eval_en_001_grid_capacity(text,uuid,jsonb,jsonb)'::regprocedure,
$old$  v_after_kw := v_current_kw + v_request_kw;
$old$,
$new$  v_after_kw := v_current_kw + v_request_kw;
  -- 0729: A SITE THAT DIVIDES ITS POWER. When the context carries the limit a site controller holds the chargers at
  -- (managed_limit_kw), a new car takes a share of that limit instead of adding its rating to it: the aggregate after
  -- the start is the lower of the sum and the limit, and never below what the meter already reads. A limit claimed above
  -- the engineering cap buys nothing past it, and a site already over the cap still reads over it.
  IF jsonb_typeof(p_context -> 'managed_limit_kw') = 'number' THEN
    v_after_kw := LEAST(v_after_kw, GREATEST(v_current_kw, (p_context ->> 'managed_limit_kw')::numeric));
  END IF;
$new$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0729_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(p.fn);
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0729: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(p.fn) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0729: % is not stored as patched', p.fn;
    END IF;
  END LOOP;
END $patch$;

-- ── (f) the build-outs' notes on what binds ──
UPDATE public.ottoq_site_buildouts
   SET basis = jsonb_set(basis, '{enforced}', to_jsonb(
         'service_max_kw at admission (0132 via ottoq_ev_charge_allowance_kw), and dcfc_max_concurrent_kw x (1 - the '
         'depot''s safety margin) at the charge start, by the shield (EN.001: the site meter plus the car''s rating; '
         'charge_session_start enforcing since 0428); no power sharing unless the run sets dc_power_sharing (0726). '
         'CORRECTED by 0729: 0724''s note denied that the cabinet limit binds anywhere (db/checks/0451 §2 (c)).'::text))
 WHERE basis ->> 'enforced' ILIKE '%never enforced%';

-- ── (g) the sweep ──
INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority,
        arm_budget_s, run_after, notes)
SELECT 'dcfc40_managed_normal_2026_10_17',
       'Forty robotic chargers on a normal day behind a site controller that holds them at the shield''s cap',
       v.depot_id, 'normal_day', v.sim_start, 144, v.sim_min_per_tick, v.seeds[1:1], 0, 15, 5400, now(),
       '0729: 0728''s dcfc40_cab2400 with dc_power_managed 1: the pool held at the engineering cap and the shield told '
       'that limit, against 0728''s dcfc40_cab2400.shared, which counts each new car''s rating on top of the meter. '
       'normal_day from 6 AM CT for 12 hours at 5 sim-minutes a tick, value_2026_09_30''s first seed.'
  FROM public.ottoq_throughput_sweeps v WHERE v.sweep_code = 'value_2026_09_30';

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc40_cab2400.managed', 1, 'otto_q', 'dcfc40_cab2400',
       '{"deploy_peak_fraction": 0.90, "dc_power_sharing": 1, "dc_power_managed": 1, "enforce_site_charge_cap": 0}'::jsonb
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'dcfc40_managed_normal_2026_10_17';

-- ── V1: each body less its 0729 insertion is its pre-image ──
DO $v1$
DECLARE p record; v_body text; v_want text;
BEGIN
  FOR p IN SELECT * FROM _0729_patch ORDER BY seq LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = p.fn;
    v_body := replace(v_body, p.c_new, p.c_old);
    v_want := CASE p.seq WHEN 1 THEN '3d224cf3ac43dc77b7cb68e6e762327e'
                         WHEN 2 THEN '5a9a9960af6c8d40bee32b20ff790a4d'
                         ELSE '696445a7f0e8f991f55bbfed188f49f3' END;
    IF md5(v_body) IS DISTINCT FROM v_want THEN
      RAISE EXCEPTION '0729 V1: % less its insertion is not its pre-image (md5 %)', p.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── V2: EN.001 on synthetic contexts at the twin depot ──
DO $v2$
DECLARE
  v_depot uuid := '11111111-1111-1111-1111-111111111111';
  v_now   timestamptz := now();
  v_cap   numeric; v_cur numeric; v_req numeric; r public.ottoq_rule_result; v_base jsonb;
BEGIN
  SELECT d.dcfc_max_concurrent_kw * (1 - COALESCE(d.dcfc_safety_margin_pct, 10.0) / 100.0) INTO v_cap
    FROM public.depots d WHERE d.id = v_depot;
  v_cur := public.ottoq_depot_current_demand_kw(v_depot, v_now);
  IF v_cap IS NULL OR v_cur >= v_cap - 1 THEN
    RAISE EXCEPTION '0729 V2: the twin depot has no cabinet cap, or its meter (% kW) is already at the cap (% kW)', v_cur, v_cap;
  END IF;
  v_req  := v_cap + 1 - v_cur;                               -- the sum lands 1 kW over the cap
  v_base := jsonb_build_object('depot_id', v_depot::text, 'requested_kw', v_req, 'now_ts', v_now::text);
  r := public.ottoq_eval_en_001_grid_capacity('stall', NULL, v_base, '{}'::jsonb);
  IF r.passed THEN
    RAISE EXCEPTION '0729 V2: without a managed limit the over-cap start passed: %', r.reason;
  END IF;
  r := public.ottoq_eval_en_001_grid_capacity('stall', NULL, v_base || jsonb_build_object('managed_limit_kw', v_cap - 1), '{}'::jsonb);
  IF NOT r.passed OR (r.payload ->> 'after_kw')::numeric IS DISTINCT FROM v_cap - 1 THEN
    RAISE EXCEPTION '0729 V2: under a limit 1 kW below the cap the start did not pass at the limit: % %', r.reason, r.payload;
  END IF;
  r := public.ottoq_eval_en_001_grid_capacity('stall', NULL, v_base || jsonb_build_object('managed_limit_kw', v_cap + 500), '{}'::jsonb);
  IF r.passed THEN
    RAISE EXCEPTION '0729 V2: a limit claimed over the cap bought a pass: %', r.reason;
  END IF;
  r := public.ottoq_eval_en_001_grid_capacity('stall', NULL, v_base || jsonb_build_object('managed_limit_kw', (v_cap - 1)::text), '{}'::jsonb);
  IF r.passed THEN
    RAISE EXCEPTION '0729 V2: a limit given as a string was read: %', r.reason;
  END IF;
END $v2$;

-- ── V3: the helper answers nothing for a run without the dials, or for an L2 stall ──
DO $v3$
BEGIN
  IF twin.ottoq_sim_dc_managed_context(gen_random_uuid(), now(), 'dcfc') <> '{}'::jsonb
     OR twin.ottoq_sim_dc_managed_context(gen_random_uuid(), now(), 'l2') <> '{}'::jsonb
     OR twin.ottoq_sim_dc_managed_context(NULL, NULL, NULL) <> '{}'::jsonb THEN
    RAISE EXCEPTION '0729 V3: the helper answered a limit for a run that sets no dial';
  END IF;
END $v3$;

-- ── V4: the dial, the grants, the notes, the sweep ──
DO $v4$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'dc_power_managed'
                  AND default_value = 0 AND min_value = 0 AND max_value = 1 AND NOT agent_writable)
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'dc_power_managed') THEN
    RAISE EXCEPTION '0729 V4: dc_power_managed is not catalogued 0..1 default 0 with no row setting it';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_sim_dc_managed_context(uuid,timestamp with time zone,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'twin.ottoq_sim_dc_managed_context(uuid,timestamp with time zone,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'twin.ottoq_sim_dc_managed_context(uuid,timestamp with time zone,text)', 'EXECUTE') THEN
    RAISE EXCEPTION '0729 V4: the helper''s grants are not postgres and service_role only';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_site_buildouts WHERE basis ->> 'enforced' ILIKE '%never enforced%') THEN
    RAISE EXCEPTION '0729 V4: a build-out still says the cabinet limit is never enforced';
  END IF;
  IF (SELECT row(s.scenario, s.priority, cardinality(s.seeds), s.ticks * s.sim_min_per_tick, count(c.*))
        FROM public.ottoq_throughput_sweeps s LEFT JOIN public.ottoq_throughput_sweep_cells c USING (sweep_id)
       WHERE s.sweep_code = 'dcfc40_managed_normal_2026_10_17'
       GROUP BY s.scenario, s.priority, s.seeds, s.ticks, s.sim_min_per_tick)
     IS DISTINCT FROM row('normal_day'::text, 15, 1, 720::numeric, 1::bigint) THEN
    RAISE EXCEPTION '0729 V4: the sweep is not normal_day, priority 15, one seed, 12 hours, one cell';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id),
                    jsonb_each_text(c.fixed_params) f
              WHERE s.sweep_code = 'dcfc40_managed_normal_2026_10_17'
                AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                                   AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                                   AND (k.max_value IS NULL OR f.value::numeric <= k.max_value))) THEN
    RAISE EXCEPTION '0729 V4: the cell sets a dial the arm would refuse';
  END IF;
END $v4$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0729_a_site_that_divides_its_power_is_judged_by_the_limit_it_holds', false, false,
  'Dial dc_power_managed (default 0) and a twin helper; one guarded insertion in each of the pool plan, the charge '
  'start and EN.001''s evaluator, acting only when a run sets dc_power_sharing and dc_power_managed: the pool is held at '
  'the engineering cap and EN.001 judges a start against that limit. V1 proves each body less its insertion is its '
  'pre-image; no canon cell sets either dial, so no canon context carries managed_limit_kw. Plus three build-out notes '
  'corrected and one sweep (dcfc40_managed_normal_2026_10_17), read only by the sweep runner.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
