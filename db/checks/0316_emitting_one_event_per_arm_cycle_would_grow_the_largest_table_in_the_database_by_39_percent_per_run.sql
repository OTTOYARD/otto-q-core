-- 0316  **The obvious implementation of "put the charge arms in the audit trail" would add ~459 MB
--       to `ottoq_events` PER RUN.** `db/checks/0315` §3 established the gap: `twin.arm_cycles`
--       holds 53,330 rows while `ottoq_events` holds **zero** arm or tether rows, so the arms — the
--       busiest subsystem in the twin — never reach the decision log, the activity feed, or Chase's
--       audit trail. This file is the sizing that decides HOW to close it, written before the fix
--       rather than after, because the natural implementation is the wrong one.
--
-- ══ THE MEASUREMENT ════════════════════════════════════════════════════════
--
-- Measured 2026-09-21 19:48 UTC (14:48 CT) on the twin depot:
--
--     ottoq_events          138,136 rows        1,188 MB      ~8.6 KB PER ROW
--     database total                            5,998 MB
--     twin.arm_cycles        53,330 rows
--
-- `ottoq_events` is already **~20% of the entire database**, and its rows are enormous — the
-- `payload->'diff'` of a `vehicle.state_changed` carries the whole before/after config object, which
-- is where 8.6 KB an event comes from.
--
-- **So one event per arm cycle costs 53,330 x 8.6 KB = ~459 MB for a single run.** That is a **39%
-- increase in the largest table in the database**, and ~8% of the whole database, to record one
-- run's worth of arms mating and demating. A second run doubles it. This is not a tuning concern;
-- it is the difference between a feature and an outage.
--
-- ══ WHY THIS IS EASY TO GET WRONG ══════════════════════════════════════════
--
-- The instruction "emit arm events into ottoq_events" reads as a one-line change, and the arm state
-- machine already has the obvious hook points: `twin.ottoq_arm_begin_cycle` (called by
-- `ottoq_sim_start_charge_session` and `stop_charge_session`) and `twin.ottoq_arm_advance_cycles`
-- (called from `public.ottoq_sim_advance_tick_world`, the tick path itself). Adding
-- `PERFORM ottoq_record_event(...)` to either is three lines and would look correct in review.
--
-- **The volume is invisible at the call site.** Nothing in `ottoq_arm_advance_cycles` suggests it
-- runs 53,330 times a run, because it advances every open cycle every tick — the multiplication is
-- between the tick count and the fleet, and neither is in view when you are editing it.
--
-- ══ THE DESIGN THAT FITS, AND IT IS ALREADY THIS REPO'S PATTERN ════════════
--
-- Split by whether a human would ever want the individual row:
--
--   **(a) EXCEPTIONS, one event each.** `fault` (85 per run) and `emergency_released` (85). These
--        are the rows an audit trail exists for, and at ~170 events/run they cost ~1.5 MB.
--
--   **(b) EVERYTHING ELSE, one summary event per tick**, carrying counts: mates begun, latched,
--        demates begun, cleared, abandoned. ~600 ticks/run = ~600 events = ~5 MB.
--
-- **Total ~7 MB per run instead of ~459 MB — a 65x reduction** with no loss of anything anyone
-- would read. And it is not a novel invention: `twin.deploy_gate_summary` and
-- `twin.staging_overflow` already do exactly this, emitting one summary per tick with counts in the
-- payload rather than one event per affected vehicle. The arms should follow the convention the
-- twin already has rather than inventing a louder one.
--
-- **`abandoned` (3,127 per run) is deliberately in the summary, not individual**, and that is a
-- judgement worth stating: an abandoned cycle means "overtaken by events", which
-- `ottoq_arm_begin_cycle`'s own comment describes as the normal consequence of a stall's robot being
-- asked to do a second thing. It is a rate to watch, not an incident to read. If that rate ever
-- needs per-row forensics the summary will show it rising first.
--
-- ══ WHAT IS NOT DECIDED HERE, AND MUST NOT BE GUESSED ══════════════════════
--
-- **Whether `vehicles.robotic_tether_*` populates DURING a live run is still unknown**, and it is
-- the more important question for what Chase actually saw, because those columns — not
-- `ottoq_events` — are what a renderer binds to. `0315` §3d records why the current reading proves
-- nothing: every one of the 53,330 cycles is closed, so NULL is the correct post-run value.
-- Answering it needs a mid-run sample. **If the renderer's binding turns out to be populated, then
-- the arms are not invisible at all and this whole event question is about the audit trail only.**
-- Do not build the renderer fix before taking that sample.
--
-- **Not applied.** Adding events changes the events atom, which is one of the fourteen, so the fix
-- is `forces_recert` TRUE. `0400`/`0401`/`0407` landed 19:12–19:38 UTC and the recert runner is
-- mid-sweep on them (3 of 9 canon columns back to current at this reading). Adding a fourth
-- invalidating change now would discard that work in flight for no gain.

