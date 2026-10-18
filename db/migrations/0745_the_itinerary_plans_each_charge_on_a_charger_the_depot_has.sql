-- migration-version: 20261018111301
-- migration-name:    the_itinerary_plans_each_charge_on_a_charger_the_depot_has
--
-- 0745  **The itinerary plans each charge on a charger the depot has, timed on the depot's learned charge clock.** (G459)
--       The itinerary planner (public.ottoq_plan_visit_itinerary) plans a car's visit at arrival: its charge, the work that
--       runs during it, its bay services after it and its readiness check. It chooses the charge by a fixed rule, a fast
--       charge at 100 kW below 45% and an L2 at 11 kW above it, whatever chargers the depot has, and times it with the
--       physics estimate at that power. The plan is what the forward calendar books bay holds from, what the reconcile
--       reads as "still charging" (BLOCKER 1), and what the owner app says a car will be ready by (G454). Research wing,
--       rule 10: under a dial, measured in the twin, then a certified change.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-17 between 5:42 and 6:07 PM CT; db/checks/0451 queries (26)-(28)) ══════════
--
--   On forty robotic posts the depot has no L2 left, and the plan still chose L2 for every car above 45%. On arm 84 (40
--   posts, normal day, seed 1) the planner wrote 127 L2 legs for 93 cars, a mean 232 minutes long, 124 of them skipped:
--   no L2 exists, and the cars charged on the fast chargers. Against the car's real charge, a skipped L2 leg ended a mean
--   219 minutes late (median 232); on arms 85, 86 (20 posts) and 83 (the depot as built) a mean 224, 237 and 218. Every
--   leg after it was planned from its end, and the forward calendar books bay holds from those legs. In 103 of arm 84's
--   124 the plan's last leg ended within 20 minutes of the phantom L2 leg. The reconcile reads an unstarted charge leg
--   as a charge under way, and deferred the bay holds of cars standing in staging while such a leg was planned: 3-6 holds
--   a normal-day run, a mean 84-95 minutes each, and 16 on the busy day (163 minutes). For 23 of those 34 holds the leg
--   was one the depot never served (G458's mirror: there a charge ran past its plan, here the plan ran past the charge).
--   The owner app's ready-by is the latest planned end (G454), so it reads the same legs.
--
--   Rehearsed out of sample on every charge to full in last night's arms (the clock's fit 11 is of 2026-10-14; the
--   rehearsal leaves out the run's own charges, which the plan adds):
--                          charges   real mean   rule: kind right / MAE / p90 |err|   0745: kind right / MAE / p90 |err|
--     arm 84, 40 posts       234       47.8 min        39.7% / 63.0 / 172.8 min         100% / 7.9 / 19.6 min
--     arm 85, 40 managed     228       50.2            43.9% / 61.2 / 181.2             100% / 8.1 / 20.7
--     arm 86, 20 posts       200       70.0            57.5% / 67.4 / 198.4             57.5% / 43.1 / 155.8
--     arm 83, as built       172      106.0            64.5% / 69.5 / 195.1             64.5% / 52.0 / 190.0
--   On a depot with both kinds the kind is the rule's, kept on purpose: the faster kind on the clock was right only 48.8%
--   on arm 83 against the rule's 64.5% (though 69.0% on arm 86 against 57.5%), because which kind a car gets there
--   depends on the mix and the queue, and a plan made at arrival sees neither. What is left at a mixed depot is that
--   choice, not the clock (14.7 minutes as built and 9.8 at 20 posts when the kind is known).
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Dial itinerary_charge_on_clock (0..1, default 0; not agent-writable).
--   (b) public.ottoq_plan_visit_itinerary, three anchored insertions, acting only at 1:
--         - the charge is planned on the one kind of charger the car can plug into here when there is one
--           (public.ottoq_charge_kind_compatible, the stall pick's own plug test), else on the rule's kind;
--         - it is timed on the depot's learned charge clock, exactly as the kernel's line times it
--           (public.ottoq_charge_order_minutes): the clock's fit, the run's own charges up to now, the depot's fastest
--           charger of that kind, from the car's battery now to rule 9's one target (ottoq_effective_target_soc_at);
--         - with no clock answer, the physics estimate at that charger's own power; any failure leaves the rule's plan;
--         - the leg's duration_basis says which: the kind, why, the power, the target, the fit and level, the minutes' basis.
--       At 0 the leg is the rule's, byte for byte, its basis the same value.
--   (c) Sweep itinclock_normal_2026_10_17, two cells, each one arm and its partner's cell plus the dial: arm 84's
--       (dcfc40.otto_q, ord 1) and arm 83's (dcfc10.otto_q, ord 2). normal_day from 6 AM CT for 12 hours at 5
--       sim-minutes a tick, value_2026_09_30's first seed, priority 16 after 0743's and 0744's, arm budget 3,000 s.
--   Not changed: which charger the line seats a car on, how long a car charges, what it needs or when it may leave
--   (rule 9). The plan is a forecast; the line and the shield decide.
--   What it may also move, and why the arms are needed: the forward calendar books each planned leg's stall at arrival
--   (ottoq.ottoq_book_workflow_legs), as it already does for every car below 45%. With the dial, on a depot with only
--   fast chargers, a car above 45% gets a fast charger held for its planned window where its L2 leg could never be
--   booked; the line supersedes the hold when it seats the car elsewhere, and while it stands, other cars cannot take
--   that charger in that window. Whether that helps the line or holds chargers against its own order is the arms' to
--   show, beside what the plan's accuracy buys the bay holds, the reconcile and the owner app.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the planner is the body this file patches (prosrc md5 990e9481); the six functions it calls
--   exist; the dial and the sweep are absent; arm 84's and arm 83's cells are as read. P2 not already applied. Pre-image
--   to ottoq_schema_snapshots as '0745_pre'. Each anchor matches once. V1 the body less its insertions is its pre-image. V2
--   nothing planned for a run that does not exist. V3 the dial is catalogued 0..1 default 0 and not agent-writable, and
--   the sweep's two cells are arm 84's and arm 83's plus the dial. Executed in full by
--   tests/test_itinerary_charge_on_clock_sql.py on the live bodies (md5 asserted).
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. At the dial's default the planner writes what it wrote before (V1,
--   and the leg's basis is the same value), and no certification arm, canon cell or dial experiment sets the dial.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0745_pre'; if no arm has run, DELETE the
--   sweep itinclock_normal_2026_10_17 and its cells and the dial's catalog row;
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0745_the_itinerary_plans_each_charge_on_a_charger_the_depot_has'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0745 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the body read, the functions it calls, arm 84's and arm 83's cells, nothing of this file ──
DO $premises$
DECLARE f text;
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)'))
     IS DISTINCT FROM '990e9481a4917ae0d23dc78e205896aa' THEN
    RAISE EXCEPTION '0745 P1: public.ottoq_plan_visit_itinerary is not the body this file patches (md5 990e9481)';
  END IF;
  FOREACH f IN ARRAY ARRAY['public.ottoq_charge_kind_compatible(uuid,uuid,text)',
                           'public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)',
                           'public.ottoq_charge_clock_model(uuid)',
                           'public.ottoq_charge_clock_run_evidence(jsonb,uuid,timestamp with time zone)',
                           'public.ottoq_charge_clock_who(uuid,text,text,text)',
                           'public.ottoq_effective_target_soc_at(uuid,timestamp with time zone)'] LOOP
    IF to_regprocedure(f) IS NULL THEN
      RAISE EXCEPTION '0745 P1: % is missing', f;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'itinerary_charge_on_clock')
     OR EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'itinclock_normal_2026_10_17') THEN
    RAISE EXCEPTION '0745 P1: the dial or the sweep already exists';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                  WHERE s.sweep_code = 'dcfc40_power_normal_2026_10_17' AND c.cell_code = 'dcfc40.otto_q'
                    AND c.buildout_code = 'dcfc40' AND s.scenario = 'normal_day'
                    AND s.sim_start = '2026-09-01 11:00:00+00' AND s.ticks = 144 AND s.sim_min_per_tick = 5
                    AND (c.fixed_params ->> 'deploy_peak_fraction')::numeric = 0.9
                    AND c.fixed_params - 'deploy_peak_fraction' = '{}'::jsonb) THEN
    RAISE EXCEPTION '0745 P1: arm 84''s cell (dcfc40_power_normal_2026_10_17 / dcfc40.otto_q) is not as read';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                  WHERE s.sweep_code = 'dcfc40_normal_2026_10_17' AND c.cell_code = 'dcfc10.otto_q'
                    AND c.buildout_code = 'dcfc10' AND s.scenario = 'normal_day'
                    AND s.sim_start = '2026-09-01 11:00:00+00' AND s.ticks = 144 AND s.sim_min_per_tick = 5
                    AND (c.fixed_params ->> 'deploy_peak_fraction')::numeric = 0.9
                    AND c.fixed_params - 'deploy_peak_fraction' = '{}'::jsonb) THEN
    RAISE EXCEPTION '0745 P1: arm 83''s cell (dcfc40_normal_2026_10_17 / dcfc10.otto_q) is not as read';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0745_the_itinerary_plans_each_charge_on_a_charger_the_depot_has') THEN
    RAISE EXCEPTION '0745 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0745_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)'::regprocedure;

