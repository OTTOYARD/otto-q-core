-- 0414  **Night 2, read the morning after: on the first calibrated test day OTTO-Q cut the power bill 42% at 10 fast
--        chargers and 20% at 20, served about 50 more cars a day and turned them 95 minutes faster, and met less of the
--        ride demand than the plain depot at both charger counts.** One test day (seed 1): single readings, not ranges.
--        (G303, G304, G305, G306 new)
--
--       Written 2026-10-01, 7:40 AM CT. Read-only. Sweep value_2026_09_30 (0575): busy_day, 24-hour test days from 6 AM
--       CT (sim Tue 2026-09-01), 5-minute ticks, deploy_peak_fraction 0.90, on the calibrated twin (0573 charge and
--       service times, 0574 NES TGSA-3 prices), scored by 0576's contract with 0577's peak after the opening. The plain
--       depot is first come, first served with energy_orchestration_enabled = 0. 0600, 0601 and 0603 (#222) were not
--       applied, so the battery planned on its highest five-minute sample and one Zoox was refused every task (G313).
--
-- ══ §1 WHAT RAN ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   arm  sweep / cell                         run       wall     departures  left short  left with work open
--   24   smoke dcfc20.otto_q (2 h)            01d8dd77    1.4 min     14          0            0
--   25   value dcfc10.otto_q                  273fb34d  121.8 min    353          0            1   (§4, G303)
--   26   value dcfc10.fifo.energy_off         e0a75a1f   98.6 min    299          0            0
--   27   value dcfc20.otto_q                  57a431cb  137.3 min    388          0            0
--   28   value dcfc20.fifo.energy_off         51d739eb  129.6 min    337          0            0
--   Every arm complete, shield paid, no arm error. The smoke sweep re-ran first because 0573/0574 moved the dial floor.
--   Arm 28 started at 10:02 UTC inside the window and finished at 12:11 UTC (7:11 AM CT), after it (§5).
--
--   **Pace.** A 24-hour test day took 98.6-137.3 minutes, not the 50-80 estimated (0575 §2): 1.6-2.3 hours, so a night
--   fits 3-4 of the value sweep's 24 arms and the sweep needs about 6-7 nights. G314 (each arm is one long transaction,
--   and ticks slow as it runs) is what would shorten that.
--
-- ══ §2 THE FIRST TEST DAY (ottoq_value_summary, seed 1) ═══════════════════════════════════════════════════════════════
--
--                                        10 fast chargers           20 fast chargers
--                                        plain     OTTO-Q           plain     OTTO-Q
--   power bill, $/month (TGSA-3)         79,184    46,159           67,357    54,109
--   peak demand, kW (from 3 h in)         1,848       853            1,385     1,033
--   peak incl. the opening, kW            1,848       853            1,715     1,342
--   demand charge, $/month               39,879    18,247           29,788    22,113
--   energy bought, kWh/day               17,811    13,232           16,797    14,992
--   effective rate, c/kWh                  14.8      11.6             13.4      12.0
--   cars fully serviced / day               299       353              337       388
--   cars per fast charger / day            29.9      35.3             16.9      19.4
--   turnaround door to door, p50 min        345       250              255       160
--   fast chargers busy, %                  69.6      59.6             52.9      52.8
--   ride demand met, %                     16.7       7.7             12.1       8.4
--   revenue hours per car per day          2.23      1.03             1.62      1.13
--
--   OTTO-Q against the plain depot: power bill -$33,025 a month (-41.7%) at 10 and -$13,248 (-19.7%) at 20; peak
--   -996 kW and -352 kW; +54 and +51 cars fully serviced a day; turnaround -95 minutes at both; revenue hours per car
--   per day -1.21 and -0.49, which at 0569's $20 a car-hour is -$24.16 and -$9.90 per car per day.
--
--   **Read plainly.** Energy and service went OTTO-Q's way on this day, by a lot at 10 chargers. Uptime did not, at
--   either charger count, and at 10 chargers the uptime loss (about $84,000 a month across 116 cars at $20 a car-hour)
--   is larger than the power saving. It is G302's pattern again, now on the calibrated twin and on 24-hour days. Both
--   depots met under a fifth of the ride demand the dispatcher asked for: the fleet spends most of the day inside the
--   depot. That, not the charger count, is the binding constraint on this twin today, and it is the engine review's.
--
--   **What one day cannot say.** No ranges (one seed), no split of the saving between the energy planner and the
--   charger assignment (the planner-off OTTO-Q cell and the planner-on first-come cell run later), and no investor
--   claim: the contract's chargers sentence correctly withholds one, though it names the wrong reason (§6, G306).
--   0574's prediction that the battery stops trading on price under NES is not checked here; the energy contrasts are.
--
-- ══ §3 WHERE EACH DAY'S PEAK FELL ════════════════════════════════════════════════════════════════════════════════════
--
--   (0577's ottoq_arm_peak_profile, minute of the day the highest 30 minutes start, from 6 AM CT)
--   25 OTTO-Q 10:  853 kW at minute 990 (10:30 PM CT) at every offset: the opening is not the peak.
--   26 plain 10:   1,848 kW at minute 1,145 (about 1:05 AM CT) at every offset: the overnight return plugs in at once.
--   27 OTTO-Q 20:  1,342 kW at minute 10 (the opening); from 3 hours in, 1,033 kW at minute 805 (7:25 PM CT).
--   28 plain 20:   1,715 kW at minute 10 (the opening); from 30 minutes in, 1,385 kW at minute 1,095 (about 12:15 AM CT).
--   So on 24-hour days the opening set the full-day peak at 20 chargers only. Billing from 3 hours in (0576) moved both
--   20-charger bills and neither 10-charger bill. The plain depot's peaks are the unmanaged overnight plug-in.
--
-- ══ §4 RULE 9: ONE CAR LEFT WITH WORK OPEN, ON THE DAY'S LAST TICK (G303) ═════════════════════════════════════════════
--
--   Arm 25, Waymo I-Pace cadd7c81, visit c5029407 (an OTA wave): arrived 5:20 AM CT (sim 10:20 UTC Sep 2), 40 sim-minutes
--   before the day ended. On the final tick (11:00 UTC, the horizon) its L2 charge finished at 100%, and in the same tick
--   it went charge_complete_holding -> staged_for_departure -> deployed (dispatch 0444c935), then offline at teardown.
--   Open at that moment: software_update in_progress (ends 11:01), item_retrieval and readiness_check never started, all
--   must_do. Every way out is checked (0543's deploy-plan filter, 0544's second door in twin.ottoq_sim_dispatch_vehicle
--   and the BEFORE INSERT trigger trg_dispatch_departure_clear), and all three ask public.ottoq_departure_clear.
--
--   Why: public.ottoq_sim_advance_tick runs the world step, then ottoq_sim_decide_and_dispatch. On the last tick the
--   world step sets the run's status to 'completed' mid-function (its own 0103 comment: "advance_tick_world writes
--   status='completed' mid-function ... decide_and_dispatch has also already run (and may have issued commands
--   post-completion)"). The AFTER UPDATE OF status trigger ottoq_sim_runs_close_needs fires at once and
--   ottoq_close_run_needs marks every open visit 'superseded'. public.ottoq_departure_clear only reads visits that are
--   'open' or 'in_progress', so the last decide-and-dispatch judges every car against an empty need list, and a car at
--   its charge target leaves. The visit's meta proves the order: closed_by ottoq_close_run_needs, close_reason
--   run_completed, which that function writes only on a visit still open or in progress.
--
--   It is the twin's end-of-day seam: a depot that runs around the clock has no last tick, and production runs do not
--   complete this way. But the twin should not do it, and the scorecard counts it as a rule-9 breach: 1 of 1,040
--   departures on night 2's value days. Night 1 had none (#222 counted 2,494 departures on 18 arms, all clean).
--
--   Proposed fix (not applied; it changes every arm's last tick, so forces_recert and forces_dial_restart TRUE): in
--   ottoq_sim_advance_tick, skip ottoq_sim_decide_and_dispatch when the world step completed the run. A completed run
--   makes no new decisions; its finalizer already expires anything issued after completion.
--
-- ══ §5 THE WINDOW STAYED OPEN, AND THE IN-FLIGHT PROBE COULD NOT SEE WHY (G304, G305) ══════════════════════════════════
--
--   G304. The window is two cron jobs (784 sets throughput_sweep_runner_enabled = 1 at 04:00 UTC, 785 sets 0 at 11:00
--   UTC), and the runner checks only that dial. Arm 28 began at 10:02 UTC and ran 129.6 minutes in one transaction.
--   While it ran, pg_cron started no job at all (G141): job_run_details holds nothing from 10:02:00 to 12:11:37 UTC. So
--   785 never fired, the dial stayed 1, and the next free runner firing would have started another 24-hour day into
--   Chase's morning, starving the depot tick, the metronome and the governor again. I set the dial to 0 by hand at
--   11:24 UTC (6:24 AM CT, reason recorded on the policy write). Missed firings are dropped, so 785 fires next at 11:00
--   UTC tomorrow.
--   Proposed fix: the runner refuses to start an arm outside the window by itself (a window end it reads, not a cron job
--   that can be starved), and refuses one that cannot finish before the window closes at the measured pace.
--
--   G305. public.ottoq_certification_in_flight reads pg_stat_activity through ottoq_certification_rig_matches, which
--   matches ottoq_determinism_pair, ottoq_ab_pair, ottoq_recert_runner, ottoq_dial_pair and
--   ottoq_dial_experiment_runner. Not ottoq_throughput_sweep_runner: the cron command running arm 28 matched nothing,
--   and the probe read 0 at 11:22 UTC while the arm was 80 minutes in. Every migration since 0571 has a P0 whose
--   message says "a pair, the recert runner, a dial pair or a sweep arm is running right now"; the sweep-arm part has
--   never been checked. Yesterday's applies were safe (no arm ran during them, and pg_stat_activity showed no active
--   client backend). Proposed fix: add '%ottoq_throughput_sweep_runner%' and '%ottoq_throughput_sweep_arm%' to the
--   rig's patterns, with a test that runs the probe against a sweep arm.
--
-- ══ §6 THE CONTRACT'S CHARGERS SENTENCE NAMES THE WRONG REASON (G306) ════════════════════════════════════════════════
--
--   ottoq_value_summary's investor block reads: "Not on every test day: with 10 fast chargers OTTO-Q served 353.0 cars a
--   day, against 337.0 at a plain depot with 20." On this day OTTO-Q at 10 DID serve more cars than the plain depot at
--   20 (353 against 337). The test it failed is the other half, ride demand met (7.7% against 12.1%), which the sentence
--   does not mention. Withholding the chargers-avoided figure is right; the sentence explaining it is wrong.
--   Proposed fix: name the condition that failed, in its own numbers.
--
-- ══ §7 NOT DONE HERE ═════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Nothing was applied. 0600, 0601, 0603 and the fixes proposed above wait for Chase. The queue after the value sweep is
--   night 1's 31 test days re-running on the calibrated twin (priority 100, created first), then charge_order and the
--   two fleet build-outs; moving night 1's re-run to the back is Chase's call.

-- ── §1 the arms, their wall time and rule 9 ──
SELECT a.arm_id, s.sweep_code, c.cell_code, a.sim_run_id, a.complete, a.paid_shield, a.arm_error,
       round(EXTRACT(EPOCH FROM (a.ran_at - r.started_at)) / 60.0, 1) AS wall_min,
       a.scorecard #>> '{rule9,departures}' AS departures,
       a.scorecard #>> '{rule9,left_below_target}' AS left_short,
       a.scorecard #>> '{rule9,left_with_needed_work_open}' AS left_with_work_open
  FROM public.ottoq_throughput_sweep_arms a
  JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
  JOIN public.ottoq_throughput_sweeps s ON s.sweep_id = a.sweep_id
  LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = a.sim_run_id
 WHERE a.ran_at >= '2026-10-01 03:55:00+00' AND a.ran_at < '2026-10-01 13:00:00+00'
 ORDER BY a.arm_id;

-- ── §2 the first test day, as the Value tab reads it ──
SELECT v -> 'fast_chargers' AS fast_chargers, v -> 'plain' AS plain, v -> 'otto_q' AS otto_q, v -> 'vs_plain' AS vs_plain
  FROM jsonb_array_elements(public.ottoq_value_summary('value_2026_09_30') -> 'views') v;

-- ── §3 where each day's peak fell ──
SELECT a.arm_id, c.cell_code, a.arm_metrics #> '{peak_after_open,peak_30min_kw}' AS peak_by_offset,
       a.arm_metrics #> '{peak_after_open,starts_min}' AS peak_starts_min
  FROM public.ottoq_throughput_sweep_arms a JOIN public.ottoq_throughput_sweep_cells c ON c.cell_id = a.cell_id
 WHERE a.arm_id BETWEEN 24 AND 28 ORDER BY a.arm_id;

-- ── §4 the car that left with work open, and the last tick's order ──
SELECT * FROM public.ottoq_visit_outcomes('273fb34d-3a45-42bd-95fa-fa8ccff95b84') WHERE needed_open_at_departure > 0;

SELECT vn.status, vn.meta ->> 'closed_by' AS closed_by, vn.meta ->> 'close_reason' AS close_reason,
       (SELECT string_agg((a ->> 'svc') || ':' || COALESCE(a ->> 'status', 'not started'), ', ')
          FROM jsonb_array_elements(vn.atoms) a) AS atoms
  FROM public.ottoq_visit_needs vn WHERE vn.visit_id = 'c5029407-d00e-4f7f-9edc-85176c0a9369';

SELECT e.event_seq, e.sim_clock_at, e.event_type,
       (e.payload #>> '{diff,current_state,from}') || ' -> ' || (e.payload #>> '{diff,current_state,to}') AS transition
  FROM public.ottoq_events e
 WHERE e.entity_id = 'cadd7c81-433d-4158-90ac-b08ecbdcdf7a' AND e.sim_run_id = '273fb34d-3a45-42bd-95fa-fa8ccff95b84'
   AND e.sim_clock_at = '2026-09-02 11:00:00+00' AND e.event_type = 'vehicle.state_changed'
   AND e.payload #> '{diff,current_state}' IS NOT NULL
 ORDER BY e.event_seq;

SELECT pg_get_triggerdef(t.oid) FROM pg_trigger t WHERE t.tgname = 'ottoq_sim_runs_close_needs';

-- ── §5 the window and the probe ──
SELECT min(start_time) FILTER (WHERE start_time > '2026-10-01 10:02:30+00') AS first_cron_job_after_arm_28_began,
       count(*) FILTER (WHERE start_time > '2026-10-01 10:02:30+00' AND start_time < '2026-10-01 12:11:00+00') AS jobs_while_it_ran
  FROM cron.job_run_details;

SELECT public.ottoq_certification_rig_matches('SET statement_timeout = 0; SELECT public.ottoq_throughput_sweep_runner();', true)
         AS probe_sees_a_sweep_arm;
