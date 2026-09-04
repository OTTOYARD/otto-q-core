-- =====================================================================
-- 0106  The atom that could be required but never retired
-- =====================================================================
-- 0105 established that busy_day is a 90-minute mass arrival followed by
-- ~20 hours of an empty depot, and asked why. This check answers it.
--
-- The depot is empty because the FLEET NEVER GOES BACK TO WORK. Not
-- because arrivals are misconfigured -- because 113 of 116 vehicles are
-- held at the depot all day by a required service that no code path in
-- the database is capable of marking complete.
--
-- Run: cd8e0796-8f5e-47e1-846a-c24ed72a4c42 (busy_day, seed 171717,
-- 48 ticks, 116-vehicle flagship fleet). Pair twin ed6ad879 agrees.
--
-- =====================================================================
-- THE SYMPTOM — THE TWIN HAS A DUTY CURVE AND DOES NOT FOLLOW IT
-- =====================================================================
-- ottoq_deploy_target_fraction is a real robotaxi duty cycle: it asks
-- for 66% of the fleet deployed at 08:00, peaking at 75% at 16:00.
-- Measured deployment against it:
--
--   sim time   target frac   should be out   actually out
--     02:00       0.006            0             116   (boot prime)
--     04:00       0.045            5              17
--     06:00       0.360           41               3
--     08:00       0.660           76               0
--     10:00       0.720           83               2
--     12:00       0.698           80               3
--     16:00       0.750           87               3
--     18:00       0.750           87               0
--     22:00       0.225           26               1
--
-- At 08:00 the twin wants 76 cars working. Zero are. For the whole
-- working day the depot holds ~113 idle vehicles.
--
-- This is not a soft miss. Of 129 dispatch records in the run, 122 are
-- boot-primed (dispatched_at < sim start) and only 7 were dispatched
-- inside the 24-hour window. The fleet arrives once and stays.
--
-- =====================================================================
-- THE CHAIN, LINK BY LINK
-- =====================================================================
-- LINK 1 — the redeploy loop runs. twin.ottoq_sim_auto_dispatch_tick is
-- called from public.ottoq_sim_decide_and_dispatch on every tick. It is
-- not disabled and it is not skipped.
--
-- LINK 2 — the brain asks for redeployments. ottoq_decisions for this
-- run holds 38 redeployment decisions (34 enacted, 4 overridden). The
-- decide path wants cars sent out.
--
-- LINK 3 — the rate cap is not the limit. deploy_release_per_tick_cap
-- defaults to 6, so 48 ticks allow up to 288 releases. 7 happened.
--
-- LINK 4 — vehicles do reach a dispatchable state. vehicle_state_log
-- for the run records charge_complete_holding -> staged_for_departure
-- 142 times. The state machine is not stuck.
--
-- LINK 5 — the hold clause. ottoq.ottoq_plan_dispatch_tick's deploy_plan
-- phase refuses any vehicle that owes work:
--
--     AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn
--        WHERE vn.vehicle_id = v.id AND vn.sim_run_id = p_sim_run_id
--          AND vn.status IN ('open','in_progress')
--          AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
--                       WHERE COALESCE((a->>'must_do')::boolean,false)
--                         AND a->>'svc' <> 'readiness_check'
--                         AND COALESCE(a->>'status','pending')
--                             NOT IN ('done','cancelled')))
--
-- The doctrine is named in the source: "always hold, no vehicle leaves
-- owing known work". It is correct policy. It is also unbounded.
--
-- LINK 6 — THE ATOM THAT CANNOT BE RETIRED. Must_do atom completion
-- across the run, by service code:
--
--   svc                    required   done   pending   % pending
--   perimeter_walkaround        113      0       113     100.0
--   interior_inspection         116     80        36      31.0
--   readiness_check             123    101        22      17.9   (exempt)
--   exterior_wash                16      8         8      50.0
--   interior_deep_clean          21     14         7      33.3
--   interior_tidy                26     18         6      23.1
--   triage_check                 19     16         3      15.8
--   charge                       73     71         2       2.7
--   item_retrieval                8      7         1      12.5
--   sensor_clean                  9      8         0       0.0
--
-- perimeter_walkaround: required 113 times, completed ZERO times. Every
-- other atom completes at least sometimes. This one never does, and it
-- is must_do, and it is not the exempted readiness_check. So 113 of 116
-- vehicles permanently owe known work and can never be redeployed.
--
-- =====================================================================
-- WHY IT CAN NEVER COMPLETE — AN OPEN PRODUCER, A CLOSED CONSUMER
-- =====================================================================
-- perimeter_walkaround appears in exactly ONE function in the entire
-- database: twin.ottoq_sim_generate_service_manifest, the function that
-- WRITES it. Nothing reads it.
--
-- The routing is total, so nothing errors:
--   public.ottoq_svc_to_leg_type('perimeter_walkaround') -> 'service'
--   (the ELSE branch, whose comment correctly insists on totality)
--
-- But retirement is NOT total. Atoms are credited on bay exit, in
-- twin.ottoq_sim_advance_service_flow STEP 1, only for vehicles in
-- in_wash_bay / in_detail_bay / in_service_bay, and only for the atoms
-- the bay's purpose declares:
--
--   ottoq.ottoq_bay_purpose_atoms('wash')    = exterior_wash, sensor_clean
--   ottoq.ottoq_bay_purpose_atoms('detail')  = interior_deep_clean,
--                                              exterior_wash, interior_tidy
--   ottoq.ottoq_bay_purpose_atoms('service') = mechanical_pm,
--                                              sensor_calibration,
--                                              fault_repair, cosmetic_repair
--   ottoq.ottoq_bay_purpose_atoms('inspect') = interior_inspection
--
-- perimeter_walkaround is in none of them. A vehicle routed to a service
-- bay for it exits the bay with the atom still pending. Forever.
--
-- The architecture states this asymmetry deliberately, in
-- ottoq_bay_purpose_atoms' own header:
--
--     "(Twin vocabulary is OPEN; OTTO-Q's is CLOSED.)"
--
-- That is a sound design. What is missing is the guard that makes it
-- safe: nothing prevents the OPEN producer from emitting a MUST_DO atom
-- the CLOSED consumer cannot retire. When it does, the hold doctrine
-- converts a vocabulary mismatch into an indefinitely parked fleet, in
-- silence -- no error, no warning, no failed assertion.
--
-- SECOND-ORDER FINDING. The atom list is stored TWICE:
-- ottoq.ottoq_bay_purpose_atoms holds it as a function, and
-- twin.ottoq_sim_advance_service_flow holds the same array INLINE.
-- Verified: the twin function does not call the shared function
-- (calls_shared_fn = false, has_inline_copy = true). The shared
-- function's own header says "MUST MIRROR
-- twin.ottoq_sim_advance_service_flow STEP 1" -- a hand-maintained
-- mirror with nothing enforcing it. Same defect class as 0094's copied
-- KPI denominator: one truth, two copies, no check.
--
-- =====================================================================
-- WHAT THIS EXPLAINS
-- =====================================================================
-- Every load-shaped observation in 0104 and 0105 is downstream of this:
--   - "busy_day is a burst then 20 hours of silence" -- nothing goes
--     out, so nothing comes back;
--   - "utilisation 0.7-23.7% even within the active window" -- the
--     depot serves one intake and then holds a car park;
--   - "2.4 turns per charge point per day" -- one turn per vehicle,
--     because no vehicle gets a second one;
--   - "only 7 dispatches in 24 hours" -- the 7 are the vehicles whose
--     manifest happened not to include a walkaround.
--
-- It also means no OTTO-Q-vs-anything comparison run to date has
-- measured a working depot. The engine was never given a second cycle.
--
-- =====================================================================
-- WHAT IT DOES NOT IMPUGN
-- =====================================================================
-- Determinism. Both arms of the pair reproduce this identically, which
-- is exactly what a deterministic engine should do with a defective
-- input. Round 13's 24-of-24 stands. The KPI corrections (0182-0190)
-- stand -- they were definitional. D001 stands -- it rests on cuOpt's
-- solver shape and latency, not on load.
--
-- =====================================================================
-- THE FIX, AND WHY IT IS NOT APPLIED IN THIS CHECK
-- =====================================================================
-- The invariant to establish: AN ATOM THAT CAN BE REQUIRED MUST BE
-- RETIRABLE. Concretely, three parts, smallest first:
--
--   1. GUARD (the real fix). Manifest generation must not emit a must_do
--      atom whose svc lies outside the retirable vocabulary. Outside it,
--      emit advisory (must_do=false) and record the violation loudly.
--      This makes the failure visible instead of silent, and no future
--      twin-side vocabulary addition can park the fleet again.
--   2. MAKE THE MIRROR ONE OBJECT. twin.ottoq_sim_advance_service_flow
--      should credit atoms via ottoq.ottoq_bay_purpose_atoms rather than
--      an inline copy, so the two cannot drift.
--   3. GIVE perimeter_walkaround A HOME. It is a legitimate operation --
--      a human walks the vehicle -- so it should be retirable work under
--      the 'inspect' purpose, not demoted. That also gives KPI 4
--      (touch_events_per_turn) a real touch event to count.
--
-- Not applied here because all three change engine behaviour and
-- therefore move every one of the six certification columns. That is a
-- forces_recert = true migration and it is done deliberately, on its
-- own, with a published prediction -- not appended to a findings check.
--
-- =====================================================================
-- QUERIES — every figure above regenerates from these
-- =====================================================================