-- ── (a) the dial ──
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects,
                                               agent_writable)
VALUES ('itinerary_charge_on_clock',
        '0745 (G459): 1 = the itinerary plans a car''s charge on the one kind of charger the car can plug into at the '
        'depot when there is one (else the 45% rule''s kind) and times it on the depot''s learned charge clock, as the '
        'kernel''s line times it, to rule 9''s one target. 0 = a fast charge at 100 kW below 45% and an L2 at 11 kW above '
        'it, whatever the depot has, as before 0745. Research days only until certified.',
        0, 0, 1, 'public.ottoq_plan_visit_itinerary', false);

-- ── (b) the planner ──
CREATE TEMP TABLE _0745_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0745_patch VALUES
  -- 1: the clock plan's variables
  (1, 'public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o1$  v_fault_first boolean := false;          -- 0558 (G292)
BEGIN
$o1$,
   $n1$  v_fault_first boolean := false;          -- 0558 (G292)
  v_on_clock boolean; v_dok boolean; v_lok boolean; v_kind text; v_kind_basis text;   -- 0745 (G459)
  v_kind_kw numeric; v_ct jsonb; v_clock jsonb; v_target numeric; v_basis jsonb; v_min_rule numeric;
BEGIN
$n1$),
  -- 2: under the dial, the charge on a charger the depot has, timed on its clock
  (2, 'public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o2$    v_min := COALESCE(v_min, 25);
    v_charge_start := v_cursor;$o2$,
   $n2$    v_min := COALESCE(v_min, 25);
    -- 0745 (G459): with itinerary_charge_on_clock on, the charge is planned on a charger the depot has that the car can
    -- plug into, and timed on the depot's learned charge clock to the car's one target (rule 9), as the kernel's own line
    -- times it (ottoq_charge_order_minutes). The rule above plans a fast charge below 45% and an L2 above it, at a fixed
    -- 100 or 11 kW, whatever the depot has: at forty robotic posts and no L2 it planned 124 L2 charges for 92 cars, each
    -- ending a mean 219 minutes after the real one, and every leg, bay hold and ready-by time after them followed. A depot
    -- with both kinds keeps the rule's kind, which its line follows more often than it follows the faster kind; the clock
    -- gives the length, and the physics on the depot's own power when the clock has no answer. Any failure leaves the
    -- rule's plan.
    v_basis := jsonb_build_object('kind','flow_contract','charger_kw_assumed',v_charger_kw);
    v_on_clock := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'itinerary_charge_on_clock', 0), 0) >= 1;
    IF v_on_clock THEN
      v_min_rule := v_min;
      BEGIN
        v_dok := public.ottoq_charge_kind_compatible(p_vehicle, v_depot, 'dcfc');
        v_lok := public.ottoq_charge_kind_compatible(p_vehicle, v_depot, 'l2');
        IF v_dok AND NOT v_lok THEN
          v_kind := 'dcfc'; v_kind_basis := 'the_only_kind_the_car_can_use_here';
        ELSIF v_lok AND NOT v_dok THEN
          v_kind := 'l2'; v_kind_basis := 'the_only_kind_the_car_can_use_here';
        ELSE
          v_kind := CASE WHEN v_veh.current_soc < 45 THEN 'dcfc' ELSE 'l2' END; v_kind_basis := 'soc_rule';
        END IF;
        SELECT max(s.connector_max_kw) INTO v_kind_kw
          FROM stalls s WHERE s.depot_id = v_depot AND s.stall_type::text = v_kind;
        v_kind_kw := COALESCE(v_kind_kw, v_charger_kw);
        v_target := COALESCE(public.ottoq_effective_target_soc_at(p_vehicle, p_clock), (v_a->>'target_soc')::numeric,
                             v_visit.target_soc, public.ottoq_default_target_soc());
        v_ct := public.ottoq_charge_clock_model(v_depot);
        IF v_ct IS NOT NULL THEN
          SELECT public.ottoq_charge_clock(v_ct, v_kind,
                   public.ottoq_charge_clock_who(vh.id, vh.vehicle_class_code, vh.make, vh.model),
                   vh.battery_capacity_kwh, vh.current_soc, v_target, v_kind_kw, vh.inlet_max_kw,
                   public.ottoq_charge_clock_run_evidence(v_ct, p_sim_run_id, p_clock) -> v_kind)
            INTO v_clock FROM vehicles vh WHERE vh.id = p_vehicle;
        END IF;
        IF (v_clock ->> 'm') IS NOT NULL THEN
          v_min := GREATEST((v_clock ->> 'm')::numeric, 1);
        ELSE
          v_min := COALESCE(ottoq_estimate_charge_minutes(v_veh.current_soc, v_target, v_kind_kw, v_veh.inlet_kw,
                                                          v_veh.pack_kwh, 20, 100, 1.0), v_min_rule);
        END IF;
        v_charge_leg_type := 'charge_' || v_kind;
        v_basis := jsonb_build_object('kind','flow_contract','charger_kw_assumed',v_kind_kw,'charge_kind',v_kind,
                     'kind_basis',v_kind_basis,'target_soc',v_target,'clock_fit',v_ct ->> 'estimate_id',
                     'clock_level',v_clock ->> 'lvl',
                     'minutes_basis',CASE WHEN (v_clock ->> 'm') IS NOT NULL THEN 'charge_clock' ELSE 'physics' END,
                     'planned_by','0745');
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '0745: the clock could not plan the charge of %, the rule''s plan stands (% %)',
          p_vehicle, SQLSTATE, SQLERRM;
        v_min := v_min_rule;
        v_charge_leg_type := (CASE WHEN v_veh.current_soc < 45 THEN 'charge_dcfc' ELSE 'charge_l2' END);
        v_basis := jsonb_build_object('kind','flow_contract','charger_kw_assumed',v_charger_kw);
      END;
    END IF;
    v_charge_start := v_cursor;$n2$),
  -- 3: the leg carries the basis the plan was made on
  (3, 'public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)'::regprocedure,
   $o3$           (v_min*60)::int, jsonb_build_object('kind','flow_contract','charger_kw_assumed',v_charger_kw), 'planned');
