-- migration-version: PENDING
-- migration-name:    a_shared_pool_gives_a_new_car_what_it_has_spare
--
-- 0733  **A shared pool gives a new car what it has spare (G448).** On a test day whose fast chargers share one DC pool
--       (0726), a fast charge that has just started is metered at the power the pool has spare for it, at most its own
--       rate, as a site controller gives a car it has just connected until it next divides the pool. Before this the
--       twin metered it at its full unshared rate until the next tick's charge step, which runs after that tick's starts
--       are judged, so the shield and the 0132 gate read a site the cabinets could not deliver. Dial-gated, default off.
--       A TWIN FIDELITY FIX, NOT A PRODUCTION CHANGE: in this database only twin.ottoq_sim_start_charge_session creates a
--       charging session and writes its first reading; a real charger reports its own.
--
-- ══ §1 WHY (G448, db/checks/0451 §3) ══════════════════════════════════════════════════════════════════════════════════
--
--   twin.ottoq_sim_start_charge_session writes a new session's last_meter_value.power_kw as the car's unshared initial
--   rate. 0726's sharing applies only in twin.ottoq_sim_advance_charge_sessions, which skips a session in the tick it
--   starts (elapsed 0) and which both world functions call after the reconcile that starts sessions. So the site meter
--   (twin.ottoq_sim_compute_charger_load_kw, which EN.001 reads through ottoq_depot_current_demand_kw) holds every car
--   started this tick or the last at its full rate. On arm 85 (0729's managed reading) every one of its 85 refusals came
--   with the meter itself over the 2,160 kW cap: the 24 sessions started at 06:10 put it at 2,200.8 kW, and the starts
--   judged at 06:15 read the same 2,200.8 kW, because only that tick's charge step then metered the 24 at their pool
--   shares, which sum to exactly 2,160.0 kW.
--
--   Energy is not touched by any of this. The charge step meters each interval at the rate it computes then
--   (v_kwh_delta := v_rate_kw * elapsed), never at the previous reading, so a first reading feeds only what reads the
--   meter: EN.001 at charge start, the 0132 gate under 0727, and the site energy snapshots the battery plan and the
--   demand figures read.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) dial `dc_power_first_reading`, 0..1, default 0, not agent-writable. Own dial, not folded into dc_power_sharing,
--       so every shared or managed cell already run or queued (0728, 0729, 0732) keeps its meaning.
--   (b) twin.ottoq_sim_dc_first_reading_kw(run, clock, stall type, rate): the rate unchanged unless the run sets both
--       dc_power_sharing and dc_power_first_reading and the stall is a fast charger; then the lower of the rate and the
--       pool's spare, which is twin.ottoq_sim_dc_pool_plan's pool_kw (0729 holds it at the engineering cap) less what
--       this run's fast charges read on the site meter by the meter's own test of a charge drawing now. The rate
--       unchanged on any error, a NULL rate stays NULL (LEAST would otherwise drop it), and with no pool to share
--       (neither a cabinet cap nor a grid cap) the car draws its own rate.
--   (c) twin.ottoq_sim_start_charge_session, one anchored insertion after the shield block and before the session is
--       written: v_init_rate passes through (b). Off, (b) returns its argument, so the body's behaviour is unchanged.
--       Under the dial the session's first reading, its peak_power_kw and the start event's initial_rate_kw all carry
--       the first reading.
--   (d) sweep `firstreading_normal_2026_10_17`: arm 85's cell plus this dial, normal_day, value_2026_09_30's first seed,
--       priority 15 so it runs first in the next window, paired with arm 85.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the start function and the pool plan are the bodies read on 2026-10-17 (md5 bccb8cfa,
--   6afd8ee2), 0729 and 0732 applied, the dial and the helper absent. P2: not already applied. V1: the start body less
--   its insertion is its pre-image. V2: the helper leaves a rate alone for a run that sets neither dial, for a run that
--   shares its pool without this dial (arm 88's, dc_power_sharing 1), for an L2 stall and for NULLs. V3: on a
--   rolled-back sub-block that sets both dials for arm 88's run, a rate far above the pool comes back as the pool's
--   spare, re-derived here from the plan and the meter's test, and a rate inside the spare comes back unchanged. V4: the
--   dial, the grants, the sweep.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: no certification arm, canon cell or dial experiment sets
--   dc_power_first_reading, and with it 0 the start function's added line assigns v_init_rate its own value.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0733_pre'; DROP FUNCTION
--   twin.ottoq_sim_dc_first_reading_kw(uuid, timestamptz, text, numeric); before the sweep has run, DELETE its cell and
--   sweep rows (once it has run its arm is evidence and stays); DELETE the dial's catalog row once no params row names it;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0733_a_shared_pool_gives_a_new_car_what_it_has_spare'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0733 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies read, 0729 and 0732 applied, the dial and the helper absent ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamp with time zone)'))
     IS DISTINCT FROM 'bccb8cfa8ae7abd897e30add18e4f4cc' THEN
    RAISE EXCEPTION '0733 P1: twin.ottoq_sim_start_charge_session is not 0729''s body (md5 bccb8cfa)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('twin.ottoq_sim_dc_pool_plan(uuid,timestamp with time zone,bigint)'))
     IS DISTINCT FROM '6afd8ee25b35b580eb491cd94e252c3a' THEN
    RAISE EXCEPTION '0733 P1: twin.ottoq_sim_dc_pool_plan is not 0729''s body (md5 6afd8ee2)';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_cert_lineage
       WHERE name IN ('0729_a_site_that_divides_its_power_is_judged_by_the_limit_it_holds',
                      '0732_two_more_seeds_for_the_four_cells_the_recommendation_rests_on')) <> 2 THEN
    RAISE EXCEPTION '0733 P1: 0729 and 0732 are not both applied';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'dc_power_first_reading')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'dc_power_first_reading')
     OR to_regprocedure('twin.ottoq_sim_dc_first_reading_kw(uuid,timestamp with time zone,text,numeric)') IS NOT NULL THEN
    RAISE EXCEPTION '0733 P1: dc_power_first_reading or its helper already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = '7fe98840-654c-45f3-9658-366ca9fb1f5b')
     OR NOT EXISTS (SELECT 1 FROM public.site_energy_snapshots WHERE sim_run_id = '7fe98840-654c-45f3-9658-366ca9fb1f5b') THEN
    RAISE EXCEPTION '0733 P1: arm 88''s run (7fe98840), which V2 and V3 test against, is gone';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'firstreading_normal_2026_10_17') THEN
    RAISE EXCEPTION '0733 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0733_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamp with time zone)'::regprocedure;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('dc_power_first_reading',
        '0733 (G448): with dc_power_sharing 1, a fast charge that has just started is metered at the power the DC pool '
        'has spare for it, at most its own rate, as a site controller gives a car it has just connected until it next '
        'divides the pool. 0 = its first reading is its unshared rate (0726), which the site meter holds until the next '
        'tick''s charge step, after that tick''s starts have been judged against it. Changes only what the meter reads '
        'in the tick a car starts; never the energy a charge delivers, its rate after that tick, or its target. Research '
        'days only.',
        0, 0, 1, 'twin.ottoq_sim_start_charge_session, twin.ottoq_sim_dc_first_reading_kw', false);

