-- migration-version: 20260920172340
-- migration-name:    the_catch_up_that_stopped_one_state_short_strands_a_vehicle_for_the_whole_run
--
-- 0385  G91: A VEHICLE THAT REACHES `staged_for_departure` STILL HOLDING A MANDATORY
--       CABIN ATOM CAN NEVER HAVE IT STARTED, SO SLA.004 HOLDS IT BACK FOR THE REST OF
--       THE RUN. THE FIX IS ONE STATE IN ONE `IN` LIST, AND THE FUNCTION'S OWN COMMENT
--       ALREADY DESCRIBES THIS EXACT FAILURE FOR A DIFFERENT STATE.
--
-- `forces_recert` **TRUE**. It changes which atoms start on which tick, so a canon
-- computed before it cannot reproduce after it.
--
-- ══ 1. THE GATE, AND THE COMMENT SITTING DIRECTLY ABOVE IT ══════════════════
--
-- `twin.ottoq_sim_advance_visit_atoms`'s first cursor chooses whose atoms may be STARTED.
-- Its inner EXISTS reads, verbatim before this migration:
--
--     AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
--                  WHERE COALESCE(a->>'status','pending') = 'pending'
--                    AND a->>'svc' <> 'readiness_check'
--                    AND ( (a->>'concurrency' = 'cabin'
--                             AND v.current_state IN ('charging_dcfc','charging_l2',
--                                                     'charge_complete_holding'))
--                       OR (a->>'concurrency' IN ('exterior','digital')) ))
--
-- `exterior` and `digital` atoms are startable in all six states the outer WHERE admits.
-- **`cabin` atoms are startable in three.** `staged_for_departure` is not one of them, and
-- a vehicle in that state is therefore never a CANDIDATE — not starved of a technician,
-- never selected at all, at any value of `v_free`.
--
-- **AND THE COMMENT IMMEDIATELY ABOVE THAT LIST ALREADY DIAGNOSES THIS, FOR THE OTHER
-- STATE:** *"charge_complete_holding is kept ONLY as a catch-up: without it a vehicle whose
-- charge finished before the tech arrived would never be cleaned and SLA.004 would block
-- its deploy forever."* That is precisely the mechanism, correctly foreseen, and fixed one
-- state short. A vehicle can leave `charge_complete_holding` for `staged_for_departure`
-- with the cabin atom still pending, and past that boundary the catch-up no longer applies.
--
-- So this migration adds `'staged_for_departure'` to that one list and changes nothing
-- else. It does NOT touch the ORDER BY, and it does NOT touch `ottoq_start_concurrent_atoms`.
--
-- ══ 2. WHY IT IS NOT A TECHNICIAN-PRIORITY PROBLEM, WHICH IS WHAT I FIRST BUILT FOR ══
--
-- My first plan was to re-rank the cursor's ORDER BY so a dispatch-blocked vehicle
-- outranked charging vehicles for the `general_tech` pool. **Measurement killed it, and it
-- would have been the wrong fix shipped confidently.** The pool is not contended for this
-- population: across the blocked vehicle-ticks on run `562bf027-6c74-4cb1-9d96-722af13b2fcc`
-- the pool averaged **1.66 of 10** busy and was full in **0.6%** of them. Re-ranking a queue
-- nobody is waiting in changes nothing. Arithmetic agrees independently: 221 cabin starts at
-- ~4 min each is ~884 technician-minutes against 10 techs x 542 sim-minutes = 5,420, i.e.
-- ~16% utilisation.
--
-- The ORDER BY is also the wrong place on its own terms — it orders CANDIDATES, and the
-- defect is that these vehicles are not candidates.
--
-- ══ 3. WHAT WAS MEASURED, AND WHAT WAS NOT ═════════════════════════════════
--
-- Scope: twin depot (rule 8), completed demo run `562bf027-6c74-4cb1-9d96-722af13b2fcc`
-- (busy_day, seed 777777, 1,241 ticks, sim span 542.6 min, 620 decision snapshots).
--
--   **SOLID — the end state of the run.** 28 vehicles finished holding a pending,
--   non-deferrable, `must_do` atom of class `cabin`: **21 `interior_inspection` + 7
--   `interior_tidy`**. `ottoq_eval_sla_004_required_services` blocks redeployment on exactly
--   that predicate (`must_do` AND NOT `deferrable` AND status NOT IN done/cancelled/skipped),
--   so none of those 28 could legally redeploy, and nothing in the engine could start their
--   atom.
--
--   **INDICATIVE, AND DELIBERATELY NOT QUOTED AS DWELL.** Over the snapshot series, 95 of
--   115 vehicles appear in `staged_for_departure` at some tick; 29 span >= 400 sim-minutes
--   and the widest spans 541.4 of the run's 542.6. **That span is first-seen to last-seen,
--   NOT continuous occupancy** — a vehicle that enters, leaves and returns produces a wide
--   span from two short visits. It bounds the problem's shape; it is not a stranding
--   duration and must not be reported as one.
--
--   **COULD NOT BE ESTABLISHED.** The snapshot frame carries `vehicles[].state` but no
--   atoms, so for any individual blocked tick there is no stored record of which atoms were
--   pending at that moment. The per-tick join "was a cabin atom pending while this vehicle
--   sat in staged_for_departure" is therefore not reconstructible after the fact, and the
--   28-vehicle end state is the strongest available evidence rather than a sample of a
--   larger measured set. A post-fix run is what settles the magnitude.
--
-- ══ 4. AND THE DOCTRINE THE GATE DEFENDS IS ALREADY NOT ENFORCED ═══════════
--
-- The gate exists for `M3_cabin_at_charger` — cabin work should overlap a charging session,
-- because serialising it gives away throughput (CLAUDE.md 2.3). Loosening it deserves care.
-- But the gate is a SELECTION filter only: `ottoq_start_concurrent_atoms` re-checks nothing
-- about vehicle state, and `ottoq_decide_tick` calls it from two enactment sites of its own.
-- Measured on this run, only **35 of 221 cabin starts (15.8%)** actually began in a charging
-- state. So the doctrine is already nominal in five cases out of six, and adding one
-- catch-up state to a selection filter cannot weaken an invariant that the executing path
-- never enforced. **That is a finding about M3 in its own right and is left open, not fixed
-- here** — making cabin work genuinely charge-overlapped would mean gating the STARTER, not
-- the cursor, and that is a throughput change rather than a deadlock repair.