$o3$,
   $n3$           (v_min*60)::int, v_basis, 'planned');   -- 0745: the rule's basis unless the clock planned the charge
$n3$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)'::regprocedure);
  FOR p IN SELECT * FROM _0745_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0745: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0745: the planner is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the patched body less its insertions is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)'::regprocedure;
  FOR p IN SELECT * FROM _0745_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM '990e9481a4917ae0d23dc78e205896aa' THEN
    RAISE EXCEPTION '0745 V1: the planner less its insertions is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: nothing planned for a run that does not exist ──
DO $v2$
BEGIN
  IF public.ottoq_plan_visit_itinerary('00000000-0000-0000-0000-00000000745a'::uuid,
                                       '00000000-0000-0000-0000-00000000745b'::uuid, now()) <> 0 THEN
    RAISE EXCEPTION '0745 V2: the planner planned something for a run that does not exist';
  END IF;
END $v2$;

-- ── (c) the pairs: arm 84's and arm 83's cells with the dial ──
INSERT INTO public.ottoq_throughput_sweeps (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick,
                                            seeds, replicates, priority, arm_budget_s, status, notes)
VALUES ('itinclock_normal_2026_10_17',
        'The itinerary plans each charge on a charger the depot has, on its clock: arms 84 and 83 with itinerary_charge_on_clock',
        '11111111-1111-1111-1111-111111111111', 'normal_day', '2026-09-01 11:00:00+00', 144, 5,
        ARRAY[686364201590009433]::bigint[], 0, 16, 3000, 'active',
        '0745 (G459). Cell 1 pairs with arm 84 (dcfc40_power_normal_2026_10_17 / dcfc40.otto_q) and cell 2 with arm 83 '
        '(dcfc40_normal_2026_10_17 / dcfc10.otto_q) on value_2026_09_30''s first seed; each differs from its partner only '
        'by the dial.');
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, x.cell_code, x.ord, 'otto_q', x.buildout_code, x.fixed_params
  FROM public.ottoq_throughput_sweeps s
 CROSS JOIN (VALUES ('dcfc40.otto_q.itinerary_on_clock', 1, 'dcfc40',
                     '{"deploy_peak_fraction": 0.90, "itinerary_charge_on_clock": 1}'::jsonb),
                    ('dcfc10.otto_q.itinerary_on_clock', 2, 'dcfc10',
                     '{"deploy_peak_fraction": 0.90, "itinerary_charge_on_clock": 1}'::jsonb)) x(cell_code, ord, buildout_code, fixed_params)
 WHERE s.sweep_code = 'itinclock_normal_2026_10_17';

