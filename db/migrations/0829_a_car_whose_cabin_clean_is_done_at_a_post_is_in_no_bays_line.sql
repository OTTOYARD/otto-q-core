-- migration-version: PENDING
-- migration-name:    0829_a_car_whose_cabin_clean_is_done_at_a_post_is_in_no_bays_line
--
-- 0829  **A car whose cabin clean is done at a charging post is in no bay's line, so it no longer yields its place in
--       the charge line for one.** (G544)
--
-- ══ §1 WHY (measured 2026-11-13 19:59-20:01 UTC, 1:59-2:01 PM CT, on run 7a08f52a, busy_day, the twin depot) ═══════════
--
--   0781 (charge_order_exit_first, on at the twin depot) has a car whose turn in the bays is far off yield its place
--   in the charge line to its own owner's cars. A car's turn in the bays is public.ottoq_bay_line's eta_min, and that
--   function puts an atom with requires_bay = 'detail' (the interior deep clean) in the WASH bays' line.
--   0817 (wash_bay_exterior_only, on at the twin depot since 2026-11-12) took cabin work out of the wash bays: the
--   deep clean is done by the charging post's arm, during the charge or on a cabin stop. Nothing told the bay line.
--   Read at tick 35 of the run:
--     the charge line                                              31 cars
--     of them yielding (exit_key = 1)                              15
--     of those, with a deep clean as their ONLY open bay work      11   (3 owe service-bay work, 1 an exterior wash)
--     mean place in the kernel's line: those 11 / cars not yielding   18.1 / 6.5
--     their mean turn in the bays, as the line computed it         120 minutes
--   and at tick 25 the wash line read 31 cars and 522 minutes (2.93 hours to clear three bays), of which 24 cars owed
--   only a deep clean and 7 an exterior wash. So eleven cars waited behind their own owner's other cars for a charger,
--   for a bay they would never enter; and the clean they were held for is done AT the charger, so the wait delayed it
--   too. Queueing is allowed (rule 9), but this queue was for nothing: the order was wrong about where the work is done.
--   The same line fed the agent's board (0783): it named the wash bays' queue at four times its size, which is half of
--   G541 (the other half, a bay counted idle while a car holds it, is in the board's own count and is not changed here).
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_bay_line: while public.ottoq_wash_bay_exterior_only(run) is true (0817's one test), an atom with
--   requires_bay = 'detail' is in no bay's line. Three substitutions on the live definition; every other byte is
--   0781's. Its readers follow at once: public.ottoq_charge_order_keys and public.ottoq_charge_line_state (a car held
--   only for a post's clean no longer yields), and public.ottoq_depot_constraint (the wash bays' queue is the cars
--   that owe an exterior wash).
--   No dial: the change follows 0817's. While wash_bay_exterior_only is 0 (the default, and every depot but the twin)
--   the function returns exactly what it returned (V2).
--
-- ══ §3 RULES 9 AND 14 ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   No car's charge, target or service changes. Fewer cars are held back: a car is no longer placed behind others for
--   a bay it does not use. 0781's exchange stays within one owner's own cars, as it was (rule 14).
--
-- ══ §4 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight and no run running (the line orders live cars). P1 the definition is the one read on live
--   (pg_get_functiondef md5 e894dd4d…) and 0817 and 0781 are classified. P2 once. The pre-image to
--   ottoq_schema_snapshots as '0829_pre'. Each anchor matches once. V1 ACL, security, volatility, settings and owner
--   unchanged. V2 on every run this database holds where the wash bay is not exterior only, the line is row for row
--   the pre-image's; where it is, the line is the pre-image's without the cars that owe only cabin work in the wash
--   lane, and holds no such car. V3 the body is the one the tests ran (md5).
--   tests/test_bay_line_cabin_work_sql.py runs this file on the scratch PostgreSQL over 0781's own harness.
--
-- ══ §5 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE: with wash_bay_exterior_only at its default of 0 the function is row for row what it was (V2),
--   and certification arms run at the defaults. forces_dial_restart FALSE: no dial is added; rule 12 holds the dial
--   program closed.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0829_pre'; DELETE FROM
--   public.ottoq_cert_lineage WHERE name = '0829_a_car_whose_cabin_clean_is_done_at_a_post_is_in_no_bays_line'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight, and no run running ──
DO $p0$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0829 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0829 P0: a run is running; the bay line orders its cars. Apply between runs';
  END IF;
END $p0$;

-- ── P2: once (asked first: after an apply the definition is no longer the one P1 names) ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0829_a_car_whose_cabin_clean_is_done_at_a_post_is_in_no_bays_line') THEN
    RAISE EXCEPTION '0829 P2: already applied';
  END IF;
END $once$;

-- ── P1: the definition this file was written against, and the two changes it joins ──
DO $p1$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_bay_line(uuid,uuid,timestamp with time zone)'::regprocedure))
       IS DISTINCT FROM 'e894dd4dcfd03fb7e5758b8956b2eda2' THEN
    RAISE EXCEPTION '0829 P1: public.ottoq_bay_line is not the definition this file was written against';
  END IF;
  IF to_regprocedure('public.ottoq_wash_bay_exterior_only(uuid)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                     WHERE name = '0817_the_wash_bay_is_exterior_only_and_cabin_work_is_done_at_a_fast_charger_post')
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                     WHERE name = '0781_the_charge_line_serves_first_the_cars_a_charge_sends_home') THEN
    RAISE EXCEPTION '0829 P1: 0781 or 0817 is not applied; apply in order';
  END IF;
END $p1$;

-- ── the pre-image, the attributes V1 holds the function to, and the pre-image as a callable for V2 ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0829_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_bay_line(uuid,uuid,timestamp with time zone)'::regprocedure;

CREATE TEMP TABLE _0829_attrs ON COMMIT DROP AS
SELECT p.proacl::text AS acl, p.prosecdef, p.provolatile, p.proconfig::text AS config, p.proowner
  FROM pg_proc p WHERE p.oid = 'public.ottoq_bay_line(uuid,uuid,timestamp with time zone)'::regprocedure;

DO $pre$
DECLARE v_def text := pg_get_functiondef('public.ottoq_bay_line(uuid,uuid,timestamp with time zone)'::regprocedure);
BEGIN
  IF position('FUNCTION public.ottoq_bay_line(' IN v_def) = 0 THEN
    RAISE EXCEPTION '0829: the definition does not name the function as expected';
  END IF;
  EXECUTE replace(v_def, 'FUNCTION public.ottoq_bay_line(', 'FUNCTION pg_temp._0829_pre(');
END $pre$;

-- ── the three substitutions, each matched once, read with bare newlines whatever line endings the paste carried ──
DO $patch$
DECLARE
  v_def text := replace(pg_get_functiondef('public.ottoq_bay_line(uuid,uuid,timestamp with time zone)'::regprocedure), E'\r', '');
  v_old text; v_new text; i int;
  v_olds text[] := ARRAY[
$a1$  WITH owed AS (
    SELECT vn.vehicle_id,$a1$,
$a2$      FROM ottoq_visit_needs vn
      JOIN vehicles v ON v.id = vn.vehicle_id
$a2$,
$a3$       AND a.value ->> 'requires_bay' IN ('service_bay', 'wash_bay', 'detail')
$a3$];
  v_news text[] := ARRAY[
$b1$  WITH x AS MATERIALIZED (
    --: 0829 (G544): with the wash bay exterior only (0817) cabin work is done at a charging post, by the post's arm,
    --: during the charge or on a cabin stop. Such an atom is in no bay's line. Read once for the run.
    SELECT public.ottoq_wash_bay_exterior_only(p_sim_run_id) AS ext
  ), owed AS (
    SELECT vn.vehicle_id,$b1$,
$b2$      FROM ottoq_visit_needs vn
      JOIN vehicles v ON v.id = vn.vehicle_id
      CROSS JOIN x
$b2$,
$b3$       AND a.value ->> 'requires_bay' IN ('service_bay', 'wash_bay', 'detail')
       AND NOT (a.value ->> 'requires_bay' = 'detail' AND COALESCE(x.ext, false))   --: 0829
$b3$];
BEGIN
  FOR i IN 1..3 LOOP
    v_old := replace(v_olds[i], E'\r', ''); v_new := replace(v_news[i], E'\r', '');
    IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
      RAISE EXCEPTION '0829: anchor % does not match exactly once', i;
    END IF;
    v_def := replace(v_def, v_old, v_new);
  END LOOP;
  EXECUTE v_def;
END $patch$;

-- ── V1: nothing about the function but its body moved ──
DO $v1$
BEGIN
  IF EXISTS (SELECT 1 FROM _0829_attrs a, pg_proc p
              WHERE p.oid = 'public.ottoq_bay_line(uuid,uuid,timestamp with time zone)'::regprocedure
                AND (p.proacl::text, p.prosecdef, p.provolatile, p.proconfig::text, p.proowner)
                    IS DISTINCT FROM (a.acl, a.prosecdef, a.provolatile, a.config, a.proowner)) THEN
    RAISE EXCEPTION '0829 V1 FAILED: the function''s ACL, security, volatility, settings or owner moved';
  END IF;
END $v1$;

-- ── V2: on every run here, at its own clock ──
DO $v2$
DECLARE r record; v_ext boolean; v_bad int; v_same int := 0; v_cut int := 0; v_gone bigint := 0;
BEGIN
  FOR r IN SELECT s.sim_run_id, s.depot_id, s.sim_clock_current AS c FROM public.ottoq_sim_runs s
            WHERE s.depot_id IS NOT NULL AND s.sim_clock_current IS NOT NULL LOOP
    v_ext := COALESCE(public.ottoq_wash_bay_exterior_only(r.sim_run_id), false);
    IF NOT v_ext THEN
      SELECT count(*) INTO v_bad FROM (
        (SELECT * FROM public.ottoq_bay_line(r.sim_run_id, r.depot_id, r.c)
         EXCEPT SELECT * FROM pg_temp._0829_pre(r.sim_run_id, r.depot_id, r.c))
        UNION ALL
        (SELECT * FROM pg_temp._0829_pre(r.sim_run_id, r.depot_id, r.c)
         EXCEPT SELECT * FROM public.ottoq_bay_line(r.sim_run_id, r.depot_id, r.c))) d;
      IF v_bad > 0 THEN
        RAISE EXCEPTION '0829 V2 FAILED: run % (wash bay not exterior only) differs from the pre-image in % rows', r.sim_run_id, v_bad;
      END IF;
      v_same := v_same + 1;
    ELSE
      --: the service lane is untouched; the wash lane holds no car that owes no wash-bay atom; and every car the
      --: pre-image had in the wash lane that owes a wash-bay atom is still there
      SELECT count(*) INTO v_bad FROM (
        (SELECT vehicle_id, lane, pos, open_min, ahead_min, bays, eta_min FROM public.ottoq_bay_line(r.sim_run_id, r.depot_id, r.c) WHERE lane = 'service_bay'
         EXCEPT SELECT vehicle_id, lane, pos, open_min, ahead_min, bays, eta_min FROM pg_temp._0829_pre(r.sim_run_id, r.depot_id, r.c) WHERE lane = 'service_bay')
        UNION ALL
        (SELECT vehicle_id, lane, pos, open_min, ahead_min, bays, eta_min FROM pg_temp._0829_pre(r.sim_run_id, r.depot_id, r.c) WHERE lane = 'service_bay'
         EXCEPT SELECT vehicle_id, lane, pos, open_min, ahead_min, bays, eta_min FROM public.ottoq_bay_line(r.sim_run_id, r.depot_id, r.c) WHERE lane = 'service_bay')) d;
      IF v_bad > 0 THEN RAISE EXCEPTION '0829 V2 FAILED: run % service lane moved (% rows)', r.sim_run_id, v_bad; END IF;
      SELECT count(*) INTO v_bad
        FROM public.ottoq_bay_line(r.sim_run_id, r.depot_id, r.c) l
       WHERE l.lane = 'wash_bay'
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn
                          CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(vn.atoms) = 'array' THEN vn.atoms ELSE '[]'::jsonb END) a
                         WHERE vn.sim_run_id = r.sim_run_id AND vn.vehicle_id = l.vehicle_id AND vn.status IN ('open', 'in_progress')
                           AND a.value ->> 'requires_bay' = 'wash_bay'
                           AND COALESCE(a.value ->> 'status', 'pending') NOT IN ('done', 'cancelled', 'skipped', 'in_progress'));
      IF v_bad > 0 THEN RAISE EXCEPTION '0829 V2 FAILED: run % wash lane still holds % car(s) owing no wash-bay work', r.sim_run_id, v_bad; END IF;
      SELECT count(*) INTO v_bad
        FROM pg_temp._0829_pre(r.sim_run_id, r.depot_id, r.c) o
       WHERE o.lane = 'wash_bay'
         AND EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn
                      CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(vn.atoms) = 'array' THEN vn.atoms ELSE '[]'::jsonb END) a
                     WHERE vn.sim_run_id = r.sim_run_id AND vn.vehicle_id = o.vehicle_id AND vn.status IN ('open', 'in_progress')
                       AND a.value ->> 'requires_bay' = 'wash_bay'
                       AND COALESCE(a.value ->> 'status', 'pending') NOT IN ('done', 'cancelled', 'skipped', 'in_progress'))
         AND NOT EXISTS (SELECT 1 FROM public.ottoq_bay_line(r.sim_run_id, r.depot_id, r.c) l
                          WHERE l.lane = 'wash_bay' AND l.vehicle_id = o.vehicle_id);
      IF v_bad > 0 THEN RAISE EXCEPTION '0829 V2 FAILED: run % lost % car(s) that owe a wash from the wash lane', r.sim_run_id, v_bad; END IF;
      v_gone := v_gone + (SELECT count(*) FROM pg_temp._0829_pre(r.sim_run_id, r.depot_id, r.c) WHERE lane = 'wash_bay')
                       - (SELECT count(*) FROM public.ottoq_bay_line(r.sim_run_id, r.depot_id, r.c) WHERE lane = 'wash_bay');
      v_cut := v_cut + 1;
    END IF;
  END LOOP;
  RAISE NOTICE '0829 V2 PASSED: % run(s) unchanged, % run(s) with the wash bay exterior only (% car(s) out of the wash line)', v_same, v_cut, v_gone;
END $v2$;

-- ── V3: the body is the one the scratch PostgreSQL ran ──
DO $v3$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_bay_line(uuid,uuid,timestamp with time zone)'::regprocedure)
       IS DISTINCT FROM '0c04c0d28c269bf9c6abf085f350d6e2' THEN
    RAISE EXCEPTION '0829 V3 FAILED: the body is not the one the tests ran';
  END IF;
END $v3$;

DROP FUNCTION pg_temp._0829_pre(uuid, uuid, timestamp with time zone);

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0829_a_car_whose_cabin_clean_is_done_at_a_post_is_in_no_bays_line', false, false,
        'G544. public.ottoq_bay_line: while public.ottoq_wash_bay_exterior_only(run) is true (0817), an atom with '
        'requires_bay = ''detail'' is in no bay''s line, so a car held only for a charging post''s cabin clean no longer '
        'yields its place in the charge line (0781) and the wash bays'' queue on the agent''s board (0783) is the cars '
        'that owe an exterior wash. At wash_bay_exterior_only 0, the default, the function is row for row what it was '
        '(V2), so no certification arm moves; no dial is added.',
        now());

COMMIT;
