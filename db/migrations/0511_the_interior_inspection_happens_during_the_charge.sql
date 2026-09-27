-- migration-version: 20260927034307
-- migration-name:    the_interior_inspection_happens_during_the_charge
--
-- 0511  **A car that charges has its interior inspection at the charger, during the charge, done by the charger's
--       sensors, and the same sensors confirm, clear or escalate an uncertain interior tidy there (G236, decided by
--       Chase on 2026-09-27).** `db/checks/0377`.
--
-- ══ §1 WHAT WAS WRONG (measured on validation run 964cf17b) ═════════════════════════════════════════════════════
--
--   Of 101 interior inspections started on visits that charge, 12 started during a charge; 71 started before the
--   car's charge began, and the seam booked the arrival inspection lane for 54 of the 115 inspection legs the planner
--   had written "concurrent with the charge". The catalogue already puts the inspection "at the charge stall", and the
--   twin's own starter already holds a cabin atom until the car is charging. Two callers ignore that:
--   `ottoq_decide_tick` starts every cabin atom when it enacts a charge (before the car reaches the charger), through
--   `ottoq_start_concurrent_atoms`, and `ottoq.ottoq_enact_inspection_seam` sends a car to the lane for any planned
--   inspection leg, including the ones planned with the charge.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `ottoq_start_concurrent_atoms`: while a visit still has its charge to do, its cabin atoms start only when the
--       car is charging, or in the twin starter's two catch-ups (still on the charger after the charge, or staged for
--       departure), so nothing waits forever. An interior inspection started while the car is on the charger
--       (charging, or holding after the charge) is done by the charger's sensors: it takes no general technician,
--       carries `performed_by = 'charger_sensors'`, and is not counted against the technicians. So is the triage
--       check, when every uncertain need it judges is in the cabin: an interior tidy whose confidence sits in the
--       confirm band waits on that check's verdict (confirm, clear, or escalate to a deep clean), and the sensors that
--       see the cabin can give it. The verdict itself is unchanged: the twin draws it from the need's confidence when
--       the check completes, whoever performed it, so only the actor and the moment move. A triage that also judges an
--       exterior need (a sensor clean, a cosmetic repair) still takes a technician. Every other cabin and exterior atom
--       still takes a technician; the interior tidy and the item retrieval stay a technician's job.
--   (2) `ottoq.ottoq_enact_inspection_seam` passes over an inspection leg the planner wrote concurrent with the
--       charge. The arrival inspection lane is for a visit that does not charge.
--   (3) `ottoq_close_atom_leg` records where the work happened on a leg nothing bound to a stall (an inspection on
--       the charger, work done where the car stood): the car's stall when the work finished, so the leg's signed
--       service record names the place. A leg already bound to a stall keeps it.
--
-- ══ §3 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   Atom timing, the technicians' free count, the triage verdicts' moment, the seam's lane bookings and commands, and
--   the legs and records they close all move on the busy columns.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0511 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P1: no run is live (the world tick calls both; V3 plants its cases on a stopped run, rolled back) ──
DO $live$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN
    RAISE EXCEPTION '0511 P1: a run is live; apply between runs';
  END IF;
END $live$;

-- ── P2: the bodies this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure))
     <> 'cf483a016ebedb9563a37bb85a188d3d' THEN
    RAISE EXCEPTION '0511 P2: public.ottoq_start_concurrent_atoms is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamptz)'::regprocedure))
     <> '5b65d6842860c1b641bcbbbbf3a816a2' THEN
    RAISE EXCEPTION '0511 P2: ottoq.ottoq_enact_inspection_seam is not the body this file patches';
  END IF;
  IF md5(pg_get_functiondef('public.ottoq_close_atom_leg(uuid,uuid,text,timestamptz,timestamptz)'::regprocedure))
     <> '41e1448da1195bff9b9c272e90b17190' THEN
    RAISE EXCEPTION '0511 P2: public.ottoq_close_atom_leg is not the body this file patches';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0511_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure,
                 'ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamptz)'::regprocedure,
                 'public.ottoq_close_atom_leg(uuid,uuid,text,timestamptz,timestamptz)'::regprocedure);

