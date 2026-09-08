-- migration-version: APPLIED-NO-LEDGER-ROW
-- migration-name:    the_frame_carries_the_join_key_and_the_plug
-- (applied through execute_sql, which writes no supabase_migrations row; the
--  file's own APPLIED footer is the record. See task G18.)
-- ---------------------------------------------------------------------------
-- 0209 — the decision frame carries the class join key and the plug.
--
-- WHY (findings L-41 and L-42, docs/MAGENTA_AUDIT.md):
--
-- proposer/forward_proposer.py is the production bridge: a decision frame in,
-- advisory rows out. Its README says the class join "in production is
-- ottoq_vehicle_classes". It was not joinable, and the plug was not checked.
--
-- 1. THE JOIN KEY IS ABSENT FROM THE FRAME (L-41). The bridge indexes its
--    class table by the frame's `platform` ('waymo' / 'tesla' / 'zoox'), and
--    ottoq_vehicle_classes has no platform column -- it is keyed by
--    vehicle_class_code. 220 of the 221 autonomous vehicles carry that column
--    and ottoq_build_decision_frame emitted make/model/platform but not it, so
--    the declared input could not be joined to the declared class table at all.
--    Its columns are named differently too (battery_capacity_kwh,
--    max_charge_rate_kw), which is the projection's job and ships beside this
--    migration as proposer/class_table.py.
--
-- 2. THE PLUG IS ABSENT FROM THE FRAME (L-42). The bridge chose a service point
--    by stall TYPE alone, so a PAD-inlet asset was proposable onto a CCS1 DC
--    connector -- and the consumer (ottoq_l2_external_proposal) validates
--    occupancy, reservation, station_state and heartbeat, but not the plug.
--    The engine already owns the correct rule, in the L1 shield
--    (db/baseline/functions_public.sql:6632):
--
--        a `Multi` stall passes iff the vehicle's inlet is in that stall's
--        supported_inlet_types; otherwise connector_type must equal inlet_type.
--
--    The frame emitted connector_type but NOT supported_inlet_types, so the
--    first half of that rule was unreachable from the frame. Measured on the
--    flagship depot 2026-09-08: all 84 charging stalls are connector_type
--    'Multi' with supported {CCS1, NACS}, and the fleet carries CCS1 (158) or
--    NACS (62). A bridge comparing connector_type to inlet_type literally
--    would abstain on EVERY vehicle; one ignoring both proposes every vehicle
--    onto every plug. The engine's rule is neither, and now it is expressible.
--
-- 3. charge_kinds HAS NO COLUMN AT ALL (L-42, second half). The bridge now
--    REQUIRES charge_kinds and refuses to default it -- the field decides which
--    stall types a vehicle may be sent to, and defaulting it to ("dcfc","l2")
--    silently granted every class both. ottoq_vehicle_classes has no such
--    column, so every production-derived class table would hit that refusal.
--    A5 adds the column and backfills it from the ONE column that speaks to
--    the question, `fast_charge_compatible`, and records that derivation in a
--    COMMENT rather than in code that re-guesses on every call.
--
-- WHAT THIS DOES NOT DO. It does not change one decision. The frame's only
-- consumers are ottoq_capture_decision_snapshot (records it),
-- ottoq_api_twin_get_state (serves it) and ottoq_score_run (scores it); the
-- decide path reads the tables directly. Two additive jsonb keys cannot move
-- a plan.
--
-- CONSEQUENCE, STATED RATHER THAN DISCOVERED LATER: ottoq_decision_snapshots
-- .content_hash is sha256(jsonb_pretty(frame)), so snapshots captured AFTER
-- this migration hash differently from ones captured before. That hash is
-- self-consistent per row (ottoq_assert_snapshot_integrity recomputes it from
-- the stored frame), it is not in the pair verdict -- h_dec is over
-- ottoq_decisions, not over snapshots -- and no committed number cites it. It
-- is recorded here so a later reader does not mistake the step for tampering.
--
-- PREDICTION, written before round 24 runs:
--   * NO verdict hash moves. Not fp, boot, endst, h_cmd, h_dec, h_evt, h_bkg,
--     h_nrg, h_prop, h_defr, h_cal, h_rule or h_rcl. This migration adds two
--     keys to a recorded payload and one column to a lookup table, and touches
--     no engine behaviour whatsoever.
--   * ottoq_decision_snapshots.content_hash moves on every NEW snapshot, and
--     on no existing one.
--   If any canon moves, the reading above is wrong and this migration did
--   something it should not have.
--
-- forces_recert: FALSE. No canon moves, so the streak stands.
-- ---------------------------------------------------------------------------

BEGIN;

SET LOCAL statement_timeout = '10min';

-- --- A0. Pin what we are rewriting -----------------------------------------
CREATE TEMP TABLE _pin_0209(name text PRIMARY KEY, md5_before text) ON COMMIT DROP;
INSERT INTO _pin_0209 VALUES
  ('ottoq_build_decision_frame(uuid,uuid)', '68bb7da7319e6e5f2fb01b0cefc16f55');

DO $$
DECLARE v_live text; v_pin text;
BEGIN
  SELECT md5_before INTO v_pin FROM _pin_0209
   WHERE name='ottoq_build_decision_frame(uuid,uuid)';
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_live
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_build_decision_frame'
     AND p.oid::regprocedure::text = 'ottoq_build_decision_frame(uuid,uuid)';
  IF v_live IS NULL THEN
    RAISE EXCEPTION 'PRECONDITION: public.ottoq_build_decision_frame(uuid,uuid) does not exist'
      USING ERRCODE='P0209';
  END IF;
  IF v_live IS DISTINCT FROM v_pin THEN
    RAISE EXCEPTION 'PRECONDITION: ottoq_build_decision_frame(uuid,uuid) drifted: % (pinned %)',
      v_live, v_pin USING ERRCODE='P0209';
  END IF;
END $$;

-- --- A1. Preconditions: the gaps are really there --------------------------
DO $$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef('public.ottoq_build_decision_frame(uuid,uuid)'::regprocedure)
    INTO v_def;
  IF v_def LIKE '%vehicle_class_code%' THEN
    RAISE EXCEPTION 'PRECONDITION: the frame already emits vehicle_class_code; '
                    '0209 is moot for L-41' USING ERRCODE='P0209';
  END IF;
  IF v_def LIKE '%supported_inlet_types%' THEN
    RAISE EXCEPTION 'PRECONDITION: the frame already emits supported_inlet_types; '
                    '0209 is moot for L-42' USING ERRCODE='P0209';
  END IF;
  -- and the columns it is about to read must exist
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='vehicles'
                    AND column_name='vehicle_class_code') THEN
    RAISE EXCEPTION 'PRECONDITION: vehicles.vehicle_class_code does not exist'
      USING ERRCODE='P0209';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema='public' AND table_name='stalls'
                    AND column_name='supported_inlet_types') THEN
    RAISE EXCEPTION 'PRECONDITION: stalls.supported_inlet_types does not exist'
      USING ERRCODE='P0209';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema='public' AND table_name='ottoq_vehicle_classes'
                AND column_name='charge_kinds') THEN
    RAISE EXCEPTION 'PRECONDITION: ottoq_vehicle_classes.charge_kinds already '
                    'exists; A5 would overwrite a column somebody else defined'
      USING ERRCODE='P0209';
  END IF;
