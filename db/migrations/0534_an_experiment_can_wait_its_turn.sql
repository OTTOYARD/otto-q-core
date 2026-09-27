-- migration-version: PENDING
-- migration-name:    an_experiment_can_wait_its_turn
--
-- 0534  **The dial runner can be told that an experiment waits, and tonight the energy replication waits so the two
--       busy-day experiments each reach their first look.**
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The runner pairs the active experiment with the fewest pairs since the dial floor, oldest first, one pair per call,
--   every ten minutes, inside the night window (06:00-10:41 UTC, 1:00-5:41 AM CT). Three experiments are active, and
--   0531 and 0533 each restarted all three:
--     - `82c5568b`, the energy replication, needs about 10 minutes a pair;
--     - `143a11c7`, G240's calibrated charge window, about 16-20;
--     - `08262943`, the charge target (G257, G258), about 20.
--   A 20-minute pair holds two of the runner's ten-minute slots, and the window holds about 28. Round-robin over three
--   gives each about five pairs, and the first look needs six counted pairs. So the night would end with no first look
--   at all. With the replication deferred one night, the two busy-day experiments alternate and each gets seven or
--   eight.
--   The replication is the one to wait. Its incumbent already is its treatment, so a win is recorded and never
--   promoted (0480's own hypothesis). The other two are unanswered:
--     - the charge target asks whether a daytime DCFC stopped at 85 meets more of the day's demand. The challenger's
--       first finding (G257: 40% of DCFC time went to cars above the deploy floor while cars waited) is what raised it;
--     - G240 asks whether a calibrated booking window stops the charge outlasting its booking.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) `ottoq_dial_experiments.run_after`: NULL, or the moment before which the runner will not pair the experiment.
--       A deferred experiment keeps its status, its pairs and its place in the queue; nothing about its verdict changes.
--       `ottoq_dial_pair` by hand still runs it, as a deliberate act.
--   (b) `ottoq_dial_next_experiment(floor)`: the runner's choice, as its own function so it can be tested without
--       running a pair. It is the same order as before (fewest pairs since the floor, then oldest), among the active
--       experiments that are due.
--   (c) The runner takes its experiment from (b). When nothing is due, it says how many experiments wait.
--   (d) `82c5568b` waits until 2026-09-29 00:00 UTC (7:00 PM CT on 9/28), after tonight's window.
--
-- ══ §3 forces_recert FALSE; forces_dial_restart FALSE ═════════════════════════════════════════════════════════════════
--
--   Nothing here is on a tick path. It changes which experiment a night's pairs go to, never what a pair runs.

BEGIN;

-- ── P0: no pair in flight (0513's one probe): this file replaces the runner ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0534 P0: a pair, the recert runner or a dial pair is running right now';
  END IF;
END $inflight$;

-- ── P2: what this file relies on, as measured ──
DO $premises$
DECLARE v_def text;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'ottoq_dial_experiments' AND column_name = 'run_after') THEN
    RAISE EXCEPTION '0534 P2: the experiments already carry run_after';
  END IF;
  IF to_regprocedure('public.ottoq_dial_next_experiment(timestamp with time zone)') IS NOT NULL THEN
    RAISE EXCEPTION '0534 P2: the selector already exists';
  END IF;
  v_def := pg_get_functiondef('public.ottoq_dial_experiment_runner()'::regprocedure);
  IF position(E'  SELECT e.* INTO x FROM public.ottoq_dial_experiments e\n   WHERE e.status = ''active''\n' IN v_def) = 0 THEN
    RAISE EXCEPTION '0534 P2: the runner does not choose its experiment as measured';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_dial_experiments
                  WHERE experiment_id = '82c5568b-d661-4469-84d5-5799a5be1f1d' AND status = 'active'
                    AND param_key = 'energy_reserve_shave') THEN
    RAISE EXCEPTION '0534 P2: the energy replication is not the active experiment measured';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0534_pre', 'function', 'public', 'ottoq_dial_experiment_runner',
       pg_get_functiondef('public.ottoq_dial_experiment_runner()'::regprocedure),
       md5(pg_get_functiondef('public.ottoq_dial_experiment_runner()'::regprocedure));

