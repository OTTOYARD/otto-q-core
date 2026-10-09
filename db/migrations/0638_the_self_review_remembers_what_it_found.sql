-- migration-version: PENDING
-- migration-name:    the_self_review_remembers_what_it_found
--
-- 0638  **The self-review remembers what it found until its evidence lets it go, and its window never cuts a run in two.**
--       Every morning at 12:55 UTC the check's self-review (ottoq_arbiter_assess) names, ranked, the places where the
--       kernel's check on an agent's charge order falls short, from the last 7 days' evidence. Each morning it forgot
--       what it said the morning before. An area left the list the moment the evidence that named it aged out of the
--       window, with nothing changed in the code or the world, and a reader could not tell the evidence from the
--       calendar (G369). The window was cut on the calendar too, so an area could turn on part of one run.
--
-- ══ §1 WHY (measured 2026-10-09 08:30-08:47 UTC, 3:30-3:47 AM CT, on live, read-only) ══════════════════════════════════════
--
--   (a) G369 (db/checks/0422 §4): the review ranked the charge clock's missing air-temperature level first at 7:22 PM CT
--       and again at 8:40 PM CT on 2026-10-08. At 9:13 PM CT, with no change but the window's start, it was gone (10
--       areas, 6 open, became 9 and 5); read with the earlier start it was back, ranked first. The one run at the
--       window's edge between the readings was cde5a21c (charges recorded 2026-10-02 01:14-02:22 UTC, 201 of them).
--   (b) G375 (0632 §1(a)) is the same shape through another door: the clock's audit reads only the charges after the
--       latest fit once it holds 30 of a kind, so an area can leave because the review can no longer test it, not
--       because it was answered.
--   (c) Nothing reads one review against the one before. The twin depot holds two (1 and 3; 2 was a rehearsal, rolled
--       back); review 3 (2026-10-08 22:50 UTC) names 11 areas, 8 open, and is the one the next review reads.
--   (d) The review's evidence is the charge ledger (recorded_at) and the graded orders (graded_at). A live run's charges
--       are recorded through its run (816bd28c over three hours, cde5a21c over 68 minutes); a backfilled run's all at one
--       moment. At the nightly hour today no run straddles the 7-day cut, so the window moves nothing tonight; at
--       9:13 PM CT on 2026-10-08 it would have kept cde5a21c whole.
--   (e) Rehearsed read-only on live at 08:45-08:47 UTC (3:45-3:47 AM CT), with the functions in pg_temp and the graded
--       orders read from the ledger 0630's view stands over: at G369's moment (2026-10-09 02:13 UTC) the window starts
--       at 01:14:17 UTC, cde5a21c's first charge, 58.7 minutes before the cut; now and at tonight's 12:55 UTC it starts
--       at the cut. Read against review 3, the review names 12 areas (247 graded orders, against 61 then) and keeps one
--       it no longer names: the charge clock's missing air level, not named since, nor read with review 3's window,
--       which is G375's case exactly. Both reviews took 40 s together.
--
-- ══ §2 WHAT CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) public.ottoq_review_window_start(depot, at, days): where the review's window starts. `days` before `at`, moved
--       back to the first evidence of a run the cut would split (its charges in the ledger, its graded orders), so the
--       review never reads part of one run. A run whose evidence began more than a day before the cut is cut as before:
--       a long session is read by the day, as the clock's audit reads it outside a run.
--   (b) public.ottoq_review_carry(live, since, at, prev, prev_since, prev_at, wide, lapse): one review read against the
--       one before. Every area named now is `seen`, with when the chain first named it (`first_seen_at`), now
--       (`last_seen_at`) and its window's start (`seen_since`). An area the review before named open, or carried, that
--       this one does not name is kept with status `unseen` and the reason, unless it was last named longer ago than
--       `lapse`:
--         - `left_window`: the review run over the window that last named it (`wide`) still names it, so what named it
--           is only older than this window; with that window's numbers;
--         - `not_named_since`: read with that window, it is not named either: answered, or no longer something the
--           review can test (G375). Kept as last named; the review cannot tell the two apart and says so.
--       Read with that window as built since (a fix landed after the orders that named it), it is kept as `built`. An
--       area last named longer ago than `lapse` (one window) is listed as `lapsed`; one the review before marked built
--       and this one does not name is history and goes. Ranked: what is named now and open, as the review ranks it;
--       then what is unseen, in the order it was ranked; then what is built.
--   (c) public.ottoq_arbiter_review(depot, days, trial): the review with its memory, written by nothing. The window from
--       (a); the self-review (ottoq_arbiter_self_assessment_v3) over it, with the trial if asked; the latest stored
--       review at the depot; the self-review over the earliest window that named an area this one does not, when one is
--       older than this window; (b). `window` says where it starts and where the calendar would have; `memory` what was
--       carried, from which review, and what lapsed.
--   (d) ottoq_arbiter_assess (same signature, same nightly job): writes (c) with the trial. A review with nothing graded
--       is written when it names, or still carries, a place to improve. Its code md5 covers (a)-(c).
--   Rule 10 holds as it was: the review is a finding for a person and changes nothing. The UI reads `status`; an
--   `unseen` area reads there as one to improve, which it is until it lapses.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 no certification in flight. P1 assess is the body 0628 left (md5 e79d4b26, unchanged by 0629-0637); 0637 is
--   applied (the graded orders' view exists); the nightly job calls assess; the objects are new. V1 the carry by meaning
--   on a planted pair of reviews: each case lands where §2(b) says, in the order it says. V2 the window at the twin
--   depot now. The review itself is not run in the apply: it reads every graded order twice (40 s on live, §1(e)), so
--   it is run read-only after the apply and recorded with the batch's check. Executed by
--   tests/test_agent_review_memory_sql.py on the miniature depot.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE, as 0619-0637: the review is read by a person and by the twin's
--   UI; no kernel decision, dial, seat, agent or certification arm reads it. No dial: it changes no decision.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0638_pre' AND object_kind = 'function'; then
--   DROP FUNCTION public.ottoq_arbiter_review(uuid, integer, boolean), public.ottoq_review_carry(jsonb, timestamptz,
--   timestamptz, jsonb, timestamptz, timestamptz, jsonb, interval), public.ottoq_review_window_start(uuid, timestamptz,
--   integer); DELETE FROM public.ottoq_cert_lineage WHERE name = '0638_the_self_review_remembers_what_it_found'. Reviews
--   written meanwhile keep their extra fields; nothing reads them but the UI, which ignores them.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0638 P0: a pair, the recert runner, a dial pair or a sweep arm is running right now';
  END IF;
END $inflight$;

-- ── P1: assess is the body 0628 left; 0637 is applied; the nightly job calls assess; the objects are new ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_arbiter_assess(uuid,integer)'))
     IS DISTINCT FROM 'e79d4b26460f266ddec422e567e0cbc7' THEN
    RAISE EXCEPTION '0638 P1: ottoq_arbiter_assess is not the body 0628 left (md5 e79d4b26); read it again';
  END IF;
  IF to_regclass('public.ottoq_charge_order_grades') IS NULL
     OR to_regprocedure('public.ottoq_arbiter_self_assessment_v3(uuid,timestamp with time zone,boolean)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
                     WHERE name = '0637_the_futures_read_the_latest_return_model_that_was_usable') THEN
    RAISE EXCEPTION '0638 P1: 0637 is not applied; apply 0630-0637 first';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE command LIKE '%public.ottoq_arbiter_assess(%') THEN
    RAISE EXCEPTION '0638 P1: no nightly job calls ottoq_arbiter_assess';
  END IF;
  IF to_regprocedure('public.ottoq_review_window_start(uuid,timestamp with time zone,integer)') IS NOT NULL
     OR to_regprocedure('public.ottoq_review_carry(jsonb,timestamp with time zone,timestamp with time zone,jsonb,timestamp with time zone,timestamp with time zone,jsonb,interval)') IS NOT NULL
     OR to_regprocedure('public.ottoq_arbiter_review(uuid,integer,boolean)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0638_the_self_review_remembers_what_it_found') THEN
    RAISE EXCEPTION '0638 P1: already applied';
  END IF;
