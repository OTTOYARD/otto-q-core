-- migration-version: PENDING
-- migration-name:    the_end_state_fingerprint_sets_aside_the_leg_id_the_cleaning_arm_mints
--
-- 0794  **The end-state fingerprint sets aside the itinerary-leg id the post's cleaning arm mints, so two identical arms
--        can agree again.** (G510)
--
-- ══ §0 WHAT THE LAB FOUND (lab/engine/reports/e1_acceptance_2026-11-04.md; db/checks/0477) ═══════════════════════════
--
--   The first determinism pair run since 2026-10-14 -- in the research lab, on a copy of production's engine exported
--   from its catalog on 2026-11-04 at 21:43 UTC (3:43 PM CT), byte-identical to it on all 1,037 routines -- reads
--   'failed': busy_day, seed 171717, 12 ticks, 13 of 14 atoms equal, atom 14 (end_state) different. The one difference
--   in the end state is visit_needs/vis/h, and in it one key: each visit-need atom 0764 gives the post's overhead arm
--   carries 'robot_leg_id', the id of the itinerary leg the arm's routine runs on. That id is minted afresh in each arm,
--   so the two arms' visit needs differ in it and in nothing else (90 of 116 visits carry one; set aside, 0 of 116
--   differ). The arms behaved identically: commands, decisions, events, bookings, energy, proposals, deferrals,
--   calibration, rules, recalls and SDRs all agree.
--
--   Production would read the same: the code path is the one the lab copied, and the twin depot has run
--   stall_cabin_robot = 2 since 2026-10-23 14:19:53 UTC (Chase), the level at which 0764 writes the key. No pair has run
--   in production since 2026-10-14 (rule 12 turned certification off on 2026-10-20), so nothing saw it. 0764 was
--   classified forces_recert FALSE because "at 0 and 1 the starter and the completion step decide exactly as before";
--   that was true, and the depot was switched to 2 the same day, which is where the canon runs.
--
-- ══ §1 THE CHANGE ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   One anchored replacement in public.ottoq_boot_state_fingerprint, in the visit_needs CTE's row hash: an atom's
--   'robot_leg_id' is removed before hashing, as the function already removes visit_id, sim_run_id and the timestamps
--   from the row, and as its bookings, legs and dispatches CTEs already set aside their minted ids. Rows whose atoms
--   carry no robot_leg_id hash exactly as before (the rebuilt jsonb is the same value, so the same text), so every end
--   state at a depot below stall_cabin_robot 2 keeps its digest. Nothing in the engine reads this function to decide
--   anything: it is the certification pair's and the A/B rig's measurement (ottoq_determinism_pair, ottoq_ab_arm_atoms).
--
-- ══ §2 RULES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Rule 12: certification is off while the build goes on; this file changes what a pair measures, not what the depot
--   does, and nothing acts on its classification until testing resumes. Rule 9: no vehicle's need is touched. Rule 10:
--   found and tested in the research lab, shipped (or not) by a person.
--
--   forces_recert TRUE: every end-state digest at a depot running stall_cabin_robot 2 changes (it could not pass
--   before). forces_dial_restart FALSE: no dial, no decision.
--
-- ══ §3 TESTED IN THE LAB ONLY ════════════════════════════════════════════════════════════════════════════════════════
--
--   Applied to replicas of the lab database (never to production): the same pair reads passed on 14 of 14 atoms over
--   12 ticks and over a full depot-day (48 ticks), where production's engine reads 13 of 14 on both. The lab's fork
--   test then reproduces its trunk on every atom. The numbers are in db/checks/0477 and
--   lab/engine/reports/e1_acceptance_2026-11-04.md.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0794 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: not applied; 0764 applied; the function as read ──
DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0794_the_end_state_fingerprint_sets_aside_the_leg_id_the_cleaning_arm_mints') THEN
    RAISE EXCEPTION '0794 P1: already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0764_every_car_that_charges_gets_the_overhead_arms_cabin_clean') THEN
    RAISE EXCEPTION '0794 P1: 0764 is not applied (this file sets aside the key 0764 writes)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('public.ottoq_boot_state_fingerprint(uuid, uuid)'))
     IS DISTINCT FROM '90d490c24ae084d03477a8a782a9f856' THEN
    RAISE EXCEPTION '0794 P1: public.ottoq_boot_state_fingerprint is not the body read (md5 90d490c2)';
  END IF;