-- (1) the starter
DO $patch1$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure);
  v_pairs text[][] := ARRAY[
    [$o1$  v_needs_triage boolean; v_has_triage boolean;
BEGIN$o1$,
     $n1$  v_needs_triage boolean; v_has_triage boolean;
  v_state text; v_charging_visit boolean; v_sensors boolean; v_cabin_triage boolean;   -- 0511
BEGIN$n1$],
    [$o2$             AND a2->>'status' = 'in_progress' AND a2->>'concurrency' IN ('cabin','exterior')))
    INTO v_free;$o2$,
     $n2$             AND a2->>'status' = 'in_progress' AND a2->>'concurrency' IN ('cabin','exterior')
             -- 0511 (G236): work the charger's sensors perform (an inspection, a cabin triage) takes no technician
             AND COALESCE(a2->>'performed_by', '') <> 'charger_sensors'))
    INTO v_free;$n2$],
    [$o3$  FOR v_a IN SELECT * FROM jsonb_array_elements(v_atoms) LOOP
    IF COALESCE(v_a->>'status','pending') = 'pending'
       AND v_a->>'concurrency' IN ('cabin','exterior','digital')
       AND v_a->>'svc' <> 'readiness_check'
       AND (NOT COALESCE((v_a->>'confirm_required')::boolean,false)) THEN
      IF v_a->>'concurrency' = 'digital' OR v_free > 0 THEN
        IF v_a->>'concurrency' <> 'digital' THEN v_free := v_free - 1; END IF;
        v_a := v_a || jsonb_build_object('status','in_progress',
                'started_at', to_jsonb(p_clock),
                'ends_at', to_jsonb(p_clock + ((COALESCE((v_a->>'est_min')::numeric,5))::text || ' minutes')::interval));$o3$,
     $n3$  -- 0511 (G236, decided 2026-09-27): a visit that still has its charge to do does its cabin work at the charger,
  -- during the charge, not before the car is plugged in. The twin starter's two catch-ups stay (still on the charger
  -- after the charge; staged for departure) so nothing waits forever. An interior inspection done while the car is on
  -- the charger is the charger's sensors' job (robotic charging), and so is a triage check that judges only the cabin:
  -- each takes no technician and says so.
  SELECT v.current_state::text INTO v_state FROM vehicles v WHERE v.id = p_vehicle;
  v_charging_visit := EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) c
                               WHERE c->>'svc' = 'charge' AND COALESCE(c->>'status','pending') NOT IN ('done','cancelled'));
  -- the triage check confirms, clears or escalates the visit's uncertain needs; when every one of them is in the
  -- cabin (an uncertain interior tidy), the charger's sensors can see all it judges
  v_cabin_triage := NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_atoms) c
                                 WHERE COALESCE((c->>'confirm_required')::boolean, false)
                                   AND COALESCE(c->>'status','pending') = 'pending'
                                   AND c->>'concurrency' IS DISTINCT FROM 'cabin');
  FOR v_a IN SELECT * FROM jsonb_array_elements(v_atoms) LOOP
    IF COALESCE(v_a->>'status','pending') = 'pending'
       AND v_a->>'concurrency' IN ('cabin','exterior','digital')
       AND v_a->>'svc' <> 'readiness_check'
       AND (NOT COALESCE((v_a->>'confirm_required')::boolean,false))
       AND NOT (v_a->>'concurrency' = 'cabin' AND v_charging_visit
                AND COALESCE(v_state, '') NOT IN ('charging_dcfc','charging_l2','charge_complete_holding','staged_for_departure')) THEN
      v_sensors := (v_a->>'svc' = 'interior_inspection' OR (v_a->>'svc' = 'triage_check' AND v_cabin_triage))
                   AND COALESCE(v_state, '') IN ('charging_dcfc','charging_l2','charge_complete_holding');
      IF v_a->>'concurrency' = 'digital' OR v_sensors OR v_free > 0 THEN
        IF v_a->>'concurrency' <> 'digital' AND NOT v_sensors THEN v_free := v_free - 1; END IF;
        v_a := v_a || jsonb_build_object('status','in_progress',
                'started_at', to_jsonb(p_clock),
                'ends_at', to_jsonb(p_clock + ((COALESCE((v_a->>'est_min')::numeric,5))::text || ' minutes')::interval))
                   || CASE WHEN v_sensors THEN jsonb_build_object('performed_by', 'charger_sensors') ELSE '{}'::jsonb END;$n3$]];
  i int; n int;
BEGIN
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0511: starter patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch1$;

