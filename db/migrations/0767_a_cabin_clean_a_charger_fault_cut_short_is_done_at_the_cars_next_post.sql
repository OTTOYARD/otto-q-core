-- migration-version: APPLIED-NO-LEDGER-ROW
-- migration-name:    a_cabin_clean_a_charger_fault_cut_short_is_done_at_the_cars_next_post
--
-- 0767  **A routine cabin clean that a charger fault cut short is done by the arm at the car's next post.** (G486)
--
-- ══ §0 CHASE'S CALL, WHICH THIS FILE CARRIES OUT ═════════════════════════════════════════════════════════════════════
--
--   Chase, 2026-10-23, with 0764 on (0765 §0): "cars should be cleaned via overhead arm while they charge always
--   regardless". The dial stall_cabin_robot has been 2 at the twin depot since then, by Chase.
--
-- ══ §1 WHAT IS LEFT, MEASURED (run 78c0624c, busy_day, the twin depot, read 2026-10-24 between 03:42 and 03:50 UTC,
--       10:42-10:50 PM CT on 10-23, read-only) ════════════════════════════════════════════════════════════════════════
--
--   Car 12cb06f0 (a Tesla at 25%) plugged into CANOPY-03 W-23 at sim 14:18:16 and the post's arm began its routine clean
--   at 14:18:27 (5.8 minutes). At 14:20:09 the charger faulted (fault.station_hardware, a 631-minute repair), the
--   charge arm let the car go (arm.emergency_release), and when the arm's cycle ran out the completion step found the
--   car off the post and cancelled the routine (0764: "it was not a need, so it is cancelled rather than sent to a
--   technician"), its leg skipped, the interruption recorded as 'left_the_cabin_robot' at 14:24:33. The car was
--   re-queued and plugged into CANOPY-03 E-29 at 14:24:53, and by sim 14:49 it had charged 25 minutes there with no
--   clean: its visit read charge pending, readiness_check pending, interior_inspection done, interior_tidy cancelled.
--   The starter decides the routine once a visit and records the decision when the clean starts
--   (meta.arm_routine = {'outcome': 'cleaned', ...}), so an interrupted routine reads as decided and is never begun
--   again; the departure test reads a cancelled atom as closed, so the car would leave uncleaned. It is the one routine
--   of the run's 97 begun by 03:50 UTC that a fault cut short (5 tidies cancelled in all; the other 4 were alert tidies
--   the triage cleared, which is right); with 11 of 85 charges ending in a fault on this run (13%), and the arm cleaning
--   in a charge's first 6 minutes, it is a car or two a day.
--
-- ══ §2 WHAT THIS CHANGES (at stall_cabin_robot = 2 only; at 0 and 1 nothing decides differently) ══════════════════════
--
--   Three substitutions on the live bodies, the same test in both places that ask whether a routine is decided:
--   (a) public.ottoq_start_concurrent_atoms: a routine the visit recorded as begun ('cleaned') whose only routine atoms
--       were cancelled with an interruption (the car left the post before the arm was home, which 0764 cancels) counts
--       as undecided, so the car's next post cleans it as a routine, through the same branch, its own leg and the same
--       hold. Any other recorded outcome stands: an immediate turnaround stays recorded once (0765), and a clean under
--       way or done blocks a second.
--   (b) the same starter: a decision taken again keeps the one it follows, as meta.arm_routine.after, so the record
--       shows both posts.
--   (c) twin.ottoq_sim_advance_visit_atoms hands the starter a car charging on a fast-charger post whose visit has no
--       tidy to do and no routine decided (0764); it now hands it such a car whose routine was cut short, by the test of
--       (a), so the starter sees it on its next pass. Its cancel is unchanged: a routine whose car left the post is still
--       cancelled, and a needed tidy still goes back to pending (0758), which the arm of the next post takes by 0758's
--       branch.
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the starter and the completion step are the bodies 0765 left and live carries (prosrc md5
--   5b98fb1d and fb7cde23), 0765 is applied, and the dial is catalogued 0..2 as 0765 left it. P2 once. The pre-images to
--   ottoq_schema_snapshots as '0767_pre'. Each anchor matches once, read with bare newlines whatever line endings the
--   paste carried. V1 each body less its changes is its pre-image. V3 each patched body is byte for byte the one the
--   tests ran (md5). V2 the dial is catalogued 0..2 with this file's description (this file sets no dial value).
--   tests/test_arm_clean_after_a_fault_sql.py runs this file on the scratch PostgreSQL over 0765's test world with 0765
--   applied (the live starter and completion step, md5 asserted): at 0 and at 1 the same world is byte-identical with
--   and without 0767; before it, at 2, a routine a fault cut short is never begun again on the car's next post; after
--   it, the next post's arm cleans the car as a routine, with its own leg, the hold and a record that names both posts,
--   and the clean completes and is not repeated; a routine cut short twice is done at the third post; a car off any post
--   is not decided until it charges again; a needed tidy cut short is the next arm's by 0758's branch, as before; an
--   immediate turnaround stays recorded once; 0767 pasted with Windows line endings applies to the same body; and it
--   refuses a second apply, a body it did not read, a database without 0765 and a dial not as 0765 left it.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ══════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE: at 0 and 1 the starter and the completion step decide exactly as before (V1; every change is
--   inside a branch the dial at 2 opens), and no certification arm, canon cell or dial experiment sets the dial to 2.
--   forces_dial_restart FALSE: no experiment varies it.
--
-- ══ §5 ON AT THE TWIN DEPOT (CLAUDE.md rule 12) ═════════════════════════════════════════════════════════════════════════
--
--   The twin depot's dial has been 2 since 0764, by Chase (2026-10-23, 9:19 AM CT), and this file makes 2 do what Chase
--   asked of it, so it is on from each run's next pass after the apply. No statement is needed. The demo-run check:
--   db/checks/0461 (6), every routine a fault cut short followed by a clean at the car's next post. Undo: the dial to 1
--   (0758's arm alone), or the rollback below.
--
-- ROLLBACK: EXECUTE the two `definition`s in ottoq_schema_snapshots WHERE label = '0767_pre'; UPDATE the catalog row's
--   description back to 0765's; DELETE FROM public.ottoq_cert_lineage WHERE name =
--   '0767_a_cabin_clean_a_charger_fault_cut_short_is_done_at_the_cars_next_post'. Cleans and legs already written stay
--   as the record of what happened.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0767 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies this file was written against, 0765, and the dial as 0765 left it ──
DO $p1$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)'))
       IS DISTINCT FROM '5b98fb1dbd54fb0baf9f39f77ca2660c'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'))
       IS DISTINCT FROM 'fb7cde232a1b8311eb2f768c812f4c9a' THEN
    RAISE EXCEPTION '0767 P1: a function this file patches is not the body it was written against';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                  WHERE name = '0765_every_charge_is_cleaned_however_short_and_a_topped_off_car_has_its_visit_as_it_plugs_in') THEN
    RAISE EXCEPTION '0767 P1: 0765 is not applied; apply in order';
  END IF;
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog
       WHERE param_key = 'stall_cabin_robot' AND default_value = 0 AND min_value = 0 AND max_value = 2
         AND NOT COALESCE(agent_writable, false) AND description LIKE '%0765 (G484)%'
         AND description NOT LIKE '%0767%') <> 1 THEN
    RAISE EXCEPTION '0767 P1: stall_cabin_robot is not catalogued 0..2 as 0765 left it';
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0767_a_cabin_clean_a_charger_fault_cut_short_is_done_at_the_cars_next_post') THEN
    RAISE EXCEPTION '0767 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0767_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)'::regprocedure,
                 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'::regprocedure);

