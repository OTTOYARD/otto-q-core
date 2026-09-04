-- =====================================================================
-- 0192  An atom that can be required must be retirable
-- =====================================================================
-- forces_recert = TRUE. This changes what the engine is allowed to
-- demand, and therefore what every seeded run does. All six
-- certification columns move. See THE PREDICTION at the foot.
--
-- THE DEFECT (db/checks/0106, evidence below)
-- ---------------------------------------------------------------------
-- Across every visit ever recorded in this database:
--
--   svc                    required   ever done
--   perimeter_walkaround     63,433           0
--   readiness_check          67,619      21,492
--   interior_inspection      62,584      37,962
--   charge                   42,752      19,481
--   ...all 14 others              -    at least 1
--
-- perimeter_walkaround has been demanded 63,433 times and completed
-- never, not once, in the history of the system. It is always must_do.
--
-- It cannot be completed. It appears in exactly one function in the
-- database -- twin.ottoq_sim_generate_service_manifest, which WRITES it.
-- Routing is total (ottoq_svc_to_leg_type sends it to the generic
-- 'service' leg via its ELSE) but RETIREMENT is not: atoms are marked
-- done only for codes a retirement path names, and no path names this
-- one.
--
-- Downstream, ottoq.ottoq_plan_dispatch_tick refuses to redeploy any
-- vehicle owing a must_do atom -- "always hold, no vehicle leaves owing
-- known work". Correct doctrine. But applied to work that can never be
-- done, it is an indefinite hold. Measured on run cd8e0796: the twin's
-- duty curve asks for 76 of 116 vehicles deployed at 08:00; zero are;
-- 7 vehicles are dispatched in 24 sim-hours.
--
-- THE CLASS, NOT THE INSTANCE
-- ---------------------------------------------------------------------
-- ottoq.ottoq_bay_purpose_atoms states the architecture in its own
-- header: "(Twin vocabulary is OPEN; OTTO-Q's is CLOSED.)" That is a
-- sound design -- the twin must be free to invent service codes. What is
-- missing is the guard that makes it safe. Nothing prevents the OPEN
-- producer from marking an atom MUST_DO that the CLOSED consumer cannot
-- retire, and when it happens the failure is silent: no error, no
-- warning, no failed assertion, just a fleet that stops working.
--
-- So this migration does not special-case perimeter_walkaround. It
-- establishes the invariant:
--
--     AN ATOM THAT CAN BE REQUIRED MUST BE RETIRABLE.
--
-- An atom outside the retirable vocabulary may still be REQUESTED -- it
-- is emitted advisory (must_do=false) and stamped so the demotion is
-- visible in the ledger forever -- but it may never BLOCK. Any future
-- twin-side vocabulary addition is caught the same way, on its first
-- appearance, instead of parking the fleet in silence.
--
-- WHAT IS DELIBERATELY NOT DONE HERE
-- ---------------------------------------------------------------------
-- perimeter_walkaround is a legitimate operation -- a human walks the
-- vehicle -- and it should eventually be REAL retirable work, not a
-- demoted request. But where it belongs is a modelling decision with
-- real consequences: routed to a service bay it would put 113 vehicles
-- through 2 bays, and a walkaround does not actually need a bay. That
-- decision gets its own change. This one only ensures the engine can
-- never again be blocked by work it cannot perform.
--
-- THE OTHER TWO DOORS
-- ---------------------------------------------------------------------
-- Guarding only the generator would be a guard that can be walked
-- around. Three paths can set must_do = true; each was checked:
--
--   twin.ottoq_sim_generate_service_manifest  -- guarded below (edit 1)
--   public.ottoq_apply_need_escalation        -- guarded below (edit 2)
--   ottoq.ottoq_rider_flag_indepot_sweep      -- cannot reach an
--       unretirable code: it assigns v_svc from a closed set of two
--       literals, 'exterior_wash' and 'interior_deep_clean', both
--       retirable. Left alone; narrowing it would be scope creep.
--
-- Escalation is safe TODAY by accident rather than by construction: it
-- promotes only atoms governed by public.service_cadence_policy, and
-- perimeter_walkaround is absent from that table (15 rows, checked), so
-- ottoq_service_must_do returns false for it via its 'never' default.
-- That is a coincidence of data, not a property of the code -- adding a
-- cadence row for an unretirable svc would re-open the whole defect. So
-- edit 2 makes it structural.
--
-- Collapsing the duplicated atom vocabulary (0106's second-order
-- finding: twin.ottoq_sim_advance_service_flow holds the bay atom lists
-- INLINE and does not call ottoq_bay_purpose_atoms, whose own header
-- says "MUST MIRROR") is also left alone. The retirable set below is
-- DERIVED from ottoq_bay_purpose_atoms rather than copied, so this
-- migration adds no third copy -- but it does not fix the second.
-- =====================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────
-- 1. THE RETIRABLE VOCABULARY, DECLARED ONCE
-- ─────────────────────────────────────────────────────────────────────
-- DERIVED from ottoq_bay_purpose_atoms for everything a bay exit
-- credits, so the bay half can never drift from this. The five codes
-- added by hand are the ones retired OUTSIDE a bay exit, each named
-- with the path that retires it:
--
--   charge              twin.ottoq_sim_advance_flow_contract
--                       (PERFORM ottoq_mark_visit_atoms_done(.., ARRAY['charge'], ..))
--   readiness_check     twin.ottoq_sim_advance_visit_atoms
--   triage_check        twin.ottoq_sim_advance_visit_atoms
--   interior_inspection retired 37,962 times; not in the inline bay CASE
--                       (which has no 'inspect' branch), so it is retired
--                       off the bay path
--   item_retrieval      retired 3,011 times off the bay path
--   remote_diagnostics  retired 2,480 times off the bay path
--
-- The assertion at the end of this migration proves this set equals the
-- set of codes the ledger has ever actually retired. If a future edit
-- makes the declaration and the ledger disagree, the migration fails
-- rather than shipping a guard that demotes real work.
CREATE OR REPLACE FUNCTION ottoq.ottoq_atom_retirable_set()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'ottoq','public','extensions'
AS $fn$
  SELECT ARRAY(
    SELECT DISTINCT s FROM (
      SELECT unnest(ottoq.ottoq_bay_purpose_atoms(p)) AS s
        FROM unnest(ARRAY['wash','detail','service','inspect']) p
      UNION ALL
      SELECT unnest(ARRAY['charge','readiness_check','triage_check',
                          'interior_inspection','item_retrieval',
                          'remote_diagnostics'])
    ) u ORDER BY s);
