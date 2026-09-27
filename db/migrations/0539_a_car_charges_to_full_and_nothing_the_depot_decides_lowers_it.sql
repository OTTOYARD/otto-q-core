-- migration-version: 20260927223621
-- migration-name:    a_car_charges_to_full_and_nothing_the_depot_decides_lowers_it
--
-- 0539  **A car charges to full. How full is its owner's answer, and nothing the depot decides lowers it.**
--
-- ══ §1 WHY (Chase, 2026-09-27; CLAUDE.md rule 9; G265, G266) ══════════════════════════════════════════════════════════
--
--   Chase, 5:00 PM CT: "Let's just do 100% across-the-board for now. I'm thinking of the vehicles there. It should just
--   go ahead and be fully charged. We can always change that later on. And ultimately, eventually that can be a per
--   vehicle or per asset setting ... a fleet manager might decide to just cap charging at 90% to get vehicles back out
--   ... They could theoretically do that from one of our apps with correct verification and confirmation and then that
--   would permanently save to their vehicle settings, and OTTO-Q would acknowledge that."
--
--   Measured before this file (2026-09-27 22:15 UTC). Five places decided how full a car charged, and four were the
--   depot's:
--     (a) public.ottoq_target_soc_cap: a fast plug stopped at dcfc_target_soc_day (90) by day, whatever the car's target;
--     (b) public.ottoq_charge_plan_for_visit: the plan's target was a chemistry default (LFP 100, NMC 90) or the
--         `nightly_soc_target` ottoq_onboard_vehicle_battery writes from the chemistry, then lowered to (a), and
--         ottoq.ottoq_book_appointment stamps it on the car as vehicles.target_soc;
--     (c) ottoq.ottoq_derive_visit_needs: an immediate-dispatch visit charged to the SLA floor + 5 (85);
--     (d) ottoq.ottoq_enact_opportunistic_charge: a top-off stopped at LEAST(90, ...);
--     (e) public.ottoq_default_target_soc() = 100: the fleet default, and the only one that was not a depot ceiling.
--   The harnesses rested the fleet at 90: ottoq_tick_invariance_reset_fleet (every certification and dial arm) and
--   ottoq_cert_arm_start (no caller). The twin's naive assigner could shift a car's target with a scenario knob (A.10).
--   public.ottoq_effective_target_soc_at, the one function named for the car's own target, had no caller and fell back
--   to the contract's PREFERRED deployment SoC (90), which is the bar for leaving, not a charge target.
--
--   G266, found on the way. The boot draw's reset of the run's SoC state (0115, step 1e) sets target_soc = NULL. The
--   column is NOT NULL, so the statement raises 23502, the step catches it as a WARNING, and the whole reset --
--   target_soc, current_soc_source, current_soc_updated_at -- has failed on every run's boot since 2026-08-30. 0096 had
--   met the same 23502 a day earlier and pinned the harness to a constant. So an operator run starts with the targets
--   the last run left: validation run ad106e55 booted with 38 of the twin's 116 cars at 85%, left by the treatment arm
--   of experiment 08262943, which was abandoned that evening under rule 9.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   ONE ANSWER to how full a car charges: public.ottoq_effective_target_soc_at(vehicle, at), the fleet default (100)
--   under the owner's contract ceiling (ottoq_fleet_operator_slas.max_charge_target_pct, 100 in all four contracts).
--   The per-vehicle limit Chase describes will be read there when an owner can set it; no caller changes then.
--     (a) ottoq_target_soc_cap returns 100 on every plug at every hour and reads no dial. The three dials it read are
--         retired in the catalog (min = max = default = 100, so any write lands at 100). Their rows stay because two
--         abandoned experiments reference them. Each caller's LEAST(target, cap) is now the car's own target.
--     (b) the charge plan's target is the answer. Neither chemistry nor the fast plug lowers it.
--     (c) derive_visit_needs reads the answer, and every visit charges the car to it, whatever the urgency. An
--         immediate dispatch keeps its 45-minute due time; it is no longer charged less.
--     (d) a top-off fills the car to the answer.
--     (e) the two harnesses rest the fleet at 100, and the naive assigner's knob is gone. No variability profile
--         carried it (0 of 19).
--     (f) G266: the boot draw resets target_soc to the answer, so the reset succeeds again, all three columns.
--   The global dcfc_target_soc_day row goes to 100, the only one of the three below it.
--
--   Not changed: ottoq_onboard_vehicle_battery still records `nightly_soc_target` from the chemistry. Nothing reads it
--   after this file. ottoq_book_appointment still stamps GREATEST(plan target, soc) on the car. That stays right while
--   the answer is 100; once an owner can set a lower limit, a car arriving above it must not raise its stamp (G265).
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   Every certification and dial arm rests its fleet at a new target and charges every car further. The canon
--   re-certifies, and pairs before this file stop counting.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0539 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: each function is the one measured (md5 of its source, 2026-09-27 22:15 UTC), and the facts §1 rests on ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_target_soc_cap(text,timestamp with time zone,uuid)',                          '24cd0c0b844f26c28d898acf10c0c0a2'),
      ('public.ottoq_effective_target_soc_at(uuid,timestamp with time zone)',                      '34c202ff2496daa9cf8071a7fbe28ef2'),
      ('public.ottoq_charge_plan_for_visit(uuid,timestamp with time zone,numeric)',                  'ede0d18281aa2cc1e754fc1a7c76de7f'),
      ('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)',        '5d532d8497048be0560c01344f10a3a9'),
      ('ottoq.ottoq_enact_opportunistic_charge(uuid,uuid,numeric,numeric,timestamp with time zone)', '1da4bc77e428eafd6829f2e9a1eb7928'),
      ('public.ottoq_tick_invariance_reset_fleet(uuid,bigint,timestamp with time zone)',            '98cd4dec7c75f740ac1bb82ea49e2094'),
      ('public.ottoq_cert_arm_start(bigint,text,uuid,integer)',                                     '1d87a48572fbb6b1cca2ff624ce9fae4'),
      ('public.ottoq_run_boot_draw(uuid)',                                                          'ad7ce0809830002914a8ec4db1fbd5b9'),
      ('twin.ottoq_sim_auto_charge_assign_tick(uuid,timestamp with time zone)',                    'd58ac263110be79ebdb090469faaa141')
    ) AS t(sig, want) LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = r.sig::regprocedure) <> r.want THEN
      RAISE EXCEPTION '0539 P2: % is not the function measured', r.sig;
    END IF;
  END LOOP;
  -- the column the boot draw nulls refuses a NULL (G266)
  IF NOT (SELECT a.attnotnull FROM pg_attribute a WHERE a.attrelid = 'public.vehicles'::regclass AND a.attname = 'target_soc') THEN
    RAISE EXCEPTION '0539 P2: vehicles.target_soc accepts NULL; G266 is not what was measured';
  END IF;
  -- the answer is 100 today: the fleet default, and every active contract's ceiling
  IF public.ottoq_default_target_soc() IS DISTINCT FROM 100 THEN
    RAISE EXCEPTION '0539 P2: the fleet default is %, not 100', public.ottoq_default_target_soc();
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_fleet_operator_slas s
              WHERE s.status = 'active' AND s.max_charge_target_pct IS DISTINCT FROM 100) THEN
    RAISE EXCEPTION '0539 P2: an active contract caps charging below 100; the answer would not be 100';
  END IF;
  -- no variability profile carries the knob the naive assigner drops
  IF EXISTS (SELECT 1 FROM public.ottoq_variability_profiles WHERE knobs ? 'target_soc') THEN
    RAISE EXCEPTION '0539 P2: a variability profile sets the target_soc knob';
  END IF;
  -- the three dials are the ones catalogued, and only the cap and the challenger's two reads name them
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog
       WHERE param_key IN ('dcfc_target_soc_day', 'dcfc_target_soc_night', 'l2_target_soc')) <> 3 THEN
    RAISE EXCEPTION '0539 P2: the three plug-ceiling dials are not all catalogued';
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public', 'ottoq', 'twin')
         AND p.prosrc ~ '(dcfc_target_soc_day|dcfc_target_soc_night|l2_target_soc)'
         AND p.oid NOT IN ('public.ottoq_target_soc_cap(text,timestamp with time zone,uuid)'::regprocedure,
                           'public.ottoq_challenger_board(uuid)'::regprocedure,
                           'public.ottoq_challenger_report(uuid)'::regprocedure)) <> 0 THEN
    RAISE EXCEPTION '0539 P2: another function names a plug-ceiling dial';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0539_pre', 'function', f.sch, f.obj, pg_get_functiondef(f.sig::regprocedure), md5(pg_get_functiondef(f.sig::regprocedure))
  FROM (VALUES ('public', 'ottoq_target_soc_cap',             'public.ottoq_target_soc_cap(text,timestamp with time zone,uuid)'),
               ('public', 'ottoq_effective_target_soc_at',    'public.ottoq_effective_target_soc_at(uuid,timestamp with time zone)'),
               ('public', 'ottoq_charge_plan_for_visit',      'public.ottoq_charge_plan_for_visit(uuid,timestamp with time zone,numeric)'),
               ('ottoq',  'ottoq_derive_visit_needs',         'ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)'),
               ('ottoq',  'ottoq_enact_opportunistic_charge', 'ottoq.ottoq_enact_opportunistic_charge(uuid,uuid,numeric,numeric,timestamp with time zone)'),
               ('public', 'ottoq_tick_invariance_reset_fleet','public.ottoq_tick_invariance_reset_fleet(uuid,bigint,timestamp with time zone)'),
               ('public', 'ottoq_cert_arm_start',             'public.ottoq_cert_arm_start(bigint,text,uuid,integer)'),
               ('public', 'ottoq_run_boot_draw',              'public.ottoq_run_boot_draw(uuid)'),
               ('twin',   'ottoq_sim_auto_charge_assign_tick','twin.ottoq_sim_auto_charge_assign_tick(uuid,timestamp with time zone)')
       ) AS f(sch, obj, sig);

