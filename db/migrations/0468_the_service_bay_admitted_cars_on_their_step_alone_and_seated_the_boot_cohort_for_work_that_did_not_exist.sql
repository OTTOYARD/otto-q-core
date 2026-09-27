-- migration-version: 20260926055955
-- migration-name:    the_service_bay_admitted_cars_on_their_step_alone_and_seated_the_boot_cohort_for_work_that_did_not_exist
--
-- 0468  **The service bay admitted any car whose step said `need_service`, whether or not it had service-bay work,
--       and the boot cohort took 40-minute seats for work that did not exist.** `db/checks/0358` §3. FINDINGS G201.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Run 317d4331 (busy_day, twin depot `11111111-…`), sim 8:00 AM-12:34 PM CT, read after its stop:
--     - `twin.ottoq_sim_seed_fleet` put 10 cars into `svc_step = need_service` at boot (9 `staged_awaiting_service`,
--       1 `charge_complete_holding`) and derived no visit for any of them: none had a visit until a later arrival.
--     - 5 of them were seated in the service bay by this function's STEP 2 (no command: the twin's own admission),
--       from 8:06 AM for ~40 minutes each, and 4 of those exits credited nothing. Tesla-AV-070 and Zoox-AV-078 are
--       the examples in 0357: `twin.service_completed` with `credited: []`, then ready and deployed.
--     - Those 4 are half of the 8 empty service-bay exits G196b counted. 0464 fixed the deploy gate's half; this is
--       the other half, and 0464 cannot reach it because these cars never pass the gate before they are seated.
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   STEP 2 has two admissions. The wash lane is need-gated ("M1_need_gated_wash: admit ONLY vehicles that actually
--   have wash/detail work outstanding"). The service lane is not: its cursor is `staged_awaiting_service` and
--   `svc_step = 'need_service'`, nothing else. So every writer of `need_service` decides whether the scarcest bay
--   (2 stalls, ~40 min a seat) is spent, and three of them write it without service-bay work: the seeder's boot
--   cohort (above), and `ottoq_readmit_resumed_visits` / `ottoq_readmit_reopened_needs`, which choose
--   `need_service` for any resumed visit that needs no charge, whatever its remaining work is. The bay's exit then
--   credits the intersection of its capabilities with the car's outstanding atoms (STEP D), which is empty.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   Immediately before the service lane's cursor, a car in `staged_awaiting_service` with `need_service` and NO
--   service-bay work is routed to `need_deploy` instead, in the same pass: the deploy gate (STEP 3, below) then
--   holds it for charge, holds it in place for other work, or releases it, exactly as 0464 made it do.
--   "Service-bay work" is the bay's own credit rule: an outstanding atom (not done, cancelled or skipped) on an open
--   visit of this run whose `service_cadence_policy.lane` is `service_bay`, the lane 0464 reads. Two cars keep their
--   seat: one holding a live service booking (a reservation is honoured, as this cursor already promises), and one
--   carrying a technician flag (`config.flagged_issue`): STEP 1 sends a flagged car here from the wash and detail
--   bays on the flag alone, and that path is unchanged. 9 of 317d4331's 10 boot cars carried no flag.
--
--   The decide path admits on the step alone too (`ottoq_l2_propose_service`: `svc_step = 'need_service' OR` open
--   service-bay work). It is not patched: `ottoq_sim_advance_tick` runs the world step, and this re-route inside it,
--   before the decide step, so the sequencer never sees a step this has just corrected.
--
--   Nothing else changes. The cursor, its order, its staff cap and the admission itself are untouched, and the
--   re-route can never loop with the gate: it fires only when there is no service-bay work, and the gate asks for
--   `need_service` only when there is.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   The service flow runs every tick; the boot cohort's first hour, service-bay seats and deploys move.
--
--   PREDICTED on the next busy_day run: no service-bay exit credits nothing; the boot cohort goes to the deploy gate
--   on the first tick instead of the service bay.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0468 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured (after 0464) ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure))
     <> '715dc283c212dcaae5693b7ca6260ae7' THEN
    RAISE EXCEPTION '0468 P2: twin.ottoq_sim_advance_service_flow is not the body this file patches';
  END IF;
  IF (SELECT array_agg(svc ORDER BY svc) FROM public.service_cadence_policy WHERE lane = 'service_bay' AND is_active)
     IS DISTINCT FROM ARRAY['cosmetic_repair','fault_repair','mechanical_pm','sensor_calibration'] THEN
    RAISE EXCEPTION '0468 P2: the service_bay lane is not the service bay''s credit set this file was written against';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0468_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure;