-- (2) the seam
DO $patch2$
DECLARE
  v_def text := pg_get_functiondef('ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamptz)'::regprocedure);
  v_old text := $o$           AND COALESCE(il.duration_basis->>'atom', c_svc) = c_svc
         ORDER BY il.seq, il.planned_start_sim, il.planned_end_sim, il.leg_id /* 0129 */ LIMIT 1) l ON true$o$;
  v_new text := $n$           AND COALESCE(il.duration_basis->>'atom', c_svc) = c_svc
           -- 0511 (G236): an inspection the planner wrote alongside the car's charge is done at the charger, during the
           -- charge, by the charger's sensors. The lane is for a visit that does not charge.
           AND COALESCE(il.duration_basis->>'concurrent_with', '') <> 'charge'
         ORDER BY il.seq, il.planned_start_sim, il.planned_end_sim, il.leg_id /* 0129 */ LIMIT 1) l ON true$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0511: the seam''s leg pick matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch2$;

-- (3) the leg closer records where the work happened
DO $patch3$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_close_atom_leg(uuid,uuid,text,timestamptz,timestamptz)'::regprocedure);
  v_old text := $o$  UPDATE ottoq_itinerary_legs
     SET status = 'done',
         actual_start_sim = COALESCE(actual_start_sim, p_started),$o$;
  v_new text := $n$  UPDATE ottoq_itinerary_legs
     SET status = 'done',
         -- 0511 (G236): a leg nothing bound to a stall (an inspection on the charger, work done where the car stood)
         -- records where the car was when the work finished, so its signed service record names the place.
         to_stall_id = COALESCE(to_stall_id, (SELECT v.current_stall_id FROM vehicles v WHERE v.id = p_vehicle)),
         actual_start_sim = COALESCE(actual_start_sim, p_started),$n$;
  n int;
BEGIN
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0511: the leg closer''s update matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch3$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_start text := pg_get_functiondef('public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure);
  v_seam  text := pg_get_functiondef('ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamptz)'::regprocedure);
BEGIN
  -- V1: each body carries its change once.
  IF (length(v_start) - length(replace(v_start, 'AND NOT (v_a->>''concurrency'' = ''cabin'' AND v_charging_visit', '')))
       / length('AND NOT (v_a->>''concurrency'' = ''cabin'' AND v_charging_visit') <> 1
     OR (length(v_start) - length(replace(v_start, 'jsonb_build_object(''performed_by'', ''charger_sensors'')', '')))
       / length('jsonb_build_object(''performed_by'', ''charger_sensors'')') <> 1
     OR (length(v_start) - length(replace(v_start, 'COALESCE(a2->>''performed_by'', '''') <> ''charger_sensors''', '')))
       / length('COALESCE(a2->>''performed_by'', '''') <> ''charger_sensors''') <> 1
     OR (length(v_start) - length(replace(v_start, 'OR (v_a->>''svc'' = ''triage_check'' AND v_cabin_triage)', '')))
       / length('OR (v_a->>''svc'' = ''triage_check'' AND v_cabin_triage)') <> 1
     OR (length(v_seam) - length(replace(v_seam, 'COALESCE(il.duration_basis->>''concurrent_with'', '''') <> ''charge''', '')))
       / length('COALESCE(il.duration_basis->>''concurrent_with'', '''') <> ''charge''') <> 1
     OR position('to_stall_id = COALESCE(to_stall_id, (SELECT v.current_stall_id FROM vehicles v WHERE v.id = p_vehicle))'
                 IN pg_get_functiondef('public.ottoq_close_atom_leg(uuid,uuid,text,timestamptz,timestamptz)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0511 V1: a patched body is not the body this file leaves';
  END IF;
  -- V2: privileges, security definer and settings kept (CREATE OR REPLACE keeps the ACL).
  IF (SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure)
       <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres'
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure)
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = 'public.ottoq_start_concurrent_atoms(uuid,timestamptz)'::regprocedure)
       <> 'search_path=twin, ottoq, public, extensions'
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc
          WHERE oid = 'ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamptz)'::regprocedure)
       <> 'postgres=X/postgres,service_role=X/postgres'
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamptz)'::regprocedure)
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc
          WHERE oid = 'ottoq.ottoq_enact_inspection_seam(uuid,uuid,bigint,uuid,timestamptz)'::regprocedure)
       <> 'search_path=twin, ottoq, public, extensions'
     OR (SELECT array_to_string(proacl, ',') FROM pg_proc
          WHERE oid = 'public.ottoq_close_atom_leg(uuid,uuid,text,timestamptz,timestamptz)'::regprocedure)
       <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres'
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.ottoq_close_atom_leg(uuid,uuid,text,timestamptz,timestamptz)'::regprocedure)
     OR (SELECT array_to_string(proconfig, ',') FROM pg_proc
          WHERE oid = 'public.ottoq_close_atom_leg(uuid,uuid,text,timestamptz,timestamptz)'::regprocedure)
       <> 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION '0511 V2: a patched function''s privileges or settings changed';
  END IF;