END $$;

-- --- A2. The join key and the plug list are worth carrying -----------------
-- If nothing in the fleet carries a class code, or no stall declares supported
-- inlets, then adding the keys buys nothing and the finding was mis-read.
DO $$
DECLARE v_classed int; v_total int; v_multi int;
BEGIN
  SELECT count(*) FILTER (WHERE vehicle_class_code IS NOT NULL), count(*)
    INTO v_classed, v_total
    FROM public.vehicles WHERE category='autonomous';
  IF v_classed = 0 THEN
    RAISE EXCEPTION 'PRECONDITION: not one of % autonomous vehicles carries a '
                    'vehicle_class_code; the join key is not in the data either'
      USING ERRCODE='P0209';
  END IF;

  SELECT count(*) INTO v_multi
    FROM public.stalls
   WHERE connector_type = 'Multi'
     AND COALESCE(array_length(supported_inlet_types, 1), 0) > 0;
  IF v_multi = 0 THEN
    RAISE EXCEPTION 'PRECONDITION: no Multi stall declares supported_inlet_types; '
                    'the L1 rule 0209 mirrors has nothing to read'
      USING ERRCODE='P0209';
  END IF;

  RAISE NOTICE '0209 A2: % of % autonomous vehicles classed; % Multi stalls '
               'declare supported inlets', v_classed, v_total, v_multi;