\echo '=== 0316 §1 — the sizing that decides the design ==='
SELECT (SELECT count(*) FROM public.ottoq_events)                                  AS event_rows,
       pg_size_pretty(pg_total_relation_size('public.ottoq_events'))               AS events_size,
       pg_size_pretty(pg_database_size(current_database()))                        AS database_size,
       round(100.0 * pg_total_relation_size('public.ottoq_events')
             / NULLIF(pg_database_size(current_database()),0), 1)                  AS pct_of_database,
       round(pg_total_relation_size('public.ottoq_events')
             / NULLIF((SELECT count(*) FROM public.ottoq_events),0) / 1024.0, 1)   AS kb_per_event;
-- EXPECT ~138k rows / ~1,188 MB / ~20% of the database / ~8.6 KB per event.

\echo '=== 0316 §2 — what one-event-per-cycle would have cost ==='
SELECT (SELECT count(*) FROM twin.arm_cycles) AS arm_cycles,
       pg_size_pretty(
         ((SELECT count(*) FROM twin.arm_cycles)
          * (pg_total_relation_size('public.ottoq_events')
             / GREATEST((SELECT count(*) FROM public.ottoq_events),1)))::bigint)   AS naive_added_bytes,
       round(100.0 * (SELECT count(*) FROM twin.arm_cycles)
             / GREATEST((SELECT count(*) FROM public.ottoq_events),1), 1)          AS pct_growth_of_events;
-- EXPECT ~459 MB added and ~39% growth, for ONE run.

\echo '=== 0316 §3 — the split: how many rows a human would actually read ==='
SELECT outcome,
       count(*) AS cycles,
       CASE WHEN outcome IN ('fault','emergency_released') THEN 'individual event'
            ELSE 'summary only' END AS proposed_treatment
  FROM twin.arm_cycles
 GROUP BY outcome ORDER BY count(*) DESC;
-- EXPECT latched ~26,956 and cleared ~22,364 -> summary; abandoned ~3,127 -> summary (a rate, not
-- an incident); emergency_released ~85 -> individual. `fault` is a PHASE rather than an outcome on
-- most rows, so §4 counts it separately.

\echo '=== 0316 §4 — the exception volume, which is what makes the split affordable ==='
SELECT count(*) FILTER (WHERE phase = 'fault')                AS fault_phase_rows,
       count(*) FILTER (WHERE outcome = 'emergency_released') AS emergency_released,
       count(DISTINCT sim_run_id)                             AS runs_represented
  FROM twin.arm_cycles;
-- ~170 exception rows per run against 53,330 cycles: ~1.5 MB, versus ~459 MB for all of them.

\echo '=== 0316 §5 — the convention this should follow, not invent ==='
SELECT event_type, count(*) AS n
  FROM public.ottoq_events
 WHERE event_type IN ('twin.deploy_gate_summary','twin.staging_overflow')
 GROUP BY 1 ORDER BY 2 DESC;
-- Both already emit ONE summary per tick with counts in the payload rather than one event per
-- affected vehicle. The arms should look like these.

\echo '=== 0316 §6 — the open question this file refuses to guess ==='
SELECT count(*) FILTER (WHERE robotic_tether_phase IS NOT NULL) AS live_tethers_now,
       (SELECT count(*) FROM twin.arm_cycles WHERE ended_at IS NULL) AS open_cycles_now
  FROM public.vehicles;
-- Both read 0 between runs, and that is CONSISTENT rather than informative: no open cycle means no
-- live tether. Whether the renderer's binding populates mid-run needs a sample taken WHILE a run is
-- ticking. Until then, "the arms do not render" is an observation, not a diagnosis.
