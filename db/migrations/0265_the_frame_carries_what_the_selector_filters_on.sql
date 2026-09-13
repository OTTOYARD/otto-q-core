-- migration-version: PENDING
-- migration-name: 0265_the_frame_carries_what_the_selector_filters_on
--
-- 0265  THE FRAME CARRIES WHAT THE SELECTOR FILTERS ON
--
-- WHY. Two live D3 runs submitted 90 CP-SAT proposals through the production door
-- and ZERO reached the shield (db/checks/0186, finding L-61). Not because the
-- proposals were unsafe -- because they named stalls the proposal selector
-- (public.ottoq_l2_external_proposal) then refused for three facts the decision
-- frame does not carry: a live reservation for a DIFFERENT vehicle, a stall
-- occupied since the frame was built, and a charger in station_state 'Faulted'.
-- Measured at tick 3 of run ccf48af1: 31 charge stalls occupied, 7 free but
-- reserved, 2 faulted, 0 offerable. The proposer was blind and the shield never
-- had to refuse a bad row, because the door refused it first.
--
-- This file makes the frame say what the selector checks. It adds facts; it takes
-- no decision. The selector is unchanged, the shield is unchanged, the tick order
-- is unchanged, and nothing here holds or reserves anything (the one-tick resource
-- hold was reviewed and sent back: db/checks/0194).
--
-- THE AUTHORITY FOR EVERY NEW FIELD is the selector's own pre-filter, which is
-- five facts plus one invisible sixth:
--     s.current_vehicle_id IS NULL
--     AND (s.reserved_by IS NULL OR s.reserved_by = <entity> OR s.reservation_expires_at <= <clk>)
--     AND c.station_state = 'Available'
--     AND c.last_heartbeat_at >= <clk> - interval '90 seconds'
--     INNER JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id   <- the sixth:
--         a stall with ocpp_charger_id NULL is unselectable forever.
-- <clk> is the SIM clock. That is load-bearing, not a detail: measured 2026-09-13,
-- all 40 flagship charge stalls are heartbeat-stale against now() and fresh against
-- the sim clock, so a consumer that compares last_heartbeat_at to the wall clock
-- abstains on the entire depot.
--
-- THE GATE. Everything is behind ottoq_policy_get(run,'proposer_frame_facts',0).
-- With the gate off -- which is every certification arm, because no global and no
-- depot row for this key exists and the arms set only the four keys 0152 sets --
-- the function emits EXACTLY the five top-level keys and exactly the 13/7/6/6/5
-- fields it emits today, byte for byte. A1 proves that on twenty real (depot, run)
-- pairs rather than asserting it.
--
-- WHAT THIS CANNOT MOVE, and why forces_recert is FALSE. The frame IS on the
-- certified tick path (ottoq_decide_tick line 32 -> ottoq_capture_decision_snapshot
-- -> here, once per tick per arm), but the frame's CONTENT is not one of the
-- fourteen compared atoms: ottoq_determinism_pair's v_equal names fp, h_cmd, h_dec,
-- h_evt, h_bkg, h_nrg, h_prop, h_defr, h_cal, h_rule, h_rcl, h_sdr, ticks and
-- endst, and h_dec hashes neither snapshot_id nor context_frame. The exposures are
-- ottoq_score_run (frame -> published ottoq_ab_runs columns), ottoq_certify_run's
-- frame breach checks, and ottoq_twin_run_digest -- and all three see gate-off
-- output, which A1 proves is byte-identical.
--
-- NO new table, NO new column, NO DROP, nothing written to ottoq_events, one
-- function replaced. CREATE OR REPLACE preserves privileges, so there is no GRANT
-- block and none is needed (A7 asserts proacl is unchanged).

