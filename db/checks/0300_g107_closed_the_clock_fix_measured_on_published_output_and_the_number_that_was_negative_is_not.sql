-- 0300  G107 CLOSED ON PUBLISHED OUTPUT. `0396` chose the clock before building the world; the
--       number that proved the defect was `hours_clipped_to_window = -227.36` on `c9b0a87e`, and
--       on the post-fix run it reads **+0.52**. `ottoq_assert_dispatch_time_coherence` returns
--       **coherent, all 101 dispatches**, where it raised **32 of 87** on the pre-fix pair.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
-- Captured 2026-09-21 06:43 UTC (01:43 CT) from a COMPLETED run, before any later demo run's
-- purge could take the class='engine' tables these figures are computed from. That ordering is
-- the whole reason `0297` said the post-fix measurement comes after `0396` and not before.
--
-- ══ 1. THE RUN, AND WHY IT IS THE RIGHT ONE TO MEASURE ═════════════════════
--
--   sim_run_id        71942fbf-76ee-4b99-9065-c9164a714993
--   seed / scenario   100020 / busy_day / policy otto_q / pack robotaxi
--   status            completed, tick_count 1147
--   sim_clock_start   2026-09-20 05:35:00+00  =  2026-09-20 00:35 CT
--   sim_elapsed       09:10:36  (550 sim-minutes, i.e. the 540-minute horizon crossed)
--   world_built_for   payload.boot_prime.start_hour_cst = "0"
--
-- **`world_built_for` is the fix, restated as data.** Pre-`0396` the world was built for hour 8
-- CT and then the clock was rewritten to `date_trunc('day', ...) + hashtext(seed) % 1440` = 05:35
-- UTC = 00:35 CT, so the depot was populated with an 8 a.m. world and then ticked from half past
-- midnight. Every dispatch minted during boot carried a `returned_at` behind its `dispatched_at`.
-- Now the offset is chosen FIRST and the world is built against it: 0 CT, matching 00:35 CT.

SELECT left(sim_run_id::text, 8)                                           AS run,
       status, tick_count, random_seed,
       sim_clock_start,
       to_char(sim_clock_start AT TIME ZONE 'America/Chicago', 'HH24:MI')  AS start_ct,
       payload->'boot_prime'->>'start_hour_cst'                            AS world_built_for_hour_ct,
       (sim_clock_current - sim_clock_start)                               AS sim_elapsed,
       (SELECT count(*) FROM public.ottoq_vehicle_dispatches d
         WHERE d.sim_run_id = r.sim_run_id AND d.dispatched_at > r.sim_clock_start)
                                                                          AS dispatched_in_the_future,
       (SELECT count(*) FROM public.ottoq_vehicle_dispatches d
         WHERE d.sim_run_id = r.sim_run_id AND d.actual_duration_min < 0)  AS negative_durations
  FROM public.ottoq_sim_runs r
 WHERE r.sim_run_id = '71942fbf-76ee-4b99-9065-c9164a714993';

-- Measured: dispatched_in_the_future 0, negative_durations 0.

-- ══ 2. THE ASSERTION `0396` ADDED, RUN IN ANGER ════════════════════════════
--
-- `public.ottoq_assert_dispatch_time_coherence` is deliberately a FUNCTION and not a CHECK
-- constraint, because the writer is the unwrapped tick hot path and a constraint there would turn
-- a data defect into a run-ending error. On `c9b0a87e` it raised:
--
--     32 of 87 dispatches return before they were dispatched and 32 carry a negative
--     actual_duration_min (worst inversion 439.5 min)
--
-- On `71942fbf` it returns:
--
--     (101, 0, 0, -1.5, "coherent: all 101 dispatches return after they were dispatched")
--
-- 101 dispatches examined, 0 inverted, 0 negative durations. This is the first time the assertion
-- has passed on a live run rather than on a rolled-back probe.

SELECT public.ottoq_assert_dispatch_time_coherence('71942fbf-76ee-4b99-9065-c9164a714993')
         AS coherence_verdict;

