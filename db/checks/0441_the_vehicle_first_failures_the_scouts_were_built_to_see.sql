-- 0441  **The vehicle-first failures the scouts were built to see.** The premises of db/migrations/0704 (six
--        deterministic per-vehicle scouts), and what they have found since. Read-only.
--
--        0704's header and its live lineage note (classified 2026-10-13) cite this file. It was named then and written
--        later the same day, at 19:40-19:45 UTC (2:40-2:45 PM CT), from the study's stored results and the scouts' own
--        evidence. The study's engine-side runs (3390752c, 723fa527, b26ccf07: ab_harness, busy_day) are run-scoped
--        engine data that later demo starts purge; the figures below from them are as the study measured them that
--        morning, and the scouts' evidence table (class 'evidence', no foreign key) is what survives to re-derive from.
--
-- ══ §1 WHAT THE STUDY MEASURED (its vehicle-first lane, 2026-10-13 morning) ══
--
--   VF-1 (critical, rule 9). On 3390752c, 128 departures across 65 cars left after the kernel's own recall policy had
--     recalled the same car for service_interval_due, with no mechanical_pm or sensor_calibration done in between, and
--     each was recalled again (723fa527: 161 departures over 74 cars; b26ccf07: 184 over 78). The recall reads wear
--     deterministically; the twin's need generator puts the PM or calibration atom on an overdue car's visit with
--     probability about 0.30 / 0.24; ottoq_departure_clear reads only visit atoms. Scout: interval_due_departure.
--     The fix is 0715 (pending: the PM/calibration due test made deterministic, Chase's decision on intervals; G430).
--   VF-2. Two schedule_tasks rows created 2026-06-04 and never closed make HW.005 fail for Zoox-AV-084 on every
--     task_start (130 / 217 / 80 / 28 refusals on four runs), stranding it 16-21 sim-hours. Scout:
--     legacy_task_residue. The rows' retirement is 0603 (pending: an UPDATE a person runs; G313).
--   VF-3. The 0642 fairness floor ties when a cohort enters the line together, and the tie-break by response ratio in
--     minutes serves top-offs first: a 13% car waited 485 minutes for an L2 while 56 sessions started for cars at 80%
--     or more. Scout: contract_wait_breach (each car past its owner's max_queue_wait_minutes).
--   VF-6. No rule or invariant encoded any of these: 180,658 shield evaluations on 3390752c flagged only VF-2's false
--     alarm. Hence the scouts: advisory, deterministic, one append-only evidence row per (run, car, scout, episode),
--     plus same_trigger_rebound (recalled again within 30 sim-minutes for the same trigger), departed_below_target
--     (rule 9's charge half, expected 0) and stranded_open_must_do (an open visit over 4 sim-hours with a must-do
--     open and nothing finished in 2).
--
-- ══ §2 WHAT THE SCOUTS FOUND, BY RUN (reproduce: (1); read 19:41 UTC) ══
--
--                               176b2912 (shadow)   57188f55 (gate on)   02ac27b3 (0562, running, sim ~3 h in)
--     contract_wait_breach      126 (101 cars)      129 (98 cars)         48 (48 cars)
--     stranded_open_must_do      89 (89 cars)        75 (75 cars)          0
--     interval_due_departure      3                   6                    0
--     legacy_task_residue         4 (3 cars)          4 (3 cars)           4 (3 cars)
--     same_trigger_rebound        0                   2 (1 car)            1
--     departed_below_target       0                   0                    0
--
--   departed_below_target is 0 on every run: rule 9's charge half held. interval_due_departure is VF-1 still
--   happening (0715 is not applied). legacy_task_residue is VF-2's rows, unchanged (0603 is not applied).
--   contract_wait_breach and stranded_open_must_do are the charge line's congestion (G384, G426): a capacity finding.

-- (1) the scouts' findings, by run
SELECT left(sim_run_id::text, 8) AS run, scout, severity, count(*) AS findings, count(DISTINCT vehicle_id) AS cars
  FROM public.ottoq_vehicle_scout_findings
 GROUP BY 1, 2, 3 ORDER BY 1, 4 DESC;

-- (2) the scan is the cron job, one statement a minute, and it ran
SELECT j.jobname, j.schedule, j.command, count(*) AS runs_last_hour,
       count(*) FILTER (WHERE d.status <> 'succeeded') AS not_ok
  FROM cron.job j
  JOIN cron.job_run_details d ON d.jobid = j.jobid
                             AND d.runid > (SELECT max(runid) FROM cron.job_run_details) - 1500
                             AND d.start_time > now() - interval '1 hour'
 WHERE j.jobname = 'ottoq-vehicle-scouts'
 GROUP BY 1, 2, 3;

-- (3) the cars VF-2 names: in_progress tasks older than any run (G313)
SELECT t.id, t.vehicle_id, t.status, t.service_code, t.created_at
  FROM public.schedule_tasks t
 WHERE t.status = 'in_progress' AND t.created_at < '2026-07-01'
 ORDER BY t.created_at;