END $premises$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0638_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = to_regprocedure('public.ottoq_arbiter_assess(uuid,integer)');

-- ══ (a) the window ═══════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_review_window_start(p_depot_id uuid, p_at timestamptz DEFAULT now(), p_days integer DEFAULT 7)
RETURNS timestamptz
LANGUAGE sql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0638: where the self-review's window starts: p_days before p_at, moved back to the first evidence of a run the cut
  -- would split (its charges in the ledger, its graded orders), so the review never reads part of one run (G369). A run
  -- whose evidence began more than a day before the cut is cut as before: a long session is read by the day.
  WITH c AS (
    SELECT p_at - make_interval(days => GREATEST(COALESCE(p_days, 7), 1)) AS cut
  ), e AS (
    SELECT l.sim_run_id AS run, l.recorded_at AS t
      FROM c, public.ottoq_charge_duration_ledger l
     WHERE l.depot_id = p_depot_id AND l.sim_run_id IS NOT NULL
       AND l.recorded_at >= c.cut - interval '2 days' AND l.recorded_at < p_at
    UNION ALL
    SELECT g.sim_run_id, g.graded_at
      FROM c, public.ottoq_charge_order_grades g
     WHERE g.depot_id = p_depot_id AND g.sim_run_id IS NOT NULL
       AND g.graded_at >= c.cut - interval '2 days' AND g.graded_at < p_at
  ), r AS (
    SELECT e.run, min(e.t) AS t0, max(e.t) AS t1 FROM e GROUP BY e.run
  )
  SELECT LEAST(c.cut, COALESCE((SELECT min(r.t0) FROM r
                                 WHERE r.t0 < c.cut AND r.t1 >= c.cut AND r.t0 >= c.cut - interval '1 day'), c.cut))
    FROM c
