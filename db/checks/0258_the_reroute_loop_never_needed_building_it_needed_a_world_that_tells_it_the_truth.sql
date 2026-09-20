-- 0258  THE REJECTION -> RE-SOLVE LOOP ALREADY EXISTED, ALREADY RAN, AND WAS
--       BEING REFUSED ITS OWN LEGAL MOVES BY EXPIRED RESERVATION POINTERS.
--
-- Read-only. The before-picture for migration 0367 (G82), the proof of the defect
-- it fixes, and the across-run purge witness that closes G72's remaining limit.
-- Scope: twin depot 11111111-1111-1111-1111-111111111111 only (CLAUDE.md rule 8).
--
-- Chase asked for a loop: "loops accordingly if anything is rejected at any stage
-- or needs re-optimization." The loop was already there. What follows is why it
-- looked like it wasn't.
--
-- ══ 1. THE DEFECT: A RECLAIMER WIRED INTO A FUNCTION THE ENGINE NEVER CALLS ══
--
-- 0360 (applied 20260920022145) added `ottoq_release_unusable_reservations` and
-- called it from `public.ottoq_sim_advance_tick`, one line above
-- `ottoq_sim_decide_and_dispatch`. `ottoq_demo_metronome` -- cron job 12, which
-- IS the live simulation engine -- calls, at its own lines 100 and 108:
--
--   SELECT out_sim_clock_after INTO v_advanced FROM public.ottoq_sim_advance_tick_world(...)
--   PERFORM public.ottoq_sim_decide_and_dispatch(...)
--
-- and never `ottoq_sim_advance_tick`. So the reclaimer had never executed on a
-- metronome-driven run. This is G77's own pattern -- the correct routine with no
-- live caller -- reproduced inside the migration that was fixing G77.
--
-- Q1 is the caller test written so it cannot be fooled the way the original was.

SELECT p.proname,
       position('ottoq_sim_advance_tick('       in p.prosrc) AS calls_advance_tick,
       position('ottoq_sim_advance_tick_world(' in p.prosrc) AS calls_advance_tick_world,
       position('ottoq_sim_decide_and_dispatch(' in p.prosrc) AS calls_decide_and_dispatch,
       --: THE TRAP. The bare name matches the _world variant, of which it is a
       --: PREFIX. This column is why the wiring was believed correct: it reads
       --: 4179 for the metronome, and 4179 is the offset of the WRONG function.
       position('ottoq_sim_advance_tick'        in p.prosrc) AS bare_name_misleading
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_demo_metronome', 'ottoq_cron_tick',
                     'ottoq_sim_advance_tick', 'ottoq_sim_decide_and_dispatch')
 ORDER BY p.proname;

-- Third instance of one mistake class in this repo: `_` as a LIKE wildcard
-- (0360's GC check), raw prosrc versus comment-stripped executable SQL (0360
-- Part B), and now a bare function name versus a call. **A caller check must
-- match the call syntax.** All three read as evidence and were not.
--
-- ══ 2. WHAT IT COST, ON RUN 3fb415d8-3e06-4084-9436-7248f6c40449 ════════════
--
-- cuOpt-only arm, seed 777777, busy_day, twin depot, speed 8.0, stopped by the
-- governor at the 540 sim-minute ceiling after 1,245 ticks. This run has since
-- been purged (see section 4), so its figures are recorded here, in git, which is
-- the only durable place they can live -- the 0256 / G72 discipline.
--
--   ottoq.refusal_escalated events                            393
--     over ticks                                            1,245
--     rate                                             0.316/tick
--     of the first 346: reason_code='no_capacity'
--       after original_refusal='target_occupied'              296   (86%)
--     the rest: superseded 32, vehicle_state_incompatible 16,
--               command_malformed 3, vehicle_unresponsive 1
--
--   release-eligible reservations standing, mid-run             38
--     across a tick boundary (tick 1123 -> 1124)          38 -> 38   <- never reclaimed
--
--   DCFC stalls the reroute walk found CALENDAR-free              4
--     of those, unclaimed by reservation or vehicle              0
--     their reservations, past expiry by                  36-45 min (SIM clock)
--     of those 4, holding no vehicle at all                      2
--
--   L2 stalls calendar-free                                      0   <- genuine
--   staging stalls calendar-free / truly unclaimed          25 / 11
--
-- So `no_capacity` was conflating two different worlds: on L2 the calendar
-- genuinely had nothing, and on DCFC the calendar had four and the reservation
-- pointer refused all four. The escalation event records neither -- same defect
-- family as G71 (a refusal reason read as a verdict) and G78 (an abstention
-- scored as a miss).
--
-- ══ 3. AND THE LOOP WAS WORKING THE WHOLE TIME ══════════════════════════════
--
-- `ottoq.ottoq_react_to_refusals(sim_run, depot, clock)` is called from
-- `ottoq_sim_decide_and_dispatch` (its line 121, inside the placement-reconcile
-- block). For a refused `proceed_to_stall` / `begin_charge` / `stage` carrying
-- `target_occupied` or `resource_faulted` it:
--
--   1. derives the wanted stall_type and booking purpose from the command,
--   2. excludes the arrival_inspection zone for parking holds so a reroute cannot
--      eat inspection capacity,
--   3. walks up to 25 calendar-free stalls (`ottoq_stall_free_between` over a
--      60-minute window), reserve-first because the legacy pointer is the
--      scarcer gate,
--   4. books through `ottoq_book_stall` and re-emits the command with
--      `reroute_after` and `reroute_reason`,
--   5. has a last-resort pass into arrival_inspection for parking only, so a
--      refused vehicle is never stranded,
--   6. stamps `reacted_at` and writes the outcome into the command's own payload,
--
-- and escalates to `no_capacity` ONLY when every candidate fails
-- `ottoq_reserve_stall`. That is a funnel with a loop in it, already built. Q3
-- reads its own success rate from the commands it stamped -- no new instrument
-- needed, because step 6 records the answer.