-- ── V3: the dial and the cells ──
DO $v3$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                  WHERE param_key = 'itinerary_charge_on_clock' AND default_value = 0 AND min_value = 0 AND max_value = 1
                    AND NOT COALESCE(agent_writable, false)) THEN
    RAISE EXCEPTION '0745 V3: the dial is not catalogued 0..1, default 0, not agent-writable';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'itinclock_normal_2026_10_17') <> 2
     OR (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
           JOIN (VALUES ('dcfc40_power_normal_2026_10_17', 'dcfc40.otto_q', 'dcfc40.otto_q.itinerary_on_clock'),
                        ('dcfc40_normal_2026_10_17', 'dcfc10.otto_q', 'dcfc10.otto_q.itinerary_on_clock')) pr(psweep, pcell, cell)
             ON pr.cell = c.cell_code
           JOIN public.ottoq_throughput_sweeps sp ON sp.sweep_code = pr.psweep
           JOIN public.ottoq_throughput_sweep_cells cp ON cp.sweep_id = sp.sweep_id AND cp.cell_code = pr.pcell
          WHERE s.sweep_code = 'itinclock_normal_2026_10_17'
            AND c.buildout_code = cp.buildout_code AND c.seat = cp.seat
            AND (s.scenario, s.sim_start, s.ticks, s.sim_min_per_tick, s.seeds[1])
              = (sp.scenario, sp.sim_start, sp.ticks, sp.sim_min_per_tick, sp.seeds[1])
            AND c.fixed_params - 'itinerary_charge_on_clock' = cp.fixed_params
            AND c.fixed_params ->> 'itinerary_charge_on_clock' = '1') <> 2 THEN
    RAISE EXCEPTION '0745 V3: the sweep''s cells are not arm 84''s and arm 83''s plus the dial';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0745_the_itinerary_plans_each_charge_on_a_charger_the_depot_has', false, false,
        'Dial itinerary_charge_on_clock (default 0); three anchored insertions in public.ottoq_plan_visit_itinerary that '
        'act only at 1: the charge is planned on the one kind of charger the car can plug into at the depot when there is '
        'one, else the 45% rule''s kind, and timed on the depot''s learned charge clock to rule 9''s one target (V1: body '
        'less insertions is its pre-image; at 0 the leg''s basis is the same value). Sweep itinclock_normal_2026_10_17 (arm '
        '84''s and arm 83''s cells plus the dial, one seed, priority 16). No certification arm, canon cell or dial '
        'experiment sets the dial.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-18 11:13:01 UTC (6:13 AM CT), ledger version 20261018111301 ══════════════════════════════════════
