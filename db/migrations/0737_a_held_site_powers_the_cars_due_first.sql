-- migration-version: 20261017164907
-- migration-name:    a_held_site_powers_the_cars_due_first
--
-- 0737  **A held site powers the cars due first (db/checks/0451 §10 point 5, the frontier).** On a test day whose fast
--       chargers share one DC pool (0726), the pool is divided by need instead of evenly: each fast charge whose car
--       has a due time gets its full demand, earliest due first, while the pool lasts, and the charges with no due
--       share what is left evenly, as before. Every charge still runs to its target (rule 9); a slower charge is
--       queueing, never a shorter charge. Dial-gated, default off. In production this is the forward charging profile
--       OTTO-Q would publish to the site controller (CLAUDE.md 2.5's power publication boundary); in the twin the pool
--       plan stands for that controller.
--
-- ══ §1 WHY ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   0726's pool is water-filled: every fast charge gets the lesser of its demand and an equal share. That is fair, and
--   it is blind to time. On arm 85 (forty posts on today's service, held at 2,160 kW by 0729, normal day, seed 1) the
--   pool bound through the 6 AM opening, and 4 of 66 immediate dispatches were on time against 8 of 72 with the grid
--   grown (arm 84): a held site gives the cars with a due the same power as the cars with none. Earliest due first is
--   the textbook answer for the latest a car can be on one shared resource. The question the arm answers is what it buys
--   the due cars, and what it costs the others, on this depot.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) dial `dc_power_by_need`, 0..1, default 0, not agent-writable. Acts only where dc_power_sharing divides a pool.
--   (b) twin.ottoq_sim_dc_pool_shares_by_need(run, demand, pool): the charges whose car's open visit in this run has a
--       dispatch_due_at, earliest due first (then by session id), each given the lesser of its demand and what is left;
--       the rest water-filled over what remains by 0726's own twin.ottoq_sim_dc_pool_shares. Total, never above the
--       pool; every charge listed; a charge with no due gets exactly 0726's share of the remainder.
--   (c) twin.ottoq_sim_dc_pool_plan, its last expression: with the dial on, (b) divides the pool; off, 0726's shares,
--       the same call as before. The pool, the demand and every other key are unchanged, so 0729's managed context and
--       0733's first reading, which read the pool and not the shares, are unchanged.
--   (d) sweep `byneed_normal_2026_10_17`: arm 85's cell plus this dial, normal_day, value_2026_09_30's first seed,
--       priority 16, after 0732's seeds, paired with arm 85.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the pool plan and 0726's shares are the bodies read on 2026-10-17 (md5 6afd8ee2,
--   864684e0), 0736 applied, nothing of this file present. P2: not already applied. V1: the plan's body with its new
--   expression read back as the old is its pre-image. V2: (b) on hand-made demand: no due, exactly 0726's shares; two
--   due charges ahead of two without, the earlier due served first and in full, the rest water-filled, the total the
--   pool; a pool above demand, every charge its demand. V3: the dial, the grants, the sweep and its cell.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: no certification arm, canon cell or dial experiment sets
--   dc_power_by_need, and with it 0 the plan calls 0726's shares as it did.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0737_pre'; DROP FUNCTION
--   twin.ottoq_sim_dc_pool_shares_by_need(uuid, jsonb, numeric); before the sweep has run, DELETE its cell and sweep
--   rows (once it has run its arm is evidence and stays); DELETE the dial's catalog row once no params row names it;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0737_a_held_site_powers_the_cars_due_first'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0737 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies read, 0736 applied, nothing of this file present ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('twin.ottoq_sim_dc_pool_plan(uuid,timestamp with time zone,bigint)'))
     IS DISTINCT FROM '6afd8ee25b35b580eb491cd94e252c3a' THEN
    RAISE EXCEPTION '0737 P1: twin.ottoq_sim_dc_pool_plan is not 0729''s body (md5 6afd8ee2)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('twin.ottoq_sim_dc_pool_shares(jsonb,numeric)'))
     IS DISTINCT FROM '864684e0f91776c1dde33710089e7b51' THEN
    RAISE EXCEPTION '0737 P1: twin.ottoq_sim_dc_pool_shares is not 0726''s body (md5 864684e0)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0736_a_realistic_promise_at_arrival_and_its_grade') THEN
    RAISE EXCEPTION '0737 P1: 0736 is not applied';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'dc_power_by_need')
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'dc_power_by_need')
     OR to_regprocedure('twin.ottoq_sim_dc_pool_shares_by_need(uuid,jsonb,numeric)') IS NOT NULL THEN
    RAISE EXCEPTION '0737 P1: dc_power_by_need or its function already exists';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'byneed_normal_2026_10_17') THEN
    RAISE EXCEPTION '0737 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0737_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_dc_pool_plan(uuid,timestamp with time zone,bigint)'::regprocedure;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('dc_power_by_need',
        '0737: with dc_power_sharing 1, a bound DC pool is divided by need: each fast charge whose car has a due time '
        'gets its full demand, earliest due first, while the pool lasts, and the charges with no due share the rest '
        'evenly (0726). 0 = every charge gets an equal share (0726). Every charge still runs to its target; a slower '
        'charge is queueing, never a shorter charge (rule 9). Research days only.',
        0, 0, 1, 'twin.ottoq_sim_dc_pool_plan, twin.ottoq_sim_dc_pool_shares_by_need', false);

