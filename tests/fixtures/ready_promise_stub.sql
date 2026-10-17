-- tests/fixtures/ready_promise_stub.sql -- what db/migrations/0736 reads beyond the charge line, for
-- tests/test_ready_promise_sql.py. Loaded AFTER the miniature depot of tests/test_agent_charge_order_sql.py has been taken
-- through 0642 (tests/test_charge_order_floor_sql.py), whose charge-line state, simulator, charge clock and hash draws are
-- the live bodies (md5 asserted by the test).
-- GENERATED from the live catalog on 2026-10-17: the two sweep tables by format_type; the two sweeps 0736's (g) and V4
-- read, with answer_normal's dcfc10 cell, as live; public.ottoq_sim_advance_tick as 0735 left it, which is the
-- ottoq_schema_snapshots row labelled 0736_pre (pg_get_functiondef md5 831d70ee, prosrc md5 34173eb6, the body 0736's P1
-- requires). The tick is only ever patched and read here, never called: its world, decide and teardown are not in the stub.
SET client_min_messages = warning;

CREATE TABLE public.ottoq_throughput_sweeps (sweep_id uuid DEFAULT gen_random_uuid(), sweep_code text, title text, depot_id uuid, scenario text, sim_start timestamp with time zone, ticks integer, sim_min_per_tick numeric, seeds bigint[], replicates integer DEFAULT 1, priority integer DEFAULT 100, arm_budget_s integer, status text DEFAULT 'active'::text, run_after timestamp with time zone, notes text, created_by text DEFAULT 'research_wing'::text, created_at timestamp with time zone DEFAULT now(), concluded_at timestamp with time zone, fleet_code text);
CREATE TABLE public.ottoq_throughput_sweep_cells (cell_id uuid DEFAULT gen_random_uuid(), sweep_id uuid, cell_code text, ord integer, seat text, buildout_code text, fixed_params jsonb DEFAULT '{}'::jsonb, control_cell_code text);

INSERT INTO public.ottoq_throughput_sweeps (sweep_id, sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick,
                                            seeds, replicates, priority, arm_budget_s, status, created_at)
VALUES ('607a5b07-252f-45bd-978b-49f2f956a61c', 'value_2026_09_30',
        'Value, night 2: OTTO-Q against first-come-first-served, with OTTO-Q''s energy planning on and off, 24-hour days at 10 and 20 robotic fast chargers',
        '11111111-1111-1111-1111-111111111111', 'busy_day', '2026-09-01 11:00:00+00', 288, 5,
        ARRAY[686364201590009433, 305838298283560562, 1071807412374370855]::bigint[], 0, 50, NULL, 'active',
        '2026-09-30 11:54:52.208019+00'),
       ('71b3c30d-4987-4902-a727-79a63588911f', 'answer_normal_2026_10_17',
        'A car answers a command in the tick it is given: 10, 20 and 40 fast chargers over the normal day',
        '11111111-1111-1111-1111-111111111111', 'normal_day', '2026-09-01 11:00:00+00', 144, 5,
        ARRAY[686364201590009433]::bigint[], 0, 15, 5400, 'active', '2026-10-17 16:16:41.900663+00');
INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
VALUES ('71b3c30d-4987-4902-a727-79a63588911f', 'dcfc10.otto_q.answer_in_tick', 1, 'otto_q', 'dcfc10',
        '{"twin_answer_in_tick": 1, "deploy_peak_fraction": 0.9}'),
       ('71b3c30d-4987-4902-a727-79a63588911f', 'dcfc20.otto_q.answer_in_tick', 2, 'otto_q', 'dcfc20',
        '{"twin_answer_in_tick": 1, "deploy_peak_fraction": 0.9}'),
       ('71b3c30d-4987-4902-a727-79a63588911f', 'dcfc40.otto_q.answer_in_tick', 3, 'otto_q', 'dcfc40',
        '{"twin_answer_in_tick": 1, "deploy_peak_fraction": 0.9}');

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0735_a_car_answers_a_command_in_the_tick_it_is_given', false, false, 'stub: 0735 applied', now());