END $$;

-- --- A3. Capture the CURRENT frame, so A6 can prove the change is additive --
CREATE TEMP TABLE _frame_0209(depot uuid PRIMARY KEY, before jsonb) ON COMMIT DROP;
INSERT INTO _frame_0209
SELECT '11111111-1111-1111-1111-111111111111'::uuid,
       public.ottoq_build_decision_frame('11111111-1111-1111-1111-111111111111'::uuid,
                                         NULL::uuid);

-- --- A4. The rewrite -------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_build_decision_frame(p_depot_id uuid, p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'vehicles', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', v.id, 'state', v.current_state, 'soc', ROUND(v.current_soc::numeric,2),
        'stall_id', v.current_stall_id, 'inlet_type', v.inlet_type,
        'inlet_max_kw', v.inlet_max_kw, 'fleet_operator_id', v.fleet_operator_id,
        'make', v.make, 'platform', v.platform, 'svc_step', v.config->>'svc_step',
        'target_soc', v.target_soc, 'min_soc_threshold', v.min_soc_threshold,
        --: 0209/L-41: THE JOIN KEY. ottoq_vehicle_classes is keyed by
        --: vehicle_class_code, not by platform, so without this the frame's
        --: declared class table could not be joined to the class table the
        --: README names. Nullable by construction: a vehicle whose class is
        --: unrecorded gets NULL and the bridge abstains on it, which is the
        --: honest answer and not a guessed battery.
        'vehicle_class_code', v.vehicle_class_code
      ) ORDER BY v.id)
      FROM vehicles v WHERE v.home_depot_id = p_depot_id AND v.category = 'autonomous'
    ), '[]'::jsonb),
    'stalls', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', s.id, 'type', s.stall_type, 'status', s.status,
        'vehicle_id', s.current_vehicle_id, 'connector_type', s.connector_type,
        'connector_max_kw', s.connector_max_kw,
        --: 0209/L-42: WHICH PLUGS THIS POINT ACCEPTS. connector_type alone is
        --: not the rule: the L1 shield passes a 'Multi' stall iff the vehicle's
        --: inlet is in THIS list, and every charging stall at the flagship
        --: depot is Multi. Without the list the frame could express only the
        --: exact-match half of a rule the engine already enforces.
        'supported_inlet_types', s.supported_inlet_types
      ) ORDER BY s.id)
      FROM stalls s WHERE s.depot_id = p_depot_id
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
  );
$function$;

-- --- A5. charge_kinds becomes a column, and the derivation is recorded ------
ALTER TABLE public.ottoq_vehicle_classes ADD COLUMN charge_kinds text[];

UPDATE public.ottoq_vehicle_classes
   SET charge_kinds = CASE WHEN fast_charge_compatible THEN ARRAY['dcfc','l2']
                           ELSE ARRAY['l2'] END;

ALTER TABLE public.ottoq_vehicle_classes
  ALTER COLUMN charge_kinds SET DEFAULT ARRAY['l2'],
  ALTER COLUMN charge_kinds SET NOT NULL;

