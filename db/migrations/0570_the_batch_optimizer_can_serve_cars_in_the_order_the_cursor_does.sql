-- migration-version: PENDING
-- migration-name:    the_batch_optimizer_can_serve_cars_in_the_order_the_cursor_does
--
-- 0570  **The batch optimizer can hand chargers out in the order the charge cursor serves cars.** (G297; research wing,
--       rule 10.) One dial, `charge_batch_order`, read by `ottoq_l2_optimize_assignments`. At 0, the default everywhere,
--       nothing changes: cars are ordered by battery alone, as always. At 1, the batch orders them the way the cursor in
--       `ottoq_decide_tick` serves them: immediate dispatch first, then the least slack, then battery. No charge is
--       shortened. The engine never sets the dial; a win is a recommendation a person ships (0540).
--
-- ══ §1 WHY (smoke arm 88e46ad3 of 0568, FINDINGS G297; CLAUDE.md rules 9 and 10) ═══════════════════════════════════════
--
--   Rule 9: when cars wait for chargers, one of the answers is better ordering of who is served next. Never shorter
--   charges.
--
--   Measured at the smoke arm's first tick (6:05 AM CT, busy_day, 20 robotic fast chargers, OTTO-Q's seat): 13 fast and
--   20 standard chargers free, 49 cars waiting. Every pass-through visit is `immediate_dispatch` with a due time 45
--   minutes after arrival, and the charge cursor serves those cars first; the per-car assigner wants a fast charger for
--   them. But the batch optimizer runs before the cursor, ranks cars by `current_soc ASC` alone, and had saved the fast
--   chargers for lower-battery cars: it proposed L2 to six urgent cars at 27-38%, and the cursor enacted those proposals
--   first. Later in the same tick, five standard cars at 45-79% that wanted L2 and found none left took the fast
--   chargers by row order. None of the nine urgent cars sent to L2 had left by 8 AM; the 8 pass-through visits that did
--   leave in the two hours were all late (p50 33 minutes).
--
--   So the two planners disagree about who is first. This dial makes the batch agree with the cursor, and the twin
--   decides whether that serves more cars (rule 10). 0548's `charge_kind_match` is a different lever and is not touched:
--   its experiment a4c7b7d0 concluded `safety_regression` (1 of 3 pairs left more returns unserved).
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `charge_batch_order` in `ottoq_policy_param_catalog`: 0 or 1, default 0, not agent-writable.
--   (b) `public.ottoq_charge_slack_min(vehicle, run, clock)`: minutes until the car's open visit is due, less the
--       minutes a fast charge to its target takes. The target is rule 9's one answer, `ottoq_effective_target_soc_at`.
--       The charge time is an estimate for ordering only: the energy to the target at 80% of the lower of the car's
--       inlet rating and 350 kW (the fastest charger any build-out has). NULL when the visit has no due time.
--   (c) `public.ottoq_l2_optimize_assignments` reads the dial once per call. Its cars' ORDER BY gains two keys in
--       front of `v.current_soc ASC, v.id`:
--         - the cursor's own first key, verbatim: the car's open visit is `immediate_dispatch`, first;
--         - then `ottoq_charge_slack_min`, least first (a car with no due time sorts after every car with one).
--       Both are `CASE WHEN v_batch_order = 1 THEN ... END`. At 0 each is NULL for every car and sorts nothing, and
--       CASE does not evaluate the subquery, so the order and the work are the ones before this file. The one added call
--       at 0 is the dial read, which writes nothing (0533's read witness is set only for a run-scoped value).
--   Not changed: the stall ORDER BY (fast first, L2 overflow), every candidate gate, the proposal, the cursor, the
--   per-car assigner, the baseline seats, 0548's dial, the charge target and the charge itself.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: no pair, recert, dial pair or sweep arm is in flight (0513's one probe). P1: the optimizer is the function
--   measured on 2026-09-29 (md5 653762a5a7f1445c8f65c763779137db of its source), and what (b) reads exists. P2: the dial
--   is not yet catalogued. Both patches match exactly once. The pre-image goes to `ottoq_schema_snapshots` as
--   '0570_pre'. V1, comment-stripped: the dial is read once and each added key is gated on it; the battery key is still
--   the last before `v.id`. The behaviour at 0 and at 1 is executed in tests/test_charge_batch_order_sql.py against
--   the live function's own source: at 0 the proposals are those the unpatched function made, byte for byte.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE, as 0548 was. The canon, the demo, every sweep arm and every other
--   experiment run the dial at its default, where the order is unchanged; the only added work at 0 is the dial read.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0570_pre'; then
--   DROP FUNCTION public.ottoq_charge_slack_min(uuid, uuid, timestamptz);
--   DELETE FROM public.ottoq_policy_params WHERE param_key = 'charge_batch_order';
--   DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'charge_batch_order';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0570_the_batch_optimizer_can_serve_cars_in_the_order_the_cursor_does'.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0570 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: the optimizer is the one measured, and what the slack reads exists ──
DO $premises$
DECLARE
  v_md5 text;
