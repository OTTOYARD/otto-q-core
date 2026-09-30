-- migration-version: PENDING
-- migration-name:    a_legacy_task_from_june_no_longer_strands_a_car_on_every_otto_q_test_day
--
-- 0603  **Two scheduler tasks left `in_progress` on 2026-06-04 make the L1 shield refuse every task one Zoox is offered,
--       on every OTTO-Q test day, so that car waits all day at 24% and never charges; under the fifo and greedy seats the
--       same car charges to 100% by 11:10.** Overnight review 2026-09-30 (G313). Data repair; no function changes.
--
-- ══ §1 WHY ════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   `HW.005.vehicle_one_active_task` (critical, `block`, probed at `task_start`, whose caller honours the refusal) counts a
--   vehicle's rows in `public.schedule_tasks` with status in_progress or vehicle_en_route, over every row, with no run
--   scope: that table has no run column. Nothing has written it since 2026-06-19 (113 rows; the last update 2026-06-18
--   04:07 UTC). Four of its rows are still `in_progress`, created 2026-06-04 18:03, never started (`actual_start` NULL),
--   and two belong to one car, the Zoox 229f655b-803c-47c0-95fd-ca8adb9d8ef0. So HW.005 finds "2 simultaneously active
--   tasks" for that car on every run, and refuses its task start.
--
--   Measured on the twin depot's surviving runs (2026-09-30): HW.005 refused that one car on every tick of the smoke arm
--   (88e46ad3, 23 of 24 ticks) and of night 1's arm 3 (85a5d396, dcfc10.otto_q: 143 of 144, ticks 2-144): 332 refusals in
--   all, always this one car, across the 13 twin runs whose evaluations survive (from 2026-09-29 00:46 UTC). On arm 3 the car sat at 24% from 6:05 AM to 6 PM CT, its deploy gate escalated at 240
--   minutes ("a person must look ... not released", rule 9 held), and it never plugged in. On the same seed, night 1's
--   fifo arm (d038fb17) and greedy arm (1edc847e), whose seats reach charging by another path, plugged it in at 11:10 UTC
--   and took it to 100%. So every OTTO-Q arm carries one stranded car that its baselines do not: arm 3's 720-minute
--   maximum charge wait is that car, and the seat comparison night 1 was built to make is biased against OTTO-Q by it.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   The four rows, pinned by id, go from `in_progress` to `cancelled`, with a note naming this migration. The table's own
--   trigger records a `task.state_changed` event for each; the transaction's run context is set to none first (0421's
--   idiom), so no running run is handed the evidence. HW.005 itself is unchanged: a real second active task is still
--   refused. Every other reader of the table was read for what a cancellation could do (2026-09-30): SLA.004's legacy
--   path and ottoq_cleaning_due count only `completed` rows, SLA.007 joins exceptions to tasks without reading the task's
--   status, and the attribution trigger and SDR coverage key on task ids. None can refuse or release anything new. Whether HW.005 should read a table the running engine no longer writes is a rule question left open (G313).
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the active rows are exactly the four measured, all unstarted and last updated by
--   2026-06-18 04:07:40.920806 UTC; nothing in the table was updated after 2026-06-20; HW.005's evaluator is the one
--   measured (prosrc md5 e744b5be3b873f4758a186f9b320f032); not yet applied.
--   V1: no active row remains. V2: HW.005's evaluator passes the Zoox 229f655b.
--   Executed by tests/test_legacy_task_sql.py against the live evaluator carried byte for byte.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert TRUE and forces_dial_restart TRUE: an OTTO-Q run's decisions change (the car's tasks start, it charges).
--   Apply with 0573/0574. Night 1's OTTO-Q arms keep the stranded car; read them with it named.
--
-- ROLLBACK: UPDATE public.schedule_tasks SET status = 'in_progress', notes = NULL
--            WHERE id IN ('54031064-b05a-41ab-917b-4134862778cc', '9c8bd438-e8c1-4579-ae81-05594d16c432',
--                         'cdffb3c8-22e0-41d9-ac80-f896c1ecf978', '1415d036-749b-4e0b-89e7-0692559ae0eb');
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0603_a_legacy_task_from_june_no_longer_strands_a_car_on_every_otto_q_test_day'.

BEGIN;