COMMENT ON COLUMN public.ottoq_vehicle_classes.charge_kinds IS
  'Which SERVICE POINT TYPES this class can charge at (stalls.stall_type). '
  'Added by migration 0209 for finding L-42: the production proposer requires '
  'this field and refuses to default it, because it alone decides which stall '
  'types a vehicle may be sent to. '
  'BACKFILLED BY DERIVATION, not measured: fast_charge_compatible = true -> '
  '{dcfc,l2}, false -> {l2}. That column is the only one in this table that '
  'speaks to the question, and recording the derivation once as data beats '
  'code that re-guesses it on every call. It is a stall-TYPE capability and '
  'says nothing about the plug: inlet compatibility is a separate rule over '
  'stalls.connector_type / stalls.supported_inlet_types and vehicles.inlet_type '
  '(the L1 shield, and proposer/forward_proposer.py which mirrors it). '
  'A class whose real capability differs -- a pad-charged AMR, a swap dock -- '
  'should have this column SET, not inferred.';

-- --- A6. Exact-once rewrite proof ------------------------------------------
DO $$
DECLARE v_def text; v_n int;
BEGIN
  SELECT pg_get_functiondef('public.ottoq_build_decision_frame(uuid,uuid)'::regprocedure)
    INTO v_def;

  v_n := (length(v_def) - length(replace(v_def, '''vehicle_class_code'', v.vehicle_class_code', '')))
         / length('''vehicle_class_code'', v.vehicle_class_code');
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'REWRITE: the vehicle_class_code pair appears % times, expected 1', v_n
      USING ERRCODE='P0209';
  END IF;

  v_n := (length(v_def) - length(replace(v_def, '''supported_inlet_types'', s.supported_inlet_types', '')))
         / length('''supported_inlet_types'', s.supported_inlet_types');
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'REWRITE: the supported_inlet_types pair appears % times, expected 1', v_n
      USING ERRCODE='P0209';
  END IF;

  -- the definer/search_path posture and every original section survived
  IF v_def NOT LIKE '%SECURITY DEFINER%'
     OR v_def NOT LIKE '%search_path TO ''twin'', ''ottoq'', ''public'', ''extensions''%'
     OR v_def NOT LIKE '%''sessions'',%' OR v_def NOT LIKE '%''energy'',%'
     OR v_def NOT LIKE '%''bess'',%' THEN
    RAISE EXCEPTION 'REWRITE: the function lost its posture or one of its sections'
      USING ERRCODE='P0209';
  END IF;
END $$;

-- --- A7. Rolled-back live probe: the change is PURELY ADDITIVE --------------
-- Strip the two new keys from every vehicle and stall object of the new frame
-- and the result must be BYTE-IDENTICAL to the frame captured in A3. That is
-- the strongest available statement that nothing else moved: not a field, not
-- an ordering, not a rounding.
DO $$
DECLARE
  v_before jsonb; v_after jsonb; v_stripped jsonb;
  v_veh int; v_veh_classed int; v_stalls int; v_stalls_keyed int;
BEGIN
  SELECT before INTO v_before FROM _frame_0209;
  v_after := public.ottoq_build_decision_frame(
               '11111111-1111-1111-1111-111111111111'::uuid, NULL::uuid);

  v_stripped := jsonb_set(
    jsonb_set(v_after, '{vehicles}', COALESCE((
      SELECT jsonb_agg(e - 'vehicle_class_code' ORDER BY ord)
        FROM jsonb_array_elements(v_after->'vehicles') WITH ORDINALITY t(e, ord)
    ), '[]'::jsonb)),
    '{stalls}', COALESCE((
      SELECT jsonb_agg(e - 'supported_inlet_types' ORDER BY ord)
        FROM jsonb_array_elements(v_after->'stalls') WITH ORDINALITY t(e, ord)
    ), '[]'::jsonb));

  IF v_stripped IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'PROBE: the new frame is NOT the old frame plus two keys — '
                    'something else changed. Refusing to apply.'
      USING ERRCODE='P0209';
  END IF;

  SELECT count(*), count(*) FILTER (WHERE e ? 'vehicle_class_code'
                                      AND e->>'vehicle_class_code' IS NOT NULL)
    INTO v_veh, v_veh_classed
    FROM jsonb_array_elements(v_after->'vehicles') e;
  SELECT count(*), count(*) FILTER (WHERE e ? 'supported_inlet_types')
    INTO v_stalls, v_stalls_keyed
    FROM jsonb_array_elements(v_after->'stalls') e;

  IF v_veh_classed = 0 OR v_stalls_keyed <> v_stalls THEN
    RAISE EXCEPTION 'PROBE: % of % vehicles carry a class code and % of % '
                    'stalls carry the inlet key — the additions did not land',
                    v_veh_classed, v_veh, v_stalls_keyed, v_stalls
      USING ERRCODE='P0209';
  END IF;

  RAISE NOTICE '0209 probe: frame is old + 2 keys exactly; %/% vehicles classed, '
               '%/% stalls carry supported_inlet_types',
               v_veh_classed, v_veh, v_stalls_keyed, v_stalls;
END $$;

-- --- A8. charge_kinds landed on every class --------------------------------
DO $$
DECLARE v_empty int;
BEGIN
  SELECT count(*) INTO v_empty FROM public.ottoq_vehicle_classes
   WHERE COALESCE(array_length(charge_kinds, 1), 0) = 0;
  IF v_empty > 0 THEN
    RAISE EXCEPTION 'BACKFILL: % classes have an empty charge_kinds; the '
                    'production bridge would refuse every one of them', v_empty
      USING ERRCODE='P0209';
  END IF;
END $$;

-- --- A9. Lineage -----------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0209_the_frame_carries_the_join_key_and_the_plug', FALSE,
        'ottoq_build_decision_frame now emits vehicles[].vehicle_class_code '
        '(the ottoq_vehicle_classes join key, absent so the declared class '
        'table was unjoinable — L-41) and stalls[].supported_inlet_types (the '
        'list the L1 Multi-stall rule reads, absent so the production bridge '
        'could not check the plug — L-42); ottoq_vehicle_classes gains a '
        'charge_kinds column backfilled from fast_charge_compatible. Purely '
        'additive: A7 proves the new frame is the old frame plus exactly two '
        'keys. No decision changes and no verdict hash moves. '
        'ottoq_decision_snapshots.content_hash moves on NEW snapshots only, '
        'because it is sha256 over the frame; it is self-consistent per row '
        'and is not in the pair verdict.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 (first attempt; every precondition and both probes passed).
--
-- CATALOG-VERIFIED AFTER APPLY (not the client's success message):
--     ottoq_build_decision_frame(uuid,uuid)  md5 68bb7da7… -> 218c5582…
--     pg_get_functiondef LIKE '%vehicle_class_code%'      true
--     pg_get_functiondef LIKE '%supported_inlet_types%'   true
--     ottoq_vehicle_classes.charge_kinds column           exists, NOT NULL
--     ottoq_cert_lineage forces_recert                    false
--     ottoq_cert_recert_floor()   2026-09-07 21:36:53.363037+00  (UNMOVED —
--         still 0208's floor, which is the point: no canon moves here)
--
-- A7 passed: the new frame stripped of the two new keys is byte-identical to
-- the frame captured before the rewrite. 220 of 221 vehicles carry a class
-- code (the 221st is the `not_applicable` platform row and has none, so the
-- bridge will abstain on it by name); all 307 stalls carry the inlet key.
--
-- charge_kinds backfill, all nine classes:
--     {dcfc,l2}  amr_pallet_2025, generic_av_dcfc, generic_passenger_av,
--                generic_robotaxi, tesla_model_y_robotaxi_2024,
--                waymo_jaguar_ipace_2024, yard_tractor_e_2025,
--                zoox_robotaxi_2024
--     {l2}       generic_av_l2   (the one class with fast_charge_compatible=false)
--
-- NOTE ON amr_pallet_2025: the derivation gives it {dcfc,l2} because its
-- fast_charge_compatible is true, which for a 4 kW PAD-inlet pallet AMR is
-- self-contradictory data. It is left as the derivation produced it rather
-- than hand-corrected, because the INLET rule is what actually refuses it: PAD
-- is not in any stall's supported_inlet_types at this depot, so the bridge
-- abstains on it with a reason naming the plug. The class carries no vehicles
-- today. A real pad-charged fleet needs this column SET, per the COMMENT.
-- ---------------------------------------------------------------------------