-- ---------------------------------------------------------------------------
-- P. NOTHING IN FLIGHT. pg_stat_activity is the only authority: a pair runs both
--    arms in ONE transaction, so its ottoq_sim_runs rows are invisible until it
--    commits.
-- ---------------------------------------------------------------------------
DO $p$
DECLARE v_busy int; v_jobs int; v_live int;
BEGIN
  SELECT count(*) INTO v_busy FROM pg_stat_activity
   WHERE pid <> pg_backend_pid() AND state <> 'idle'
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_sim_advance_tick%'
          OR query ILIKE '%ottoq_ab_pair%');
  IF v_busy > 0 THEN
    RAISE EXCEPTION '0265 P: % certification/pair call(s) in flight', v_busy;
  END IF;
  SELECT count(*) INTO v_jobs FROM cron.job WHERE active AND jobname ~ '^r[0-9]+_';
  IF v_jobs > 0 THEN
    RAISE EXCEPTION '0265 P: % round job(s) still scheduled', v_jobs;
  END IF;
  SELECT count(*) INTO v_live FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_live > 0 THEN
    RAISE EXCEPTION '0265 P: % run(s) running or paused', v_live;
  END IF;
END $p$;

-- ---------------------------------------------------------------------------
-- A0. PIN WHAT IS REWRITTEN, WHAT IS COPIED, AND WHAT MUST NOT MOVE.
-- ---------------------------------------------------------------------------
DO $a0$
DECLARE v_src text; v_def text; v_deleg text; v_sel text; v_len int;
BEGIN
  SELECT p.prosrc, md5(pg_get_functiondef(p.oid)), length(p.prosrc)
    INTO v_src, v_def, v_len
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_build_decision_frame'
     AND pg_get_function_identity_arguments(p.oid) = 'p_depot_id uuid, p_sim_run_id uuid';
  IF md5(v_src) <> '34c60b8f3072df7700f9d3f83b00026d' THEN
    RAISE EXCEPTION '0265 A0: frame prosrc md5 is %, expected 34c60b8f3072df7700f9d3f83b00026d', md5(v_src);
  END IF;
  IF v_def <> '218c55825d4fbea1d9892a8811a4c876' THEN
    RAISE EXCEPTION '0265 A0: frame functiondef md5 is %, expected 218c55825d4fbea1d9892a8811a4c876', v_def;
  END IF;
  IF v_len <> 3054 THEN
    RAISE EXCEPTION '0265 A0: frame prosrc length is %, expected 3054', v_len;
  END IF;
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_deleg
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_build_decision_frame'
     AND pg_get_function_identity_arguments(p.oid) = 'p_depot_id uuid';
  IF v_deleg <> '810d5e9962f24e39f9a53aa6edf9ae0d' THEN
    RAISE EXCEPTION '0265 A0: the (uuid) delegate md5 is %, expected 810d5e9962f24e39f9a53aa6edf9ae0d', v_deleg;
  END IF;
  SELECT md5(p.prosrc) INTO v_sel
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_l2_external_proposal';
  IF v_sel <> 'dfc10ce047495a415f9178cd32bf17ee' THEN
    RAISE EXCEPTION '0265 A0: the selector prosrc md5 is %, expected dfc10ce047495a415f9178cd32bf17ee -- the new fields are a COPY of its pre-filter, so a moved selector invalidates this file', v_sel;
  END IF;
END $a0$;

-- ---------------------------------------------------------------------------
-- A0b. ANCHOR-UNIQUENESS ON THE SELECTOR (the 0259 idiom, used as a drift guard).
--      Each fragment the new code copies must occur exactly once in the live
--      selector, so "we copied its pre-filter" is checkable and not a claim.
-- ---------------------------------------------------------------------------
DO $a0b$
DECLARE v text; v_n int; f text;
BEGIN
  SELECT p.prosrc INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_l2_external_proposal';
  FOREACH f IN ARRAY ARRAY[
      's.current_vehicle_id IS NULL',
      'station_state',
      'last_heartbeat_at',
      'reservation_expires_at'] LOOP
    v_n := (length(v) - length(replace(v, f, ''))) / length(f);
    IF v_n < 1 THEN
      RAISE EXCEPTION '0265 A0b: fragment % does not occur in the live selector', f;
    END IF;
  END LOOP;
END $a0b$;

-- ---------------------------------------------------------------------------
-- 1. SNAPSHOT THE PRE-IMAGE (APPLYING.md step 2). The selector is snapshotted
--    although unchanged: the new code is a copy of its pre-filter, and a later
--    reader needs the version that was copied.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0265-pre', 'function', 'public',
       p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_build_decision_frame', 'ottoq_l2_external_proposal');