-- ══ 3. THE FIVE KPIs, VERBATIM, AND THE HONEST READING OF THEM ═════════════
--
-- Recorded before interpretation, because a figure computed from `class='engine'` tables is gone
-- the moment the next demo run starts (CLAUDE.md Part 3's 2026-09-20 refresh: cite the run, never
-- the table).
--
--   asset_hours_available_per_day          2026-09-20: 46.06
--   service_point_turns_per_point_per_day  2026-09-20: 2.78
--   peak_site_kw                           1150.2      (peak_site_kw_demand 1729.5)
--   touch_events_per_turn                  0.252
--   p95_time_to_service_min                147.7       (p50 1.5)
--   returns_unserved                       12
--
--   run_key.config_hash   1f6a3be3bb825bfc4ce8e267b954668b
--   run_key.engine_hash   cf3622a078f5185da2ca71c8d541a1ce
--   provenance.not_reproducible  []   (all eight metrics reproducible from the run ID)
--
--   audit.asset_hours.horizon_source       run_horizon      <- required; `now()` here would mean
--                                                             the bound is not reproducible
--   audit.asset_hours.hours_clipped_to_window  **+0.52**    <- THE NUMBER. -227.36 pre-fix.
--   audit.asset_hours.dispatches_counted   101, open_at_horizon 1
--   audit.turns  bookings_seen 1092, turns_completed 417, bookings_not_a_turn 675,
--                released_never_occupied 400, released_by_teardown 146, released_no_show 8,
--                points_used_max_day 150, points_with_a_turn_max_day 142
--   audit.touch  touch_events 105 = operator 105 + override 0; override_flag_only 1297
--   audit.p95    dispatches_total 101, admitted 100, returns_measured 88, returns_unserved 12,
--                never_returned 1, max_time_to_service_min 177.3,
--                returned_past_horizon 0, deferred_beyond_horizon 0
--
-- **`hours_clipped_to_window` IS THE TEST, AND IT IS THE ONLY CLEAN ONE HERE.** `0182` added that
-- column so the clipping the KPI performs would be visible in its own payload. A NEGATIVE clip is
-- arithmetically impossible from a coherent world — it is the sum of intervals that ran backwards
-- — so -227.36 was a proof of corruption and +0.52 is a proof of its absence. It needs no
-- baseline, no pairing, and no seed match to read, which is exactly why `0297` nominated it.
--
-- ══ 3b. AND EVERY OTHER FIGURE HERE IS A TREND LOG, NOT A CONTROLLED PAIR ══
--
-- Against `0296` §6's pre-fix figures for `c9b0a87e`:
--
--                                   c9b0a87e (pre)   71942fbf (post)
--   asset_hours_available_per_day          26.64            46.06
--   turns_per_point_per_day                 2.12             2.78
--   peak_site_kw                          1071.8           1150.2
--   peak_site_kw_demand                   1058.0           1729.5
--   touch_events_per_turn                  0.135            0.252
--   p95_time_to_service_min                 71.1            147.7
--   p50_time_to_service_min                  0.8              1.5
--   returns_unserved                          11               12
--   config_hash                       89e34c73…        1f6a3be3…
--   engine_hash                       ec8dfa03…        cf3622a0…
--
-- **DO NOT READ THAT TABLE AS A RESULT.** Three things differ at once and each alone disqualifies
-- it as a controlled comparison:
--
--   (a) **config_hash differs**, so it is not the same experiment. `ottoq_run_config_key` covers
--       scenario, seed, policy, depot, horizon, clock and effective params — and `0396` changed
--       the clock, which is one of its inputs. The config hash was GOING to move; that is the fix
--       landing, not drift.
--   (b) **engine_hash differs**, so it is not the same code. `0396` and `0397` both applied
--       between the two runs, and `0397` was `forces_recert TRUE` as well.
--   (c) **The runs are not the same length.** `71942fbf` logged 1147 ticks across 550 sim-minutes.
--       Several of these metrics are per-day rates computed over a horizon, so a longer run moves
--       them for reasons that have nothing to do with either fix. p95 roughly doubling and
--       asset_hours roughly doubling are consistent with duration alone.
--
-- So the defensible sentence is narrow and it is the one to quote: *"the clock defect is fixed,
-- measured on published output — `hours_clipped_to_window` went from -227.36 to +0.52 and the
-- dispatch-coherence assertion went from 32-of-87 inverted to coherent across all 101. The other
-- KPIs moved too, and nothing here establishes why: the config hash, the engine hash and the run
-- length all changed with them."* A controlled answer needs `ottoq_determinism_pair`-style
-- pairing on one engine_hash, which is `0145`/`0146`'s A/B gap and is not this file's claim.

SELECT jsonb_pretty(public.ottoq_kpi_five('71942fbf-76ee-4b99-9065-c9164a714993')) AS kpi_five;

-- ══ 4. WHAT THIS DOES NOT CLOSE ════════════════════════════════════════════
--
-- `returns_unserved` 12 and `p95_time_to_service_min` 147.7 against a `p50` of **1.5** is a
-- 98x spread between the median and the tail. That shape — almost everything served instantly,
-- a dozen waiting over two hours — is the staging/charging capacity question `0250` and `0264`
-- opened, and `0396` had no reason to touch it. It is not a clock defect and must not be
-- reported as one now that the clock is fixed.