CREATE OR REPLACE FUNCTION public.ottoq_sim_advance_tick(p_sim_run_id uuid)
 RETURNS TABLE(out_sim_clock_after timestamp with time zone, out_tick_minutes numeric, out_dispatched integer, out_telemetry_emitted integer, out_charge_assigned integer, out_charge_advanced integer, out_completed boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE w RECORD; d RECORD;
BEGIN
  -- 0196: transaction-local flags are TICK-local by contract. Under pg_cron a tick
  -- is its own transaction and these die with it; under the certification pair
  -- both arms and every tick share one transaction, so a grant stamped in arm A
  -- authorised stall vacates in arm B (db/checks/0111). Clear them here so every
  -- driver sees the same world at every tick boundary.
  PERFORM set_config('ottoq.reassign_ok', '', true);
  PERFORM set_config('ottoq.skip_wash_bump', '', true); /* 0196 */
  -- 0654: with twin_operator_door on, the twin's operators answer the directives the last tick issued before the world
  -- moves. Here (a pair, a sweep, a jump) that is the caller's transaction; the metronome gives it its own.
  IF ottoq_policy_get(p_sim_run_id, 'twin_operator_door', 0) >= 1 THEN
    PERFORM twin.ottoq_twin_operator_step(p_sim_run_id);
  END IF;
  SELECT * INTO w FROM ottoq_sim_advance_tick_world(p_sim_run_id);
  IF w.out_completed AND w.out_sim_clock_after IS NULL THEN
    -- 0102: a run that completes naturally gets the SAME teardown as a stopped one.
    -- Finalized HERE -- after the world function has returned and every phase loop
    -- closed -- because mid-world teardown (0101's seam) trips on in-flight state.
    -- GUC pinned per 0092 so teardown events carry this run.
    BEGIN
      PERFORM set_config('ottoq.sim_run_id', p_sim_run_id::text, true);
      PERFORM ottoq_sim_release_depot(p_sim_run_id, 'sim_clock_end_reached');
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'advance_tick completion teardown FAILED: % %', SQLSTATE, SQLERRM;
    END;
    out_completed:=TRUE; RETURN NEXT; RETURN;
  END IF;
  -- 0360 (G76): release reservations whose holder can no longer use them,
  -- and those expired on the SIM clock, BEFORE this tick decides. The depot
  -- was measured at 155 of 158 stalls reserved and 21 occupied, so every
  -- proposer saw ~1% of a site that was 87% free. Never allowed to abort the
  -- tick: the function returns ok:false rather than raising, and this handler
  -- is the second line of that same defence.
  BEGIN
    PERFORM public.ottoq_release_unusable_reservations(p_sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0360 release_unusable_reservations: % %', SQLSTATE, SQLERRM;
  END;
  SELECT * INTO d FROM ottoq_sim_decide_and_dispatch(p_sim_run_id);
  -- 0735 (G449, G450): with twin_answer_in_tick on, the twin carries out in this tick the commands this tick's decide
  -- gave, and plugs in a car seated on a charger; off, they wait for the next tick's world step, as they always did.
  IF NOT COALESCE(w.out_completed, false) AND w.out_sim_clock_after IS NOT NULL
     AND COALESCE(ottoq_policy_get(p_sim_run_id, 'twin_answer_in_tick', 0), 0) >= 1 THEN
    PERFORM twin.ottoq_sim_answer_in_tick(p_sim_run_id, w.out_sim_clock_after);
  END IF;
  out_sim_clock_after:=w.out_sim_clock_after; out_tick_minutes:=w.out_tick_minutes;
  out_dispatched:=d.out_dispatched; out_telemetry_emitted:=w.out_telemetry_emitted;
  out_charge_assigned:=d.out_charge_assigned; out_charge_advanced:=w.out_charge_advanced;
  out_completed:=w.out_completed;
  -- 0103: the LIVE completion seam. advance_tick_world writes status='completed'
  -- mid-function and still returns a non-NULL clock, so the early branch above
  -- never fires; decide_and_dispatch has also already run (and may have issued
  -- commands post-completion -- the finalizer expires them). Finalize HERE, after
  -- the full tick. GUC pinned per 0092 so teardown events carry this run.
  IF w.out_completed THEN
    BEGIN
      PERFORM set_config('ottoq.sim_run_id', p_sim_run_id::text, true);
      PERFORM ottoq_sim_release_depot(p_sim_run_id, 'sim_clock_end_reached');
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'advance_tick completion teardown FAILED: % %', SQLSTATE, SQLERRM;
    END;
  END IF;
  RETURN NEXT;
END;
$function$;
-- the tick's grants as live (proacl {postgres=X/postgres,service_role=X/postgres}): a browser role cannot call it
REVOKE ALL ON FUNCTION public.ottoq_sim_advance_tick(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_sim_advance_tick(uuid) TO service_role;
