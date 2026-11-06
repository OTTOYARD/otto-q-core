-- migration-version: 20261106174158
-- migration-name:    the_scorecard_does_not_count_the_arms_routine_clean_as_needed_work_left_open
--
-- 0800  **The throughput scorecard does not count the post's arm's routine clean as needed work left open at departure.**
--        (G521)
--
-- ══ §1 WHAT IS WRONG (FINDINGS G521; read in the research lab, 2026-11-06 between 05:06 and 05:08 UTC) ═══════════════
--
--   The starter writes every routine clean of the post's arm `must_do: true` (public.ottoq_start_concurrent_atoms, 0764).
--   When a routine is cut short at one post (the car moved) and the next post's decision is an owner's immediate
--   turnaround on a charge shorter than the arm's cycle (recorded, not held: 0765), the visit departs with that routine
--   cancelled and no done tidy, and ottoq_visit_outcomes counts it in needed_open_at_departure, so the scorecard's
--   rule9.left_with_needed_work_open reads 1 where no need was left: on the lab's 150-car 12-hour day with 0798, visit
--   ef2c7e0d (cut short at 7:15 AM, waived at the next post with 4.8 minutes of charge left against the 5.8-minute cycle),
--   and the same visit shape on the base day. The routine is the arm's promise to every charging car, not a need the
--   triage found (0764: "it was not a need, so it is cancelled rather than sent to a technician"); a needed tidy the arm
--   performs is a separate atom, not marked arm_routine (0758), and stays counted.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   One anchored insertion in ottoq_visit_outcomes' open count, after 0796's: a cancelled atom marked arm_routine is not
--   open. Read only by ottoq_throughput_scorecard; no engine decision reads either. A routine cut short and never done
--   again is a broken promise, which lab/research/p2_capacity/arm_routine_gaps.sql counts; it is not a rule-9 need.
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 not applied; the function is the body 0796 left (prosrc md5 81757b43, production read
--   2026-11-06 05:09:54 UTC, and the lab). The anchor matches once. V1 the body less its insertion is its pre-image. V2 on
--   every run the database holds, the patched function against its pre-image (a session-temporary copy): every row equal
--   but the open count, which never rises and falls only for a visit holding a cancelled arm_routine atom. V3 the patched
--   body is byte for byte the one the lab ran (md5 6f53b127): on a copy of the 150-car 0798 day the scorecard's
--   rule9.left_with_needed_work_open went 1 to 0 and V2 moved that one visit (ef2c7e0d), read 2026-11-06 05:10 UTC.
--
-- ══ §4 LINEAGE ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: no certification atom and no dial reads a scorecard. Rule 12: a
--   reporting fix, on as applied. Rule 9: no vehicle's need is touched; the change makes the report say what happened.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0800_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0800_the_scorecard_does_not_count_the_arms_routine_clean_as_needed_work_left_open'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0800 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0800_the_scorecard_does_not_count_the_arms_routine_clean_as_needed_work_left_open') THEN
    RAISE EXCEPTION '0800 P1: already applied';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_visit_outcomes(uuid)'))
     IS DISTINCT FROM '81757b435b6775cfa13eefae20cba44c' THEN
    RAISE EXCEPTION '0800 P1: public.ottoq_visit_outcomes is not the body 0796 left (md5 81757b43)';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0800_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_visit_outcomes(uuid)'::regprocedure;

CREATE TEMP TABLE _0800_patch (c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0800_patch VALUES (
$o$                                           <= d.dispatched_at))$o$,
$n$                                           <= d.dispatched_at))
               -- 0800 (G521): the post's arm's routine clean is a promise to every charging car (0764), not a need the
               -- triage found; cut short, or waived for an owner's immediate turnaround (0765), it is not work left open
               AND NOT (e->>'status' = 'cancelled' AND COALESCE((e->>'arm_routine')::boolean, false))$n$);

