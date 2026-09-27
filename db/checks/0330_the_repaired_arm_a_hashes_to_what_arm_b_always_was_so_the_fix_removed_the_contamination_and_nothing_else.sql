-- 0330  **0421's verification, as `0421` §5 specified it: recompute atom 4 for the pairs certified after
--       the fix and compare against the nine before it. Result: 3 of 3 post-fix pairs reproduce from
--       stored evidence; 9 of 9 pre-fix pairs still do not. And the sharper result nobody asked for —
--       the repaired arm A hashes to EXACTLY the value pre-fix arm B carried, in all three columns and
--       across both depots, so the fix removed the contamination and changed nothing else.**
--
--       Measured 2026-09-22 13:02-13:05 UTC (08:02 CT), mid-sweep: 3 of the 9 canon columns have
--       recertified since the 12:56:37 floor. §4 says what is therefore not yet shown.
--
-- ══ §1 THE VERIFICATION 0421 §5 ASKED FOR ═════════════════════════════════════
--
--     pairs          certified    verdict said clean   atom 4 AGREES today   atom 4 DISAGREES today
--     ------------   ----------   ------------------   -------------------   ----------------------
--     pre-0421       9            9                    0                     **9**
--     post-0421      3            3                    **3**                 0
--
-- Same query as `0329` §1, same `h_evt` expression copied verbatim from `ottoq_determinism_pair`,
-- split on the recert floor. The before/after is total and there is no partial case.
--
-- ══ §2 AND THE ROW COUNTS, WHICH SAY IT WITHOUT A HASH ════════════════════════
--
--     verdict  scenario     seed     ticks   events A   events B   delta
--     -------  ----------   ------   -----   --------   --------   -----
--     100      grid_smoke   239001       6        206        202   **4**     <- pre-fix
--     109      grid_smoke   239001       6        202        202     0       <- post-fix
--     101      grid_smoke   424242       6        173        169   **4**
--     110      grid_smoke   424242       6        169        169     0
--     102      busy_day     171717      12      6,674      6,558   **116**
--     111      busy_day     171717      12      6,558      6,558     0
--
-- `0329` §2 established the delta is one `vehicle.state_changed` per vehicle at that depot (116 twin,
-- 4 fixture), written into arm A at arm A's final clock. It is gone.
--
-- ══ §3 THE RESULT THAT PROVES MORE THAN THE FIX ═══════════════════════════════
--
-- Recomputed `h_evt` per arm, all six pairs:
--
--     scenario     seed     ticks   pre-fix A                          pre-fix B / post-fix A / post-fix B
--     ----------   ------   -----   --------------------------------   ----------------------------------
--     grid_smoke   239001       6   3da3f25fa743a4b497b533dd0437d8d2   5e9b2bcfd04b268ee275a4a9252d1353
--     grid_smoke   424242       6   5360accbd60d2547774d3dce19c4e6c9   8f0f7a7af8516becff7d9688e6f64ed6
--     busy_day     171717      12   0fd5b06a89f8a6cdd017f70e18832d06   d6e467f92d718fe0009c52f79bc4bc1a
--
-- **Three of the four hashes in every column are the same value.** Only pre-fix arm A differs.
--
-- Two things follow, and the second is new:
--
--   (a) **The fix is exactly the right size.** Repaired arm A does not merely agree with its own arm B —
--       it lands on the *identical digest* arm B has carried since 09:34. So `0421` deleted the 116 (or 4)
--       contaminating rows and touched nothing else. A fix that had perturbed the simulation would have
--       moved all four hashes to some new common value; this one moved one hash back onto three.
--
--   (b) **This is the first CROSS-TRANSACTION determinism result in the engine's life.**
--       `ottoq_determinism_pair` proves arm A == arm B *inside one transaction*, which is the strongest
--       form of "same inputs, same outputs" the rig has ever asserted — and also the weakest possible
--       independence, since both arms share a snapshot, a backend, a connection and a clock. Here the
--       same `h_evt` appears in a pair certified at **09:34** and a pair certified at **12:59**: different
--       run ids, different transactions, different backends, 3.5 hours apart, engine hash changed in
--       between (`2a553262…` -> `269d569c…`). That is reproducibility in the sense an outside reviewer
--       means it, and the rig was not built to measure it. It is visible here only as a by-product.
--
--       **Do not promote it to a claim on this evidence.** Three columns, one morning, one database. But
--       it is the first datum for the property 2.9a actually sells, and it points at a cheap standing
--       check: store `h_evt` per arm in the verdict ledger and assert it across certifications of the
--       same (scenario, seed, ticks, engine_hash). Filed as G140.
--
-- ══ §4 WHAT IS NOT SHOWN, SAID BEFORE SOMEONE QUOTES §1 ═══════════════════════
--
--   - **3 of 9 columns, not 9.** The sweep is mid-flight; `busy_day` 314159/424242 at 12t, both 24t
--     columns, `normal_day` 12t and the 48-tick column have not recertified yet. The 48-tick column is
--     the one `0329` showed the largest absolute contamination on and is the one to re-check last.
--   - **Atom 4 only.** `0329` measured `events` because `events` is what moved. The other thirteen atoms
--     were not recomputed from the archive, here or there, and at least one (`content_hash`) is known to
--     have its own history (2.9a / `0216` / `0280`). "Re-derivable from the archive" is proven for one
--     atom of fourteen and must be said that way.
--   - **Nothing is shown about arm B.** Arm B was always clean — the contamination landed in arm A by
--     construction (`0329` §3: it is the *previous* arm that owns the stale cached run id). The fix is
--     verified on the arm that was broken; there was never a defect on the other to verify.
--
-- ══ §5 AN INCIDENTAL MONITORING TRAP, RECORDED BECAUSE IT FOOLED ME TWICE ══════
--
-- At 13:01:38 UTC I read `count(*) FROM ottoq_sim_runs WHERE status IN ('running','paused')` = **0** and
-- concluded the sweep had stalled. It had not: cron job 746 started at 12:59:00 and ran until 13:02:14,
-- and verdict 111 appeared seconds later. **A determinism pair is invisible to that query while it runs**,
-- because both arms execute in one uncommitted transaction, so its `ottoq_sim_runs` rows are not visible
-- to any other session until commit.
--
-- This is not a defect and the runner is not relying on that query for mutual exclusion — its real mutex
-- is `pg_try_advisory_xact_lock(hashtext('ottoq_recert_runner'))`, and the `status IN ('running','paused')`
-- test exists to yield to a *demo* run, which does commit per tick. But **"0 runs active" does not mean
-- idle**, and any dashboard or check that reads it as "the sweep is finished" is wrong for up to the
-- length of one pair.
--
-- **Then the obvious fallback fooled me too, and this is the part worth keeping.** `cron.job_run_details`
-- is NOT a finished-only log. Job 746's command is two statements (`SET statement_timeout = 0;` then the
-- DO block), and pg_cron files a row as soon as the FIRST one completes — `status='succeeded'`,
-- `return_message='SET'`, and an `end_time` under a second after `start_time` — while the DO block runs
-- for minutes. So `end_time IS NULL` never fires, and a row that reads "succeeded in 0.77s" can be a pair
-- that is three minutes from finishing. At 13:05:10 `pg_stat_activity` showed that exact backend
-- (pid 970514) still `active`, `xact_start` 13:02:14, on the runner's text.
--
--     **The only honest in-flight signal is `pg_stat_activity`.** A `return_message='SET'` row is a
--     *strong hint* the pair is still running (a completed job files 'DO'), but it is a side effect of the
--     command having two statements, not a documented state. §5's query below reads the backend.
--
-- ══ §6 AND FOLLOWING THAT TRAP FOUND A REAL ONE: THE PAIR STARVES pg_cron ══════
--
-- `cron.use_background_workers` is **off** on this project, so the launcher runs tasks itself. Measured,
-- raw rows, two consecutive windows:
--
--     746 run 12:59:00.085 -> 13:02:14.862  (3m14s)   other jobs fired during: **0**
--       then at 13:02:14.91-15.02, within 110 ms: job 12 x4, job 10 x2, job 17 x2   <- catch-up burst
--     746 run 13:02:14.916 -> 13:05:31.320  (3m16s)   other jobs fired during: **0**
--       then at 13:05:31.38-31.45: job 12 x3, job 10 x1, job 17 x1
--
-- And over every long recert run in the last seven days:
--
--     long 746 runs (>60s)                                 63
--     firings of jobs 10/12/17 in their INTERIOR          **0**   (total, across all 63)
--     runs with a zero interior                          63 / 63
--     total wall-clock inside a long 746 run             **5h 28m** of a 40h 40m span = **13.6%**
--
-- **Every other cron job is blocked for the whole length of a determinism pair.** The 48-tick column's
-- pair ran **12m55s** this morning; that is a thirteen-minute cron outage, once per sweep.
--
--     **The interior window must exclude the first few seconds, and the first draft of this query did
--     not** — it reported up to 8 firings "during" runs that had none, because the runner starts pairs
--     back-to-back and the PREVIOUS pair's release burst lands ~100 ms after the NEXT pair's start_time.
--     Same boundary-attribution shape as the clock-domain errors elsewhere in this folder: the reading
--     was of the right table and the wrong instant.
--
-- **And the missed firings are DROPPED, not deferred.** The release burst averages **5.0** firings where
-- full catch-up would be **10.2**. A 12m55s run should owe job 17 (*/2) six firings and pays about one.
-- So a sweep does not delay the run governor, it *skips* it.
--
-- The three jobs starved are `ottoq-depot-tick` (10, */2), `ottoq-demo-metronome` (12, * * * * *) and
-- **`ottoq-run-governor` (17, */2)** — the auto-stop that enforces `run_governor_max_sim_minutes`.
--
-- **Why this is a latency nuisance and not a safety hole, checked rather than assumed.** The governor
-- cannot stop a runaway run while a pair holds the launcher — but the metronome cannot advance one
-- either, and `ottoyarddepot-sim/src/hooks/useTwinControl.ts` states in its own comment that there is
-- **NO BROWSER TICK LOOP**: *"The server-side metronome (pg_cron -> ottoq_demo_metronome) owns the world
-- clock"*, the client loop having been removed because it collided with the metronome's run lock. So
-- nothing else advances a demo run, and the two starvations cancel: a frozen run cannot run away.
-- (The runner already declines to start a pair while a run is `running`/`paused`, so the only way to be
-- in this state at all is to start a run *during* a pair.)
--
-- **What it does cost, and one thing that saves it.** On release, a `live`-playback run takes its whole
-- frozen span in ONE oversized tick, because `live` computes `tick_minutes := real elapsed x speed_x`;
-- the three catch-up calls behind it then see ~0 elapsed. No sim time is lost. **And `0420` is what keeps
-- that honest** — the fault hazard now multiplies per-tick λ by `payload->>'tick_minutes_actual'` rather
-- than by the metronome's nominal cadence, so a 3-minute tick gets 3 minutes of hazard. Had `0413`'s
-- defect still been live, this burst would have charged one tick's worth of faults for six ticks' worth
-- of sim time. Per-tick logic that is NOT duration-scaled (booking windows, one advice fetch per tick)
-- still sees a single enormous tick, which is the residual.
--
-- **AND IT PUTS A CAVEAT ON THE AGENT-LATENCY NUMBERS.** `ottoq_model_call_ledger` latency is REAL clock,
-- and `0417`'s live-era figures (mean 19,723 ms, p95 66,566 ms, 18.7% over one tick) are computed across
-- whatever real-time gaps the beat actually had. A recert sweep freezes that beat for minutes at a time.
-- The ledger spans far more than sweep windows so the means are not dominated by it, but **a latency
-- percentile taken from a window overlapping a sweep is not measuring the agent**. Filed as G141; the fix
-- if it ever matters is to exclude calls whose tick spans a 746 run, not to re-tune anything.
--
-- ══ §7 STATUS ════════════════════════════════════════════════════════════════
--
-- G137 (the verdict is not re-derivable) is **fixed and verified on 3 of 9 columns**; it closes when the
-- sweep completes and §1 reads 9/9. G138 stands as the retraction it always was: the nine pairs certified
-- before 12:56 remain correct verdicts over clean evidence and remain non-re-derivable forever, because
-- the rows were mutated in place and `ottoq_events` is append-only — there is nothing to repair, only to
-- supersede. G140 is new (§3b), G141 is new (§6).

