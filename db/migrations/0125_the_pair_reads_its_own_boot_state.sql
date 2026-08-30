-- migration-version: 20260830233000
-- migration-name:    the_pair_reads_its_own_boot_state
-- 0125 -- the Round-2 instrument (db/checks/0050: "next instrument"). The 171717/24t
-- column forks with equal end-fingerprints, equal boot fp-covered state (the fixpoint),
-- and a first divergent WRITE six sim-hours before any stream difference -- so the
-- carrier is boot-world state OUTSIDE every projection the harness records. Backward
-- archaeology found and killed six suspects and falsified a seventh (0046 pairs 44-53);
-- this migration stops digging and makes the instrument name the carrier directly.
--
-- ottoq_boot_state_fingerprint(depot, run): per ledger table, TWO classes --
--   'vis' = rows a run-scoped read can return (sim_run_id NULL or = this run),
--   'fgn' = OTHER runs' leftover rows still in live states (the cross-run hazard set) --
-- each as {n: row count, h: md5 over content-addressed row hashes}. Rows are hashed as
-- to_jsonb(row) MINUS per-run identifiers and wall-clock columns (visit_id/booking_id/
-- leg_id/dispatch_id/itinerary_id/decision_id/sim_run_id/created_at/updated_at/booked_at
-- and visit meta, which nests booking uuids), ordered by their own content hash -- a
-- total order immune to heap layout. Chargers are a world table (no run tag): one
-- 'world' class keeping station_state, connector_states, and last_heartbeat_at (the
-- 0049 rank-3 suspect) in the image.
--
-- ottoq_determinism_pair gains two diagnostic sections per arm, NOT part of the verdict:
--   'boot'  = the fingerprint right after reset + boot + prime (before the first tick),
--   'endst' = the fingerprint at arm end (before stop_and_reset).
-- Reading a failing pair: boot_a vs boot_b names the table whose starting image differs;
-- endst_a vs boot_b shows what teardown+reset changed between the arms. A healthy pair
-- has boot_a.vis = boot_b.vis; the fgn sections differ by construction (arm B's world
-- carries arm A's leftovers) and are recorded for exactly that reason.
--
-- Pre-image pin, read live 2026-08-30: public.ottoq_determinism_pair
--   c499042a58703ed0d4fbc37c85dcfcab  (full pinned replace; verdict semantics unchanged)

CREATE OR REPLACE FUNCTION public.ottoq_boot_state_fingerprint(p_depot uuid, p_run uuid)
RETURNS jsonb
LANGUAGE sql STABLE
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
WITH vn AS (
  SELECT (t.sim_run_id IS NOT NULL AND t.sim_run_id <> p_run) AS fgn, t.status::text AS st,
         md5((to_jsonb(t) - 'visit_id' - 'sim_run_id' - 'created_at' - 'updated_at' - 'meta')::text) AS h
  FROM public.ottoq_visit_needs t WHERE t.depot_id = p_depot
), bk AS (
  SELECT (t.sim_run_id IS NOT NULL AND t.sim_run_id <> p_run) AS fgn, t.state::text AS st,
         md5((to_jsonb(t) - 'booking_id' - 'sim_run_id' - 'decision_id' - 'leg_id'
              - 'booked_at' - 'created_at' - 'updated_at')::text) AS h
  FROM public.ottoq_stall_bookings t
  WHERE EXISTS (SELECT 1 FROM public.stalls s WHERE s.id = t.stall_id AND s.depot_id = p_depot)
), lg AS (
  SELECT (t.sim_run_id IS NOT NULL AND t.sim_run_id <> p_run) AS fgn, t.status::text AS st,
         md5((to_jsonb(t) - 'leg_id' - 'itinerary_id' - 'sim_run_id' - 'created_at')::text) AS h
  FROM public.ottoq_itinerary_legs t
  WHERE EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id = t.vehicle_id AND v.home_depot_id = p_depot)
), dp AS (
  SELECT (t.sim_run_id IS NOT NULL AND t.sim_run_id <> p_run) AS fgn, t.status::text AS st,
         md5((to_jsonb(t) - 'dispatch_id' - 'sim_run_id' - 'created_at')::text) AS h
  FROM public.ottoq_vehicle_dispatches t
  WHERE EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id = t.vehicle_id AND v.home_depot_id = p_depot)
), ch AS (
  SELECT md5((to_jsonb(t) - 'created_at' - 'updated_at' - 'last_fault_payload')::text) AS h
  FROM public.ottoq_ocpp_chargers t WHERE t.depot_id = p_depot
)
SELECT jsonb_build_object(
  'visit_needs', jsonb_build_object(
    'vis', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM vn WHERE NOT fgn),
    'fgn', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM vn WHERE fgn AND st IN ('open','in_progress','carried_over'))),
  'bookings', jsonb_build_object(
    'vis', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM bk WHERE NOT fgn),
    'fgn', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM bk WHERE fgn AND st IN ('held','active','interrupted'))),
  'legs', jsonb_build_object(
    'vis', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM lg WHERE NOT fgn),
    'fgn', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM lg WHERE fgn AND st IN ('planned','active','in_progress'))),
  'dispatches', jsonb_build_object(
    'vis', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM dp WHERE NOT fgn),
    'fgn', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM dp WHERE fgn AND st IN ('active','returning'))),
  'chargers', jsonb_build_object(
    'world', (SELECT jsonb_build_object('n', count(*), 'h', md5(COALESCE(string_agg(h, '' ORDER BY h), ''))) FROM ch)))