-- ── (a) run_after ──
ALTER TABLE public.ottoq_dial_experiments ADD COLUMN run_after timestamp with time zone;

COMMENT ON COLUMN public.ottoq_dial_experiments.run_after IS
  '0534. NULL, or the moment before which ottoq_dial_experiment_runner will not pair this experiment. A deferred '
  'experiment keeps its status, its pairs and its place in the queue; ottoq_dial_pair by hand still runs it.';

-- ── (b) the runner's choice, testable on its own ──
CREATE FUNCTION public.ottoq_dial_next_experiment(p_floor timestamp with time zone)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'extensions'
AS $function$
  /* 0534: the experiment the runner pairs next. The order is 0439's, with 0523's floor: the active experiment with the
     fewest pairs since the dial floor, then the oldest. Among those that are due: run_after NULL or passed. */
  SELECT e.experiment_id
    FROM public.ottoq_dial_experiments e
   WHERE e.status = 'active'
     AND (e.run_after IS NULL OR e.run_after <= now())
   ORDER BY (SELECT count(*) FROM public.ottoq_dial_pair_ledger l
              WHERE l.experiment_id = e.experiment_id AND l.ran_at >= p_floor), e.created_at, e.experiment_id
   LIMIT 1
$function$;

COMMENT ON FUNCTION public.ottoq_dial_next_experiment(timestamp with time zone) IS
  '0534. The experiment ottoq_dial_experiment_runner pairs next: fewest pairs since the dial floor, then oldest, among '
  'the active experiments whose run_after is NULL or has passed.';

-- ── (c) the runner takes its experiment from (b) ──
DO $runner$
DECLARE
  v_def text; n int;
  v_old text := $o$  SELECT e.* INTO x FROM public.ottoq_dial_experiments e
   WHERE e.status = 'active'
   ORDER BY (SELECT count(*) FROM public.ottoq_dial_pair_ledger l
              WHERE l.experiment_id = e.experiment_id AND l.ran_at >= v_floor), e.created_at, e.experiment_id
   LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ran', false, 'why', 'no active experiment'); END IF;$o$;
  v_new text := $n$  -- 0534: the choice is ottoq_dial_next_experiment's (the same order, among the experiments that are due)
  SELECT e.* INTO x FROM public.ottoq_dial_experiments e
   WHERE e.experiment_id = public.ottoq_dial_next_experiment(v_floor);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ran', false, 'why',
             format('no active experiment is due (%s waiting on run_after)',
                    (SELECT count(*) FROM public.ottoq_dial_experiments w WHERE w.status = 'active' AND w.run_after > now())));
  END IF;$n$;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_dial_experiment_runner()'::regprocedure);
  n := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  IF n <> 1 THEN RAISE EXCEPTION '0534 (c): the runner''s choice matched % times, not once', n; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $runner$;

-- ── (d) the energy replication waits one night ──
UPDATE public.ottoq_dial_experiments
   SET run_after = '2026-09-29 00:00:00+00'
 WHERE experiment_id = '82c5568b-d661-4469-84d5-5799a5be1f1d' AND status = 'active';

DO $verify$
DECLARE v_def text;
BEGIN
  -- V1 (read with comments stripped)
  v_def := regexp_replace(pg_get_functiondef('public.ottoq_dial_experiment_runner()'::regprocedure), '--[^\n]*', '', 'g');
  IF position('WHERE e.experiment_id = public.ottoq_dial_next_experiment(v_floor);' IN v_def) = 0
     OR v_def ~ 'ORDER BY \(SELECT count\(\*\) FROM public\.ottoq_dial_pair_ledger' THEN
    RAISE EXCEPTION '0534 V1: the runner does not take its experiment from the selector';
  END IF;
  IF (SELECT run_after FROM public.ottoq_dial_experiments WHERE experiment_id = '82c5568b-d661-4469-84d5-5799a5be1f1d')
     IS DISTINCT FROM '2026-09-29 00:00:00+00'::timestamptz THEN
    RAISE EXCEPTION '0534 V1: the energy replication does not wait as intended';
  END IF;
END $verify$;

