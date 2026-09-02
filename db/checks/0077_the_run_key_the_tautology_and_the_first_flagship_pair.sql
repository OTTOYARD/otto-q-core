-- 0077  The run key, the tautology, and the first flagship pair after the fixes.
--       Read 3:35-4:00 PM CT, 2026-09-02. Migration 0167 applied 3:58 PM CT.
--
-- Everything built earlier today (0155 meter, 0156 fit-ordering, 0159 downgrade
-- policy, 0161-0166 the fault channel) was proven only on the 20-second grid
-- fixture. This is the first flagship evidence, and reading it turned up two
-- defects in the instrument that were worse than anything it found in the engine.
--
--
-- §1  A correction to my own reporting
-- ------------------------------------
-- I told Chase that three attempts to fire a flagship pair from pg_cron had
-- failed. That was wrong. cron.job_run_details for jobid 264 - the same command,
-- fired 3:21 PM CT - reads status=succeeded, 394.4s, "1 row". The pair ran. I
-- read the row as the timeout probe's and reported a failure that had not
-- happened.
--
-- The mechanism behind the confusion is worth keeping, because it will mislead
-- again. jobid 267 fired the identical command at 3:40 PM CT and
-- cron.job_run_details recorded status=succeeded, 1.0s, return_message "SET" -
-- the first statement only. But ottoq_sim_runs shows both arms of that pair ran
-- to completion, last tick 3:47:57 PM CT, and the verdict is stored. So:
--
--   For a multi-statement pg_cron command, cron.job_run_details is not a
--   completion signal. Read completion from ottoq_sim_runs, never from cron.
--
-- Two of my three "failures" today were this. The engine was innocent again.
--
--
-- §2  The pair itself - passed, equal, and reproducible across pairs
-- ------------------------------------------------------------------
-- Two flagship pairs on busy_day / 171717 / 12 ticks / depot 11111111, both
-- after today's five forces_recert migrations:
--
--   pair 1   arms 25944bde / 0f70589b   (sim_run_seq 1748 / 1749)  3:21 PM CT
--   pair 2   arms 85a2c137 / 45717e4a   (sim_run_seq 1751 / 1752)  3:40 PM CT
--
--   outcome passed, equal true, endst equal - both pairs.
--   canons IDENTICAL ACROSS BOTH PAIRS:
--     h_cmd 04177a2a5d686032aa1c54fcac43f958
--     h_dec 5328154a5f72e9e1bb6b10d177def459
--     h_bkg 0bf42b3cc1b2db78de9e91274d28b3df
--     h_nrg 8dcf8918702a18b9f20022b80dd24513
--
--   ottoq_cert_matrix at the recert floor: pairs_seen 2, consecutive_passes 2,
--   green TRUE. One of six columns re-certified at the new floor.
--
-- Against round 7's canons (04177a2a / 1c9ace35 / 0bf42b3c / e6425186):
-- h_cmd and h_bkg did NOT move; h_dec and h_nrg did. That is the expected shape.
-- h_dec moved because 0156 adds headroom_kw / fits_headroom / power_downgrade to
-- the decision rationale. h_nrg moved because 0155 stopped the twin meter
-- reporting 0.00 kW. h_bkg holding means the ASSIGNMENTS did not change on this
-- column - which is the honest reading of today's engine work on the flagship.
--
--
-- §3  Today's engine fixes are a no-op on this flagship column
-- ------------------------------------------------------------
-- ottoq_kpi_dispatch_readiness, pre-fix run 0864b2df vs post-fix run 25944bde:
--
--   visits_with_due 63, on_time 26, late 12, stranded 8, no_charge_needed 17,
--   p50_late 150.0 min, p95_late 285.0, max_late 285.0, on_time_pct 56.5
--
-- Identical. Every field. 0156's fit-ordering only bites when site headroom
-- binds, and on the flagship at 12 ticks it does not: peak demand 805.4 kW
-- against a far larger cap. The improvement I measured this morning (AV-01
-- 73->100, AV-02 60->96, EN.001 blocks 17->0) was on the TIGHT-CAP GRID FIXTURE,
-- where the cap binds by construction. Both statements are true and they are not
-- the same statement. The fix is real; its blast radius on this column is zero.
--
-- Also correcting a number I gave Chase this morning: readiness "80% on time"
-- was a different run key, not this column. On busy_day/171717/12t the figure is
-- and was 56.5%.
--
-- peak_site_kw moved 500.3 -> 919.6 and peak_site_kw_demand 381.6 -> 805.4
-- between the pre- and post-0155 engines. That is the meter fix landing on the
-- flagship: the site meter now reports the power that flowed.
--
--
-- §4  DEFECT - the reproducibility key was not reproducible (0167)
-- ----------------------------------------------------------------
-- ottoq_run_archives.config_hash was md5(ottoq_sim_runs.payload::text). The
-- payload is the run's OUTCOME - it carries boot_draw.drawn_at (wall clock),
-- boot_draw.draw_ms, need_profiles.ms and inbound_forecast.sim_run_id. So the
-- two arms of a pair that are byte-identical on commands, decisions, bookings,
-- energy and end state were handed DIFFERENT keys:
--
--   pair 1658/1659   17c661d3... / e6e1cfce...
--   pair 1748/1749   e55954bf... / f8d2a9b4...
--
-- "No number ships without a run ID" cannot rest on a key that changes when the
-- configuration did not. 0072 §6a named this; it was not built. 0167 builds it.
--
--   config_hash is now md5(ottoq_run_config_key(run)) - scenario, seed, policy,
--   depot, ticks, tick interval, pinned sim clock, time scale, and the EFFECTIVE
--   policy params resolved run -> depot -> global exactly as ottoq_policy_get
--   resolves them. The projection itself is stored as config_key, so a reader
--   can see WHY two runs differ, not only THAT they do.
--
--   Verified: all four runs above collapse to d011095c4b5f8492c1630bb79d6bc086.
--
-- That collapse exposed the other half. 1658/1659 (pre-0155 engine, peak 500.3)
-- and 1748/1749 (post-0155, peak 919.6) now share a config_hash, because they
-- ARE the same configuration. What differs is the engine. So the archive also
-- stamps engine_hash = md5 over the applied migration set at archive time -
-- 608728d1979ff24157ca09512e9352af over 823 migrations as of 0167. Configuration
-- and engine are two axes; the key now carries both. Pre-0167 archives keep
-- engine_hash NULL: which engine produced them is not reconstructable, and
-- guessing would be worse than admitting it.
--
--
-- §5  DEFECT - p95_time_to_service could not return a non-zero number (0167)
-- --------------------------------------------------------------------------
-- CLAUDE.md 2.9 defines KPI 5 as "recall-complete -> first op ACTIVE". The view
-- measured actual_return_at -> min(lower(ottoq_stall_bookings.during)): the
-- CALENDAR CLAIM, not the physical start. The twin stamps
-- actual_return_at = p_sim_clock_now and the decide path books on that same tick
-- with during starting at that same instant. Measured on run 25944bde:
--
--   116 returns, 116 exactly zero, max 0.0 min, mean 0.00.
--
-- Reported p95: 0.0. returns_unserved: 0. A check that cannot fail is not a
-- check, and this one is one of the five canonical KPIs - the one that is
-- supposed to answer "how long does an asset wait."
--
-- 0167 measures to ottoq_itinerary_legs.actual_start_sim - when an operation
-- actually went active - excluding leg_type taxi (the inter-point move) and
-- stage (parking), which are not service. Same run:
--
--   p95 210.0 min, p50 30.0, max 270.0, 17 of 116 genuinely instant.
--
-- This is the physical side of "assignment plus verification, always." The old
-- view read only the assignment side and called it service.
--
-- FALSIFICATION - a KPI that returns one constant is still a tautology, so the
-- new one was swept across 14 runs before being trusted:
--
--   busy_day  171717 12t   p95 210.0   unserved 0   (seq 1748,1749,1751,1752)
--   busy_day  424242 12t   p95 244.5   unserved 0   (seq 1686-1689)
--   busy_day  171717 24t   p95 210.0   unserved 3   (seq 1680-1683)
--   normal_day 171717 12t  p95 150.0   unserved 0   (seq 1676,1677)
--
-- It varies by scenario and by seed, and it is identical within every arm pair.
-- That is what a reproducible KPI that measures something looks like.
--
-- And it surfaces a finding the old view could not: 3 assets on the 24-tick runs
-- returned to the depot and never had a single service operation go active
-- across the whole horizon. The old view scored those as served, because a
-- booking existed for them.
--
--
-- §6  CORRECTION - ottoq_kpi_five's provenance told a live falsehood
-- ------------------------------------------------------------------
-- The function declared peak_site_kw not_reproducible, citing a twin battery
-- "not yet deterministic". Counted over the last 40 certified determinism pairs:
--
--   peak_site_kw         equal in 40, differing in 0
--   peak_site_kw_demand  equal in 40, differing in 0
--
-- 0072 §6a had already flagged the text as stale and it shipped anyway inside
-- every KPI response. 0167 retires it and replaces it with the count, so the
-- claim is falsifiable rather than asserted. The replacement text says to re-run
-- the count before quoting the line.
--
--
-- §7  What is still open
-- -----------------------
--  a. Five of six certification columns have no pair since this morning's five
--     forces_recert migrations. r8a-r8e fired 4:03-4:45 PM CT to close that:
--     314159/12t, 424242/12t, normal_day 171717/12t, 171717/24t, 424242/24t.
--     Each needs a SECOND pass before its column is green.
--  b. The 3 unserved assets on busy_day/171717/24t (§5) are unexplained. They
--     are the same class as the 8 stranded in the readiness KPI and the 24
--     never-reconsidered mid-charge faults in 0076 §12. One deterministic floor
--     probably closes all three.
--  c. ottoq_kpi_p95_time_to_service uses a correlated subquery per dispatch and
--     is too slow to sweep more than a handful of runs (60s timeout at 25 runs).
--     The set-based form in §5's falsification does the same work in one pass.
--     The view should be rewritten in that shape before the KPI CLI depends on
--     it. Not done here; it is a performance fix, not a correctness one.
--  d. Task #47 unchanged: the streak restarts at the new floor. Bar still
--     proposed at 8 consecutive corrected passes, not closed unilaterally.
--
--
-- §8  Queries
-- ------------