$fn$;
COMMENT ON FUNCTION public.ottoq_review_window_start(uuid, timestamptz, integer) IS
'0638. Where the check''s self-review window starts at a depot: p_days before p_at, moved back to the first evidence (a charge in ottoq_charge_duration_ledger, a graded order in ottoq_charge_order_grades) of a run the cut would split, so the review never reads part of one run (G369). A run whose evidence began more than a day before the cut is cut as before.';

-- ══ (b) one review read against the one before ═══════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_review_carry(p_live jsonb, p_since timestamptz, p_at timestamptz,
                                          p_prev jsonb, p_prev_since timestamptz, p_prev_at timestamptz,
                                          p_wide jsonb, p_lapse interval)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO 'public', 'extensions'
AS $fn$
  -- 0638: one review's areas (p_live, over the window from p_since, at p_at) read against the review before (p_prev,
  -- over p_prev_since, at p_prev_at). An area named now is seen; one the review before named open or carried and this
  -- one does not is kept as unseen until it was last named longer ago than p_lapse: left_window when the review over the
  -- window that last named it (p_wide) still names it, not_named_since when it does not (answered, or no longer
  -- testable: G375); built when p_wide names it built. Ranked: named now and open, unseen, built (G369).
  WITH live AS (
    SELECT a.value AS j, a.ordinality AS o
      FROM jsonb_array_elements(COALESCE(p_live, '[]'::jsonb)) WITH ORDINALITY a
     WHERE a.value ? 'area'
  ), prev AS (
    SELECT a.value AS j, a.ordinality AS o,
           COALESCE((a.value ->> 'first_seen_at')::timestamptz, p_prev_at) AS first_seen,
           COALESCE((a.value ->> 'last_seen_at')::timestamptz, p_prev_at) AS last_seen,
           COALESCE((a.value ->> 'seen_since')::timestamptz, p_prev_since) AS seen_since
      FROM jsonb_array_elements(COALESCE(p_prev, '[]'::jsonb)) WITH ORDINALITY a
     WHERE a.value ? 'area'
  ), named AS (
    SELECT l.o, COALESCE(l.j ->> 'status', '') = 'built' AS built,
           (l.j - ARRAY['rank', 'seen_finding', 'unseen_reason'])
           || jsonb_build_object('seen', true, 'first_seen_at', COALESCE(p.first_seen, p_at), 'last_seen_at', p_at,
                                 'seen_since', p_since) AS j
      FROM live l
      LEFT JOIN LATERAL (SELECT p.first_seen FROM prev p WHERE p.j ->> 'area' = l.j ->> 'area' ORDER BY p.o LIMIT 1) p ON true
  ), gone AS (
    SELECT p.*, w.j AS wj
      FROM prev p
      LEFT JOIN LATERAL (SELECT w.value AS j FROM jsonb_array_elements(COALESCE(p_wide, '[]'::jsonb)) w
                          WHERE w.value ->> 'area' = p.j ->> 'area' LIMIT 1) w ON true
     WHERE p.j ->> 'status' IN ('open', 'unseen')
       AND NOT EXISTS (SELECT 1 FROM live l WHERE l.j ->> 'area' = p.j ->> 'area')
  ), kept AS (
    SELECT g.o, COALESCE(g.wj ->> 'status', '') = 'built' AS built,
           CASE WHEN g.wj IS NOT NULL THEN 'left_window' ELSE 'not_named_since' END AS why,
           COALESCE(g.wj, g.j) AS base,
           CASE WHEN g.wj IS NOT NULL THEN g.wj ->> 'finding'
                ELSE COALESCE(g.j ->> 'seen_finding', g.j ->> 'finding') END AS seen_finding,
           g.first_seen, g.last_seen, g.seen_since
      FROM gone g
     WHERE g.last_seen > p_at - p_lapse
  ), carried AS (
    SELECT k.o, k.built, k.why,
           (k.base - ARRAY['rank', 'seen_finding', 'unseen_reason'])
           || jsonb_build_object(
                'status', CASE WHEN k.built THEN 'built' ELSE 'unseen' END,
                'seen', false, 'first_seen_at', k.first_seen, 'last_seen_at', k.last_seen, 'seen_since', k.seen_since,
                'unseen_reason', k.why, 'seen_finding', k.seen_finding,
                'finding', COALESCE(k.seen_finding, '')
                           || CASE WHEN k.why = 'left_window' AND k.built
                                   THEN ' This review''s evidence does not name it; read with the evidence that named it, it has been built since.'
                                   WHEN k.why = 'left_window'
                                   THEN ' This review''s evidence does not name it: what named it is older than its window, and read with that it still is.'
                                   ELSE ' This review''s evidence does not name it, nor read with what named it: answered, or no longer something the review can test.'
                              END
                           || ' Last named ' || public.ottoq_review_ct(k.last_seen) || '; kept until '
                           || public.ottoq_review_ct(k.last_seen + p_lapse) || ' unless named again.') AS j
      FROM kept k
  ), ranked AS (
    SELECT x.j, row_number() OVER (ORDER BY x.grp, x.o) AS rn
      FROM (SELECT n.j, CASE WHEN n.built THEN 3 ELSE 1 END AS grp, n.o FROM named n
            UNION ALL
            SELECT c.j, CASE WHEN c.built THEN 4 ELSE 2 END, c.o FROM carried c) x
  )
  SELECT jsonb_build_object(
    'areas', COALESCE((SELECT jsonb_agg(r.j || jsonb_build_object('rank', r.rn) ORDER BY r.rn) FROM ranked r), '[]'::jsonb),
    'named', (SELECT count(*) FROM named),
    'unseen', (SELECT count(*) FROM carried WHERE NOT built),
    'left_window', (SELECT count(*) FROM carried WHERE why = 'left_window'),
    'not_named_since', (SELECT count(*) FROM carried WHERE why = 'not_named_since'),
    'built_since', (SELECT count(*) FROM carried WHERE built),
    'lapsed', COALESCE((SELECT jsonb_agg(jsonb_build_object('area', g.j ->> 'area', 'title', g.j ->> 'title',
                                                            'first_seen_at', g.first_seen, 'last_seen_at', g.last_seen)
                                         ORDER BY g.o)
                          FROM gone g WHERE g.last_seen <= p_at - p_lapse), '[]'::jsonb),
    'lapse', p_lapse)