\echo '=== 0330 §1 — the before/after 0421 asked for, split on the recert floor ==='
WITH pairs AS (
  SELECT verdict_id, certified_at, scenario, seed, ticks, arm_a_run, arm_b_run, disagreeing_atoms
    FROM public.ottoq_determinism_verdict_ledger
   WHERE certified_at >= '2026-09-22 09:00:00+00'
), h AS (
  SELECT p.*, (p.certified_at > '2026-09-22 12:56:37.305405+00') AS post_0421,
    (SELECT md5(COALESCE(string_agg(
       event_type||'|'||CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                             THEN '-' ELSE COALESCE(entity_id::text,'-') END||'|'||
       COALESCE(e.sim_clock_at::text,'-'), E'\n'
       ORDER BY event_type, CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                                 THEN '-' ELSE COALESCE(entity_id::text,'-') END, e.sim_clock_at), ''))
       FROM public.ottoq_events e WHERE e.sim_run_id=p.arm_a_run) AS h_a,
    (SELECT md5(COALESCE(string_agg(
       event_type||'|'||CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                             THEN '-' ELSE COALESCE(entity_id::text,'-') END||'|'||
       COALESCE(e.sim_clock_at::text,'-'), E'\n'
       ORDER BY event_type, CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                                 THEN '-' ELSE COALESCE(entity_id::text,'-') END, e.sim_clock_at), ''))
       FROM public.ottoq_events e WHERE e.sim_run_id=p.arm_b_run) AS h_b
    FROM pairs p
)
SELECT post_0421,
       count(*)                                  AS pairs,
       count(*) FILTER (WHERE disagreeing_atoms = '{}') AS verdict_said_clean,
       count(*) FILTER (WHERE h_a =  h_b)        AS atom4_AGREES_today,
       count(*) FILTER (WHERE h_a <> h_b)        AS atom4_DISAGREES_today
  FROM h GROUP BY post_0421 ORDER BY post_0421;
