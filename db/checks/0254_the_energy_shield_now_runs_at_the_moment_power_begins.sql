-- 0254  FIVE BLOCK RULES THAT HAD NEVER EXECUTED NOW GATE EVERY CHARGE SESSION.
--       38 OF 38 SESSIONS, 190 EVALUATIONS, MEASURED ON A LIVE RUN.
--
-- The after-measurement for G74, closed by migrations 0355 (applied
-- 20260919235525) and 0356 (applied 20260919235738). db/checks/0253 opened it.
--
-- ══ 1. WHAT CHANGED, IN TWO ROWS ═══════════════════════════════════════════
--
--                                          BEFORE            AFTER
--   EN.001 real evaluations       0 of 8,219 at task_start   38 of 38 at
--                                (100% abstentions)          charge_session_start
--   rules evaluated at the
--   moment power actually flows            0 of 5            5 of 5
--
-- Measured on run 92a6ac36 (busy_day, twin depot, rule 8), first 7 ticks:
-- **38 charge sessions, 190 evaluations, 5 distinct rule codes** — and
-- 190 = 38 × 5 exactly, so every session was gated by every rule. Q1 asserts that
-- arithmetic rather than reporting it.
--
-- EN.001 specifically: **38 of 38 carry `en001_evaluated = true` and a measured
-- `headroom_kw`**, minimum 95.6 kW. Zero abstentions at this context, because the
-- probe supplies the load the rule needs. At `task_start` it abstained 8,219 times
-- out of 8,219 for exactly the opposite reason.
--
-- ══ 2. THE FINDING WAS BIGGER THAN THE FILE THAT OPENED IT ═════════════════
--
-- 0253 found one rule failing open. Chasing the fix found that
-- `charge_session_start` is declared by FIVE active rules and every one is
-- `enforcement='block'`:
--
--   EN.001.grid_capacity_ceiling        block  safety_critical
--   EN.002.stall_power_ceiling          block  critical
--   EN.004.demand_response_compliance   block  critical
--   EN.005.grid_event_hardstop          block  safety_critical
--   HW.002.charger_state_precondition   block  critical
--
-- None had ever been evaluated, because nothing had ever probed there. So the
-- whole energy-safety cluster between the orchestrator and the switchgear was
-- dark. Four more of G44's nine no-caller rules are now called.
--
-- ══ 3. AND A LATENT BLOCKING BUG IN HW.002, WHICH THE PRE-FLIGHT FOUND ═════
--
-- Its allowed-states fallback read:
--
--     COALESCE(ARRAY(SELECT jsonb_array_elements_text(p_parameters->'allowed_states')),
--              ARRAY['Available'])
--
-- `ARRAY(SELECT ...)` over a NULL input returns an EMPTY ARRAY, never NULL, so
-- COALESCE could not reach the fallback, `v_allowed_states` stayed `'{}'`, and
-- `station_state = ANY('{}')` is always false. **Called with empty parameters this
-- block rule REJECTED EVERY CHARGER, healthy Available ones included.** Dormant
-- only because the rule's registered `default_parameters` do supply
-- `allowed_states` — and dormant *behind* the other defect, since nothing probed
-- the context where it fires. Repaired in 0355 with an explicit guard; production
-- behaviour unchanged, which 0355's A6 asserts in both directions (an Available
-- charger must still pass, a Faulted one must still fail).
--
-- ══ 4. MEASURED, NOT ENFORCED — AND WHY THAT IS NOT TIMIDITY ═══════════════
--
-- The probe records and does not refuse a session, even on `would_block`.
-- CLAUDE.md 2.9a: measured first, enforced after a flagship round, the order
-- 0139 / 0206 / 0217 / 0225 and 0353 all followed. The pre-flight is what makes
-- that a judgement rather than a hedge: all five evaluators were shadow-called
-- against the live run BEFORE any change (they are all `STABLE` and none writes,
-- which is what made that safe), and with each rule's own registered parameters
-- and the sim clock all five passed on a healthy charger. Measured after wiring:
-- 190 of 190 evaluations passed, 0 `would_block`.
--
-- Promotion to enforcing reads `ottoq_shield_probe.would_block`, which is why the
-- probe calls that function (9 columns, including it) and not
-- `ottoq_evaluate_rules_for_action` (5, without).
--
-- ══ 5. FOUR PLACEMENT TRAPS, EACH ALREADY PAID FOR ONCE IN THIS REPO ═══════
--
-- 1. BEFORE the `INSERT INTO ocpp_sessions`. EN.001 reads
--    `ottoq_depot_current_demand_kw(depot, now_ts)`; after the insert that sum
--    already contains the session being started, so the check would double-count
--    its own load — wrong by one car, in the direction that makes the depot look
--    closer to its cap than it is. 0356's A1c asserts the ordering, not merely
--    the presence.
-- 2. `p_entity_id := p_stall_id`, never `v_session_id`. The session id is
--    `gen_random_uuid()` and differs between determinism-pair arms, and
--    `ottoq_hash_rule_evaluations` DIGESTS `entity_id` — every certification pair
--    would have disagreed on `h_rule`. Fifth instance of 0139's class after 0137,
--    0139, 0280, 0353; A4 asserts both halves.
-- 3. `now_ts := v_clock`, the sim clock. Wall clock makes every charger read hours
--    stale against HW.002's 90-second threshold and refuses the whole depot.
-- 4. Wrapped in `EXCEPTION WHEN OTHERS THEN RAISE WARNING` — a shield probe must
--    never abort a charge session.
--
-- ══ 6. THREE WRONG READINGS THIS WORK PRODUCED, ALL CAUGHT BEFORE SHIPPING ══
--
-- (a) "HW.002 would block 36 of 36 sessions." My shadow passed `'{}'` as
--     `p_parameters`; the shield passes the rule's registered defaults. Believed,
--     this would have "fixed" a rule that was not broken — or, acted on the other
--     way, enforced a rule that refuses every session.
-- (b) "The chargers are all offline." I passed wall-clock `now()` against
--     heartbeats stamped on the sim clock. Against the sim clock 39 of 40 are
--     fresh to the second (`ottoq_world_advance` restamps every tick); the one
--     stale charger is the Faulted one, correctly stale.
-- (c) G74 as filed said the abstention was "indistinguishable from a real check by
--     any count that does not parse the reason string." **Wrong** — abstentions
--     returned `'{}'::jsonb` while every other path returned keys, so
--     `result_payload = '{}'` already identified them exactly (10,787 of 10,787
--     measured). The real defect was weaker: an undocumented convention nothing
--     asserted. 0355's `en001_evaluated` makes it a labelled fact, and FINDINGS.md
--     carries the correction.
--
-- And one precondition defect the read-only dry-run caught, which would have
-- aborted 0355: `prosrc LIKE '%charge_session_start%'` returned TRUE while
-- `position()` returned 0, because **`_` is a LIKE wildcard** and the pattern
-- matched the `charge.session_started` event type the function already emits.
-- Both 0355 P5 and 0356 P4 now use `position()`.
--
-- ══ 7. WHAT IS STILL OPEN ══════════════════════════════════════════════════
--
-- * Not enforced. Promotion is a deliberate later step (see §4).
-- * `power_increase` is the sixth declared-never-called energy context and stays
--   uncalled: it needs a throttle path that does not exist.
-- * `task_start`'s abstentions remain, correctly — most task starts carry no load.
--   What changed is that they no longer present themselves as grid checks.
-- * G44 is reduced, not closed.
-- * AND THE GRID IS NOT THIS DEPOT'S BINDING CONSTRAINT. Worst case measured was
--   712.6 kW against a 1,620 kW engineering cap, with L2/DCFC stalls at 87%/80%
--   occupancy — roughly **908 kW spare at peak**. This depot is STALL-constrained,
--   not power-constrained, which is the answer to "how many vehicles can we
--   orchestrate here": add charge points, not service capacity.
--
-- Nothing in this file changes engine state.
--
-- ── THE QUERIES ────────────────────────────────────────────────────────────

