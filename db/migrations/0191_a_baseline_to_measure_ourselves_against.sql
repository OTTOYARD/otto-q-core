-- =====================================================================
-- 0191  A baseline to measure ourselves against
-- =====================================================================
-- forces_recert = FALSE. Read-only function; touches no engine state and
-- no canon. Nothing in the decide path calls it.
--
-- WHY THIS EXISTS
-- ---------------------------------------------------------------------
-- ottoq_ab_runs holds 68 runs. ottoq_run_archives holds 762. EVERY ONE
-- of them records policy = 'otto_q'. There is no baseline. We have never
-- run anything against ourselves.
--
-- CLAUDE.md C5 says "ottoq_ab_runs already pairs OTTO-Q vs FIFO vs greedy
-- under common random numbers, keyed by seed - wrap, don't rebuild."
-- THAT IS NOT TRUE. The column exists; no other value was ever written.
-- Same class as the stale row counts and the "52 rules" phrasing: a brief
-- describing an intention as though it were a fact.
--
-- "Outperform everyone on industry KPIs" is a claim about a DIFFERENCE.
-- We currently have nothing to difference against, so the claim cannot be
-- made at all - in either direction.
--
-- WHY A COUNTERFACTUAL AND NOT A SECOND POLICY
-- ---------------------------------------------------------------------
-- The honest alternative is a real second policy inside the decide path.
-- public.ottoq_decide_tick is 82,688 characters. Branching it would touch
-- the engine, force recertification of all six columns, and risk the
-- determinism property thirteen rounds were spent establishing - to
-- produce a number we can get read-only.
--
-- So: replay a completed run's OWN demand against a naive depot and score
-- it with the same clock. No engine change, no recert, and it isolates
-- exactly the thing in question - the assignment decision.
--
-- THE RULES, chosen so this is not a strawman
-- ---------------------------------------------------------------------
-- The baseline gets every advantage that is not scheduling skill:
--   - the SAME stall inventory the run actually used, by type
--   - the SAME service durations the run actually observed, per leg
--     (FIFO is not punished with slower service)
--   - the SAME readiness times (planned_start_sim)
--   - work taken strictly in ready-time order, assigned to the
--     earliest-free stall of a compatible type
--
-- The ONLY difference is order and choice: first-come-first-served into
-- the first free compatible stall, versus whatever OTTO-Q decided. If
-- OTTO-Q cannot beat that, we need to know, and this is built to be able
-- to say so.
--
-- WHAT IT DOES NOT MODEL, stated so no one over-reads the number
-- ---------------------------------------------------------------------
-- It replays a fixed demand stream. A real FIFO depot would make
-- different early choices, which would change what arrived later. This
-- measures scheduling quality on an identical day; it is not a full
-- closed-loop simulation of a FIFO world.
--
-- It also only counts stall-requiring work. Legs needing no stall
-- (interior_tidy, sensor_clean, remote_diagnostics, item_retrieval)
-- contend for nothing and are excluded from both sides.
--
-- Read the result as: "on the same day, with the same fleet, the same
-- stalls and the same service times, ordering the work naively would have
-- produced X." That is a real and defensible comparison, and it is the
-- floor the product has to clear.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.ottoq_baseline_fifo(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 -- VOLATILE, not STABLE: the assignment loop needs temp tables, which
 -- Postgres forbids in a non-volatile function. It still writes NOTHING
 -- persistent - the two temp tables are ON COMMIT DROP and no permanent
 -- row is touched. VOLATILE here means "the planner may not cache me",
 -- not "I have side effects".
 VOLATILE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run        record;
  w            record;
  v_stall      record;
  v_start      timestamptz;
  v_end        timestamptz;
  v_waits      numeric[] := ARRAY[]::numeric[];
  v_turns      int := 0;
  v_unserved   int := 0;
  v_makespan   timestamptz;
  v_actual     jsonb;
BEGIN
  SELECT sim_run_id, sim_clock_start, sim_clock_current INTO v_run
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_run.sim_run_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'run not found');
  END IF;

  -- The demand: stall-requiring work the run actually performed, with the
  -- duration it actually took and the time it was actually ready.
  CREATE TEMP TABLE _work ON COMMIT DROP AS
  SELECT l.leg_id, l.vehicle_id, s.stall_type,
         l.planned_start_sim AS ready_at,
         (l.actual_end_sim - l.actual_start_sim) AS dur
    FROM ottoq_itinerary_legs l
    JOIN stalls s ON s.id = l.to_stall_id
   WHERE l.sim_run_id = p_sim_run_id
     AND l.status = 'done'
     AND l.actual_start_sim IS NOT NULL
     AND l.actual_end_sim   IS NOT NULL
     AND l.planned_start_sim IS NOT NULL
     AND l.leg_type <> ALL (ARRAY['taxi','stage','depart']);

  -- The resources: the stall inventory this run actually had available,
  -- by type. Same stalls, same counts - the baseline is not starved.
  CREATE TEMP TABLE _stall ON COMMIT DROP AS
  SELECT s.id AS stall_id, s.stall_type, v_run.sim_clock_start AS free_at
    FROM stalls s
   WHERE s.id IN (SELECT DISTINCT to_stall_id FROM ottoq_itinerary_legs
                   WHERE sim_run_id = p_sim_run_id AND to_stall_id IS NOT NULL);

  -- FIFO: strictly in ready order, into the earliest-free compatible stall.
  FOR w IN SELECT * FROM _work ORDER BY ready_at, vehicle_id, leg_id LOOP
    SELECT * INTO v_stall FROM _stall
     WHERE stall_type = w.stall_type
     ORDER BY free_at, stall_id LIMIT 1;

    IF v_stall.stall_id IS NULL THEN
      v_unserved := v_unserved + 1;   -- no stall of that type existed at all
      CONTINUE;
    END IF;

    v_start := GREATEST(w.ready_at, v_stall.free_at);
    v_end   := v_start + w.dur;

    -- Work that could not start before the run's horizon is not counted as
    -- a turn - the same rule 0182/0188 apply to our own numbers.
    IF v_start >= v_run.sim_clock_current THEN
      v_unserved := v_unserved + 1;
      CONTINUE;
    END IF;

    UPDATE _stall SET free_at = v_end WHERE stall_id = v_stall.stall_id;
    v_turns := v_turns + 1;
    v_waits := v_waits || (EXTRACT(epoch FROM v_start - w.ready_at)/60.0)::numeric;
    IF v_makespan IS NULL OR v_end > v_makespan THEN v_makespan := v_end; END IF;
  END LOOP;

  -- What OTTO-Q actually achieved on the identical demand.
  SELECT jsonb_build_object(
      'turns_completed', count(*),
      'p95_wait_min', round(percentile_cont(0.95) WITHIN GROUP (
          ORDER BY EXTRACT(epoch FROM actual_start_sim - planned_start_sim)/60.0)::numeric, 1),
      'median_wait_min', round(percentile_cont(0.50) WITHIN GROUP (
          ORDER BY EXTRACT(epoch FROM actual_start_sim - planned_start_sim)/60.0)::numeric, 1),
      'makespan', max(actual_end_sim))
    INTO v_actual
    FROM ottoq_itinerary_legs l
    JOIN stalls s ON s.id = l.to_stall_id
   WHERE l.sim_run_id = p_sim_run_id AND l.status='done'
     AND l.actual_start_sim IS NOT NULL AND l.actual_end_sim IS NOT NULL
     AND l.planned_start_sim IS NOT NULL
     AND l.leg_type <> ALL (ARRAY['taxi','stage','depart']);

  RETURN jsonb_build_object(
    'ok', true,
    'sim_run_id', p_sim_run_id,
    'window', jsonb_build_object('from', v_run.sim_clock_start, 'to', v_run.sim_clock_current),
    'demand_legs', (SELECT count(*) FROM _work),
    'stalls_available', (SELECT count(*) FROM _stall),
    'baseline_fifo', jsonb_build_object(
       'turns_completed', v_turns,
       'unserved', v_unserved,
       'p95_wait_min', (SELECT round(percentile_cont(0.95) WITHIN GROUP (ORDER BY x)::numeric,1)
                          FROM unnest(v_waits) x),
       'median_wait_min', (SELECT round(percentile_cont(0.50) WITHIN GROUP (ORDER BY x)::numeric,1)
                          FROM unnest(v_waits) x),
       'makespan', v_makespan),
    'actual_otto_q', v_actual,
    'method', 'Counterfactual replay. Same demand, same stalls, same observed service durations, same readiness times; the only difference is that work is taken in ready-time order into the earliest-free compatible stall. Does NOT model how a FIFO depot would have changed later demand. Stall-free legs are excluded from both sides.'
  );