DO $patch_lane$
DECLARE
  v_def text := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
  v_pat text := $p$SELECT COUNT\(\*\) INTO v_in_svc FROM vehicles WHERE home_depot_id = p_depot_id AND current_state = 'in_service_bay';$p$;
  v_new text := $r$-- ══════ 0468 (G201): THE SERVICE LANE IS NEED-GATED, LIKE THE WASH LANE ABOVE ══════
  -- This cursor admitted any car whose step said need_service. The seeder's boot cohort and the readmit paths write
  -- that step without service-bay work, so 4 of 5 boot seats on 317d4331 were 40 minutes on the scarcest bay that
  -- credited nothing. A car with no outstanding service-bay atom (the bay's own credit rule, by
  -- service_cadence_policy.lane, the lane 0464's gate reads), no technician flag and no live service booking goes
  -- to the deploy gate below in this same pass. The gate asks for need_service only when service-bay work is open,
  -- so this cannot loop.
  UPDATE vehicles v
     SET config = jsonb_set(COALESCE(v.config, '{}'::jsonb), '{svc_step}', to_jsonb('need_deploy'::text))
   WHERE v.home_depot_id = p_depot_id AND v.current_state = 'staged_awaiting_service'
     AND v.config->>'svc_step' = 'need_service'
     -- a technician flag is its own reason to see the service bay: STEP 1 sends a flagged car here from the
     -- wash and detail bays on the flag alone, with no atom, and that path is kept as it is
     AND NOT COALESCE((v.config->>'flagged_issue')::boolean, false)
     AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs n
                       CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
                       JOIN service_cadence_policy cp ON cp.svc = a->>'svc' AND cp.is_active AND cp.lane = 'service_bay'
                      WHERE n.vehicle_id = v.id AND n.sim_run_id = p_sim_run_id
                        AND n.status IN ('open','in_progress')
                        AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled','skipped'))
     AND NOT EXISTS (SELECT 1 FROM ottoq_stall_bookings b
                      WHERE b.sim_run_id = p_sim_run_id AND b.vehicle_id = v.id
                        AND b.state = 'held' AND b.purpose = 'service'
                        AND lower(b.during) <= p_sim_clock_now AND upper(b.during) > p_sim_clock_now);

  SELECT COUNT(*) INTO v_in_svc FROM vehicles WHERE home_depot_id = p_depot_id AND current_state = 'in_service_bay';$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0468: the service lane anchor matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat, v_new);
  EXECUTE v_def;
END $patch_lane$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_f text := pg_get_functiondef('twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)'::regprocedure);
        n int;
BEGIN
  -- V1: the gate sits once, directly above the service lane's capacity count; 0464's remedy is still there.
  SELECT count(*) INTO n FROM regexp_matches(v_f, $x$0468 \(G201\): THE SERVICE LANE IS NEED-GATED$x$, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0468 V1: the gate appears % times', n; END IF;
  IF position($x$cp.lane = 'service_bay')$x$ IN v_f) = 0
     OR position($x$AND NOT COALESCE((v.config->>'flagged_issue')::boolean, false)$x$ IN v_f) = 0
     OR v_f !~ $x$AND upper\(b\.during\) > p_sim_clock_now\);\s+SELECT COUNT\(\*\) INTO v_in_svc$x$
     OR position($x$WHEN v_open_svc_bay                     THEN 'need_service'$x$ IN v_f) = 0 THEN
    RAISE EXCEPTION '0468 V1: the service flow is not the body this file writes';
  END IF;
  -- V2: one overload, same ACL.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'twin' AND p.proname = 'ottoq_sim_advance_service_flow') <> 1 THEN
    RAISE EXCEPTION '0468 V2: an overload appeared';
  END IF;
  IF has_function_privilege('anon', 'twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0468 V2: the ACL moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0468_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0468_the_service_bay_admitted_cars_on_their_step_alone_and_seated_the_boot_cohort_for_work_that_did_not_exist', true,
  'Tick path: twin.ottoq_sim_advance_service_flow routes a need_service car with no service-bay work, no technician '
  'flag and no live service booking to need_deploy before the service lane admits. Boot cohort, service-bay seats and deploys move.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
