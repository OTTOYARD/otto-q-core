-- 0457  **A fault repair's technician green-light is required by one dispatch door, asked for by nothing, and skipped
--        by the other doors, so a repaired car leaves without one.** -> G467, fixed under a dial by db/migrations/0753.
--        Found while reading who answers a green-light in production (G465). §1-§4 read-only, against
--        gxdrcyphqjzjsuhxuqtg, 2026-10-18 between 1:03 and 1:30 AM CT (06:03 and 06:30 UTC), bounded by clock reads,
--        inside the sweep window (catalog reads and one small table read). §5 counts the cars on the twin depot's runs
--        and waits for the window to close (11:00 UTC). Every claim names its query.
--
-- ══ §1 THE REQUIREMENT (reproduce: (1)) ═══════════════════════════════════════════════════════════════════════════════
--
--   Two functions write requires_tech_greenlight true on an atom, (1): ottoq.ottoq_derive_visit_needs, on every
--   fault_repair it derives ('must_do' true, 'deferrable' false, a service-bay atom), and
--   twin.ottoq_sim_advance_visit_atoms, on the cosmetic_repair a triaged cosmetic flag escalates to. Both are bay work,
--   done in the service bay and credited at its exit by STEP 1 of the service flow.
--
-- ══ §2 WHO WAITS FOR IT (reproduce: (2), (4)) ═════════════════════════════════════════════════════════════════════════
--
--   Three functions read the flag, (2). ottoq.ottoq_arrival_disposition stages a flagged arrival on a technician hold; it
--   is not a departure door. public.ottoq_decide_tick's redeployment cursor holds a car in staged_for_departure whose
--   open visit carries such an atom until a tech_greenlight approval, approved and created since the visit opened,
--   exists. twin.ottoq_sim_advance_visit_atoms raises a green-light after a timed completion of work done in place, in
--   its sim-only branch; no green-light atom is work done in place, so it never raises one for a repair.
--   Every other door tests public.ottoq_departure_clear (md5 ac79f1b4), the one departure test 0543 made rule 9's, and
--   none of it, nor any of them, names a green-light, (4): ottoq.ottoq_plan_dispatch_tick (the deploy planner, whose
--   release list twin.ottoq_sim_auto_dispatch_tick departs), twin.ottoq_sim_dispatch_vehicle (the twin's dispatcher),
--   public.ottoq_refuse_unfinished_departure (0544, the trigger that refuses a dispatch row), the departure recheck and
--   the v2 operator door's departure report.
--
-- ══ §3 WHO ASKS FOR IT (reproduce: (3)) ═══════════════════════════════════════════════════════════════════════════════
--
--   Nothing, after a bay repair. ottoq.ottoq_stage_advance_approval inserts a tech_greenlight and has no caller in the
--   database, (3). The ops approvals table held 25,564 indepot_reassign questions, 1 opportunistic_charge and no
--   tech_greenlight at all when read at 1:30 AM CT.
--
-- ══ §4 WHAT FOLLOWS ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The decide's door can never let a repaired car go, since nothing it waits for is ever written; the planner's door,
--   which does not wait, always does. So the requirement the derive writes on every repair is not enforced anywhere: a
--   car leaves its repair with no technician having signed it off. In production that is a car back on the road after
--   a fault repair nobody green-lit; in the twin, every fault-repaired car has left this way. Rule 9 is about work open
--   on the car; the repair is done, so the departure test is right by its own terms. What is missing is the sign-off the
--   plan itself asks for.
--
-- ══ §5 THE CARS (after the window; reproduce: (5)) ══════════════════════════════════════════════════════════════════
--
--   Not yet measured: the departures of fault-repaired cars on the twin depot's runs since 2026-10-16, by door, and how
--   many of them had a green-light, are counted after the sweep window closes at 6:00 AM CT, when heavy reads are
--   allowed again. The expected count with a green-light is none, by §3.
--
-- ══ §6 THE FIX (0753) ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   Dial repair_needs_its_green_light (default 0). A repair that needs a green-light asks for one when it is done (a
--   trigger on the visit's atoms, so every door that marks it done asks: the bay exit and the production seam alike);
--   the one departure test holds the car until one approved since its visit opened exists, so every door holds it
--   alike; a declined green-light re-opens the repair. At a twin-fed depot the twin's technician answers on its own
--   delay and draw; at a real one a person does (0751). Executed on the scratch PostgreSQL against the live departure
--   test, atom marker and scan (tests/test_repair_green_light_sql.py, 8 tests).

-- (1) who writes the requirement
SELECT n.nspname || '.' || p.proname AS fn
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~ $$'requires_tech_greenlight',\s*true$$
 ORDER BY 1;

-- (2) who reads it, and whether each also tests the one departure test
SELECT n.nspname || '.' || p.proname AS fn, p.prosrc ~ 'ottoq_departure_clear' AS tests_departure_clear
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~ $$requires_tech_greenlight'\)::boolean$$
 ORDER BY 1;

-- (3) who asks, and what the table holds
SELECT 'callers of ottoq_stage_advance_approval' AS k, count(*)::text AS v
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~ 'ottoq_stage_advance_approval'
   AND p.proname <> 'ottoq_stage_advance_approval'
UNION ALL
SELECT 'approvals: ' || approval_type, count(*)::text FROM public.ottoq_ops_approvals GROUP BY approval_type;

-- (4) the departure test's callers, and whether any names a green-light
SELECT n.nspname || '.' || p.proname AS fn, p.prosrc ~ 'tech_greenlight' AS names_a_green_light
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public', 'twin', 'ottoq') AND p.prosrc ~ 'ottoq_departure_clear\('
   AND p.proname <> 'ottoq_departure_clear'
 ORDER BY 1;
