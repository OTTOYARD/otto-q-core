-- migration-version: 20260926045517
-- migration-name:    a_charge_that_completed_below_its_visit_target_stayed_open_and_the_deploy_gate_looped_the_car_through_the_service_bay
--
-- 0463  **A charge that completed below its visit's target was never closed, so the deploy gate held a charged car
--       as "must-do work open" and sent it to the service bay, which cannot close a charge, over and over.**
--       `db/checks/0357` §3. FINDINGS G196.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Run 317d4331 (busy_day, twin depot `11111111-…`), live, 2026-09-26 04:14–04:50 UTC, sim 8:00–10:30 AM CT:
--     - Waymo-006 arrived at 8:00, charged on DCFC-STALL-02 19% -> 90% and its session ended `completed` at 8:35:31.
--       Its visit targets 100% (visit, vehicle and `ottoq_default_target_soc()` all 100), so the charge atom stayed
--       open. The flow itself had moved on: charge_complete_holding -> staged_awaiting_service, `need_deploy`.
--     - The deploy gate then held it (`must_do_work_open`, SoC 90 >= ready 80) with remedy `need_service`, and the
--       service flow seated it in the service bay 8:46:28-9:19:31 AM, crediting nothing (the bay can do mechanical
--       work, never a charge). Out, held again, re-seated at 9:56:12 AM. Each pass holds one of the depot's TWO
--       service bays for ~33 minutes.
--     - Of the run's first 16 sessions to end `completed`, 4 ended below their visit's target (all DCFC, which
--       stops at 90%), and the atom of 1 of those 4 was still open. Across the twin depot's archive, 2,505
--       `completed` sessions end between 90% and 100%, so any visit targeting above the charger's own stop is exposed.
--
-- ══ §2 THE MECHANISM: TWO PARTS OF THE ENGINE DISAGREE ABOUT WHETHER THE CHARGE HAPPENED ═══════════════════════
--
--   The flow treats a normally completed session as the end of charging (charge_complete_holding -> need_deploy).
--   `ottoq.ottoq_close_satisfied_charge_needs`, the only closer of the charge atom, accepts nothing but
--   `current_soc >= visit target`. When the charger stops first (DCFC at 90% against 100%), the atom never closes,
--   and the deploy gate, which counts any open must-do atom as work (`twin.ottoq_sim_advance_service_flow`,
--   "IDENTICAL predicate to ottoq_plan_dispatch_tick"), holds the car and remedies with `need_service`.
--   `need_service` admits to the service bay whatever the open work is (G196b, not fixed here). The gate's
--   `missing` list is the needs card's (`software_update` for Waymo-006), not the atom that holds it, which is why
--   the car read as waiting for a software update.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The closer also closes a visit's charge atom when a charge session of THAT visit (same run and vehicle, started
--   at or after the visit's `arrived_at`, both sim time) ended `completed`, and no session of that vehicle is open
--   now. That is exactly the flow's own view. It is stamped `closed_by = 'session_completed'` with `closed_soc`,
--   `closed_vs_target` and `closed_session_ended_at`, so a shortfall against the visit's target stays visible and
--   countable, distinct from `ottoq_satisfied` (SoC reached the target) and from a bay completion.
--
--   Deliberately NOT stamped: the session's id. `ocpp_sessions.id` is a fresh random uuid per arm, and a random id
--   in visit atoms is 0216's defect (a hash that moves on a minted id). The session's sim end time identifies it.
--
--   Not changed: readiness. The gate's own SoC test (`current_soc >= ready_soc`) still decides whether a car may
--   deploy; a faulted or cancelled session closes nothing; a car charging again keeps its atom open until that
--   session ends. And not changed: the gate's remedy for other open work (G196b), and the service bay's admission.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   The closer runs every decide tick (`ottoq_sim_decide_and_dispatch`). Charge atoms close earlier, so the deploy
--   gate, the dispatcher's deploy plan and SLA.004 see them done, and deploys, service-bay seats, bookings and the
--   end state move. The recertification runner re-certifies every canon column against the new floor.
--
--   PREDICTED on the next busy_day run: no service-bay seat for a car whose only open must-do atom is `charge`;
--   `closed_by = 'session_completed'` on roughly a quarter of completed DCFC charges; fewer `twin.bay_credit_none`
--   exits; the same number of charges.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0463 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file replaces, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('ottoq.ottoq_close_satisfied_charge_needs(uuid,timestamp with time zone)'::regprocedure))
     <> '5eae8a38a8027de4010387493642f052' THEN
    RAISE EXCEPTION '0463 P2: ottoq.ottoq_close_satisfied_charge_needs is not the body this file replaces';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0463_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'ottoq.ottoq_close_satisfied_charge_needs(uuid,timestamp with time zone)'::regprocedure;