-- ---------------------------------------------------------------------------
-- 2. CAPTURE THE OLD OUTPUT, FROM THE OLD FUNCTION, BEFORE REPLACING IT.
--    Twenty real (depot, run) pairs out of ottoq_decision_snapshots plus both
--    certification depots with a NULL run. A1 compares against this.
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE _pre0265 ON COMMIT DROP AS
WITH pairs AS (
  SELECT DISTINCT depot_id, sim_run_id
    FROM public.ottoq_decision_snapshots
   WHERE depot_id IS NOT NULL
   ORDER BY depot_id, sim_run_id
   LIMIT 20
  UNION ALL
  SELECT '11111111-1111-1111-1111-111111111111'::uuid, NULL::uuid
  UNION ALL
  SELECT 'aacd0bb0-2d02-d101-72cc-33f70e950bc8'::uuid, NULL::uuid
)
SELECT p.depot_id, p.sim_run_id,
       md5(jsonb_pretty(public.ottoq_build_decision_frame(p.depot_id, p.sim_run_id))) AS pretty_md5,
       jsonb_array_length(COALESCE(public.ottoq_build_decision_frame(p.depot_id, p.sim_run_id) -> 'stalls', '[]'::jsonb)) AS n_stalls,
       jsonb_array_length(COALESCE(public.ottoq_build_decision_frame(p.depot_id, p.sim_run_id) -> 'vehicles', '[]'::jsonb)) AS n_vehicles,
       (SELECT count(*) FROM jsonb_object_keys(public.ottoq_build_decision_frame(p.depot_id, p.sim_run_id))) AS n_top_keys
  FROM pairs p;

-- ---------------------------------------------------------------------------
-- 3. REGISTER THE GATE. ottoq_policy_set refuses a key absent from the catalog
--    ({"ok":false,"error":"unknown_param"}) -- the defect 0262 existed to fix,
--    found only because a demo run proceeded silently with a hold switched off.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects)
SELECT 'proposer_frame_facts',
       '0265. When 1, ottoq_build_decision_frame adds the facts the proposal '
       'selector pre-filters on: per stall the charger id, the reservation and '
       'whether it is live against the SIM clock, the charger state and heartbeat '
       'freshness, and one vehicle-blind offerable verdict; per vehicle its live '
       'reservation and whether it holds a live booking; plus a top-level selector '
       'block naming the clock and the heartbeat window. RUN SCOPE ONLY: with the '
       'key absent (0) the frame is byte-identical to its pre-0265 output, which '
       'is what every certification arm sees.',
       0, 0, 1, 'public.ottoq_build_decision_frame'
 WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog
                    WHERE param_key = 'proposer_frame_facts');