-- ── the one answer, and the cap that no longer lowers it: each body is replaced whole (the md5 above pins the old) ──
DO $whole$
DECLARE
  r record; v_def text; v_old text; n int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('public.ottoq_effective_target_soc_at(uuid,timestamp with time zone)', $new$
  -- 0539 (Chase 2026-09-27, CLAUDE.md rule 9): HOW FULL THIS CAR CHARGES, AND IT IS THE OWNER'S ANSWER. The fleet
  -- default (public.ottoq_default_target_soc(), 100) under the owner's contract ceiling
  -- (ottoq_fleet_operator_slas.max_charge_target_pct, 100 in all four contracts). Nothing the depot decides enters it.
  -- A per-vehicle limit an owner sets from an app, verified and confirmed ("that would permanently save to their
  -- vehicle settings, and OTTO-Q would acknowledge that"), is read here when it exists, and no caller changes.
  -- This read vehicles.target_soc first, the engine's own stamp of the car's last plan and not the owner's; then the
  -- contract's PREFERRED deployment SoC (90), the bar for leaving and not a charge target; then 90. It had no caller.
  SELECT LEAST(
    public.ottoq_default_target_soc(),
    COALESCE((SELECT s.max_charge_target_pct FROM ottoq_fleet_operator_slas s
               WHERE s.fleet_operator_id = v.fleet_operator_id AND s.status='active'
                 AND s.effective_from <= p_as_of
                 AND (s.effective_until IS NULL OR s.effective_until > p_as_of)
               ORDER BY s.version DESC LIMIT 1), 100))
  FROM vehicles v WHERE v.id = p_vehicle_id;
$new$),
    ('public.ottoq_target_soc_cap(text,timestamp with time zone,uuid)', $new$
  -- 0539 (Chase 2026-09-27, CLAUDE.md rule 9): THE DEPOT SETS NO CEILING ON A CAR'S CHARGE. A car charges to its own
  -- target (public.ottoq_effective_target_soc_at: its owner's) on any plug, by day and by night. This returned
  -- dcfc_target_soc_day (90) on a fast plug by day, so every daytime fast charge stopped at 90% whatever the car's
  -- target. It returns full and reads no dial, so each caller's LEAST(target, cap) is the car's own target. The three
  -- dials it read are retired in ottoq_policy_param_catalog. The arguments stay so that no caller changes.
  SELECT 100::numeric;
$new$)
  ) AS t(sig, body) LOOP
    v_def := pg_get_functiondef(r.sig::regprocedure);
    v_old := (SELECT prosrc FROM pg_proc WHERE oid = r.sig::regprocedure);
    n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    IF n <> 1 THEN RAISE EXCEPTION '0539 (whole): the body of % appears % times in its definition', r.sig, n; END IF;
    EXECUTE replace(v_def, v_old, r.body);
  END LOOP;
END $whole$;

-- ── (b)-(f): each anchor must match exactly once (a literal, or a pattern where only whitespace is uncertain) ──
DO $patch$
DECLARE
  r record; v_def text; v_cur text := ''; n int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    -- (b) the charge plan
    (1, 'public.ottoq_charge_plan_for_visit(uuid,timestamp with time zone,numeric)', 're',
     $a$  -- What the CAR wants: chemistry default, or an explicit per-vehicle nightly target\.\n  v_target := COALESCE\(\(v\.config->>'nightly_soc_target'\)::numeric,\n\s+CASE WHEN v_chem='lfp' THEN 100 ELSE 90 END\);$a$,
     $b$  -- 0539 (CLAUDE.md rule 9): the car charges to ITS target, which is its owner's (public.ottoq_effective_target_soc_at,
  -- 100 today). This was a chemistry default (LFP 100, NMC 90) or the `nightly_soc_target` battery onboarding writes
  -- from the chemistry: the depot deciding how full a car leaves.
  v_target := public.ottoq_effective_target_soc_at(p_vehicle_id, p_clock);$b$, 1),
    (2, 'public.ottoq_charge_plan_for_visit(uuid,timestamp with time zone,numeric)', 'lit',
     $a$  -- What the DEPOT allows on a fast plug at this hour. A ceiling, never a floor.$a$,
     $b$  -- 0539: the depot sets no ceiling on a car's charge (ottoq_target_soc_cap returns full). Read for the record only.$b$, 1),
    (3, 'public.ottoq_charge_plan_for_visit(uuid,timestamp with time zone,numeric)', 'lit',
     $a$v_class := 'dcfc'; v_target := LEAST(v_target, v_dc_cap);$a$,
     $b$v_class := 'dcfc';$b$, 2),
    (4, 'public.ottoq_charge_plan_for_visit(uuid,timestamp with time zone,numeric)', 'lit',
     $a$'overnight_dcfc_to_' || v_dc_cap::text$a$, $b$'overnight_dcfc_to_' || v_target::text$b$, 1),
    (5, 'public.ottoq_charge_plan_for_visit(uuid,timestamp with time zone,numeric)', 'lit',
     $a$'daytime_fast_turnaround_' || v_dc_cap::text$a$, $b$'daytime_fast_turnaround_' || v_target::text$b$, 1),
    -- (c) the visit's need
    (6, 'ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)', 'lit',
     $a$SELECT current_soc, COALESCE(target_soc, public.ottoq_default_target_soc()), COALESCE((config->>'cycles_since_wash')::int,0),$a$,
     $b$SELECT current_soc, public.ottoq_effective_target_soc_at(p_vehicle_id, v_clock) /* 0539: the owner's, not the last plan's stamp */, COALESCE((config->>'cycles_since_wash')::int,0),$b$, 1),
    (7, 'ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)', 're',
     $a$v_visit_target := CASE WHEN v_urgency = 'immediate_dispatch'\s+THEN GREATEST\(v_sla_floor \+ 5, 70\) ELSE v_target END;$a$,
     $b$-- 0539 (CLAUDE.md rule 9): every visit charges the car to its target, whatever the urgency. An immediate dispatch
  -- keeps its 45-minute due time. It was also charged less, to the SLA floor + 5 (85), which no owner asked for.
  v_visit_target := v_target;$b$, 1),
    -- (d) the top-off
    (8, 'ottoq.ottoq_enact_opportunistic_charge(uuid,uuid,numeric,numeric,timestamp with time zone)', 'lit',
     $a$  v_target := LEAST(90, GREATEST(COALESCE(p_vehicle_target_soc, public.ottoq_default_target_soc()), p_current_soc + 20));$a$,
     $b$  -- 0539 (CLAUDE.md rule 9): a top-off fills the car to its target, its owner's. This was LEAST(90, ...): no top-off
  -- filled a car past 90%, whatever its target.
  v_target := public.ottoq_effective_target_soc_at(p_vehicle_id, p_clock);$b$, 1),
    -- (e) the harnesses and the naive assigner
    (9, 'public.ottoq_tick_invariance_reset_fleet(uuid,bigint,timestamp with time zone)', 'lit',
     $a$         -- 0096: NOT NULL column; canonical means a CONSTANT (seeded fleet rests at 90).
         target_soc = 90,$a$,
     $b$         -- 0096: NOT NULL column; canonical means a CONSTANT.
         -- 0539 (CLAUDE.md rule 9): and the constant is FULL. It was 90, the rest level 0096 read off the seeded
         -- fleet. A car's target is its owner's, 100 today (public.ottoq_effective_target_soc_at; 0539 V3 checks both).
         target_soc = 100,$b$, 1),
    (10, 'public.ottoq_cert_arm_start(bigint,text,uuid,integer)', 'lit',
     $a$target_soc = 90, current_state='staged_for_departure'$a$,
     $b$target_soc = 100 /* 0539: the fleet rests at full */, current_state='staged_for_departure'$b$, 1),
    (11, 'twin.ottoq_sim_auto_charge_assign_tick(uuid,timestamp with time zone)', 'lit',
     $a$    -- A.10: target_soc knob shifts the charge target (clamped 50-100%)
    v_target_soc := GREATEST(50, LEAST(100,
      ottoq_apply_profile(p_sim_run_id, 'target_soc', COALESCE(v_vehicle.target_soc, public.ottoq_default_target_soc()), COALESCE(v_vehicle.target_soc, public.ottoq_default_target_soc()))));$a$,
     $b$    -- 0539 (CLAUDE.md rule 9): the car charges to its own target. The A.10 `target_soc` profile knob shifted it,
    -- clamped to 50-100%: a scenario lowering the owner's target. No variability profile carried it (0 of 19).
    v_target_soc := COALESCE(v_vehicle.target_soc, public.ottoq_default_target_soc());$b$, 1),
    -- (f) G266: the boot draw's reset can succeed
    (12, 'public.ottoq_run_boot_draw(uuid)', 'lit',
     $a$  -- ---- 1e. 0115: THE SOC STATE BELONGS TO THE RUN (pair-17 fork, db/checks/0046).$a$,
     $b$  -- ---- 1e. 0115: THE SOC STATE BELONGS TO THE RUN (pair-17 fork, db/checks/0046).
  --      0539 (G266): this set target_soc = NULL on a NOT NULL column. It raised 23502, caught below as a WARNING,
  --      so the whole reset failed on every boot from 0115 to 0539 and a run started with the last run's targets.
  --      It rests each car at its own target now (public.ottoq_effective_target_soc_at), and the reset succeeds.$b$, 1),
    (13, 'public.ottoq_run_boot_draw(uuid)', 'lit',
     $a$SET target_soc = NULL,$a$,
     $b$SET target_soc = public.ottoq_effective_target_soc_at(v.id, v_run.sim_clock_start),$b$, 1),
    (14, 'public.ottoq_run_boot_draw(uuid)', 'lit',
     $a$AND (v.target_soc IS NOT NULL$a$,
     $b$AND (v.target_soc IS DISTINCT FROM public.ottoq_effective_target_soc_at(v.id, v_run.sim_clock_start)$b$, 1)
  ) AS t(k, sig, kind, anchor, repl, times)
  ORDER BY sig, k LOOP
    IF r.sig <> v_cur THEN
      IF v_cur <> '' THEN EXECUTE v_def; END IF;
      v_cur := r.sig;
      v_def := pg_get_functiondef(r.sig::regprocedure);
    END IF;
    IF r.kind = 'lit' THEN
      n := (length(v_def) - length(replace(v_def, r.anchor, ''))) / length(r.anchor);
      IF n <> r.times THEN RAISE EXCEPTION '0539 patch %: the anchor matches % times in %, not %', r.k, n, r.sig, r.times; END IF;
      v_def := replace(v_def, r.anchor, r.repl);
    ELSE
      n := (SELECT count(*) FROM regexp_matches(v_def, r.anchor, 'g'));
      IF n <> r.times THEN RAISE EXCEPTION '0539 patch %: the pattern matches % times in %, not %', r.k, n, r.sig, r.times; END IF;
      v_def := regexp_replace(v_def, r.anchor, r.repl);
    END IF;
  END LOOP;
  EXECUTE v_def;
END $patch$;

-- ── (a) the three plug-ceiling dials are retired: any write lands at 100, and the global row is 100 ──
UPDATE public.ottoq_policy_param_catalog
   SET min_value = 100, default_value = 100,
       description = 'RETIRED by 0539 (CLAUDE.md rule 9, Chase 2026-09-27): the depot sets no ceiling on a car''s charge. '
                  || 'public.ottoq_target_soc_cap returns full and reads no dial; a car charges to its own target, its '
                  || 'owner''s (public.ottoq_effective_target_soc_at). The row stays because ottoq_dial_experiments rows '
                  || 'reference it (two experiments abandoned 2026-09-27, G265). min = max = 100, so any write lands at '
                  || '100. Was: ' || description
 WHERE param_key IN ('dcfc_target_soc_day', 'dcfc_target_soc_night', 'l2_target_soc');

DO $dial$
DECLARE v jsonb;
BEGIN
  v := public.ottoq_policy_set('global', NULL, 'dcfc_target_soc_day', 100, '0539_a_car_charges_to_full');
  IF NOT COALESCE((v->>'ok')::boolean, false) OR (v->>'applied')::numeric IS DISTINCT FROM 100 THEN
    RAISE EXCEPTION '0539: the global day ceiling did not go to 100: %', v;
  END IF;
END $dial$;

-- ── V1 (comment-stripped): each function says what §2 says it says ──
DO $verify$
DECLARE
  r record; v_src text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_effective_target_soc_at(uuid,timestamp with time zone)',
       ARRAY['max_charge_target_pct', 'public.ottoq_default_target_soc()'], ARRAY['preferred_soc_at_deployment_pct', 'v.target_soc']),
      ('public.ottoq_target_soc_cap(text,timestamp with time zone,uuid)',
       ARRAY['SELECT 100::numeric'], ARRAY['ottoq_policy_get', 'dcfc_target_soc']),
      ('public.ottoq_charge_plan_for_visit(uuid,timestamp with time zone,numeric)',
       ARRAY['v_target := public.ottoq_effective_target_soc_at(p_vehicle_id, p_clock);'],
       ARRAY['nightly_soc_target', 'LEAST(v_target', 'ELSE 90 END']),
      ('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)',
       ARRAY['public.ottoq_effective_target_soc_at(p_vehicle_id, v_clock)', 'v_visit_target := v_target;'],
       ARRAY['v_sla_floor + 5', 'COALESCE(target_soc, public.ottoq_default_target_soc())']),
      ('ottoq.ottoq_enact_opportunistic_charge(uuid,uuid,numeric,numeric,timestamp with time zone)',
       ARRAY['v_target := public.ottoq_effective_target_soc_at(p_vehicle_id, p_clock);'], ARRAY['LEAST(90']),
      ('public.ottoq_tick_invariance_reset_fleet(uuid,bigint,timestamp with time zone)',
       ARRAY['target_soc = 100,'], ARRAY['target_soc = 90']),
      ('public.ottoq_cert_arm_start(bigint,text,uuid,integer)',
       ARRAY['target_soc = 100'], ARRAY['target_soc = 90']),
      ('public.ottoq_run_boot_draw(uuid)',
       ARRAY['SET target_soc = public.ottoq_effective_target_soc_at(v.id, v_run.sim_clock_start),'], ARRAY['target_soc = NULL']),
      ('twin.ottoq_sim_auto_charge_assign_tick(uuid,timestamp with time zone)',
       ARRAY['v_target_soc := COALESCE(v_vehicle.target_soc, public.ottoq_default_target_soc());'],
       ARRAY['ottoq_apply_profile(p_sim_run_id, ''target_soc''', 'GREATEST(50'])
    ) AS t(sig, must, mustnt) LOOP
    v_src := regexp_replace(regexp_replace(pg_get_functiondef(r.sig::regprocedure), '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
    IF EXISTS (SELECT 1 FROM unnest(r.must) m WHERE position(m IN v_src) = 0) THEN
      RAISE EXCEPTION '0539 V1: % lacks one of %', r.sig, r.must;
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(r.mustnt) m WHERE position(m IN v_src) > 0) THEN
      RAISE EXCEPTION '0539 V1: % still carries one of %', r.sig, r.mustnt;
    END IF;
  END LOOP;
  -- the one answer is still STABLE, and no retired dial takes a value under 100
  IF (SELECT provolatile FROM pg_proc WHERE oid = 'public.ottoq_effective_target_soc_at(uuid,timestamp with time zone)'::regprocedure) <> 's' THEN
    RAISE EXCEPTION '0539 V1: the answer is no longer STABLE';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
              WHERE param_key IN ('dcfc_target_soc_day', 'dcfc_target_soc_night', 'l2_target_soc')
                AND (min_value IS DISTINCT FROM 100 OR max_value IS DISTINCT FROM 100 OR default_value IS DISTINCT FROM 100)) THEN
    RAISE EXCEPTION '0539 V1: a retired dial still admits a value under 100';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_policy_params
              WHERE scope_type IN ('global', 'depot')
                AND param_key IN ('dcfc_target_soc_day', 'dcfc_target_soc_night', 'l2_target_soc') AND param_value <> 100) THEN
    RAISE EXCEPTION '0539 V1: a global or depot plug ceiling is under 100';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0539_a_car_charges_to_full_and_nothing_the_depot_decides_lowers_it', true, true,
  'Rule 9 (Chase 2026-09-27: "100% across-the-board"): one answer to how full a car charges, the owner''s '
  '(ottoq_effective_target_soc_at: the fleet default under the contract ceiling, 100). The plug ceiling returns full and '
  'its three dials are retired; the charge plan, the visit need, the top-off, both harnesses and the naive assigner charge '
  'to the answer; the boot draw''s SoC reset stops failing on a NULL (G266). Every certification and dial arm rests its '
  'fleet at 100 instead of 90 and charges every car further.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back:
