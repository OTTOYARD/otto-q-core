-- 0392  **G249: a run whose fleet seed fails runs anyway, on the previous run's world. This morning's validation run
--       929e323c was refused its seed by the arm interlock -- a tether the stopped run 11f15672 had left on a car,
--       stamped on 11f15672's clock and judged on 929e323c's -- and `ottoq_sim_run_scenario` wrote `seed_fleet
--       {"ok": false}` into the run's payload and started it. For five sim-hours the engine ran 11f15672's cars.**
--
--       Written on 2026-09-27 (11:50-12:20 UTC, 6:50-7:20 AM CT). Read-only. Found while reading 929e323c for 0390 §4:
--       it opened charges at about half the rate of the three runs before it.

-- ══ §1 THE SEED WAS REFUSED, AND THE START WENT ON ════════════════════════════════════════════════════════════

\echo '=== 0392 §1 — every retained run, by who ran it and whether its fleet seed succeeded ==='
SELECT run_by, payload->'seed_fleet'->>'ok' AS seed_ok, count(*) AS runs, min(started_at) AS first, max(started_at) AS last,
       string_agg(DISTINCT left(payload->'seed_fleet'->>'error', 110), ' | ') AS error
  FROM public.ottoq_sim_runs
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-27 12:10 UTC): 15 operator runs retained, 14 with `seed_fleet.ok = true` and one false: 929e323c,
--   started 11:18:08 UTC, error "arm interlock: vehicle 137ab789-... is held by the arm at stall 9753cfd9-... until
--   2026-09-27 16:32:00+00 (sim 2026-09-27 13:00:00+00, charging/charging) -- refusing to move it to nowhere". The car is
--   Waymo-AV-031 on NASH-DCFC-STALL-08, charging there on 11f15672 from 15:30 sim. Certification and A/B-harness arms
--   carry no `seed_fleet` key: they do not start through this door (§3).
--
--   The chain, each link read from the source:
--   (1) 11f15672 was stopped with `ottoq_sim_mark_stopped` alone (0391 §2(b)), which marks the run and releases nothing.
--       The operator's door, `ottoq_sim_stop_and_reset`, also calls `ottoq_sim_release_depot`, which releases every
--       tether first -- hoisted above its vehicle reset on 2026-08-13 because "the tether is a SIM-CLOCK deadline, so a
--       run stopped at sim 19:30 leaves deadlines in the future of any run that starts at 06:00 ... Left alone, the next
--       run inherits cars its own gate calls immovable."
--   (2) `twin.ottoq_sim_seed_fleet` moves every car (`current_stall_id = NULL`) without releasing tethers. The interlock
--       (`ottoq_arm_interlock_guard`, on `vehicles`) judges a tether against the sim clock of the newest running run --
--       at seed time, the new run's own start, 13:00 -- so 11f15672's deadline of 16:32 read as 3.5 hours in the future.
--   (3) `ottoq_sim_run_scenario` wraps the seed in `EXCEPTION WHEN OTHERS`, records `ok: false` and carries on. The
--       exception rolled back the WHOLE seed -- dispatches, sessions, vehicles, chargers, stalls -- so nothing of the
--       new day was dealt. The run then ticked from 11f15672's end state.

-- ══ §2 WHAT 929e323c RAN ON ═══════════════════════════════════════════════════════════════════════════════════════

\echo '=== 0392 §2(a) — the sessions each run opened in its first 10 sim-minutes, and how many resume a session of 11f15672 ==='
WITH runs AS (SELECT sim_run_id, left(sim_run_id::text, 8) AS run, sim_clock_start FROM public.ottoq_sim_runs
               WHERE left(sim_run_id::text, 8) IN ('caf85837','4bc19d29','c4afb873','929e323c'))
SELECT r.run, st.stall_type::text AS stall, count(*) AS opened_first_10min,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ocpp_sessions o
                                       WHERE o.sim_run_id = '11f15672-bb3b-407d-ba39-90859577d7ec' AND o.vehicle_id = s.vehicle_id
                                         AND o.stall_id = s.stall_id AND o.stopped_reason = 'orphaned_run')) AS resumes_11f15672
  FROM runs r JOIN public.ocpp_sessions s ON s.sim_run_id = r.sim_run_id JOIN public.stalls st ON st.id = s.stall_id
 WHERE s.started_at < r.sim_clock_start + interval '10 minutes'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-27 11:58 UTC): 929e323c opened 30 L2 and 6 DCFC charges in its first 10 sim-minutes, and 33 of the 36
