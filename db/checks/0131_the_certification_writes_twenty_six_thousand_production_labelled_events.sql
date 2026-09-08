-- ---------------------------------------------------------------------------
-- 0131 — G16, CONVICTED, and it is larger than the task line said.
--
--   The task line: "arm B's boot writes are stamped with arm A's run id
--   (teardown pins the GUC and nothing re-points it)."
--
--   That is true, and it is the SMALLER half. The larger half is what happens
--   on arm A, where the GUC is not yet set at all: the certification harness
--   writes **26,740 HMAC-signed events labelled `data_source = 'production'`**
--   into ottoq_events. They are not production. They are the harness resetting
--   the fleet, and they have been accumulating since at least 2026-09-01.
--
-- Traced 2026-09-08 12:30 UTC against gxdrcyphqjzjsuhxuqtg, read-only, while
-- round 26 was in flight. Nothing here was fixed; a migration during a round is
-- forbidden and this needs a decision anyway (Q7).
-- ---------------------------------------------------------------------------

-- Q1. THE ARM LOOP, from the live body of public.ottoq_determinism_pair:
--
--       FOR v_arm IN 1..2 LOOP
--         PERFORM ottoq_tick_invariance_reset_fleet(p_depot, p_seed, p_sim_start);  <-- (1)
--         v_run := twin.ottoq_sim_start_run(...);                                   <-- (2)
--         PERFORM twin.ottoq_sim_prime_deployment(v_run, ...);
--         v_boot := ottoq_boot_state_fingerprint(p_depot, v_run);
--         ... PERFORM ottoq_sim_advance_tick(v_run); ...
--         v_arms := v_arms || v_h;
--         PERFORM ottoq_sim_stop_and_reset(v_run, 'determinism_arm_complete');      <-- (3)
--       END LOOP;
--
--     Both arms run in ONE transaction, and the run identity is carried in a
--     transaction-local GUC, `ottoq.sim_run_id`:
--
--       (2) twin.ottoq_sim_start_run     set_config('ottoq.sim_run_id', v_run_id, true)
--       (3) public.ottoq_sim_stop_and_reset
--                                        set_config('ottoq.sim_run_id', p_sim_run_id, true)
--
--     (3) sets the GUC to the run it is tearing down and leaves it there. So at
--     step (1):
--
--       arm A — the GUC is unset. ottoq.ottoq_active_sim_run_id() falls back to
--               "the most recent run with status='running'", finds none (the
--               harness asserts that before a round), returns NULL — and by
--               0092's rule does NOT cache the miss.
--       arm B — the GUC still holds ARM A's run id.
--
--     Nothing between (3) and the next iteration's (1) re-points or clears it.
SELECT n.nspname||'.'||p.proname AS fn,
       (SELECT string_agg(m[1], ' | ') FROM regexp_matches(p.prosrc, '(set_config\([^;]{0,90})', 'g') m) AS sets
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE (n.nspname,p.proname) IN (('twin','ottoq_sim_start_run'),
                                ('public','ottoq_sim_stop_and_reset'),
                                ('public','ottoq_sim_advance_tick'));

-- Q2. WHAT READS THE GUC AT STEP (1). ottoq_tick_invariance_reset_fleet updates
--     `vehicles`, which fires public.ottoq_vehicles_state_change — a trigger
--     whose FIRST statement is `v_run := ottoq.ottoq_active_sim_run_id();` and
--     whose event write is:
--
--       p_data_source := CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END,
--       p_sim_run_id  := v_run
--
--     So the trigger does not merely mis-file the row. It reclassifies it. A
--     NULL run does not mean "unknown provenance" here; it means PRODUCTION.
SELECT n.nspname||'.'||p.proname AS fn, l.lanname
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_language l ON l.oid=p.prolang
WHERE p.prokind IN ('f','p') AND n.nspname IN ('public','twin','ottoq')
  AND p.prosrc LIKE '%active_sim_run_id%' AND p.proname <> 'ottoq_active_sim_run_id'