-- false: 9 / 9 / 0 / 9.  true: 3 / 3 / 3 / 0.  Closes when the true row reads 9 / 9 / 9 / 0.

\echo '=== 0330 §2 — the same thing without a hash: total event rows per arm ==='
WITH pairs AS (
  SELECT verdict_id, scenario, seed, ticks, arm_a_run, arm_b_run,
         (certified_at > '2026-09-22 12:56:37.305405+00') AS post_0421
    FROM public.ottoq_determinism_verdict_ledger WHERE certified_at >= '2026-09-22 09:00:00+00'
)
SELECT p.verdict_id, p.post_0421, p.scenario, p.seed, p.ticks,
       (SELECT count(*) FROM public.ottoq_events e WHERE e.sim_run_id=p.arm_a_run) AS events_a,
       (SELECT count(*) FROM public.ottoq_events e WHERE e.sim_run_id=p.arm_b_run) AS events_b,
       (SELECT count(*) FROM public.ottoq_events e WHERE e.sim_run_id=p.arm_a_run)
     - (SELECT count(*) FROM public.ottoq_events e WHERE e.sim_run_id=p.arm_b_run) AS delta
  FROM pairs p ORDER BY p.scenario, p.seed, p.ticks, p.post_0421;
-- delta = depot vehicle count before the fix, 0 after it.

