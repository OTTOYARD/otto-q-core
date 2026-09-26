-- migration-version: 20260926145308
-- migration-name:    the_battery_drains_while_the_car_is_out_and_otto_q_rereads_its_charge_need_every_tick
--
-- 0486  **The battery drains while the car is out, and OTTO-Q re-reads a car's charge need every tick.**
--       FINDINGS G219 (`db/checks/0363` §4) and the intake-and-charge half of G210. Chase, 2026-09-26: the battery
--       should drain gradually, because that is closer to how vehicle batteries behave, and OTTO-Q should keep
--       assessing, so that a change is identified and orchestrated as it happens.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   `twin.ottoq_sim_advance_deployed_telemetry` drains a deployed car continuously, from its cumulative energy, and
--   then sets its SoC at the gate to `ottoq_apply_profile(run, 'soc_on_arrival', soc, soc) - ottoq_twin_arrival_soc_drain`.
--   busy_day's template is `soc_on_arrival {shift -30, ceiling 78}` and the climate drain is about 3 points more, so
--   the whole busy-day drain lands in one step at the gate. On `461c79fa` the dispatch ledger's `soc_at_return_pct`
--   sits 32.9-33.8 points above the gate SoC on all 88 completed dispatches.
--
--   Everything that reads the car before the gate reads it about 33 points high: the recall decision, the visit it
--   opens, the day plan's EV forecast, the dispatch ledger. Visits are derived once, at the recall, from that
--   reading. On `3dbe16db`, 39 visits derived as needing no charge (from a mean 90%) reached the gate at a mean 46%,
--   39 of 39 below their target and below the 80% SLA floor, and the gate intake took 33 of them as needing no
--   charge. On `461c79fa` it was 13 of 13. The same misread made G210's remaining intake-and-charge pair: the charge
--   path, which reads the SoC, sent the car to a charger while the intake, which reads the atoms, staged it.
--
--   Actual stints on busy_day average 58 minutes (a recall is need-driven and mostly comes after the planned return),
--   so the -30 lands on an average stint about as 30 points an hour would.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) THE TWIN: the drain is driven, not stamped. The run's out-drain is `-shift` of its `soc_on_arrival` template
--       (0 when there is none, and never negative: a battery is not refilled by driving) plus the climate drain,
--       read as SoC points per hour deployed. It is added to the car's discharge power, so it lands in the same
--       cumulative energy the SoC is already derived from, every tick the car is out and on its way home. The gate
--       reads the SoC the car arrived with and applies no step. So the recall decision, the telemetry packet, the
--       dispatch ledger and the arrival webhook all see the same battery the gate does.
--       `floor` and `ceiling` on `soc_on_arrival` no longer apply: they clamped a step that no longer exists. The
--       catalog row says so, and `arrival` is marked unwired, because nothing in the engine reads it.
--   (2) THE KERNEL: `ottoq.ottoq_reassess_charge_needs(run, clock)` runs every tick beside
--       `ottoq_close_satisfied_charge_needs`, its mirror. It closes a need the car no longer has; this opens one the
--       car has grown since its visit was derived. For every open visit of the run whose car is on its way in, at
--       the gate or waiting in staging (`en_route_to_depot`, `arrived_at_gate`, `staged_awaiting_service`), whose
--       visit carries no charge atom at all, and whose SoC is now below the visit's target minus 1, it adds the
--       charge the deriver would give that car now: must-do, not deferrable, to the visit's target, with the
--       deriver's charge-time estimate. A visit derived as pass-through is relabelled as the deriver would label it
--       with a charge. Each addition is an `ottoq.need_reassessed` event, so it shows in the run's event stream.
--       A visit that already has a charge atom, of any status, is left alone. A charge that finished short of its
--       target is closed on purpose (0463, G196), and reopening it would bring back G196's loop.
--
--   With the charge atom present when the car reaches the gate, the intake (`ottoq_decide_tick` (3b)) no longer
--   takes it as a no-charge arrival, so (3) is the only section that decides it.
--
-- ══ §3 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   Both are on the tick path. The canon's arms carry no template, so their out-drain is the climate drain alone
--   (about 0.5 points on the canon's date), now spread over the stint instead of at the gate. The re-assessment
--   adds atoms and events wherever a car's SoC falls below its visit's target with no charge planned.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0486 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the bodies this file patches, exactly as measured, and nothing it creates exists yet ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamp with time zone,numeric)'::regprocedure))
     <> '0e3d7c4dae6096eea44608ca27e1f804' THEN
    RAISE EXCEPTION '0486 P2: twin.ottoq_sim_advance_deployed_telemetry is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure))
     <> '2bf23ba15db3c3e4fda29b14aa671c09' THEN
    RAISE EXCEPTION '0486 P2: public.ottoq_sim_decide_and_dispatch is not the body this file patches';
  END IF;
  IF to_regprocedure('ottoq.ottoq_reassess_charge_needs(uuid,timestamp with time zone)') IS NOT NULL THEN
    RAISE EXCEPTION '0486 P2: ottoq.ottoq_reassess_charge_needs already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_event_types_catalog WHERE event_type = 'ottoq.need_reassessed') THEN
    RAISE EXCEPTION '0486 P2: the event type ottoq.need_reassessed already exists';
  END IF;
  -- the deriver still gives a car below its visit target a must-do charge, which is the rule copied below
  IF position($x$IF v_soc < v_visit_target - 1 THEN
    v_m := v_m || jsonb_build_object('svc','charge','must_do',true,'deferrable',false,$x$
              IN pg_get_functiondef('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0486 P2: the deriver no longer writes the charge atom this file copies';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0486_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamp with time zone,numeric)'::regprocedure,
                 'public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure);

-- ── (1) the twin: the drain is driven, not stamped ──
DO $patch_drain$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamp with time zone,numeric)'::regprocedure);
  v_pat_decl text := $p$(  v_recall_id      UUID;      -- 0212: the decision a refusal names
)$p$;
  v_new_decl text := $r$  v_recall_id      UUID;      -- 0212: the decision a refusal names
  v_out_drain_pct_h NUMERIC;  -- 0486: SoC points per hour a car is out, beyond what it drives
$r$;
  v_pat_rate text := $p$(  v_seed := abs\(hashtextextended\(COALESCE\(\(SELECT random_seed::text FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id\), '42'\) \|\| twin\.ottoq_sim_clock_salt\(p_sim_run_id, p_sim_clock_now\), 42\)\);
)$p$;
  v_new_rate text := $r$  v_seed := abs(hashtextextended(COALESCE((SELECT random_seed::text FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id), '42') || twin.ottoq_sim_clock_salt(p_sim_run_id, p_sim_clock_now), 42));
  -- 0486 (G219): THE DRAIN IS DRIVEN, NOT STAMPED. The scenario's arrival drain (a negative soc_on_arrival shift,
  -- never a positive one, since driving refills nothing) and the climate drain used to land in one step at the
  -- gate, so every reading before the gate was about 33 points high on busy_day. They are now SoC points per
  -- hour the car is out, drawn as power below, so the battery falls while the car drives.
  v_out_drain_pct_h := GREATEST(0, -COALESCE((SELECT (vp.knobs #>> '{soc_on_arrival,shift}')::numeric
                                                FROM ottoq_variability_profiles vp
                                               WHERE vp.sim_run_id = p_sim_run_id), 0))
                       + GREATEST(0, COALESCE(ottoq_twin_arrival_soc_drain(p_sim_run_id, p_sim_clock_now), 0));
$r$;
  v_pat_kw text := $p$(    v_discharge_kw := v_discharge_kw \* COALESCE\(v_dispatch\.v_cons_scalar, 1\.0\);
)$p$;
  v_new_kw text := $r$    v_discharge_kw := v_discharge_kw * COALESCE(v_dispatch.v_cons_scalar, 1.0);
    -- 0486 (G219): the out-drain as power, so it lands in the cumulative energy the SoC below is derived from.
    v_discharge_kw := v_discharge_kw + (v_out_drain_pct_h / 100.0) * COALESCE(v_dispatch.battery_capacity_kwh, 0);
$r$;
  v_pat_gate text := $p$current_soc = GREATEST\(2, LEAST\(100,
\s+ottoq_apply_profile\(p_sim_run_id, 'soc_on_arrival', v_new_soc, v_new_soc\) - ottoq_twin_arrival_soc_drain\(p_sim_run_id, p_sim_clock_now\)\)\),$p$;
  v_new_gate text := $r$current_soc = GREATEST(2, LEAST(100, v_new_soc)),  -- 0486 (G219): the drain landed on the way in$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat_decl, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0486: the declaration anchor matched % times, not once', n; END IF;
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat_rate, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0486: the seed line matched % times, not once', n; END IF;
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat_kw, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0486: the consumption scalar line matched % times, not once', n; END IF;
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat_gate, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0486: the gate SoC matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat_decl, v_new_decl);
  v_def := regexp_replace(v_def, v_pat_rate, v_new_rate);
  v_def := regexp_replace(v_def, v_pat_kw, v_new_kw);
  v_def := regexp_replace(v_def, v_pat_gate, v_new_gate);
  EXECUTE v_def;