-- AND THE DENOMINATOR IS THE WHOLE POINT, so it is written down rather than
-- chosen. The reactor can only reroute `target_occupied` / `resource_faulted` on
-- `proceed_to_stall` / `begin_charge` / `stage`; a `superseded` or
-- `vehicle_state_incompatible` refusal it escalates is the reactor being CORRECT.
-- The first reading of this rate divided by all 31 refusals on run 5b37ee46 and
-- reported 6.5%; 24 of those 31 were not reroutable at all and the honest figure
-- was 2 of 7. That is G78's defect -- an honest refusal scored as a miss --
-- committed by me, on the instrument measuring the fix. Split, always.

SELECT r.sim_run_id, r.tick_count,
       count(*) FILTER (WHERE c.status = 'refused')                                   AS refused_all,
       count(*) FILTER (WHERE c.status = 'refused'
                          AND c.reason_code IN ('target_occupied','resource_faulted')
                          AND c.command_type IN ('proceed_to_stall','begin_charge','stage')) AS reroutable,
       count(*) FILTER (WHERE c.payload->'reaction'->>'action' = 'rerouted')           AS rerouted,
       count(*) FILTER (WHERE c.payload->'reaction'->>'reason'  = 'no_capacity')       AS escalated_no_capacity,
       count(*) FILTER (WHERE c.status = 'refused'
                          AND c.reason_code NOT IN ('target_occupied','resource_faulted')) AS not_reroutable_by_design,
       --: the ONLY honest success rate: rerouted over the reroutable class
       round(100.0 * count(*) FILTER (WHERE c.payload->'reaction'->>'action' = 'rerouted')
             / NULLIF(count(*) FILTER (WHERE c.status = 'refused'
                          AND c.reason_code IN ('target_occupied','resource_faulted')
                          AND c.command_type IN ('proceed_to_stall','begin_charge','stage')), 0), 1)
                                                                                       AS reroute_success_pct,
       --: 0368 makes this readable: what the walk looked for, and how many it saw
       count(*) FILTER (WHERE c.payload->'reaction'->>'stall_type_source' = 'target_stall') AS type_from_target_stall,
       count(*) FILTER (WHERE c.payload->'reaction'->>'stall_type_source' = 'command_type_default') AS type_guessed
  FROM public.ottoq_sim_runs r
  LEFT JOIN public.ottoq_vehicle_commands c ON c.sim_run_id = r.sim_run_id
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY r.sim_run_id, r.tick_count, r.started_at
 ORDER BY r.started_at DESC;

-- ══ 4. THE PURGE WITNESS G72 WAS MISSING (closes 0257 section 5) ═════════════
--
-- 0257 could only say the disposition ledger was *registered* to survive a demo
-- run, not that it had. Starting run `5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10`
-- (`ottoq_start_demo_run('busy_day', 8.0, 1, 777777)`) purged the prior run and
-- converted that. Measured, from the purge's own report and the tables after:
--
--   rows_purged                                            352,673
--   prior_runs_deleted                                           1
--   evidence_preserved                                         177
--   ottoq_external_proposals cleared                            24   <- the working set
--   ottoq_proposal_disposition_ledger in cleared_by_table      absent
--
--   ledger rows before the purge                                12
--   ledger rows after                                           12
--   of those, rows whose sim_run_id is the DELETED run           12
--   the deleted run still present in ottoq_sim_runs               0
--   ottoq_model_call_ledger (0340) before / after       3,318 / 3,318
--
-- Twelve outcome rows survive a purge that deleted the run they describe and the
-- working-set rows they were captured from. That is the property, observed.