-- Q1  §1's headline as an assertion: every charge session gated by every rule.
--     A count that does not equal sessions × rules means the probe is missing
--     sessions or firing twice, and either is a defect.
WITH r AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY started_at DESC LIMIT 1
)
SELECT (SELECT count(*) FROM public.ocpp_sessions o, r WHERE o.sim_run_id = r.sim_run_id) AS sessions,
       (SELECT count(*) FROM public.ottoq_rule_evaluations e, r
         WHERE e.sim_run_id = r.sim_run_id AND e.action_context = 'charge_session_start') AS evaluations,
       (SELECT count(DISTINCT e.rule_code) FROM public.ottoq_rule_evaluations e, r
         WHERE e.sim_run_id = r.sim_run_id AND e.action_context = 'charge_session_start') AS distinct_rules,
       (SELECT count(*) FROM public.ottoq_rule_evaluations e, r
         WHERE e.sim_run_id = r.sim_run_id AND e.action_context = 'charge_session_start')
         = (SELECT count(*) FROM public.ocpp_sessions o, r WHERE o.sim_run_id = r.sim_run_id) * 5
         AS every_session_gated_by_all_five;

-- Q2  §1's second half: EN.001 does REAL work at this context, and says so.
WITH r AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY started_at DESC LIMIT 1
)
SELECT count(*)                                                                   AS en001_evals,
       count(*) FILTER (WHERE (e.result_payload->>'en001_evaluated')::boolean)      AS really_evaluated,
       count(*) FILTER (WHERE e.result_payload ? 'headroom_kw')                     AS with_measured_headroom,
       round(min((e.result_payload->>'headroom_kw')::numeric),1)                     AS min_headroom_kw,
       count(*) = count(*) FILTER (WHERE (e.result_payload->>'en001_evaluated')::boolean)
                                                                                   AS no_abstentions_here
  FROM public.ottoq_rule_evaluations e, r
 WHERE e.sim_run_id = r.sim_run_id
   AND e.action_context = 'charge_session_start'
   AND e.rule_code LIKE 'EN.001%';

