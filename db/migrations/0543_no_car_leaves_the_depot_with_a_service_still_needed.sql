-- migration-version: 20260928013804
-- migration-name:    no_car_leaves_the_depot_with_a_service_still_needed
--
-- 0543  **No car leaves the depot with a service still needed, ever. A car that is not finished is re-orchestrated,
--        never released.**
--
-- ══ §1 WHY (Chase, 2026-09-27 8:00 PM CT; CLAUDE.md rule 9; G268) ═══════════════════════════════════════════════════
--
--   Chase: "vehicles cannot leave the depot with any remaining service still needed, EVER. Re-optimizations can occur,
--   especially if there is a delay, or flagging, or hardware fault, etc. This is what OTTO-Q should optimize for, and can
--   always use temporary or perimeter parking if needed, while temporary re-orchestration occurs. If there is an
--   immediate option that otto-q identifies for a re-submission, the vehicle can go straight to that next reservation or
--   stall without the temporary staging recommendation. Again, OTTO-Q has to be all seeing and all knowing."
--
--   Measured on validation run c9d14225 (the first operator day under 0539-0541), from the signed state stream and each
--   departure's visit as it stood when the car left:
--     - 93 departures. **10 left with work still open**, all of it work the engine had marked optional: exterior wash
--       (5), preventive maintenance (2), sensor calibration (2), deep clean (2). None left with required work open.
--     - **22 departures had no visit record**: cars the boot placed ready in `staged_for_departure`, sent out between
--       5:00 and 6:57 AM CT sim. **10 of them left below 99%** (as low as 80%). Neither dispatcher checks a car's charge
--       against its target. The deploy plan asks only for 80%, and a car with no visit has no charge need on record.
--       (4 more, at 87-93%, are the boot's prime deployment: cars already out when the day starts, not departures.)
--   Ten functions create a service as optional (`must_do = false`): the need deriver for remote diagnostics, software
--   update, sensor calibration, preventive maintenance and cosmetic repair, plus a wash that is not yet overdue and a
--   scheduled deep clean; the triage's escalations (a deep clean after a failed tidy, a sensor calibration after a
--   failed sensor clean); and the opportunistic top-off. `ottoq_atoms_guard` demoted a required service to optional
--   when no executor was registered for it. `software_update` was missing from that registry, although the concurrent
--   atom starter performs every digital atom. The triage deferred a car's deferrable services to an overnight crew and
--   released the car.
--
--   Found while tracing where a held car goes, each of which would have stranded cars once every service is required:
--     - The readiness gate counted only required services (`must_do`), so it could release a car the dispatchers now
--       refuse, and the recheck below would take it back every tick.
--     - The decide tick's bay admission (4b) takes wash and detail work only from the needs card's `must_do_now`, which
--       is computed from the car's profile, not from its visit. A wash on the visit that the card does not call due has
--       no door from staging: the wash lane in the service flow takes only cars coming off a charger.
--     - (4b) also skips any car short of `vehicles.target_soc` (100), while the charge cursor charges only a car below
--       its target - 1 (G244). A car at 99% with a wash open is taken by neither.
--     - Nothing takes a car off `need_charge` except the charge cursor, which takes it only below target - 1. A car
--       sent to wait for a charger it no longer needs waits for good.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) Every service OTTO-Q finds a car to need is required. The ten creators write `must_do = true`, and `deferrable`
--       stays as an urgency hint: it may wait until later in the visit, never past departure. The atoms guard no longer
--       demotes; it marks a service with no registered executor `no_executor` and leaves it required. `software_update`
--       joins the registry. The triage defers nothing (`deferred_services` is empty), so nothing is left for an
--       overnight crew.
--   (b) One answer to "may this car leave": `public.ottoq_departure_clear(car, run, clock, need_readiness)`. It requires
--       the car's SoC at its effective target - 1 (the one rule for whether a car needs a charge, G244), and no open or
--       in-progress service of any kind on its open visit. With need_readiness it also requires the readiness check.
--   (c) Both dispatchers require it: the deploy plan (`ottoq.ottoq_plan_dispatch_tick`) and the decide tick's
--       redeployment.
--   (d) Re-orchestration, not release: `twin.ottoq_sim_departure_recheck` runs each tick before the readiness gate.
--       - A car staged to leave (`staged_for_departure`, or staged `ready`) that is not clear goes back to what it
--         needs: below its charge target - 1, `need_charge`, where the charge cursor takes it to the next free charger;
--         service-bay work, `need_service`; wash or detail work, `need_deploy`, held by the gate and admitted to a bay
--         from staging. It stays on the stall it is parked on until its charger or bay is free (the temporary parking),
--         and goes straight there when one is. In-place work (cabin, exterior, digital) runs where the car is, and a
--         charge step at target - 1 is the flow contract's to close; for those the car stays and the dispatchers wait.
--       - A car on `need_charge` that no longer needs a charge (at its target - 1, no charge step open) goes back to the
--         gate (`need_deploy`), which routes it to what it needs next or releases it.
--   (e) The readiness gate asks what the dispatchers ask: its ready charge is the car's target - 1, not the 80% deploy
--       floor, and it counts every open service, not only the required ones. It stops releasing a car it would only
--       have to take back.
--   (f) The decide tick's bay admission (4b) also admits a staged car for any wash or detail service open on its visit,
--       and it leaves to the charge cursor only a car the cursor would charge (below its target - 1).
--
-- ══ §3 forces_recert TRUE; forces_dial_restart TRUE ═══════════════════════════════════════════════════════════════════
--
--   Every arm derives needs, triages, admits to bays and dispatches, so certified digests and dial arms can move.
--
-- ══ §4 NOT IN THIS FILE ═══════════════════════════════════════════════════════════════════════════════════════════════
--
--   A structural refusal. After this file a departure with open needs is refused by predicate at both dispatchers, not
--   by the schema. The trigger that rejects the write comes after the validation run shows zero such departures:
--   measure first, then enforce, as with every other promotion. Also out of scope, and recorded:
--   - The boot's prime deployment (`twin.ottoq_sim_prime_deployment`) sets initial conditions, cars already out at the
--     day's start, not departures.
--   - The C5 baselines (`ottoq_fifo_tick`, `ottoq_manual_tick`) run in no operator path.
--   - `ottoq_l2_propose_service` still records `promote_ready` with `deferred_service` when a service bay is busy. Since
--     0469 that verdict emits no command (the gate releases), so nothing is deferred, but the decision row still says so.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0543 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: each function is the one measured (md5 of its source, 2026-09-28 01:15 UTC) ──
DO $premises$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('ottoq.ottoq_plan_dispatch_tick(text,uuid,uuid,timestamp with time zone,integer,bigint,integer,integer,integer,integer,integer,numeric,jsonb,boolean)', '45fa9aa0906cbe80001cae66f5fc1012'),
      ('public.ottoq_decide_tick(uuid)',                                                                  '90368fa3f6dd001c6562bd6912c23f2e'),
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)',                 'ae2a62233a3d21e1a816fa9d857cab06'),
      ('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)',              'c0a565de6e1d1a4f0c3577cd5573c9f1'),
      ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)',                               '28fc41010ccdfd350c623b101992e7f6'),
      ('ottoq.ottoq_enact_opportunistic_charge(uuid,uuid,numeric,numeric,timestamp with time zone)',      '9f8f16a318ed361c471bdc4f6452a07f'),
      ('ottoq.ottoq_atom_retirable_set()',                                                                '90ad3c4a77ec28bfe96b9f9dde2eb2de'),
      ('ottoq.ottoq_decide_wash_triage(uuid,uuid,jsonb,integer,integer,timestamp with time zone)',        '2bb88c2e5c5efc54d431d75aa2b2a7b6'),
      ('ottoq.ottoq_atoms_guard(jsonb)',                                                                  'ac5db6898ce77b2a6f0870db9016dd3f')
    ) AS t(sig, want) LOOP
    IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = r.sig::regprocedure) <> r.want THEN
      RAISE EXCEPTION '0543 P2: % is not the function measured', r.sig;
    END IF;
  END LOOP;
  IF to_regprocedure('public.ottoq_departure_clear(uuid,uuid,timestamp with time zone,boolean)') IS NOT NULL
     OR to_regprocedure('twin.ottoq_sim_departure_recheck(uuid,timestamp with time zone,uuid)') IS NOT NULL THEN
    RAISE EXCEPTION '0543 P2: a function this file creates already exists';
  END IF;
  -- the transition the recheck writes is in the catalog SM.001 judges
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_state_transitions
                  WHERE entity_kind = 'vehicle' AND status = 'active'
                    AND from_state = 'staged_for_departure' AND to_state = 'staged_awaiting_service') THEN
    RAISE EXCEPTION '0543 P2: staged_for_departure -> staged_awaiting_service is not a catalogued transition';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0543_pre', 'function', f.sch, f.obj, pg_get_functiondef(f.sig::regprocedure), md5(pg_get_functiondef(f.sig::regprocedure))
  FROM (VALUES ('ottoq',  'ottoq_plan_dispatch_tick',        'ottoq.ottoq_plan_dispatch_tick(text,uuid,uuid,timestamp with time zone,integer,bigint,integer,integer,integer,integer,integer,numeric,jsonb,boolean)'),
               ('public', 'ottoq_decide_tick',               'public.ottoq_decide_tick(uuid)'),
               ('twin',   'ottoq_sim_advance_service_flow',  'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'),
               ('ottoq',  'ottoq_derive_visit_needs',        'ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)'),
               ('twin',   'ottoq_sim_advance_visit_atoms',   'twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'),
               ('ottoq',  'ottoq_enact_opportunistic_charge','ottoq.ottoq_enact_opportunistic_charge(uuid,uuid,numeric,numeric,timestamp with time zone)'),
               ('ottoq',  'ottoq_atom_retirable_set',        'ottoq.ottoq_atom_retirable_set()'),
               ('ottoq',  'ottoq_decide_wash_triage',        'ottoq.ottoq_decide_wash_triage(uuid,uuid,jsonb,integer,integer,timestamp with time zone)'),
               ('ottoq',  'ottoq_atoms_guard',               'ottoq.ottoq_atoms_guard(jsonb)')
       ) AS f(sch, obj, sig);

