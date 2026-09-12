-- 0185  The A/B pair holds the world and the shield constant and moves only
--       the policy -- read the verdicts, the scores, and whether a re-run of
--       the same comparison came back byte-identical.
--
-- STATUS: READER for db/migrations/0261. Every query is read-only. Run after
-- 0261 is applied and at least one ottoq_ab_pair has committed. Sections 1-3 are
-- what policies/AB_TWIN.md quotes; section 4 is the reproducibility gate
-- V1_DEMO_PLAN Phase 1 names as its stopping rule ("one reproducible comparison,
-- byte-identical on re-run").
--
-- THE READING RULE. An ab_harness arm's validation_status says the INSTRUMENT
-- was valid (both arms complete, boot image and priors byte-equal). It never says
-- a policy won. The columns that say who did what are in ottoq_ab_runs, one row
-- per arm, and they are only comparable within one ab_group_id.

-- =========================================================================
-- 1. EVERY A/B VERDICT, newest first: outcome, what moved, and the leak.
--    stall_sources says who decided each enacted stall assignment. For seat 0,
--    local_heuristic is OTTO-Q's own in-tick rule; for a baseline seat the fallback
--    stamps the seat, so a fifo arm must read fifo + reservation_* and nothing else
--    (0261 A5). If it reads anything else, the seat leaked and the number is not a
--    comparison.
-- =========================================================================
WITH v AS (
  SELECT r.sim_run_id, r.started_at, r.validation_status, (r.validation_notes::jsonb) AS j
    FROM public.ottoq_sim_runs r
   WHERE r.run_by = 'ab_harness' AND r.validation_notes IS NOT NULL
     AND (r.validation_notes::jsonb)->>'kind' = 'ab_pair'
     AND (r.validation_notes::jsonb)->'arm_a'->>'run' = r.sim_run_id::text   -- one row per pair
)
SELECT started_at, j->>'outcome' AS outcome, validation_status AS instrument,
       j->>'scenario' AS scenario, j->>'seed' AS seed, j->>'ticks' AS ticks,
       j->>'seat_a' AS a, j->>'seat_b' AS b,
       j->'moved' AS moved,
       j->'arm_a'->'stall_sources' AS a_sources, j->'arm_b'->'stall_sources' AS b_sources,
       j->'arm_a'->'blocked' AS a_blocked,      j->'arm_b'->'blocked' AS b_blocked,
       (j->>'ab_group_id')::uuid AS ab_group_id
  FROM v ORDER BY started_at DESC LIMIT 20;

-- =========================================================================
-- 2. THE SCORE TABLE, per group: what the deck may quote, with the run ids.
--    NULL columns are NULL on purpose (0230's rule: no confident zeros).
-- =========================================================================
SELECT a.ab_group_id, a.scenario_code, a.seed, a.ticks, a.policy, a.sim_run_id,
       a.decisions_total, a.enacted_total, a.overrides_total,
       a.safety_violations, a.safety_critical_violations,
       a.energy_peak_kw, a.peak_demand_pct_of_cap,
       a.charge_sessions, a.vehicles_cycled, a.vehicles_turned_around,
       a.median_turnaround_min, a.throughput_per_hr, a.gate_backlog,
       a.fleet_ready_pct, a.ready_or_deployed_pct, a.scored_at
  FROM public.ottoq_ab_runs a
 WHERE a.scored_at >= now() - interval '7 days'
 ORDER BY a.ab_group_id, a.scored_at, a.policy;

-- =========================================================================
-- 3. THE DIFFERENCE, side by side, for the newest group that compared two
--    different seats. Positive delta = arm B (the baseline) is higher.
-- =========================================================================
WITH g AS (
  SELECT (j->>'ab_group_id')::uuid AS gid, j->>'seat_a' AS a, j->>'seat_b' AS b, r.started_at
    FROM public.ottoq_sim_runs r, LATERAL (SELECT r.validation_notes::jsonb AS j) x
   WHERE r.run_by = 'ab_harness' AND r.validation_notes IS NOT NULL
     AND j->>'kind' = 'ab_pair' AND j->>'outcome' IN ('compared','indistinguishable')
     AND j->'arm_a'->>'run' = r.sim_run_id::text
   ORDER BY r.started_at DESC LIMIT 1
), rows_ AS (
  SELECT a.*, row_number() OVER (PARTITION BY a.policy ORDER BY a.scored_at DESC) AS rn
    FROM public.ottoq_ab_runs a JOIN g ON a.ab_group_id = g.gid
)
SELECT g.a AS seat_a, g.b AS seat_b, m.metric, m.a_val, m.b_val, m.b_val - m.a_val AS delta_b_minus_a
  FROM g
  JOIN rows_ ra ON ra.policy = g.a AND ra.rn = 1
  JOIN rows_ rb ON rb.policy = g.b AND rb.rn = 1
  CROSS JOIN LATERAL (VALUES
    ('decisions_total',            ra.decisions_total::numeric,            rb.decisions_total::numeric),
    ('enacted_total',              ra.enacted_total::numeric,              rb.enacted_total::numeric),
    ('overrides_total',            ra.overrides_total::numeric,            rb.overrides_total::numeric),
    ('safety_violations',          ra.safety_violations::numeric,          rb.safety_violations::numeric),
    ('safety_critical_violations', ra.safety_critical_violations::numeric, rb.safety_critical_violations::numeric),
    ('energy_peak_kw',             ra.energy_peak_kw,                      rb.energy_peak_kw),
    ('peak_demand_pct_of_cap',     ra.peak_demand_pct_of_cap,              rb.peak_demand_pct_of_cap),
    ('charge_sessions',            ra.charge_sessions::numeric,            rb.charge_sessions::numeric),
    ('vehicles_cycled',            ra.vehicles_cycled::numeric,            rb.vehicles_cycled::numeric),
    ('vehicles_turned_around',     ra.vehicles_turned_around::numeric,     rb.vehicles_turned_around::numeric),
    ('median_turnaround_min',      ra.median_turnaround_min,               rb.median_turnaround_min),
    ('throughput_per_hr',          ra.throughput_per_hr,                   rb.throughput_per_hr),
    ('gate_backlog',               ra.gate_backlog::numeric,               rb.gate_backlog::numeric),
    ('fleet_ready_pct',            ra.fleet_ready_pct,                     rb.fleet_ready_pct),
    ('ready_or_deployed_pct',      ra.ready_or_deployed_pct,               rb.ready_or_deployed_pct)
  ) AS m(metric, a_val, b_val);

-- =========================================================================
-- 4. THE STOPPING RULE: a re-run of the same comparison must agree with the
--    first run on every atom, per seat. Two pairs share a group when seed,
--    ticks, scenario, depot, clock and both seats are equal (the group id IS
--    the key). For each (group, seat) with more than one arm, count distinct
--    values of each atom: 1 everywhere = byte-identical on re-run.
-- =========================================================================
WITH arms AS (
  SELECT (j->>'ab_group_id')::uuid AS gid, side,
         (j->side)->>'seat' AS seat, (j->side)->>'run' AS run, r.started_at,
         (j->side)->>'fp' AS fp, (j->side)->>'h_cmd' AS h_cmd, (j->side)->>'h_dec' AS h_dec,
         (j->side)->>'h_evt' AS h_evt, (j->side)->>'h_bkg' AS h_bkg, (j->side)->>'h_nrg' AS h_nrg,
         (j->side)->>'h_prop' AS h_prop, (j->side)->>'h_defr' AS h_defr, (j->side)->>'h_cal' AS h_cal,
         (j->side)->>'h_rule' AS h_rule, (j->side)->>'h_rcl' AS h_rcl, (j->side)->>'h_sdr' AS h_sdr,
         (j->side)->>'ticks' AS ticks, ((j->side)->'endst')::text AS endst, (j->side)->>'h_arr' AS h_arr
    FROM public.ottoq_sim_runs r
    CROSS JOIN LATERAL (SELECT r.validation_notes::jsonb AS j) x
    CROSS JOIN LATERAL (VALUES ('arm_a'), ('arm_b')) s(side)
   WHERE r.run_by = 'ab_harness' AND r.validation_notes IS NOT NULL
     AND j->>'kind' = 'ab_pair' AND j->'arm_a'->>'run' = r.sim_run_id::text
)
SELECT gid, seat, count(*) AS arms,
       count(DISTINCT fp) AS fp, count(DISTINCT h_cmd) AS h_cmd, count(DISTINCT h_dec) AS h_dec,
       count(DISTINCT h_evt) AS h_evt, count(DISTINCT h_bkg) AS h_bkg, count(DISTINCT h_nrg) AS h_nrg,
       count(DISTINCT h_prop) AS h_prop, count(DISTINCT h_defr) AS h_defr, count(DISTINCT h_cal) AS h_cal,
       count(DISTINCT h_rule) AS h_rule, count(DISTINCT h_rcl) AS h_rcl, count(DISTINCT h_sdr) AS h_sdr,
       count(DISTINCT ticks) AS ticks, count(DISTINCT endst) AS endst, count(DISTINCT h_arr) AS h_arr,
       (count(DISTINCT fp) = 1 AND count(DISTINCT h_cmd) = 1 AND count(DISTINCT h_dec) = 1
        AND count(DISTINCT h_evt) = 1 AND count(DISTINCT h_bkg) = 1 AND count(DISTINCT h_nrg) = 1
        AND count(DISTINCT h_prop) = 1 AND count(DISTINCT h_defr) = 1 AND count(DISTINCT h_cal) = 1
        AND count(DISTINCT h_rule) = 1 AND count(DISTINCT h_rcl) = 1 AND count(DISTINCT h_sdr) = 1
        AND count(DISTINCT ticks) = 1 AND count(DISTINCT endst) = 1) AS byte_identical_on_rerun
  FROM arms
 GROUP BY gid, seat
HAVING count(*) > 1
 ORDER BY gid, seat;

-- =========================================================================
-- 5. THE SEAT NEVER REACHED A CERTIFICATION ARM. Must be 0 rows, always.
-- =========================================================================
SELECT r.sim_run_id, r.run_by, p.param_key, p.param_value
  FROM public.ottoq_policy_params p
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = p.scope_id
 WHERE p.param_key = 'proposer_seat' AND r.run_by <> 'ab_harness';