ORDER BY 1;

-- Q3. THE ASYMMETRY, MEASURED. Pair a of round 26, started 11:35:00.068802 UTC,
--     the two arms side by side:
--
--       sim_run_seq   run                  veh_state (trigger)   stall_state
--              2087   f644ee8f-…                        2,303          1,335
--              2088   ff4fb102-…                        2,187          1,335
--       ------------------------------------------------------------------
--       difference                                       +116              0
--
--     Arm A's run carries **exactly 116 more** vehicle state-change events than
--     arm B's. Stalls are identical, so the reset moves vehicle state and not
--     stall state. 116 is arm B's fleet reset, written into arm A's run.
WITH pair AS (
  SELECT sim_run_id, sim_run_seq FROM public.ottoq_sim_runs
  WHERE started_at = '2026-09-08 11:35:00.068802+00' ORDER BY sim_run_seq
)
SELECT p.sim_run_seq, p.sim_run_id,
       count(*) FILTER (WHERE e.event_type='vehicle.state_changed' AND e.ingest_source='trigger') AS veh_state_trigger,
       count(*) FILTER (WHERE e.event_type='stall.state_changed'   AND e.ingest_source='trigger') AS stall_state_trigger
FROM pair p LEFT JOIN public.ottoq_events e ON e.sim_run_id = p.sim_run_id
GROUP BY 1,2 ORDER BY 1;

-- Q4. AND THE OTHER 116 ARE LABELLED PRODUCTION. Same window, the two pairs of
--     round 26 that had run by 12:16:
--
--       recorded_at (UTC)              data_source    rows   distinct vehicles
--       2026-09-08 11:35:00.068802     production      116                 116
--       2026-09-08 11:54:00.153151     production      116                 116
--
--     Those two timestamps are the transaction-start instants of r26_a and
--     r26_b. 116 rows, 116 distinct vehicles, one instant: that is a bulk
--     UPDATE inside one transaction, not a telemetry feed.
SELECT recorded_at AT TIME ZONE 'UTC' AS recorded, data_source, count(*) AS n,
       count(DISTINCT entity_id) AS distinct_vehicles
FROM public.ottoq_events
WHERE recorded_at > now() - interval '80 minutes'
  AND event_type='vehicle.state_changed' AND ingest_source='trigger'
  AND data_source='production'
GROUP BY 1,2 ORDER BY 1;

-- Q5. THE TOTAL. Not a rounding error and not new:
--
--       production-labelled vehicle.state_changed trigger events   26,740
--       first                                       2026-09-01 00:04:00 UTC
--       last                                        2026-09-08 11:54:00 UTC
--       distinct recorded_at instants                                  245
--       -> 109 rows per instant
--
--     245 instants for 26,740 rows means every row shares its timestamp with
--     about 108 others. A live feed does not look like that; a per-pair bulk
--     reset does.
--
--     A CORRECTION, made here rather than left standing. The first draft of
--     this paragraph said these rows survive the nightly purge BECAUSE they are
--     labelled production. That is false, and reading the purge worker says so:
--
--       DELETE FROM public.ottoq_events e
--        WHERE e.occurred_at >= v_from AND e.occurred_at <= v_batch_ts
--          AND e.occurred_at <  v_cut
--          AND (e.sim_run_id IS NULL OR NOT (e.sim_run_id = ANY (v_live)))
--
--     A NULL sim_run_id is explicitly INCLUDED in what the purge deletes. These
--     rows are not exempt; they are simply newer than the cutoff. So 26,740 is
--     ONE RETENTION WINDOW'S WORTH, a steady state rather than a total, and the
--     "since 2026-09-01" start date is the retention horizon, not the date the
--     defect began. That makes the finding smaller than the first draft implied
--     and it is recorded in that direction on purpose: the ongoing rate — about
--     109 mislabelled signed events per pair, forever — is the real claim, and
--     it does not need the total to be inflated.
SELECT count(*) AS production_veh_state_events,
       min(recorded_at) AT TIME ZONE 'UTC' AS first,
       max(recorded_at) AT TIME ZONE 'UTC' AS last,
       count(DISTINCT recorded_at) AS distinct_batches,
       round(count(*)::numeric / NULLIF(count(DISTINCT recorded_at),0), 1) AS rows_per_batch