-- This file's own classification goes in before V3 (0523's rule).
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0534_an_experiment_can_wait_its_turn', false, false,
  'ottoq_dial_experiments.run_after and ottoq_dial_next_experiment: the dial runner pairs only experiments that are due, '
  'in the same order as before. No tick path and no arm changes; the energy replication 82c5568b waits one night.', now())
ON CONFLICT (name) DO NOTHING;

-- V3, rolled back.
--   Two planted experiments, older than every real one and with no pairs, so they are first in the order:
--     - B older, deferred to tomorrow; A newer, due;
--     - the selector takes A while B waits, and B once its time has passed;
--     - with both deferred, the selector takes a real experiment, never the energy replication;
--     - with every active experiment deferred, it takes none.
DO $v3$
DECLARE
  v_msg text; v_a uuid; v_b uuid; v_floor timestamptz := public.ottoq_dial_pair_floor();
  s1 uuid; s2 uuid; s3 uuid; s4 uuid;
BEGIN
  BEGIN
    INSERT INTO public.ottoq_dial_experiments (created_at, created_by, depot_id, param_key, control_value, treatment_value,
                                               scenario, ticks, sim_start, primary_metric, primary_better, hypothesis,
                                               sim_min_per_tick, run_after)
    VALUES ('2020-01-01 00:00:00+00', '0534_v3', '11111111-1111-1111-1111-111111111111', 'l2_target_soc', 100, 95, 'busy_day',
            90, '2026-09-01 13:00:00+00', 'unmet_demand_car_hours', 'lower', '0534 V3 plant A', 6, NULL)
    RETURNING experiment_id INTO v_a;
    INSERT INTO public.ottoq_dial_experiments (created_at, created_by, depot_id, param_key, control_value, treatment_value,
                                               scenario, ticks, sim_start, primary_metric, primary_better, hypothesis,
                                               sim_min_per_tick, run_after)
    VALUES ('2019-01-01 00:00:00+00', '0534_v3', '11111111-1111-1111-1111-111111111111', 'dcfc_target_soc_night', 100, 95,
            'busy_day', 90, '2026-09-01 13:00:00+00', 'unmet_demand_car_hours', 'lower', '0534 V3 plant B', 6,
            now() + interval '1 day')
    RETURNING experiment_id INTO v_b;
    s1 := public.ottoq_dial_next_experiment(v_floor);
    UPDATE public.ottoq_dial_experiments SET run_after = now() - interval '1 minute' WHERE experiment_id = v_b;
    s2 := public.ottoq_dial_next_experiment(v_floor);
    UPDATE public.ottoq_dial_experiments SET run_after = now() + interval '1 day' WHERE experiment_id IN (v_a, v_b);
    s3 := public.ottoq_dial_next_experiment(v_floor);
    UPDATE public.ottoq_dial_experiments SET run_after = now() + interval '1 day' WHERE status = 'active';
    s4 := public.ottoq_dial_next_experiment(v_floor);
    IF s1 IS DISTINCT FROM v_a OR s2 IS DISTINCT FROM v_b OR s3 IS NULL OR s3 IN (v_a, v_b)
       OR s3 = '82c5568b-d661-4469-84d5-5799a5be1f1d'::uuid OR s4 IS NOT NULL THEN
      RAISE EXCEPTION '0534 V3 FAILED: took % (A due, B waiting; want A), % (B due; want B), % (both waiting; want a real one, not the replication), % (all waiting; want none)',
        s1, s2, s3, s4;
    END IF;
    RAISE EXCEPTION '0534 V3 PASSED: the due plant while the older one waited, the older one once due, the real experiment % with both plants waiting, and none with every experiment waiting', s3;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  IF v_msg IS NULL OR v_msg NOT LIKE '0534 V3 PASSED%' THEN RAISE EXCEPTION '%', COALESCE(v_msg, '0534 V3: no verdict'); END IF;
  RAISE NOTICE '%', v_msg;
END $v3$;

-- Rollback: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0534_pre'; then
--   DROP FUNCTION public.ottoq_dial_next_experiment(timestamp with time zone);
--   ALTER TABLE public.ottoq_dial_experiments DROP COLUMN run_after.
COMMIT;