--   (a) the cap is 100 on a fast plug by day and by night and on L2, with no run, with the two-argument form, and with a
--       run that holds 85 on the retired day dial;
--   (b) the answer is 100 for every car of the twin depot; with one operator's contract ceiling set to 90 it is 90 for
--       exactly that operator's cars and 100 for the rest;
--   (c) a 10 AM CT plan charges an NMC car and a car with no chemistry to 100 on a fast plug;
--   (d) an immediate dispatch at 40% derives a visit that charges to 100, keeps its 45-minute due time, and whose charge
--       atom aims at 100;
--   (e) a top-off of a car at 70% aims at 100;
--   (f) the certification harness rests every twin car at 100;
--   (g) G266: after planting 85 on every twin car, the boot draw of validation run ad106e55 rests every active twin car at
--       100, 'estimated', stamped at the run's sim start -- the reset succeeds;
--   (h) a write of 85 to a retired dial lands at 100.
DO $v3$
DECLARE
  v_msg text; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_day timestamptz := '2026-09-01 15:00:00+00'; v_night timestamptz := '2026-09-01 08:00:00+00';
  v_boot_run uuid := 'ad106e55-e775-4780-b853-418f504d4bcf'; v_start timestamptz;
  c numeric[]; v_run uuid := gen_random_uuid(); v_op uuid; v_n int; v_bad int; v_ceiled int; v_rest int; v_mine int;
  v_nmc uuid; v_plain uuid; v_p1 jsonb; v_p2 jsonb; v_vis record; v_atom numeric; v_opp jsonb; v_set jsonb; v_boot jsonb;