-- Q1 — the duty curve against reality.
WITH run AS (SELECT 'cd8e0796-8f5e-47e1-846a-c24ed72a4c42'::uuid AS id,
                    '2026-09-01 02:00:00+00'::timestamptz AS t0),
t AS (SELECT g AS tick, run.t0 + (g*30 || ' minutes')::interval AS ts
        FROM generate_series(0,47) g, run),
fleet AS (SELECT count(*) AS n FROM vehicles v, run
           WHERE v.home_depot_id = (SELECT depot_id FROM ottoq_sim_runs, run WHERE sim_run_id=run.id)
             AND v.category='autonomous')
SELECT t.tick, to_char(t.ts,'HH24:MI') AS sim_time,
       round(ottoq_deploy_target_fraction(EXTRACT(hour FROM t.ts)::int, 0.75)::numeric,3) AS target_frac,
       FLOOR((SELECT n FROM fleet) * ottoq_deploy_target_fraction(EXTRACT(hour FROM t.ts)::int,0.75))::int AS should_be_out,
       (SELECT count(*) FROM ottoq_vehicle_dispatches d, run
         WHERE d.sim_run_id = run.id AND d.dispatched_at <= t.ts
           AND (d.actual_return_at IS NULL OR d.actual_return_at > t.ts)) AS actually_out
  FROM t WHERE t.tick % 4 = 0 ORDER BY t.tick;

