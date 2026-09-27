-- migration-version: 20260927164827
-- migration-name:    the_challenger_asks_whether_the_chargers_could_do_more_while_cars_wait
--
-- 0532  **The challenger, first form: a loop beside the funnel that asks, every minute of a live day, whether the
--       depot could be doing better right now, writes down what it saw and what a different decision would have
--       gained, and grades each claim against what happened. Its first three questions are about the day's binding
--       resource: a DCFC charging a car already above the deploy floor while cars wait for a charger, a charger free
--       by all three gates while cars wait, and a charger faulted while cars wait.** `db/checks/0398`.
--
-- ══ §1 WHY THESE QUESTIONS FIRST ══════════════════════════════════════════════════════════════════════════════════════
--
--   On validation run 6e0352a0 (0397 §5) cars waited for a charger in every one of the day's 551 minutes, a mean 34.2
--   of them at once and 58 at the worst. The ten DCFCs were busy 3,980 charger-minutes; 1,576 of those -- 40% -- were
--   spent on cars already at or above the 80% deploy floor, every one of them while cars waited, and 863 above 85%. A
--   DCFC session averaged 49.8 minutes, 22.9 of them above the floor. Nothing in the engine measured that: the charge
--   plan fills a daytime DCFC to 90% whoever is waiting (`ottoq_target_soc_cap`), and the scorecard had no line for
--   charger time spent where it bought no deployment. That is the kind of thing the challenger exists to see.
--
-- ══ §2 WHAT THIS ADDS ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_challenger_findings` -- one row per EPISODE of a question (a session, a free-charger spell, a fault),
--   evidence class, no foreign key to the run (0340's rule: the claims must outlive the run they are about). Each row
--   carries what was seen at first sight, the worst it got, the counterfactual it claims, and, once the episode closes,
--   what happened and a grade.
--   `public.ottoq_challenger_scan(run)` -- reads the live world at the run's sim clock and upserts the episodes it sees;
--   an episode not seen in this scan is closed and graded at once, from the rows that exist now, so a demo purge that
--   deletes the run's working data cannot take the grade with it.
--     Q1 charging_above_floor_while_cars_wait  an active DCFC session whose car is at or above the deploy floor, while
--        at least one car waits for a charger. CLAIM: ending it at first sight hands the charger to the longest-waiting
--        car. GRADE: the saving is the lesser of the minutes the session went on and the minutes that car went on
--        waiting -- confirmed at 5 or more, refuted under 1.
--     Q2 charger_offerable_while_cars_wait  a DCFC or L2 stall free by pointer, calendar (on the SIM clock, 0326 §1),
--        session and charger state (not Faulted, Unavailable or Maintenance), while a car has waited 5 minutes or more. CLAIM: a missed assignment. GRADE:
--        confirmed if it stayed free across two scans and the longest waiter went on waiting 5 minutes or more.
--     Q3 charger_faulted_while_cars_wait  a charger Faulted while cars wait. CLAIM: charger capacity lost to the
--        fault. GRADE: confirmed at 30 minutes or more.
--   `public.ottoq_challenger_taper_tax(run)` -- the hindsight measure behind Q1 for a whole run, from the signed SoC
--     stream and the charge sessions (§1's numbers).
--   `public.ottoq_challenger_report(run)` -- the questions' counts, grades and claimed savings, beside the taper tax.
--   `public.ottoq_challenger_tick()` -- scans every live operator and production run; cron job `challenger_scan`,
--     every minute.
--   OBSERVE AND GRADE FIRST. No finding is submitted to the funnel yet: a question earns a seat among the proposers
--   (`ottoq_external_proposals`, disposed by the decide path like any other) once its hit rate and grades are measured
--   -- the blind-spot promotion doctrine (2.9a) applied to proposals. Q1 also has no verb to act on: the engine cannot
--   end a charge early. Its lever today is the dial experiment registered at 0531 (08262943: `dcfc_target_soc_day` 90
--   against 85, primary unmet demand), and a queue-aware charge target is the design it points at.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════════
--
--   Nothing here is on the certified path or runs inside a tick: the scan reads the world in its own transaction from
--   its own cron job and writes only its own ledger, and it scans operator and production runs only -- a pair's arms
--   live inside one uncommitted transaction and are invisible to it.

BEGIN;

-- ── P0: no pair in flight, and no live run: V3 starts one through the operator's door ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0532 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running', 'paused')) THEN
    RAISE EXCEPTION '0532 P0: a run is live';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
BEGIN
  IF to_regclass('public.ottoq_challenger_findings') IS NOT NULL THEN
    RAISE EXCEPTION '0532 P2: the ledger already exists';
  END IF;
  IF to_regprocedure('public.ottoq_deploy_target_now(uuid,uuid,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.ottoq_policy_get(uuid,text,numeric)') IS NULL
     OR to_regprocedure('public.ottoq_engine_hash()') IS NULL THEN
    RAISE EXCEPTION '0532 P2: a function the scan reads is missing';
  END IF;
  -- the live values the scan reads: an active session, an open visit, a held or active booking, a faulted charger
  IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                  WHERE t.typname = 'ocpp_session_status' AND e.enumlabel = 'active')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.ottoq_visit_needs'::regclass
                      AND pg_get_constraintdef(c.oid) LIKE '%''open''%''in_progress''%')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.ottoq_stall_bookings'::regclass
                      AND pg_get_constraintdef(c.oid) LIKE '%''held''%''active''%')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid = 'public.ottoq_ocpp_chargers'::regclass
                      AND pg_get_constraintdef(c.oid) LIKE '%station_state%''Unavailable''%''Faulted''%''Maintenance''%') THEN
    RAISE EXCEPTION '0532 P2: a state value the scan reads is not as measured';
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'challenger_scan') THEN
    RAISE EXCEPTION '0532 P2: a cron job named challenger_scan already exists';
  END IF;
END $premises$;

-- ── the ledger ──
CREATE TABLE public.ottoq_challenger_findings (
  finding_id      bigserial PRIMARY KEY,
  sim_run_id      uuid,                    -- NULL on a production feed; NO foreign key (evidence, 0340)
  depot_id        uuid NOT NULL,
  question        text NOT NULL CHECK (question IN ('charging_above_floor_while_cars_wait',
                                                     'charger_offerable_while_cars_wait',
                                                     'charger_faulted_while_cars_wait')),
  entity_type     text NOT NULL,           -- charge_session | stall | charger
  entity_id       uuid NOT NULL,
  episode_key     text NOT NULL,           -- one row per episode: the session, or the stall/charger and its first sight
  first_seen_sim  timestamptz NOT NULL,
  last_seen_sim   timestamptz NOT NULL,
  scans_seen      int NOT NULL DEFAULT 1,
  evidence        jsonb NOT NULL,          -- what was seen at first sight
  peak            jsonb NOT NULL DEFAULT '{}'::jsonb,   -- the worst the episode got
  counterfactual  jsonb NOT NULL,          -- what the challenger claims a different decision would have gained
  status          text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
  closed_sim      timestamptz,
  realized        jsonb,                   -- what happened, read when the episode closed
  grade           text CHECK (grade IN ('confirmed', 'refuted', 'inconclusive')),
  graded_at       timestamptz,
  proposal_id     uuid,                    -- set when a question has earned a proposer seat; never in the first form
  detected_at     timestamptz NOT NULL DEFAULT now(),
  engine_hash     text,
  scan_version    text NOT NULL,
  CONSTRAINT ottoq_challenger_findings_episode UNIQUE NULLS NOT DISTINCT (sim_run_id, question, episode_key)
);
CREATE INDEX ottoq_challenger_findings_run_status ON public.ottoq_challenger_findings (sim_run_id, status);
COMMENT ON TABLE public.ottoq_challenger_findings IS
  '0532. The challenger''s claims: one row per episode of a question it asks of a live run, what it saw, what a '
  'different decision would have gained, and the grade that claim got against what happened. Evidence: no foreign key '
  'to the run, registered class evidence, so the purge of a run''s working data leaves its claims and grades.';
REVOKE ALL ON public.ottoq_challenger_findings FROM anon, authenticated;
REVOKE ALL ON SEQUENCE public.ottoq_challenger_findings_finding_id_seq FROM anon, authenticated;
GRANT SELECT ON public.ottoq_challenger_findings TO authenticated;

INSERT INTO public.ottoq_run_scope_registry (table_schema, table_name, column_name, class, note)
VALUES ('public', 'ottoq_challenger_findings', 'sim_run_id', 'evidence',
        '0532: the challenger''s claims and their grades. Evidence, not engine: a claim graded after its run''s working '
        'data is purged must still be readable, and the learning loop reads the grades across runs. No FK to '
        'ottoq_sim_runs, deliberately (0340).');

-- ── who is waiting for a charger at a moment: an open visit that arrived owing a charge still owed, whose car is in
--    the depot with no charge session running -- 0501's waiting visit, read live ──
CREATE FUNCTION public.ottoq_challenger_waiting(p_run uuid, p_now timestamptz)
 RETURNS TABLE(vehicle_id uuid, display_name text, soc numeric, arrived_at timestamptz, waited_min numeric)
 LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT DISTINCT ON (vn.vehicle_id) vn.vehicle_id, v.display_name, v.current_soc::numeric, vn.arrived_at,
         round((extract(epoch FROM p_now - vn.arrived_at) / 60.0)::numeric, 1)
    FROM public.ottoq_visit_needs vn JOIN public.vehicles v ON v.id = vn.vehicle_id
   WHERE vn.sim_run_id = p_run AND vn.status IN ('open', 'in_progress')
     AND vn.arrived_at IS NOT NULL AND vn.arrived_at <= p_now
     AND v.current_state::text NOT IN ('deployed', 'en_route_to_deployment', 'en_route_to_depot', 'offline')
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                  WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status', 'pending') NOT IN ('done', 'skipped', 'cancelled'))
     AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions os
                      WHERE os.sim_run_id = p_run AND os.vehicle_id = vn.vehicle_id AND os.status = 'active')
   ORDER BY vn.vehicle_id, vn.arrived_at
$function$;

-- ── the scan ──
CREATE FUNCTION public.ottoq_challenger_scan(p_run uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
-- 0532: the challenger's scan of one live run at its sim clock. Reads the world; writes only its own ledger.
DECLARE
  r record; s record; v_now timestamptz; v_floor numeric; v_target int; v_out int; v_engine text;
  v_n int; v_longest numeric; v_longest_car uuid; v_longest_name text; v_below int;
  v_q1 int := 0; v_q2 int := 0; v_q3 int := 0; v_closed int := 0; v_ctx jsonb;
  c_ver constant text := 'challenger_v1';
BEGIN
  SELECT sim_run_id, depot_id, sim_clock_current, status INTO r FROM public.ottoq_sim_runs WHERE sim_run_id = p_run;
  -- a paused run's clock does not move: a scan of it would only count the same moment again
  IF NOT FOUND OR r.status <> 'running' THEN
    RETURN jsonb_build_object('run', p_run, 'scanned', false, 'why', COALESCE(r.status, 'no such run'));
  END IF;
  v_now    := r.sim_clock_current;
  v_floor  := public.ottoq_policy_get(p_run, 'deploy_floor_soc', 80);
  v_target := public.ottoq_deploy_target_now(p_run, r.depot_id, v_now);
  v_engine := public.ottoq_engine_hash();
  SELECT count(*) INTO v_out FROM public.vehicles
   WHERE home_depot_id = r.depot_id AND category = 'autonomous' AND current_state = 'deployed';
  SELECT count(*), max(w.waited_min), (array_agg(w.vehicle_id ORDER BY w.waited_min DESC))[1],
         (array_agg(w.display_name ORDER BY w.waited_min DESC))[1], count(*) FILTER (WHERE w.soc < v_floor)
    INTO v_n, v_longest, v_longest_car, v_longest_name, v_below
    FROM public.ottoq_challenger_waiting(p_run, v_now) w;
  v_ctx := jsonb_build_object('sim_clock', v_now, 'cars_waiting', v_n, 'waiting_below_floor', v_below,
                              'longest_wait_min', v_longest, 'longest_waiter', v_longest_name,
                              'longest_waiter_id', v_longest_car, 'deploy_target', v_target, 'deployed', v_out,
                              'deploy_floor', v_floor);

  IF v_n > 0 THEN
    -- Q1: a DCFC charging a car at or above the deploy floor while cars wait
    FOR s IN SELECT os.id, os.vehicle_id, v.display_name, v.current_soc, v.target_soc, os.started_at, st.stall_code
               FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id
               JOIN public.vehicles v ON v.id = os.vehicle_id
              WHERE os.sim_run_id = p_run AND os.status = 'active' AND st.stall_type = 'dcfc'
                AND v.current_soc >= v_floor
    LOOP
      INSERT INTO public.ottoq_challenger_findings AS f
             (sim_run_id, depot_id, question, entity_type, entity_id, episode_key, first_seen_sim, last_seen_sim,
              evidence, peak, counterfactual, engine_hash, scan_version)
      VALUES (p_run, r.depot_id, 'charging_above_floor_while_cars_wait', 'charge_session', s.id, s.id::text, v_now, v_now,
              v_ctx || jsonb_build_object('car', s.display_name, 'car_id', s.vehicle_id, 'car_soc', s.current_soc,
                                          'car_target_soc', s.target_soc, 'stall', s.stall_code,
                                          'session_started', s.started_at),
              jsonb_build_object('cars_waiting', v_n, 'longest_wait_min', v_longest, 'car_soc', s.current_soc),
              jsonb_build_object('claim', 'ending this charge now hands the DCFC to the longest-waiting car',
                                 'beneficiary', v_longest_name, 'beneficiary_id', v_longest_car,
                                 'beneficiary_waited_min', v_longest),
              v_engine, c_ver)
      ON CONFLICT (sim_run_id, question, episode_key) DO UPDATE
         SET last_seen_sim = EXCLUDED.last_seen_sim, scans_seen = f.scans_seen + 1,
             peak = jsonb_build_object(
               'cars_waiting', GREATEST((f.peak->>'cars_waiting')::int, v_n),
               'longest_wait_min', GREATEST((f.peak->>'longest_wait_min')::numeric, v_longest),
               'car_soc', GREATEST((f.peak->>'car_soc')::numeric, s.current_soc))
       WHERE f.status = 'open';
      v_q1 := v_q1 + 1;
    END LOOP;

    -- Q2: a charger free by every gate while a car has waited five minutes or more
    IF v_longest >= 5 THEN
      FOR s IN SELECT st.id, st.stall_code, st.stall_type::text AS kind
                 FROM public.stalls st LEFT JOIN public.ottoq_ocpp_chargers c ON c.charger_id = st.ocpp_charger_id
                WHERE st.depot_id = r.depot_id AND st.stall_type IN ('dcfc', 'l2')
                  AND st.status::text = 'available' AND st.current_vehicle_id IS NULL AND st.reserved_by IS NULL
                  AND COALESCE(c.station_state, 'Available') NOT IN ('Faulted', 'Unavailable', 'Maintenance')
                  AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b      -- the SIM clock (0326 §1)
                                   WHERE b.stall_id = st.id AND b.state IN ('held', 'active')
                                     AND b.during && tstzrange(v_now, v_now + interval '1 minute'))
                  AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions os WHERE os.stall_id = st.id AND os.status = 'active')
      LOOP
        UPDATE public.ottoq_challenger_findings f
           SET last_seen_sim = v_now, scans_seen = f.scans_seen + 1,
               peak = jsonb_build_object('cars_waiting', GREATEST((f.peak->>'cars_waiting')::int, v_n),
                                         'longest_wait_min', GREATEST((f.peak->>'longest_wait_min')::numeric, v_longest))
         WHERE f.sim_run_id = p_run AND f.question = 'charger_offerable_while_cars_wait' AND f.entity_id = s.id
           AND f.status = 'open';
        IF NOT FOUND THEN
          INSERT INTO public.ottoq_challenger_findings
                 (sim_run_id, depot_id, question, entity_type, entity_id, episode_key, first_seen_sim, last_seen_sim,
                  evidence, peak, counterfactual, engine_hash, scan_version)
          VALUES (p_run, r.depot_id, 'charger_offerable_while_cars_wait', 'stall', s.id, s.id || '@' || v_now, v_now, v_now,
                  v_ctx || jsonb_build_object('stall', s.stall_code, 'stall_type', s.kind),
                  jsonb_build_object('cars_waiting', v_n, 'longest_wait_min', v_longest),
                  jsonb_build_object('claim', 'a free charger and a waiting car: a missed assignment',
                                     'beneficiary', v_longest_name, 'beneficiary_id', v_longest_car,
                                     'beneficiary_waited_min', v_longest),
                  v_engine, c_ver);
        END IF;
        v_q2 := v_q2 + 1;
      END LOOP;
    END IF;

    -- Q3: a charger faulted while cars wait
    FOR s IN SELECT c.charger_id, c.station_state_changed_at, c.last_fault_code, st.stall_code, st.stall_type::text AS kind
               FROM public.ottoq_ocpp_chargers c JOIN public.stalls st ON st.ocpp_charger_id = c.charger_id
              WHERE st.depot_id = r.depot_id AND st.stall_type IN ('dcfc', 'l2') AND c.station_state = 'Faulted'
    LOOP
      INSERT INTO public.ottoq_challenger_findings AS f
             (sim_run_id, depot_id, question, entity_type, entity_id, episode_key, first_seen_sim, last_seen_sim,
              evidence, peak, counterfactual, engine_hash, scan_version)
      VALUES (p_run, r.depot_id, 'charger_faulted_while_cars_wait', 'charger', s.charger_id,
              s.charger_id || '@' || COALESCE(s.station_state_changed_at::text, 'unknown'), v_now, v_now,
              v_ctx || jsonb_build_object('stall', s.stall_code, 'stall_type', s.kind, 'fault_code', s.last_fault_code,
                                          'faulted_since', s.station_state_changed_at),
              jsonb_build_object('cars_waiting', v_n, 'longest_wait_min', v_longest),
              jsonb_build_object('claim', 'charger capacity lost to a fault while cars wait'),
              v_engine, c_ver)
      ON CONFLICT (sim_run_id, question, episode_key) DO UPDATE
         SET last_seen_sim = EXCLUDED.last_seen_sim, scans_seen = f.scans_seen + 1,
             peak = jsonb_build_object('cars_waiting', GREATEST((f.peak->>'cars_waiting')::int, v_n),
                                       'longest_wait_min', GREATEST((f.peak->>'longest_wait_min')::numeric, v_longest))
       WHERE f.status = 'open';
      v_q3 := v_q3 + 1;
    END LOOP;
  END IF;

  -- an episode this scan did not see has ended: close it and grade it now, from the rows that exist now
  SELECT count(*) INTO v_closed FROM public.ottoq_challenger_close(p_run, v_now);

  RETURN jsonb_build_object('run', p_run, 'scanned', true, 'sim_clock', v_now, 'cars_waiting', v_n,
                            'charging_above_floor', v_q1, 'charger_offerable', v_q2, 'charger_faulted', v_q3,
                            'closed', v_closed);
END
$function$;

-- ── close and grade the episodes a scan did not see ──
CREATE FUNCTION public.ottoq_challenger_close(p_run uuid, p_now timestamptz)
 RETURNS SETOF bigint
 LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
-- 0532: an open episode not seen at p_now has ended. Its realized outcome is read now, while the run's rows exist.
DECLARE f record; v_ended timestamptz; v_plug timestamptz; v_after numeric; v_ran numeric; v_saving numeric;
        v_real jsonb; v_grade text;
BEGIN
  FOR f IN SELECT * FROM public.ottoq_challenger_findings
            WHERE sim_run_id IS NOT DISTINCT FROM p_run AND status = 'open' AND last_seen_sim < p_now
            ORDER BY finding_id
  LOOP
    -- the beneficiary's first charger after first sight, if any yet
    v_plug := (SELECT min(os.started_at) FROM public.ocpp_sessions os
                WHERE os.sim_run_id = p_run AND os.vehicle_id = (f.counterfactual->>'beneficiary_id')::uuid
                  AND os.started_at >= f.first_seen_sim);
    v_after := round((extract(epoch FROM COALESCE(v_plug, p_now) - f.first_seen_sim) / 60.0)::numeric, 1);
    IF f.question = 'charging_above_floor_while_cars_wait' THEN
      v_ended := (SELECT COALESCE(os.ended_at, p_now) FROM public.ocpp_sessions os WHERE os.id = f.entity_id);
      v_ran := round((extract(epoch FROM COALESCE(v_ended, f.last_seen_sim) - f.first_seen_sim) / 60.0)::numeric, 1);
      v_saving := LEAST(v_ran, v_after);
      v_grade := CASE WHEN v_saving >= 5 THEN 'confirmed' WHEN v_saving < 1 THEN 'refuted' ELSE 'inconclusive' END;
      v_real := jsonb_build_object('session_ended', v_ended, 'minutes_charged_after_first_sight', v_ran,
                                   'beneficiary_first_plug', v_plug, 'beneficiary_waited_after_min', v_after,
                                   'saving_min', v_saving, 'beneficiary_still_waiting', v_plug IS NULL);
    ELSIF f.question = 'charger_offerable_while_cars_wait' THEN
      v_ran := round((extract(epoch FROM f.last_seen_sim - f.first_seen_sim) / 60.0)::numeric, 1);
      v_grade := CASE WHEN f.scans_seen >= 2 AND v_after >= 5 THEN 'confirmed'
                      WHEN f.scans_seen = 1 AND v_after < 5 THEN 'refuted' ELSE 'inconclusive' END;
      v_real := jsonb_build_object('free_for_min_at_least', v_ran, 'scans_free', f.scans_seen,
                                   'beneficiary_first_plug', v_plug, 'beneficiary_waited_after_min', v_after);
    ELSE
      v_ran := round((extract(epoch FROM f.last_seen_sim - f.first_seen_sim) / 60.0)::numeric, 1);
      v_grade := CASE WHEN v_ran >= 30 THEN 'confirmed' ELSE 'inconclusive' END;
      v_real := jsonb_build_object('faulted_while_waiting_min_at_least', v_ran, 'scans_seen', f.scans_seen);
    END IF;
    UPDATE public.ottoq_challenger_findings
       SET status = 'closed', closed_sim = p_now, realized = v_real, grade = v_grade, graded_at = now()
     WHERE finding_id = f.finding_id;
    RETURN NEXT f.finding_id;
  END LOOP;
END
$function$;

-- ── the hindsight measure behind Q1, for a whole run ──
CREATE FUNCTION public.ottoq_challenger_taper_tax(p_run uuid)
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  -- 0532: charger-minutes spent on cars at or above the deploy floor (and above 85%) while cars waited for a charger.
  -- Waiting is 0501's definition over the day: a visit that arrived owing a charge waits until its first session before
  -- the car's next dispatch, or to the horizon while still owed. When a session crossed a level is read from the
  -- signed SoC stream. MATERIALIZED where a CTE feeds the per-minute counts (0397 §2).
  WITH r AS MATERIALIZED (SELECT sim_run_id, sim_clock_start, sim_clock_current FROM public.ottoq_sim_runs WHERE sim_run_id = p_run),
  fl AS MATERIALIZED (SELECT public.ottoq_policy_get(p_run, 'deploy_floor_soc', 80) AS v),
  soc AS MATERIALIZED (
    SELECT e.entity_id AS car, e.sim_clock_at AS t, (e.payload->'diff'->'current_soc'->>'to')::numeric AS s
      FROM public.ottoq_events e
     WHERE e.sim_run_id = p_run AND (e.event_type || '') = 'vehicle.state_changed' AND e.payload->'diff' ? 'current_soc'),
  sess AS MATERIALIZED (
    SELECT os.id, os.vehicle_id AS car, st.stall_type::text AS kind, os.started_at AS t0,
           COALESCE(os.ended_at, r.sim_clock_current) AS t1, os.soc_start
      FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id, r
     WHERE os.sim_run_id = p_run AND COALESCE(os.ended_at, r.sim_clock_current) > os.started_at),
  cr AS MATERIALIZED (
    SELECT s.*,
           CASE WHEN s.soc_start >= (SELECT v FROM fl) THEN s.t0
                ELSE (SELECT min(x.t) FROM soc x WHERE x.car = s.car AND x.t >= s.t0 AND x.t < s.t1 AND x.s >= (SELECT v FROM fl)) END AS t80,
           CASE WHEN s.soc_start >= 85 THEN s.t0
                ELSE (SELECT min(x.t) FROM soc x WHERE x.car = s.car AND x.t >= s.t0 AND x.t < s.t1 AND x.s >= 85) END AS t85
      FROM sess s),
  v AS (
    SELECT vn.vehicle_id, vn.arrived_at, (SELECT a FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'charge' LIMIT 1) AS ca
      FROM public.ottoq_visit_needs vn, r
     WHERE vn.sim_run_id = p_run AND vn.arrived_at IS NOT NULL AND vn.arrived_at <= r.sim_clock_current
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a WHERE a->>'svc' = 'charge')),
  w AS MATERIALIZED (
    SELECT v.vehicle_id AS car, v.arrived_at AS w0,
           COALESCE((SELECT min(o.started_at) FROM public.ocpp_sessions o
                      WHERE o.sim_run_id = p_run AND o.vehicle_id = v.vehicle_id AND o.started_at >= v.arrived_at
                        AND o.started_at < COALESCE((SELECT min(d.dispatched_at) FROM public.ottoq_vehicle_dispatches d
                                                      WHERE d.sim_run_id = p_run AND d.vehicle_id = v.vehicle_id
                                                        AND d.dispatched_at > v.arrived_at), 'infinity')),
                    CASE WHEN COALESCE(v.ca->>'status', 'open') NOT IN ('done', 'skipped', 'cancelled')
                         THEN (SELECT sim_clock_current FROM r) END) AS w1
      FROM v),
  mins AS (SELECT gs AS m FROM r, generate_series(r.sim_clock_start, r.sim_clock_current - interval '1 minute', interval '1 minute') gs),
  pm AS MATERIALIZED (
    SELECT m.m,
           (SELECT count(*) FROM w WHERE w.w1 IS NOT NULL AND w.w0 <= m.m AND w.w1 > m.m) AS waiters,
           (SELECT count(*) FROM cr c WHERE c.kind = 'dcfc' AND c.t0 <= m.m AND c.t1 > m.m) AS dbusy,
           (SELECT count(*) FROM cr c WHERE c.kind = 'dcfc' AND c.t80 <= m.m AND c.t1 > m.m) AS d80,
           (SELECT count(*) FROM cr c WHERE c.kind = 'dcfc' AND c.t85 <= m.m AND c.t1 > m.m) AS d85,
           (SELECT count(*) FROM cr c WHERE c.kind = 'l2' AND c.t0 <= m.m AND c.t1 > m.m) AS lbusy,
           (SELECT count(*) FROM cr c WHERE c.kind = 'l2' AND c.t80 <= m.m AND c.t1 > m.m) AS l80
      FROM mins m)
  SELECT CASE WHEN (SELECT count(*) FROM r) = 0 THEN NULL ELSE jsonb_build_object(
    'sim_run_id', p_run,
    'minutes', (SELECT count(*) FROM pm),
    'deploy_floor', (SELECT v FROM fl),
    'minutes_with_cars_waiting', (SELECT count(*) FROM pm WHERE waiters > 0),
    'mean_cars_waiting', (SELECT round(avg(waiters), 1) FROM pm),
    'max_cars_waiting', (SELECT max(waiters) FROM pm),
    'dcfc_sessions', (SELECT count(*) FROM cr WHERE kind = 'dcfc'),
    'dcfc_busy_min', (SELECT sum(dbusy) FROM pm),
    'dcfc_above_floor_min', (SELECT sum(d80) FROM pm),
    'dcfc_above_floor_while_waiting_min', (SELECT COALESCE(sum(d80) FILTER (WHERE waiters > 0), 0) FROM pm),
    'dcfc_above_85_while_waiting_min', (SELECT COALESCE(sum(d85) FILTER (WHERE waiters > 0), 0) FROM pm),
    'dcfc_mean_session_min', (SELECT round(avg(extract(epoch FROM t1 - t0) / 60.0)::numeric, 1) FROM cr WHERE kind = 'dcfc'),
    'dcfc_mean_min_above_floor', (SELECT round(avg(extract(epoch FROM t1 - t80) / 60.0)::numeric, 1)
                                    FROM cr WHERE kind = 'dcfc' AND t80 IS NOT NULL),
    'l2_sessions', (SELECT count(*) FROM cr WHERE kind = 'l2'),
    'l2_busy_min', (SELECT sum(lbusy) FROM pm),
    'l2_above_floor_while_waiting_min', (SELECT COALESCE(sum(l80) FILTER (WHERE waiters > 0), 0) FROM pm),
    'meaning', 'Charger-minutes spent on cars at or above the deploy floor (and above 85%) in minutes when at least '
               'one car was waiting for a charger (0501''s waiting visit). The crossing of each level is read from '
               'the signed SoC stream. Charger time here bought battery beyond what a car needs to deploy while a car '
               'below the floor waited for the charger: the opportunity the challenger''s Q1 names one session at a '
               'time.')
  END
$function$;

-- ── the report ──
CREATE FUNCTION public.ottoq_challenger_report(p_run uuid)
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  SELECT jsonb_build_object(
    'sim_run_id', p_run,
    'questions', COALESCE((SELECT jsonb_object_agg(q, x) FROM (
        SELECT f.question AS q, jsonb_build_object(
                 'episodes', count(*), 'open', count(*) FILTER (WHERE f.status = 'open'),
                 'confirmed', count(*) FILTER (WHERE f.grade = 'confirmed'),
                 'refuted', count(*) FILTER (WHERE f.grade = 'refuted'),
                 'inconclusive', count(*) FILTER (WHERE f.grade = 'inconclusive'),
                 'claimed_saving_min', round(COALESCE(sum((f.realized->>'saving_min')::numeric), 0), 1),
                 'first_seen', min(f.first_seen_sim), 'last_seen', max(f.last_seen_sim)) AS x
          FROM public.ottoq_challenger_findings f
         WHERE f.sim_run_id IS NOT DISTINCT FROM p_run
         GROUP BY f.question) z), '{}'::jsonb),
    'taper_tax', public.ottoq_challenger_taper_tax(p_run),
    'lever', 'Q1 has no verb in the engine (a charge cannot be ended early); its lever is the dial experiment '
             '08262943 (dcfc_target_soc_day 90 against 85, primary unmet_demand_car_hours) and, next, a queue-aware '
             'charge target. No question is a proposer yet: each earns a seat once its hit rate and grades are measured.')
$function$;

-- ── the cron body: every live operator or production run ──
CREATE FUNCTION public.ottoq_challenger_tick()
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE r record; v_out jsonb := '[]'::jsonb;
BEGIN
  FOR r IN SELECT sim_run_id FROM public.ottoq_sim_runs
            WHERE status IN ('running', 'paused') AND run_by IN ('operator_demo', 'production_live')
            ORDER BY started_at LOOP
    BEGIN
      v_out := v_out || jsonb_build_array(public.ottoq_challenger_scan(r.sim_run_id));
    EXCEPTION WHEN OTHERS THEN
      v_out := v_out || jsonb_build_array(jsonb_build_object('run', r.sim_run_id, 'error', SQLERRM));
    END;
  END LOOP;
  -- a run that ended with episodes open: close them at its last clock
  FOR r IN SELECT DISTINCT f.sim_run_id, s.sim_clock_current
             FROM public.ottoq_challenger_findings f JOIN public.ottoq_sim_runs s ON s.sim_run_id = f.sim_run_id
            WHERE f.status = 'open' AND s.status NOT IN ('running', 'paused') LOOP
    BEGIN
      PERFORM public.ottoq_challenger_close(r.sim_run_id, r.sim_clock_current + interval '1 second');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
  RETURN jsonb_build_object('scanned', jsonb_array_length(v_out), 'runs', v_out);
END
$function$;

REVOKE ALL ON FUNCTION public.ottoq_challenger_waiting(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_challenger_scan(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_challenger_close(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ottoq_challenger_tick() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_challenger_report(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_challenger_taper_tax(uuid) TO authenticated;

DO $verify$
BEGIN
  -- V1: the ledger is evidence with no foreign key, and every function is in place
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry
                  WHERE table_name = 'ottoq_challenger_findings' AND column_name = 'sim_run_id' AND class = 'evidence')
     OR EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.ottoq_challenger_findings'::regclass AND contype = 'f')
     OR to_regprocedure('public.ottoq_challenger_scan(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_challenger_close(uuid,timestamp with time zone)') IS NULL
     OR to_regprocedure('public.ottoq_challenger_taper_tax(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_challenger_report(uuid)') IS NULL
     OR to_regprocedure('public.ottoq_challenger_tick()') IS NULL THEN
    RAISE EXCEPTION '0532 V1: the ledger or a function is not as intended';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0532_the_challenger_asks_whether_the_chargers_could_do_more_while_cars_wait', false, false,
  'The challenger''s first form: an evidence ledger, a scan of live operator and production runs from its own cron job, '
  'and hindsight grading. It reads the world and writes only its ledger; nothing on the certified path changes.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back: (a) the taper tax of 6e0352a0 is the prototype's (0398 §3): 551 minutes, cars waiting in all of
--     them, a mean 34.2 and at most 58, 80 DCFC sessions, 3,980 DCFC-minutes busy, 1,576 of them above the floor and
--     863 above 85% while cars waited -- in under 3 seconds. (b) The scan's mechanics, on a day started through the
--     operator's door and ticked 2 sim-minutes at a time until the first DCFC session runs (at most 10 ticks) while the
--     dealt gate queue waits. That car is planted at 85%, above the floor, so Q1 must see it: the first scan writes it as
--     an open episode naming that car, with its evidence and claim; after one more tick a second scan extends the
--     episode rather than opening another, or closes and grades it if the queue or the session ended; the run is
--     stopped and the next tick of the challenger closes and grades every episode left open. A tick of this world costs
--     about 6.6 s (0398 §1), so V3 plants rather than waits.
DO $v3$
DECLARE
  v_msg text; v_t0 timestamptz; v_ms numeric; v_tax jsonb; v_run uuid; v_scan1 jsonb; v_scan2 jsonb; v_car uuid;
  v_open int; v_rows int; v_graded int; f record; v_ticks int := 0;
BEGIN
  BEGIN
    v_t0 := clock_timestamp();
    v_tax := public.ottoq_challenger_taper_tax('6e0352a0-243d-4429-9c4d-70debc73f902');
    v_ms := extract(epoch FROM clock_timestamp() - v_t0) * 1000;
    IF (v_tax->>'minutes')::int <> 551 OR (v_tax->>'minutes_with_cars_waiting')::int <> 551
       OR (v_tax->>'mean_cars_waiting')::numeric <> 34.2 OR (v_tax->>'max_cars_waiting')::int <> 58
       OR (v_tax->>'dcfc_sessions')::int <> 80 OR (v_tax->>'dcfc_busy_min')::int <> 3980
       OR (v_tax->>'dcfc_above_floor_while_waiting_min')::int <> 1576
       OR (v_tax->>'dcfc_above_85_while_waiting_min')::int <> 863 OR v_ms > 3000 THEN
      RAISE EXCEPTION '0532 V3 FAILED (a): 6e0352a0 read % in % ms', v_tax - 'meaning', round(v_ms);
    END IF;

    PERFORM set_config('ottoq.sim_run_id', '', true);
    v_run := public.ottoq_sim_run_scenario('busy_day', 532532, 'ab_harness', '2026-09-01 13:00:00+00');
    PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
    -- 2 sim-minutes a tick, until the first DCFC session runs (the dealt gate queue takes a few ticks to plug)
    UPDATE public.ottoq_sim_runs SET time_scale = 4, tick_interval_seconds = 30 WHERE sim_run_id = v_run;
    FOR i IN 1..10 LOOP
      PERFORM public.ottoq_sim_advance_tick(v_run);
      v_ticks := i;                                   -- a FOR loop's variable is the loop's own, gone after it
      SELECT os.vehicle_id INTO v_car
        FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id
       WHERE os.sim_run_id = v_run AND os.status = 'active' AND st.stall_type = 'dcfc'
       ORDER BY os.vehicle_id LIMIT 1;
      EXIT WHEN v_car IS NOT NULL;
    END LOOP;
    IF v_car IS NULL THEN
      RAISE EXCEPTION '0532 V3 FAILED (b): no DCFC session was running after % ticks of 2 sim-minutes', v_ticks;
    END IF;
    UPDATE public.vehicles SET current_soc = 85 WHERE id = v_car;     -- the plant
    v_scan1 := public.ottoq_challenger_scan(v_run);
    IF COALESCE((v_scan1->>'cars_waiting')::int, 0) = 0 OR COALESCE((v_scan1->>'charging_above_floor')::int, 0) = 0
       OR NOT EXISTS (SELECT 1 FROM public.ottoq_challenger_findings
                       WHERE sim_run_id = v_run AND question = 'charging_above_floor_while_cars_wait' AND status = 'open'
                         AND (evidence->>'car_id')::uuid = v_car AND (evidence->>'car_soc')::numeric = 85
                         AND counterfactual ? 'beneficiary_id' AND (evidence->>'cars_waiting')::int > 0) THEN
      RAISE EXCEPTION '0532 V3 FAILED (b): the first scan saw % and wrote no open Q1 episode for the planted car', v_scan1;
    END IF;
    PERFORM public.ottoq_sim_advance_tick(v_run);
    v_scan2 := public.ottoq_challenger_scan(v_run);
    SELECT * INTO f FROM public.ottoq_challenger_findings
     WHERE sim_run_id = v_run AND question = 'charging_above_floor_while_cars_wait' AND (evidence->>'car_id')::uuid = v_car;
    IF NOT ((f.status = 'open' AND f.scans_seen = 2)
            OR (f.status = 'closed' AND f.grade IS NOT NULL AND f.realized ? 'saving_min')) THEN
      RAISE EXCEPTION '0532 V3 FAILED (b): after the second scan the planted episode reads status %, scans %, grade %',
        f.status, f.scans_seen, f.grade;
    END IF;
    IF (SELECT count(*) FROM public.ottoq_challenger_findings
         WHERE sim_run_id = v_run AND question = 'charging_above_floor_while_cars_wait'
           AND (evidence->>'car_id')::uuid = v_car) <> 1 THEN
      RAISE EXCEPTION '0532 V3 FAILED (b): the planted session was written as more than one episode';
    END IF;
    PERFORM public.ottoq_sim_stop_and_reset(v_run, '0532_v3');
    PERFORM public.ottoq_challenger_tick();
    SELECT count(*), count(*) FILTER (WHERE grade IS NOT NULL), count(*) FILTER (WHERE status = 'open')
      INTO v_rows, v_graded, v_open FROM public.ottoq_challenger_findings WHERE sim_run_id = v_run;
    IF v_open <> 0 OR v_graded <> v_rows THEN
      RAISE EXCEPTION '0532 V3 FAILED (b): after the stop % of % episodes graded, % still open', v_graded, v_rows, v_open;
    END IF;
    RAISE EXCEPTION '0532 V3 PASSED: 6e0352a0 taper tax % DCFC-minutes above the floor while cars waited (% above 85), in % ms; at % sim (tick %) % cars waiting and % DCFC above the floor (one planted); the planted episode % after the second scan (scans %); after the stop % of % episodes graded (%)',
      v_tax->'dcfc_above_floor_while_waiting_min', v_tax->'dcfc_above_85_while_waiting_min', round(v_ms),
      to_char((v_scan1->>'sim_clock')::timestamptz AT TIME ZONE 'America/Chicago', 'HH24:MI'), v_ticks,
      v_scan1->'cars_waiting', v_scan1->'charging_above_floor', f.status, f.scans_seen, v_graded, v_rows,
      (SELECT jsonb_object_agg(question || ':' || grade, n) FROM (SELECT question, grade, count(*) AS n
         FROM public.ottoq_challenger_findings WHERE sim_run_id = v_run GROUP BY 1, 2) z);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0532 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0532 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- The scan runs every minute beside the funnel, never inside it.
SELECT cron.schedule('challenger_scan', '* * * * *', 'SELECT public.ottoq_challenger_tick();');

-- Rollback: SELECT cron.unschedule('challenger_scan'); DROP FUNCTION public.ottoq_challenger_tick(),
--   public.ottoq_challenger_report(uuid), public.ottoq_challenger_taper_tax(uuid), public.ottoq_challenger_scan(uuid),
--   public.ottoq_challenger_close(uuid, timestamptz), public.ottoq_challenger_waiting(uuid, timestamptz);
--   DELETE FROM public.ottoq_run_scope_registry WHERE table_name = 'ottoq_challenger_findings';
--   DROP TABLE public.ottoq_challenger_findings.
COMMIT;
