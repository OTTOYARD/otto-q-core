-- migration-version: 20261017174210
-- migration-name:    a_promise_on_the_busy_day
--
-- 0740  **A promise on the busy day.** The depot as built over the busy day, as arm 82 ran it, with 0736's recorder on,
--       so 0739's promise is graded on the day the bays back up. Research wing, rule 10: it measures, and a result is a
--       recommendation.
--
-- ══ §1 WHY (G452) ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The promise arm queued by 0736 runs the normal day, where the bays keep up and 0739 agrees with 0736 (the after-charge
--   median 33-43 minutes against 20-70 taken). 0739 changes the promise where they back up: on arm 82 (busy day, dcfc10,
--   seed 1) the cars that had finished said 35 minutes after the charge at hour 6 while the next hour's cars took 110,
--   and at hour 10 15 of the next 17 cars were never ready before the run ended. So the busy day is the grade that says
--   whether an owner can believe the promise when it matters.
--
-- ══ §2 WHAT THIS ADDS (rows only; no engine change) ═══════════════════════════════════════════════════════════════════
--
--   Sweep promise_busy_2026_10_17, one cell, dcfc10.otto_q.promise: arm 82's cell (dcfc10.otto_q at
--   deploy_peak_fraction 0.90, in dcfc40_2026_10_17) plus ready_promise_record 1, on the same busy day (144 ticks of 5
--   sim-minutes from dcfc40_2026_10_17's sim start) and seed. Priority 15, after 0736's promise arm. Arm 82 took 33
--   minutes of wall time (started 06:12:00, recorded 06:45:28 UTC on 2026-10-17); the recorder adds one estimate per
--   tick that has a new visit, 1.4 s each in 0739's dry run.
--   The recorder decides nothing, and every dial added since arm 82 ran (0733, 0735, 0737) defaults to 0, so this arm
--   must agree with arm 82 on every outcome: the observer test on the busy day, beside the grade.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P1: arm 82's sweep and cell as read on 2026-10-17, 0739 applied, 0736's promise sweep and dial present. P2: not
--   already applied. V1: the sweep is arm 82's scenario, start, ticks, tick and seed, at priority 15, written after
--   0736's promise sweep; its one cell is arm 82's cell plus ready_promise_record; every dial is one the arm accepts.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: rows in the sweep tables, read only by the sweep runner.
--
-- ROLLBACK (before the sweep has run): DELETE its cell and sweep rows; once run, its arm is evidence and stays.
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0740_a_promise_on_the_busy_day'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P1: what the cell copies ──
DO $premises$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps s
                  WHERE s.sweep_code = 'dcfc40_2026_10_17' AND s.scenario = 'busy_day' AND s.ticks = 144
                    AND s.sim_min_per_tick = 5 AND s.sim_start = '2026-09-01 11:00:00+00'
                    AND s.seeds[1] = 686364201590009433) THEN
    RAISE EXCEPTION '0740 P1: arm 82''s sweep (dcfc40_2026_10_17, busy_day, 144 x 5 from 2026-09-01 11:00 UTC, seed 1) is not as read';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                  WHERE s.sweep_code = 'dcfc40_2026_10_17' AND c.cell_code = 'dcfc10.otto_q' AND c.seat = 'otto_q'
                    AND c.buildout_code = 'dcfc10' AND c.fixed_params = '{"deploy_peak_fraction": 0.90}'::jsonb) THEN
    RAISE EXCEPTION '0740 P1: arm 82''s cell does not carry the build-out and dial this copies';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0739_a_promise_counts_the_cars_still_waiting') THEN
    RAISE EXCEPTION '0740 P1: 0739 is not applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'promise_normal_2026_10_17')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = 'ready_promise_record') THEN
    RAISE EXCEPTION '0740 P1: 0736''s promise sweep or its dial is missing';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'promise_busy_2026_10_17') THEN
    RAISE EXCEPTION '0740 P2: already applied';
  END IF;
END $once$;

INSERT INTO public.ottoq_throughput_sweeps
       (sweep_code, title, depot_id, scenario, sim_start, ticks, sim_min_per_tick, seeds, replicates, priority,
        arm_budget_s, run_after, notes, created_at)