$fn$;
COMMENT ON FUNCTION public.ottoq_review_carry(jsonb, timestamptz, timestamptz, jsonb, timestamptz, timestamptz, jsonb, interval) IS
'0638. One self-review''s areas read against the review before: an area named now is seen (first_seen_at, last_seen_at, seen_since); one the review before named open or carried that this one does not is kept as unseen until it was last named longer ago than p_lapse, with why: left_window (the review over the window that last named it, p_wide, still names it) or not_named_since (it does not: answered, or no longer testable); built when p_wide names it built. Ranked named-and-open, unseen, built. Returns {areas, named, unseen, left_window, not_named_since, built_since, lapsed, lapse}. A finding for a person (G369, G375).';

-- ══ (c) the review with its memory ═══════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.ottoq_arbiter_review(p_depot_id uuid, p_days integer DEFAULT 7, p_trial boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $fn$
/* 0638: the check's self-review at a depot with its memory, written by nothing (ottoq_arbiter_assess writes it). The
   window starts where ottoq_review_window_start says (a run is never cut in two); the review is
   ottoq_arbiter_self_assessment_v3 over it, with the trial if asked; it is read against the latest stored review at the
   depot (ottoq_review_carry), and when an area that review named is not named now, the review is also run over the
   earliest window that named one, so the carry can tell an area whose evidence only aged out from one its evidence no
   longer names. An area is kept one window after it was last named (G369, G375). A finding for a person (rule 10). */
DECLARE
  v_days    int := GREATEST(COALESCE(p_days, 7), 1);
  v_cut     timestamptz := now() - make_interval(days => GREATEST(COALESCE(p_days, 7), 1));
  v_since   timestamptz := public.ottoq_review_window_start(p_depot_id, now(), p_days);
  v_lapse   interval := make_interval(days => GREATEST(COALESCE(p_days, 7), 1));
  v         jsonb;
  v_prev_id bigint; v_prev_since timestamptz; v_prev_at timestamptz; v_prev jsonb;
  v_wide_since timestamptz;
  v_wide    jsonb;
  v_carry   jsonb;
BEGIN
  v := public.ottoq_arbiter_self_assessment_v3(p_depot_id, v_since, p_trial);
  SELECT a.assessment_id, a.since, a.assessed_at, a.improvement_areas
    INTO v_prev_id, v_prev_since, v_prev_at, v_prev
    FROM public.ottoq_arbiter_assessments a
   WHERE a.depot_id = p_depot_id
   ORDER BY a.assessment_id DESC LIMIT 1;
  IF v_prev_id IS NOT NULL THEN
    SELECT min(COALESCE((x.value ->> 'seen_since')::timestamptz, v_prev_since)) INTO v_wide_since
      FROM jsonb_array_elements(COALESCE(v_prev, '[]'::jsonb)) x
     WHERE x.value ->> 'status' IN ('open', 'unseen')
       AND COALESCE((x.value ->> 'last_seen_at')::timestamptz, v_prev_at) > now() - v_lapse
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(v -> 'improvement_areas', '[]'::jsonb)) y
                        WHERE y.value ->> 'area' = x.value ->> 'area');
    IF v_wide_since IS NOT NULL THEN
      v_wide := CASE WHEN v_wide_since < v_since
                     THEN public.ottoq_arbiter_self_assessment_v3(p_depot_id, v_wide_since, false) -> 'improvement_areas'
                     ELSE v -> 'improvement_areas' END;
    END IF;
  END IF;
  v_carry := public.ottoq_review_carry(v -> 'improvement_areas', v_since, now(), v_prev, v_prev_since, v_prev_at, v_wide,
                                       v_lapse);
  RETURN (v - 'improvement_areas') || jsonb_build_object(
    'window', jsonb_build_object('since', v_since, 'cut', v_cut, 'days', v_days,
                                 'kept_whole_min', round((extract(epoch FROM v_cut - v_since) / 60.0)::numeric, 1)),
    'memory', (v_carry - 'areas') || jsonb_build_object('previous', v_prev_id, 'previous_at', v_prev_at,
                                                        'wide_since', v_wide_since),
    'areas_unseen', (v_carry -> 'unseen'),
    'improvement_areas', v_carry -> 'areas');