-- ── (b) one answer to "may this car leave" ──
CREATE FUNCTION public.ottoq_departure_clear(p_vehicle_id uuid, p_sim_run_id uuid, p_clock timestamptz,
                                             p_need_readiness boolean DEFAULT true)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
  -- 0543 (CLAUDE.md rule 9, Chase 2026-09-27): a car leaves only when nothing it needs is left. Its charge is at its
  -- effective target - 1 (G244's one rule), and no service on its open visit is open or in progress. With
  -- p_need_readiness the readiness check must be done too (the dispatchers). Without it (the recheck) the readiness
  -- check is left to the staging it is done in. A car with no SoC on record is not clear.
  SELECT COALESCE(v.current_soc >= public.ottoq_effective_target_soc_at(v.id, p_clock) - 1, false)
     AND NOT EXISTS (
           SELECT 1
             FROM public.ottoq_visit_needs vn
             CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
            WHERE vn.vehicle_id = v.id
              AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
              AND vn.status IN ('open', 'in_progress')
              AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled')
              AND (p_need_readiness OR a->>'svc' <> 'readiness_check'))
    FROM public.vehicles v
   WHERE v.id = p_vehicle_id;
$fn$;
COMMENT ON FUNCTION public.ottoq_departure_clear(uuid, uuid, timestamptz, boolean) IS
  '0543 (CLAUDE.md rule 9): true only when the car may leave the depot: charge at its effective target - 1 and no open '
  'or in-progress service of any kind on its open visit (and, with p_need_readiness, its readiness check done). Both '
  'dispatchers require it.';

-- ── (d) re-orchestration: a car staged to leave that is not finished goes back to what it needs ──
CREATE FUNCTION twin.ottoq_sim_departure_recheck(p_sim_run_id uuid, p_sim_clock_now timestamptz, p_depot_id uuid)
RETURNS integer LANGUAGE plpgsql SET search_path = twin, ottoq, public, extensions AS $fn$
DECLARE v_rec record; v_remedy text; v_n int := 0; v_back int := 0;
        v_moved jsonb := '[]'::jsonb; v_back_cars jsonb := '[]'::jsonb;
BEGIN
  -- 0543 (CLAUDE.md rule 9). (1) A car in staged_for_departure (or staged and 'ready') that is not departure-clear
  -- was staged to leave too early. It goes back to what it needs. Below its charge target - 1: need_charge, and the
  -- charge cursor takes it to the next free charger. Service-bay work: need_service. Wash or detail work: need_deploy,
  -- where the readiness gate holds it and the bay admission takes it from staging. Until then it stays where it is
  -- parked, which is the temporary parking. In-place work (cabin, exterior, digital) is left to finish where the car
  -- is, and a charge step at target - 1 is the flow contract's to close; the dispatchers wait for both.
  FOR v_rec IN
    SELECT v.id, v.current_soc, public.ottoq_effective_target_soc_at(v.id, p_sim_clock_now) AS tgt,
           o.open_svcs, o.open_svc_bay, o.open_wash_detail
      FROM vehicles v
      CROSS JOIN LATERAL (
        SELECT COALESCE(array_agg(DISTINCT a->>'svc' ORDER BY a->>'svc'), ARRAY[]::text[]) AS open_svcs,
               COALESCE(bool_or(cp.lane = 'service_bay'), false)           AS open_svc_bay,
               COALESCE(bool_or(cp.lane IN ('wash_bay', 'detail')), false) AS open_wash_detail
          FROM ottoq_visit_needs vn
          CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
          LEFT JOIN service_cadence_policy cp ON cp.svc = a->>'svc' AND cp.is_active
         WHERE vn.vehicle_id = v.id AND vn.sim_run_id = p_sim_run_id AND vn.status IN ('open', 'in_progress')
           AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled')
           AND a->>'svc' <> 'readiness_check') o
     WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
       AND (v.current_state = 'staged_for_departure'
            OR (v.current_state = 'staged_awaiting_service' AND COALESCE(v.config->>'svc_step', 'ready') = 'ready'))
       AND NOT public.ottoq_departure_clear(v.id, p_sim_run_id, p_sim_clock_now, false)
     ORDER BY v.id
  LOOP
    v_remedy := CASE
                  WHEN v_rec.current_soc IS NULL OR v_rec.current_soc < v_rec.tgt - 1 THEN 'need_charge'
                  WHEN v_rec.open_svc_bay                                           THEN 'need_service'
                  WHEN v_rec.open_wash_detail                                       THEN 'need_deploy'
                  ELSE NULL END;
    CONTINUE WHEN v_remedy IS NULL;
    UPDATE vehicles
       SET current_state = 'staged_awaiting_service'::vehicle_state, last_state_change = p_sim_clock_now,
           config = jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}', to_jsonb(v_remedy))
                    || jsonb_build_object('departure_hold', jsonb_build_object(
                         'at', p_sim_clock_now, 'run', p_sim_run_id, 'remedy', v_remedy,
                         'soc', v_rec.current_soc, 'target_soc', v_rec.tgt, 'open', to_jsonb(v_rec.open_svcs)))
     WHERE id = v_rec.id;
    v_n := v_n + 1;
    v_moved := v_moved || jsonb_build_array(jsonb_build_object('vehicle_id', v_rec.id, 'remedy', v_remedy,
                 'soc', v_rec.current_soc, 'target_soc', v_rec.tgt, 'open', to_jsonb(v_rec.open_svcs)));
  END LOOP;

  -- (2) A car waiting for a charger it no longer needs (at its target - 1, no charge step open) goes back to the
  -- readiness gate, which routes it to what it needs next or releases it. The charge cursor takes a car only below
  -- its target - 1, and nothing else takes a car off need_charge.
  WITH back AS (
    UPDATE vehicles v
       SET config = jsonb_set(COALESCE(v.config, '{}'::jsonb), '{svc_step}', to_jsonb('need_deploy'::text))
     WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
       AND v.current_state = 'staged_awaiting_service' AND v.config->>'svc_step' = 'need_charge'
       AND COALESCE(v.current_soc >= public.ottoq_effective_target_soc_at(v.id, p_sim_clock_now) - 1, false)
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                         CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
                        WHERE vn.vehicle_id = v.id AND vn.sim_run_id = p_sim_run_id
                          AND vn.status IN ('open', 'in_progress')
                          AND a->>'svc' = 'charge' AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'cancelled'))
    RETURNING v.id, v.current_soc)
  SELECT count(*), COALESCE(jsonb_agg(jsonb_build_object('vehicle_id', b.id, 'soc', b.current_soc) ORDER BY b.id), '[]'::jsonb)
    INTO v_back, v_back_cars FROM back b;

  IF v_n + v_back > 0 THEN
    PERFORM ottoq_record_event(p_actor_type := 'ottoq_engine', p_actor_id := 'departure_recheck',
      p_event_type := 'twin.departure_recheck', p_entity_type := 'depot', p_entity_id := p_depot_id,
      p_payload := jsonb_build_object('rerouted', v_n, 'cars', v_moved,
        'back_to_gate', v_back, 'back_cars', v_back_cars,
        'note', 'a car staged to leave that is not finished goes back to its charge or bay; a car that no longer needs '
                || 'a charge goes back to the gate (CLAUDE.md rule 9)'),
      p_severity := CASE WHEN v_n > 0 THEN 'warning' ELSE 'info' END,
      p_ingest_source := 'twin', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
  END IF;
  RETURN v_n + v_back;
END;
$fn$;
COMMENT ON FUNCTION twin.ottoq_sim_departure_recheck(uuid, timestamptz, uuid) IS
  '0543 (CLAUDE.md rule 9): each tick, before the readiness gate, a car staged to leave that is not departure-clear goes '
  'back to its charge (need_charge), its service bay (need_service) or its wash or detail bay (need_deploy), and a car '
  'waiting for a charger it no longer needs goes back to the gate. It is re-orchestrated, never released.';

-- ── (a) every service found needed is required; (c) both dispatchers require the one answer; (e) the gate asks what
--    the dispatchers ask; (f) the bay admission reads the visit; the recheck runs before the gate ──
DO $patches$
DECLARE v_def text; r record; n int; v_sig text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      -- the need deriver: seven creators of optional work
      ('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)', 1,
       $o$'svc','remote_diagnostics','must_do',false$o$, $n$'svc','remote_diagnostics','must_do',true$n$),
      ('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)', 2,
       $o$'svc','software_update','must_do',false$o$, $n$'svc','software_update','must_do',true$n$),
      ('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)', 3,
       $o$'svc','sensor_calibration','must_do',false$o$, $n$'svc','sensor_calibration','must_do',true$n$),
      ('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)', 4,
       $o$'svc','mechanical_pm','must_do',false$o$, $n$'svc','mechanical_pm','must_do',true$n$),
      ('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)', 5,
       $o$'svc','cosmetic_repair','must_do',false$o$, $n$'svc','cosmetic_repair','must_do',true$n$),
      ('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)', 6,
       $o$'must_do', v_deep_clean_due, 'deferrable', NOT v_deep_clean_due,$o$,
       $n$'must_do', true, 'deferrable', NOT v_deep_clean_due,$n$),
      ('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)', 7,
       $o$'must_do', v_wash_overdue, 'deferrable', NOT v_wash_overdue,$o$,
       $n$'must_do', true, 'deferrable', NOT v_wash_overdue,$n$),
      -- the triage's escalations
      ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)', 8,
       $o$'svc','interior_deep_clean','must_do',false$o$, $n$'svc','interior_deep_clean','must_do',true$n$),
      ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)', 9,
       $o$'svc','sensor_calibration','must_do',false$o$, $n$'svc','sensor_calibration','must_do',true$n$),
      -- a started top-off finishes before the car leaves (rule 9: a charge is never ended early)
      ('ottoq.ottoq_enact_opportunistic_charge(uuid,uuid,numeric,numeric,timestamp with time zone)', 10,
       $o$'svc','charge','must_do',false$o$, $n$'svc','charge','must_do',true$n$),
      -- the concurrent atom starter performs every digital atom, software_update included
      ('ottoq.ottoq_atom_retirable_set()', 11,
       $o$'remote_diagnostics','perimeter_walkaround'])$o$, $n$'remote_diagnostics','perimeter_walkaround','software_update'])$n$),
      -- the triage defers nothing: a car leaves with no service left for an overnight crew
      ('ottoq.ottoq_decide_wash_triage(uuid,uuid,jsonb,integer,integer,timestamp with time zone)', 12,
       $o$  SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(p_manifest) e
    WHERE COALESCE((e->>'deferrable')::boolean,false)
    INTO v_deferrable;$o$,
       $n$  -- 0543 (CLAUDE.md rule 9): nothing is deferred past departure. Every service the visit carries is done before
  -- the car leaves, so no deferred list is written for an overnight crew.
  v_deferrable := '[]'::jsonb;$n$),
      -- the deploy plan
      ('ottoq.ottoq_plan_dispatch_tick(text,uuid,uuid,timestamp with time zone,integer,bigint,integer,integer,integer,integer,integer,numeric,jsonb,boolean)', 13,
       $o$AND NOT public.ottoq_vehicle_is_tethered(v.id, p_sim_clock_now)$o$,
       $n$AND NOT public.ottoq_vehicle_is_tethered(v.id, p_sim_clock_now)
           -- 0543 (CLAUDE.md rule 9): a car leaves only with nothing it needs left, its charge at target included
           AND public.ottoq_departure_clear(v.id, p_sim_run_id, p_sim_clock_now, true)$n$),
      -- the decide tick's redeployment
      ('public.ottoq_decide_tick(uuid)', 14,
       $o$AND v.current_state='staged_for_departure'$o$,
       $n$AND v.current_state='staged_for_departure'
       AND public.ottoq_departure_clear(v.id, p_sim_run_id, v_clock, true)   /* 0543 (CLAUDE.md rule 9) */$n$),
      -- (f) the bay admission leaves to the charge cursor only a car the cursor would charge (G244's one rule)
      ('public.ottoq_decide_tick(uuid)', 15,
       $o$OR COALESCE(c.soc_deficit_to_target, 0) > 0)$o$,
       $n$OR COALESCE(c.soc_pct, 0) < public.ottoq_effective_target_soc_at(c.vehicle_id, v_clock) - 1)   /* 0543: the one charge rule (G244); the card's deficit is to 100 and left a car at 99% to neither */$n$),
      -- (f) and admits a staged car for any wash or detail service open on its visit
      ('public.ottoq_decide_tick(uuid)', 16,
       $o$CROSS JOIN LATERAL unnest(k.must_do_now) AS x(svc)$o$,
       $n$-- 0543 (CLAUDE.md rule 9): the card's must-do list and every wash or detail service still open on the car's
            -- visit. Every service OTTO-Q finds a car to need is required, and a staged car has no other door to those
            -- bays: the service flow's wash lane takes only cars coming off a charger.
            CROSS JOIN LATERAL (SELECT DISTINCT u.svc
                                  FROM unnest(COALESCE(k.must_do_now, '{}'::text[])
                                              || ARRAY(SELECT a->>'svc'
                                                         FROM ottoq_visit_needs vn
                                                         CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
                                                         JOIN public.service_cadence_policy cp
                                                           ON cp.svc = a->>'svc' AND cp.is_active
                                                          AND cp.lane IN ('wash_bay','detail')
                                                        WHERE vn.vehicle_id = k.vehicle_id AND vn.sim_run_id = p_sim_run_id
                                                          AND vn.status IN ('open','in_progress')
                                                          AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'))) AS u(svc)) AS x(svc)$n$),
      -- (e) the readiness gate reads the car's charge target, not the deploy floor
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)', 17,
       $o$GREATEST(v_floor, COALESCE(k.min_ready_soc_pct, v_floor)) AS ready_soc,$o$,
       $n$GREATEST(v_floor, COALESCE(k.min_ready_soc_pct, v_floor),
                        public.ottoq_effective_target_soc_at(cd.id, p_sim_clock_now) - 1) AS ready_soc,   /* 0543 */$n$),
      -- (e) and counts every open service, as the dispatchers now do
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)', 18,
       $o$WHERE COALESCE((a->>'must_do')::boolean,false) = true
                                         AND a->>'svc' <> 'readiness_check'$o$,
       $n$WHERE a->>'svc' <> 'readiness_check'   /* 0543 (CLAUDE.md rule 9): every open service, as the dispatchers ask */$n$),
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)', 19,
       $o$             AND COALESCE((a->>'must_do')::boolean,false) = true
             AND a->>'svc' <> 'readiness_check'
             AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled');$o$,
       $n$             AND a->>'svc' <> 'readiness_check'   /* 0543: the remedy follows every open service */
             AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled');$n$),
      -- (d) the recheck runs each tick, before the gate
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)', 20,
       $o$v_gate_on      := COALESCE(ottoq_policy_get(p_sim_run_id,'deploy_ready_gate_enabled',1),1) > 0;$o$,
       $n$-- 0543 (CLAUDE.md rule 9): a car staged to leave that is not finished goes back to what it needs first, and a car
  -- waiting for a charger it no longer needs comes back to this gate.
  PERFORM twin.ottoq_sim_departure_recheck(p_sim_run_id, p_sim_clock_now, p_depot_id);
  v_gate_on      := COALESCE(ottoq_policy_get(p_sim_run_id,'deploy_ready_gate_enabled',1),1) > 0;$n$)
    ) AS t(sig, k, o, nw) ORDER BY k LOOP
    IF v_sig IS DISTINCT FROM r.sig THEN
      IF v_sig IS NOT NULL THEN EXECUTE v_def; END IF;
      v_sig := r.sig; v_def := pg_get_functiondef(r.sig::regprocedure);
    END IF;
    n := (length(v_def) - length(replace(v_def, r.o, ''))) / length(r.o);
    IF n <> 1 THEN RAISE EXCEPTION '0543 patch %: the text matches % times in %, not 1', r.k, n, r.sig; END IF;
    v_def := replace(v_def, r.o, r.nw);
  END LOOP;
  EXECUTE v_def;