CREATE OR REPLACE FUNCTION ottoq.ottoq_close_satisfied_charge_needs(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'ottoq', 'twin', 'public', 'extensions'
AS $function$
DECLARE v_n int := 0;
BEGIN
  IF p_sim_run_id IS NULL THEN RETURN 0; END IF;

  WITH base AS (
    SELECT n.visit_id,
           n.atoms,
           -- The target for THIS VISIT wins over the vehicle's standing target:
           -- a visit may legitimately have been booked to a different level.
           COALESCE(n.target_soc, v.target_soc, public.ottoq_default_target_soc()) AS tgt,
           v.current_soc,
           -- 0463 (G196): THE CHARGE THIS VISIT ASKED FOR IS ALSO DONE WHEN ITS OWN SESSION COMPLETED.
           -- The flow already reads a `completed` session as the end of charging (charge_complete_holding ->
           -- need_deploy). A DCFC stops at 90%, so a visit targeting 100% kept an open charge atom forever, and
           -- the deploy gate looped the car through the service bay, which cannot close a charge (317d4331,
           -- Waymo-006). Sim time on both sides (arrived_at, started_at, ended_at, p_clock); never a session of an
           -- earlier visit, never while a session of this vehicle is still open, never a faulted one.
           (SELECT max(os.ended_at)
              FROM public.ocpp_sessions os
             WHERE os.sim_run_id     = p_sim_run_id
               AND os.vehicle_id     = n.vehicle_id
               AND n.arrived_at IS NOT NULL
               AND os.started_at    >= n.arrived_at
               AND os.ended_at IS NOT NULL
               AND os.ended_at      <= p_clock
               AND os.stopped_reason = 'completed'
               AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions o2
                                WHERE o2.sim_run_id = p_sim_run_id
                                  AND o2.vehicle_id = n.vehicle_id
                                  AND o2.ended_at IS NULL)) AS session_ended_at
      FROM public.ottoq_visit_needs n
      JOIN public.vehicles v ON v.id = n.vehicle_id
     WHERE n.sim_run_id = p_sim_run_id
       AND v.current_soc IS NOT NULL
       AND jsonb_typeof(n.atoms) = 'array'
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(n.atoms) a
                    WHERE a->>'svc' = 'charge'
                      AND COALESCE(a->>'status','open') <> 'done')
  ), cand AS (
    SELECT b.*, (b.current_soc >= b.tgt) AS soc_met
      FROM base b
     WHERE b.current_soc >= b.tgt
        OR b.session_ended_at IS NOT NULL
  ), rebuilt AS (
    SELECT c.visit_id,
           (SELECT jsonb_agg(
                     CASE WHEN e.a->>'svc' = 'charge'
                           AND COALESCE(e.a->>'status','open') <> 'done'
                          -- Stamped with WHO closed it and WHY, so a satisfied
                          -- need is distinguishable from one a bay completed,
                          -- and a charge that stopped short of its target from both.
                          THEN e.a || jsonb_build_object(
                                        'status',     'done',
                                        'closed_by',  CASE WHEN c.soc_met THEN 'ottoq_satisfied' ELSE 'session_completed' END,
                                        'closed_at',  p_clock,
                                        'closed_soc', c.current_soc,
                                        'closed_vs_target', c.tgt)
                               || CASE WHEN c.soc_met THEN '{}'::jsonb
                                       ELSE jsonb_build_object('closed_session_ended_at', c.session_ended_at) END
                          ELSE e.a END
                     ORDER BY e.ord)
              FROM jsonb_array_elements(c.atoms) WITH ORDINALITY e(a, ord)) AS new_atoms
      FROM cand c
  )
  UPDATE public.ottoq_visit_needs n
     SET atoms = r.new_atoms
    FROM rebuilt r
   WHERE n.visit_id = r.visit_id
     AND r.new_atoms IS NOT NULL;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_def text := pg_get_functiondef('ottoq.ottoq_close_satisfied_charge_needs(uuid,timestamp with time zone)'::regprocedure);
BEGIN
  -- V1: both closing reasons are in the live body, and the session branch is sim-time and completed-only.
  IF position('0463 (G196)' IN v_def) = 0
     OR position($x$'session_completed'$x$ IN v_def) = 0
     OR position($x$'ottoq_satisfied'$x$ IN v_def) = 0
     OR position($x$os.stopped_reason = 'completed'$x$ IN v_def) = 0
     OR position($x$os.started_at    >= n.arrived_at$x$ IN v_def) = 0 THEN
    RAISE EXCEPTION '0463 V1: the closer is not the body this file writes';
  END IF;
  -- V2: no random id is stamped into atoms (0216's class).
  IF v_def ~ $x$'closed_session'\s*,$x$ OR v_def ~ $x$os\.id$x$ THEN
    RAISE EXCEPTION '0463 V2: a session id reached the atom stamp';
  END IF;
  -- V3: one overload, same security and ACL as before.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_close_satisfied_charge_needs') <> 1 THEN
    RAISE EXCEPTION '0463 V3: an overload appeared';
  END IF;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'ottoq.ottoq_close_satisfied_charge_needs(uuid,timestamp with time zone)'::regprocedure)
     OR has_function_privilege('anon', 'ottoq.ottoq_close_satisfied_charge_needs(uuid,timestamp with time zone)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'ottoq.ottoq_close_satisfied_charge_needs(uuid,timestamp with time zone)', 'EXECUTE') THEN
    RAISE EXCEPTION '0463 V3: security or ACL moved';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0463_pre' (CREATE OR REPLACE; the ACL is kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0463_a_charge_that_completed_below_its_visit_target_stayed_open_and_the_deploy_gate_looped_the_car_through_the_service_bay', true,
  'Tick path: ottoq.ottoq_close_satisfied_charge_needs also closes a visit''s charge atom when that visit''s own '
  'session ended completed and none is open (closed_by session_completed). Charge atoms close earlier, so the '
  'deploy gate, the deploy plan and SLA.004 move, and with them deploys, service-bay seats and end state.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
