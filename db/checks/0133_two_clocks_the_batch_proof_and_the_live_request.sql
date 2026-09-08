-- ---------------------------------------------------------------------------
-- 0133 — the two clocks, separated, because they keep getting confused.
--
--   THE PAIR:      519 s mean, 12 ticks, whole depot, twice, one transaction
--   THE REQUEST:   24-47 ms mean, measured on the live API over 637,473 calls
--
--   These are not the same measurement and neither one is evidence about the
--   other. Written 2026-09-08 12:50 UTC because the question "does hundreds of
--   seconds mean OTTO-Q cannot talk to a vehicle in real time" is the right
--   question and deserves a numbered answer rather than a reassurance.
-- ---------------------------------------------------------------------------

-- Q1. WHAT THE 519 SECONDS IS. ottoq_determinism_pair boots the flagship depot
--     (226 vehicles, 330 stalls), runs N simulated ticks, then does the entire
--     thing AGAIN from the same seed, both arms inside ONE transaction, and
--     hashes twelve streams to prove the two runs are byte-identical.
--
--       12-tick pair = 24 whole-depot re-plans + 4 fingerprints + 12 hashes x 2
--
--     It is a proof harness. No production request waits on it, and no vehicle
--     path calls it. Per whole-depot re-plan that is ~16 s (0129:
--     ottoq_sim_decide_and_dispatch, 388.7 s over 24 calls) and per emitted
--     vehicle command ~8 ms (0129: 612 calls, 4.9 s).
SELECT jobname, round(extract(epoch FROM (end_time - start_time)))::int AS pair_secs
FROM cron.job_run_details d JOIN cron.job j USING (jobid)
WHERE j.jobname ~ '^r2[0-9]+_' AND d.end_time IS NOT NULL
  AND end_time - start_time > interval '60 seconds'
ORDER BY start_time DESC LIMIT 8;

-- Q2. WHAT A LIVE REQUEST COSTS, from pg_stat_statements on the API's own
--     PostgREST wrapper — real traffic, not a benchmark:
--
--       calls      mean_ms   max_ms
--       272,723      37.28   19,916.6
--       191,845      23.58   14,131.1
--       172,905      46.64    7,945.8
--
--     637,473 calls at a 24-47 ms mean. The internal lookups underneath are
--     0.00-0.01 ms each.
--
--     READ THAT WITH ITS WINDOW, which the first draft of this file left out and
--     which materially weakens the claim. pg_stat_statements was last reset
--     2026-07-30 and these rows' stats_since is 2026-07-30 / 2026-08-05, so
--     these are **lifetime means over 34-40 days**, not a live reading:
--
--       272,723 calls / 34 days  =  ~334 per hour  =  ~5.6 per minute
--
--     And at 12:48:20 vs 12:49:35 UTC — 75 seconds apart, with no pair running —
--     the counters were **identical to the decimal**. Zero calls arrived. The
--     API is not merely quiet, it is idle at this moment.
--
--     So the honest form of the claim is: over a month of real but LIGHT traffic
--     (~5.6 calls/min at the busiest endpoint), the typical request costs 24-47
--     ms. That is evidence the code path is fast. **It is not evidence the
--     system is fast under load, because it has never been under load.** No
--     load test exists in this repo. Saying "real-time territory" without that
--     sentence would be the same class of overstatement as quoting a row count
--     without its retention window (0131 Q5, 0132 Q4).
SELECT left(regexp_replace(query,'\s+',' ','g'), 60) AS q, calls,
       round(mean_exec_time::numeric,2) AS mean_ms,
       round(max_exec_time::numeric,1) AS max_ms
FROM pg_stat_statements
WHERE query LIKE '%pgrst_source%' AND calls > 1000
ORDER BY calls DESC LIMIT 6;

-- Q3. THE TAIL IS THE PART TO WORRY ABOUT, AND IT IS NOT THE MEAN.
--     8 to 20 SECONDS at the maximum. A mean of 37 ms with a max of 19.9 s is
--     not a fast system with an outlier; it is a fast system that sometimes
--     stops. Two candidate causes, neither yet proven:
--
--       (a) CONTENTION WITH THE PROOF HARNESS. A certification pair holds the
--           flagship depot inside a single ~9-minute transaction. Anything
--           touching the same rows queues behind it. Six pairs a round, several
--           rounds a day, on the SAME DATABASE the API serves.
--       (b) the same unbounded-history reads this file's siblings convict —
--           a request that happens to hit a path scanning ottoq_stall_bookings
--           (786k rows) or ottoq_events (2.28M) pays for the archive.
--
--     (a) is testable in principle by differencing the API's latency inside and
--     outside a pair window. IT WAS ATTEMPTED, 2026-09-08 12:48-12:50 UTC, and
--     the attempt is recorded here because it failed for an instructive reason:
--     at ~5.6 calls per minute the windows are too sparse. A 19-minute pair
--     window contains about a hundred calls against a distribution with a
--     19-second tail, which is not enough to separate an effect from noise. The
--     experiment needs generated load, and generated load is what this system
--     has never had.
--
--     Until then the honest statement is "24-47 ms typical over a month of light
--     traffic, seconds at the tail, cause unproven, never load-tested".
--
--     The architectural point stands regardless: **production must not share a
--     database with the proof harness.** Whatever fraction of that tail is (a),
--     it is self-inflicted and it disappears the moment the twin runs somewhere
--     else.