END $premises$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0794_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_boot_state_fingerprint(uuid, uuid)'::regprocedure;

-- ── the visit-needs row hash: an atom's robot_leg_id is set aside ──
CREATE TEMP TABLE _0794_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0794_patch VALUES
  (1,
   $o1$         md5((to_jsonb(t) - 'visit_id' - 'sim_run_id' - 'created_at' - 'updated_at' - 'meta')::text) AS h
  FROM public.ottoq_visit_needs t WHERE t.depot_id = p_depot$o1$,
   $n1$         md5(((to_jsonb(t) - 'visit_id' - 'sim_run_id' - 'created_at' - 'updated_at' - 'meta' - 'atoms')
              -- 0794 (G510): an atom's robot_leg_id is the id of the itinerary leg 0764 mints for the post's cleaning
              -- arm, fresh in every arm, so it is set aside like the row's own ids. Atoms without one are kept as
              -- they are, so their rows hash exactly as before.
              || jsonb_build_object('atoms',
                   CASE WHEN jsonb_typeof(t.atoms) = 'array' AND t.atoms @? '$[*].robot_leg_id'
                        THEN (SELECT jsonb_agg(x.e - 'robot_leg_id' ORDER BY x.o)
                                FROM jsonb_array_elements(t.atoms) WITH ORDINALITY x(e, o))
                        ELSE t.atoms END))::text) AS h
  FROM public.ottoq_visit_needs t WHERE t.depot_id = p_depot$n1$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_boot_state_fingerprint(uuid, uuid)'::regprocedure);
  FOR p IN SELECT * FROM _0794_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0794: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_boot_state_fingerprint(uuid, uuid)'::regprocedure) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0794: the fingerprint is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the patched body less its replacement is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  v_body := pg_get_functiondef('public.ottoq_boot_state_fingerprint(uuid, uuid)'::regprocedure);
  FOR p IN SELECT * FROM _0794_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM (SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0794_pre') THEN
    RAISE EXCEPTION '0794 V1: the fingerprint less its replacement is not its pre-image';
  END IF;
END $v1$;

-- ── V2: a row whose atoms carry no robot_leg_id hashes as before; one that does, without it ──
DO $v2$
DECLARE
  v_plain jsonb := '[{"svc": "charge", "est_min": 28}]';
  v_robot jsonb := '[{"svc": "interior_tidy", "arm_routine": true, "robot_leg_id": "00000000-0000-0000-0000-000000000001"}]';
  v_kept jsonb;
BEGIN
  SELECT CASE WHEN jsonb_typeof(v_plain) = 'array' AND v_plain @? '$[*].robot_leg_id'
              THEN (SELECT jsonb_agg(x.e - 'robot_leg_id' ORDER BY x.o) FROM jsonb_array_elements(v_plain) WITH ORDINALITY x(e, o))
              ELSE v_plain END INTO v_kept;
  IF v_kept::text IS DISTINCT FROM v_plain::text THEN
    RAISE EXCEPTION '0794 V2: atoms without a robot_leg_id are not kept as they are';
  END IF;
  SELECT CASE WHEN jsonb_typeof(v_robot) = 'array' AND v_robot @? '$[*].robot_leg_id'
              THEN (SELECT jsonb_agg(x.e - 'robot_leg_id' ORDER BY x.o) FROM jsonb_array_elements(v_robot) WITH ORDINALITY x(e, o))
              ELSE v_robot END INTO v_kept;
  IF v_kept::text IS DISTINCT FROM '[{"svc": "interior_tidy", "arm_routine": true}]' THEN
    RAISE EXCEPTION '0794 V2: the robot_leg_id is not set aside (%)', v_kept;
  END IF;
  PERFORM public.ottoq_boot_state_fingerprint('11111111-1111-1111-1111-111111111111'::uuid, NULL::uuid);
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0794_the_end_state_fingerprint_sets_aside_the_leg_id_the_cleaning_arm_mints', true, false,
        'G510. public.ottoq_boot_state_fingerprint sets aside an atom''s robot_leg_id (the itinerary leg 0764 mints for '
        'the post''s cleaning arm) before hashing a visit need. Found by the research lab''s first pair on a copy of '
        'production''s engine (2026-11-04): busy_day/171717/12 read failed on end_state only, the arms identical but for '
        'that minted id; with this change the lab''s pair passes 14 of 14. forces_recert: every end state at a depot '
        'running stall_cabin_robot 2 changes digest. No decision changes.',
        now());

COMMIT;