END $patch_drain$;

-- ── (2) the kernel: an unmet need is an open need, and it is read again every tick ──
CREATE FUNCTION ottoq.ottoq_reassess_charge_needs(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'ottoq', 'twin', 'public', 'extensions'
AS $function$
/* 0486 (G219). The mirror of ottoq_close_satisfied_charge_needs, which closes a charge the car no longer needs.
   This opens one the car has grown since its visit was derived: a visit is derived once, at the recall, from the
   SoC the car had then, and the car keeps driving. The rule is the deriver's own charge rule (a car below its
   visit target minus 1 gets a must-do charge to that target), applied to the SoC the car has now.
   Only cars still coming in, at the gate or waiting in staging are read. A visit with any charge atom, whatever
   its status, is left alone, because a charge closed short of its target is closed on purpose (0463). */
DECLARE v_n int := 0; r record; v_min int;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;
  FOR r IN
    SELECT n.visit_id, n.vehicle_id, n.depot_id, n.atoms, n.archetype, n.urgency,
           COALESCE(n.target_soc, v.target_soc, public.ottoq_default_target_soc()) AS tgt,
           v.current_soc, v.current_state::text AS state, v.fleet_operator_id,
           v.battery_capacity_kwh, v.inlet_max_kw,
           (v.config->>'battery_soh_pct')::numeric AS soh,
           (v.config->>'charge_curve_scalar')::numeric AS curve,
           n.meta->'soc_at_arrival' AS derived_from
      FROM public.ottoq_visit_needs n
      JOIN public.vehicles v ON v.id = n.vehicle_id
     WHERE n.sim_run_id = p_sim_run_id
       AND n.status IN ('open','in_progress')
       AND jsonb_typeof(n.atoms) = 'array'
       AND v.current_soc IS NOT NULL
       AND v.current_state::text IN ('en_route_to_depot','arrived_at_gate','staged_awaiting_service')
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(n.atoms) a WHERE a->>'svc' = 'charge')
       AND v.current_soc < COALESCE(n.target_soc, v.target_soc, public.ottoq_default_target_soc()) - 1
     ORDER BY n.vehicle_id, n.visit_id
  LOOP
    v_min := GREATEST(8, round(COALESCE(
               public.ottoq_estimate_charge_minutes(r.current_soc, r.tgt, 150, COALESCE(r.inlet_max_kw, 150),
                                                    COALESCE(r.battery_capacity_kwh, 75), 25, COALESCE(r.soh, 95),
                                                    GREATEST(0.2, 1.0 / GREATEST(0.2, COALESCE(r.curve, 1.0)))), 25)))::int;
    UPDATE public.ottoq_visit_needs n
       SET atoms = jsonb_build_array(jsonb_build_object(
                     'svc', 'charge', 'must_do', true, 'deferrable', false, 'target_soc', r.tgt,
                     'est_min', v_min, 'concurrency', 'anchor',
                     'reassessed_at', p_clock, 'reassessed_soc', r.current_soc,
                     'derived_from_soc', r.derived_from)) || n.atoms,
           archetype = CASE WHEN n.archetype = 'M_pass_through_or_P_triage' THEN
                         CASE WHEN n.urgency = 'immediate_dispatch'
                                   AND EXISTS (SELECT 1 FROM jsonb_array_elements(n.atoms) e WHERE e->>'svc' = 'interior_tidy')
                                THEN 'A_charge_clean_go'
                              WHEN n.urgency = 'immediate_dispatch' THEN 'D_charge_and_go'
                              WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(n.atoms) e WHERE e->>'svc' = 'mechanical_pm')
                                THEN 'B_full_service'
                              ELSE 'std_mixed' END
                         ELSE n.archetype END,
           meta = COALESCE(n.meta, '{}'::jsonb) || jsonb_build_object('charge_reassessed',
                    jsonb_build_object('at', p_clock, 'soc', r.current_soc, 'state', r.state,
                                       'archetype_before', n.archetype))
     WHERE n.visit_id = r.visit_id;
    v_n := v_n + 1;
    BEGIN
      PERFORM ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'need_reassessment',
        p_event_type := 'ottoq.need_reassessed', p_entity_type := 'vehicle', p_entity_id := r.vehicle_id,
        p_fleet_operator_id := r.fleet_operator_id, p_depot_id := r.depot_id,
        p_payload := jsonb_build_object('visit_id', r.visit_id, 'svc', 'charge', 'soc', r.current_soc,
                                        'target_soc', r.tgt, 'derived_from_soc', r.derived_from,
                                        'state', r.state, 'est_min', v_min),
        p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  RETURN v_n;