END $verify$;

-- V3: planted on the newest stopped operator run (marked running inside this block only), then rolled back.
--   (a) a car whose visit still has its charge to do, waiting in staging, planted with an uncertain interior tidy and
--       a passenger item to retrieve: none of its cabin work starts (inspection, the triage check the starter adds,
--       the item retrieval).
--   (b) the same car charging, with no general technician free: its interior inspection and its triage check (which
--       judges only the cabin) start, performed by the charger's sensors; the item retrieval does not (a technician's
--       job), nor the tidy (it waits on the triage's verdict).
--   (b2) the same car with an uncertain sensor clean added and the triage put back: the triage now judges an exterior
--       need too, and waits for a technician.
--   (c) a second car whose charge is done, in staging, with the technicians back: its interior inspection starts, by
--       a technician (no `performed_by`).
--   (d) the seam, with both cars staged and each given one planned interior inspection leg (the first's written with
--       the charge, the second's standalone): it passes over the first and considers the second.
--   (e) the first car on a charger stall, its inspection finishing: the leg closes on that stall, and its one service
--       record names it.
DO $v3$
DECLARE
  v_msg text; v_run uuid; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  v_clock timestamptz; v1 record; v2 record; r jsonb; t jsonb; t0 jsonb; n_dec1 int; n_dec2 int; v_stall uuid;
BEGIN
  BEGIN
    SELECT sr.sim_run_id, sr.sim_clock_current INTO v_run, v_clock FROM public.ottoq_sim_runs sr
     WHERE sr.depot_id = v_depot AND sr.validation_status IS NULL AND sr.status = 'completed'
       AND sr.sim_clock_current IS NOT NULL
     ORDER BY sr.started_at DESC LIMIT 1;
    IF v_run IS NULL THEN RAISE EXCEPTION '0511 V3 FAILED: no stopped operator run to plant on'; END IF;
    UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = v_run;
    v_clock := v_clock + interval '1 minute';

    -- two visits of the run, each with a pending interior inspection and a pending charge, and an inspection leg
    SELECT vn.visit_id, vn.vehicle_id,
           (SELECT l.leg_id FROM public.ottoq_itinerary_legs l
             WHERE l.sim_run_id = v_run AND l.vehicle_id = vn.vehicle_id AND l.leg_type = 'inspect'
               AND COALESCE(l.duration_basis->>'atom', 'interior_inspection') = 'interior_inspection'
             ORDER BY l.seq, l.leg_id LIMIT 1) AS leg_id
      INTO v1
      FROM public.ottoq_visit_needs vn
     WHERE vn.sim_run_id = v_run
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) x WHERE x->>'svc' = 'interior_inspection' AND x->>'status' IS NULL)
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) x WHERE x->>'svc' = 'charge' AND x->>'status' IS NULL)
       AND EXISTS (SELECT 1 FROM public.ottoq_itinerary_legs l
                    WHERE l.sim_run_id = v_run AND l.vehicle_id = vn.vehicle_id AND l.leg_type = 'inspect'
                      AND COALESCE(l.duration_basis->>'atom', 'interior_inspection') = 'interior_inspection')
     ORDER BY vn.vehicle_id LIMIT 1;
    SELECT vn.visit_id, vn.vehicle_id,
           (SELECT l.leg_id FROM public.ottoq_itinerary_legs l
             WHERE l.sim_run_id = v_run AND l.vehicle_id = vn.vehicle_id AND l.leg_type = 'inspect'
               AND COALESCE(l.duration_basis->>'atom', 'interior_inspection') = 'interior_inspection'
             ORDER BY l.seq, l.leg_id LIMIT 1) AS leg_id
      INTO v2
      FROM public.ottoq_visit_needs vn
      LEFT JOIN public.ottoq_vehicle_needs_card c ON c.vehicle_id = vn.vehicle_id AND c.depot_id = v_depot
     WHERE vn.sim_run_id = v_run AND vn.vehicle_id <> v1.vehicle_id
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) x WHERE x->>'svc' = 'interior_inspection' AND x->>'status' IS NULL)
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) x WHERE x->>'svc' = 'charge')
       AND EXISTS (SELECT 1 FROM public.ottoq_itinerary_legs l
                    WHERE l.sim_run_id = v_run AND l.vehicle_id = vn.vehicle_id AND l.leg_type = 'inspect'
                      AND COALESCE(l.duration_basis->>'atom', 'interior_inspection') = 'interior_inspection')
       AND COALESCE(public.ottoq_approach_zone(vn.vehicle_id, v_run), 'B') <> 'C'
       AND COALESCE(c.fits_window, true) AND (c.minutes_to_deploy IS NULL OR c.minutes_to_deploy >= 4)
     ORDER BY vn.vehicle_id LIMIT 1;
    IF v1.visit_id IS NULL OR v2.visit_id IS NULL OR v1.leg_id IS NULL OR v2.leg_id IS NULL THEN
      RAISE EXCEPTION '0511 V3 FAILED: the run has no two visits to plant on (% %)', v1.visit_id, v2.visit_id;
    END IF;
    -- each visit is the car's only open one; the second car's charge is done
    UPDATE public.ottoq_visit_needs SET status = 'closed' WHERE sim_run_id = v_run
       AND vehicle_id IN (v1.vehicle_id, v2.vehicle_id) AND visit_id NOT IN (v1.visit_id, v2.visit_id)
       AND status IN ('open','in_progress');
    UPDATE public.ottoq_visit_needs SET status = 'open' WHERE visit_id IN (v1.visit_id, v2.visit_id);
    UPDATE public.ottoq_visit_needs
       SET atoms = (SELECT jsonb_agg(CASE WHEN x->>'svc' = 'charge' THEN x || '{"status":"done"}'::jsonb ELSE x END)
                      FROM jsonb_array_elements(atoms) x)
     WHERE visit_id = v2.visit_id;
    -- the first visit's cabin: an uncertain interior tidy (inside the confirm band) and a passenger item to retrieve
    UPDATE public.ottoq_visit_needs
       SET atoms = COALESCE((SELECT jsonb_agg(x) FROM jsonb_array_elements(atoms) x
                              WHERE x->>'svc' NOT IN ('interior_tidy','item_retrieval','triage_check','sensor_clean')), '[]'::jsonb)
                   || jsonb_build_array(
                        jsonb_build_object('svc','interior_tidy','must_do',true,'deferrable',false,'est_min',4,
                                           'concurrency','cabin','confidence',0.6,'confirm_required',true),
                        jsonb_build_object('svc','item_retrieval','must_do',true,'deferrable',false,'est_min',4,
                                           'concurrency','cabin','confidence',1.0,'confirm_required',false))
     WHERE visit_id = v1.visit_id;

    -- (a) the first car waits in staging
    UPDATE public.vehicles SET current_state = 'staged_awaiting_service', current_stall_id = NULL WHERE id = v1.vehicle_id;
    PERFORM public.ottoq_start_concurrent_atoms(v1.vehicle_id, v_clock);
    SELECT x INTO r FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
     WHERE vn.visit_id = v1.visit_id AND x->>'svc' = 'interior_inspection';
    IF r->>'status' IS NOT NULL
       OR (SELECT count(*) FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
            WHERE vn.visit_id = v1.visit_id AND x->>'concurrency' = 'cabin' AND x->>'status' IS NOT NULL) <> 0
       OR NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
                       WHERE vn.visit_id = v1.visit_id AND x->>'svc' = 'triage_check') THEN
      RAISE EXCEPTION '0511 V3 FAILED (a): a charging visit''s cabin work started in staging (or no triage was added): %',
        (SELECT atoms FROM public.ottoq_visit_needs WHERE visit_id = v1.visit_id);
    END IF;

    -- (b) the same car charging, with no technician free
    UPDATE public.ottoq_depot_staffing SET headcount = 0 WHERE depot_id = v_depot AND role = 'general_tech';
    IF NOT FOUND THEN
      INSERT INTO public.ottoq_depot_staffing (depot_id, role, headcount) VALUES (v_depot, 'general_tech', 0);
    END IF;
    UPDATE public.vehicles SET current_state = 'charging_l2' WHERE id = v1.vehicle_id;
    PERFORM public.ottoq_start_concurrent_atoms(v1.vehicle_id, v_clock);
    SELECT x INTO r FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
     WHERE vn.visit_id = v1.visit_id AND x->>'svc' = 'interior_inspection';
    SELECT x INTO t FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
     WHERE vn.visit_id = v1.visit_id AND x->>'svc' = 'triage_check';
    SELECT x INTO t0 FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
     WHERE vn.visit_id = v1.visit_id AND x->>'svc' = 'item_retrieval';
    IF r->>'status' IS DISTINCT FROM 'in_progress' OR r->>'performed_by' IS DISTINCT FROM 'charger_sensors'
       OR t->>'status' IS DISTINCT FROM 'in_progress' OR t->>'performed_by' IS DISTINCT FROM 'charger_sensors'
       OR t0->>'status' IS NOT NULL
       OR (SELECT x->>'status' FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
            WHERE vn.visit_id = v1.visit_id AND x->>'svc' = 'interior_tidy') IS NOT NULL THEN
      RAISE EXCEPTION '0511 V3 FAILED (b): charging with no technician, inspection %, triage %, item retrieval %', r, t, t0;
    END IF;

    -- (b2) an uncertain sensor clean joins the visit and the triage is put back to pending: it judges an exterior need
    --      now, which the charger's sensors do not see, so it waits for a technician
    UPDATE public.ottoq_visit_needs
       SET atoms = (SELECT jsonb_agg(CASE WHEN x->>'svc' = 'triage_check'
                                          THEN x - 'status' - 'started_at' - 'ends_at' - 'performed_by' ELSE x END)
                      FROM jsonb_array_elements(atoms) x)
                   || jsonb_build_array(jsonb_build_object('svc','sensor_clean','must_do',true,'deferrable',false,
                        'est_min',5,'concurrency','exterior','confidence',0.6,'confirm_required',true))
     WHERE visit_id = v1.visit_id;
    PERFORM public.ottoq_start_concurrent_atoms(v1.vehicle_id, v_clock);
    SELECT x INTO t FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
     WHERE vn.visit_id = v1.visit_id AND x->>'svc' = 'triage_check';
    IF t->>'status' IS NOT NULL THEN
      RAISE EXCEPTION '0511 V3 FAILED (b2): a triage that judges an exterior need started with no technician: %', t;
    END IF;

    -- (c) the second car, charge done, in staging, technicians back (enough that the stopped run's stale in-progress
    --     atoms cannot use them all up)
    UPDATE public.ottoq_depot_staffing SET headcount = 1000 WHERE depot_id = v_depot AND role = 'general_tech';
    UPDATE public.vehicles SET current_state = 'staged_awaiting_service', current_stall_id = NULL WHERE id = v2.vehicle_id;
    PERFORM public.ottoq_start_concurrent_atoms(v2.vehicle_id, v_clock);
    SELECT x INTO r FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
     WHERE vn.visit_id = v2.visit_id AND x->>'svc' = 'interior_inspection';
    IF r->>'status' IS DISTINCT FROM 'in_progress' OR r ? 'performed_by' THEN
      RAISE EXCEPTION '0511 V3 FAILED (c): a visit with its charge done, in staging, inspection %', r;
    END IF;

    -- (d) the seam: both cars staged, one planned inspection leg each; put the atoms back to pending first
    UPDATE public.ottoq_visit_needs
       SET atoms = (SELECT jsonb_agg(CASE WHEN x->>'svc' = 'interior_inspection'
                                          THEN x - 'status' - 'started_at' - 'ends_at' - 'performed_by' ELSE x END)
                      FROM jsonb_array_elements(atoms) x)
     WHERE visit_id IN (v1.visit_id, v2.visit_id);
    UPDATE public.vehicles SET current_state = 'staged_awaiting_service', current_stall_id = NULL
     WHERE id IN (v1.vehicle_id, v2.vehicle_id);
    -- no other car of the run is a candidate: every other planned inspection leg is set aside
    UPDATE public.ottoq_itinerary_legs SET status = 'skipped'
     WHERE sim_run_id = v_run AND leg_type = 'inspect' AND status = 'planned';
    UPDATE public.ottoq_itinerary_legs
       SET status = 'planned', to_stall_id = NULL,
           duration_basis = COALESCE(duration_basis, '{}'::jsonb)
                            || '{"atom":"interior_inspection","concurrent_with":"charge"}'::jsonb
     WHERE leg_id = v1.leg_id;
    UPDATE public.ottoq_itinerary_legs
       SET status = 'planned', to_stall_id = NULL,
           duration_basis = (COALESCE(duration_basis, '{}'::jsonb) - 'concurrent_with') || '{"atom":"interior_inspection"}'::jsonb
     WHERE leg_id = v2.leg_id;
    UPDATE public.ottoq_stall_bookings SET state = 'released', release_reason = '0511_v3'
     WHERE sim_run_id = v_run AND vehicle_id IN (v1.vehicle_id, v2.vehicle_id) AND state IN ('held','active');
    -- the run's own lane bookings for these two legs are history: detach them, or the seam's first step closes the
    -- replanted legs as already inspected before it looks for a car
    UPDATE public.ottoq_stall_bookings SET leg_id = NULL
     WHERE sim_run_id = v_run AND leg_id IN (v1.leg_id, v2.leg_id) AND purpose = 'inspect';
    PERFORM ottoq.ottoq_enact_inspection_seam(v_run, v_depot, 999999, NULL, v_clock);
    SELECT count(*) INTO n_dec1 FROM public.ottoq_decisions d
     WHERE d.sim_run_id = v_run AND d.sim_clock = v_clock AND d.entity_id = v1.vehicle_id
       AND d.context_frame->>'lane' = 'inspection';
    SELECT count(*) INTO n_dec2 FROM public.ottoq_decisions d
     WHERE d.sim_run_id = v_run AND d.sim_clock = v_clock AND d.entity_id = v2.vehicle_id
       AND d.context_frame->>'lane' = 'inspection';
    IF n_dec1 <> 0 OR n_dec2 <> 1 THEN
      RAISE EXCEPTION '0511 V3 FAILED (d): the seam considered the charging car % times and the standalone one % times',
        n_dec1, n_dec2;
    END IF;

    -- (e) the first car on an L2 stall, its inspection finishing four minutes on
    SELECT s.id INTO v_stall FROM public.stalls s
     WHERE s.depot_id = v_depot AND s.stall_type = 'l2' AND s.ocpp_charger_id IS NOT NULL ORDER BY s.id LIMIT 1;
    UPDATE public.vehicles SET current_state = 'charging_l2', current_stall_id = v_stall WHERE id = v1.vehicle_id;
    DELETE FROM public.ottoq_service_detail_records WHERE leg_id = v1.leg_id;
    PERFORM public.ottoq_close_atom_leg(v_run, v1.vehicle_id, 'interior_inspection', v_clock, v_clock + interval '4 minutes');
    IF (SELECT l.status || '|' || COALESCE(l.to_stall_id::text, '-') FROM public.ottoq_itinerary_legs l WHERE l.leg_id = v1.leg_id)
         IS DISTINCT FROM 'done|' || v_stall::text
       OR (SELECT count(*) FROM public.ottoq_service_detail_records sd WHERE sd.leg_id = v1.leg_id AND sd.stall_id = v_stall) <> 1 THEN
      RAISE EXCEPTION '0511 V3 FAILED (e): the inspection leg closed as % with % record(s) on the charger stall',
        (SELECT l.status || ' on ' || COALESCE(l.to_stall_id::text, 'no stall') FROM public.ottoq_itinerary_legs l WHERE l.leg_id = v1.leg_id),
        (SELECT count(*) FROM public.ottoq_service_detail_records sd WHERE sd.leg_id = v1.leg_id AND sd.stall_id = v_stall);
    END IF;

    RAISE EXCEPTION '0511 V3 PASSED: (a) cabin work held in staging; (b) the inspection and a cabin-only triage started on the charger by its sensors with no technician free, the item retrieval did not; (b2) a triage judging an exterior need waited for a technician; (c) a technician''s inspection with the charge done; (d) the seam passed over the charging car and considered the other; (e) closed on the charger stall with its record there';
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0511 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0511 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: restore the three functions from ottoq_schema_snapshots label '0511_pre' (CREATE OR REPLACE, ACL kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0511_the_interior_inspection_happens_during_the_charge', true,
  'A visit that still has its charge to do starts its cabin work only on the charger (or in the twin''s two catch-ups); '
  'an interior inspection on the charger, and a triage check that judges only the cabin, are done by its sensors and '
  'take no technician; the inspection seam passes over a leg planned with the charge; a leg nothing bound to a stall '
  'records where the work finished. Atom timing, the technicians'' free count, the triage verdicts'' moment, the lane '
  'bookings and the records'' stalls move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
