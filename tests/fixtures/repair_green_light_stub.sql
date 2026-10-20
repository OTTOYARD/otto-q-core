-- tests/fixtures/repair_green_light_stub.sql: the departure test and the atom marker as live, for
-- tests/test_repair_green_light_sql.py (db/migrations/0753, G467). Loaded after tests/fixtures/agent_charge_order_stub.sql
-- (vehicles, runs, visit needs, the policy reader, the effective target) and tests/fixtures/opportunistic_scan_stub.sql
-- (the depots' feed mode, the ops approvals table and the twin technician's scan as live, with its seeded draw). Read from
-- the live catalog on 2026-10-18 between 1:03 and 1:30 AM CT (the test asserts each md5 of prosrc):
--   public.ottoq_departure_clear ac79f1b4, public.ottoq_mark_visit_atoms_done be7dc4f2.
-- One stand-in, noted where defined: an owner's departure hold, which no car here has.
SET client_min_messages = warning;

-- stand-in: the live function reads an owner's holds and unplaced service orders (0605); no owner has placed one here
CREATE OR REPLACE FUNCTION public.ottoq_owner_departure_blocked(p_vehicle_id uuid, p_sim_run_id uuid,
                                                                p_clock timestamp with time zone)
RETURNS boolean LANGUAGE sql STABLE
AS $$ SELECT false $$;

-- live: public.ottoq_mark_visit_atoms_done (prosrc md5 be7dc4f2393b0b451543e12450f2df88)
CREATE OR REPLACE FUNCTION public.ottoq_mark_visit_atoms_done(p_vehicle uuid, p_svcs text[], p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_visit uuid; v_atoms jsonb; v_new jsonb := '[]'::jsonb; v_a jsonb; v_n int := 0;
BEGIN
  SELECT visit_id, atoms INTO v_visit, v_atoms FROM ottoq_visit_needs
   WHERE vehicle_id = p_vehicle AND status IN ('open','in_progress') AND COALESCE(ottoq_visit_needs.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE((SELECT r0.sim_run_id FROM public.ottoq_sim_runs r0 WHERE r0.status = 'running' AND r0.depot_id = ottoq_visit_needs.depot_id ORDER BY r0.started_at DESC LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
   ORDER BY created_at DESC LIMIT 1;
  IF v_visit IS NULL THEN RETURN 0; END IF;
  FOR v_a IN SELECT * FROM jsonb_array_elements(v_atoms) LOOP
    IF v_a->>'svc' = ANY(p_svcs) AND COALESCE(v_a->>'status','pending') <> 'done' THEN
      v_a := v_a || jsonb_build_object('status','done','done_at', to_jsonb(p_clock));
      v_n := v_n + 1;
    END IF;
    v_new := v_new || jsonb_build_array(v_a);
  END LOOP;
  IF v_n > 0 THEN UPDATE ottoq_visit_needs SET atoms = v_new, status = 'in_progress' WHERE visit_id = v_visit; END IF;
  RETURN v_n;
END; $function$;

-- live: public.ottoq_departure_clear (prosrc md5 ac79f1b4109f9eae3e821fdc20e6dca0)
CREATE OR REPLACE FUNCTION public.ottoq_departure_clear(p_vehicle_id uuid, p_sim_run_id uuid, p_clock timestamp with time zone, p_need_readiness boolean DEFAULT true)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- 0543 (CLAUDE.md rule 9, Chase 2026-09-27): a car leaves only when nothing it needs is left. Its charge is at its
  -- effective target - 1 (G244's one rule), and no service on its open visit is open or in progress. With
  -- p_need_readiness the readiness check must be done too (the dispatchers). Without it (the recheck) the readiness
  -- check is left to the staging it is done in. A car with no SoC on record is not clear.
  -- 0555 (G290): and it carries no vehicle fault that has not been repaired. The fault lives in config.exception, which
  -- neither the charge nor the card shows, so Waymo-AV-011 left with a steering/brake fault on 0410's run.
  -- 0605 (Chase 2026-10-02): and its owner has not asked OTTO-Q to keep it until later on this run (a hold is "not
  -- before" and can only delay a departure), and no owner service order placed this tick is still waiting to be put on
  -- its visit. A finished car that is held fails here and nowhere else, so 0543's recheck leaves it parked in staging.
  SELECT COALESCE(v.current_soc >= public.ottoq_effective_target_soc_at(v.id, p_clock) - 1, false)
     AND NOT public.ottoq_vehicle_fault_open(v.config)
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
     AND NOT public.ottoq_owner_departure_blocked(v.id, p_sim_run_id, p_clock)
    FROM public.vehicles v
   WHERE v.id = p_vehicle_id;
$function$;
