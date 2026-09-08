-- ---------------------------------------------------------------------------
-- 0122 — G7: what was missing, and what 0211/0212 made real.
--
-- CLAUDE.md 2.7: "Work-side refusal (mission overrun) is a first-class event
-- triggering re-solve, never an error." Traced 2026-09-08, it was not one.
--
-- Readings below were taken against gxdrcyphqjzjsuhxuqtg. Q1 and Q2 record the
-- BEFORE state and will now read differently — that is the point of keeping
-- them, not a reason to update them.
-- ---------------------------------------------------------------------------

-- Q1. FIVE CANONICAL EVENT TYPES, REGISTERED IN AUGUST, NEVER ONCE EMITTED.
--     Registered by migration 0045 on 2026-08-19 with descriptions that read
--     as though they were load-bearing. recall_refused's says: "Canonical: the
--     work side refused a recall — first-class, triggers re-solve (C9)."
--
--     BEFORE 0212:  every one of the five at 0.
--     AFTER  0212:  recall_refused > 0; the other four still 0.
--
--     recall_issued is deliberately still 0. Emitting it would fire on every
--     recall in every run and move h_evt on every certified column at once —
--     a recert to schedule, not a side effect to discover.
SELECT c.event_type, c.introduced_in, c.emitter,
       (SELECT count(*) FROM ottoq_events e WHERE e.event_type = c.event_type) AS emitted
FROM ottoq_event_types_catalog c
WHERE c.event_type IN ('recall_issued','recall_refused','move_start','move_end','touch_event')
ORDER BY c.event_type;

-- Q2. THE TWIN COULD VARY THE WEATHER BUT NOT THE MISSION.
--     Six domains, no work_side. The twin can perturb the grid, the staff, the
--     chargers and the vehicles; it could not perturb whether the system that
--     owns the mission lets an asset go.
--
--     RESULT 2026-09-08: energy_grid 7, environment 7, fleet_demand 7,
--     operations 11, reliability 7, vehicle 8. No work_side row.
--
--     0211 put the knob in the POLICY catalog rather than here, beside
--     recall_implementation_id, because that is where the recall subsystem's
--     other tunables live and where ottoq_policy_get looks.
SELECT domain, count(*) AS knobs FROM ottoq_variability_catalog GROUP BY domain ORDER BY domain;

-- Q3. THE SEAM AND ITS TWO PARAMETERS.
--     RESULT 2026-09-08: both present; rate default 0, hold default 90.
SELECT param_key, default_value, min_value, max_value
FROM ottoq_policy_param_catalog
WHERE param_key LIKE 'work_side%' ORDER BY param_key;

-- Q4. THE TICK ASKS BEFORE IT BOOKS.
--     RESULT 2026-09-08: asks_work_side true, emits_refusal true,
--     md5 7777fdcb -> 35486348.
SELECT pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure)
         LIKE '%ottoq_work_side_accepts%' AS asks_work_side,
       pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure)
         LIKE '%recall_refused%'          AS emits_refusal,
       md5(pg_get_functiondef('twin.ottoq_sim_advance_deployed_telemetry(uuid,timestamptz,numeric)'::regprocedure))
                                          AS tick_md5;

-- Q5. THE SAFETY INVARIANT, MEASURED OVER EVERY REFUSAL EVER RECORDED.
--     A recall the rung ladder marks non-deferrable is coming home on a safety
--     margin and the work side may not keep it. ottoq_work_side_accepts returns
--     accepted for those without consulting the rate at all.
--
--     RESULT 2026-09-08 (6 refusals, from the rate-1.0 pair): refusals 6,
--     of non-deferrable recalls 0, distinct triggers {wash_cadence}.
--
--     This is the query to re-run after any future refusal work. A non-zero
--     second column means the invariant broke.
SELECT count(*)                                            AS refusals,
       count(*) FILTER (WHERE was_deferrable IS DISTINCT FROM true)
                                                           AS non_deferrable_refused,
       count(DISTINCT recall_trigger)                      AS distinct_triggers,
       count(DISTINCT reason_code)                         AS distinct_reasons
FROM ottoq_recall_refusals;

-- Q6. THE REFUSAL IS DETERMINISTIC, WHICH IS WHY IT MAY EXIST AT ALL.
--     The two arms of the rate-1.0 pair produced identical refusal content.
--     A refusal drawn from random() would have made the twin irreproducible,
--     and reproducibility is the property every claim in this repo rests on.
--
--     RESULT 2026-09-08: two runs, 3 refusals each, both
--     71200303b1edfec9087a3461f79cd598.
SELECT sim_run_id, count(*) AS refusals,
       md5(string_agg(content_hash, '|' ORDER BY content_hash)) AS refusal_stream_hash
FROM ottoq_recall_refusals
GROUP BY sim_run_id ORDER BY min(refused_at);
