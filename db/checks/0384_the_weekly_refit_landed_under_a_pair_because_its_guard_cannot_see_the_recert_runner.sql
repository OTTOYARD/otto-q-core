-- 0384  **G243: the weekly calibration refit landed inside a certification pair, so the pair's two arms booted on
--       different priors and verdict 474 failed on `calibration`. The refit has a guard against exactly this, and
--       it cannot see the pairs the recert runner runs: it is a copy of G194's probe inside a database function,
--       and G194's fix never reached it. Behind that sits a second gap: the refit's rows are written a second or
--       more after the guard runs, by an edge function, with no guard at all.**
--
--       Found on 2026-09-27 (04:20-04:45 UTC, 11:20-11:45 PM CT on the 26th) while reading the one failed verdict
--       of the 0511 sweep. Read-only; nothing here writes.
--
--       The pair did its job. `h_cal` exists (0201) so that two arms on different priors are reported as two
--       different worlds, and it did exactly that. The retry, verdict 475, passed on the new priors without anyone
--       touching it. What is wrong is upstream: a refit is never supposed to land under a pair (0201's own comment
--       in `ottoq_twin_ingest_refresh`, after db/checks/0115 caught round 19 at 04:05:25 UTC), and it did.

-- ══ §1 THE CALIBRATION PRIORS EVERY VERDICT BOOTED ON ═════════════════════════════════════════════

\echo '=== 0384 §1 — h_cal per arm, boot and end state, across the 0510 and 0511 sweeps ==='
SELECT verdict_id, certified_at, outcome,
       left(verdict->'arm_a'->>'h_cal', 8)                        AS a_boot,
       left(verdict->'arm_b'->>'h_cal', 8)                        AS b_boot,
       left(verdict->'arm_a'->'endst'->'calibration'->>'h', 8)    AS a_end,
       left(verdict->'arm_b'->'endst'->'calibration'->>'h', 8)    AS b_end
  FROM public.ottoq_determinism_verdict_ledger
 WHERE verdict_id BETWEEN 457 AND 475
 ORDER BY verdict_id;