\echo '=== 0330 §3 — repaired arm A lands on the digest arm B has carried since 09:34 ==='
WITH v AS (
  SELECT verdict_id, scenario, seed, ticks, arm_a_run, arm_b_run,
         (certified_at > '2026-09-22 12:56:37.305405+00') AS post_0421
    FROM public.ottoq_determinism_verdict_ledger WHERE certified_at >= '2026-09-22 09:00:00+00'
), arms AS (
  SELECT verdict_id, post_0421, scenario, seed, ticks, 'A' arm, arm_a_run rid FROM v
  UNION ALL SELECT verdict_id, post_0421, scenario, seed, ticks, 'B', arm_b_run FROM v
)
SELECT a.scenario, a.seed, a.ticks, a.verdict_id, a.post_0421, a.arm,
   (SELECT md5(COALESCE(string_agg(
      event_type||'|'||CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                            THEN '-' ELSE COALESCE(entity_id::text,'-') END||'|'||
      COALESCE(e.sim_clock_at::text,'-'), E'\n'
      ORDER BY event_type, CASE WHEN entity_type IN ('ocpp_session','service_detail_record','sim_run')
                                THEN '-' ELSE COALESCE(entity_id::text,'-') END, e.sim_clock_at), ''))
      FROM public.ottoq_events e WHERE e.sim_run_id=a.rid) AS h_evt
  FROM arms a
 WHERE EXISTS (SELECT 1 FROM v v2 WHERE v2.scenario=a.scenario AND v2.seed=a.seed
                 AND v2.ticks=a.ticks AND v2.post_0421 <> a.post_0421)
 ORDER BY a.scenario, a.seed, a.ticks, a.post_0421, a.arm;