-- ── P0: nothing in flight (0513's one probe) ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0603 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: the four rows measured, the table dead since June, the evaluator measured, not yet applied ──
DO $premises$
DECLARE
  v_ids text;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0603_a_legacy_task_from_june_no_longer_strands_a_car_on_every_otto_q_test_day') THEN
    RAISE EXCEPTION '0603 P1: already applied';
  END IF;
  SELECT string_agg(id::text, ',' ORDER BY id::text) INTO v_ids
    FROM public.schedule_tasks
   WHERE status IN ('in_progress', 'vehicle_en_route') AND actual_start IS NULL
     AND updated_at <= '2026-06-18 04:07:40.920806+00';
  IF v_ids IS DISTINCT FROM '1415d036-749b-4e0b-89e7-0692559ae0eb,54031064-b05a-41ab-917b-4134862778cc,'
                            '9c8bd438-e8c1-4579-ae81-05594d16c432,cdffb3c8-22e0-41d9-ac80-f896c1ecf978'
     OR (SELECT count(*) FROM public.schedule_tasks WHERE status IN ('in_progress', 'vehicle_en_route')) <> 4 THEN
    RAISE EXCEPTION '0603 P1: the active schedule tasks are not the four measured on 2026-09-30: %', v_ids;
  END IF;
  IF (SELECT max(updated_at) FROM public.schedule_tasks) > '2026-06-20 00:00+00' THEN
    RAISE EXCEPTION '0603 P1: something has written schedule_tasks since June; it is not the dead table measured';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'public.ottoq_eval_hw_005_vehicle_one_task(text,uuid,jsonb,jsonb)'::regprocedure)
     IS DISTINCT FROM 'e744b5be3b873f4758a186f9b320f032' THEN
    RAISE EXCEPTION '0603 P1: HW.005''s evaluator is not the one measured on 2026-09-30';
  END IF;
END $premises$;

-- ── the repair: the evidence belongs to no run (0421), and says who wrote it ──
DO $ctx$
BEGIN
  PERFORM set_config('ottoq.sim_run_id', 'none', true);
  PERFORM set_config('ottoq.actor_type', 'migration', true);
  PERFORM set_config('ottoq.actor_id', '0603', true);
END $ctx$;

UPDATE public.schedule_tasks
   SET status = 'cancelled',
       notes = '0603 (G313), 2026-09-30: orphaned in_progress since 2026-06-04 and never started; the scheduler that '
               'wrote this table last ran 2026-06-19. HW.005 counted it on every run.'
 WHERE id IN ('54031064-b05a-41ab-917b-4134862778cc', '9c8bd438-e8c1-4579-ae81-05594d16c432',
              'cdffb3c8-22e0-41d9-ac80-f896c1ecf978', '1415d036-749b-4e0b-89e7-0692559ae0eb')
   AND status = 'in_progress';

-- ── V1: no active row remains ──
DO $v1$
BEGIN
  IF EXISTS (SELECT 1 FROM public.schedule_tasks WHERE status IN ('in_progress', 'vehicle_en_route')) THEN
    RAISE EXCEPTION '0603 V1: an active schedule task remains';
  END IF;
END $v1$;

-- ── V2: HW.005 passes the car it refused ──
DO $v2$
DECLARE
  r public.ottoq_rule_result;
BEGIN
  r := public.ottoq_eval_hw_005_vehicle_one_task('vehicle', '229f655b-803c-47c0-95fd-ca8adb9d8ef0', '{}'::jsonb, '{}'::jsonb);
  IF NOT r.passed THEN
    RAISE EXCEPTION '0603 V2: HW.005 still refuses the Zoox 229f655b: %', r.reason;
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0603_a_legacy_task_from_june_no_longer_strands_a_car_on_every_otto_q_test_day', true, true,
  'G313, overnight review 2026-09-30. Cancels the four schedule_tasks rows orphaned in_progress since 2026-06-04 (the '
  'table has had no writer since 2026-06-19). HW.005 counted two of them for the Zoox 229f655b on every run and refused '
  'its task start on every tick of every OTTO-Q test day (smoke arm 88e46ad3, night 1 arm 85a5d396), so it never charged; '
  'fifo and greedy on the same seed charged it to 100%. TRUE/TRUE: OTTO-Q runs change. Apply with 0573/0574.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