-- ── (b) the first reading of a fast charge starting now ──
CREATE OR REPLACE FUNCTION twin.ottoq_sim_dc_first_reading_kw(p_sim_run_id uuid, p_sim_clock_now timestamptz,
                                                               p_stall_type text, p_rate_kw numeric)
RETURNS numeric
LANGUAGE plpgsql STABLE
SET search_path = twin, ottoq, public, extensions
AS $fn$
-- 0733 (G448): p_rate_kw, the car's own initial rate, unless the run sets both dc_power_sharing and
-- dc_power_first_reading and the stall is a fast charger; then the lower of that rate and what the DC pool has spare:
-- the plan's pool (0729 holds it at the engineering cap) less what this run's fast charges read on the site meter, by
-- the meter's own test of a charge drawing now (twin.ottoq_sim_compute_charger_load_kw). p_rate_kw unchanged on any
-- error, so a failure here leaves 0726's reading, never a missing one.
DECLARE v_plan jsonb; v_seed bigint; v_dc_meter numeric;
BEGIN
  IF p_rate_kw IS NULL OR p_stall_type IS DISTINCT FROM 'dcfc'
     OR COALESCE(public.ottoq_policy_get(p_sim_run_id, 'dc_power_sharing', 0), 0) < 1
     OR COALESCE(public.ottoq_policy_get(p_sim_run_id, 'dc_power_first_reading', 0), 0) < 1 THEN
    RETURN p_rate_kw;
  END IF;
  v_seed := abs(hashtextextended(COALESCE((SELECT r.random_seed::text FROM public.ottoq_sim_runs r
                                            WHERE r.sim_run_id = p_sim_run_id), '42'), 42));
  v_plan := twin.ottoq_sim_dc_pool_plan(p_sim_run_id, p_sim_clock_now, v_seed);
  IF jsonb_typeof(v_plan -> 'pool_kw') IS DISTINCT FROM 'number'
     OR (jsonb_typeof(v_plan -> 'dc_cap_kw') IS DISTINCT FROM 'number'
         AND jsonb_typeof(v_plan -> 'grid_room_kw') IS DISTINCT FROM 'number') THEN
    RETURN p_rate_kw;                            -- no pool to share: the car draws its own rate
  END IF;
  SELECT COALESCE(sum((cs.last_meter_value ->> 'power_kw')::numeric), 0) INTO v_dc_meter
    FROM public.ocpp_sessions cs JOIN public.stalls st ON st.id = cs.stall_id
   WHERE cs.sim_run_id = p_sim_run_id
     AND cs.status IN ('active'::ocpp_session_status, 'completed'::ocpp_session_status)
     AND cs.started_at <= p_sim_clock_now
     AND (cs.ended_at IS NULL OR cs.ended_at >= p_sim_clock_now)
     AND st.stall_type::text = 'dcfc';
  RETURN LEAST(p_rate_kw, GREATEST(0, (v_plan ->> 'pool_kw')::numeric - v_dc_meter));
