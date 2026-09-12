-- ===========================================================================
-- 0171  THE INTENT RANKS ELEVEN OBJECTIVES AND THE DATABASE CAN COMPUTE TWO
-- ===========================================================================
-- Measured 2026-09-12 04:00-04:05 UTC (2026-09-11 11:00 PM CT), read-only, against
-- the live catalog and intent/intent_v1.json (fingerprint_md5
-- a2214eeaf222514dba85f55dd9323e08, generated 2026-09-06). Taken while round 37's
-- first pairs were firing; nothing here writes or scans a run-scoped table.
--
-- WHY THIS EXISTS. BUILD_QUEUE #4 said "no objective function (G45)". That was
-- wrong in the direction that flatters nobody: the objective exists, is declared,
-- ranked, regime-aware and SOURCED. What does not exist is the ability to COMPUTE
-- it where the decisions are made. This file measures exactly that gap, objective
-- by objective, because "wire the proposer in" is not actionable until you know
-- what the disposer would be able to read.
--
-- ---------------------------------------------------------------------------
-- WHAT THE INTENT ACTUALLY DECLARES (read from the artifact, not summarised)
-- ---------------------------------------------------------------------------
--
-- ELEVEN objectives, each carrying direction, kind, metric, dollar_value and
-- provenance. TWO are kind='floor' rather than 'objective': readiness and
-- service_completion. SIX regimes, selected by signal or hour range:
--
--   weather_event   readiness, service_completion, risk_hedge, degradation
--   grid_peak       bess_peak_shave, energy_cost, risk_hedge, degradation
--   demand_surge    readiness, throughput, deadhead, staging
--   dispatch_rush   readiness, throughput, deadhead, energy_cost     (hours 5-10)
--   overnight       service_completion, energy_cost, degradation, dwell (20-5)
--   steady_state    all eleven, in order: readiness, service_completion,
--                   energy_cost, degradation, throughput, deadhead, staff, dwell,
--                   staging, bess_peak_shave, risk_hedge
--
-- AND THE NUMERAIRE IS A REFUSAL, WHICH IS THE BEST THING IN THE FILE:
--
--   "lexicographic -- objectives are ordered by priority, never summed into a
--    single dollar scale"
--   reason: "R-10: no robotaxi operator has published a dollar value for a late
--    minute or an unready vehicle. A weight would be a price on lateness nobody
--    agreed to. Readiness is therefore a floor, not a coefficient."
--
-- That is a sourced design decision, not a placeholder. Six of eleven objectives
-- carry dollar_value='NOT_FOUND' with the reason recorded. So R-13's "which
-- structure -- weighted sum, lexicographic, or epsilon-constraint" question is
-- already answered and evidenced; R-13 has been narrowed in place accordingly.
--
-- ---------------------------------------------------------------------------
-- WHAT THE DATABASE CAN COMPUTE. Searched every non-internal routine in public,
-- ottoq and twin, plus every column name in those schemas, for each declared
-- metric.
-- ---------------------------------------------------------------------------
--
--   objective           declared metric           routines  cols  computed by
--   ------------------  ------------------------  --------  ----  -----------------------
--   bess_peak_shave     site_peak_kw                     4     2  ottoq_kpi_five(_raw)  YES
--   staff               touch_events_per_turn            2     1  ottoq_kpi_five(_raw)  YES
--   throughput          vehicles_cycled                  1     1  ottoq_score_run       partial
--   energy_cost         monthly_total_usd                4     4  no scorer             BLOCKED
--   dwell               dwell_minutes                    2     0  no scorer             no
--   deadhead            empty_moves                      0     0  --                    no
--   degradation         capacity_fade                    0     0  --                    no
--   readiness           tardy_minutes                    0     0  --                    no
--   risk_hedge          robustness_band                  0     0  --                    no
--   service_completion  service_completion_rate          0     0  --                    no
--   staging             staging_footprint                0     0  --                    no
--
-- TWO OF ELEVEN. The shipped payload (ottoq_kpi_five) computes the declared metric
-- for exactly bess_peak_shave and staff -- which the intent ranks TENTH and SEVENTH
-- in steady_state.
--
-- ---------------------------------------------------------------------------
-- THE FINDING, AND IT IS SHARPER THAN "SOME METRICS ARE MISSING"
-- ---------------------------------------------------------------------------
--
-- `readiness` is ranked FIRST in four of the six regimes -- weather_event,
-- demand_surge, dispatch_rush and steady_state -- and it is a FLOOR, meaning it
-- outranks every objective below it rather than trading against them. Its declared
-- metric is `tardy_minutes`.
--
-- THE STRING 'tardy' APPEARS IN ZERO ROUTINES AND ZERO COLUMN NAMES IN THIS
-- DATABASE. Not in a KPI, not in a view, not in the decide path. The engine has no
-- representation of lateness at all.
--
-- It exists in exactly one place in the company: the CP-SAT prototype, as
-- `min_tardy`, the first pass of every regime sequence (policies/regime.py
-- prepends the readiness floor to every regime, so min_tardy is always pass 1).
-- So tardiness is a first-class quantity in the component with no callers and a
-- non-concept in the component that decides.
--
-- `service_completion` is ranked first in `overnight` and second in steady_state
-- and weather_event. Also a floor. Also zero routines, zero columns.
--
-- SO THE TWO FLOORS -- the two quantities the declared intent says must be
-- satisfied before anything else is even considered -- ARE THE TWO THE ENGINE
-- CANNOT MEASURE. Wiring the proposer in today would produce proposals optimised
-- against a ranking whose top two terms the disposer cannot evaluate, and an A/B
-- between them would be decided entirely by the tenth- and seventh-ranked terms,
-- because those are the only ones with numbers. That is how you ship a number that
-- is arithmetically correct, carries a run ID, and measures the wrong thing --
-- db/checks/0146's lesson in a new place.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS CHANGES ABOUT THE BUILD ORDER (the actionable part)
-- ---------------------------------------------------------------------------
--
-- BUILD_QUEUE #4 was re-scoped to "wire the proposer to the disposer". That is
-- still the destination but it is NOT the next step. The order is forced:
--
--   1. tardy_minutes, run-scoped. The floor must be computable before anything can
--      be said to respect it. Needs a per-run required-ready time and a per-run
--      actual-ready time. `dispatch_due_at` already carries the deadline for
--      exactly the urgency classes that have one (`0164`/BUILD_QUEUE 8d:
--      overnight_hold 100%, immediate_dispatch 100%, standard 0%, tech_hold 0%) --
--      so the denominator question is already settled and must be carried over,
--      not re-litigated: a standard visit cannot be late.
--   2. service_completion_rate, run-scoped. The second floor.
--   3. energy_cost. BLOCKED TWICE: by the empty settlement rail (`0168` --
--      220,946 SDRs, 100% with tariff_id, 0% with cost) and by a question only
--      Chase can answer (may twin-simulated energy produce a dollar figure that
--      looks like production revenue?). Until then the third-ranked objective is
--      unscorable and that must be stated wherever a score is shown.
--   4. THEN the declared intent becomes data in the database -- ottoq_intent plus
--      ranked objectives, content-hash pinned to intent_v1.json's own
--      fingerprint_md5 so repo and engine can be PROVEN identical rather than
--      assumed so -- and `ottoq_objective_score(p_run)` returns the lexicographic
--      VECTOR (never a scalar; the numeraire forbids summing) with an explicit
--      `unscorable` list naming every term it could not compute.
--   5. THEN the proposer wiring, through ottoq_submit_external_proposal under the
--      existing deferral pattern, registered in ottoq_certified_proposers, hashed
--      into h_prop. Infrastructure question deferred to then: the Python solver is
--      a repo-local library, and the only precedent for reaching out of the
--      database is the cuOpt edge function.
--
-- A scorer that silently omits its two highest-ranked terms would be worse than no
-- scorer, so step 4's `unscorable` list is not decoration -- it is the thing that
-- keeps the output honest while steps 1-3 are incomplete.
--
-- NOT MEASURED HERE: whether `ottoq_kpi_dispatch_readiness` could be adapted into
-- tardy_minutes. It reports readiness as a percentage with stranded/no-charge
-- split, not as minutes late, and BUILD_QUEUE 8c already records that its end_soc
-- reads live shared state (the 0145 class). It is a starting point, not the answer.
-- ===========================================================================

