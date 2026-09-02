-- =====================================================================
-- 0074  A certification pair in thirteen seconds
--       The grid fixture (0153) measured; one instrument defect (0154);
--       pg_cron runs one job at a time.
-- =====================================================================
-- Chase, Sep 2 ~7 AM CT: "Do we need an entire depot? ... It's all just
-- data points and grid points. If we see scenario A go to grid B, which
-- is according to its instructions ... that would be a success."
--
-- §1  The instrument
-- ------------------
-- 0153 (applied 7:49 AM CT, functions only; PR #145 merged 7:54 AM CT)
-- adds twin.ottoq_grid_fixture_create (clone the flagship's depot SHAPE
-- into a tiny grid), twin.ottoq_grid_assert (eleven rules the engine's
-- own code states, checked against what a run wrote; a vacuous check
-- FAILS) and twin.ottoq_grid_smoke (one command: a two-arm certification
-- pair on the fixture, then the assertions).
--
-- §2  Measured, in transactions that were rolled back
-- ----------------------------------------------------
-- Every trial below created the fixture 'grid-dry', ran a pair, raised
-- with the results, and so left nothing behind (verified: 0 depot rows,
-- 0 runs for that depot afterwards). The flagship round 7 ran alongside;
-- uncommitted rows are invisible to it.
--
--   trial            wall     per tick   verdict   proposer
--   fixture build    298 ms   -          -         -
--   2 arms x 3 ticks  5.0 s   ~0.3 s     passed    policy_disabled x3
--   2 arms x 12 ticks 13.1 s  ~0.5 s     passed    policy_disabled x12
--   flagship 12-tick pair, for comparison: 5.4-7.5 min, 7-16 s per tick
--
-- 12-tick trial (7:55 AM CT, seed 424242, 4 assets, 10 points, cap 600 kW):
--   run_completed                        PASS  status=completed, ticks=12
--   every_enacted_assignment_is_booked   FAIL  0 of 6            <- the instrument, see §3
--   no_point_double_booked               PASS  0 overlapping among 19 bookings
--   every_booking_on_a_capable_point     PASS  0 of 19 on an incapable point
--   dcfc_first_l2_only_as_overflow       PASS  0 violations, 10 charge bookings
--   most_depleted_gets_the_fast_point    PASS  0 same-tick inversions among 6 charging assignments
--   site_power_cap_held                  PASS  max ev charging 59.80 kW vs 600 kW
--   every_completed_operation_has_an_sdr PASS  9 of 9 completed service legs have an SDR
--   every_refusal_carries_a_reason       PASS  0 of 6 refusals without a reason code
--   proposer_quiesced                    PASS  12 invocations, all policy_disabled
--   pair_verdict_passed                  PASS  outcome=passed, equal=true
--
-- So on a world the engine cannot tell from a depot, a full two-arm
-- certification pair plus eleven behavioural assertions costs about
-- fourteen seconds. The flagship round stays as the nightly
-- confirmation; the grid is the iteration loop.
--
-- §3  The one failure was the instrument (0154)
-- ---------------------------------------------
-- Check 2 required every enacted stall assignment's enacted_action to
-- carry a booking_id. On the latest flagship arm (round 7, 7:49 AM CT):
-- 191 enacted stall assignments; 12 carry booking_id (all gate_intake,
-- all 12 resolve to the right booking); 179 do not (assign_stall); and
-- ALL 191 have a booking for that vehicle on that point in that run. The
-- engine's rule holds. The check now matches on (run, vehicle, point) and
-- requires the id only where the action names one. Same class as 0148:
-- state the check in terms the data actually carries.
--
-- §4  pg_cron runs one job at a time here
-- ---------------------------------------
-- The 12-tick trial was scheduled for 12:52 UTC; it started at
-- 12:55:29.432, forty milliseconds after r7_a2 (12:49:00 - 12:55:29.393)
-- finished. The per-minute production jobs show the same gaps:
--   ottoq-demo-metronome (* * * * *) ran 12:38 12:39 12:40 | 12:47 12:48 12:49 | 12:55 12:56
--   ottoq-depot-tick    (*/2)        ran 12:38 12:40 | 12:48 | 12:56
--   ottoq-run-governor  (*/2)        ran 12:38 12:40 | 12:48 | 12:56
-- i.e. nothing ran while r7_a1 (12:40-12:47) or r7_a2 (12:49-12:55) was
-- running, although cron.max_running_jobs=32. Whatever the cause
-- (cron.use_background_workers=off on this instance), the observed
-- behaviour is: a flagship certification pair blocks EVERY other cron
-- job - the production heartbeat included - for its duration. Harmless
-- today (the flagship's feed_mode is 'sim' and no live fleet is on it);
-- not acceptable once a real feed depends on ottoq_cron_tick. The grid
-- fixture reduces the blockage to seconds; the standing item is to move
-- the flagship rounds off the production cron path.
--
-- §5  Next
-- --------
--  - After round 7 ends (~9:52 AM CT): create the committed 'grid-fixture'
--    and run twin.ottoq_grid_smoke(424242, 12) for the first committed
--    grid pair; its run id goes here.
--  - A tight-cap variant (service_max_kw below two DCFC sessions) so the
--    0132 gate is exercised, not merely respected.
--  - Every future engine change: grid smoke first (seconds), flagship
--    round after (nightly).
--
-- §6  Queries
-- -----------
-- 6.1 the smoke (creates the fixture on first use)
--   SELECT twin.ottoq_grid_fixture_create('grid-fixture');
--   SELECT * FROM twin.ottoq_grid_smoke(424242, 12);
-- 6.2 the assertions on any run
--   SELECT * FROM twin.ottoq_grid_assert('<sim_run_id>');
-- 6.3 the pg_cron gaps
SELECT j.jobname, j.schedule, string_agg(to_char(d.start_time AT TIME ZONE 'UTC','HH24:MI'), ' ' ORDER BY d.start_time) AS minutes
  FROM cron.job_run_details d JOIN cron.job j USING (jobid)
 WHERE d.start_time BETWEEN '2026-09-02 12:38:00+00' AND '2026-09-02 12:56:30+00' AND j.jobid IN (10, 12, 17)
 GROUP BY 1,2 ORDER BY 1;
-- 6.4 the instrument defect, on any flagship arm
WITH arm AS (SELECT sim_run_id FROM ottoq_sim_runs WHERE run_by='cert_harness' AND status='completed'
              AND depot_id='11111111-1111-1111-1111-111111111111' ORDER BY started_at DESC, sim_run_id DESC LIMIT 1),
     d AS (SELECT d.* FROM ottoq_decisions d JOIN arm USING (sim_run_id) WHERE d.action_context='stall_assignment' AND d.outcome_status='enacted')
SELECT count(*) AS enacted,
       count(*) FILTER (WHERE enacted_action ? 'booking_id') AS with_booking_key,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM ottoq_stall_bookings b WHERE b.sim_run_id=d.sim_run_id AND b.vehicle_id=d.entity_id
                                        AND b.stall_id=(d.enacted_action->>'stall_id')::uuid)) AS booked_on_that_point,
       string_agg(DISTINCT enacted_action->>'verb', ', ') AS verbs
  FROM d;