BEGIN
  SELECT md5(prosrc) INTO v_md5 FROM pg_proc
   WHERE oid = to_regprocedure('public.ottoq_l2_optimize_assignments(uuid,uuid,timestamptz)');
  IF v_md5 IS DISTINCT FROM '653762a5a7f1445c8f65c763779137db' THEN
    RAISE EXCEPTION '0570 P1: ottoq_l2_optimize_assignments is not the function measured on 2026-09-29 (md5 %)', v_md5;
  END IF;
  IF to_regprocedure('public.ottoq_effective_target_soc_at(uuid,timestamptz)') IS NULL
     OR to_regprocedure('public.ottoq_policy_get(uuid,text,numeric)') IS NULL THEN
    RAISE EXCEPTION '0570 P1: rule 9''s target function or the dial reader is missing';
  END IF;
  IF (SELECT count(*) FROM information_schema.columns
       WHERE table_schema = 'public'
         AND ((table_name = 'ottoq_visit_needs'
               AND column_name IN ('vehicle_id', 'sim_run_id', 'status', 'urgency', 'dispatch_due_at', 'created_at', 'visit_key'))
           OR (table_name = 'vehicles' AND column_name IN ('battery_capacity_kwh', 'inlet_max_kw', 'current_soc')))) <> 10 THEN
    RAISE EXCEPTION '0570 P1: the visit need or the vehicle no longer carries the columns the slack reads';
  END IF;
END $premises$;

-- ── P2: not applied already ──
DO $fresh$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'charge_batch_order') THEN
    RAISE EXCEPTION '0570 P2: charge_batch_order is already catalogued; this file has already been applied';
  END IF;
END $fresh$;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, agent_writable, affects, description)
VALUES ('charge_batch_order', 0, 1, 0, false, 'ottoq_l2_optimize_assignments',
  '0570 (G297, research wing): the order the batch optimizer hands chargers out in. 0 (the default) = by battery alone, '
  'lowest first. 1 = the order the charge cursor serves cars: immediate dispatch first, then the least slack '
  '(ottoq_charge_slack_min), then battery. Set run-scoped by a paired test; never by the engine.');

-- ── (b) the slack ──
CREATE FUNCTION public.ottoq_charge_slack_min(p_vehicle_id uuid, p_sim_run_id uuid, p_clock timestamptz)
RETURNS numeric LANGUAGE sql STABLE SET search_path = public, pg_catalog AS $fn$
  -- 0570 (G297): minutes until the car's open visit is due, less the minutes a fast charge to its target takes. An
  -- estimate for ORDERING only: the energy to rule 9's target at 80% of the lower of the car's inlet rating and 350 kW.
  -- NULL when the visit has no due time, so a car with one always sorts ahead of a car without.
  SELECT round(extract(epoch FROM (n.dispatch_due_at - p_clock)) / 60.0
               - COALESCE(v.battery_capacity_kwh, 75)
                 * GREATEST(public.ottoq_effective_target_soc_at(v.id, p_clock) - v.current_soc, 0) / 100.0
                 / (LEAST(COALESCE(v.inlet_max_kw, 150), 350) * 0.8) * 60.0, 1)
    FROM public.vehicles v
    JOIN LATERAL (SELECT vn.dispatch_due_at FROM public.ottoq_visit_needs vn
                   WHERE vn.vehicle_id = v.id AND vn.status IN ('open', 'in_progress')
                     AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                       = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                   ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1) n ON true
   WHERE v.id = p_vehicle_id AND n.dispatch_due_at IS NOT NULL