-- ── (b) the pool divided by need ──
CREATE OR REPLACE FUNCTION twin.ottoq_sim_dc_pool_shares_by_need(p_sim_run_id uuid, p_demand jsonb, p_pool_kw numeric)
RETURNS jsonb
LANGUAGE plpgsql STABLE
SET search_path = twin, ottoq, public, extensions
AS $fn$
-- 0737: p_demand is {session id: kW} as twin.ottoq_sim_dc_pool_plan builds it. Each charge whose car's open visit in
-- this run has a dispatch_due_at gets the lesser of its demand and what is left, earliest due first (then by session
-- id); the others are water-filled over what remains by 0726's twin.ottoq_sim_dc_pool_shares. Every charge listed;
-- total never above the pool.
DECLARE r record; v_left numeric; v_out jsonb := '{}'::jsonb; v_rest jsonb := '{}'::jsonb; v_g numeric;
BEGIN
  IF p_demand IS NULL OR p_demand = '{}'::jsonb THEN
    RETURN '{}'::jsonb;
  END IF;
  v_left := GREATEST(0, COALESCE(p_pool_kw, 0));
  FOR r IN
    SELECT d.k, d.dem, (SELECT vn.dispatch_due_at
                          FROM public.ocpp_sessions cs
                          JOIN public.ottoq_visit_needs vn ON vn.vehicle_id = cs.vehicle_id
                         WHERE cs.id = d.sid AND vn.sim_run_id IS NOT DISTINCT FROM p_sim_run_id
                           AND vn.status IN ('open', 'in_progress')
                         ORDER BY vn.arrived_at DESC NULLS LAST, vn.created_at DESC, vn.visit_id DESC LIMIT 1) AS due_at
      FROM (SELECT e.key AS k, GREATEST(0, COALESCE(e.value::numeric, 0)) AS dem,
                   CASE WHEN e.key ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN e.key::uuid END AS sid
              FROM jsonb_each_text(p_demand) e) d
     ORDER BY 3 ASC NULLS LAST, d.k
  LOOP
    IF r.due_at IS NOT NULL THEN
      v_g := LEAST(r.dem, v_left);
      v_out := v_out || jsonb_build_object(r.k, v_g);
      v_left := v_left - v_g;
    ELSE
      v_rest := v_rest || jsonb_build_object(r.k, r.dem);
    END IF;
  END LOOP;
  RETURN v_out || twin.ottoq_sim_dc_pool_shares(v_rest, v_left);
END
$fn$;

REVOKE ALL ON FUNCTION twin.ottoq_sim_dc_pool_shares_by_need(uuid, jsonb, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION twin.ottoq_sim_dc_pool_shares_by_need(uuid, jsonb, numeric) TO service_role;

-- ══ (c): the plan's last expression, the anchor once ═════════════════════════════════════════════════════════════════
CREATE TEMP TABLE _0737_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0737_patch VALUES
(1, 'twin.ottoq_sim_dc_pool_plan(uuid,timestamp with time zone,bigint)'::regprocedure,
$old$ELSE twin.ottoq_sim_dc_pool_shares(v_dc, v_pool) END);$old$,
$new$ELSE CASE WHEN COALESCE(public.ottoq_policy_get(p_sim_run_id, 'dc_power_by_need', 0), 0) >= 1   -- 0737
                             THEN twin.ottoq_sim_dc_pool_shares_by_need(p_sim_run_id, v_dc, v_pool)
                             ELSE twin.ottoq_sim_dc_pool_shares(v_dc, v_pool) END END);$new$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0737_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(p.fn);
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0737: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(p.fn) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0737: % is not stored as patched', p.fn;
    END IF;
  END LOOP;
END $patch$;

-- ── (d) the sweep that measures it, paired with arm 85 ──
INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority,
        arm_budget_s, run_after, notes, created_at)