--   are 11f15672's charges picked up again on the same car and stall (27 of 30 L2, 6 of 6 DCFC) -- the 33 sessions its
--   first tick reaped as `orphaned_run` (0391 §1). The three runs before it opened 9-12 L2 and 7-10 DCFC, none resumed.

\echo '=== 0392 §2(b) — the depot fleet at 929e323c sim 12:59 PM: cars stamped at 11f15672 last clock, and whose dispatch they hold ==='
SELECT v.current_state::text AS state, count(*) AS cars,
       count(*) FILTER (WHERE v.current_soc_updated_at = '2026-09-27 16:30:00+00') AS soc_last_set_on_11f15672_last_tick,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ottoq_vehicle_dispatches d WHERE d.vehicle_id = v.id
                                         AND d.sim_run_id = '11f15672-bb3b-407d-ba39-90859577d7ec'
                                         AND d.status IN ('active','returning'))) AS holds_an_open_11f15672_dispatch
  FROM public.vehicles v
 WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
 GROUP BY 1 ORDER BY 2 DESC;
-- READ (2026-09-27 11:58 UTC, sim 12:59 PM CT, 289 sim-minutes in; this query now reads the stopped depot, so the
--   numbers are kept here): 116 cars. 11 of them had been out of the run since it began:
--     en_route_to_depot  5   SoC last set at 16:30:00 (11f15672's final clock), each holding 11f15672's `returning`
--                            dispatch (scheduled back at 16:31-16:32 on 11f15672's clock) and no dispatch of 929e323c's
--     deployed           6   the same, with 11f15672's `active` dispatches
--   929e323c lands and recalls cars through its own dispatches only, so the five were "on their way" for five sim-hours
--   and the six never came back.

\echo '=== 0392 §2(c) — the ten fast chargers at 929e323c sim 12:59 PM ==='
-- Read before the stop and kept here (the stop clears the pointers):
--     DCFC-01, -02, -05, -06   status available, charger Available, `reserved_by` Zoox-AV-078, -081, -087, Tesla-AV-049
--                              -- four of the five en-route cars -- reserved at 13:07:23 sim, seven minutes into the
--                              run, until 18:41:23: 5 h 34 min. 0 sessions on any of the four in the whole run.
--     DCFC-07                  reserved the same way for the fifth, Waymo-002, from 13:41; 1 session, at 13:07.
--     DCFC-08, -09             Faulted since 16:00 and 16:14.
--     DCFC-03, -04, -10        charging.
--   So from its second tick the run had at most five usable fast chargers, and by 11 AM sim one or two.

\echo '=== 0392 §2(d) — charges opened per sim hour, 929e323c against the three runs before it ==='
WITH runs AS (SELECT sim_run_id, left(sim_run_id::text, 8) AS run, sim_clock_start FROM public.ottoq_sim_runs
               WHERE left(sim_run_id::text, 8) IN ('caf85837','4bc19d29','c4afb873','929e323c'))
SELECT r.run, floor(extract(epoch FROM s.started_at - r.sim_clock_start) / 3600)::int AS sim_hour, count(*) AS opened,
       count(*) FILTER (WHERE st.stall_type::text = 'dcfc') AS dcfc, count(*) FILTER (WHERE st.stall_type::text = 'l2') AS l2
  FROM runs r JOIN public.ocpp_sessions s ON s.sim_run_id = r.sim_run_id JOIN public.stalls st ON st.id = s.stall_id
 WHERE s.started_at < r.sim_clock_start + interval '5 hours'
 GROUP BY 1, 2 ORDER BY 1, 2;
-- READ (2026-09-27 12:12 UTC), sim hours from 8 AM CT:
--     929e323c   38 / 6 / 10 / 12 / 13     (DCFC 8 / 4 / 4 / 5 / 3)
--     4bc19d29   50 / 21 / 20 / 17 / 17    (DCFC 14 / 9 / 10 / 10 / 7)
--     caf85837   55 / 26 / 13 / 4          (stopped at 11:14 AM sim)
--     c4afb873   55 / 26                   (stopped at 9:55 AM sim)
--   The L2 row was full from the first quarter hour (30 of 30 busy at 8:15, against 12-13 on the others), with charges
--   carried over from 11f15672, and the DCFC row was short five chargers held for cars that never arrived.

-- ══ §3 HOW OFTEN THIS CAN HAPPEN ══════════════════════════════════════════════════════════════════════════════════
--
--   A seed meets a live tether whenever the run before it ended without releasing the depot. Two paths do that:
--   (a) a stop through `ottoq_sim_mark_stopped` alone. Nothing but `ottoq_sim_stop_and_reset` calls it, so this is a
--       stop by hand -- as here, by me. Still a live door: it is callable, it answers `true`, and it leaves the depot as
--       the run had it.
--   (b) `ottoq_sim_run_scenario`'s own supersede. A start at a depot with a running run marks that run `completed` with
--       a bare UPDATE -- no release, no archive. The control edge function's start calls this door directly (to stay
--       inside PostgREST's statement timeout), as does `ottoq_start_demo_run` (`ottoq_start_busy_run` through it). The cockpit shows
--       Start only while it knows of no run, but a second client, the edge API or a runbook start does not ask. On a busy
--       run a tether is almost always live (every car on a DCFC charges tethered: 3 of 3 at 929e323c's stop), so a start
--       that supersedes a busy run would almost always be refused its seed -- and would run anyway.
--   Certification and A/B-harness arms do not pass through either door (`ottoq_determinism_pair` resets the fleet itself;
--   no function but `ottoq_start_demo_run` calls `ottoq_sim_run_scenario`, and nothing but it calls the seed), so no
--   certified or dial-pair number is touched.
--
--   (c) AND ONE MORE COPY OF A FIXED BUG, in the seed, not reached today because the seed failed: it closes the depot's
--   open twin sessions with `ended_at = COALESCE(ended_at, NOW())` -- a wall clock in a sim column, the fallback 0357
--   removed from `ottoq_sim_release_depot` and not from here. On 929e323c's start it would have stamped 33 charges begun
--   at 15:30-16:30 sim with an end of 11:18 real.

-- ══ §4 WHAT 929e323c's READS ARE WORTH ═════════════════════════════════════════════════════════════════════════
--
--   0390 §4(a)(b) is a per-car rule -- whether the sensors start work only on a car on a charger -- and the starter
--   applies it to whatever car is in front of it, so it held on this run as on any: 43 sensor starts, 14 on a DCFC and 29
--   on an L2, every one on a stall the car had a session on, none on staging, in a bay or on no stall (READ 11:55 UTC).
--   That is kept as a read of the rule, not of the run. Throughput, waits and the charge evidence from 929e323c describe
--   11f15672's leftovers and are quoted nowhere. The run selectors in 0390 §4 and 0388 §4 now skip a run whose seed failed.

-- ══ §5 STOPPED, AND STARTED AGAIN ═════════════════════════════════════════════════════════════════════════════════
--
--   929e323c stopped through `ottoq_sim_stop_and_reset` at 12:00 UTC (7:00 AM CT): 32 sessions closed as `sim_reset` on
--   its own clock, 116 cars unplaced, 0 tethers, 0 stall pointers left. The 11 open 11f15672 dispatches survived the
--   release (it closes only its own run's) and the next seed aborted them, as the seed is written to.
--   6ddd827e started at 12:02 UTC with live playback at 8x: `seed_fleet.ok = true`, 0 open dispatches of another run,
--   0 cars stamped at 11f15672's clock. It is the validation run 0390 §4 and 0388 §4 now read.

-- ══ §6 THE FIX: 0524 ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) The seed releases every tether at the depot before it moves a car, as the release door does. A seed deals a new
--       day; no arm of the old one is holding anything in it.
--   (2) The seed closes a leftover open session on its own run's last clock, as `sim_reset` -- the release door's rule.
--   (3) A start that finds a live run at the depot stops it through `ottoq_sim_stop_and_reset`, so a start is a stop and
--       a start, never a relabel.
--   (4) A seed that still fails stops the start: `ottoq_sim_run_scenario` raises, the transaction rolls back, and the
--       caller sees why. No run exists that says it is a scenario's day and is not.
--   APPLIED `20260927131711` (2026-09-27 13:17 UTC, 8:17 AM CT), once 6ddd827e had ended, after a full dry run with no run
--   live: P2, both patches, V1 and all three V3 cases passed -- (a) a start over a car planted on a DCFC stall with a 2099
--   tether and an open charge of the last operator run: the seed succeeded, the tether was gone, the charge was
--   `cancelled`/`sim_reset` at that run's own last clock; (b) a second start stopped the first through the stop door
--   (archived, noted, `failure_reason` the supersede) and ran seeded, with the transaction no longer pinned to the first;
--   (c) a planted refusal of the seed's move made the start raise "fleet seed failed at depot ..., so no run was
--   started", with no new run and the live one still running. The ledger's statement md5 matches the file.