$fn$;
COMMENT ON FUNCTION public.ottoq_charge_slack_min(uuid, uuid, timestamptz) IS
'0570 (G297). Minutes until the car''s open visit is due, less the minutes a fast charge to rule 9''s target takes (at 80% of the lower of its inlet and 350 kW). For ordering only; NULL without a due time.';
REVOKE ALL ON FUNCTION public.ottoq_charge_slack_min(uuid, uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_charge_slack_min(uuid, uuid, timestamptz) TO service_role;

-- ── (c) the batch order ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0570_pre', 'function', 'public', 'ottoq_l2_optimize_assignments',
       pg_get_functiondef('public.ottoq_l2_optimize_assignments(uuid,uuid,timestamptz)'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_l2_optimize_assignments(uuid,uuid,timestamptz)'::regprocedure));

DO $patch$
DECLARE
  v_def text;
  v_old1 text := $o1$  v_used uuid[] := ARRAY[]::uuid[];
BEGIN
$o1$;
  v_new1 text := $n1$  v_used uuid[] := ARRAY[]::uuid[];
  v_batch_order int;   /* 0570 (G297) */
BEGIN
  /* 0570 (G297, research wing): the order this batch hands chargers out in. 0, the default, is by battery alone, as it
     always was; 1 is the order the charge cursor serves cars. Read once per call; a run-scoped value is set only by a
     paired test. */
  v_batch_order := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'charge_batch_order', 0), 0)::int;
$n1$;
  v_old2 text := $o2$     ORDER BY v.current_soc ASC, v.id              -- urgency: most depleted vehicle picks first$o2$;
  v_new2 text := $n2$     ORDER BY
       /* 0570 (G297): at charge_batch_order = 1, the cursor's own first key (ottoq_decide_tick's charge cursor, verbatim)
          and then the least slack, so the batch saves the fast chargers for the cars the cursor will serve first. At 0
          both keys are NULL for every car and sort nothing, and CASE does not run their subqueries. */
       CASE WHEN v_batch_order = 1 THEN
         COALESCE((SELECT vn.urgency = 'immediate_dispatch' FROM ottoq_visit_needs vn
                    WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                      AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                        = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                    ORDER BY vn.created_at DESC, vn.visit_key DESC LIMIT 1), false) END DESC NULLS LAST,
       CASE WHEN v_batch_order = 1 THEN public.ottoq_charge_slack_min(v.id, p_sim_run_id, p_sim_clock) END ASC NULLS LAST,
       v.current_soc ASC, v.id              -- urgency: most depleted vehicle picks first$n2$;
  n1 int; n2 int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_l2_optimize_assignments(uuid,uuid,timestamptz)'::regprocedure);
  n1 := (length(v_def) - length(replace(v_def, v_old1, ''))) / length(v_old1);
  n2 := (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2);
  IF n1 <> 1 OR n2 <> 1 THEN
    RAISE EXCEPTION '0570: the patches matched % and % times, not once each', n1, n2;
  END IF;
  EXECUTE replace(replace(v_def, v_old1, v_new1), v_old2, v_new2);
END $patch$;

-- ── V1: the dial is read once, each added key is gated on it, and battery is still the last key before v.id ──
DO $verify$
DECLARE
  v_src text;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src
    FROM pg_proc WHERE oid = 'public.ottoq_l2_optimize_assignments(uuid,uuid,timestamptz)'::regprocedure;
  IF (length(v_src) - length(replace(v_src, '''charge_batch_order''', ''))) / length('''charge_batch_order''') <> 1
     OR (length(v_src) - length(replace(v_src, 'CASE WHEN v_batch_order = 1 THEN', ''))) / length('CASE WHEN v_batch_order = 1 THEN') <> 2
     OR v_src !~ 'ottoq_charge_slack_min\(v\.id, p_sim_run_id, p_sim_clock\) END ASC NULLS LAST,\s+v\.current_soc ASC, v\.id'
     OR v_src !~ 'ORDER BY\s+CASE WHEN v_batch_order = 1 THEN\s+COALESCE\(\(SELECT vn\.urgency = ''immediate_dispatch''' THEN
    RAISE EXCEPTION '0570 V1: the batch order is not as intended';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'charge_batch_order'
                    AND min_value = 0 AND max_value = 1 AND default_value = 0 AND NOT agent_writable) THEN
    RAISE EXCEPTION '0570 V1: the dial is not catalogued as declared';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params WHERE param_key = 'charge_batch_order') THEN
    RAISE EXCEPTION '0570 V1: the dial is set somewhere; it must start at its default everywhere';
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0570_the_batch_optimizer_can_serve_cars_in_the_order_the_cursor_does', false, false,
  'A research dial (charge_batch_order, default 0) read by the batch optimizer, and the slack it orders by at 1. At 0 '
  'both added ORDER BY keys are NULL for every car, so the order and the work are unchanged; the only added call is the '
  'dial read, which writes nothing.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