END;
$function$;

REVOKE ALL ON FUNCTION ottoq.ottoq_reassess_charge_needs(uuid, timestamp with time zone) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION ottoq.ottoq_reassess_charge_needs(uuid, timestamp with time zone) TO service_role;

INSERT INTO public.ottoq_event_types_catalog (event_type, category, default_severity, description, introduced_in, emitter)
VALUES ('ottoq.need_reassessed', 'action', 'info',
        'OTTO-Q read a car again after its visit was derived and added a charge the car now needs (its SoC fell below '
        'the visit''s target with no charge planned). Payload: visit_id, soc, target_soc, derived_from_soc, state, est_min.',
        '0486', 'ottoq');

-- ── (2b) the tick reads it, beside its mirror ──
DO $patch_tick$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure);
  v_pat text := $p$(    BEGIN
      PERFORM ottoq\.ottoq_close_satisfied_charge_needs\(p_sim_run_id, v_run\.sim_clock_current\);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'close satisfied charge needs: %', SQLERRM;
    END;
)$p$;
  v_new text := $r$    BEGIN
      PERFORM ottoq.ottoq_close_satisfied_charge_needs(p_sim_run_id, v_run.sim_clock_current);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'close satisfied charge needs: %', SQLERRM;
    END;
    -- 0486 (G219): AN UNMET NEED IS AN OPEN NEED, AND IT IS READ AGAIN EVERY TICK.
    -- A visit is derived once, at the recall, from the SoC the car had then, and the car keeps driving. A car
    -- still coming in or waiting whose SoC is now below its visit target, with no charge planned, gets the charge
    -- the deriver would give it now. Never allowed to abort the tick.
    BEGIN
      PERFORM ottoq.ottoq_reassess_charge_needs(p_sim_run_id, v_run.sim_clock_current);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'reassess charge needs: %', SQLERRM;
    END;