SELECT 'promise_busy_2026_10_17',
       'A promise on the busy day: the depot as built over the busy day, every visit promised and graded',
       d.depot_id, d.scenario, d.sim_start, d.ticks, d.sim_min_per_tick, d.seeds[1:1], 0, 15, 5400, now(),
       '0740 (G452): arm 82''s cell (dcfc10.otto_q in dcfc40_2026_10_17) plus ready_promise_record, on the same busy day '
       'and seed, so 0739''s promise is graded on the day the bays back up. The recorder decides nothing, so this arm must '
       'agree with arm 82 on every outcome; public.ottoq_ready_promise_grade reads its promises.',
       clock_timestamp()
  FROM public.ottoq_throughput_sweeps d WHERE d.sweep_code = 'dcfc40_2026_10_17';

INSERT INTO public.ottoq_throughput_sweep_cells (sweep_id, cell_code, ord, seat, buildout_code, fixed_params)
SELECT s.sweep_id, 'dcfc10.otto_q.promise', 1, 'otto_q', 'dcfc10',
       '{"deploy_peak_fraction": 0.90, "ready_promise_record": 1}'::jsonb
  FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'promise_busy_2026_10_17';

-- ── V1: arm 82's day and cell plus the recorder, after 0736's promise arm ──
DO $verify$
DECLARE v_bad text;
BEGIN
  IF (SELECT row(s.scenario, s.sim_start, s.ticks, s.sim_min_per_tick, s.seeds[1], cardinality(s.seeds), s.depot_id)
        FROM public.ottoq_throughput_sweeps s WHERE s.sweep_code = 'promise_busy_2026_10_17')
     IS DISTINCT FROM (SELECT row(d.scenario, d.sim_start, d.ticks, d.sim_min_per_tick, d.seeds[1], 1, d.depot_id)
                         FROM public.ottoq_throughput_sweeps d WHERE d.sweep_code = 'dcfc40_2026_10_17') THEN
    RAISE EXCEPTION '0740 V1: the sweep is not arm 82''s day, tick and seed';
  END IF;
  IF (SELECT priority FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'promise_busy_2026_10_17') <> 15
     OR (SELECT created_at FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'promise_busy_2026_10_17')
        <= (SELECT created_at FROM public.ottoq_throughput_sweeps WHERE sweep_code = 'promise_normal_2026_10_17') THEN
    RAISE EXCEPTION '0740 V1: the sweep is not priority 15 after 0736''s promise arm';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
       WHERE s.sweep_code = 'promise_busy_2026_10_17') <> 1
     OR (SELECT row(c.fixed_params - 'ready_promise_record', c.fixed_params -> 'ready_promise_record', c.buildout_code, c.seat)
           FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
          WHERE s.sweep_code = 'promise_busy_2026_10_17')
        IS DISTINCT FROM (SELECT row(c.fixed_params, '1'::jsonb, c.buildout_code, c.seat)
                            FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                           WHERE s.sweep_code = 'dcfc40_2026_10_17' AND c.cell_code = 'dcfc10.otto_q') THEN
    RAISE EXCEPTION '0740 V1: the sweep does not hold exactly arm 82''s cell plus ready_promise_record';
  END IF;
  SELECT string_agg(c.cell_code || ':' || f.key, ', ') INTO v_bad
    FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id),
         jsonb_each_text(c.fixed_params) f
   WHERE s.sweep_code = 'promise_busy_2026_10_17'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog k WHERE k.param_key = f.key
                        AND (k.min_value IS NULL OR f.value::numeric >= k.min_value)
                        AND (k.max_value IS NULL OR f.value::numeric <= k.max_value));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0740 V1: dials the arm would refuse: %', v_bad;
  END IF;
END $verify$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0740_a_promise_on_the_busy_day', false, false,
  'Rows only: sweep promise_busy_2026_10_17, arm 82''s cell (dcfc10.otto_q, busy_day, 144 x 5, seed 1) plus '
  'ready_promise_record, priority 15 after 0736''s promise arm. Read only by the sweep runner.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;

-- ══ APPLIED 2026-10-17 17:42:10 UTC (12:42 PM CT), ledger version 20261017174210 ═════════════════════════════════════
--
--   Through apply_migration with the sweep window closed. Executable part 6,073 characters, md5
--   8f118a7aff541a96bb905ba15849c5c6, equal to the ledger's statements[1] read back. Dry-run with a rolled-back read-back
--   first: promise_busy_2026_10_17, busy_day, 144 x 5 from 2026-09-01 11:00 UTC, seed 686364201590009433, priority 15,
--   budget 5,400 s, one cell dcfc10.otto_q.promise {deploy_peak_fraction 0.90, ready_promise_record 1}. Read back in the
--   runner's order, (priority, created_at): it runs after 0736's promise arm (16:38:02 UTC) and before the priority-16
--   sweeps.