--
--   Through apply_migration with nothing in flight (no run live and nothing in flight, read before and after; the file's
--   own P0 at the apply). The text sent, BEGIN through COMMIT and one newline, is 15,679 characters, md5
--   712ca77098f2689e04d0104afc2fbd04, equal to the ledger's statements[1] read back; its executable part is 15,663
--   characters, md5 3f382ac975d2eaf0b9ecede7782f4819, equal to this file's. public.ottoq_plan_visit_itinerary is now md5
--   b18eef1a0b1b9b8f855c939f37cd00b3 (prosrc), the body the dry run of 2026-10-17 at 6:14 PM CT left and
--   tests/test_itinerary_charge_on_clock_sql.py pins on the scratch PostgreSQL. Sweep itinclock_normal_2026_10_17 is
--   queued (two cells, priority 16).
--
--   End to end on live, rolled back by its own raise at 11:43:47 UTC (6:43 AM CT): a probe run at the twin depot; a car
--   at 60% with an open visit (charge, and an exterior wash in a wash bay). At the dial's default the planner wrote
--   charge_l2 for 230.5 minutes on {flow_contract, charger_kw_assumed 11}; with itinerary_charge_on_clock 1, charge_l2
--   for 154.1 minutes on the charge clock (kind_basis soc_rule, 19.2 kW); and with every L2 stall made a fast charger
--   inside the same transaction, charge_dcfc for 83.3 minutes on the clock (kind_basis
--   the_only_kind_the_car_can_use_here, 350 kW), the wash leg starting at that charge's end. The first attempt, at
--   11:43:04 UTC, put a wash atom with no concurrency on the probe's visit, and the planner, rightly, planned no wash
--   leg for it; the probe was corrected, not the planner.