$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0486: the satisfied-need block matched % times, not once', n; END IF;
  EXECUTE regexp_replace(v_def, v_pat, v_new);
END $patch_tick$;

-- ── (3) the catalog says what the knobs now do ──
UPDATE public.ottoq_variability_catalog
   SET generator  = 'twin.ottoq_sim_advance_deployed_telemetry',
       definition = 'Extra battery drain while a car is out, in SoC points per hour deployed: -30 drains 30 more points '
                 || 'each hour, so cars come back lower. Lower = more charging demand. Only negative values act: driving '
                 || 'refills nothing.',
       knob_types = ARRAY['shift']::text[],
       max_value  = 0
 WHERE var_key = 'soc_on_arrival';
UPDATE public.ottoq_variability_catalog SET wired = false WHERE var_key = 'arrival';

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_t text := pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamp with time zone,numeric)'::regprocedure);
  v_d text := pg_get_functiondef('public.ottoq_sim_decide_and_dispatch(uuid)'::regprocedure);
  v_f regprocedure := 'ottoq.ottoq_reassess_charge_needs(uuid,timestamp with time zone)'::regprocedure;
BEGIN
  -- V1: the gate applies no profile and no climate step, the out-drain is computed once before the cursor and
  -- drawn once inside it, and the webhook and ledger still take the SoC the car has.
  IF position('ottoq_apply_profile(p_sim_run_id, ''soc_on_arrival''' IN v_t) > 0
     OR (SELECT count(*) FROM regexp_matches(v_t, 'ottoq_twin_arrival_soc_drain', 'g')) <> 1
     OR (SELECT count(*) FROM regexp_matches(v_t, 'v_out_drain_pct_h :=', 'g')) <> 1
     OR position('v_out_drain_pct_h :=' IN v_t) > position('FOR v_dispatch IN' IN v_t)
     OR (SELECT count(*) FROM regexp_matches(v_t, $x$v_discharge_kw := v_discharge_kw \+ \(v_out_drain_pct_h / 100\.0\)$x$, 'g')) <> 1
     OR position('current_soc = GREATEST(2, LEAST(100, v_new_soc))' IN v_t) = 0
     OR position('soc_at_return_pct = v_new_soc' IN v_t) = 0 THEN
    RAISE EXCEPTION '0486 V1: the deployed telemetry is not the body this file writes';
  END IF;
  -- V2: the tick calls the re-assessment once, right after the satisfied-need close, inside the otto_q branch.
  IF (SELECT count(*) FROM regexp_matches(v_d, 'ottoq\.ottoq_reassess_charge_needs\(', 'g')) <> 1
     OR position('ottoq.ottoq_reassess_charge_needs(' IN v_d) < position('ottoq.ottoq_close_satisfied_charge_needs(' IN v_d)
     OR position('ottoq.ottoq_reassess_charge_needs(' IN v_d) > position('v_seat := COALESCE(public.ottoq_policy_get(p_sim_run_id, ''proposer_seat''' IN v_d) THEN
    RAISE EXCEPTION '0486 V2: the tick does not call the re-assessment where this file puts it';
  END IF;
  -- V3: one overload of each, the ACLs as intended.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_deployed_telemetry') <> 1
     OR (SELECT count(*) FROM pg_proc WHERE proname = 'ottoq_sim_decide_and_dispatch') <> 1
     OR (SELECT count(*) FROM pg_proc WHERE proname = 'ottoq_reassess_charge_needs') <> 1 THEN
    RAISE EXCEPTION '0486 V3: an overload appeared';
  END IF;
  IF has_function_privilege('anon', v_f, 'EXECUTE') OR has_function_privilege('authenticated', v_f, 'EXECUTE')
     OR NOT has_function_privilege('service_role', v_f, 'EXECUTE') THEN
    RAISE EXCEPTION '0486 V3: the re-assessment''s ACL is not service_role only';
  END IF;
  -- V4: a run of nothing is a no-op, and the catalog rows say what the knobs do.
  IF ottoq.ottoq_reassess_charge_needs(NULL, now()) <> 0 THEN
    RAISE EXCEPTION '0486 V4: the re-assessment did something with no run';
  END IF;
  IF (SELECT generator FROM public.ottoq_variability_catalog WHERE var_key = 'soc_on_arrival')
       <> 'twin.ottoq_sim_advance_deployed_telemetry'
     OR (SELECT wired FROM public.ottoq_variability_catalog WHERE var_key = 'arrival') THEN
    RAISE EXCEPTION '0486 V4: the catalog rows are not what this file writes';
  END IF;
END $verify$;

-- Rollback: restore both functions from ottoq_schema_snapshots label '0486_pre' (CREATE OR REPLACE; ACLs kept),
-- DROP FUNCTION ottoq.ottoq_reassess_charge_needs(uuid, timestamp with time zone), delete the event type row, and
-- restore the two catalog rows (generator ottoq_sim_dispatch_vehicle, the old definition, knob_types
-- {shift,spread,floor,ceiling}, max_value 40; arrival wired true).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0486_the_battery_drains_while_the_car_is_out_and_otto_q_rereads_its_charge_need_every_tick', true,
  'Tick path: twin.ottoq_sim_advance_deployed_telemetry drains the scenario and climate arrival drain as power while '
  'the car is out (no step at the gate), and ottoq_sim_decide_and_dispatch calls the new '
  'ottoq.ottoq_reassess_charge_needs every tick, adding the charge a car below its visit target now needs.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