-- ══ P0 PREFLIGHT ═══════════════════════════════════════════════════════════

DO $p0$
DECLARE v_n int;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN
    RAISE EXCEPTION '0385 P0: a sim run is running or paused -- this rewrites a tick-path function and needs a quiet depot';
  END IF;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_visit_atoms'
     AND p.prosrc LIKE '%''charge_complete_holding''))%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0385 P0: the cabin gate does not end at charge_complete_holding as expected (found %) -- the function has changed and this patch must be re-derived', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_visit_atoms'
     AND p.prosrc LIKE '%''staged\_for\_departure''))%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0385 P0: staged_for_departure is already in the cabin gate -- nothing to do';
  END IF;
  RAISE NOTICE '0385 P0: depot quiet, cabin gate is the three-state form';
END $p0$;

-- ══ THE CHANGE ═════════════════════════════════════════════════════════════
-- Body reproduced verbatim from pg_get_functiondef at 2026-09-20 17:23 UTC with exactly one
-- substitution, asserted unique before this file was written. Nothing else is touched.

CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_visit_atoms(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_seed bigint; v_rec RECORD; v_new jsonb; v_a jsonb; v_b jsonb;
  v_changed boolean; v_total int := 0;
  v_triage_done boolean; v_conf numeric; v_roll numeric; v_verdict text;
  v_escalations jsonb; v_tick bigint; v_feed_sim boolean := true;
BEGIN
  SELECT depot_id, COALESCE(random_seed,42), tick_count INTO v_depot, v_seed, v_tick
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;
  SELECT COALESCE(d.feed_mode,'sim')='sim' INTO v_feed_sim FROM depots d WHERE d.id = v_depot;
  v_feed_sim := COALESCE(v_feed_sim, true);

  FOR v_rec IN
    SELECT vn.vehicle_id
      FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
     WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
       AND v.current_state IN ('charging_dcfc','charging_l2','charge_complete_holding',
                               'staged_awaiting_service','staged_for_departure','arrived_at_gate')
       -- M3_cabin_at_charger: cabin work (interior tidy) is performed BY A
       -- TECHNICIAN AT THE CHARGER during the session, so it may only start while the
       -- vehicle is plugged in. Previously it could start in any of six states —
       -- including at the gate and while staged for departure — which is why only 5.8%
       -- of interior cleans actually overlapped a charge. charge_complete_holding is
       -- kept ONLY as a catch-up: without it a vehicle whose charge finished before the
       -- tech arrived would never be cleaned and SLA.004 would block its deploy forever.
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                    WHERE COALESCE(a->>'status','pending') = 'pending'
                      AND a->>'svc' <> 'readiness_check'
                      AND ( (a->>'concurrency' = 'cabin'
                               AND v.current_state IN ('charging_dcfc','charging_l2',
                                                       'charge_complete_holding',
                                                       -- 0385: the second catch-up. The
                                                       -- comment above added
                                                       -- charge_complete_holding for
                                                       -- exactly this failure and stopped
                                                       -- one state short.
                                                       'staged_for_departure'))
                         OR (a->>'concurrency' IN ('exterior','digital')) ))
     ORDER BY (vn.urgency = 'immediate_dispatch') DESC,
              (v.current_state IN ('charging_dcfc','charging_l2')) DESC,
              v.last_state_change ASC,
              vn.vehicle_id   /* 0108: run-stable tail; same-tick transitions tie */
     LIMIT 30
  LOOP
    PERFORM ottoq_start_concurrent_atoms(v_rec.vehicle_id, p_clock);
  END LOOP;

  FOR v_rec IN
    SELECT vn.visit_id, vn.vehicle_id, vn.atoms, v.current_state
      FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
     WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
       AND (EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                    WHERE a->>'status' = 'in_progress' AND (a->>'ends_at')::timestamptz <= p_clock)
         OR (v.current_state = 'staged_for_departure'
             AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                          WHERE a->>'svc' = 'readiness_check' AND COALESCE(a->>'status','pending') = 'pending')))
     ORDER BY vn.vehicle_id   /* 0054: run-stable cursor order */
  LOOP
    v_new := '[]'::jsonb; v_changed := false; v_triage_done := false; v_escalations := '[]'::jsonb;
    FOR v_a IN SELECT * FROM jsonb_array_elements(v_rec.atoms) LOOP
      IF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock THEN
        v_a := v_a || jsonb_build_object('status','done','done_at', v_a->'ends_at');
        v_changed := true; v_total := v_total + 1;
        -- N2/M4c: close the matching flow-contract leg with real times
        PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, v_a->>'svc',
                (v_a->>'started_at')::timestamptz, (v_a->>'ends_at')::timestamptz);

        -- ══════════ 0005: CREDIT THE LEDGER THE DEPOT ACTUALLY READS ══════════
        -- This is the line whose absence meant 90 inspections, 26 cabin tidies, 5 sensor
        -- cleans and 5 item retrievals in run 909 moved nothing at all. Shared function,
        -- shared with the real-telemetry seam -- see §3 header. Fully qualified so
        -- search_path can never resolve it somewhere else. Own handler: a ledger failure
        -- must never unwind the atom close, the leg close, or the tick.
        BEGIN
          PERFORM public.ottoq_wear_mark_serviced(
                    v_rec.vehicle_id, p_sim_run_id, v_a->>'svc',
                    COALESCE((v_a->>'ends_at')::timestamptz, p_clock));
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'ottoq_sim_advance_visit_atoms: need-ledger credit FAILED SAFELY vehicle=% svc=% %: %',
            v_rec.vehicle_id, v_a->>'svc', SQLSTATE, SQLERRM;
        END;

        IF v_a->>'svc' = 'triage_check' THEN v_triage_done := true; END IF;
        IF COALESCE((v_a->>'requires_tech_greenlight')::boolean,false) THEN
          INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, visit_id, sim_run_id, depot_id,
                 payload, requested_at, decide_after, expires_at, priority)
          SELECT 'tech_greenlight', v_rec.vehicle_id, v_rec.visit_id, p_sim_run_id, v_depot,
                 jsonb_build_object('svc', v_a->>'svc', 'est_min', v_a->>'est_min'),
                 p_clock,
                 p_clock + ((15 + floor(ottoq_sim_seeded_random(v_seed, v_rec.vehicle_id::text || ':glDelay') * 45))::text || ' minutes')::interval,
                 p_clock + interval '120 minutes', 'high'
          WHERE NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals ap
                             WHERE ap.vehicle_id = v_rec.vehicle_id AND ap.approval_type = 'tech_greenlight'
                               AND ap.sim_run_id = p_sim_run_id  /* 0108: a prior run's approval must not suppress this run's raise */
                               AND (ap.status = 'pending' OR ap.decided_at > p_clock - interval '60 minutes'));
        END IF;
      ELSIF v_a->>'svc' = 'readiness_check' AND COALESCE(v_a->>'status','pending') = 'pending'
         AND v_rec.current_state = 'staged_for_departure' THEN
        -- 0005 NOTE: deliberately NOT credited. A readiness check confirms the vehicle is
        -- fit to leave; it restores nothing, and there is no column it may honestly move.
        v_a := v_a || jsonb_build_object('status','done','done_at', to_jsonb(p_clock));
        v_changed := true; v_total := v_total + 1;
        PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, 'inspect',
                p_clock - interval '3 minutes', p_clock);
      END IF;
      v_new := v_new || jsonb_build_array(v_a);
    END LOOP;

    IF v_triage_done AND v_feed_sim THEN
      v_b := v_new; v_new := '[]'::jsonb;
      FOR v_a IN SELECT * FROM jsonb_array_elements(v_b) LOOP
        IF COALESCE((v_a->>'confirm_required')::boolean,false)
           AND COALESCE(v_a->>'status','pending') = 'pending' THEN
          v_conf := COALESCE((v_a->>'confidence')::numeric, 0.6);
          v_roll := ottoq_sim_seeded_random(v_seed, v_rec.vehicle_id::text || ':' || (v_a->>'svc') || ':verdict');
          v_verdict := CASE WHEN v_roll < v_conf THEN 'confirm'
                            WHEN v_roll < v_conf + (1 - v_conf) * 0.7 THEN 'clear'
                            ELSE 'escalate' END;
          IF v_verdict = 'confirm' THEN
            v_a := v_a || jsonb_build_object('confirm_required', false, 'triage_verdict', 'confirm');
          ELSIF v_verdict = 'clear' THEN
            -- 0005 NOTE: deliberately NOT credited. Cleared by triage means the work was
            -- never performed, so no ledger column may move. Cancellation is not completion.
            v_a := v_a || jsonb_build_object('status','cancelled','confirm_required',false,
                     'triage_verdict','clear','cleared_by_triage',true);
            PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, v_a->>'svc', p_clock, p_clock);
          ELSE
            v_a := v_a || jsonb_build_object('confirm_required', false, 'triage_verdict', 'escalate');
            IF v_a->>'svc' = 'interior_tidy' THEN
              v_escalations := v_escalations || jsonb_build_array(jsonb_build_object(
                'svc','interior_deep_clean','must_do',false,'deferrable',true,'est_min',20,
                'concurrency','bay','requires_bay','detail','carryover_eligible',true,'from_escalation',true));
            ELSIF v_a->>'svc' = 'sensor_clean' THEN
              v_escalations := v_escalations || jsonb_build_array(jsonb_build_object(
                'svc','sensor_calibration','must_do',false,'deferrable',true,'est_min',30,
                'concurrency','bay','requires_bay','service_bay','carryover_eligible',true,'from_escalation',true));
            ELSIF v_a->>'svc' = 'cosmetic_repair' THEN
              v_a := v_a || jsonb_build_object('requires_tech_greenlight', true);
            END IF;
          END IF;
          INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,action_context,resolved_action_context,
                 entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
          VALUES (p_sim_run_id, v_tick, p_clock, v_depot, 'task_start', 'triage_verdict',
                 'vehicle', v_rec.vehicle_id,
                 jsonb_build_object('svc', v_a->>'svc', 'confidence', v_conf),
                 jsonb_build_object('verb','triage'),
                 jsonb_build_object('verb','triage_' || v_verdict, 'svc', v_a->>'svc'),
                 'enacted', 0, 0);
        END IF;
        v_new := v_new || jsonb_build_array(v_a);
      END LOOP;
      IF jsonb_array_length(v_escalations) > 0 THEN
        FOR v_a IN SELECT * FROM jsonb_array_elements(v_escalations) LOOP
          IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_new) e WHERE e->>'svc' = v_a->>'svc') THEN
            v_new := v_new || jsonb_build_array(v_a);
          END IF;
        END LOOP;
      END IF;
      v_changed := true;
    END IF;

    IF v_changed THEN UPDATE ottoq_visit_needs SET atoms = v_new WHERE visit_id = v_rec.visit_id; END IF;
  END LOOP;

  UPDATE ottoq_visit_needs vn SET status =
    CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                       WHERE COALESCE((a->>'carryover_eligible')::boolean,false)
                         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'))
         THEN 'carried_over' ELSE 'complete' END
  FROM vehicles v
  WHERE v.id = vn.vehicle_id AND vn.depot_id = v_depot
    AND vn.status IN ('open','in_progress') AND COALESCE(vn.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid) /* 0124 */
    AND v.current_state IN ('deployed','en_route_to_deployment');
  RETURN v_total;
