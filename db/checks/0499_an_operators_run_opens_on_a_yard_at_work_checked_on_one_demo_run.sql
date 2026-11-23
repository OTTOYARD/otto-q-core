-- 0499  **An operator's run now opens on a yard already at work, and OTTO-Q decides before the first frame. Checked on
--        one demo run (f29d2d0b): the start took 9.1 s, the first tick came 0.4 s after it committed, and every car on
--        the site held a stall by the second tick.**
--        Production database, 2026-11-23 03:09 to 03:12 UTC (2026-11-22, 9:09 to 9:12 PM CT). Rule 8: the twin depot.
--        Rule 12: one demo run started to see the change working, read, and stopped; no pair, no sweep. One seed:
--        readings, not ranges.
--
-- ══ (1) THE CHANGE ══
--
--   0849 (ledger 20261123030919). Chase, 2026-11-19: "Just make sure Otto-q begins solving and orchestrating immediately
--   as soon as the world variables are selected and the twin rendering loads." For an operator's start with
--   boot_mid_shift on (1 at the twin depot): OTTO-Q's own tick decides at the start clock and places every car on the
--   site; the twin walks those commands at once and gives each charge a drawn head start; the run is in live playback
--   from its first instant; and with metronome_idle_poll on (1, global) the metronome picks a new run up within a second.
--
-- ══ (2) THE RUN: f29d2d0b-6375-479a-b25c-3f066ac714df ══
--
--   Started by me as the cockpit starts one: public.ottoq_operator_start_run('busy_day', NULL, 'operator_demo', NULL),
--   then public.ottoq_set_playback(run, 'live', 8). Seed 6351136665790388000. Stopped through
--   public.ottoq_sim_stop_and_reset at 03:12:12 UTC, after 20 ticks, at sim 14:14:48 (start 14:00:00).
--   - THE START: 9,129 ms for the whole call (before 0849: about 2 s). The boot step took 6,545 ms of it: OTTO-Q enacted
--     27 decisions of 28 requests built and placed 10 more cars; the twin walked 25 commands and opened 20 charges, each
--     before the start clock (head starts 1.0 to 28.5 sim-minutes, mean 10.8; the earliest opened at sim 13:31:30).
--     1 charge faulted inside its head start and its car stood on the site with no stall when the boot step returned.
--   - THE FIRST TICK: at 03:10:16.37 UTC, 0.4 s after the start committed (03:10:15.98). Before 0849 a new run waited
--     for the metronome's next firing (11 s on 368e1472, up to 60).
--   - BY THE SECOND TICK (sim 14:01:27, 19 real seconds in): 49 staged awaiting service, 18 charging, 3 staged to leave,
--     1 holding after its charge: 71 cars on the site, 0 without a stall. 29 decisions carried the start clock; 109 in
--     all. 0 active charges with a target below the car's own (rule 9).
--   - AT 114 REAL SECONDS: 18 ticks, 745 sim-seconds played (6.5 sim-s a real second over the whole span, which holds
--     the 9 s start and the first seconds at 1x before the speed was set to 8x). 38 sessions (19 active, 15 completed,
--     4 faulted), 566 decisions, 2 cars in a service bay and 1 in a wash bay, 0 cars on the site without a stall.
--   - IN THE COCKPIT (2D, the dev server on this branch against the live run, at sim 08:10 CT): cars stand on their
--     chargers with arms out, staged cars in their stalls, a wash bay and both service bays in use, no page error.
--
-- ══ (3) WHAT THIS DID NOT SHOW ══
--
--   - A BAY SEAT WITH A HEAD START. No car was in a bay at the start clock, at the apply's self-test (seed 849) or on
--     this run: OTTO-Q's first decision seated none. The bay branch of twin.ottoq_sim_boot_head_start has not run on
--     production. It was exercised only on the scratch database before the apply.
--   - THE START THROUGH THE API. I started the run as postgres. The cockpit's start runs under service_role's 20 s
--     statement_timeout; the step stands down when under 12 s of it is left. At 9.1 s (13.3 s in the self-test) it fits,
--     with less room than before. A start that stands down says so on the run (payload.boot_mid_shift.skipped).
--   - THE 3D VIEW, and the first rendered frame itself: the screenshot was taken 25 s after the page opened.
--   - Whether a fault inside a head start is wanted. It is the twin's own fault draw played over the head start's
--     minutes, and the first tick re-seated the car. It is 1 car of 20 here and 1 of 18 in the self-test.
--
-- ══ (4) THE QUERIES ══
SELECT r.status, r.tick_count, r.sim_clock_start, r.sim_clock_current, r.payload->'boot_mid_shift' AS boot,
       r.payload->>'playback_mode' AS playback
  FROM public.ottoq_sim_runs r
 WHERE r.sim_run_id = 'f29d2d0b-6375-479a-b25c-3f066ac714df';

SELECT count(*) AS sessions, count(*) FILTER (WHERE cs.started_at < r.sim_clock_start) AS opened_before_start,
       min(cs.started_at) AS earliest
  FROM public.ocpp_sessions cs
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = cs.sim_run_id
 WHERE cs.sim_run_id = 'f29d2d0b-6375-479a-b25c-3f066ac714df';

SELECT count(*) FILTER (WHERE d.sim_clock = r.sim_clock_start) AS at_start_clock, count(*) AS total
  FROM public.ottoq_decisions d
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = d.sim_run_id
 WHERE d.sim_run_id = 'f29d2d0b-6375-479a-b25c-3f066ac714df';