END $fn$;
COMMENT ON FUNCTION public.ottoq_arbiter_review(uuid, integer, boolean) IS
'0638. The check''s self-review at a depot with its memory, written by nothing (ottoq_arbiter_assess writes it): ottoq_arbiter_self_assessment_v3 over the window ottoq_review_window_start gives, read against the latest stored review by ottoq_review_carry, with the review over the earliest window that named an area this one does not. `window` and `memory` say where it starts and what it carried. A finding for a person (rule 10; G369, G375).';

-- ══ (d) the nightly review writes it ═════════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_arbiter_assess(p_depot_id uuid, p_days integer DEFAULT 7)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
/* 0621: the day's self-assessment of the check at a depot, written to ottoq_arbiter_assessments; NULL when nothing was
   graded in the window. A finding for a person, never a change (rule 10). 0622: the assessment is
   ottoq_arbiter_self_assessment_v2 (the clock's own calibration and audit, and the outflow). 0626: it is
   ottoq_arbiter_self_assessment_v3, which tries a change the scan names out of sample; and a review with nothing graded
   is written when it names a place to improve, since the clock's audit and its world need no graded order. 0627: the
   code md5 also covers where each arrival fell in its forecast (ottoq_inbound_arrival_z, ottoq_normal_cdf). 0638: it is
   ottoq_arbiter_review: the window never cuts a run in two, and the review is read against the one before, so an area
   is kept until its evidence lets it go (G369, G375); a review with nothing graded is written when it names, or still
   carries, a place to improve. */