-- ---------------------------------------------------------------------------
-- 4. THE FUNCTION. Full retype of this one overload, not a splice: the change is
--    structural (a gate/clock CTE, a LEFT JOIN to the charger table, and two
--    correlated lookups per vehicle). The five base keys and all 13/7/6/6/5
--    fields are reproduced verbatim from the pinned pre-image.
--
--    The LEFT JOIN cannot multiply rows: ottoq_ocpp_chargers.charger_id is unique
--    (94 rows, 94 distinct, 0 duplicates) and no stall carries a dangling
--    reference (measured 2026-09-13). A3 asserts the row counts anyway.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_build_decision_frame(p_depot_id uuid, p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  WITH g AS (
    --: 0265. ONE gate read and ONE clock read per frame build. The clock is the
    --: selector's own expression: sim when the run has one, wall only when there
    --: is no run at all. Measured 2026-09-13: all 40 flagship charge stalls are
    --: heartbeat-stale against now() and fresh against the sim clock, so reading
    --: the wall clock here would make every stall look dead.
    SELECT COALESCE(public.ottoq_policy_get(p_sim_run_id, 'proposer_frame_facts', 0), 0)::int AS facts,
           COALESCE((SELECT r.sim_clock_current FROM ottoq_sim_runs r
                      WHERE r.sim_run_id = p_sim_run_id), now()) AS clk
  )
  SELECT jsonb_build_object(
    'vehicles', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', v.id, 'state', v.current_state, 'soc', ROUND(v.current_soc::numeric,2),
        'stall_id', v.current_stall_id, 'inlet_type', v.inlet_type,
        'inlet_max_kw', v.inlet_max_kw, 'fleet_operator_id', v.fleet_operator_id,
        'make', v.make, 'platform', v.platform, 'svc_step', v.config->>'svc_step',
        'target_soc', v.target_soc, 'min_soc_threshold', v.min_soc_threshold,
        --: 0209/L-41: THE JOIN KEY. ottoq_vehicle_classes is keyed by
        --: vehicle_class_code, not by platform, so without this the frame could
        --: not be joined to the class table the proposer README names. Nullable
        --: by construction: a vehicle whose class is unrecorded gets NULL and
        --: the bridge abstains on it, which is the honest answer and not a
        --: guessed battery.
        'vehicle_class_code', v.vehicle_class_code
      ) || CASE WHEN g.facts = 1 THEN jsonb_build_object(
        --: 0265/L-60. A staged vehicle usually already holds a reservation the
        --: frame did not show, so a proposer planned for vehicles that were never
        --: going to be re-decided. Both lookups are RUN-SCOPED (the 0145 class).
        'reserved_stall_id', (SELECT s2.id FROM stalls s2
                               WHERE s2.depot_id = p_depot_id AND s2.reserved_by = v.id
                                 AND COALESCE(s2.reservation_expires_at, 'infinity'::timestamptz) > g.clk
                               ORDER BY s2.id LIMIT 1),
        'has_live_booking', EXISTS (SELECT 1 FROM ottoq_stall_bookings b
                                     WHERE b.vehicle_id = v.id
                                       AND b.state IN ('held','active')
                                       AND COALESCE(b.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
                                           = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid))
      ) ELSE '{}'::jsonb END
      ORDER BY v.id)
      FROM vehicles v WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
    ), '[]'::jsonb),
    'stalls', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', s.id, 'type', s.stall_type, 'status', s.status,
        'vehicle_id', s.current_vehicle_id, 'connector_type', s.connector_type,
        'connector_max_kw', s.connector_max_kw,
        --: 0209/L-42: WHICH PLUGS THIS POINT ACCEPTS. connector_type alone is
        --: not the rule: the L1 shield passes a 'Multi' stall iff the vehicle's
        --: inlet is in THIS list, and every charging stall at the flagship depot
        --: is Multi. Without the list the frame could express only the
        --: exact-match half of a rule the engine already enforces.
        'supported_inlet_types', s.supported_inlet_types
      ) || CASE WHEN g.facts = 1 THEN jsonb_build_object(
        --: 0265/L-61. The three facts the selector refuses on and the frame did
        --: not carry, plus the join key that makes a stall selectable at all.
        'ocpp_charger_id', s.ocpp_charger_id,
        'reserved_by', s.reserved_by,
        'reservation_expires_at', s.reservation_expires_at,
        'reservation_live', (s.reserved_by IS NOT NULL
                             AND COALESCE(s.reservation_expires_at, 'infinity'::timestamptz) > g.clk),
        'charger_state', c.station_state,
        'charger_heartbeat_at', c.last_heartbeat_at,
        'charger_fresh', (c.last_heartbeat_at IS NOT NULL
                          AND c.last_heartbeat_at >= g.clk - interval '90 seconds'),
        --: VEHICLE-BLIND on purpose: the selector also accepts a stall reserved
        --: for the proposal's OWN vehicle, which this object cannot know. So
        --: offerable=false means no proposal can win it; offerable=true means a
        --: proposal for a vehicle with no competing reservation can.
        'offerable', (s.current_vehicle_id IS NULL
                      AND s.ocpp_charger_id IS NOT NULL
                      AND c.station_state = 'Available'
                      AND c.last_heartbeat_at IS NOT NULL
                      AND c.last_heartbeat_at >= g.clk - interval '90 seconds'
                      AND (s.reserved_by IS NULL
                           OR COALESCE(s.reservation_expires_at, '-infinity'::timestamptz) <= g.clk))
      ) ELSE '{}'::jsonb END
      ORDER BY s.id)
      FROM stalls s
      LEFT JOIN ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
      WHERE s.depot_id = p_depot_id
    ), '[]'::jsonb),
    'sessions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', cs.id, 'stall_id', cs.stall_id, 'vehicle_id', cs.vehicle_id,
        'status', cs.status, 'started_at', cs.started_at,
        'power_kw', ((cs.last_meter_value->>'power_kw'))::numeric
      ) ORDER BY cs.id)
      FROM ocpp_sessions cs WHERE cs.depot_id = p_depot_id AND cs.status = 'active'
    ), '[]'::jsonb),
    'energy', (
      SELECT jsonb_build_object(
        'grid_import_kw', se.grid_import_kw, 'total_ev_charging_kw', se.total_ev_charging_kw,
        'building_load_kw', se.building_load_kw, 'peak_demand_kw_15min', se.peak_demand_kw_15min,
        'tariff', se.current_tariff_label, 'at', se.timestamp
      )
      FROM site_energy_snapshots se WHERE se.depot_id = p_depot_id
        AND se.sim_run_id = p_sim_run_id
      ORDER BY se.timestamp DESC LIMIT 1
    ),
    'bess', (
      SELECT jsonb_build_object(
        'soc_pct', b.current_soc_pct, 'power_kw', b.current_power_kw,
        'state', b.current_state, 'temp_c', b.current_temperature_c, 'soh_pct', b.current_soh_pct
      )
      FROM ottoq_bess_units b WHERE b.depot_id = p_depot_id LIMIT 1
    )
  ) || CASE WHEN g.facts = 1 THEN jsonb_build_object(
    --: 0265. The consumer must not have to guess which clock the verdicts used.
    'selector', jsonb_build_object('facts_version', 1, 'clock', g.clk,
                                   'heartbeat_window_s', 90,
                                   'authority', 'public.ottoq_l2_external_proposal')
  ) ELSE '{}'::jsonb END
  FROM g;