END; $function$;

-- ══ POSTFLIGHT ════════════════════════════════════════════════════════════

DO $p1$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_visit_atoms'
     AND p.prosrc LIKE '%''staged\_for\_departure''))%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0385 P1: staged_for_departure is not in the cabin gate (found %)', v_n;
  END IF;

  -- the three original states must all survive; dropping one would trade this deadlock for another
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_visit_atoms'
     AND p.prosrc LIKE '%''charging\_dcfc'',''charging\_l2''%'
     AND p.prosrc LIKE '%''charge\_complete\_holding''%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0385 P1: one of the three original cabin states was lost';
  END IF;

  -- exterior/digital must remain unconditioned on state, or 0383's walkaround regresses
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_visit_atoms'
     AND p.prosrc LIKE '%OR (a->>''concurrency'' IN (''exterior'',''digital''))%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0385 P1: the exterior/digital branch changed shape -- 0383 depends on it being state-free';
  END IF;
  RAISE NOTICE '0385 P1: cabin gate is now four states, exterior/digital still state-free';
END $p1$;

DO $p2$
DECLARE v_out int;
BEGIN
  -- INVOKE it, do not merely grep it: 0381 shipped a body that raised 42703 while three
  -- source assertions passed, because plpgsql resolves columns at execution time. There is
  -- no live run, so this is expected to return 0 and the point is that it RUNS.
  SELECT twin.ottoq_sim_advance_visit_atoms(
           (SELECT sim_run_id FROM public.ottoq_sim_runs
             WHERE depot_id='11111111-1111-1111-1111-111111111111'
             ORDER BY started_at DESC LIMIT 1),
           now())
    INTO v_out;
  RAISE NOTICE '0385 P2: function executes, returned % atoms advanced', v_out;