SELECT 'byneed_normal_2026_10_17',
       'A held site powers the cars due first: forty posts held at their limit, the pool divided by need',
       v.depot_id, 'normal_day', v.sim_start, 144, v.sim_min_per_tick, v.seeds[1:1], 0, 16, 5400, now(),
       '0737: arm 85''s cell (dcfc40_cab2400.managed, 0729) with dc_power_by_need 1, on normal_day and '
       'value_2026_09_30''s first seed, so the cars with a due time get their full demand, earliest due first, while '
       'the held pool lasts. Paired with arm 85 (the pool shared evenly).',
       clock_timestamp()
  FROM public.ottoq_throughput_sweeps v WHERE v.sweep_code = 'value_2026_09_30';

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc40_cab2400.managed.by_need', 1, 'otto_q', 'dcfc40_cab2400',
       '{"deploy_peak_fraction": 0.90, "dc_power_sharing": 1, "dc_power_managed": 1, "enforce_site_charge_cap": 0, "dc_power_by_need": 1}'::jsonb
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'byneed_normal_2026_10_17';

-- ── V1: the plan's body with its new expression read back as the old is its pre-image ──
DO $v1$
DECLARE p record; v_body text;
BEGIN
  FOR p IN SELECT * FROM _0737_patch ORDER BY seq LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = p.fn;
    v_body := replace(v_body, p.c_new, p.c_old);
    IF md5(v_body) IS DISTINCT FROM '6afd8ee25b35b580eb491cd94e252c3a' THEN
      RAISE EXCEPTION '0737 V1: % read back is not its pre-image (md5 %)', p.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── V2: the division on hand-made demand (session ids that exist nowhere have no due) ──
DO $v2$
DECLARE
  v_run uuid := 'e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd';
  v_dem jsonb := '{"a": 300, "b": 120, "c": 200, "d": 50}'::jsonb;
  v_even jsonb; v_need jsonb; v_s1 uuid; v_s2 uuid; v_car1 uuid; v_car2 uuid; v_tot numeric; v_mix jsonb;
BEGIN
  -- no charge has a due: exactly 0726's shares
  v_even := twin.ottoq_sim_dc_pool_shares(v_dem, 400);
  v_need := twin.ottoq_sim_dc_pool_shares_by_need(v_run, v_dem, 400);
  IF v_need IS DISTINCT FROM v_even THEN
    RAISE EXCEPTION '0737 V2: with no due, by need is % and not 0726''s %', v_need, v_even;
  END IF;
  -- a pool above the demand: every charge its demand
  IF twin.ottoq_sim_dc_pool_shares_by_need(v_run, v_dem, 1000) IS DISTINCT FROM twin.ottoq_sim_dc_pool_shares(v_dem, 1000) THEN
    RAISE EXCEPTION '0737 V2: a pool above demand did not give every charge its demand';
  END IF;
  -- two charges with a due ahead of two without, on a rolled-back sub-block: two of arm 83's sessions, of two different
  -- cars, whose cars are given an open visit with a due (the sessions themselves are not touched)
  SELECT s.id, s.vehicle_id INTO v_s1, v_car1 FROM public.ocpp_sessions s
   WHERE s.sim_run_id = v_run ORDER BY s.vehicle_id, s.id LIMIT 1;
  SELECT s.id, s.vehicle_id INTO v_s2, v_car2 FROM public.ocpp_sessions s
   WHERE s.sim_run_id = v_run AND s.vehicle_id <> v_car1 ORDER BY s.vehicle_id, s.id LIMIT 1;
  IF v_s1 IS NULL OR v_s2 IS NULL THEN
    RAISE EXCEPTION '0737 V2: arm 83''s run has no two sessions of two cars to test with';
  END IF;
  BEGIN
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, urgency, dispatch_due_at,
                                          target_soc, atoms, status, source)
    VALUES (v_car1, v_run, '11111111-1111-1111-1111-111111111111', '2026-09-01 22:00+00', '0737_v2_1', 'immediate_dispatch',
            '2026-09-01 22:45+00', 100, '[]'::jsonb, 'open', '0737_v2'),
           (v_car2, v_run, '11111111-1111-1111-1111-111111111111', '2026-09-01 22:00+00', '0737_v2_2', 'immediate_dispatch',
            '2026-09-01 22:30+00', 100, '[]'::jsonb, 'open', '0737_v2');
    v_mix := jsonb_build_object(v_s1::text, 300, v_s2::text, 120, 'c', 200, 'd', 50);
    v_need := twin.ottoq_sim_dc_pool_shares_by_need(v_run, v_mix, 400);
    RAISE EXCEPTION 'undo_0737_v2';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'undo_0737_v2' THEN RAISE; END IF;
  END;
  -- car2's due (22:30) is first: its 120 in full; then car1's 300 gets what is left of 400 (280); c and d share 0
  SELECT sum(e.value::numeric) INTO v_tot FROM jsonb_each_text(v_need) e;
  IF (v_need ->> v_s2::text)::numeric IS DISTINCT FROM 120 OR (v_need ->> v_s1::text)::numeric IS DISTINCT FROM 280
     OR (v_need ->> 'c')::numeric IS DISTINCT FROM 0 OR (v_need ->> 'd')::numeric IS DISTINCT FROM 0 OR v_tot IS DISTINCT FROM 400 THEN
    RAISE EXCEPTION '0737 V2: two due charges ahead of two without came out as % (total %)', v_need, v_tot;
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_visit_needs WHERE source = '0737_v2') THEN
    RAISE EXCEPTION '0737 V2: the rolled-back sub-block left a visit behind';
  END IF;