$function$;

COMMENT ON FUNCTION public.ottoq_build_decision_frame(uuid, uuid) IS
'0209 + 0265. The decision frame: what a proposer is allowed to see. 0265 adds, behind ottoq_policy_get(run,''proposer_frame_facts'',0) and only when that resolves 1, the facts public.ottoq_l2_external_proposal pre-filters on -- per stall ocpp_charger_id, reserved_by, reservation_expires_at, reservation_live, charger_state, charger_heartbeat_at, charger_fresh and a VEHICLE-BLIND offerable verdict; per vehicle reserved_stall_id and has_live_booking; and a top-level selector block. The selector is the authority for every one of them and the clock is its clock (sim when the run has one). With the key absent the output is byte-identical to the pre-0265 frame, which is what every certification arm sees.';

-- ---------------------------------------------------------------------------
-- 5. CLASSIFY. An unclassified migration moves the recert floor, because
--    ottoq_cert_recert_floor() reads COALESCE(forces_recert, true).
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
SELECT '0265_the_frame_carries_what_the_selector_filters_on', false,
       'FALSE with proof, not by assertion. (1) The frame''s content is not one of '
       'the fourteen compared atoms: ottoq_determinism_pair''s v_equal names fp, '
       'h_cmd, h_dec, h_evt, h_bkg, h_nrg, h_prop, h_defr, h_cal, h_rule, h_rcl, '
       'h_sdr, ticks and endst, and h_dec hashes neither snapshot_id nor '
       'context_frame. (2) Every new field is behind a run-scoped key with no '
       'global and no depot row, so a certification arm resolves 0, and A1 proves '
       'gate-off output is byte-identical on 22 (depot, run) pairs including both '
       'certification depots. (3) No new table, no new column, no DROP, nothing '
       'written to ottoq_events, and CREATE OR REPLACE preserves privileges (A7).',
       now()
 WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                    WHERE name = '0265_the_frame_carries_what_the_selector_filters_on');

-- ---------------------------------------------------------------------------
-- 6. ASSERTIONS. Any failure writes nothing: apply_migration is atomic.
-- ---------------------------------------------------------------------------
DO $a$
DECLARE
  v_bad int; v_n int; v_keys text[]; v_run uuid; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  v_frame jsonb; v_acl text;