-- Within each (scenario, seed, ticks) group: three identical digests and one outlier, and the outlier is
-- always pre-fix arm A. The WHERE clause keeps only columns that exist on BOTH sides of the floor, so this
-- query grows correctly as the sweep lands the remaining six.

\echo '=== 0330 §5 — the monitoring trap: neither the runs table nor job_run_details shows a live pair ==='
SELECT (SELECT count(*) FROM public.ottoq_sim_runs WHERE status IN ('running','paused'))   AS runs_active_says,
       (SELECT count(*) FROM cron.job_run_details WHERE jobid=746 AND end_time IS NULL)    AS end_time_null_says,
       (SELECT count(*) FROM pg_stat_activity
         WHERE state='active' AND pid <> pg_backend_pid()
           AND query LIKE '%ottoq\_recert\_runner%')                                       AS backend_says,
       (SELECT min(now()-xact_start) FROM pg_stat_activity
         WHERE state='active' AND pid <> pg_backend_pid()
           AND query LIKE '%ottoq\_recert\_runner%')                                       AS running_for,
       (SELECT count(*) FROM public.ottoq_determinism_canon WHERE enabled AND NOT satisfies_floor) AS canons_left;
-- While a pair is in flight: runs_active_says = 0, end_time_null_says = 0, backend_says = 1.
-- Only the third column is true. The second is false because pg_cron files a row when the command's
-- FIRST statement (`SET statement_timeout = 0`) finishes -- return_message 'SET', end_time already set.
-- The `pid <> pg_backend_pid()` is not decoration: without it this query matches ITSELF (its own text
-- contains the pattern) and reports 2 in-flight pairs with running_for 00:00:00. First draft did.

\echo '=== 0330 §6 — a determinism pair blocks every other cron job for its whole duration ==='
WITH long746 AS (
  SELECT start_time, end_time, end_time-start_time AS dur
    FROM cron.job_run_details
   WHERE jobid=746 AND end_time-start_time > interval '60 seconds'
     AND start_time >= now() - interval '7 days'
)
, m AS (
  SELECT l.start_time, l.dur,
       (SELECT count(*) FROM cron.job_run_details d
         WHERE d.jobid IN (10,12,17)
           AND d.start_time > l.start_time + interval '5 seconds'   -- see note: the PREVIOUS pair's
           AND d.start_time < l.end_time   - interval '1 second')   -- release burst lands here
                                                                            AS during_interior,
       (SELECT count(*) FROM cron.job_run_details d
         WHERE d.jobid IN (10,12,17) AND d.start_time >= l.end_time - interval '1 second'
           AND d.start_time <  l.end_time + interval '3 seconds')            AS burst_on_release,
       round(extract(epoch FROM l.dur)/60.0) * 2                             AS burst_if_fully_deferred
    FROM long746 l
)
SELECT count(*)                                        AS long_runs,
       sum(during_interior)                            AS total_interior_firings,
       count(*) FILTER (WHERE during_interior = 0)     AS runs_with_zero_interior,
       round(avg(burst_on_release),1)                  AS avg_burst,
       round(avg(burst_if_fully_deferred),1)           AS avg_if_deferred_not_dropped,
       min(dur) AS min_dur, max(dur) AS max_dur
  FROM m;
-- 63 / 0 / 63 / 5.0 / 10.2 / 3m04s / 12m55s at the time of writing (it read 64 / 0 / 64 four minutes
-- later, mid-sweep -- long_runs grows with every pair, the zero does not). Zero interior firings, and a release
-- burst half the size full catch-up would be -- so missed minutes are dropped, not deferred.
-- The `+ interval '5 seconds'` is load-bearing: pairs run back-to-back, so without it the previous
-- pair's release burst (~110 ms after this one's start_time) is miscounted as interior traffic.
