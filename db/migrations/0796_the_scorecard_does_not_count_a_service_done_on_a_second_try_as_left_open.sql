-- migration-version: PENDING
-- migration-name:    the_scorecard_does_not_count_a_service_done_on_a_second_try_as_left_open
--
-- 0796  **The throughput scorecard does not count a service that was done on a second try as work left open at
--        departure.** (G514)
--
-- ══ §0 WHAT THE LAB FOUND (FINDINGS G514; lab/research/p2_capacity/) ══════════════════════════════════════════════════
--
--   The research lab's first capacity day (normal_day, 116 cars, seed 171717, production's engine) read
--   rule9.left_with_needed_work_open = 1 on its scorecard. The car, Waymo-AV-035 (visit f4af4ba7), left at 12:00 sim with
--   every service done: its first interior_tidy, begun by the post's cleaning arm at 11:30, was cancelled at 11:40 when the
--   car left the robot (0764: 'left_the_cabin_robot'), and 0767 began it again: a second interior_tidy, done at 11:50:48.
--   public.ottoq_visit_outcomes counts every must_do atom that is not done (unless triage cleared it) as open, so the
--   cancelled first copy read as open. Rule 9 held; the scorecard's rule-9 line said it did not.
--
-- ══ §1 THE CHANGE ═══════════════════════════════════════════════════════════════════════════════════════════════════
--
--   One anchored insertion in ottoq_visit_outcomes' open count: a cancelled must_do atom is not open when the same visit
--   holds a done atom of the same service, finished no later than the departure. Every other atom counts exactly as
--   before: a cancelled atom with no done copy is still open (unless triage cleared it), a done atom finished after the
--   departure is still open, and the triage and untimed counts are unchanged. Only ottoq_throughput_scorecard reads this
--   function (comment-stripped search of every routine and view, and the edge functions and the twin app's source).
--   The departure test itself (ottoq_departure_clear, 0543) is not touched and was not wrong.
--
-- ══ §2 CHECKS ════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 not applied; the function is the body read on 2026-11-05 (md5 4e702e55, production and lab).
--   The anchor matches once. V1: the body less its insertion is its pre-image. V2: on every run the database holds, the patched function
--   against its pre-image (a session-temporary copy): every row equal but the open count, which never rises and falls
--   only for a visit holding a cancelled must_do atom with a done copy of the same service.
--   Executed in the research lab on the day that found it: the scorecard reads left_with_needed_work_open 0, and every
--   other visit's row is unchanged (lab/research/p2_capacity/check_0796.sql).
--
-- ══ §3 LINEAGE ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: no certification atom and no dial reads a scorecard. Rule 12: a
--   reporting fix, on as applied. Rule 9: no vehicle's need is touched; the change makes the report say what happened.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0796_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0796_the_scorecard_does_not_count_a_service_done_on_a_second_try_as_left_open'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0796 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0796_the_scorecard_does_not_count_a_service_done_on_a_second_try_as_left_open') THEN
    RAISE EXCEPTION '0796 P1: already applied';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_visit_outcomes(uuid)'))
     IS DISTINCT FROM '4e702e55ba823aacac7ff5b319761df1' THEN
    RAISE EXCEPTION '0796 P1: public.ottoq_visit_outcomes is not the body read (md5 4e702e55)';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0796_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_visit_outcomes(uuid)'::regprocedure;

CREATE TEMP TABLE _0796_patch (c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0796_patch VALUES (
$o$               AND NOT (e->>'status' = 'cancelled' AND COALESCE((e->>'cleared_by_triage')::boolean, false))$o$,
$n$               AND NOT (e->>'status' = 'cancelled' AND COALESCE((e->>'cleared_by_triage')::boolean, false))
               -- 0796 (G514): a cancelled copy of a service the visit then did, before the car left, is not open
               -- (the post's cleaning arm, interrupted when the car leaves it, begins the routine again: 0764, 0767)
               AND NOT (e->>'status' = 'cancelled'
                        AND EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v.atoms, '[]'::jsonb)) e2
                                     WHERE e2->>'svc' = e->>'svc' AND e2->>'status' = 'done'
                                       AND COALESCE((e2->>'closed_at')::timestamptz, (e2->>'done_at')::timestamptz,
                                                    (e2->>'ends_at')::timestamptz, 'infinity'::timestamptz)
                                           <= d.dispatched_at))$n$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  SELECT * INTO p FROM _0796_patch;
  v_def := pg_get_functiondef('public.ottoq_visit_outcomes(uuid)'::regprocedure);
  n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
  IF n <> 1 THEN
    RAISE EXCEPTION '0796: the anchor matches % times, not 1', n;
  END IF;
  v_def := replace(v_def, p.c_old, p.c_new);
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_visit_outcomes(uuid)'::regprocedure) IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0796: the function is not stored as patched';
  END IF;
END $patch$;

DO $v1$
DECLARE p record; v_body text;
BEGIN
  SELECT * INTO p FROM _0796_patch;
  v_body := replace(pg_get_functiondef('public.ottoq_visit_outcomes(uuid)'::regprocedure), p.c_new, p.c_old);
  IF md5(v_body) IS DISTINCT FROM (SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0796_pre') THEN
    RAISE EXCEPTION '0796 V1: the function less its insertion is not its pre-image';
  END IF;
END $v1$;

-- ── V2: on every run this database holds, the patched function against its pre-image (a session-temporary copy):
--        every row equal but the open count; the open count never rises; and it falls only where a cancelled must_do
--        atom has a done copy of the same service finished by the departure ──
DO $v2$
DECLARE v_pre text; r record; v_rows int := 0; v_moved int := 0; v_bad int;
BEGIN
  SELECT replace(definition, 'CREATE OR REPLACE FUNCTION public.ottoq_visit_outcomes(',
                 'CREATE FUNCTION pg_temp.ottoq_visit_outcomes_0796_pre(')
    INTO v_pre FROM public.ottoq_schema_snapshots WHERE label = '0796_pre';
  IF strpos(v_pre, 'pg_temp.ottoq_visit_outcomes_0796_pre(') = 0 THEN
    RAISE EXCEPTION '0796 V2: could not name the pre-image';
  END IF;
  EXECUTE v_pre;
  FOR r IN SELECT DISTINCT vn.sim_run_id FROM public.ottoq_visit_needs vn WHERE vn.sim_run_id IS NOT NULL LOOP
    WITH a AS (SELECT * FROM public.ottoq_visit_outcomes(r.sim_run_id)),
         b AS (SELECT * FROM pg_temp.ottoq_visit_outcomes_0796_pre(r.sim_run_id))
    SELECT count(*) FILTER (WHERE (to_jsonb(a) - 'needed_open_at_departure') IS DISTINCT FROM (to_jsonb(b) - 'needed_open_at_departure')
                               OR a.needed_open_at_departure > b.needed_open_at_departure
                               OR (a.needed_open_at_departure < b.needed_open_at_departure AND NOT EXISTS (
                                     SELECT 1 FROM public.ottoq_visit_needs vn,
                                            jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) e,
                                            jsonb_array_elements(COALESCE(vn.atoms, '[]'::jsonb)) e2
                                      WHERE vn.visit_id = a.visit_id AND e->>'status' = 'cancelled'
                                        AND COALESCE((e->>'must_do')::boolean, false)
                                        AND e2->>'svc' = e->>'svc' AND e2->>'status' = 'done'))),
           count(*) FILTER (WHERE a.needed_open_at_departure < b.needed_open_at_departure)
      INTO v_bad, v_moved
      FROM a FULL JOIN b USING (visit_id);
    IF v_bad > 0 THEN
      RAISE EXCEPTION '0796 V2: run % has % visits the change should not have moved', r.sim_run_id, v_bad;
    END IF;
    v_rows := v_rows + 1;
    RAISE NOTICE '0796 V2: run %: % visits no longer read work left open', r.sim_run_id, v_moved;
  END LOOP;
  RAISE NOTICE '0796 V2: % runs compared', v_rows;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0796_the_scorecard_does_not_count_a_service_done_on_a_second_try_as_left_open', false, false,
        'G514. public.ottoq_visit_outcomes does not count a cancelled must_do atom as open at departure when the visit '
        'holds a done atom of the same service finished by the dispatch (the cleaning arm begins an interrupted routine '
        'again, 0767). Read only by ottoq_throughput_scorecard; no atom or dial reads it.',
        now());

COMMIT;