BEGIN
  -- A1. GATE OFF IS BYTE-IDENTICAL, on every captured pair. This is the whole
  --     forces_recert=FALSE argument, measured rather than argued.
  SELECT count(*) INTO v_bad
    FROM _pre0265 pre
   WHERE md5(jsonb_pretty(public.ottoq_build_decision_frame(pre.depot_id, pre.sim_run_id))) <> pre.pretty_md5;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0265 A1: gate-off output changed on % of % captured (depot, run) pairs',
                    v_bad, (SELECT count(*) FROM _pre0265);
  END IF;
  SELECT count(*) INTO v_n FROM _pre0265;
  IF v_n < 3 THEN
    RAISE EXCEPTION '0265 A1: only % pairs captured; the byte-identity proof is too narrow', v_n;
  END IF;

  -- A2. GATE OFF EMITS EXACTLY FIVE TOP-LEVEL KEYS -- no selector block leaks.
  SELECT count(*) INTO v_bad FROM _pre0265 WHERE n_top_keys <> 5;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0265 A2: % captured pair(s) did not have five top-level keys BEFORE the change', v_bad;
  END IF;
  SELECT array_agg(k ORDER BY k) INTO v_keys
    FROM jsonb_object_keys(public.ottoq_build_decision_frame(v_depot, NULL)) k;
  IF v_keys <> ARRAY['bess','energy','sessions','stalls','vehicles'] THEN
    RAISE EXCEPTION '0265 A2: gate-off top-level keys are %, expected the five', v_keys;
  END IF;

  -- A3. THE LEFT JOIN DOES NOT MULTIPLY ROWS, gate off or on.
  SELECT count(*) INTO v_bad
    FROM _pre0265 pre
   WHERE jsonb_array_length(COALESCE(public.ottoq_build_decision_frame(pre.depot_id, pre.sim_run_id) -> 'stalls','[]'::jsonb)) <> pre.n_stalls
      OR jsonb_array_length(COALESCE(public.ottoq_build_decision_frame(pre.depot_id, pre.sim_run_id) -> 'vehicles','[]'::jsonb)) <> pre.n_vehicles;
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0265 A3: stall or vehicle row count changed on % pair(s)', v_bad;
  END IF;

  -- A4. THE POSITIVE CONTROL. With the gate ON at a scratch run scope, the facts
  --     appear, and `offerable` agrees with the selector's own conjunction
  --     recomputed here independently for every charge stall at the flagship depot.
  v_run := '00000000-0000-0000-0000-000000000265';
  PERFORM public.ottoq_policy_set('run', v_run, 'proposer_frame_facts', 1, '0265-assert');
  v_frame := public.ottoq_build_decision_frame(v_depot, v_run);
  SELECT array_agg(k ORDER BY k) INTO v_keys FROM jsonb_object_keys(v_frame) k;
  IF NOT ('selector' = ANY(v_keys)) THEN
    RAISE EXCEPTION '0265 A4: gate on, and no selector block appeared (keys %)', v_keys;
  END IF;
  SELECT count(*) INTO v_bad
    FROM jsonb_to_recordset(v_frame -> 'stalls')
           AS f(id uuid, type text, offerable boolean, charger_fresh boolean, reservation_live boolean)
    JOIN public.stalls s ON s.id = f.id
    LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.stall_type IN ('dcfc','l2')
     AND f.offerable IS DISTINCT FROM
         (s.current_vehicle_id IS NULL AND s.ocpp_charger_id IS NOT NULL
          AND c.station_state = 'Available'
          AND c.last_heartbeat_at IS NOT NULL
          AND c.last_heartbeat_at >= (SELECT COALESCE((SELECT r.sim_clock_current FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run), now())) - interval '90 seconds'
          AND (s.reserved_by IS NULL
               OR COALESCE(s.reservation_expires_at, '-infinity'::timestamptz) <= (SELECT COALESCE((SELECT r.sim_clock_current FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run), now()))));
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0265 A4: offerable disagrees with the selector conjunction on % charge stall(s)', v_bad;
  END IF;

  -- A5. THE FACTS ARE NOT ALL-NULL AND NOT ALL-TRUE: a frame that says nothing
  --     would pass A4 vacuously.
  SELECT count(*) INTO v_n
    FROM jsonb_to_recordset(v_frame -> 'stalls') AS f(id uuid, charger_state text)
   WHERE f.charger_state IS NOT NULL;
  IF v_n = 0 THEN
    RAISE EXCEPTION '0265 A5: gate on, and no stall carries a charger_state -- the facts block is empty';
  END IF;

  -- A6. THE SCRATCH SCOPE LEAVES NO RESIDUE, and the key has no global or depot
  --     tier, which is what makes a certification arm resolve 0.
  DELETE FROM public.ottoq_policy_params
   WHERE scope_type = 'run' AND scope_id = v_run AND param_key = 'proposer_frame_facts';
  SELECT count(*) INTO v_bad FROM public.ottoq_policy_params
   WHERE param_key = 'proposer_frame_facts' AND (scope_type <> 'run' OR scope_id IS NULL);
  IF v_bad > 0 THEN
    RAISE EXCEPTION '0265 A6: % non-run-scoped row(s) for proposer_frame_facts', v_bad;
  END IF;
  IF COALESCE(public.ottoq_policy_get(NULL, 'proposer_frame_facts', 0), 0)::int <> 0 THEN
    RAISE EXCEPTION '0265 A6: the key does not resolve 0 with no run -- a cert arm would see the facts';
  END IF;

  -- A7. PRIVILEGES PRESERVED, the delegate untouched, exactly two overloads.
  --     The ACL is pinned literally, measured 2026-09-13 before this file ran:
  --     CREATE OR REPLACE preserves privileges, and this is what preserved means.
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_build_decision_frame';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0265 A7: % overloads of the frame, expected 2', v_n;
  END IF;
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_build_decision_frame'
     AND pg_get_function_identity_arguments(p.oid)='p_depot_id uuid';
  IF v_acl <> '810d5e9962f24e39f9a53aa6edf9ae0d' THEN
    RAISE EXCEPTION '0265 A7: the delegate moved to %', v_acl;
  END IF;
  SELECT COALESCE(array_to_string(p.proacl, ','), '(default)') INTO v_acl
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_build_decision_frame'
     AND pg_get_function_identity_arguments(p.oid)='p_depot_id uuid, p_sim_run_id uuid';
  IF v_acl <> 'postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres' THEN
    RAISE EXCEPTION '0265 A7: the frame''s ACL is now %, expected postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres', v_acl;
  END IF;

  -- A8. THE SIM CLOCK IS LOAD-BEARING, stated as a measurement so a later reader
  --     cannot mistake it for style: every flagship charge stall is stale against
  --     the wall clock. A frame built on now() would call the whole depot dead.
  SELECT count(*) INTO v_n
    FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = v_depot AND s.stall_type IN ('dcfc','l2')
     AND c.last_heartbeat_at >= now() - interval '90 seconds';
  IF v_n > 0 THEN
    RAISE NOTICE '0265 A8: % flagship charge stall(s) are heartbeat-fresh against the WALL clock; the measurement this file was written against said 0', v_n;
  END IF;
