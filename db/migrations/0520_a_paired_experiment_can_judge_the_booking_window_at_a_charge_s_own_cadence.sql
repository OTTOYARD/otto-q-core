-- migration-version: 20260927081719
-- migration-name:    a_paired_experiment_can_judge_the_booking_window_at_a_charge_s_own_cadence
--
-- 0520  **G240, step 4's instrument: a designed pair can now judge the calibrated booking window, which it could not.
--       Two things stood in the way. The dial pair ran every arm at 30 sim-minutes a tick, so a charge's length was
--       read to the nearest half hour -- a 25-minute DCFC charge and a 55-minute one end on the same tick -- which
--       drowns the thing the window changes. And no arm metric said whether a charge outlasted its booking. Now an
--       experiment names its cadence, and each arm reports the share of its completed charges that outlasted the
--       booking they held, read from 0514's ledger at the moment of the stop.**
--       `db/checks/0386` §6; `db/checks/0389`.
--
-- ══ §1 WHAT WAS MISSING ════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `ottoq_dial_pair` starts both arms with `twin.ottoq_sim_start_run(..., 60, ...)`: a 30-second tick times 60, so
--       30 sim-minutes a tick (0439 chose that for the canon's own cadence, and the promoter's cells are keyed by it).
--       The window that 0516/0517 size is the difference between a charge's nominal minutes and its paced ones; at a
--       half-hour grain the arms cannot see it.
--   (2) `ottoq_dial_arm_metrics` scores the five KPIs, the shield, operations and energy. None of them is the window's
--       own measure. On the full-day operator run 4bc19d29, under the window as booked today, 60.8% of the completed
--       DCFC charges (31 of 51) and 78.6% of the L2 ones (44 of 56) outlasted their booking, by a median 20.7 and 45.7
--       minutes (`db/checks/0386` §6).
--   (3) That measure cannot be read from the calendar at the end of an arm: a booking's end moves after its charge
--       stops (on 4bc19d29, 32 of 109 completed charges' bookings no longer end where they did at the stop). 0515
--       records the booking as it stood at the stop, but only for operator and production runs.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `ottoq_dial_experiments.sim_min_per_tick` (0.5 to 30, default 30): the dial pair starts both arms at
--       `time_scale = 2 x sim_min_per_tick` (a 30-second tick, the rule `ottoq_tick_invariance_arm` states). Every
--       existing experiment keeps 30, so it keeps its meaning and its cells.
--   (2) The charge ledger's capture also records A/B-harness arms (`run_by = 'ab_harness'`). Certification arms still
--       write nothing, and the calibration's evidence reader keeps reading operator and production runs only
--       (`ottoq_charge_window_evidence` filters `run_by`), so an experiment's own charges can never fit the window it
--       is judging.
--   (3) `ottoq_dial_arm_metrics` adds `charges_completed_booked`, `charges_outlasting_booking`, `charge_outlast_pct`
--       (and by charger type), and `charge_overrun_p50_min`, over the arm's completed charges with a booking in the
--       ledger. `charge_outlast_pct`, lower is better, is the primary metric an experiment on
--       `charge_window_calibration_id` names.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   No certified path changes: the dial pair and the arm metrics are the experiment harness, and the capture returns
--   at its first lookup on a certification arm as before. No atom reads the ledger.

BEGIN;

-- ── P0: no pair in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0520 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'ottoq_dial_experiments'
                AND column_name = 'sim_min_per_tick') THEN
    RAISE EXCEPTION '0520 P2: already applied';
  END IF;
  -- the fit reads operator and production runs only, so capturing harness arms cannot reach it
  IF position('AND (l.run_by IN (''operator_demo'', ''production_live'') OR l.sim_run_id IS NULL)'
              IN pg_get_functiondef('public.ottoq_charge_window_evidence(uuid,timestamptz,numeric,integer,numeric[])'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0520 P2: the calibration''s evidence reader no longer filters the runs it learns from';
  END IF;
  -- the promoter and the verdict read the cadence of an arm from the arm, not from a constant
  IF position('sim_min_per_tick' IN pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0520 P2: the arm metrics no longer report their own cadence';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0520_pre', 'function', 'public', f.fn, pg_get_functiondef(f.oid), md5(pg_get_functiondef(f.oid))
  FROM (VALUES ('ottoq_dial_pair', 'public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure::oid),
               ('ottoq_dial_arm_metrics', 'public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure::oid),
               ('ottoq_capture_charge_duration', 'public.ottoq_capture_charge_duration()'::regprocedure::oid))
       AS f(fn, oid);

-- ── (1) an experiment names its cadence ──
ALTER TABLE public.ottoq_dial_experiments
  ADD COLUMN sim_min_per_tick numeric NOT NULL DEFAULT 30
    CONSTRAINT ottoq_dial_experiments_sim_min_per_tick_chk CHECK (sim_min_per_tick >= 0.5 AND sim_min_per_tick <= 30);
COMMENT ON COLUMN public.ottoq_dial_experiments.sim_min_per_tick IS
  '0520: sim-minutes per tick for both arms (time_scale = 2 x this, on a 30-second tick). 30 is the canon''s cadence '
  'and every experiment before 0520; a charge-window experiment needs a finer one, since a 30-minute tick reads a '
  'charge''s length to the nearest half hour.';

DO $patch_pair$
DECLARE
  v_def text; n int;
  v_old text := $o$    v_run := twin.ottoq_sim_start_run(x.scenario, x.sim_start, 60, p_seed, 'ab_harness');$o$;
  v_new text := $n$    -- 0520 (G240): the experiment's cadence, time_scale = 2 x sim-minutes per tick on a 30-second tick (30 -> 60)
    v_run := twin.ottoq_sim_start_run(x.scenario, x.sim_start, 2 * x.sim_min_per_tick, p_seed, 'ab_harness');$n$;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0520: dial pair patch matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $patch_pair$;

-- ── (2) the ledger records a harness arm's stops too ──
DO $patch_capture$
DECLARE
  v_def text;
  v_pairs text[][] := ARRAY[
    ARRAY[$o1$IF COALESCE(v_run_by, '') NOT IN ('operator_demo', 'production_live') THEN$o1$,
          $n1$-- 0520 (G240): and A/B-harness arms, so a designed pair can read whether a charge outlasted its booking as the
  -- booking stood at the stop. The calibration's evidence reader still learns from operator and production runs only.
  IF COALESCE(v_run_by, '') NOT IN ('operator_demo', 'production_live', 'ab_harness') THEN$n1$],
    ARRAY[$o2$-- a certification or A/B arm, or a run this ledger does not time$o2$,
          $n2$-- a certification arm, or a run this ledger does not time$n2$]];
  i int; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_capture_charge_duration()'::regprocedure);
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0520: capture patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch_capture$;

UPDATE public.ottoq_run_scope_registry
   SET note = note || ' 0520: also A/B-harness arms (run_by ab_harness), which ottoq_charge_window_evidence excludes.'
 WHERE table_schema = 'public' AND table_name = 'ottoq_charge_duration_ledger' AND column_name = 'sim_run_id'
   AND position('0520' IN note) = 0;

-- ── (3) the arm reports the window's own measure ──
DO $patch_metrics$
DECLARE
  v_def text;
  v_pairs text[][] := ARRAY[
    ARRAY[$o1$  v_evals bigint; v_fail bigint; v_crit bigint; v_crit_ref bigint; v_crit_unp bigint; v_dr int; v_defer bigint;$o1$,
          $n1$  v_evals bigint; v_fail bigint; v_crit bigint; v_crit_ref bigint; v_crit_unp bigint; v_dr int; v_defer bigint;
  v_bk_n int; v_bk_out int; v_bk_n_dc int; v_bk_out_dc int; v_bk_n_l2 int; v_bk_out_l2 int; v_bk_p50 numeric;   -- 0520$n1$],
    ARRAY[$o2$  SELECT * INTO v_ab FROM ottoq_ab_runs WHERE sim_run_id = p_run ORDER BY scored_at DESC LIMIT 1;$o2$,
          $n2$  SELECT * INTO v_ab FROM ottoq_ab_runs WHERE sim_run_id = p_run ORDER BY scored_at DESC LIMIT 1;
  -- 0520 (G240): the booking window's own measure. Of the arm's completed charges that held a booking, how many
  -- outlasted it -- read from 0514's ledger, which records each stop's booking as it stood at the stop. The calendar
  -- itself cannot answer this at the end of an arm: a booking's end moves after its charge stops.
  SELECT count(*), count(*) FILTER (WHERE l.ended_at > l.booked_to),
         count(*) FILTER (WHERE l.charger_type = 'dcfc'), count(*) FILTER (WHERE l.charger_type = 'dcfc' AND l.ended_at > l.booked_to),
         count(*) FILTER (WHERE l.charger_type = 'l2'),   count(*) FILTER (WHERE l.charger_type = 'l2' AND l.ended_at > l.booked_to),
         percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (l.ended_at - l.booked_to)) / 60.0)
           FILTER (WHERE l.ended_at > l.booked_to)
    INTO v_bk_n, v_bk_out, v_bk_n_dc, v_bk_out_dc, v_bk_n_l2, v_bk_out_l2, v_bk_p50
    FROM public.ottoq_charge_duration_ledger l
   WHERE l.sim_run_id = p_run AND l.stopped_reason = 'completed' AND l.booked_to IS NOT NULL;$n2$],
    ARRAY[$o3$    'ticks', r.tick_count);$o3$,
          $n3$    'ticks', r.tick_count)
    -- 0520 (G240): charges that outlasted the booking they held; lower is better
    || jsonb_build_object(
    'charges_completed_booked', v_bk_n, 'charges_outlasting_booking', v_bk_out,
    'charge_outlast_pct',      round(100.0 * v_bk_out / NULLIF(v_bk_n, 0), 2),
    'charge_outlast_pct_dcfc', round(100.0 * v_bk_out_dc / NULLIF(v_bk_n_dc, 0), 2),
    'charge_outlast_pct_l2',   round(100.0 * v_bk_out_l2 / NULLIF(v_bk_n_l2, 0), 2),
    'charge_overrun_p50_min',  round(v_bk_p50, 1));$n3$]];
  i int; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure);
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    n := (length(v_def) - length(replace(v_def, v_pairs[i][1], ''))) / length(v_pairs[i][1]);
    IF n <> 1 THEN RAISE EXCEPTION '0520: metrics patch % matched % times, not once', i, n; END IF;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
  END LOOP;
  EXECUTE v_def;