FROM public.ottoq_events
WHERE event_type='vehicle.state_changed' AND ingest_source='trigger' AND data_source='production';

-- Q6. WHY NO ROUND HAS EVER FAILED ON IT, which is the part worth sitting with.
--
--     h_evt for an arm is computed at the END of that arm, over rows scoped to
--     that arm's run. Work through both arms:
--
--       arm A's reset events   sim_run_id NULL      -> outside R_A's scope
--       arm A's h_evt          computed here
--       arm B's reset events   sim_run_id = R_A     -> outside R_B's scope, and
--                                                      written AFTER R_A was hashed
--       arm B's h_evt          computed here
--
--     Both arms exclude their own reset events, symmetrically, and arm B's
--     contamination of R_A lands after R_A's hash is already taken. The defect
--     is invisible to the verdict BY CONSTRUCTION, not by luck. No amount of
--     re-running the certification would have found it — which is the argument
--     for reading the engine as well as running it.
--
--     It is also why 0139's blind-spot doctrine does not catch this: an atom
--     can only see what is inside its own run scope, and this defect is
--     precisely a row landing outside it.

-- Q7. WHAT TO DO, with the consequence of each stated rather than a preference.
--
--     TWO REAL COSTS, both outside the verdict:
--
--     (a) PROVENANCE. 26,740 signed events assert `data_source='production'`
--         about work the harness did. CLAUDE.md 2.8 makes data_source the one
--         thing that separates twin from real telemetry in shared tables — "it
--         is what makes sim and real telemetry indistinguishable to the metrics
--         layer, which is the point." Rows that lie about which side they came
--         from are the failure mode that discipline exists to prevent, and they
--         carry an HMAC signature that attests to them either way.
--     (b) REPLAY. Arm A's archived run holds 116 vehicle state changes arm A
--         never made. ottoq_run_archives is "the reproducibility key"; a replay
--         of R_A from its own event stream diverges from R_A.
--
--     FIX 1 — SUPPRESS. Have ottoq_tick_invariance_reset_fleet mark its updates
--     as harness scaffolding (a transaction-local GUC the two state-change
--     triggers honour) so the reset emits no events at all. A fleet reset is
--     harness setup, not telemetry, and nothing downstream wants it.
--     **This is hash-neutral, and Q6 is the proof**: neither arm's h_evt
--     contains its own reset events today, so removing them changes no atom on
--     any column. That is a falsifiable prediction, and the round that follows
--     is what judges it.
--
--     FIX 2 — RE-POINT. Move the reset after twin.ottoq_sim_start_run, or pass
--     the run id in, so both arms' reset events are correctly attributed to the
--     arm that made them. This is CORRECT but NOT hash-neutral: it adds ~116
--     events to every arm's own run scope, so **every column's h_evt moves** and
--     the change is forces_recert TRUE. That is not an objection — a canon
--     should move when the thing it describes changes — but it must be declared
--     in advance rather than discovered.
--
--     They are not exclusive: FIX 1 first, because it is free and stops the
--     bleeding; FIX 2 only if someone wants the reset to be part of the record,
--     which is a product decision about what the twin's event stream is FOR.
--
--     WHAT NEITHER FIXES: the 26,740 rows already written. They are signed, and
--     the signature covers the mislabel. Re-labelling them invalidates the
--     signature; deleting them is a deletion from the audit ledger. That is
--     Chase's call, not the build track's, and it belongs on the founder list
--     next to S-01/S-02 rather than in a migration.
SELECT 'see Q1-Q6 above; this file changes nothing' AS status;