-- ── the dial's description says what 2 now does ──
UPDATE public.ottoq_policy_param_catalog
   SET description = replace(replace(description,
         '0758 (G476), 0764 (G483), 0765 (G484):', '0758 (G476), 0764 (G483), 0765 (G484), 0767 (G486):'),
         'once a visit, except that', 'once a visit (and again at the car''s next post when a charger fault or an '
         'emergency moved it off the post before the arm was home, 0767), except that')
 WHERE param_key = 'stall_cabin_robot';

-- ── the patches ──
CREATE TEMP TABLE _0767_patch (fn text, seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0767_patch VALUES
  -- (a) a routine a fault cut short counts as undecided
  ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 1,
   $s1o$    IF NOT (COALESCE(v_meta, '{}'::jsonb) ? 'arm_routine')
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_new) t
$s1o$,
   $s1n$    IF (NOT (COALESCE(v_meta, '{}'::jsonb) ? 'arm_routine')
        -- 0767 (G486): a routine the arm began whose car left the post before the cycle ran out (a charger fault, an
        -- emergency; 0764's completion step cancels it and skips its leg) was never done, and every charging car is
        -- cleaned (Chase, G484): the car's next post decides it again. Any other recorded outcome stands.
        OR (v_meta -> 'arm_routine' ->> 'outcome' = 'cleaned'
            AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_new) t
                         WHERE t->>'svc' = 'interior_tidy' AND COALESCE((t->>'arm_routine')::boolean, false)
                           AND t->>'status' = 'cancelled' AND t ? 'interrupted')))
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_new) t
$s1n$),
  -- (b) a decision taken again keeps the one it follows
  ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', 2,
   $s2o$      IF v_routine IS NOT NULL THEN
        UPDATE ottoq_visit_needs SET meta = COALESCE(meta, '{}'::jsonb) || jsonb_build_object('arm_routine', v_routine)