$fn$;

COMMENT ON FUNCTION ottoq.ottoq_atom_retirable_set() IS
  '0192: the codes a must_do atom may name. Bay-retired codes are derived '
  'from ottoq_bay_purpose_atoms so the two cannot drift; the rest are '
  'retired off the bay path and are listed with their path in 0192.';

-- Total, NULL-safe, never raises: it can only ever demote, never block.
CREATE OR REPLACE FUNCTION ottoq.ottoq_atom_retirable(p_svc text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'ottoq','public','extensions'
AS $fn$
  SELECT COALESCE(p_svc, '') = ANY (ottoq.ottoq_atom_retirable_set());
$fn$;

-- ─────────────────────────────────────────────────────────────────────
-- 2. THE GUARD
-- ─────────────────────────────────────────────────────────────────────
-- TOTAL by construction: a NULL or non-array input returns unchanged, an
-- atom without an svc is left alone, and an atom already advisory is
-- untouched. It only ever clears must_do -- it never sets it, never
-- drops an atom, and never reorders them, so the manifest a vehicle
-- receives is the same manifest minus the power to block on work the
-- depot cannot do.
--
-- The demotion is stamped INTO the atom (guard_demoted / guard_reason)
-- rather than only logged, so the ledger carries its own evidence: any
-- future reader can count demotions per run without a join, and 0106's
-- finding stays visible in the data after this migration hides its
-- symptom.
CREATE OR REPLACE FUNCTION ottoq.ottoq_atoms_guard(p_atoms jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'ottoq','public','extensions'
AS $fn$
  SELECT CASE
    WHEN p_atoms IS NULL OR jsonb_typeof(p_atoms) <> 'array' THEN p_atoms
    ELSE COALESCE((
      SELECT jsonb_agg(
               CASE
                 WHEN COALESCE((a.value->>'must_do')::boolean, false)
                  AND NOT ottoq.ottoq_atom_retirable(a.value->>'svc')
                 THEN a.value
                      || jsonb_build_object('must_do', false,
                                            'guard_demoted', true,
                                            'guard_reason', 'svc_not_retirable')
                 ELSE a.value
               END
               ORDER BY a.ord)
        FROM jsonb_array_elements(p_atoms) WITH ORDINALITY AS a(value, ord)
    ), p_atoms)
  END;
$fn$;

COMMENT ON FUNCTION ottoq.ottoq_atoms_guard(jsonb) IS
  '0192: an atom that can be required must be retirable. Clears must_do on '
  'any atom whose svc no retirement path can mark done, and stamps the '
  'demotion into the atom. Total: never drops, reorders or promotes.';

-- ─────────────────────────────────────────────────────────────────────
-- 3. APPLY IT WHERE THE MANIFEST IS WRITTEN — ANCHORED EDIT
-- ─────────────────────────────────────────────────────────────────────
-- The anchor is asserted by COUNT, not presence: if the generator has
-- drifted since this was written, the edit refuses rather than silently
-- patching the wrong call site or patching one of two.
DO $mig$
DECLARE
  v_src text;
  v_anchor text := 'v_archetype, v_urgency, v_due, v_visit_target, v_m,';
  v_repl  text := 'v_archetype, v_urgency, v_due, v_visit_target, ottoq.ottoq_atoms_guard(v_m),';
  v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_generate_service_manifest';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0192: twin.ottoq_sim_generate_service_manifest not found';
  END IF;

  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0192: anchor occurs % times, expected exactly 1 - refusing to edit', v_n;
  END IF;

  -- guard against re-application on an already-patched body
  IF position('ottoq_atoms_guard' in v_src) > 0 THEN
    RAISE EXCEPTION '0192: generator already calls ottoq_atoms_guard - refusing to double-apply';
  END IF;

  EXECUTE replace(v_src, v_anchor, v_repl);
END
$mig$;

-- The ON CONFLICT DO UPDATE branch sets atoms = EXCLUDED.atoms, so the
-- upsert path is guarded by the same call. Verified by the assertion
-- below, which requires the guard to appear exactly once in the body.
DO $chk$
DECLARE v_src text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_sim_generate_service_manifest';
  v_n := (length(v_src) - length(replace(v_src, 'ottoq_atoms_guard', ''))) / length('ottoq_atoms_guard');
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0192: post-edit guard count is %, expected 1', v_n;
  END IF;
END
$chk$;

-- ─────────────────────────────────────────────────────────────────────
-- 3b. THE SECOND DOOR — ESCALATION MAY NOT PROMOTE UNRETIRABLE WORK
-- ─────────────────────────────────────────────────────────────────────
-- public.ottoq_apply_need_escalation rebuilds atoms with
--     (s.cur_must OR (s.governed AND ... AND ottoq_service_must_do(...)))
-- and its own comment reads "MONOTONE: only ever promotes." Monotone
-- promotion is right for real work and wrong for work that cannot be
-- done, so the promotion branch gains the same retirability test. The
-- cur_must arm is deliberately NOT touched: an atom that is already
-- must_do reached that state through a guarded door, and clearing it
-- here would be a second, hidden demotion.
DO $mig2$
DECLARE
  v_src text;
  v_anchor text := 'ottoq_service_must_do(s.svc, s.urg)';
  v_repl  text := 'ottoq_service_must_do(s.svc, s.urg) AND ottoq.ottoq_atom_retirable(s.svc)';
  v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_apply_need_escalation';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0192: public.ottoq_apply_need_escalation not found';
  END IF;

  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0192: escalation anchor occurs % times, expected exactly 1 - refusing to edit', v_n;
  END IF;

  IF position('ottoq_atom_retirable' in v_src) > 0 THEN
    RAISE EXCEPTION '0192: escalation already calls ottoq_atom_retirable - refusing to double-apply';
  END IF;

  EXECUTE replace(v_src, v_anchor, v_repl);
END
$mig2$;

DO $chk2$
DECLARE v_src text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_apply_need_escalation';
  v_n := (length(v_src) - length(replace(v_src, 'ottoq_atom_retirable', ''))) / length('ottoq_atom_retirable');
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0192: post-edit escalation retirability count is %, expected 1', v_n;
  END IF;
END
$chk2$;

-- ─────────────────────────────────────────────────────────────────────
-- 4. THE ASSERTIONS — A CHECK THAT CANNOT FAIL IS NOT A CHECK
-- ─────────────────────────────────────────────────────────────────────
DO $assert$
DECLARE
  v_declared text[];
  v_ledger   text[];
  v_missing  text[];
  v_extra    text[];
  v_demoted  jsonb;
BEGIN
  v_declared := ottoq.ottoq_atom_retirable_set();

  -- every code the ledger has EVER retired, across every visit ever
  SELECT COALESCE(array_agg(DISTINCT svc ORDER BY svc), ARRAY[]::text[])
    INTO v_ledger
    FROM (SELECT x->>'svc' AS svc
            FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) x
           WHERE COALESCE(x->>'status','pending') = 'done') d;

  -- A1. The declaration must not omit anything the system demonstrably
  -- retires. An omission here would demote REAL work -- the one way this
  -- migration could do harm.
  SELECT COALESCE(array_agg(s ORDER BY s), ARRAY[]::text[]) INTO v_missing
    FROM unnest(v_ledger) s WHERE NOT (s = ANY (v_declared));
  IF array_length(v_missing, 1) > 0 THEN
    RAISE EXCEPTION '0192 A1 FAILED: ledger retires % which the declaration omits. '
                    'Guard would demote real work. Refusing.', v_missing;
  END IF;

  -- A2. Report (do not fail on) declared codes the ledger has never
  -- retired. Not an error: a path can be correct and simply never have
  -- fired. It is recorded so the gap is visible.
  SELECT COALESCE(array_agg(s ORDER BY s), ARRAY[]::text[]) INTO v_extra
    FROM unnest(v_declared) s WHERE NOT (s = ANY (v_ledger));
  RAISE NOTICE '0192 A2: declared but never retired in the ledger: %',
    CASE WHEN array_length(v_extra,1) > 0 THEN v_extra::text ELSE '(none)' END;

  -- A3. The guard must actually bite on the known offender, and must
  -- leave a known-good atom completely untouched. If either half of this
  -- is wrong the guard is either useless or destructive.
  v_demoted := ottoq.ottoq_atoms_guard(jsonb_build_array(
      jsonb_build_object('svc','perimeter_walkaround','must_do',true,'status','pending'),
      jsonb_build_object('svc','charge','must_do',true,'status','pending')));

  IF COALESCE((v_demoted->0->>'must_do')::boolean, true) <> false
     OR COALESCE((v_demoted->0->>'guard_demoted')::boolean, false) <> true THEN
    RAISE EXCEPTION '0192 A3 FAILED: guard did not demote perimeter_walkaround: %', v_demoted;
  END IF;
  IF COALESCE((v_demoted->1->>'must_do')::boolean, false) <> true
     OR (v_demoted->1 ? 'guard_demoted') THEN
    RAISE EXCEPTION '0192 A3 FAILED: guard touched a retirable atom (charge): %', v_demoted;
  END IF;

  -- A4. Totality. None of these may raise, and none may lose an atom.
  IF ottoq.ottoq_atoms_guard(NULL) IS NOT NULL THEN
    RAISE EXCEPTION '0192 A4 FAILED: NULL input did not pass through';
  END IF;
  IF ottoq.ottoq_atoms_guard('{"not":"an array"}'::jsonb) <> '{"not":"an array"}'::jsonb THEN
    RAISE EXCEPTION '0192 A4 FAILED: non-array input was altered';
  END IF;
  IF jsonb_array_length(ottoq.ottoq_atoms_guard(
       jsonb_build_array(jsonb_build_object('no_svc_key', 1)))) <> 1 THEN
    RAISE EXCEPTION '0192 A4 FAILED: an atom without an svc key was dropped';
  END IF;

  -- A5. The escalation door, proved shut two ways: the cadence table has
  -- no row for the offender (so ottoq_service_must_do defaults to never),
  -- AND the retirability test is now in the promotion branch regardless.
  IF public.ottoq_service_must_do('perimeter_walkaround','critical') THEN
    RAISE EXCEPTION '0192 A5 FAILED: cadence policy would promote perimeter_walkaround at critical urgency';
  END IF;
  IF ottoq.ottoq_atom_retirable('perimeter_walkaround') THEN
    RAISE EXCEPTION '0192 A5 FAILED: perimeter_walkaround is declared retirable, but nothing retires it';
  END IF;

  RAISE NOTICE '0192: all assertions passed. Retirable vocabulary: %', v_declared;
END
$assert$;

-- ─────────────────────────────────────────────────────────────────────
-- 5. LINEAGE
-- ─────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0192_an_atom_that_can_be_required_must_be_retirable', TRUE,
  'Establishes the invariant that a must_do atom must name a service some retirement path can mark done. '
  'Root cause in db/checks/0106: perimeter_walkaround was demanded 63,433 times across the ledger and marked done zero times, '
  'because it appears in exactly one function - the one that writes it. ottoq_plan_dispatch_tick then held every vehicle owing it '
  'under the correct doctrine "no vehicle leaves owing known work", which applied to unperformable work is an indefinite hold: '
  'on run cd8e0796 the duty curve asked for 76 of 116 vehicles deployed at 08:00, zero were, and 7 vehicles were dispatched in 24 sim-hours. '
  'The fix is a guard at manifest generation, not a special case: an atom outside the retirable vocabulary is emitted advisory and stamped '
  'guard_demoted, so it can be requested but never block, and any future twin-side vocabulary addition is caught on first appearance '
  'instead of silently parking the fleet. A second anchored edit closes the escalation door: ottoq_apply_need_escalation may no longer '
  'promote an unretirable svc, which today is safe only because perimeter_walkaround happens to be absent from service_cadence_policy. '
  'The retirable set is DERIVED from ottoq_bay_purpose_atoms for bay-retired codes so no third copy is created; six off-bay codes are '
  'declared explicitly with their retiring path. Assertion A1 fails the migration if the declaration omits any code the ledger has ever '
  'actually retired, which is the only way this guard could demote real work. Both edits are anchored, assert their anchor occurs exactly '
  'once, and refuse on drift or double-application. '
  'forces_recert=TRUE: this changes what the engine may demand and therefore every seeded run - all six certification columns move by design.',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

COMMIT;

-- =====================================================================
-- APPLIED 2026-09-04. All assertions passed. Verified after commit:
--   ottoq_atom_retirable_set() = charge, cosmetic_repair, exterior_wash,
--     fault_repair, interior_deep_clean, interior_inspection,
--     interior_tidy, item_retrieval, mechanical_pm, readiness_check,
--     remote_diagnostics, sensor_calibration, sensor_clean, triage_check
--     -- 14 codes, exactly the set the ledger has ever retired (A1/A2).
--   twin.ottoq_sim_generate_service_manifest: 1 guard call
--   public.ottoq_apply_need_escalation:        1 retirability call
--   ottoq_cert_lineage.forces_recert:          true
--   guard on a live pair -> perimeter_walkaround demoted and stamped,
--     interior_inspection returned byte-identical.
--
-- =====================================================================
-- THE PREDICTION (published before the round, per the 0181 pattern)
-- =====================================================================
-- Stated now so the next certification round can falsify it.
--
-- 1. ALL SIX certification columns change. Every canon (h_cmd, h_dec,
--    h_bkg, h_nrg, endst) moves in every column. A column that does NOT
--    move would mean the guard never fired in that scenario, which for
--    busy_day and normal_day on the flagship depot would itself be a
--    finding.
--
-- 2. Both arms of every pair still agree. The guard is IMMUTABLE and
--    seed-independent; it reads no clock, no random source and no row
--    outside its argument. If any pair DISAGREES after this, the guard
--    introduced nondeterminism and must be reverted, not tuned.
--
-- 3. On busy_day/171717, redeployment starts working: dispatches in
--    window rise from 7 toward the duty curve, and deployed-at-08:00
--    rises from 0 toward its target of 76. It will NOT hit 76 exactly --
--    deploy_release_per_tick_cap is 6, so the depot can release at most
--    6 per tick and needs ~13 ticks to reach the morning target from
--    zero. Reaching it exactly would mean the cap is not being honoured.
--
-- 4. Utilisation rises and time-to-service gets WORSE. This is the point.
--    A depot that cycles its fleet has contention; a depot that parks it
--    does not. If p95 time-to-service does not degrade, the fleet is
--    still not cycling.
--
-- 5. 0104's +7% turns result does not survive unchanged and should not
--    be quoted after this lands. It was measured on a parked fleet.
-- =====================================================================