END $patches$;

-- ── (a) the atoms guard never demotes ──
DO $guard$
DECLARE v_def text; n int;
  c_pat CONSTANT text := $p$jsonb_build_object\('must_do',\s*false,\s*'guard_demoted',\s*true,\s*'guard_reason',\s*'svc_not_retirable'\)$p$;
BEGIN
  v_def := pg_get_functiondef('ottoq.ottoq_atoms_guard(jsonb)'::regprocedure);
  n := (SELECT count(*) FROM regexp_matches(v_def, c_pat, 'g'));
  IF n <> 1 THEN RAISE EXCEPTION '0543 guard: the demotion matches % times, not 1', n; END IF;
  -- 0543 (CLAUDE.md rule 9): a service with no registered executor stays required; it is marked so a person sees it
  EXECUTE regexp_replace(v_def, c_pat, $r$jsonb_build_object('no_executor', true, 'guard_reason', 'svc_not_retirable')$r$);
END $guard$;

-- ── V1 (comment-stripped): each function says what §2 says it says ──
DO $verify$
DECLARE r record; v_src text; n int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('ottoq.ottoq_derive_visit_needs(uuid,uuid,uuid,timestamp with time zone,uuid,jsonb)',
       ARRAY['''svc'',''remote_diagnostics'',''must_do'',true', '''svc'',''software_update'',''must_do'',true',
             '''svc'',''sensor_calibration'',''must_do'',true', '''svc'',''mechanical_pm'',''must_do'',true',
             '''svc'',''cosmetic_repair'',''must_do'',true'],
       ARRAY['''must_do'', v_deep_clean_due', '''must_do'', v_wash_overdue']),
      ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)',
       ARRAY['''svc'',''interior_deep_clean'',''must_do'',true', '''svc'',''sensor_calibration'',''must_do'',true'],
       ARRAY[]::text[]),
      ('ottoq.ottoq_enact_opportunistic_charge(uuid,uuid,numeric,numeric,timestamp with time zone)',
       ARRAY['''svc'',''charge'',''must_do'',true'], ARRAY[]::text[]),
      ('ottoq.ottoq_atom_retirable_set()', ARRAY['''software_update'''], ARRAY[]::text[]),
      ('ottoq.ottoq_atoms_guard(jsonb)', ARRAY['''no_executor'', true'], ARRAY['guard_demoted']),
      ('ottoq.ottoq_decide_wash_triage(uuid,uuid,jsonb,integer,integer,timestamp with time zone)',
       ARRAY['v_deferrable := ''[]''::jsonb;'], ARRAY['INTO v_deferrable']),
      ('ottoq.ottoq_plan_dispatch_tick(text,uuid,uuid,timestamp with time zone,integer,bigint,integer,integer,integer,integer,integer,numeric,jsonb,boolean)',
       ARRAY['public.ottoq_departure_clear(v.id, p_sim_run_id, p_sim_clock_now, true)'], ARRAY[]::text[]),
      ('public.ottoq_decide_tick(uuid)',
       ARRAY['public.ottoq_departure_clear(v.id, p_sim_run_id, v_clock, true)',
             'COALESCE(c.soc_pct, 0) < public.ottoq_effective_target_soc_at(c.vehicle_id, v_clock) - 1',
             'unnest(COALESCE(k.must_do_now, ''{}''::text[])', 'cp.lane IN (''wash_bay'',''detail'')'],
       ARRAY['c.soc_deficit_to_target, 0) > 0', 'unnest(k.must_do_now) AS x(svc)']),
      ('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)',
       ARRAY['twin.ottoq_sim_departure_recheck(p_sim_run_id, p_sim_clock_now, p_depot_id)',
             'public.ottoq_effective_target_soc_at(cd.id, p_sim_clock_now) - 1'],
       ARRAY['COALESCE((a->>''must_do'')::boolean,false) = true'])
    ) AS t(sig, must, mustnt) LOOP
    v_src := regexp_replace(regexp_replace(pg_get_functiondef(r.sig::regprocedure), '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g');
    IF EXISTS (SELECT 1 FROM unnest(r.must) m WHERE position(m IN v_src) = 0) THEN
      RAISE EXCEPTION '0543 V1: % lacks one of %', r.sig, r.must;
    END IF;
    IF EXISTS (SELECT 1 FROM unnest(r.mustnt) m WHERE position(m IN v_src) > 0) THEN
      RAISE EXCEPTION '0543 V1: % still carries one of %', r.sig, r.mustnt;
    END IF;
  END LOOP;
  -- the census that found the ten: no live function builds a service atom as anything but required
  SELECT count(*) INTO n
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace,
         regexp_matches(regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'gs'), '--[^\n]*', '', 'g'),
                        '''svc''\s*,\s*([^,]+?)\s*,\s*''must_do''\s*,\s*([^,]+?)\s*,', 'g') m
   WHERE ns.nspname IN ('public', 'twin', 'ottoq') AND p.prokind = 'f' AND p.proname NOT LIKE 'ottoq_fn_backup%'
     AND m[2] !~* '^true$';
  IF n <> 0 THEN RAISE EXCEPTION '0543 V1: % service atom(s) are still built optional', n; END IF;
  -- every service the deriver can name has an executor
  IF EXISTS (SELECT 1 FROM public.service_cadence_policy c
              WHERE c.is_active AND NOT (c.svc = ANY (ottoq.ottoq_atom_retirable_set()))) THEN
    RAISE EXCEPTION '0543 V1: a catalogued service has no registered executor: %',
      (SELECT string_agg(c.svc, ', ') FROM public.service_cadence_policy c
        WHERE c.is_active AND NOT (c.svc = ANY (ottoq.ottoq_atom_retirable_set())));
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0543_no_car_leaves_the_depot_with_a_service_still_needed', true, true,
  'Rule 9 (Chase 2026-09-27 8 PM CT: no car leaves with a service still needed, ever): every service found needed is '
  'required (ten optional creators flipped, the guard never demotes, the triage defers nothing); one departure predicate '
  '(charge at target - 1, no open service) at both dispatchers; a recheck sends a car staged to leave but unfinished back '
  'to its charge or bay and a car that no longer needs a charge back to the gate; the readiness gate asks what the '
  'dispatchers ask; the bay admission reads the visit''s open wash and detail work. Every arm derives, triages, admits '
  'and dispatches.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back, on the ended validation run c9d14225 (its cars and visits are still on record):
--   (a) the predicate: a full car with one open wash is not clear; with the wash done it is; at 95% it is not; with the
--       readiness check pending it is clear only without p_need_readiness.
--   (b) the recheck: a car staged to leave at 90% with nothing open goes to need_charge; at 100% with an open wash to
--       need_deploy; at 100% with an open walkaround it stays staged (in-place work); a clear car stays staged.
--   (b2) the recheck's second pass: the 90% car, now full with no charge step open, goes back to the gate (need_deploy).
--   (c) the deploy plan: of two staged cars, the clear one is offered and the unclear one is not.
--   (d) the guard: a required service with no executor stays required and is marked no_executor.
DO $v3$
DECLARE
  v_msg text; v_run uuid := 'c9d14225-a7e6-4cf8-b4b7-7b652db9b283'; v_twin uuid := '11111111-1111-1111-1111-111111111111';
  v_clock timestamptz; v_cars uuid[]; c1 uuid; c2 uuid; c3 uuid; c4 uuid; v_visit uuid;
  a1 boolean; a2 boolean; a3 boolean; a4 boolean; a5 boolean;
  s1 text; s2 text; s3 text; s4 text; st1 text; st2 text; st3 text; st4 text; v_n int; v_n2 int; v_n3 int; s1b text;
  v_plan jsonb; v_offered jsonb; v_guard jsonb;
BEGIN
  BEGIN
    SELECT r.sim_clock_current INTO v_clock FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run;
    IF v_clock IS NULL THEN RAISE EXCEPTION '0543 V3: run % is gone; point V3 at a run that exists', v_run; END IF;
    -- four twin cars that nothing else holds at the clock: no live dispatch, not tethered, no rider flag due
    SELECT array_agg(id ORDER BY id) INTO v_cars FROM (
      SELECT v.id FROM public.vehicles v
       WHERE v.home_depot_id = v_twin AND v.category = 'autonomous'
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches d
                          WHERE d.vehicle_id = v.id AND d.sim_run_id = v_run AND d.status IN ('active', 'returning'))
         AND NOT public.ottoq_vehicle_is_tethered(v.id, v_clock)
         AND NOT public.ottoq_rider_flag_due(v.id, v_run, v_clock)
       ORDER BY v.id LIMIT 4) q;
    IF coalesce(array_length(v_cars, 1), 0) < 4 THEN RAISE EXCEPTION '0543 V3: fewer than four free twin cars'; END IF;
    c1 := v_cars[1]; c2 := v_cars[2]; c3 := v_cars[3]; c4 := v_cars[4];
    UPDATE public.ottoq_visit_needs SET status = 'superseded'
     WHERE vehicle_id = ANY (v_cars) AND sim_run_id = v_run AND status IN ('open', 'in_progress');
    UPDATE public.vehicles SET current_state = 'staged_for_departure'::vehicle_state, current_soc = 100,
                               config = jsonb_set(COALESCE(config, '{}'::jsonb), '{svc_step}', '"ready"')
     WHERE id = ANY (v_cars);

    -- (a) the predicate, on c1
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, status)
    VALUES (c1, v_run, v_twin, v_clock - interval '60 minutes', '0543_v3_a',
            '[{"svc":"exterior_wash","must_do":false,"deferrable":true,"status":"pending","concurrency":"bay","requires_bay":"wash_bay"}]'::jsonb,
            'open')
    RETURNING visit_id INTO v_visit;
    a1 := public.ottoq_departure_clear(c1, v_run, v_clock, true);
    UPDATE public.ottoq_visit_needs SET atoms = jsonb_set(atoms, '{0,status}', '"done"') WHERE visit_id = v_visit;
    a2 := public.ottoq_departure_clear(c1, v_run, v_clock, true);
    UPDATE public.vehicles SET current_soc = 95 WHERE id = c1;
    a3 := public.ottoq_departure_clear(c1, v_run, v_clock, true);
    UPDATE public.vehicles SET current_soc = 100 WHERE id = c1;
    UPDATE public.ottoq_visit_needs
       SET atoms = atoms || '[{"svc":"readiness_check","must_do":true,"status":"pending","concurrency":"gate"}]'::jsonb
     WHERE visit_id = v_visit;
    a4 := public.ottoq_departure_clear(c1, v_run, v_clock, true);
    a5 := public.ottoq_departure_clear(c1, v_run, v_clock, false);
    IF a1 OR NOT a2 OR a3 OR a4 OR NOT a5 THEN
      RAISE EXCEPTION '0543 V3 FAILED (a): open wash %, wash done %, at 95%% %, readiness pending % (without readiness %)',
        a1, a2, a3, a4, a5;
    END IF;
    UPDATE public.ottoq_visit_needs SET status = 'superseded' WHERE visit_id = v_visit;

    -- (b) the recheck: c1 at 90% with nothing open; c2 full with an open wash; c3 full with an open walkaround; c4 clear
    UPDATE public.vehicles SET current_soc = 90 WHERE id = c1;
    INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms, status)
    VALUES (c2, v_run, v_twin, v_clock - interval '60 minutes', '0543_v3_b2',
            '[{"svc":"exterior_wash","must_do":true,"status":"pending","concurrency":"bay","requires_bay":"wash_bay"}]'::jsonb, 'open'),
           (c3, v_run, v_twin, v_clock - interval '60 minutes', '0543_v3_b3',
            '[{"svc":"perimeter_walkaround","must_do":true,"status":"pending","concurrency":"exterior"}]'::jsonb, 'open');
    v_n := twin.ottoq_sim_departure_recheck(v_run, v_clock, v_twin);
    SELECT v.current_state::text, v.config->>'svc_step' INTO st1, s1 FROM public.vehicles v WHERE v.id = c1;
    SELECT v.current_state::text, v.config->>'svc_step' INTO st2, s2 FROM public.vehicles v WHERE v.id = c2;
    SELECT v.current_state::text, v.config->>'svc_step' INTO st3, s3 FROM public.vehicles v WHERE v.id = c3;
    SELECT v.current_state::text, v.config->>'svc_step' INTO st4, s4 FROM public.vehicles v WHERE v.id = c4;
    IF st1 IS DISTINCT FROM 'staged_awaiting_service' OR s1 IS DISTINCT FROM 'need_charge'
       OR st2 IS DISTINCT FROM 'staged_awaiting_service' OR s2 IS DISTINCT FROM 'need_deploy'
       OR st3 IS DISTINCT FROM 'staged_for_departure' OR st4 IS DISTINCT FROM 'staged_for_departure' THEN
      RAISE EXCEPTION '0543 V3 FAILED (b): 90%% no work %/%, open wash %/%, open walkaround %/%, clear %/%',
        st1, s1, st2, s2, st3, s3, st4, s4;
    END IF;

    -- (b2) c1 charged to full: no longer needs its charger, so it goes back to the gate
    UPDATE public.vehicles SET current_soc = 100 WHERE id = c1;
    v_n2 := twin.ottoq_sim_departure_recheck(v_run, v_clock, v_twin);
    SELECT v.config->>'svc_step' INTO s1b FROM public.vehicles v WHERE v.id = c1;
    IF s1b IS DISTINCT FROM 'need_deploy' THEN
      RAISE EXCEPTION '0543 V3 FAILED (b2): a full car waiting for a charger stayed on %', s1b;
    END IF;

    -- (c) the deploy plan offers c4 (clear) and not c3 (walkaround still open). The release cap is a rate, so a tick
    --     of 30,000 minutes lets every candidate through and the test reads candidacy, not the cap's ordering.
    v_plan := ottoq.ottoq_plan_dispatch_tick(p_phase := 'deploy_plan', p_sim_run_id := v_run, p_depot_id := v_twin,
                p_sim_clock_now := v_clock, p_hour := 12, p_seed := 1, p_to_dispatch := 500, p_to_recall := 0,
                p_holdout_pct := 0, p_win_start := 22, p_win_end := 6, p_tick_minutes_actual := 30000,
                p_vehicles := '[]'::jsonb, p_forced := false);
    v_offered := COALESCE(v_plan->'release', '[]'::jsonb) || COALESCE(v_plan->'hold', '[]'::jsonb);
    IF NOT (v_offered @> to_jsonb(ARRAY[c4::text])) OR v_offered @> to_jsonb(ARRAY[c3::text]) THEN
      RAISE EXCEPTION '0543 V3 FAILED (c): the plan offers the clear car %, the unfinished car % (plan %)',
        v_offered @> to_jsonb(ARRAY[c4::text]), v_offered @> to_jsonb(ARRAY[c3::text]), v_plan;
    END IF;
    v_n3 := jsonb_array_length(v_offered);

    -- (d) the guard keeps a required service with no executor required
    v_guard := ottoq.ottoq_atoms_guard('[{"svc":"no_such_service_0543","must_do":true,"status":"pending"}]'::jsonb);
    IF (v_guard->0->>'must_do')::boolean IS NOT TRUE OR (v_guard->0->>'no_executor')::boolean IS NOT TRUE THEN
      RAISE EXCEPTION '0543 V3 FAILED (d): the guard returned %', v_guard;
    END IF;

    RAISE EXCEPTION '0543 V3 PASSED: the predicate reads open wash %, done %, 95%% %, readiness pending %/% ; the recheck moved % car(s): 90%% to %, an open wash to %, a walkaround left %, a clear car left %; charged to full it went back to the gate (% moved); the plan offers the clear car and not the unfinished one (% offered); the guard keeps a no-executor service required',
      a1, a2, a3, a4, a5, v_n, s1, s2, st3, st4, v_n2, v_n3;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0543 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0543 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the nine `definition`s in ottoq_schema_snapshots WHERE label = '0543_pre' as they are, then
--   DROP FUNCTION twin.ottoq_sim_departure_recheck(uuid, timestamptz, uuid) and
--   public.ottoq_departure_clear(uuid, uuid, timestamptz, boolean).
COMMIT;