DECLARE v jsonb; v_id bigint;
BEGIN
  v := public.ottoq_arbiter_review(p_depot_id, p_days, true);
  IF COALESCE((v ->> 'graded')::int, 0) = 0
     AND jsonb_array_length(COALESCE(v -> 'improvement_areas', '[]'::jsonb)) = 0 THEN
    RETURN NULL;
  END IF;
  INSERT INTO ottoq_arbiter_assessments (depot_id, since, n_graded, n_decisions, assessment, improvement_areas, code_md5)
  VALUES (p_depot_id, (v #>> '{window,since}')::timestamptz, COALESCE((v ->> 'graded')::int, 0),
          COALESCE((v ->> 'decisions')::int, 0),
          v - 'improvement_areas', COALESCE(v -> 'improvement_areas', '[]'::jsonb),
          md5(pg_get_functiondef('public.ottoq_arbiter_self_assessment(uuid,timestamptz)'::regprocedure)
              || pg_get_functiondef('public.ottoq_arbiter_self_assessment_v3(uuid,timestamptz,boolean)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_clock_audit_v2(uuid,timestamptz,jsonb)'::regprocedure)
              || pg_get_functiondef('public.ottoq_charge_clock_calibration(uuid,timestamptz)'::regprocedure)
              || pg_get_functiondef('public.ottoq_evidence_regime_scan(uuid,timestamptz,jsonb)'::regprocedure)
              || pg_get_functiondef('public.ottoq_review_words(text,text)'::regprocedure)
              || pg_get_functiondef('public.ottoq_inbound_arrival_z(jsonb,jsonb,double precision)'::regprocedure)
              || pg_get_functiondef('public.ottoq_normal_cdf(double precision)'::regprocedure)
              || pg_get_functiondef('public.ottoq_arbiter_review(uuid,integer,boolean)'::regprocedure)
              || pg_get_functiondef('public.ottoq_review_carry(jsonb,timestamptz,timestamptz,jsonb,timestamptz,timestamptz,jsonb,interval)'::regprocedure)
              || pg_get_functiondef('public.ottoq_review_window_start(uuid,timestamptz,integer)'::regprocedure)))
  RETURNING assessment_id INTO v_id;
  RETURN v_id;
END $function$;

REVOKE ALL ON FUNCTION public.ottoq_arbiter_review(uuid, integer, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_arbiter_review(uuid, integer, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_review_carry(jsonb, timestamptz, timestamptz, jsonb, timestamptz, timestamptz, jsonb, interval)
  TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ottoq_review_window_start(uuid, timestamptz, integer) TO anon, authenticated, service_role;

-- ══ V1: the carry by meaning, on a planted pair of reviews ═══════════════════════════════════════════════════════════════
DO $v1$
DECLARE
  t  constant timestamptz := '2026-10-09 12:55:00+00';
  pv constant jsonb := jsonb_build_array(
    jsonb_build_object('area', 'a', 'status', 'open', 'title', 'A', 'finding', 'a was seen.', 'rank', 1),
    jsonb_build_object('area', 'b', 'status', 'open', 'title', 'B', 'finding', 'b was seen.', 'rank', 2),
    jsonb_build_object('area', 'c', 'status', 'unseen', 'title', 'C', 'finding', 'c was seen. A note.',
                       'seen_finding', 'c was seen.', 'first_seen_at', t - interval '5 days',
                       'last_seen_at', t - interval '3 days', 'seen_since', t - interval '10 days', 'rank', 3),
    jsonb_build_object('area', 'd', 'status', 'open', 'title', 'D', 'finding', 'd was seen.',
                       'last_seen_at', t - interval '8 days', 'rank', 4),
    jsonb_build_object('area', 'f', 'status', 'open', 'title', 'F', 'finding', 'f was seen.', 'rank', 5),
    jsonb_build_object('area', 'e', 'status', 'built', 'title', 'E', 'finding', 'e was built.', 'rank', 6));
  lv constant jsonb := jsonb_build_array(
    jsonb_build_object('area', 'a', 'status', 'open', 'title', 'A', 'finding', 'a is seen.', 'rank', 1),
    jsonb_build_object('area', 'g', 'status', 'open', 'title', 'G', 'finding', 'g is new.', 'rank', 2),
    jsonb_build_object('area', 'h', 'status', 'built', 'title', 'H', 'finding', 'h is built.', 'rank', 3));
  wd constant jsonb := jsonb_build_array(
    jsonb_build_object('area', 'b', 'status', 'open', 'title', 'B', 'finding', 'b read wide.'),
    jsonb_build_object('area', 'f', 'status', 'built', 'title', 'F', 'finding', 'f read wide, built.'));
  v jsonb; v_order text; a jsonb;
BEGIN
  v := public.ottoq_review_carry(lv, t - interval '7 days', t, pv, t - interval '8 days', t - interval '1 day', wd,
                                 interval '7 days');
  v_order := (SELECT string_agg((x.value ->> 'area') || ':' || (x.value ->> 'status'), ' ' ORDER BY (x.value ->> 'rank')::int)
                FROM jsonb_array_elements(v -> 'areas') x);
  IF v_order IS DISTINCT FROM 'a:open g:open b:unseen c:unseen h:built f:built' THEN
    RAISE EXCEPTION '0638 V1: the carry ranks % , not a:open g:open b:unseen c:unseen h:built f:built', v_order;
  END IF;
  IF (v ->> 'named')::int <> 3 OR (v ->> 'unseen')::int <> 2 OR (v ->> 'left_window')::int <> 2
     OR (v ->> 'not_named_since')::int <> 1 OR (v ->> 'built_since')::int <> 1
     OR jsonb_array_length(v -> 'lapsed') <> 1 OR v #>> '{lapsed,0,area}' <> 'd' THEN
    RAISE EXCEPTION '0638 V1: the carry counts %', v - 'areas';
  END IF;
  SELECT x.value INTO a FROM jsonb_array_elements(v -> 'areas') x WHERE x.value ->> 'area' = 'a';
  IF (a ->> 'seen')::boolean IS NOT TRUE OR (a ->> 'first_seen_at')::timestamptz <> t - interval '1 day'
     OR (a ->> 'last_seen_at')::timestamptz <> t OR (a ->> 'seen_since')::timestamptz <> t - interval '7 days'
     OR a ->> 'finding' <> 'a is seen.' THEN
    RAISE EXCEPTION '0638 V1: an area named again is %', a;
  END IF;
  SELECT x.value INTO a FROM jsonb_array_elements(v -> 'areas') x WHERE x.value ->> 'area' = 'b';
  IF a ->> 'unseen_reason' <> 'left_window' OR a ->> 'seen_finding' <> 'b read wide.'
     OR (a ->> 'last_seen_at')::timestamptz <> t - interval '1 day' OR (a ->> 'seen_since')::timestamptz <> t - interval '8 days'
     OR a ->> 'finding' NOT LIKE 'b read wide. This review''s evidence does not name it: what named it is older%' THEN
    RAISE EXCEPTION '0638 V1: an area whose evidence aged out is %', a;
  END IF;
  SELECT x.value INTO a FROM jsonb_array_elements(v -> 'areas') x WHERE x.value ->> 'area' = 'c';
  IF a ->> 'unseen_reason' <> 'not_named_since' OR a ->> 'seen_finding' <> 'c was seen.'
     OR (a ->> 'first_seen_at')::timestamptz <> t - interval '5 days' OR (a ->> 'seen_since')::timestamptz <> t - interval '10 days'
     OR a ->> 'finding' NOT LIKE 'c was seen. This review''s evidence does not name it, nor read with what named it%' THEN
    RAISE EXCEPTION '0638 V1: an area its evidence no longer names is %', a;
  END IF;
  RAISE NOTICE '0638 V1: the carry by meaning: 3 named now (1 named before), 2 kept unseen (1 whose evidence aged out, 1 its evidence no longer names), 1 built since, 1 lapsed, 1 built before and gone; ranked named, unseen, built';
END $v1$;

-- ══ V2: the window at the twin depot now ═════════════════════════════════════════════════════════════════════════════════
DO $v2$
DECLARE v_cut timestamptz := now() - interval '7 days'; v_since timestamptz;
BEGIN
  v_since := public.ottoq_review_window_start('11111111-1111-1111-1111-111111111111', now(), 7);
  IF v_since > v_cut OR v_since < v_cut - interval '1 day' THEN
    RAISE EXCEPTION '0638 V2: the window starts % against the cut %', v_since, v_cut;
  END IF;
  RAISE NOTICE '0638 V2: the twin depot''s review window starts % min before the 7-day cut (%)',
    round((extract(epoch FROM v_cut - v_since) / 60.0)::numeric, 1),
    CASE WHEN v_since < v_cut THEN 'a run kept whole' ELSE 'no run straddles it' END;
END $v2$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0638_the_self_review_remembers_what_it_found', false, false,
  'the check''s nightly self-review reads its window whole (a run is never cut in two) and against the review before, '
  'keeping an area until its evidence lets it go (G369, G375). FALSE/FALSE as 0619-0637: the review is read by a person '
  'and the twin''s UI; no kernel decision, dial, seat, agent or certification arm reads it.',
  now())
ON CONFLICT (name) DO NOTHING;

COMMIT;
