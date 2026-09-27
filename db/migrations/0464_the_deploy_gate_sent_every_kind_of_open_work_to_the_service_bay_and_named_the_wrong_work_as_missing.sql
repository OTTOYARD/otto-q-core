-- migration-version: 20260926045544
-- migration-name:    the_deploy_gate_sent_every_kind_of_open_work_to_the_service_bay_and_named_the_wrong_work_as_missing
--
-- 0464  **The deploy gate sent every kind of open must-do work to the service bay, and named the wrong work as
--       missing.** `db/checks/0357` §3. FINDINGS G196b.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Run 317d4331 (busy_day, twin depot `11111111-…`), live, sim 8:00-11:37 AM CT on 2026-09-26 04:14-04:45 UTC:
--     - 14 service-bay seats; 11 had exited and 8 of those 11 credited NOTHING, on the depot's scarcest bay
--       (2 stalls, ~40 minutes a seat). The three that credited something did it for service-bay work
--       (sensor_calibration, mechanical_pm x2).
--     - What the gate had sent there: a charge (Waymo-006, three times), detail and wash work (Tesla-RT-002
--       `interior_deep_clean`; Tesla-AV-042 `exterior_wash, interior_deep_clean`), and two seats stamped
--       `must_do_work_open` with `missing: []` (Zoox-AV-077, Waymo-AV-030; their open atom was interior_deep_clean).
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `twin.ottoq_sim_advance_service_flow`, the deploy gate: a staged car is ready when SoC >= ready_soc and no
--   must-do atom is open ("IDENTICAL predicate to ottoq_plan_dispatch_tick", unchanged here). When it is not, the
--   gate wrote `svc_step := CASE WHEN soc < ready THEN 'need_charge' ELSE 'need_service' END`: any open work at a
--   ready SoC meant `need_service`, and `need_service` admits to the SERVICE BAY and nowhere else. The bay credits
--   only what it can do (0009: bay_capable ∩ outstanding), so a charge, a deep clean or a wash is never credited and
--   the car comes back to the gate. And `missing` was the needs card's `must_do_now`, not the atoms holding the gate,
--   so the stamp could say "must-do work open, missing: nothing".
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The gate reads the open must-do atoms it already counts (same filter as its own predicate) and their lane from
--   `service_cadence_policy.lane`, the catalog that already says what each bay can do (service_bay =
--   cosmetic_repair, fault_repair, mechanical_pm, sensor_calibration, exactly the service bay's credit set). Then:
--     SoC below ready              -> need_charge   (unchanged, and still first)
--     open service-bay work        -> need_service  (the only case that now reaches the service bay from here)
--     an open charge atom          -> need_charge   (the visit wants its charge)
--     anything else                -> need_deploy   (held here and re-read next tick: cabin, exterior and digital
--                                                    work runs in place; wash and detail are admitted from staging
--                                                    by the needs card; the gate's own patience flag and hard cap
--                                                    still bound the wait)
--   `missing` becomes the open atoms, plus `charge` when SoC is the reason; the card's list stays in the stamp as
--   `card_must_do_now`, where it already was.
--
--   Not changed: what counts as ready (the predicate shared with the dispatcher), the hard cap, the patience flag,
--   the service bay's admission and credit, and the needs card.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   The gate runs on every world tick. Service-bay seats, holds, deploys, bookings and the end state move. Applied in
--   the same recert window as 0463 and 0465, so one sweep re-certifies all three.
--
--   PREDICTED on the next busy_day run: service-bay exits crediting nothing fall from 8 of 11 toward the boot seats
--   alone; no gate stamp reads `must_do_work_open` with an empty `missing`.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0464 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured (after 0458) ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure))
     <> 'c2133e17fb3558ff0a88f97b4a8ac396' THEN
    RAISE EXCEPTION '0464 P2: twin.ottoq_sim_advance_service_flow is not the body this file patches';
  END IF;
  IF (SELECT array_agg(svc ORDER BY svc) FROM public.service_cadence_policy WHERE lane = 'service_bay' AND is_active)
     IS DISTINCT FROM ARRAY['cosmetic_repair','fault_repair','mechanical_pm','sensor_calibration'] THEN
    RAISE EXCEPTION '0464 P2: the service_bay lane is not the service bay''s credit set this file was written against';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0464_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure;