-- READ (2026-09-27 04:35 UTC): every verdict from 457 to 473 booted and ended both arms on c5fbb56e. Verdict 474
--   (busy_day/171717/48, the sweep's last column): arm A booted on cc798e04, arm B on bb7fb6fa, and BOTH ended on
--   bb7fb6fa. Verdict 475, the runner's automatic retry of the same column, booted and ended both arms on bb7fb6fa
--   and passed. So the priors moved twice while arm A was running: c5fb -> cc79 before arm A's boot read, and
--   cc79 -> bb7f before its end. cc79 is a state that exists only between the refit's first and last write.

-- ══ §2 WHAT WROTE THE PRIORS, AND WHEN ═══════════════════════════════════════════════════════════

\echo '=== 0384 §2 — calibration rows refit in the last day, by their own fitted_at / ingested_at ==='
SELECT 'distribution' AS kind, dataset_code || '/' || variable_name || '/' || COALESCE(segment, '-') AS what, fitted_at AS at
  FROM public.ottoq_calibration_distributions WHERE fitted_at > timestamptz '2026-09-27 03:00+00'
UNION ALL
SELECT 'profile', dataset_code || '/' || profile_name, fitted_at
  FROM public.ottoq_calibration_profiles WHERE fitted_at > timestamptz '2026-09-27 03:00+00'
UNION ALL
SELECT 'dataset', dataset_code || ' (' || record_count || ' records)', ingested_at
  FROM public.ottoq_calibration_datasets WHERE ingested_at > timestamptz '2026-09-27 03:00+00'
ORDER BY at;
-- READ (2026-09-27 04:30 UTC):
--     distribution  noaa_nws/ambient_temp_c/global   04:03:39.70
--     distribution  noaa_nws/precip_mm/global        04:03:40.85
--     dataset       noaa_nws (362 records)            04:03:40.85
--     distribution  eia_grid/grid_demand_mw/global   04:03:46.62
--     dataset       eia_grid (8784 records)           04:03:46.62
--     profile       eia_grid/hourly_grid_demand_shape 04:03:47.07
--   Eight seconds of writes, in four transactions or more. Arm A's boot read fell after the first and before the
--   last, which is where cc798e04 comes from.

\echo '=== 0384 §3 — the jobs pg_cron launched at the moment the first pair of the sweep released it ==='
SELECT j.jobid, j.jobname, d.start_time, d.end_time, d.status
  FROM cron.job_run_details d JOIN cron.job j USING (jobid)
 WHERE d.start_time BETWEEN timestamptz '2026-09-27 04:03:38+00' AND timestamptz '2026-09-27 04:03:39+00'
   AND j.jobid IN (2, 746)
 ORDER BY d.start_time;
-- READ (2026-09-27 04:25 UTC):
--     746  ottoq-recert-runner       04:03:38.812  ->  04:14:14.640  succeeded   (the pair that became verdict 474)
--       2  ottoq-twin-ingest-weekly  04:03:38.833  ->  04:03:38.885  succeeded   (scheduled '0 4 * * 0', i.e. 04:00)
--   The refit was due at 04:00:00 and started at 04:03:38.83, the moment the previous pair (verdict 473,
--   03:59:24 -> 04:03:38.70) released pg_cron (0330 §6: a pair starves every other job for its whole length).
--   pg_cron then launched the next pair and the refit 21 ms apart. The timing is incidental: §4 shows the guard
--   would have missed the pair at any point in its ten minutes.

-- ══ §4 WHY THE GUARD DID NOT STOP IT: IT CANNOT SEE THE RUNNER AT ALL (G194, in the copies its fix missed) ═══

\echo '=== 0384 §4 — what the refit guard can see of the recert runner, and every other copy of that guard ==='
WITH r AS (SELECT command, left(command, 1023) AS visible FROM cron.job WHERE jobid = 746)
SELECT current_setting('track_activity_query_size')           AS query_text_kept,
       octet_length(command)                                   AS runner_command_bytes,
       position('ottoq_determinism_pair' IN command)           AS pair_named_at,
       visible ILIKE '%ottoq_determinism_pair%'                AS guard_can_match,
       command ILIKE '%ottoq_determinism_pair%'                AS full_text_would_match
  FROM r;
-- READ (2026-09-27 04:40 UTC): 1kB kept, the runner's command is 1,800 bytes, it names the pair at byte 1,542,
--   guard_can_match FALSE, full_text_would_match TRUE. pg_stat_activity.query keeps the first 1,023 bytes, and the
--   runner's first 1,023 bytes end inside its rule-8 comment. So `ottoq_twin_ingest_refresh()`'s check
--   (query ILIKE '%ottoq_determinism_pair%' on a non-idle backend) reads zero for EVERY pair the runner holds.
--   Not a race. This is exactly G194 (2026-09-26: the runner named the pair at 1,303 then; the rule-8 comment and
--   0481's promotion-guard line have pushed it to 1,542 since). G194's fix added `ottoq_recert_runner` to every
--   copy of the probe it found: the migrations' P0, scripts/APPLYING.md, load/harness.py and
--   scripts/schedule-round.sql. It found no copy inside a database function, and there are two.

SELECT n.nspname || '.' || p.proname AS fn,
       p.prosrc ~* 'ottoq_recert_runner' AS sees_runner
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.prosrc ~* 'pg_stat_activity' AND p.prosrc ~* '(determinism|ab|dial)_pair'
 ORDER BY 1;
-- READ (2026-09-27 04:42 UTC):
--     public.ottoq_retention_purge_runs   f   (cron 625, the nightly purge at 09:00 UTC / 4:00 AM CT)
--     public.ottoq_twin_ingest_refresh    f   (cron 2, the weekly refit, Sundays 04:00 UTC / 11:00 PM CT Saturday)
--   And one in the repo: bridge/proposer_bridge.py's CERT_CALLS = ('%ottoq_determinism_pair%', '%ottoq_ab_pair%').
--   The bridge's blindness is harmless today, since the runner only starts when no run is running or paused and a
--   pair's own runs are uncommitted, so the bridge finds no run to propose into. The other two are not harmless:
--   tonight the refit landed under a pair, and the purge can land under one the same way.
--
-- AND A SECOND GAP THE RUNNER-AWARE CHECK WOULD NOT CLOSE. The refit function does not write the priors itself. It
--   posts two requests with `net.http_post` to the `ottoq-twin-ingest` edge function and returns in about 50 ms
--   (§3). The edge function fetches NOAA and EIA and writes the rows one to nine seconds later (§2), and nothing
--   on that path asks whether a pair is running. So the guard has to move, or be repeated, where the rows are
--   written: a pair that starts after a correct kickoff check still gets tonight's failure.
--
-- AND THE PURGE'S PROBE IS DEAD CODE, WHICH IS WHY IT IS LEFT ALONE. Above its pair probe, `ottoq_retention_purge_runs`
--   skips when "a certification round is scheduled": any ACTIVE cron job whose command contains
--   ottoq_determinism_pair. cron.job.command is the full text, not pg_stat_activity's 1 kB, and cron 746 is active and
--   always contains it, so that check matches every night and the purge has returned early every night since the
--   runner was created (its oldest kept run is 2026-09-20 20:16 UTC). Measured 2026-09-27 05:00 UTC: 0 of the 585
--   non-production runs are older than the purge's 48 hours, because the demo start's `ottoq_purge_prior_runs`
--   clears them. So nothing is lost today. Unblocking the purge would delete the nine operator runs G240's
--   calibration is measured on, the oldest from 2026-09-25 19:12 UTC, so it waits for G240's evidence ledger, and
--   both checks are fixed together then.

\echo '=== 0384 §4(b) — the purge''s round check, and what the purge would have had to delete ==='
SELECT j.jobid, j.jobname,
       (j.active AND (j.command ILIKE '%ottoq_determinism_pair%' OR j.command ILIKE '%ottoq_cert_battery_step%')) AS matches_round_check
  FROM cron.job j WHERE j.jobid = 746;
SELECT count(*) FILTER (WHERE COALESCE(run_by, '') <> 'production_live') AS non_production_runs,
       count(*) FILTER (WHERE COALESCE(run_by, '') <> 'production_live' AND status <> 'running'
                          AND started_at < now() - interval '48 hours') AS purgeable_after_48h
  FROM public.ottoq_sim_runs;
-- READ (2026-09-27 05:00 UTC): 746 matches_round_check TRUE; 585 non-production runs, 0 purgeable after 48 hours.

-- ══ §5 WHAT THIS DOES AND DOES NOT TOUCH ═════════════════════════════════════════════════════════
--
-- Nothing certified is wrong. Verdicts 466-473 certified their columns on c5fbb56e and verdict 475 certified
-- busy_day/171717/48 on bb7fb6fa, each internally consistent, which is what `h_cal` guarantees. The canon under
-- 0511 therefore passed all nine columns, eight on last week's priors and one on this week's, with one automatic
-- retry. Every run from 04:03:47 UTC on draws its weather and grid demand from the new fit. The next sweep will
-- certify the other eight columns on bb7fb6fa, and it may move their digests, for a reason that is not a
-- migration.

-- ══ §6 THE FIX: 0513, APPLIED 20260927050506 (12:05 AM CT), forces_recert FALSE ══════════════════════════════════════
--
--   `public.ottoq_certification_rig_matches(text, boolean)` holds the G194-fixed pattern list once;
--   `public.ottoq_certification_in_flight(boolean)` counts the other backends it matches (SECURITY DEFINER, since the
--   edge function writes as service_role, which cannot read other roles' query text). `ottoq_twin_ingest_refresh()`
--   asks it, and skips a source refit in the last six days. A statement-level guard on the four calibration tables
--   refuses writes while it reads non-zero, so the asynchronous write is guarded where it lands. cron 2 runs
--   '0 4-23 * * 0', the same first attempt with hourly retries through Sunday UTC. bridge/proposer_bridge.py's
--   CERT_CALLS carries the same list. The purge is untouched (above). The last window, a pair starting between the
--   guard's check and a refit write's commit, is milliseconds now; closing it needs a lock the runner holds for the
--   pair's whole transaction, and that waits for a recert window.

\echo '=== 0384 §6 — 0513 as applied ==='
SELECT m.version, md5(m.statements[1]) AS stored_md5,
       (SELECT schedule FROM cron.job WHERE jobid = 2) AS refit_schedule,
       (SELECT count(*) FROM pg_trigger WHERE tgname = 'ottoq_calibration_write_guard' AND NOT tgisinternal) AS guards,
       public.ottoq_certification_in_flight(true) AS rigs_now
  FROM supabase_migrations.schema_migrations m
 WHERE m.name = 'the_weekly_refit_could_not_see_the_recert_runner_and_wrote_the_priors_under_a_pair';
-- READ (2026-09-27 05:06 UTC): version 20260927050506, stored md5 9c77fb14ce37cd524959263e9910be4e (the file's body
--   byte for byte), refit_schedule '0 4-23 * * 0', guards 4, rigs_now 0. The same blocks passed a rolled-back dry run
--   first. V3, rolled back: (a) the runner's visible text (1,023 characters) is a rig to the predicate and invisible
--   to the old probe; (b) with a rig in flight (the fail-closed flag), an UPDATE on a calibration table is refused
--   with 55P03 and the refresh asks for nothing; (c) with none, the write goes through and the two sources refit at
--   04:03 UTC are skipped; (d) with NOAA's dataset aged seven days, exactly one request is queued, for NOAA.
--   The refresh's body moved 66a94e5141493b0b2dd8ab7febf9db63 -> 6739008c0c963938e53e278977db6cb7 (`0513_pre`
--   holds the old one). What is not seen yet: a live deferral or refusal. The first chance is a refit that finds a
--   pair running, and the next scheduled refit is 2026-10-04 04:00 UTC.