$function$;

DO $pin$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_determinism_pair'::regproc))
     <> 'c499042a58703ed0d4fbc37c85dcfcab' THEN
    RAISE EXCEPTION '0125 abort: ottoq_determinism_pair drifted (md5 %)',
      md5(pg_get_functiondef('public.ottoq_determinism_pair'::regproc));
  END IF;
END
$pin$;

CREATE OR REPLACE FUNCTION public.ottoq_determinism_pair(p_seed bigint, p_ticks integer DEFAULT 12, p_scenario text DEFAULT 'busy_day'::text, p_depot uuid DEFAULT '11111111-1111-1111-1111-111111111111'::uuid, p_sim_start timestamp with time zone DEFAULT '2026-09-01 02:00:00+00'::timestamp with time zone, p_arm_budget_s integer DEFAULT 240)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_arm int; v_run uuid; v_t0 timestamptz;
  v_clock timestamptz; v_status text; v_ticks int;
  v_boot jsonb;
  v_h jsonb; v_arms jsonb[] := '{}';
  v_equal boolean; v_verdict jsonb;
BEGIN
  FOR v_arm IN 1..2 LOOP
    PERFORM public.ottoq_tick_invariance_reset_fleet(p_depot, p_seed);
    v_run := twin.ottoq_sim_start_run(p_scenario, p_sim_start, 60, p_seed, 'cert_harness');
    BEGIN PERFORM twin.ottoq_sim_prime_deployment(v_run, p_sim_start, 0.70);
    EXCEPTION WHEN OTHERS THEN RAISE WARNING 'determinism_pair arm % prime failed: %', v_arm, SQLERRM; END;

    -- 0125: the boot image, captured before the first tick. Diagnostic, not verdict.
    v_boot := public.ottoq_boot_state_fingerprint(p_depot, v_run);

    v_t0 := clock_timestamp();
    LOOP
      SELECT sim_clock_current, status, tick_count INTO v_clock, v_status, v_ticks
        FROM ottoq_sim_runs WHERE sim_run_id = v_run;
      EXIT WHEN v_status <> 'running' OR v_ticks >= p_ticks;
      EXIT WHEN EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) >= p_arm_budget_s;
      PERFORM public.ottoq_sim_advance_tick(v_run);
    END LOOP;

    SELECT jsonb_build_object(
      'run', v_run, 'ticks', r.tick_count, 'clock', r.sim_clock_current,
      'fp', r.payload->>'world_fingerprint',
      'boot', v_boot,
      'endst', public.ottoq_boot_state_fingerprint(p_depot, v_run),
      'h_cmd', (SELECT md5(COALESCE(string_agg(
          issued_at::text||'|'||vehicle_id::text||'|'||command_type||'|'||COALESCE(payload->>'stall_id','-')||'|'||status||'|'||COALESCE(reason_code,'-'),
          E'\n' ORDER BY issued_at, vehicle_id, command_type, COALESCE(payload->>'stall_id','-'), status), ''))
        FROM ottoq_vehicle_commands c WHERE c.sim_run_id = v_run),
      'h_dec', (SELECT md5(COALESCE(string_agg(
          sim_clock::text||'|'||tick_seq::text||'|'||action_context||'|'||entity_id::text||'|'||outcome_status
          ||'|'||COALESCE(enacted_action->>'verb', proposed_action->>'verb','-')||'|'||COALESCE(proposed_action->>'stall_id','-'),
          E'\n' ORDER BY sim_clock, tick_seq, action_context, entity_id, outcome_status,
                        COALESCE(enacted_action->>'verb', proposed_action->>'verb','-'), COALESCE(proposed_action->>'stall_id','-')), ''))
        FROM ottoq_decisions d WHERE d.sim_run_id = v_run),
      'h_evt', (SELECT md5(COALESCE(string_agg(
          event_type||'|'||CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                                THEN '-' ELSE COALESCE(entity_id::text,'-') END,
          E'\n' ORDER BY event_type,
                        CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                             THEN '-' ELSE COALESCE(entity_id::text,'-') END), ''))
        FROM ottoq_events e WHERE e.sim_run_id = v_run),
      'h_bkg', (SELECT md5(COALESCE(string_agg(
          lower(during)::text||'|'||upper(during)::text||'|'||vehicle_id::text||'|'||stall_id::text||'|'||purpose||'|'||state,
          E'\n' ORDER BY lower(during), vehicle_id, stall_id, purpose, state), ''))
        FROM ottoq_stall_bookings k WHERE k.sim_run_id = v_run))
      INTO v_h
      FROM ottoq_sim_runs r WHERE r.sim_run_id = v_run;
    v_arms := v_arms || v_h;

    PERFORM public.ottoq_sim_stop_and_reset(v_run, 'determinism_arm_complete');
  END LOOP;

  v_equal := (v_arms[1]->>'fp')    = (v_arms[2]->>'fp')
         AND (v_arms[1]->>'h_cmd') = (v_arms[2]->>'h_cmd')
         AND (v_arms[1]->>'h_dec') = (v_arms[2]->>'h_dec')
         AND (v_arms[1]->>'h_evt') = (v_arms[2]->>'h_evt')
         AND (v_arms[1]->>'h_bkg') = (v_arms[2]->>'h_bkg')
         AND (v_arms[1]->>'ticks') = (v_arms[2]->>'ticks');

  v_verdict := jsonb_build_object(
    'equal', v_equal, 'seed', p_seed, 'ticks', p_ticks, 'scenario', p_scenario,
    'arm_a', v_arms[1], 'arm_b', v_arms[2]);

  -- The verdict survives a dropped client: it lives on both run rows.
  UPDATE ottoq_sim_runs
     SET validation_status = CASE WHEN v_equal THEN 'passed' ELSE 'failed' END,
         validation_notes  = v_verdict::text
   WHERE sim_run_id IN ((v_arms[1]->>'run')::uuid, (v_arms[2]->>'run')::uuid);

  RETURN v_verdict;
END
$function$;

-- 0121b discipline: the post-condition executes the new code path. The helper runs
-- end-to-end against the live depot with a throwaway run id (returns real counts).
DO $smoke$
DECLARE v jsonb;
BEGIN
  v := public.ottoq_boot_state_fingerprint('11111111-1111-1111-1111-111111111111'::uuid,
                                           'ffffffff-ffff-4fff-8fff-ffffffffffff'::uuid);
  IF v->'visit_needs'->'vis'->>'h' IS NULL OR v->'chargers'->'world'->>'n' IS NULL THEN
    RAISE EXCEPTION '0125 abort: boot fingerprint incomplete: %', v;
  END IF;
  RAISE NOTICE '0125 smoke: boot fingerprint executes — chargers n=%, visit vis n=%, fgn n=%',
    v->'chargers'->'world'->>'n', v->'visit_needs'->'vis'->>'n', v->'visit_needs'->'fgn'->>'n';
END
$smoke$;