DO $patch_gate$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  v_pat_decl   text := $p$v_since TIMESTAMPTZ; v_reason TEXT; v_missing TEXT\[\]; v_held_min NUMERIC; v_remedy TEXT;$p$;
  v_pat_remedy text := $p$v_reason   := CASE WHEN v_rec\.current_soc < v_rec\.ready_soc THEN 'soc_below_ready' ELSE 'must_do_work_open' END;\s+v_remedy   := CASE WHEN v_rec\.current_soc < v_rec\.ready_soc THEN 'need_charge'\s+ELSE 'need_service' END;\s+v_missing  := \(CASE WHEN v_rec\.current_soc < v_rec\.ready_soc THEN ARRAY\['charge'\] ELSE ARRAY\[\]::text\[\] END\)\s+\|\| COALESCE\(v_rec\.card_must, ARRAY\[\]::text\[\]\);$p$;
  v_new_decl   text := $r$v_since TIMESTAMPTZ; v_reason TEXT; v_missing TEXT[]; v_held_min NUMERIC; v_remedy TEXT;
          v_open TEXT[]; v_open_svc_bay BOOLEAN; v_open_charge BOOLEAN;   -- 0464 (G196b)$r$;
  v_new_remedy text := $r$-- ══════ 0464 (G196b): THE REMEDY FOLLOWS THE WORK, AND `missing` NAMES IT ══════
          -- Any open must-do atom at a ready SoC used to mean need_service, and need_service admits to the
          -- SERVICE BAY only: 8 of 11 service-bay exits on 317d4331 credited nothing (a charge, detail and
          -- wash work). service_cadence_policy.lane already says what each bay can do. Service-bay work ->
          -- need_service; an open charge -> need_charge; anything else -> need_deploy, held here and re-read
          -- next tick (cabin, exterior and digital work runs in place; wash and detail are admitted from
          -- staging by the needs card), bounded as before by this gate's patience flag and hard cap.
          -- `missing` is the atoms that hold the gate; the card's list stays as card_must_do_now.
          SELECT COALESCE(array_agg(DISTINCT a->>'svc' ORDER BY a->>'svc'), ARRAY[]::text[]),
                 COALESCE(bool_or(cp.lane = 'service_bay'), false),
                 COALESCE(bool_or(a->>'svc' = 'charge'), false)
            INTO v_open, v_open_svc_bay, v_open_charge
            FROM ottoq_visit_needs vn
            CROSS JOIN LATERAL jsonb_array_elements(vn.atoms) a
            LEFT JOIN service_cadence_policy cp ON cp.svc = a->>'svc' AND cp.is_active
           WHERE vn.vehicle_id = v_rec.id AND vn.sim_run_id = p_sim_run_id
             AND vn.status IN ('open','in_progress')
             AND COALESCE((a->>'must_do')::boolean,false) = true
             AND a->>'svc' <> 'readiness_check'
             AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled');
          v_reason   := CASE WHEN v_rec.current_soc < v_rec.ready_soc THEN 'soc_below_ready' ELSE 'must_do_work_open' END;
          v_remedy   := CASE WHEN v_rec.current_soc < v_rec.ready_soc THEN 'need_charge'
                             WHEN v_open_svc_bay                     THEN 'need_service'
                             WHEN v_open_charge                      THEN 'need_charge'
                             ELSE 'need_deploy' END;
          v_missing  := (CASE WHEN v_rec.current_soc < v_rec.ready_soc AND NOT ('charge' = ANY (v_open))
                              THEN ARRAY['charge'] ELSE ARRAY[]::text[] END) || v_open;$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat_decl, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0464: the gate declaration matched % times, not once', n; END IF;
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat_remedy, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0464: the remedy block matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat_decl, v_new_decl);
  v_def := regexp_replace(v_def, v_pat_remedy, v_new_remedy);
  EXECUTE v_def;
END $patch_gate$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_f text := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
BEGIN
  -- V1: the remedy reads the lane, and the old unconditional need_service is gone.
  IF position('0464 (G196b): THE REMEDY FOLLOWS THE WORK' IN v_f) = 0
     OR position($x$WHEN v_open_svc_bay                     THEN 'need_service'$x$ IN v_f) = 0
     OR position($x$ELSE 'need_deploy' END;$x$ IN v_f) = 0
     OR v_f ~ $x$THEN 'need_charge'\s+ELSE 'need_service' END$x$ THEN
    RAISE EXCEPTION '0464 V1: the gate remedy is not the body this file writes';
  END IF;
  -- V2: the readiness predicate shared with the dispatcher is untouched.
  IF position('-- IDENTICAL predicate to ottoq_plan_dispatch_tick(deploy_plan)' IN v_f) = 0 THEN
    RAISE EXCEPTION '0464 V2: the shared readiness predicate moved';
  END IF;
  -- V3: one overload, not callable by the browser key.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_service_flow') <> 1 THEN
    RAISE EXCEPTION '0464 V3: an overload appeared';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0464 V3: the ACL moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0464_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0464_the_deploy_gate_sent_every_kind_of_open_work_to_the_service_bay_and_named_the_wrong_work_as_missing', true,
  'Tick path: the deploy gate in twin.ottoq_sim_advance_service_flow chooses its remedy by the lane of the open '
  'must-do work (service_bay -> need_service, charge -> need_charge, else need_deploy) and stamps the open atoms '
  'as missing. Service-bay seats, holds, deploys, bookings and end state move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