-- 8.1 the pair verdicts (read these, NOT cron.job_run_details)
SELECT sim_run_seq,
       (validation_notes::jsonb)->>'outcome' AS outcome,
       (validation_notes::jsonb)->>'equal'   AS equal,
       left((validation_notes::jsonb)->'arm_a'->>'h_cmd',8) AS cmd,
       left((validation_notes::jsonb)->'arm_a'->>'h_dec',8) AS dec,
       left((validation_notes::jsonb)->'arm_a'->>'h_bkg',8) AS bkg,
       left((validation_notes::jsonb)->'arm_a'->>'h_nrg',8) AS nrg
  FROM ottoq_sim_runs
 WHERE validation_notes LIKE '%outcome%'
 ORDER BY sim_run_seq DESC LIMIT 12;

-- 8.2 the matrix at the floor
SELECT left(depot::text,8) AS depot, seed, ticks, scenario, pairs_seen,
       consecutive_passes, green, left(canon_cmd,8) AS cmd, left(canon_dec,8) AS dec,
       left(canon_bkg,8) AS bkg, left(canon_nrg,8) AS nrg,
       to_char(last_pair_at AT TIME ZONE 'America/Chicago','HH12:MI AM') AS last_ct
  FROM public.ottoq_cert_matrix(public.ottoq_cert_recert_floor())
 ORDER BY scenario, seed, ticks;

