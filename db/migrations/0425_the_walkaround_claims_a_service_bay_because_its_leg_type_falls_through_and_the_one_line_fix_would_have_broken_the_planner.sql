-- migration-version: 20260922155332
-- migration-name:    the_walkaround_claims_a_service_bay_because_its_leg_type_falls_through_and_the_one_line_fix_would_have_broken_the_planner
--
-- 0425  **`perimeter_walkaround` is performed AT THE VEHICLE and holds 3,257 bookings on the twin depot's
--       TWO service bays. Cause: `public.ottoq_svc_to_leg_type('perimeter_walkaround')` returns the
--       fall-through `'service'`, which `ottoq.ottoq_book_workflow_legs` maps with a hardcoded
--       `CASE ... WHEN 'service' THEN 'service_bay'`. Diagnosed in `db/checks/0338` §8 (G152).**
--
--       Every one of its seven siblings returns its own name and books nothing — `sensor_clean`,
--       `interior_tidy`, `item_retrieval`, `remote_diagnostics`, `triage_check`, `software_update`, and
--       `interior_inspection` → `'inspect'`. Confirmed from the leg population: `sensor_clean` 398 legs
--       / **0** with a stall, against `service` 5,677 / **3,225**.
--
--       **This is `0383`'s residue, and `0383` is mine.** It re-derived the walkaround's *concurrency*
--       class onto `sensor_clean` — proving the atom starts and completes — and left its *leg type*
--       falling through. A service's identity is declared in two places and `0383` changed one.
--
--       `forces_recert` **TRUE**: this changes which stalls a run books, and `bookings` is one of the
--       fourteen atoms.
--
--       **And the count is live, not historical.** `0338` measured 3,257; the read-only pre-flight dry-run
--       forty minutes later returned **3,785**, still climbing as the `0424` resweep ran. Quote it with its
--       moment or not at all (Part 3's standing instruction: cite the run, never the table).
--
-- ══ §1 WHY THIS IS TWO PARTS AND NOT THE ONE-LINE FIX I SPECIFIED ═════════════
--
-- `0338` §8 and the check-in prompt I wrote both said the fix is *"one mapping: return
-- 'perimeter_walkaround' from that one bridge."* **Applying only that would have broken the planner.**
--
-- `ottoq_itinerary_legs` carries `ottoq_itinerary_legs_leg_type_check`, a CHECK constraint with a fixed
-- 22-value allowlist, and **`perimeter_walkaround` is not in it.** Measured over the fifteen values the
-- amended bridge would emit: **fourteen are permitted and `perimeter_walkaround` is the only one that is
-- not.** So the bridge is total-and-safe today precisely because its entire output range is a subset of
-- that allowlist — an invariant nothing asserts, and the one the one-line fix would have violated.
--
-- The blast radius is the planner: `public.ottoq_plan_visit_itinerary` performs **six** bare
-- `INSERT INTO ottoq_itinerary_legs` (its only `EXCEPTION WHEN` wraps the charge-minutes estimate, not the
-- inserts), so a CHECK violation would propagate out of the planner rather than degrade it — which is the
-- defect class APPLYING.md names: *"A failure must never abort `decide_tick`."*
--
-- **So: (A) extend the constraint, THEN (B) amend the bridge. Order is load-bearing** — reversed, every
-- walkaround itinerary insert fails between the two statements.
--
-- ══ §2 WHAT IS DELIBERATELY NOT CHANGED ══════════════════════════════════════
--
--   1. **The `ELSE 'service'` fall-through STAYS.** Its own comment is correct and is the reason this was
--      survivable: *"Anything the twin invents that OTTO-Q has no leg for lands on the generic service
--      leg. DO NOT remove this ELSE: totality is the whole point. The true code is preserved in
--      `ottoq_itinerary_legs.payload->>'atom'`, so the remap is lossless."* The defect was never the
--      fall-through; it was a declared, stall-free service never being added to the pass-through list.
--   2. **`ottoq_book_workflow_legs` is untouched.** Its `CASE` already ends `ELSE NULL`, so an
--      unrecognised leg type books no stall. That is why (B) needs no companion change there.
--   3. **No `lane_stalls` predicate.** `0338` §6 proposed one as the general guard; it is not required to
--      close this and would be a second mechanism for a problem the existing pattern already solves.
--      `lane_stalls` is also a *capacity*, not a boolean — `interior_deep_clean` carries `0` and
--      legitimately books wash stalls — so a naive `IS NULL` predicate would be wrong anyway.
--   4. **`readiness_check` is NOT folded in.** Same shape (`lane='gate'`, `lane_stalls=NULL`, **4,467**
--      bookings on `inspection` stalls, larger than the walkaround) but it has **no same-lane twin** to
--      compare against, and `ottoq_plan_visit_itinerary` excludes it from the non-bay loops by name
--      (`AND v_a->>'svc' NOT IN ('readiness_check')`) while emitting a dedicated `'inspect'` leg for it at
--      the end. That is a deliberate design, not a fall-through. It needs its own measurement.
--   5. **The 3,257 existing bookings are NOT deleted.** They are historical calendar rows on runs that are
--      `class='engine'` and will purge on their own. Deleting calendar rows to make a number look right is
--      the opposite of what the calendar is for.
--
-- ══ §3 WHAT THIS DOES AND DOES NOT CLAIM TO FIX ═══════════════════════════════
--
--   * **FIXES:** new runs stop booking a service bay for a service performed at the vehicle.
--   * **DOES NOT FIX, and must not be quoted as fixing:** `0337` §2's **234 of 808** false-critical
--      HW.006 failures. Those come from `0418`'s probe resolving a stall via
--      `ottoq_stall_bookings.need_atom = svc`; with no booking to resolve, HW.006 should ABSTAIN rather
--      than fail — but that is a prediction about the probe's behaviour on a population that does not
--      exist yet, and V4 below only records the baseline so it can be checked after a run.
--   * **DOES NOT establish displacement.** `0335`'s rule stands: a booking is not contention until
--      something is refused because of it. Freeing two bays may change nothing measurable, and this
--      migration does not assert that it will.
--
-- ══ §4 PRE-FLIGHT, CHANGE, VERIFICATION ═══════════════════════════════════════

\set ON_ERROR_STOP on
BEGIN;

-- ── P1: the defect is still live and still exactly one service ──
DO $$
DECLARE v_leg_type text; v_bookings int; v_sibling int;
BEGIN
  SELECT public.ottoq_svc_to_leg_type('perimeter_walkaround') INTO v_leg_type;
  IF v_leg_type <> 'service' THEN
    RAISE EXCEPTION '0425 P1: ottoq_svc_to_leg_type(''perimeter_walkaround'') already returns %, not '
                    '''service'' -- somebody fixed this. Re-derive db/checks/0338 before applying.',
                    v_leg_type;
  END IF;

  SELECT count(*) INTO v_bookings
    FROM public.ottoq_stall_bookings sb JOIN public.stalls st ON st.id = sb.stall_id
   WHERE st.depot_id='11111111-1111-1111-1111-111111111111'
     AND sb.need_atom='perimeter_walkaround';
  IF v_bookings < 100 THEN
    RAISE EXCEPTION '0425 P1: only % walkaround bookings on the twin depot -- the evidence was purged; '
                    're-derive db/checks/0338 section 6 before applying.', v_bookings;
  END IF;

  -- The sibling comparison is the whole argument: same lane, same lane_stalls, same concurrency.
  SELECT count(*) INTO v_sibling
    FROM public.ottoq_stall_bookings sb JOIN public.stalls st ON st.id = sb.stall_id
   WHERE st.depot_id='11111111-1111-1111-1111-111111111111' AND sb.need_atom='sensor_clean';
  IF v_sibling <> 0 THEN
    RAISE EXCEPTION '0425 P1: sensor_clean now holds % stall bookings. The argument for this fix is that '
                    'the walkaround''s own declared twin books NONE; if that is no longer true, STOP.',
                    v_sibling;
  END IF;
  RAISE NOTICE '0425 P1: walkaround % bookings vs sensor_clean 0 -- defect confirmed', v_bookings;
END $$;

-- ── P2: the CHECK constraint exists, and forbids the value we are about to emit ──
DO $$
DECLARE v_def text;
BEGIN
  SELECT pg_get_constraintdef(con.oid) INTO v_def
    FROM pg_constraint con JOIN pg_class rel ON rel.oid = con.conrelid
   WHERE rel.relname='ottoq_itinerary_legs' AND con.conname='ottoq_itinerary_legs_leg_type_check';
  IF v_def IS NULL THEN
    RAISE EXCEPTION '0425 P2: ottoq_itinerary_legs_leg_type_check not found -- (A) has nothing to extend '
                    'and (B) alone may be unsafe for a different reason. STOP and re-read the table.';
  END IF;
  IF position('perimeter_walkaround' in v_def) > 0 THEN
    RAISE NOTICE '0425 P2: constraint already permits perimeter_walkaround; (A) will be a no-op';
  ELSE
    RAISE NOTICE '0425 P2: constraint forbids perimeter_walkaround, as expected -- (A) is required BEFORE (B)';
  END IF;
END $$;

-- ── P3: no run in flight, and no determinism pair (G141) ──
DO $$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_n <> 0 THEN RAISE EXCEPTION '0425 P3: % run(s) running/paused -- apply between runs', v_n; END IF;
  SELECT count(*) INTO v_n FROM pg_stat_activity
   WHERE state='active' AND pid <> pg_backend_pid()
     AND query LIKE '%ottoq\_recert\_runner%';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0425 P3b: a determinism pair is in flight (invisible to ottoq_sim_runs -- G141). '
                    'Only pg_stat_activity is honest about this. Wait for the sweep.';
  END IF;
END $$;

-- ── SNAPSHOT BEFORE REPLACING (APPLYING.md step 2) ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0425_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_svc_to_leg_type';

-- ══ (A) EXTEND THE CONSTRAINT FIRST. Order is load-bearing (§1). ══════════════
-- Recreated from pg_get_constraintdef's own 22 values plus one, rather than retyped, so the existing
-- allowlist cannot be silently narrowed by a transcription slip. `interior_deep_clean` is in the
-- allowlist and is NOT emitted by the bridge (it maps to 'detail'); that asymmetry is pre-existing and
-- deliberately preserved.
ALTER TABLE public.ottoq_itinerary_legs
  DROP CONSTRAINT ottoq_itinerary_legs_leg_type_check;

ALTER TABLE public.ottoq_itinerary_legs
  ADD CONSTRAINT ottoq_itinerary_legs_leg_type_check CHECK (leg_type = ANY (ARRAY[
    'arrive','taxi','charge_dcfc','charge_l2','wash','detail','service','inspect','settle','stage',
    'depart','interior_tidy','sensor_clean','item_retrieval','interior_deep_clean','software_update',
    'remote_diagnostics','triage_check','sensor_calibration','mechanical_pm','fault_repair',
    'cosmetic_repair','perimeter_walkaround']));

-- ══ (B) THEN THE BRIDGE. One value added to the pass-through array. ═══════════
DO $$
DECLARE
  v_def text; v_new text; v_anchor text; v_insert text; v_hits int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_svc_to_leg_type';
  IF v_def IS NULL THEN RAISE EXCEPTION '0425 (B): ottoq_svc_to_leg_type not found'; END IF;

  v_anchor := '''remote_diagnostics'',''triage_check'',''sensor_calibration'',';
  v_hits := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0425 (B): anchor matched % times, expected exactly 1 -- the function was '
                    'reformatted; re-read pg_get_functiondef and re-derive the anchor', v_hits;
  END IF;

  -- perimeter_walkaround joins the pass-through list beside sensor_clean, which is the service 0383
  -- explicitly modelled it on: both concurrency='exterior', both lane_stalls=NULL, both performed at
  -- the vehicle, so neither should ever resolve to a lane stall. (A) above admits the value.
  v_insert := '''remote_diagnostics'',''triage_check'',''sensor_calibration'',''perimeter_walkaround'',';

  v_new := replace(v_def, v_anchor, v_insert);
  IF length(v_new) - length(v_def) <> length(v_insert) - length(v_anchor) THEN
    RAISE EXCEPTION '0425 (B): byte delta % <> expected % -- refusing a substitution that did more than '
                    'one replacement', length(v_new) - length(v_def), length(v_insert) - length(v_anchor);
  END IF;

  EXECUTE v_new;
  RAISE NOTICE '0425 (B): ottoq_svc_to_leg_type installed, +% bytes', length(v_new) - length(v_def);
END $$;

-- ── V1: the bridge now passes the walkaround through, and the siblings are unchanged ──
DO $$
DECLARE r record; v_bad int := 0;
BEGIN
  FOR r IN SELECT svc, expect FROM (VALUES
      ('perimeter_walkaround','perimeter_walkaround'), ('sensor_clean','sensor_clean'),
      ('interior_tidy','interior_tidy'), ('item_retrieval','item_retrieval'),
      ('remote_diagnostics','remote_diagnostics'), ('triage_check','triage_check'),
      ('software_update','software_update'), ('interior_inspection','inspect'),
      ('exterior_wash','wash'), ('interior_deep_clean','detail'),
      ('sensor_calibration','sensor_calibration'), ('mechanical_pm','mechanical_pm'),
      ('fault_repair','fault_repair'), ('cosmetic_repair','cosmetic_repair'),
      ('some_service_the_twin_invented','service')            -- totality: the ELSE still works
    ) AS t(svc, expect)
  LOOP
    IF public.ottoq_svc_to_leg_type(r.svc) IS DISTINCT FROM r.expect THEN
      v_bad := v_bad + 1;
      RAISE WARNING '0425 V1: % -> %, expected %', r.svc,
                    public.ottoq_svc_to_leg_type(r.svc), r.expect;
    END IF;
  END LOOP;
  IF v_bad <> 0 THEN RAISE EXCEPTION '0425 V1: % mapping(s) wrong', v_bad; END IF;
  RAISE NOTICE '0425 V1: 15 mappings correct, including the ELSE fall-through';
END $$;

-- ── V2: THE INVARIANT THAT WAS SILENTLY HOLDING AND THAT THE ONE-LINE FIX WOULD HAVE BROKEN.
-- Every value the bridge can emit must be permitted by the leg_type CHECK constraint. Nothing asserted
-- this before; it is the reason (A) is in this file at all, so it is asserted here permanently.
DO $$
DECLARE r record; v_bad int := 0; v_def text;
BEGIN
  SELECT pg_get_constraintdef(con.oid) INTO v_def
    FROM pg_constraint con JOIN pg_class rel ON rel.oid = con.conrelid
   WHERE rel.relname='ottoq_itinerary_legs' AND con.conname='ottoq_itinerary_legs_leg_type_check';

  FOR r IN
    SELECT DISTINCT public.ottoq_svc_to_leg_type(scp.svc) AS emitted
      FROM public.service_cadence_policy scp
     UNION SELECT public.ottoq_svc_to_leg_type('a_code_no_policy_declares')
  LOOP
    IF position('''' || r.emitted || '''' in v_def) = 0 THEN
      v_bad := v_bad + 1;
      RAISE WARNING '0425 V2: bridge emits % which the leg_type CHECK forbids', r.emitted;
    END IF;
  END LOOP;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '0425 V2: % emitted leg type(s) would violate ottoq_itinerary_legs_leg_type_check. '
                    'ottoq_plan_visit_itinerary performs six BARE inserts, so this aborts the planner '
                    'rather than degrading it.', v_bad;
  END IF;
  RAISE NOTICE '0425 V2: every leg type the bridge can emit is permitted by the CHECK constraint';
END $$;

-- ── V3: the constraint was EXTENDED, not replaced. No previously-legal value was dropped. ──
DO $$
DECLARE v_def text; r record; v_bad int := 0;
BEGIN
  SELECT pg_get_constraintdef(con.oid) INTO v_def
    FROM pg_constraint con JOIN pg_class rel ON rel.oid = con.conrelid
   WHERE rel.relname='ottoq_itinerary_legs' AND con.conname='ottoq_itinerary_legs_leg_type_check';

  FOR r IN SELECT unnest(ARRAY['arrive','taxi','charge_dcfc','charge_l2','wash','detail','service',
      'inspect','settle','stage','depart','interior_tidy','sensor_clean','item_retrieval',
      'interior_deep_clean','software_update','remote_diagnostics','triage_check','sensor_calibration',
      'mechanical_pm','fault_repair','cosmetic_repair']) AS v
  LOOP
    IF position('''' || r.v || '''' in v_def) = 0 THEN
      v_bad := v_bad + 1; RAISE WARNING '0425 V3: previously-legal leg type % was DROPPED', r.v;
    END IF;
  END LOOP;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '0425 V3: % of the original 22 leg types no longer permitted -- the constraint was '
                    'narrowed, not extended', v_bad;
  END IF;
  IF position('perimeter_walkaround' in v_def) = 0 THEN
    RAISE EXCEPTION '0425 V3: perimeter_walkaround not in the new constraint -- (A) did not take';
  END IF;
  RAISE NOTICE '0425 V3: all 22 original leg types retained, plus perimeter_walkaround';
END $$;

-- ── V4: record the pre-fix baseline so the effect is checkable after the next run. ──
-- Deliberately NOT an assertion. Existing bookings are historical and are not deleted (§2.5), so nothing
-- about them changes at apply time. What must fall is the count on runs started AFTER this migration.
DO $$
DECLARE v_wa int; v_sc int; v_legs int;
BEGIN
  SELECT count(*) INTO v_wa FROM public.ottoq_stall_bookings sb
    JOIN public.stalls st ON st.id=sb.stall_id
   WHERE st.depot_id='11111111-1111-1111-1111-111111111111' AND sb.need_atom='perimeter_walkaround';
  SELECT count(*) INTO v_sc FROM public.ottoq_stall_bookings sb
    JOIN public.stalls st ON st.id=sb.stall_id
   WHERE st.depot_id='11111111-1111-1111-1111-111111111111' AND sb.need_atom='sensor_clean';
  SELECT count(*) INTO v_legs FROM public.ottoq_itinerary_legs WHERE leg_type='perimeter_walkaround';
  RAISE NOTICE '0425 V4 BASELINE: walkaround bay bookings %, sensor_clean %, perimeter_walkaround legs % '
               '(expect legs > 0 and NEW-run bookings = 0 after the next run)', v_wa, v_sc, v_legs;
END $$;

-- ── LINEAGE. In the file and inside the transaction, deliberately.
-- `ottoq_cert_recert_floor()` reads `schema_migrations LEFT JOIN ottoq_cert_lineage` and takes
-- `COALESCE(forces_recert, TRUE)`, so a MISSING row is not "unknown", it is "forces recert". Writing it
-- here rather than by hand afterwards means the classification cannot be forgotten between applying and
-- remembering to record it — which is how `0267`/`0271` moved the floor by omission.
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0425_the_walkaround_claims_a_service_bay_because_its_leg_type_falls_through_and_the_one_line_fix_would_have_broken_the_planner',
  true,
  'Adds perimeter_walkaround to ottoq_svc_to_leg_type''s pass-through array so it stops falling through to '
  '''service'', which ottoq_book_workflow_legs maps to a service_bay -- a stall the service does not need, '
  'since 0383 derived it as concurrency=''exterior'' with lane_stalls=NULL, explicitly modelled on '
  'sensor_clean. Measured: sensor_clean books 0 stall bookings and the walkaround booked 3,785 (rising '
  'during the resweep) on the twin depot''s TWO service bays; all seven non-bay siblings already return '
  'their own leg type and book nothing. TRUE because `bookings` is one of the fourteen atoms and this '
  'changes which stalls a run books. TWO PARTS, order load-bearing: (A) extends '
  'ottoq_itinerary_legs_leg_type_check, whose 22-value allowlist did NOT contain perimeter_walkaround, '
  'BEFORE (B) amends the bridge -- the one-mapping fix specified in db/checks/0338 section 8 would have '
  'made six BARE inserts in ottoq_plan_visit_itinerary violate a CHECK constraint on the planner path. V2 '
  'now permanently asserts the invariant that was silently holding: every leg type the bridge can emit is '
  'permitted by the constraint. The ELSE ''service'' fall-through is KEPT (totality is deliberate; the true '
  'code survives in payload->>''atom''). Existing bookings are NOT deleted and readiness_check is NOT '
  'folded in (4,467 bookings but no same-lane twin, and it is excluded from the non-bay loops by name, so '
  'it is a design rather than a fall-through). Does NOT claim to fix 0337 section 2''s 234 false-critical '
  'HW.006 failures, and does NOT establish displacement -- 0335''s rule stands.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- ══ §5 AFTER APPLYING ═════════════════════════════════════════════════════════
--
-- `forces_recert` TRUE — resweep before quoting any determinism claim.
--
-- Then start a run and re-run `db/checks/0338` §6's isolation table. **The walkaround must join its
-- siblings at zero stall bookings on the new run, while `sensor_clean` stays zero:**
--
--   WITH b AS (SELECT sb.need_atom, st.stall_kind FROM public.ottoq_stall_bookings sb
--                JOIN public.stalls st ON st.id = sb.stall_id
--               WHERE st.depot_id='11111111-1111-1111-1111-111111111111'
--                 AND sb.sim_run_id = '<the new run>')
--   SELECT need_atom, count(*) AS bookings, string_agg(DISTINCT stall_kind, ', ') AS kinds
--     FROM b WHERE need_atom IN ('perimeter_walkaround','sensor_clean') GROUP BY 1;
--
-- **Scope the query to the new `sim_run_id`.** The 3,257 historical rows are not deleted, so an unscoped
-- count will still show them and read as a failed fix — the `0250`/rule-8 defect shape in miniature.
--
-- And confirm the legs are being written under the new type at all:
--
--   SELECT leg_type, count(*), count(*) FILTER (WHERE to_stall_id IS NOT NULL) AS with_stall
--     FROM public.ottoq_itinerary_legs WHERE leg_type IN ('perimeter_walkaround','service')
--    GROUP BY 1;
--
-- `perimeter_walkaround` legs must appear with **`with_stall = 0`**, and the `service` leg count must
-- fall. If `perimeter_walkaround` legs are zero, the planner is not reaching the non-bay loop for this
-- atom and the diagnosis in `0338` §8 needs re-deriving.

-- ══ APPLIED ═══════════════════════════════════════════════════════════════════
--
-- **Applied 2026-09-22 15:53:32 UTC (10:53 AM CT) as `20260922155332`**, in a window verified clear:
-- canon 9/9 `satisfies_floor` and `passed`, `ottoq_sim_runs` 0 active, and `pg_stat_activity` 0 pairs in
-- flight (the only honest signal, per G141). All blocks ran: P1 confirmed the defect live (3,785 walkaround
-- bookings against sensor_clean's 0), P2 confirmed the constraint forbade the value, (A) extended it, (B)
-- spliced the bridge, V1/V2/V3 passed, V4 recorded the baseline.
--
-- **VERIFIED independently of the migration's own asserts**, re-reading the catalog afterwards:
--
--     ottoq_svc_to_leg_type('perimeter_walkaround')  = 'perimeter_walkaround'   (was 'service')
--     ottoq_svc_to_leg_type('sensor_clean')          = 'sensor_clean'           (unchanged)
--     ottoq_svc_to_leg_type('a_code_nobody_declares')= 'service'                (ELSE intact)
--     constraint permits 'perimeter_walkaround'      = true
--
-- **TWO DEVIATIONS FROM THE FILE, both declared rather than dropped (APPLYING.md step 4).**
--
--   1. As with `0424`, the apply channel takes SQL inline, so whole-line `--` comments and the one psql
--      directive were stripped. Comment-stripped and whitespace-collapsed, file and submission differed by
--      exactly 22 characters — `\set ON_ERROR_STOP on`, a psql directive that is not SQL.
--   2. **A REAL CORRECTION, made at submit time and back-ported into this file so the two now match:**
--      three `RAISE WARNING` strings used `%s` where PL/pgSQL takes `%`. It is cosmetic — `%s` consumes the
--      argument and prints a literal `s` after it, and only on the failure paths — but a malformed message
--      is worst exactly when it is being read, so it was fixed in the SQL that ran and the file was then
--      amended to agree. **The file above is what executed.** The `EXCEPTION` strings were already correct.
--
-- **`forces_recert` row written by this file**, moving the floor to 2026-09-22 15:54:23 and putting 9 of 9
-- canons into `NOT satisfies_floor`. `0426` was applied 51 seconds later deliberately, so ONE resweep
-- covers both.
--
-- **NOT YET VERIFIED, and this is what actually settles it:** that a NEW run books no service bay for the
-- walkaround. §5's query must be scoped to the new `sim_run_id` — the 3,785 historical rows are not deleted,
-- so an unscoped count still shows them and reads as a failed fix.