-- The measurement, re-runnable.
WITH m(objective, rank_steady, kind, metric, pat) AS (VALUES
  ('readiness',          1,'floor',    'tardy_minutes',           'tardy'),
  ('service_completion', 2,'floor',    'service_completion_rate', 'service_completion'),
  ('energy_cost',        3,'objective','monthly_total_usd',       'monthly_total_usd|total_cost_usd'),
  ('degradation',        4,'objective','capacity_fade',           'capacity_fade'),
  ('throughput',         5,'objective','vehicles_cycled',         'vehicles_cycled'),
  ('deadhead',           6,'objective','empty_moves',             'empty_moves|deadhead'),
  ('staff',              7,'objective','touch_events_per_turn',   'touch_events_per_turn'),
  ('dwell',              8,'objective','dwell_minutes',           'dwell_minutes|dwell_min'),
  ('staging',            9,'objective','staging_footprint',       'staging_footprint'),
  ('bess_peak_shave',   10,'objective','site_peak_kw',            'peak_site_kw|site_peak_kw'),
  ('risk_hedge',        11,'objective','robustness_band',         'robustness_band')
)
SELECT m.rank_steady AS steady_state_rank, m.kind, m.objective, m.metric,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('public','ottoq','twin') AND p.prolang<>13 AND p.prosrc ~* m.pat) AS routines,
  (SELECT count(*) FROM information_schema.columns c
    WHERE c.table_schema IN ('public','ottoq','twin') AND c.column_name ~* m.pat) AS columns,
  COALESCE((SELECT string_agg(DISTINCT p.proname, ', ')
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname IN ('public','ottoq','twin') AND p.prolang<>13 AND p.prosrc ~* m.pat
      AND p.proname ~* 'kpi|score|objective|metric'), '--') AS scored_by
FROM m ORDER BY m.rank_steady;