-- Q3  §2: the five rules, and that they are now CALLED rather than merely
--     declared. `declared` comes from ottoq_rules; `evaluated_ever` from the
--     ledger. Before 0356 the second column was 0 for all five.
SELECT ru.rule_code, ru.enforcement, ru.severity,
       (SELECT count(*) FROM public.ottoq_rule_evaluations e
         WHERE e.rule_code = ru.rule_code
           AND e.action_context = 'charge_session_start')  AS evaluated_ever
  FROM public.ottoq_rules ru
 WHERE ru.status = 'active'
   AND ru.applies_to_actions @> ARRAY['charge_session_start']::text[]
 ORDER BY ru.rule_code;

-- Q4  §4: measured, not enforced. Nothing was refused, and this is the query that
--     decides whether promotion to enforcing is safe. A non-zero `would_block`
--     count here is the signal to investigate before promoting, not to promote.
WITH r AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY started_at DESC LIMIT 1
)
SELECT count(*)                                              AS evaluations,
       count(*) FILTER (WHERE e.passed)                       AS passed,
       count(*) FILTER (WHERE NOT e.passed)                   AS failed,
       count(*) FILTER (WHERE e.enforcement_taken <> 'allowed') AS anything_actually_blocked
  FROM public.ottoq_rule_evaluations e, r
 WHERE e.sim_run_id = r.sim_run_id AND e.action_context = 'charge_session_start';

-- Q5  §5(1): the ordering property, checked against the live function body rather
--     than trusted. The probe must PRECEDE the insert or EN.001 double-counts the
--     session's own load.
SELECT position('ottoq_shield_probe' in p.prosrc)                AS probe_at,
       position('INSERT INTO ocpp_sessions' in p.prosrc)          AS insert_at,
       position('ottoq_shield_probe' in p.prosrc)
         < position('INSERT INTO ocpp_sessions' in p.prosrc)      AS probe_precedes_insert
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_start_charge_session';

-- Q6  §5(2): the arm-stable entity, and the minted id absent. Fifth instance of
--     0139's class, so this is a test rather than a comment.
SELECT position('p_entity_id         := p_stall_id' in p.prosrc) > 0   AS passes_stall_id,
       position('p_entity_id         := v_session_id' in p.prosrc) = 0 AS never_passes_session_id
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_start_charge_session';

-- Q7  §3: the HW.002 repair, both directions. Empty parameters must now accept an
--     Available charger, and the rule must still refuse a Faulted one — a fix that
--     turned it into a rubber stamp would pass the first half and fail this.
WITH hb AS (SELECT max(last_heartbeat_at)::text AS ts FROM public.ottoq_ocpp_chargers),
ok AS (
  SELECT s.id FROM public.stalls s
    JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
     AND c.station_state = 'Available' AND c.last_heartbeat_at IS NOT NULL
   ORDER BY s.stall_code LIMIT 1),
bad AS (
  SELECT s.id FROM public.stalls s
    JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
     AND c.station_state = 'Faulted'
   ORDER BY s.stall_code LIMIT 1)
SELECT (SELECT (public.ottoq_eval_hw_002_charger_state('stall', ok.id,
          jsonb_build_object('stall_id', ok.id::text, 'now_ts', (SELECT ts FROM hb)),
          '{}'::jsonb)).passed FROM ok)                       AS available_passes_with_empty_params,
       (SELECT (public.ottoq_eval_hw_002_charger_state('stall', bad.id,
          jsonb_build_object('stall_id', bad.id::text, 'now_ts', (SELECT ts FROM hb)),
          '{}'::jsonb)).passed FROM bad)                      AS faulted_still_refused_expect_false;

-- Q8  §6(c): the correction to G74. `result_payload = '{}'` DID identify
--     abstentions before 0355, which is why the "not countable" claim was wrong.
--     Kept so the record shows the convention held and was simply unasserted.
SELECT count(*)                                                        AS en001_total,
       count(*) FILTER (WHERE e.result_payload = '{}'::jsonb)           AS legacy_empty_payload,
       count(*) FILTER (WHERE e.reason = 'no depot/request context')    AS legacy_abstention_reason,
       count(*) FILTER (WHERE e.result_payload ? 'en001_evaluated')     AS labelled_since_0355
  FROM public.ottoq_rule_evaluations e
 WHERE e.rule_code LIKE 'EN.001%';