END;
$function$;

COMMENT ON FUNCTION public.ottoq_baseline_fifo(uuid) IS
  '0191. The baseline OTTO-Q had never been measured against - all 762 archived runs record policy=otto_q. Replays a completed run''s own stall-requiring demand under first-come-first-served into the earliest-free compatible stall, using the same inventory, the same observed durations and the same readiness times, and reports both sides. Read-only. Counterfactual, not a closed-loop FIFO simulation: it isolates scheduling quality on an identical day and does not model how different early choices would change later demand.';

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('a_baseline_to_measure_ourselves_against', false,
        'Adds public.ottoq_baseline_fifo(uuid), a read-only counterfactual baseline. Motivation: ottoq_ab_runs holds 68 runs and ottoq_run_archives 762, and EVERY row records policy=otto_q - there is no baseline and OTTO-Q has never been measured against anything. CLAUDE.md C5 asserts that ottoq_ab_runs already pairs OTTO-Q vs FIFO vs greedy under common random numbers and instructs wrap-dont-rebuild; that is false, the column exists but no other value was ever written, the same class of error as the stale Part 3 row counts and the 52-rules phrasing. Outperforming on industry KPIs is a claim about a difference and we had nothing to difference against, so the claim could not be made in either direction. Implemented as a counterfactual rather than a second engine policy because public.ottoq_decide_tick is 82,688 characters: branching it would touch the engine, force recertification of all six columns and risk the determinism property thirteen rounds established, to obtain a number available read-only. The baseline is deliberately not a strawman - it receives the same stall inventory the run used, the same observed service durations per leg, and the same readiness times, differing only in taking work in ready-time order into the earliest-free compatible stall. Stated limits carried in the function output: it replays a fixed demand stream and does not model how a FIFO depot would have changed later demand, and stall-free legs (interior_tidy, sensor_clean, remote_diagnostics, item_retrieval) contend for nothing and are excluded from both sides. Work that could not start before the run horizon is counted unserved rather than as a turn, applying the same rule 0182 and 0188 apply to our own numbers. forces_recert=false: read-only, no engine path calls it.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