-- Q4. ARE THE MILLIONS OF ROWS NEEDED? Two different answers.
--
--     THEY ARE THE PRODUCT, as history. Signed events, stall bookings, rule
--     evaluations, decisions, SDRs — that is what makes "every claim traces to
--     a run ID" true and what a settlement record settles against. You do not
--     need it to MAKE a decision. You need it to PROVE one afterwards.
--
--     AND SOME OF IT IS DISPOSABLE — but only some, and the per-table numbers
--     say which. Measured 2026-09-08 12:52 UTC:
--
--       table                          inserts      deletes    live   purged
--       ottoq_events                 9,492,881    9,195,864   2.29M     97%
--       ottoq_decisions              2,988,890    4,854,763   1.67M    >100%*
--       ottoq_rule_evaluations      10,585,536    4,766,150   5.54M     45%
--       ottoq_stall_bookings           939,170      134,089    794k     14%
--       ottoq_service_detail_records   196,026       12,589    183k      6%
--
--       * deletes exceed inserts because the counters predate a bulk load;
--         read it as "aggressively purged", not as a paradox.
--
--     A CORRECTION TO MY OWN FIRST DRAFT, which said "most of it is disposable"
--     and cited only ottoq_events. That is true of ottoq_events and false of
--     ottoq_stall_bookings, which has had **14%** of its rows deleted and is
--     therefore an ACCUMULATION, not a rolling window. It grows by roughly 800
--     bookings per certification pair, forever, and db/checks/0127 measured it
--     at 53% of every disk block this database has ever read.
--
--     That is an open issue this file raises and does not close: the retention
--     purge covers the event stream and the decision ledger and barely touches
--     the calendar. Whether stall bookings from a finished twin run are evidence
--     worth keeping is a product question, not a performance one — but the
--     performance consequence is real, and it is the same shape as Q5.
SELECT relname,
       n_tup_ins AS inserts_lifetime, n_tup_del AS deletes_lifetime,
       n_live_tup AS live_now,
       round(100.0 * n_tup_del / NULLIF(n_tup_ins,0)) AS pct_purged
FROM pg_stat_user_tables
WHERE relname IN ('ottoq_events','ottoq_stall_bookings','ottoq_rule_evaluations',
                  'ottoq_decisions','ottoq_service_detail_records')
ORDER BY n_live_tup DESC;

-- Q5. WHAT WAS ACTUALLY WASTEFUL, and it was not the data.
--
--     It was DECISION CODE READING THE LEDGER TO ANSWER A QUESTION ABOUT NOW:
--
--       ottoq_boot_state_fingerprint   1,360,915 rows serialized and MD5'd per
--                                      call, four calls a pair, to characterise
--                                      THIRTEEN. Fixed by 0222; the pair went
--                                      from a 747 s mean to 519 s.
--       ottoq_sim_compute_charger_load_kw
--                                      8,966,506 evaluations per pair of a
--                                      value that is constant for the call.
--                                      195 s of the pair. 0223 drafted.
--       ottoq_validate_assignment      walked every booking a stall ever had,
--                                      in every run that ever ran, because the
--                                      run scope was written as a COALESCE the
--                                      index could not read. Fixed by 0221.
--
--     All three are one defect wearing three faces: **work proportional to all
--     history, to answer a question about this instant.** That is the shape
--     that gets monotonically slower on an unchanged workload, and it is the
--     one that would have bitten production rather than the harness.
--
--     THE STANDING RULE, stated so it can be checked rather than remembered:
--     the hot path reads the WORKING SET — this depot, this run, live rows —
--     and never the archive. A vehicle command validation is ~8 ms today and
--     does not grow with history. Anything on the tick or request path whose
--     cost is a function of total row count is a defect, whatever its current
--     absolute number.
SELECT 'see Q1-Q5; this file changes nothing' AS status;