UPDATE _0800_patch SET c_old = replace(c_old, E'\r\n', E'\n'), c_new = replace(c_new, E'\r\n', E'\n');

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  SELECT * INTO p FROM _0800_patch;
  v_def := pg_get_functiondef('public.ottoq_visit_outcomes(uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
  IF n <> 1 THEN
    RAISE EXCEPTION '0800: the anchor matches % times, not 1', n;
  END IF;
  v_def := replace(v_def, p.c_old, p.c_new);
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_visit_outcomes(uuid)'::regprocedure) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0800: the function is not stored as patched';
  END IF;
END $patch$;

DO $v1$
DECLARE p record; v_body text;
BEGIN
  SELECT * INTO p FROM _0800_patch;
  v_body := replace(pg_get_functiondef('public.ottoq_visit_outcomes(uuid)'::regprocedure), p.c_new, p.c_old);
  IF md5(v_body) IS DISTINCT FROM (SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0800_pre') THEN
    RAISE EXCEPTION '0800 V1: the function less its insertion is not its pre-image';
  END IF;
END $v1$;

-- ── V2: on every run this database holds, the patched function against its pre-image (a session-temporary copy):
--        every row equal but the open count; the open count never rises; and it falls only where the visit holds a
--        cancelled arm_routine atom ──
DO $v2$
DECLARE v_pre text; r record; v_rows int := 0; v_moved int := 0; v_bad int; v_m int;
BEGIN
  SELECT replace(definition, 'CREATE OR REPLACE FUNCTION public.ottoq_visit_outcomes(',
                 'CREATE FUNCTION pg_temp.ottoq_visit_outcomes_0800_pre(')
    INTO v_pre FROM public.ottoq_schema_snapshots WHERE label = '0800_pre';
  IF strpos(v_pre, 'pg_temp.ottoq_visit_outcomes_0800_pre(') = 0 THEN
    RAISE EXCEPTION '0800 V2: could not name the pre-image';
  END IF;
  EXECUTE v_pre;
  FOR r IN SELECT DISTINCT vn.sim_run_id FROM public.ottoq_visit_needs vn WHERE vn.sim_run_id IS NOT NULL LOOP
    WITH a AS (SELECT * FROM public.ottoq_visit_outcomes(r.sim_run_id)),
         b AS (SELECT * FROM pg_temp.ottoq_visit_outcomes_0800_pre(r.sim_run_id))
    SELECT count(*) FILTER (WHERE (to_jsonb(a) - 'needed_open_at_departure') IS DISTINCT FROM (to_jsonb(b) - 'needed_open_at_departure')
                               OR a.needed_open_at_departure > b.needed_open_at_departure
                               OR (a.needed_open_at_departure < b.needed_open_at_departure AND NOT EXISTS (
                                     SELECT 1 FROM public.ottoq_visit_needs vn,
                                            jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) e
                                      WHERE vn.visit_id = a.visit_id AND e->>'status' = 'cancelled'
                                        AND COALESCE((e->>'arm_routine')::boolean, false)))),
           count(*) FILTER (WHERE a.needed_open_at_departure < b.needed_open_at_departure)
      INTO v_bad, v_m
      FROM a FULL JOIN b USING (visit_id);
    IF v_bad > 0 THEN
      RAISE EXCEPTION '0800 V2: run % has % visits the change should not have moved', r.sim_run_id, v_bad;
    END IF;
    v_rows := v_rows + 1;
    v_moved := v_moved + v_m;
  END LOOP;
  RAISE NOTICE '0800 V2: % runs compared, % visits no longer read a routine as work left open', v_rows, v_moved;
END $v2$;

-- ── V3: the patched body is byte for byte the one the research lab ran ──
DO $v3$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_visit_outcomes(uuid)'::regprocedure)
       IS DISTINCT FROM '6f53b127bfb8bce83d360e2c59b0d9f2' THEN
    RAISE EXCEPTION '0800 V3: the patched body is not the one the lab ran (md5 %)',
      (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_visit_outcomes(uuid)'::regprocedure);
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0800_the_scorecard_does_not_count_the_arms_routine_clean_as_needed_work_left_open', false, false,
        'G521. public.ottoq_visit_outcomes does not count a cancelled atom marked arm_routine (the post''s arm''s routine '
        'clean, 0764: a promise, not a need) as open at departure. Read only by ottoq_throughput_scorecard; no atom or dial '
        'reads it.',
        now());

COMMIT;

-- APPLIED 2026-11-06 at 17:41:58 UTC (11:41 AM CT), ledger 20261106174158, through apply_migration, on Chase's word
--   ("Yes, just keep building", read 2026-11-06 by 13:20 UTC, in reply to the report that asked to approve 0798-0802
--   and gave the go-ahead for the battery planner), each apply confirmed by Chase at the connector's prompt (he opened
--   it at "Okay I have supabase open in a tab. Now what?"). Nothing live, and the function at the md5 P1 names,
--   81757b43 (read 17:40:49 UTC, with 358 runs holding visits for V2 to compare; one pass of the function over all of
--   them took 6.1 s). The text sent was this file before its version line and this footer were set: 9,418 characters
--   (10,082 bytes), md5 1d080556, equal to the ledger's statements[1] read back. P0, P1, the anchor, V1, V2 and V3
--   passed inside the apply. Read back at 17:42:18 UTC: md5(prosrc) of public.ottoq_visit_outcomes 6f53b127, the body
--   the lab ran; one '0800_pre' snapshot; the lineage row FALSE/FALSE at 17:41:58. A reporting fix, on as applied. The
--   lab template ottoq_lab took the same text and ledger row at 17:57 UTC.