BEGIN
  BEGIN
    -- (a)
    INSERT INTO public.ottoq_policy_params(scope_type, scope_id, param_key, param_value, updated_by)
    VALUES ('run', v_run, 'dcfc_target_soc_day', 85, '0539_v3');
    PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
    c := ARRAY[public.ottoq_target_soc_cap('dcfc', v_day, NULL), public.ottoq_target_soc_cap('dcfc', v_night, NULL),
               public.ottoq_target_soc_cap('l2', v_day, NULL), public.ottoq_target_soc_cap('dcfc', v_day, v_run),
               public.ottoq_target_soc_cap('dcfc', v_day)];
    PERFORM set_config('ottoq.sim_run_id', 'none', true);
    IF c IS DISTINCT FROM ARRAY[100, 100, 100, 100, 100]::numeric[] THEN
      RAISE EXCEPTION '0539 V3 FAILED (a): the cap reads % (day, night, l2, a run at 85, pinned)', c;
    END IF;

    -- (b)
    SELECT count(*), count(*) FILTER (WHERE public.ottoq_effective_target_soc_at(v.id, v_day) IS DISTINCT FROM 100)
      INTO v_n, v_bad FROM public.vehicles v WHERE v.home_depot_id = v_twin AND v.category = 'autonomous';
    IF v_n < 100 OR v_bad <> 0 THEN RAISE EXCEPTION '0539 V3 FAILED (b): % of % twin cars do not charge to 100', v_bad, v_n; END IF;
    SELECT v.fleet_operator_id INTO v_op FROM public.vehicles v
     WHERE v.home_depot_id = v_twin AND v.category = 'autonomous' AND v.fleet_operator_id IS NOT NULL ORDER BY v.id LIMIT 1;
    UPDATE public.ottoq_fleet_operator_slas SET max_charge_target_pct = 90 WHERE fleet_operator_id = v_op AND status = 'active';
    SELECT count(*) FILTER (WHERE public.ottoq_effective_target_soc_at(v.id, v_day) = 90),
           count(*) FILTER (WHERE public.ottoq_effective_target_soc_at(v.id, v_day) = 100),
           count(*) FILTER (WHERE v.fleet_operator_id = v_op)
      INTO v_ceiled, v_rest, v_mine FROM public.vehicles v WHERE v.home_depot_id = v_twin AND v.category = 'autonomous';
    IF v_mine = 0 OR v_ceiled <> v_mine OR v_ceiled + v_rest <> v_n THEN
      RAISE EXCEPTION '0539 V3 FAILED (b): a 90 contract ceiling gives % cars 90 and % cars 100, for % of the operator''s % cars',
        v_ceiled, v_rest, v_n, v_mine;
    END IF;
    UPDATE public.ottoq_fleet_operator_slas SET max_charge_target_pct = 100 WHERE fleet_operator_id = v_op AND status = 'active';

    -- (c)
    SELECT v.id INTO v_nmc FROM public.vehicles v
     WHERE v.home_depot_id = v_twin AND v.category = 'autonomous' AND v.config->>'battery_chemistry' = 'nmc' ORDER BY v.id LIMIT 1;
    SELECT v.id INTO v_plain FROM public.vehicles v
     WHERE v.home_depot_id = v_twin AND v.category = 'autonomous' AND NOT (v.config ? 'battery_chemistry') ORDER BY v.id LIMIT 1;
    v_p1 := public.ottoq_charge_plan_for_visit(v_nmc, v_day, NULL);
    v_p2 := public.ottoq_charge_plan_for_visit(v_plain, v_day, NULL);
    IF v_nmc IS NULL OR v_plain IS NULL
       OR (v_p1->>'target_soc')::numeric IS DISTINCT FROM 100 OR (v_p2->>'target_soc')::numeric IS DISTINCT FROM 100
       OR v_p1->>'charger_class' IS DISTINCT FROM 'dcfc' OR v_p2->>'charger_class' IS DISTINCT FROM 'dcfc' THEN
      RAISE EXCEPTION '0539 V3 FAILED (c): the 10 AM plans are % (nmc) and % (no chemistry)', v_p1, v_p2;
    END IF;

    -- (d)
    UPDATE public.vehicles SET current_soc = 40 WHERE id = v_plain;
    PERFORM ottoq.ottoq_derive_visit_needs(v_plain, NULL, NULL, v_day, v_twin,
              jsonb_build_object('urgency_intent', 'immediate_dispatch', 'observer', '0539_v3', 'generator', '0539_v3'));
    SELECT vn.target_soc, vn.urgency, vn.dispatch_due_at, vn.atoms INTO v_vis FROM public.ottoq_visit_needs vn
     WHERE vn.vehicle_id = v_plain AND vn.visit_key = v_plain::text || ':' || to_char(v_day, 'YYYYMMDDHH24MISS')
       AND vn.sim_run_id IS NULL;
    SELECT (a->>'target_soc')::numeric INTO v_atom FROM jsonb_array_elements(v_vis.atoms) a WHERE a->>'svc' = 'charge';
    IF v_vis.target_soc IS DISTINCT FROM 100 OR v_vis.urgency IS DISTINCT FROM 'immediate_dispatch'
       OR v_vis.dispatch_due_at IS DISTINCT FROM v_day + interval '45 minutes' OR v_atom IS DISTINCT FROM 100 THEN
      RAISE EXCEPTION '0539 V3 FAILED (d): an immediate dispatch derives target %, urgency %, due %, charge atom %',
        v_vis.target_soc, v_vis.urgency, v_vis.dispatch_due_at, v_atom;
    END IF;

    -- (e)
    v_opp := ottoq.ottoq_enact_opportunistic_charge(v_boot_run, v_plain, 70, 90, v_day);  -- its hold booking needs a run
    IF (v_opp->>'target_soc')::numeric IS DISTINCT FROM 100 THEN
      RAISE EXCEPTION '0539 V3 FAILED (e): a top-off of a car at 70%% aims at %', v_opp->>'target_soc';
    END IF;

    -- (f)
    PERFORM public.ottoq_tick_invariance_reset_fleet(v_twin, 171717, v_day);
    SELECT count(*) FILTER (WHERE v.target_soc IS DISTINCT FROM 100) INTO v_bad
      FROM public.vehicles v WHERE v.home_depot_id = v_twin AND v.category = 'autonomous';
    IF v_bad <> 0 THEN RAISE EXCEPTION '0539 V3 FAILED (f): the harness rests % twin cars below 100', v_bad; END IF;

    -- (g)
    UPDATE public.vehicles SET target_soc = 85 WHERE home_depot_id = v_twin AND category = 'autonomous';
    SELECT r.sim_clock_start INTO v_start FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_boot_run;
    v_boot := public.ottoq_run_boot_draw(v_boot_run);
    SELECT count(*), count(*) FILTER (WHERE v.target_soc IS DISTINCT FROM 100
                                         OR v.current_soc_source IS DISTINCT FROM 'estimated'
                                         OR v.current_soc_updated_at IS DISTINCT FROM v_start)
      INTO v_n, v_bad FROM public.vehicles v
     WHERE v.home_depot_id = v_twin AND v.category = 'autonomous' AND v.is_active;
    IF v_start IS NULL OR v_n < 100 OR v_bad <> 0 THEN
      RAISE EXCEPTION '0539 V3 FAILED (g): after the boot draw % of % active twin cars are not reset (draw: %)', v_bad, v_n, left(v_boot::text, 300);
    END IF;

    -- (h)
    v_set := public.ottoq_policy_set('run', v_run, 'dcfc_target_soc_day', 85, '0539_v3');
    IF (v_set->>'applied')::numeric IS DISTINCT FROM 100 THEN
      RAISE EXCEPTION '0539 V3 FAILED (h): a write of 85 to the retired day dial applied %', v_set->>'applied';
    END IF;

    RAISE EXCEPTION '0539 V3 PASSED: the cap reads %; % twin cars charge to 100, and a 90 contract ceiling binds exactly its operator''s % cars; the 10 AM plans aim at % (nmc) and % (no chemistry); an immediate dispatch aims at % with its atom at % and is due %; a top-off aims at %; the harness and the boot draw rest every twin car at 100; a retired dial takes 85 as %',
      c, v_n, v_mine, v_p1->>'target_soc', v_p2->>'target_soc', v_vis.target_soc, v_atom, v_vis.dispatch_due_at,
      v_opp->>'target_soc', v_set->>'applied';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0539 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0539 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the nine `definition`s in ottoq_schema_snapshots WHERE label = '0539_pre' as they are; then restore
--   the three catalog rows (min_value 0; default_value 90 for dcfc_target_soc_day and 100 for the other two; the text
--   after 'Was: ' in each description) and the global dcfc_target_soc_day row (90).
COMMIT;