-- Q2 — dispatch records: boot-primed vs actually dispatched in-window.
WITH run AS (SELECT 'cd8e0796-8f5e-47e1-846a-c24ed72a4c42'::uuid AS id,
                    '2026-09-01 02:00:00+00'::timestamptz AS t0,
                    '2026-09-02 02:00:00+00'::timestamptz AS t1)
SELECT count(*) AS dispatch_rows,
       count(*) FILTER (WHERE dispatched_at < run.t0) AS boot_primed,
       count(*) FILTER (WHERE dispatched_at >= run.t0 AND dispatched_at < run.t1) AS dispatched_in_window,
       count(DISTINCT vehicle_id) AS distinct_vehicles
  FROM ottoq_vehicle_dispatches, run WHERE sim_run_id = run.id GROUP BY run.t0, run.t1;

-- Q3 — the brain did ask. 38 redeployment decisions.
WITH run AS (SELECT 'cd8e0796-8f5e-47e1-846a-c24ed72a4c42'::uuid AS id)
SELECT action_context, outcome_status, count(*) AS n
  FROM ottoq_decisions, run
 WHERE sim_run_id = run.id AND action_context = 'redeployment'
 GROUP BY 1,2 ORDER BY n DESC;

-- Q4 — vehicles did reach a dispatchable state 142 times.
WITH r AS (SELECT started_at, COALESCE(ended_at,last_tick_at) AS endt, depot_id
             FROM ottoq_sim_runs WHERE sim_run_id='cd8e0796-8f5e-47e1-846a-c24ed72a4c42')
SELECT l.previous_state::text AS from_state, l.new_state::text AS to_state, count(*) AS n
  FROM vehicle_state_log l, r
 WHERE l.created_at BETWEEN r.started_at AND r.endt + interval '2 min'
   AND l.depot_id = r.depot_id
   AND (l.previous_state::text = 'charge_complete_holding' OR l.new_state::text = 'charge_complete_holding')
 GROUP BY 1,2 ORDER BY n DESC;

-- Q5 — THE FINDING: must_do completion by service code.
WITH run AS (SELECT 'cd8e0796-8f5e-47e1-846a-c24ed72a4c42'::uuid AS id),
atoms AS (SELECT a->>'svc' AS svc, COALESCE(a->>'status','pending') AS st
            FROM ottoq_visit_needs vn, run, jsonb_array_elements(vn.atoms) a
           WHERE vn.sim_run_id = run.id AND COALESCE((a->>'must_do')::boolean,false))
SELECT svc, count(*) AS required,
       count(*) FILTER (WHERE st='done') AS done,
       count(*) FILTER (WHERE st='pending') AS pending,
       round(100.0*count(*) FILTER (WHERE st='pending')/count(*),1) AS pct_pending
  FROM atoms GROUP BY 1 ORDER BY pct_pending DESC, pending DESC;

-- Q6 — perimeter_walkaround is written by one function and read by none.
SELECT n.nspname||'.'||p.proname AS function_mentioning_it
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('twin','ottoq','public') AND p.prokind='f'
   AND pg_get_functiondef(p.oid) ILIKE '%perimeter_walkaround%'
 ORDER BY 1;

-- Q7 — the retirable vocabulary, and the mirror that is a second copy.
SELECT purpose, ottoq.ottoq_bay_purpose_atoms(purpose) AS retirable_atoms
  FROM unnest(ARRAY['wash','detail','service','inspect']) purpose;

SELECT (pg_get_functiondef(p.oid) ILIKE '%ottoq_bay_purpose_atoms%') AS calls_shared_fn,
       (pg_get_functiondef(p.oid) ILIKE '%mechanical_pm%')           AS has_inline_copy
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_service_flow';