$s2o$,
   $s2n$      IF v_routine IS NOT NULL THEN
        -- 0767 (G486): a decision taken again keeps the one it follows
        IF COALESCE(v_meta, '{}'::jsonb) ? 'arm_routine' THEN
          v_routine := v_routine || jsonb_build_object('after', v_meta -> 'arm_routine');
        END IF;
        UPDATE ottoq_visit_needs SET meta = COALESCE(meta, '{}'::jsonb) || jsonb_build_object('arm_routine', v_routine)
$s2n$),
  -- (c) the completion step hands the starter a car whose routine was cut short, by the test of (a)
  ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)', 1,
   $a1o$            OR (v_arm_every AND v.current_state = 'charging_dcfc'
                AND NOT (COALESCE(vn.meta, '{}'::jsonb) ? 'arm_routine')
$a1o$,
   $a1n$            OR (v_arm_every AND v.current_state = 'charging_dcfc'
                AND (NOT (COALESCE(vn.meta, '{}'::jsonb) ? 'arm_routine')
                     -- 0767 (G486): or a routine the arm began whose car left the post before the arm was home (the
                     -- 0764 branch below cancels it), so the starter decides it again at the car's next post
                     OR (vn.meta -> 'arm_routine' ->> 'outcome' = 'cleaned'
                         AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) r
                                      WHERE r->>'svc' = 'interior_tidy' AND COALESCE((r->>'arm_routine')::boolean, false)
                                        AND r->>'status' = 'cancelled' AND r ? 'interrupted')))
$a1n$);

-- A paste can arrive with Windows line endings (the SQL editor did so with 0765 on 2026-10-23); the stored bodies end
-- their lines in a bare newline, so the anchors and their replacements are read with bare newlines.
UPDATE _0767_patch SET c_old = replace(c_old, E'\r\n', E'\n'), c_new = replace(c_new, E'\r\n', E'\n');

DO $patch$
DECLARE f text; p record; v_def text; n int;
BEGIN
  FOR f IN SELECT DISTINCT fn FROM _0767_patch ORDER BY fn LOOP
    v_def := pg_get_functiondef(f::regprocedure);
    FOR p IN SELECT * FROM _0767_patch WHERE fn = f ORDER BY seq LOOP
      n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
      IF n <> 1 THEN
        RAISE EXCEPTION '0767: anchor % of % matches % times, not 1', p.seq, f, n;
      END IF;
      v_def := replace(v_def, p.c_old, p.c_new);
    END LOOP;
    EXECUTE v_def;
    IF pg_get_functiondef(f::regprocedure) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0767: % is not stored as patched', f;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: the body less its changes is its pre-image ──