SELECT (SELECT count(*) FROM public.ottoq_proposal_disposition_ledger) AS ledger_rows,
       (SELECT count(*) FROM public.ottoq_proposal_disposition_ledger l
         WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                            WHERE r.sim_run_id = l.sim_run_id))        AS rows_outliving_a_deleted_run,
       (SELECT count(*) FROM public.ottoq_model_call_ledger)           AS model_call_ledger_rows,
       (SELECT class FROM public.ottoq_run_scope_registry
         WHERE table_name = 'ottoq_proposal_disposition_ledger' LIMIT 1) AS registry_class;

-- ══ 5. THE AFTER-PICTURE OF 0367 ════════════════════════════════════════════
--
-- Immediate effect, measured 4 minutes after 0367 applied, on the tail of run
-- 3fb415d8 (so the reclaimer was live for roughly its last 16 ticks):
--
--   release-eligible reservations          38 -> 1
--   unclaimed stalls (all types)           11 -> 41
--   unclaimed charge-type stalls (dcfc+l2)  0 -> 1
--   ottoq.reservation_reclaim_blocked events     0   <- no deadlock, no silence
--
-- The escalation-rate comparison needs a full paired run, not a tail. Run
-- `5b37ee46` is that run: identical seed (777777), scenario (busy_day), depot and
-- speed (8.0), with the reclaimer live from tick 1. Baseline to beat: **0.316
-- escalations per tick**.
--
-- ONE DIFFERENCE HELD, NOT HIDDEN: 0365 and 0366 applied mid-way through
-- 3fb415d8 and are live from tick 1 on 5b37ee46. Their engine effect is nil by
-- construction -- 0365 adds a read-only instrument with no caller on the tick
-- path, and 0366 adds `occupies_charge_stall_unbooked` to the decision frame,
-- which only `proposer/forward_proposer.py` reads and which is not running in
-- either arm. 0364 adds an evidence-only capture trigger. So the engine delta
-- between these two runs is 0367 and nothing else.
--
-- Q5 is the comparison, to be read once 5b37ee46 has ticks behind it.

SELECT r.sim_run_id, r.status, r.tick_count,
       round(EXTRACT(epoch FROM (r.sim_clock_current - r.sim_clock_start))/60.0, 1) AS sim_minutes,
       (SELECT count(*) FROM public.ottoq_events e
         WHERE e.sim_run_id = r.sim_run_id
           AND e.event_type = 'ottoq.refusal_escalated')                             AS escalations,
       round((SELECT count(*) FROM public.ottoq_events e
               WHERE e.sim_run_id = r.sim_run_id
                 AND e.event_type = 'ottoq.refusal_escalated')::numeric
             / NULLIF(r.tick_count, 0), 4)                                           AS escalations_per_tick,
       (SELECT count(*) FROM public.ottoq_events e
         WHERE e.sim_run_id = r.sim_run_id
           AND e.event_type = 'ottoq.reservation_reclaim_blocked')                    AS reclaim_blocked
  FROM public.ottoq_sim_runs r
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
 ORDER BY r.started_at DESC LIMIT 4;

-- ══ 6. TWO THINGS NOTED WHILE DOING THIS, NEITHER FIXED HERE ════════════════
--
-- (a) THE EVENT VOCABULARY IS NOT REGISTERED. `ottoq_event_types_catalog` held
--     137 rows (138 after 0367); run `3fb415d8` emitted 57 distinct event types
--     and **25 of the 57 were absent from the catalog** -- `ottoq.refusal_escalated`
--     among them, which is the single most informative event in this whole
--     investigation. That is C7 step 2's audit and it is real work, not a line
--     item. 0367 registers only the one type it introduces.
--
--     READ Q6 WITH ITS DATE. The 25-of-57 figure is from before the purge that
--     started run 5b37ee46; `ottoq_events` is `class='engine'` for the run scope,
--     so Q6 run today counts only types the CURRENT run has emitted so far and
--     will read far lower. It is a floor, never a total -- the same "cite the run,
--     not the table" rule CLAUDE.md Part 3 states for signed-event counts.
--
-- (b) MIGRATION VERSION HEADERS ARE CHOSEN, NOT MEASURED. 0367's header reads
--     `20260920041500`; it actually applied at about 04:05 UTC. 0364's reads
--     `20260920035200` against a real apply near 03:46. Harmless as an
--     identifier, wrong as a timestamp, and this file is the place it gets said
--     out loud. Derive the version from `now()` at apply time.

SELECT (SELECT count(*) FROM public.ottoq_event_types_catalog) AS catalog_rows,
       (SELECT count(*) FROM (
          SELECT DISTINCT e.event_type AS et FROM public.ottoq_events e
           WHERE e.depot_id = '11111111-1111-1111-1111-111111111111') z
         WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_event_types_catalog c
                            WHERE c.event_type = z.et))              AS unregistered_types_seen;