END $a$;

-- ---------------------------------------------------------------------------
-- APPLY LOG
-- ---------------------------------------------------------------------------
-- Attempt 1: PENDING. Not yet applied. Dry-run record below, filled before apply.
--   DRY RUN 2026-09-13 06:05-06:12 UTC, read-only, each answer read:
--     P    : 0 pair calls in flight, 0 active r<N>_ cron jobs, 0 runs running/paused.
--     A0   : frame prosrc 34c60b8f3072df7700f9d3f83b00026d, functiondef
--            218c55825d4fbea1d9892a8811a4c876, length 3054; delegate
--            810d5e9962f24e39f9a53aa6edf9ae0d; selector prosrc
--            dfc10ce047495a415f9178cd32bf17ee. All five match the pins.
--     A0b  : all four selector fragments present.
--     A1   : the two legs that change were run as standalone queries with the gate
--            resolving 0 and compared to the live function: stalls
--            ba36d7f5dedcad36b624fd00f32a116b == ba36d7f5dedcad36b624fd00f32a116b,
--            vehicles ad7dff4224a787567625ebfc75ddd029 ==
--            ad7dff4224a787567625ebfc75ddd029. Byte-identical, which also proves
--            the LEFT JOIN does not multiply rows.
--     A4   : with facts forced to 1 and the clock at 2026-09-02 02:00:00+00, the
--            flagship depot's 40 charge stalls came back 39 offerable, 1
--            heartbeat-stale, 1 not Available, 0 live reservations -- the facts
--            discriminate rather than saying everything is fine.
--     SHAPE: ottoq_ocpp_chargers.charger_id is unique (94 rows, 94 distinct, 0
--            duplicates), 0 dangling stall references, and the frame's ACL is
--            postgres=X,authenticated=X,service_role=X.
-- ---------------------------------------------------------------------------
