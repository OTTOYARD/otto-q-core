-- 0447  **Production ran a world the twin never certified.** A production session's world step, twin.ottoq_world_advance,
--        is a hand-made copy of the certified public.ottoq_sim_advance_tick_world and never called three of its phases:
--        the owner-orders step, the arm cycles and the tether release. -> G436, 0718. (The study's DC-3.)
--        Measured 2026-10-13, read-only, from 20:18:04 UTC (the first catalog read) to 20:28:11 UTC; the live probe in
--        §3 is a rolled-back transaction. The twin depot 11111111-... is the only site in it (CLAUDE.md rule 8).
--
-- ══ §1 THE CALL GRAPHS DIFFER BY EXACTLY THREE FUNCTIONS (reproduce: (1), (2)) ══════════════════════════════════════
--
--   Comment-stripped callee sets (every identifier followed by "(" that names a function in public, twin or ottoq):
--     public.ottoq_sim_advance_tick_world (certified, 28 callees) minus twin.ottoq_world_advance (production, 27):
--       ottoq.ottoq_owner_orders_tick, twin.ottoq_arm_advance_cycles, public.ottoq_release_expired_tethers
--     production minus certified: ottoq_default_target_soc (production's own target-aware gate rule) and
--       ottoq_sim_decide_and_dispatch (production decides in the same step; the certified tick decides in its own half).
--   Callers, comment-stripped: ottoq_release_expired_tethers and ottoq_owner_orders_tick have ONE caller each, the
--   certified world; twin.ottoq_arm_advance_cycles likewise. twin.ottoq_world_advance is called by public.ottoq_cron_tick
--   (job 10, */2) and public.ottoq_production_start, and returns at once unless a run_by = 'production_live' run is
--   running. Its md5 was 3489fb1392073751df4f601d45dc7731.
--   Production has run 9 sessions: the longest 4,050 ticks (2026-07-02) and 328 and 241 ticks, all before the tether
--   (0011-TETHER) and owner orders (0605) existed; the three since are 7, 0 and 6 ticks (2026-08-30, 08-30, 10-09).
--
-- ══ §2 WHAT EACH MISSING PHASE DOES IN A PRODUCTION SESSION (read from the live source) ═══════════════════════════════
--
--   (a) THE TETHER, AND A FAST CHARGER NEVER HANDED BACK. twin.ottoq_sim_stop_charge_session ends a DCFC session that is
--       not re-queued by writing, in the statement that would otherwise free the stall, robotic_tether_until = clock +
--       the demate time, robotic_tether_stall_id = the stall, direction 'demate'. The car keeps pointing at the stall and
--       the stall at the car: "ottoq_release_expired_tethers clears both the stall and this pointer". In production
--       nothing calls it. After the deadline public.ottoq_arm_interlock_guard lets the car move (it refuses only before
--       the deadline). But public.sync_stall_occupancy frees the old stall only when NOT (NEW.robotic_tether_until IS NOT
--       NULL AND NEW.robotic_tether_stall_id = OLD.current_stall_id), and with no release the tether is never cleared.
--       So when the car leaves, its fast charger stays occupied by it. Each fast charge in a production session would
--       take one of the twin depot's ten fast chargers out of service until the session ends.
--   (b) THE OWNER'S ORDER, AND RULE 9. An owner's order lands in public.ottoq_owner_settings with pending_reconcile, and
--       ottoq.ottoq_owner_orders_tick is the step that writes a charge limit to the car and attaches a service order to
--       the car's open visit. public.ottoq_owner_departure_blocked holds a car with an unreconciled service order for at
--       most 60 sim minutes ("so a tick step that kept failing could not keep a car forever"). In production the step
--       never runs: the car is held an hour, then may leave without the service its owner ordered. Latent: the table
--       holds 0 rows today. It matters the first time an owner uses the app, which is the point of the app.
--   (c) THE ARM. A mate opened when a DCFC session starts (twin.ottoq_sim_start_charge_session -> ottoq_arm_begin_cycle)
--       is never walked, so no registration is written.
--
--   What production's copy has that the certified world lacks is not in scope: its gate rule is target-aware where the
--   certified one is a hard 85% cut. Making them one function is the study's item 18; it forces recert.
--
-- ══ §3 THE LIVE PROBE (reproduce: (3)) ══════════════════════════════════════════════════════════════════════════════
--
--   A rolled-back transaction at the twin depot: a production_live session, a car left on a DCFC stall the way the
--   stop leaves it with its demate window one minute past, one call to twin.ottoq_world_advance(), then the car moved
--   off. Before 0718: PENDING (the recert sweep held it). After 0718: PENDING.
--
-- ══ QUERIES ══

-- (1) the two callee sets, comment-stripped
WITH f AS (
  SELECT p.oid, n.nspname || '.' || p.proname AS fn,
         regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE p.oid IN ('twin.ottoq_world_advance()'::regprocedure, 'public.ottoq_sim_advance_tick_world(uuid)'::regprocedure)),
c AS (SELECT f.fn, lower(m[1]) AS callee FROM f, regexp_matches(f.src, '(?:[a-z_]+\.)?([a-z_][a-z0-9_]*)\s*\(', 'gi') m)
SELECT c.fn, array_agg(DISTINCT c.callee ORDER BY c.callee) FILTER (WHERE EXISTS (
         SELECT 1 FROM pg_proc p WHERE p.proname = c.callee
            AND p.pronamespace IN ('public'::regnamespace, 'twin'::regnamespace, 'ottoq'::regnamespace))) AS callees,
       md5(pg_get_functiondef('twin.ottoq_world_advance()'::regprocedure)) AS production_md5
  FROM c GROUP BY 1;

-- (2) who calls the three, and the world step, comment-stripped
SELECT n.nspname || '.' || p.proname AS caller, m.callee
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  CROSS JOIN (VALUES ('ottoq_release_expired_tethers'), ('ottoq_owner_orders_tick'), ('ottoq_arm_advance_cycles'),
                     ('ottoq_world_advance')) m(callee)
 WHERE regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') ~ (m.callee || '\s*\(')
   AND p.proname <> m.callee
 ORDER BY 2, 1;

-- (3) the probe: run it only when no run and no pair is in flight; it raises its result and rolls back
-- SET lock_timeout = '3s'; SET statement_timeout = '58s';
DO $p$
DECLARE r uuid := 'f0718000-0000-0000-0000-000000000001'; v_car uuid; v_stall uuid;
        v_after_tick jsonb; v_after_move jsonb; t0 timestamptz := clock_timestamp();
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN RAISE EXCEPTION 'PROBE|inflight'; END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN RAISE EXCEPTION 'PROBE|a run is running'; END IF;
  INSERT INTO public.ottoq_sim_runs (sim_run_id, scenario_id, scenario_code, depot_id, run_by, status, started_at, last_tick_at,
                                     sim_clock_start, sim_clock_current, sim_clock_end, tick_interval_seconds, time_scale, payload)
  SELECT r, x.scenario_id, x.scenario_code, x.depot_id, 'production_live', 'running', now() - interval '10 minutes',
         now() - interval '2 minutes', now() - interval '10 minutes', now() - interval '2 minutes', now() + interval '1 day',
         120, 1, '{}'
    FROM public.ottoq_sim_runs x WHERE x.sim_run_id = '02ac27b3-fe50-42b1-bf1b-82ac2a50445f';
  SELECT s.id INTO v_stall FROM public.stalls s WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
     AND s.stall_type::text = 'dcfc' AND s.current_vehicle_id IS NULL AND s.reserved_by IS NULL ORDER BY s.id LIMIT 1;
  SELECT v.id INTO v_car FROM public.vehicles v WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111'
     AND v.category = 'autonomous' AND v.current_stall_id IS NULL AND v.robotic_tether_until IS NULL ORDER BY v.id LIMIT 1;
  IF v_stall IS NULL OR v_car IS NULL THEN RAISE EXCEPTION 'PROBE|no free dcfc (%) or car (%)', v_stall, v_car; END IF;
  -- the state twin.ottoq_sim_stop_charge_session leaves at a DCFC stop, with the demate window already past
  UPDATE public.vehicles SET current_stall_id = v_stall, robotic_tether_until = now() - interval '1 minute',
         robotic_tether_stall_id = v_stall, robotic_tether_direction = 'demate', robotic_tether_phase = 'unlatch'
   WHERE id = v_car;
  PERFORM count(*) FROM twin.ottoq_world_advance();
  SELECT jsonb_build_object('car_tether_until', v.robotic_tether_until, 'car_on_stall', v.current_stall_id = v_stall,
           'stall_holds_car', s.current_vehicle_id = v_car, 'stall_status', s.status,
           'run_ticks', (SELECT tick_count FROM public.ottoq_sim_runs WHERE sim_run_id = r))
    INTO v_after_tick FROM public.vehicles v, public.stalls s WHERE v.id = v_car AND s.id = v_stall;
  UPDATE public.vehicles SET current_stall_id = NULL WHERE id = v_car;
  SELECT jsonb_build_object('stall_holds_car', s.current_vehicle_id = v_car, 'stall_status', s.status)
    INTO v_after_move FROM public.stalls s WHERE s.id = v_stall;
  RAISE EXCEPTION 'PROBE|def=%|after_tick=%|after_move=%|ms=%',
    md5(pg_get_functiondef('twin.ottoq_world_advance()'::regprocedure)), v_after_tick, v_after_move,
    round(extract(epoch FROM clock_timestamp() - t0) * 1000);
END $p$;