END $patch_metrics$;

DO $verify$
BEGIN
  -- V1: the cadence in the pair, the harness in the capture, the measure in the metrics; grants unchanged
  IF position('2 * x.sim_min_per_tick' IN pg_get_functiondef('public.ottoq_dial_pair(uuid,bigint,integer)'::regprocedure)) = 0
     OR position('''ab_harness'')' IN pg_get_functiondef('public.ottoq_capture_charge_duration()'::regprocedure)) = 0
     OR position('''cert_harness''' IN pg_get_functiondef('public.ottoq_capture_charge_duration()'::regprocedure)) > 0
     OR position('''charge_outlast_pct''' IN pg_get_functiondef('public.ottoq_dial_arm_metrics(uuid,uuid,numeric)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0520 V1: the patched functions are not as intended';
  END IF;
  IF has_function_privilege('anon', 'public.ottoq_dial_arm_metrics(uuid,uuid,numeric)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.ottoq_dial_pair(uuid,bigint,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '0520 V1: a harness function is callable by the browser key';
  END IF;
END $verify$;

-- V3: rolled back. (a) On the full-day operator run the arm metrics report exactly what the ledger says about it;
--     (b) a one-arm check of the cadence: a harness run started the way the pair now starts one, at 2 sim-minutes a
--     tick, advances 2 minutes a tick; (c) a charge stopped on that harness run is in the ledger with its booking,
--     and the calibration's evidence reader does not see it.
DO $v3$
DECLARE
  v_msg text; v_op uuid; v_m jsonb; v_n int; v_out int; v_run uuid; v_c0 timestamptz; v_c1 timestamptz;
  r public.ocpp_sessions%ROWTYPE; v_sess uuid; v_bk uuid; v_seen int;
BEGIN
  BEGIN
    IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN
      RAISE EXCEPTION '0520 V3 FAILED: a run is live';
    END IF;
    -- (a)
    SELECT l.sim_run_id INTO v_op FROM public.ottoq_charge_duration_ledger l
     WHERE l.run_by = 'operator_demo' AND l.capture_version = 2 AND l.booked_to IS NOT NULL
     GROUP BY 1 ORDER BY count(*) DESC LIMIT 1;
    SELECT count(*), count(*) FILTER (WHERE ended_at > booked_to) INTO v_n, v_out
      FROM public.ottoq_charge_duration_ledger WHERE sim_run_id = v_op AND stopped_reason = 'completed' AND booked_to IS NOT NULL;
    v_m := public.ottoq_dial_arm_metrics(v_op, '11111111-1111-1111-1111-111111111111', NULL);
    IF v_op IS NULL OR v_n = 0 OR (v_m->>'charges_completed_booked')::int IS DISTINCT FROM v_n
       OR (v_m->>'charges_outlasting_booking')::int IS DISTINCT FROM v_out
       OR (v_m->>'charge_outlast_pct')::numeric IS DISTINCT FROM round(100.0 * v_out / v_n, 2) THEN
      RAISE EXCEPTION '0520 V3 FAILED (a): the arm metrics disagree with the ledger on %: % of % against %', v_op, v_out, v_n, v_m;
    END IF;
    -- (b)
    v_run := twin.ottoq_sim_start_run('busy_day', '2026-09-01 13:00:00+00', 2 * 2, 424242, 'ab_harness');
    SELECT sim_clock_current INTO v_c0 FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
    PERFORM public.ottoq_sim_advance_tick(v_run);
    SELECT sim_clock_current INTO v_c1 FROM public.ottoq_sim_runs WHERE sim_run_id = v_run;
    IF v_c1 - v_c0 <> interval '2 minutes' THEN
      RAISE EXCEPTION '0520 V3 FAILED (b): a harness run at time_scale 4 advanced % a tick, not 2 minutes', v_c1 - v_c0;
    END IF;
    -- (c) a charge on that run, with a booking, stopped: captured, and invisible to the fit. Planted six hours on, past
    --     anything the one tick booked, on a copy of a real completed DCFC session so every column is one the table takes
    SELECT os.* INTO r FROM public.ocpp_sessions os JOIN public.stalls st ON st.id = os.stall_id
     WHERE os.depot_id = '11111111-1111-1111-1111-111111111111' AND os.stopped_reason = 'completed'
       AND st.stall_type::text = 'dcfc' AND os.soc_end > os.soc_start
     ORDER BY os.started_at DESC LIMIT 1;
    IF r.id IS NULL THEN RAISE EXCEPTION '0520 V3 FAILED (c): no completed DCFC session to copy'; END IF;
    v_bk := gen_random_uuid();
    INSERT INTO public.ottoq_stall_bookings (booking_id, sim_run_id, stall_id, vehicle_id, purpose, during, state, booked_by, source, booked_at_sim)
    VALUES (v_bk, v_run, r.stall_id, r.vehicle_id, 'charge_dcfc',
            tstzrange(v_c1 + interval '6 hours', v_c1 + interval '6 hours 30 minutes'), 'done', '0520_v3', '0520_v3',
            v_c1 + interval '6 hours');
    v_sess := gen_random_uuid();
    INSERT INTO public.ocpp_sessions (id, depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id,
                                      connector_id, status, started_at, soc_start, ambient_temp_c, sim_run_id)
    VALUES (v_sess, r.depot_id, r.stall_id, r.vehicle_id, r.charge_point_id, '0520-v3-' || v_sess::text, r.evse_id,
            r.connector_id, r.status, v_c1 + interval '6 hours', r.soc_start, r.ambient_temp_c, v_run);
    UPDATE public.ocpp_sessions SET ended_at = v_c1 + interval '6 hours 42 minutes', soc_end = r.soc_end,
           stopped_reason = 'completed', energy_delivered_kwh = r.energy_delivered_kwh
     WHERE id = v_sess;
    SELECT count(*) INTO v_seen FROM public.ottoq_charge_duration_ledger l
     WHERE l.session_id = v_sess AND l.run_by = 'ab_harness' AND l.booking_id = v_bk
       AND l.booked_to = v_c1 + interval '6 hours 30 minutes';
    IF v_seen <> 1 THEN RAISE EXCEPTION '0520 V3 FAILED (c): a harness arm''s stop was not captured with its booking'; END IF;
    SELECT count(*) INTO v_seen FROM public.ottoq_charge_window_evidence('11111111-1111-1111-1111-111111111111', NULL, 2.0, 0, '{5,15,25}') e
     WHERE e.session_id = v_sess;
    IF v_seen <> 0 THEN RAISE EXCEPTION '0520 V3 FAILED (c): the calibration''s evidence reader sees a harness arm''s charge'; END IF;
    v_m := public.ottoq_dial_arm_metrics(v_run, '11111111-1111-1111-1111-111111111111', NULL);
    IF (v_m->>'charges_completed_booked')::int IS DISTINCT FROM 1 OR (v_m->>'charge_outlast_pct')::numeric IS DISTINCT FROM 100
       OR (v_m->>'charge_overrun_p50_min')::numeric IS DISTINCT FROM 12 THEN
      RAISE EXCEPTION '0520 V3 FAILED (c): the harness arm''s metrics are not the one charge that outlasted its booking by 12 minutes: %', v_m;
    END IF;
    RAISE EXCEPTION '0520 V3 PASSED: the arm metrics match the ledger (% of % on %); a harness run at time_scale 4 moves 2 minutes a tick; a harness stop is captured with its booking and the fit cannot see it', v_out, v_n, v_op;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0520 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0520 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: restore the three functions from `0520_pre` (CREATE OR REPLACE, ACL kept), then
-- ALTER TABLE public.ottoq_dial_experiments DROP COLUMN sim_min_per_tick.

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0520_a_paired_experiment_can_judge_the_booking_window_at_a_charge_s_own_cadence', false,
  'G240: a dial experiment names its cadence (default 30, the canon''s), the charge ledger also captures A/B-harness '
  'arms (the fit still reads operator and production runs only), and the arm metrics report the share of completed '
  'charges that outlasted their booking. Harness only; no certified path changes.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