END $v2$;

-- ── V3: the dial, the grants, the sweep and its cell ──
DO $v3$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'dc_power_by_need'
                  AND default_value = 0 AND min_value = 0 AND max_value = 1 AND NOT agent_writable)
     OR EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'dc_power_by_need') THEN
    RAISE EXCEPTION '0737 V3: dc_power_by_need is not catalogued 0..1 default 0 with no row setting it';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_sim_dc_pool_shares_by_need(uuid,jsonb,numeric)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'twin.ottoq_sim_dc_pool_shares_by_need(uuid,jsonb,numeric)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'twin.ottoq_sim_dc_pool_shares_by_need(uuid,jsonb,numeric)', 'EXECUTE') THEN
    RAISE EXCEPTION '0737 V3: the function''s grants are not postgres and service_role only';
  END IF;
  IF (SELECT row(s.scenario, s.priority, cardinality(s.seeds), s.ticks * s.sim_min_per_tick, s.seeds[1])
        FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'byneed_normal_2026_10_17')
     IS DISTINCT FROM (SELECT row('normal_day'::text, 16, 1, 720::numeric, v.seeds[1])
                         FROM public.ottoq_throughput_sweeps v WHERE v.sweep_code = 'value_2026_09_30') THEN
    RAISE EXCEPTION '0737 V3: the sweep is not normal_day, priority 16, value_2026_09_30''s first seed, 12 hours';
  END IF;
  IF (SELECT c.fixed_params - 'dc_power_by_need' FROM public.ottoq_throughput_sweep_cells c
        JOIN public.ottoq_throughput_sweeps s USING (sweep_id) WHERE s.sweep_code = 'byneed_normal_2026_10_17')
     IS DISTINCT FROM (SELECT c.fixed_params FROM public.ottoq_throughput_sweep_cells c
                         JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                        WHERE s.sweep_code = 'dcfc40_managed_normal_2026_10_17' AND c.cell_code = 'dcfc40_cab2400.managed') THEN
    RAISE EXCEPTION '0737 V3: the cell is not arm 85''s cell plus dc_power_by_need';
  END IF;
  IF (SELECT created_at FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'byneed_normal_2026_10_17')
     <= (SELECT created_at FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'seeds23_normal_2026_10_17') THEN
    RAISE EXCEPTION '0737 V3: the sweep would run before 0732''s seeds';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0737_a_held_site_powers_the_cars_due_first', false, false,
  'Dial dc_power_by_need (default 0) and twin.ottoq_sim_dc_pool_shares_by_need; twin.ottoq_sim_dc_pool_plan''s last '
  'expression calls it under the dial and 0726''s shares otherwise (V1: read back, the pre-image). Sweep '
  'byneed_normal_2026_10_17 (arm 85''s cell plus the dial, one seed, priority 16). No certification arm, canon cell or '
  'dial experiment sets the dial.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;

-- ══ APPLIED 2026-10-17 16:49:07 UTC (11:49 AM CT), ledger version 20261017164907 ═════════════════════════════════════
--
--   Through apply_migration with the sweep window closed, P0 passing. Executable part 14,547 characters, md5
--   340a6805d7d54f8a5a67cb16151832f9, equal to the ledger's statements[1] read back. twin.ottoq_sim_dc_pool_plan is now
--   md5 34830619d8873790b83a008a139dbc05 (prosrc); twin.ottoq_sim_dc_pool_shares_by_need 7952e2a3f94a7fbbb5af32edcf0c2d51.
--   Dry-run first, on live, rolled back by a closing exception: P0-P2, the patch (anchor once) and V1-V3 passed, V2's
--   hand-made division among them (with no due, 0726's shares exactly; two dues ahead of two without, 120 kW and then
--   280 kW of a 400 kW pool, the two without nothing). The sweep was written at 16:49:07.825556 UTC, after 0732's seeds,
--   so its arm follows them: the night after next at tonight's pace.