-- 8.3 the run key is arm-stable (the 0167 claim)
SELECT r.sim_run_seq, a.config_hash, a.engine_hash
  FROM public.ottoq_run_archives a JOIN public.ottoq_sim_runs r USING (sim_run_id)
 WHERE r.sim_run_seq IN (1658,1659,1748,1749,1751,1752) ORDER BY r.sim_run_seq;

-- 8.4 time to service, the set-based form (fast; §7c wants the view rewritten to this)
WITH runs AS (SELECT sim_run_id, sim_run_seq, scenario_code, random_seed, tick_count
                FROM ottoq_sim_runs WHERE status='completed' ORDER BY sim_run_seq DESC LIMIT 14),
f AS (
  SELECT d.sim_run_id, d.vehicle_id, d.actual_return_at,
         min(l.actual_start_sim) FILTER (WHERE l.actual_start_sim >= d.actual_return_at) AS first_op
    FROM ottoq_vehicle_dispatches d
    JOIN runs USING (sim_run_id)
    LEFT JOIN ottoq_itinerary_legs l
      ON l.sim_run_id = d.sim_run_id AND l.vehicle_id = d.vehicle_id
     AND l.leg_type NOT IN ('taxi','stage') AND l.actual_start_sim IS NOT NULL
   WHERE d.actual_return_at IS NOT NULL
   GROUP BY 1,2,3)
SELECT r.sim_run_seq, r.scenario_code, r.random_seed, r.tick_count, count(*) AS returns,
       round(percentile_cont(0.95) WITHIN GROUP (
         ORDER BY EXTRACT(epoch FROM f.first_op - f.actual_return_at)/60.0)::numeric,1) AS p95_min,
       count(*) FILTER (WHERE f.first_op IS NULL) AS unserved
  FROM f JOIN runs r USING (sim_run_id)
 GROUP BY 1,2,3,4 ORDER BY 1 DESC;

-- 8.5 the peak_site_kw reproducibility count that §6 rests on
WITH v AS (
  SELECT (validation_notes::jsonb)->'arm_a'->>'run' AS a,
         (validation_notes::jsonb)->'arm_b'->>'run' AS b
    FROM ottoq_sim_runs WHERE validation_notes LIKE '%outcome%'
   ORDER BY sim_run_seq DESC LIMIT 40)
SELECT count(*) AS pairs,
       count(*) FILTER (WHERE pa.peak_site_kw_15min =  pb.peak_site_kw_15min) AS peak_equal,
       count(*) FILTER (WHERE pa.peak_site_kw_15min <> pb.peak_site_kw_15min) AS peak_differs
  FROM v
  LEFT JOIN public.ottoq_kpi_peak_site_kw pa ON pa.sim_run_id = v.a::uuid
  LEFT JOIN public.ottoq_kpi_peak_site_kw pb ON pb.sim_run_id = v.b::uuid;