END $p2$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0385_the_catch_up_that_stopped_one_state_short_strands_a_vehicle_for_the_whole_run', true,
  'G91. twin.ottoq_sim_advance_visit_atoms chooses which vehicles may have in-place atoms '
  'STARTED, and its inner EXISTS sub-gates concurrency=cabin to three vehicle states while '
  'exterior/digital are startable in all six. staged_for_departure is not one of the three, '
  'so a vehicle that reaches it still holding a mandatory cabin atom is never a candidate at '
  'any value of v_free -- and ottoq_eval_sla_004_required_services (critical) blocks '
  'redeployment on exactly that atom, so the vehicle is held for the rest of the run. THE '
  'FUNCTION''S OWN COMMENT ALREADY DIAGNOSES THIS FOR THE NEIGHBOURING STATE: '
  'charge_complete_holding is documented as kept "ONLY as a catch-up: without it a vehicle '
  'whose charge finished before the tech arrived would never be cleaned and SLA.004 would '
  'block its deploy forever." Correct mechanism, one state short. This adds '
  'staged_for_departure to that list and nothing else. MEASURED on completed run '
  '562bf027 (busy_day, seed 777777, 1241 ticks, 542.6 sim-min): 28 vehicles ended holding a '
  'pending non-deferrable must_do cabin atom (21 interior_inspection, 7 interior_tidy), none '
  'of which any code path could start. NOT a technician-priority problem, which is what I '
  'first planned to fix: the general_tech pool averaged 1.66 of 10 busy during the blocked '
  'ticks and was full in 0.6% of them, and 221 cabin starts at ~4 min against 10 techs x 542 '
  'min is ~16% utilisation -- re-ranking the ORDER BY would have re-ranked a queue nobody was '
  'waiting in, and the ORDER BY orders candidates while the defect is that these vehicles are '
  'not candidates. Loosening the gate cannot weaken the M3_cabin_at_charger doctrine it '
  'defends, because that doctrine is already nominal: ottoq_start_concurrent_atoms re-checks '
  'no vehicle state and ottoq_decide_tick calls it from two enactment sites of its own, so '
  'only 35 of 221 cabin starts (15.8%) actually began in a charging state. That is left open '
  'as an M3 finding, not fixed here. forces_recert TRUE: atoms start on different ticks.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