EXCEPTION WHEN OTHERS THEN
  RETURN p_rate_kw;
END
$fn$;

REVOKE ALL ON FUNCTION twin.ottoq_sim_dc_first_reading_kw(uuid, timestamptz, text, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION twin.ottoq_sim_dc_first_reading_kw(uuid, timestamptz, text, numeric) TO service_role;

-- ══ (c): one anchored insertion in the start function, the anchor once ═══════════════════════════════════════════════
CREATE TEMP TABLE _0733_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0733_patch VALUES
(1, 'twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamp with time zone)'::regprocedure,
$old$  END;
  INSERT INTO ocpp_sessions (
$old$,
$new$  END;
  -- 0733 (G448): under a shared DC pool a new fast charge's first reading is what the pool has spare for it, at most its
  -- own rate (dial dc_power_first_reading); off, the helper returns v_init_rate unchanged. Energy is not touched: the
  -- charge step meters each interval at the rate it computes then.
  v_init_rate := twin.ottoq_sim_dc_first_reading_kw(p_sim_run_id, v_clock, v_stall.stall_type::text, v_init_rate);
  INSERT INTO ocpp_sessions (
$new$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0733_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(p.fn);
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0733: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(p.fn) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0733: % is not stored as patched', p.fn;
    END IF;
  END LOOP;
END $patch$;

-- ── (d) the sweep that measures it, paired with arm 85 ──
INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority,
        arm_budget_s, run_after, notes)
SELECT 'firstreading_normal_2026_10_17',
       'A shared pool gives a new car what it has spare: forty held at their limit, metered from the first reading',
       v.depot_id, 'normal_day', v.sim_start, 144, v.sim_min_per_tick, v.seeds[1:1], 0, 15, 5400, now(),
       '0733 (G448): arm 85''s cell (dcfc40_cab2400.managed, 0729) with dc_power_first_reading 1, on normal_day and '
       'value_2026_09_30''s first seed, so a new fast charge is metered at the pool''s spare from its first reading. '
       'Paired with arm 85, which refused 85 starts with the meter itself over the cap.'
  FROM public.ottoq_throughput_sweeps v WHERE v.sweep_code = 'value_2026_09_30';

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc40_cab2400.managed.first_reading', 1, 'otto_q', 'dcfc40_cab2400',
       '{"deploy_peak_fraction": 0.90, "dc_power_sharing": 1, "dc_power_managed": 1, "enforce_site_charge_cap": 0, "dc_power_first_reading": 1}'::jsonb
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'firstreading_normal_2026_10_17';

-- ── V1: the start body less its 0733 insertion is its pre-image ──
DO $v1$
DECLARE p record; v_body text;
BEGIN
  FOR p IN SELECT * FROM _0733_patch ORDER BY seq LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = p.fn;
    v_body := replace(v_body, p.c_new, p.c_old);
    IF md5(v_body) IS DISTINCT FROM 'bccb8cfa8ae7abd897e30add18e4f4cc' THEN
      RAISE EXCEPTION '0733 V1: % less its insertion is not its pre-image (md5 %)', p.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── V2: the helper leaves a rate alone wherever the dials do not both apply ──
DO $v2$
DECLARE v_clock timestamptz;
BEGIN
  SELECT max(e.timestamp) INTO v_clock FROM public.site_energy_snapshots e
   WHERE e.sim_run_id = '7fe98840-654c-45f3-9658-366ca9fb1f5b';
  IF twin.ottoq_sim_dc_first_reading_kw(gen_random_uuid(), now(), 'dcfc', 123.45) IS DISTINCT FROM 123.45
     OR twin.ottoq_sim_dc_first_reading_kw('7fe98840-654c-45f3-9658-366ca9fb1f5b', v_clock, 'dcfc', 123.45)
        IS DISTINCT FROM 123.45
     OR twin.ottoq_sim_dc_first_reading_kw('7fe98840-654c-45f3-9658-366ca9fb1f5b', v_clock, 'l2', 123.45)
        IS DISTINCT FROM 123.45
     OR twin.ottoq_sim_dc_first_reading_kw(NULL, NULL, NULL, 123.45) IS DISTINCT FROM 123.45
     OR twin.ottoq_sim_dc_first_reading_kw('7fe98840-654c-45f3-9658-366ca9fb1f5b', v_clock, 'dcfc', NULL) IS NOT NULL THEN
    RAISE EXCEPTION '0733 V2: the helper changed a rate it should have left alone';
  END IF;
END $v2$;

-- ── V3: with both dials, a rate above the pool comes back as its spare, and a rate inside it unchanged ──
DO $v3$
DECLARE
  v_run uuid := '7fe98840-654c-45f3-9658-366ca9fb1f5b';
  v_clock timestamptz; v_big numeric; v_small numeric; v_pool numeric; v_meter numeric; v_spare numeric;
BEGIN
  SELECT max(e.timestamp) INTO v_clock FROM public.site_energy_snapshots e WHERE e.sim_run_id = v_run;
  BEGIN
    INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
    VALUES ('run', v_run, 'dc_power_first_reading', 1, '0733_v3', now())
    ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value;
    v_big   := twin.ottoq_sim_dc_first_reading_kw(v_run, v_clock, 'dcfc', 1000000);
    v_small := twin.ottoq_sim_dc_first_reading_kw(v_run, v_clock, 'dcfc', 0.5);
    v_pool  := (twin.ottoq_sim_dc_pool_plan(v_run, v_clock,
                  abs(hashtextextended(COALESCE((SELECT r.random_seed::text FROM public.ottoq_sim_runs r
                                                  WHERE r.sim_run_id = v_run), '42'), 42))) ->> 'pool_kw')::numeric;
    SELECT COALESCE(sum((cs.last_meter_value ->> 'power_kw')::numeric), 0) INTO v_meter
      FROM public.ocpp_sessions cs JOIN public.stalls st ON st.id = cs.stall_id
     WHERE cs.sim_run_id = v_run AND cs.status IN ('active'::ocpp_session_status, 'completed'::ocpp_session_status)
       AND cs.started_at <= v_clock AND (cs.ended_at IS NULL OR cs.ended_at >= v_clock)
       AND st.stall_type::text = 'dcfc';
    RAISE EXCEPTION 'undo_0733_v3';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'undo_0733_v3' THEN RAISE; END IF;
  END;
  v_spare := GREATEST(0, v_pool - v_meter);
  IF v_pool IS NULL OR v_big IS DISTINCT FROM v_spare OR v_big >= 1000000 THEN
    RAISE EXCEPTION '0733 V3: a fast charge''s first reading under both dials is % kW, not the pool''s spare % kW (pool %, meter %)',
      v_big, v_spare, v_pool, v_meter;
  END IF;
  IF v_small IS DISTINCT FROM LEAST(0.5, v_spare) THEN
    RAISE EXCEPTION '0733 V3: a rate inside the spare did not come back unchanged (% kW, spare % kW)', v_small, v_spare;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'dc_power_first_reading') THEN
    RAISE EXCEPTION '0733 V3: the rolled-back sub-block left a dc_power_first_reading row behind';
  END IF;
END $v3$;

-- ── V4: the dial, the grants, the sweep ──
DO $v4$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'dc_power_first_reading'
                  AND default_value = 0 AND min_value = 0 AND max_value = 1 AND NOT agent_writable)
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'dc_power_first_reading') THEN
    RAISE EXCEPTION '0733 V4: dc_power_first_reading is not catalogued 0..1 default 0 with no row setting it';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_sim_dc_first_reading_kw(uuid,timestamp with time zone,text,numeric)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'twin.ottoq_sim_dc_first_reading_kw(uuid,timestamp with time zone,text,numeric)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'twin.ottoq_sim_dc_first_reading_kw(uuid,timestamp with time zone,text,numeric)', 'EXECUTE') THEN
    RAISE EXCEPTION '0733 V4: the helper''s grants are not postgres and service_role only';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamp with time zone)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamp with time zone)', 'EXECUTE') THEN
    RAISE EXCEPTION '0733 V4: the start function gained a browser grant';
  END IF;
  IF (SELECT row(s.scenario, s.priority, cardinality(s.seeds), s.ticks * s.sim_min_per_tick, count(c.*))
        FROM public.ottoq_throughput_sweeps s LEFT JOIN public.ottoq_throughput_sweep_cells c USING (sweep_id)
       WHERE s.sweep_code = 'firstreading_normal_2026_10_17'
       GROUP BY s.scenario, s.priority, s.seeds, s.ticks, s.sim_min_per_tick)
     IS DISTINCT FROM row('normal_day'::text, 15, 1, 720::numeric, 1::bigint) THEN
    RAISE EXCEPTION '0733 V4: the sweep is not normal_day, priority 15, one seed, 12 hours, one cell';
  END IF;
  IF (SELECT seeds[1] FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'firstreading_normal_2026_10_17')
     IS DISTINCT FROM (SELECT seeds[1] FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'value_2026_09_30') THEN
    RAISE EXCEPTION '0733 V4: the seed is not value_2026_09_30''s first, arm 85''s';
  END IF;
  IF (SELECT c.fixed_params - 'dc_power_first_reading' FROM public.ottoq_throughput_sweep_cells c
        JOIN public.ottoq_throughput_sweeps s USING (sweep_id) WHERE s.sweep_code = 'firstreading_normal_2026_10_17')
     IS DISTINCT FROM (SELECT c.fixed_params FROM public.ottoq_throughput_sweep_cells c
                         JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                        WHERE s.sweep_code = 'dcfc40_managed_normal_2026_10_17' AND c.cell_code = 'dcfc40_cab2400.managed') THEN
    RAISE EXCEPTION '0733 V4: the cell is not arm 85''s cell plus dc_power_first_reading';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id),
                    jsonb_each_text(c.fixed_params) f
              WHERE s.sweep_code = 'firstreading_normal_2026_10_17'
                AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                                   AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                                   AND (k.max_value IS NULL OR f.value::numeric <= k.max_value))) THEN
    RAISE EXCEPTION '0733 V4: the cell sets a dial the arm would refuse';
  END IF;
END $v4$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0733_a_shared_pool_gives_a_new_car_what_it_has_spare', false, false,
  'Dial dc_power_first_reading (default 0) and twin.ottoq_sim_dc_first_reading_kw; one anchored insertion in '
  'twin.ottoq_sim_start_charge_session that returns v_init_rate unchanged with the dial off (V1: body less insertion is '
  'its pre-image). Sweep firstreading_normal_2026_10_17 (arm 85''s cell plus the dial, one seed, priority 15). No '
  'certification arm, canon cell or dial experiment sets the dial.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