DO $v1$
DECLARE r record; p record; v_body text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
             ('public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)', '5b98fb1dbd54fb0baf9f39f77ca2660c'),
             ('twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)', 'fb7cde232a1b8311eb2f768c812f4c9a'))
             AS x(fn, pre) LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = r.fn::regprocedure;
    FOR p IN SELECT * FROM _0767_patch WHERE fn = r.fn ORDER BY seq DESC LOOP
      v_body := replace(v_body, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_body) IS DISTINCT FROM r.pre THEN
      RAISE EXCEPTION '0767 V1: % less its changes is not its pre-image (md5 %)', r.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── V3: the patched bodies are byte for byte the ones the scratch PostgreSQL ran ──
DO $v3$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_start_concurrent_atoms(uuid,timestamp with time zone)'::regprocedure)
       IS DISTINCT FROM '25052205e0b6aa2c74504652b840869c'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'twin.ottoq_sim_advance_visit_atoms(uuid,timestamp with time zone)'::regprocedure)
       IS DISTINCT FROM '99f6aa09e973fcb914ae67f1328c0d49' THEN
    RAISE EXCEPTION '0767 V3: a patched body is not the one the tests ran';
  END IF;
END $v3$;

-- ── V2: the dial, as declared, and set nowhere by this file ──
DO $v2$
BEGIN
  IF (SELECT count(*) FROM public.ottoq_policy_param_catalog
       WHERE param_key = 'stall_cabin_robot' AND default_value = 0 AND min_value = 0 AND max_value = 2
         AND NOT COALESCE(agent_writable, false) AND description LIKE '%0765 (G484), 0767 (G486):%'
         AND description LIKE '%next post when a charger fault%') <> 1 THEN
    RAISE EXCEPTION '0767 V2: the dial is not catalogued 0..2 as declared';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0767_a_cabin_clean_a_charger_fault_cut_short_is_done_at_the_cars_next_post', false, false,
        'G486. At stall_cabin_robot 2: public.ottoq_start_concurrent_atoms counts a routine recorded as begun whose '
        'only routine atoms were cancelled with an interruption (the car left the post before the arm was home, as a '
        'charger fault makes it) as undecided, so the car''s next post cleans it, and a decision taken again keeps the '
        'one it follows as meta.arm_routine.after; twin.ottoq_sim_advance_visit_atoms hands the starter such a car by '
        'the same test. At 0 and 1 none of it runs (V1). No certification arm, canon cell or dial experiment sets the '
        'dial to 2.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-24 12:39:24 UTC (7:39 AM CT), no ledger row ═══════════════════════════════════════════════════
--
--   Chase ran this file in the Supabase dashboard's SQL editor as the first of three in one paste made by
--   scripts/editor_paste.py from the files at 81dcaf3 (this file md5 3def7c14, its part of the paste 7c71baaf; the paste
--   a55de610, 41,415 bytes), each file its own transaction once its text's md5 had been checked. The header's version and
--   this footer are the only text added since. P0, P1, P2, the anchors, V1, V3 and V2 passed inside the file's
--   transaction; its lineage row and its two '0767_pre' snapshots carry 12:39:24.097236 UTC (the three transactions share
--   the paste's start time, as one editor message). Read back at 12:40:22 UTC (7:40 AM CT): the starter at md5
--   25052205e0b6aa2c74504652b840869c and the completion step at 99f6aa09e973fcb914ae67f1328c0d49, as V3 requires; the
--   dial catalogued 0..2 with this file's description and still 2 at the twin depot by Chase, so it is on there. No run
--   was live; not yet seen in a demo run.
