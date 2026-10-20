-- migration-version: 20261017182220
-- migration-name:    the_promise_is_graded_beside_what_the_owner_app_says
--
-- 0741  **The promise is graded beside what the owner app says.** When a car arrives, the owner app (and a personal
--       agent asking through OTTO-Command) tells its owner "Planned to be ready around <time>". That time is
--       public.ottoq_owner_car's ready_by: the end of the car's last planned itinerary leg. 0736's recorder now records it
--       at the moment it records the promise, and 0736's grade scores both on the same cars. Research wing, rule 10: it
--       measures. Whether the owner app should say the promise instead is a decision for a person (G454).
--
-- ══ §1 WHY (G454) ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   public.ottoq_owner_read says "Planned to be ready around ..." for one car and "Next planned ready: ..." for the
--   three soonest, both from ottoq_owner_car (prosrc md5 683bf45b, read 2026-10-17), whose ready_by is
--   max(planned_end_sim) over the car's itinerary legs in the run with status planned or active. Nothing has ever graded
--   that time against when the car was ready, and it cannot be graded after the fact. The itinerary is written in the
--   tick the visit arrives (on arm 83 every one of the 202 visits' first legs carries its visit's own transaction time)
--   and is then amended in place, with planned_end_sim rewritten by ottoq_yield_bay_holds, ottoq_reconcile_bay_
--   reservations, ottoq_readmit_reopened_needs, ottoq_readmit_resumed_visits, ottoq_release_vacated_spaces,
--   ottoq_activate_due_bay_reservations, ottoq_book_workflow_legs and twin.ottoq_sim_advance_flow_contract. So what an
--   owner was told at arrival has to be recorded at that moment, which is what 0736's recorder already does for the
--   promise.
--   What the plan is made of shows why it needs grading. One car on arm 82 (busy day), read from its legs as they stood
--   after the run: a readiness check planned at 17:51-17:54 UTC behind an L2 charge leg whose duration assumed an 11 kW
--   charger (duration_basis {"kind": "flow_contract", "charger_kw_assumed": 11}), done at 13:42-13:45 (deviation_s
--   -14,952), and a PM leg carrying a planned 40-minute bay queue. A plan's legs mix the charge line's own estimates
--   with fixed assumptions, so its last end can sit hours away from the car's readiness in either direction. How often
--   and how far, against the promise on the same cars, is what tonight's two promise arms can say if they record both.
--
-- ══ §2 WHAT THIS CHANGES ══════════════════════════════════════════════════════════════════════════════════════════════
--
--   (a) twin.ottoq_sim_record_ready_promises: before it writes, it asks public.ottoq_owner_car for each car it promises.
--       That is the function the owner app reads, called rather than copied, so the record is what the app says even if
--       that function changes. It adds two keys to each promise's detail: owner_ready_by_sim (the app's ready_by, JSON
--       null when the app shows none) and owner_read (false if the call failed). The call has its own exception block:
--       a failure is a WARNING and the promises are still written. ottoq_owner_car is EXECUTE for postgres only, so a
--       recorder run as service_role records owner_read false. The sweep runner and the metronome run as postgres.
--   (b) public.ottoq_ready_promise_grade: in every part (all, situation, bundle, after_src) the app's time is graded
--       beside the promise:
--         - with_owner, graded_owner and by_owner: ready by the time the app said, censored as by_p50 is;
--         - owner_mae_min, owner_bias_min and owner_min_median;
--         - owner_in_past: the app named a time before the moment it was read;
--         - mae_p50_min_with_owner, by_p50_with_owner and by_p90_with_owner: the promise on the same cars.
--   Not changed: the promise, the estimator, the tick and the owner app.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0: nothing in flight. P1: the recorder is 0739's (prosrc md5 9a733c10) and the grade is 0736's (36a72509);
--   ottoq_owner_car(vehicles,uuid,numeric) exists and returns ready_by_sim from v_ready. P2: not already applied.
--   Pre-image to ottoq_schema_snapshots as '0741_pre'. Each anchor matches once. V1: each body less its patches is its
--   pre-image. V2: nothing for a run that does not exist, and the grade's empty answer is unchanged. V3: the grants are
--   the pre-images'.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE: the recorder runs only under 0736's dial ready_promise_record
--   (default 0), which no certification arm, canon cell or dial experiment sets; the call it adds reads and writes
--   nothing else; the grade is read-only.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0741_pre' (both functions);
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0741_the_promise_is_graded_beside_what_the_owner_app_says'.
--   Promises recorded meanwhile keep their two detail keys; the pre-image grade ignores them.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0741 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies read, the owner app's time present ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'))
     IS DISTINCT FROM '9a733c10d0a553a1f34d54eafcc887e3' THEN
    RAISE EXCEPTION '0741 P1: twin.ottoq_sim_record_ready_promises is not 0739''s body (md5 9a733c10)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_ready_promise_grade(uuid)'))
     IS DISTINCT FROM '36a7250943264056b352c4b94b7d28f1' THEN
    RAISE EXCEPTION '0741 P1: public.ottoq_ready_promise_grade is not 0736''s body (md5 36a72509)';
  END IF;
  IF to_regprocedure('public.ottoq_owner_car(vehicles,uuid,numeric)') IS NULL
     OR (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_owner_car(vehicles,uuid,numeric)'))
        NOT LIKE '%''ready_by_sim'', v_ready%' THEN
    RAISE EXCEPTION '0741 P1: public.ottoq_owner_car(vehicles, uuid, numeric) is missing or no longer returns ready_by_sim';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name = '0741_the_promise_is_graded_beside_what_the_owner_app_says') THEN
    RAISE EXCEPTION '0741 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0741_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid IN ('twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'::regprocedure,
                 'public.ottoq_ready_promise_grade(uuid)'::regprocedure);

CREATE TEMP TABLE _0741_patch (seq int, fn regprocedure, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0741_patch VALUES
-- (1) the recorder holds what the owner app says
(1, 'twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'::regprocedure,
$old$DECLARE v_depot uuid; v_ids uuid[]; v_n int := 0;
$old$,
$new$DECLARE v_depot uuid; v_ids uuid[]; v_n int := 0; v_owner jsonb;
$new$),
-- (2) it asks the owner app, in its own block, before it writes
(2, 'twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'::regprocedure,
$old$  BEGIN
    INSERT INTO public.ottoq_ready_promises
$old$,
$new$  -- 0741 (G454): what the owner app tells each owner at this moment ("Planned to be ready around ..."), asked of the
  -- app's own function so the record is what the app says; its own block, so a failure leaves the promises written
  BEGIN
    SELECT jsonb_object_agg(v.id::text, public.ottoq_owner_car(v, p_sim_run_id, 100) -> 'ready_by_sim')
      INTO v_owner
      FROM public.vehicles v WHERE v.id = ANY (v_ids);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '0741 owner ready-by: % %', SQLSTATE, SQLERRM;
    v_owner := NULL;
  END;
  BEGIN
    INSERT INTO public.ottoq_ready_promises
$new$),
-- (3) and records it beside the promise
(3, 'twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'::regprocedure,
$old$(rp.detail ->> 'futures')::int, rp.detail
$old$,
$new$(rp.detail ->> 'futures')::int,
           rp.detail || jsonb_build_object('owner_read', v_owner IS NOT NULL,
                                           'owner_ready_by_sim', v_owner -> rp.vehicle_id::text)
$new$),
-- (4) the grade reads the owner app's time
(4, 'public.ottoq_ready_promise_grade(uuid)'::regprocedure,
$old$         p.promised_at, p.detail ->> 'after_src' AS after_src,
$old$,
$new$         p.promised_at, p.detail ->> 'after_src' AS after_src,
         (p.detail ->> 'owner_ready_by_sim')::timestamptz AS owner_at,
$new$),
-- (5) grades it as it grades the median
(5, 'public.ottoq_ready_promise_grade(uuid)'::regprocedure,
$old$         extract(epoch FROM (g0.ready_at - g0.promised_at)) / 60.0 AS actual_min,
$old$,
$new$         extract(epoch FROM (g0.ready_at - g0.promised_at)) / 60.0 AS actual_min,
         extract(epoch FROM (g0.owner_at - g0.promised_at)) / 60.0 AS owner_min,
         CASE WHEN g0.owner_at IS NULL THEN NULL
              WHEN g0.ready_at IS NOT NULL THEN g0.ready_at <= g0.owner_at
              WHEN g0.owner_at < g0.run_end THEN false END AS by_owner,
$new$),
-- (6) and reports both on the same cars
(6, 'public.ottoq_ready_promise_grade(uuid)'::regprocedure,
$old$           'by_p90_of_those_with_due', round(avg(by_p90::int) FILTER (WHERE due_at IS NOT NULL)::numeric, 3)) AS j
$old$,
$new$           'by_p90_of_those_with_due', round(avg(by_p90::int) FILTER (WHERE due_at IS NOT NULL)::numeric, 3),
           'with_owner', count(owner_at), 'graded_owner', count(by_owner),
           'by_owner', round(avg(by_owner::int)::numeric, 3),
           'owner_mae_min', round(avg(abs(actual_min - owner_min))::numeric, 1),
           'owner_bias_min', round(avg(actual_min - owner_min)::numeric, 1),
           'owner_min_median', round(percentile_cont(0.5) WITHIN GROUP (ORDER BY owner_min)::numeric, 1),
           'owner_in_past', count(*) FILTER (WHERE owner_at < promised_at),
           'mae_p50_min_with_owner', round(avg(abs(actual_min - ready_p50_min)) FILTER (WHERE owner_at IS NOT NULL)::numeric, 1),
           'by_p50_with_owner', round(avg(by_p50::int) FILTER (WHERE owner_at IS NOT NULL)::numeric, 3),
           'by_p90_with_owner', round(avg(by_p90::int) FILTER (WHERE owner_at IS NOT NULL)::numeric, 3)) AS j
$new$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  FOR p IN SELECT * FROM _0741_patch ORDER BY seq LOOP
    v_def := pg_get_functiondef(p.fn);
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0741: anchor % (%) matches % times, not 1', p.seq, p.fn, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
    EXECUTE v_def;
    IF pg_get_functiondef(p.fn) IS DISTINCT FROM v_def THEN
      RAISE EXCEPTION '0741: % is not stored as patched', p.fn;
    END IF;
  END LOOP;
END $patch$;

-- ── V1: each patched body less its patches is its pre-image ──
DO $v1$
DECLARE f record; v_body text; p record;
BEGIN
  FOR f IN SELECT DISTINCT fn, CASE WHEN fn = 'public.ottoq_ready_promise_grade(uuid)'::regprocedure
                                    THEN '36a7250943264056b352c4b94b7d28f1' ELSE '9a733c10d0a553a1f34d54eafcc887e3' END AS md5_pre
             FROM _0741_patch LOOP
    SELECT prosrc INTO v_body FROM pg_proc WHERE oid = f.fn;
    FOR p IN SELECT * FROM _0741_patch WHERE fn = f.fn ORDER BY seq DESC LOOP
      v_body := replace(v_body, p.c_new, p.c_old);
    END LOOP;
    IF md5(v_body) IS DISTINCT FROM f.md5_pre THEN
      RAISE EXCEPTION '0741 V1: % less its patches is not its pre-image (md5 %)', f.fn, md5(v_body);
    END IF;
  END LOOP;
END $v1$;

-- ── V2: nothing for a run that does not exist, and the grade's empty answer unchanged ──
DO $v2$
DECLARE v_run uuid := gen_random_uuid(); v_g jsonb;
BEGIN
  IF twin.ottoq_sim_record_ready_promises(v_run, now()) <> 0 THEN
    RAISE EXCEPTION '0741 V2: the recorder acted on a run that does not exist';
  END IF;
  v_g := public.ottoq_ready_promise_grade(v_run);
  IF v_g IS DISTINCT FROM jsonb_build_object('run', v_run, 'promises', 0, 'by_situation', '{}'::jsonb,
                                             'by_bundle', '{}'::jsonb, 'by_after_src', '{}'::jsonb) THEN
    RAISE EXCEPTION '0741 V2: the grade of a run with no promises changed: %', v_g;
  END IF;
END $v2$;

-- ── V3: the grants are the pre-images' ──
DO $v3$
BEGIN
  IF (SELECT proacl::text FROM pg_proc WHERE oid = to_regprocedure('twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)'))
       IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}'
     OR (SELECT proacl::text FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_ready_promise_grade(uuid)'))
       IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}' THEN
    RAISE EXCEPTION '0741 V3: the recorder''s or the grade''s grants changed';
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0741_the_promise_is_graded_beside_what_the_owner_app_says', false, false,
  'twin.ottoq_sim_record_ready_promises records, beside each promise, the time the owner app says the car will be ready '
  '(public.ottoq_owner_car''s ready_by_sim, asked of the function itself in its own exception block); '
  'public.ottoq_ready_promise_grade grades that time beside the promise on the same cars. V1: each body less its '
  'patches is its pre-image. Recorded only under 0736''s dial ready_promise_record (default 0), which no certification '
  'arm, canon cell or dial experiment sets; the grade is read-only.', now())
ON CONFLICT (name) DO NOTHING;

COMMIT;

-- ══ APPLIED 2026-10-17 18:22:20 UTC (1:22 PM CT), ledger version 20261017182220 ═════════════════════════════════════
--
--   Through apply_migration with the sweep window closed and nothing in flight (P0 read 0, no run running, at 18:21:40
--   UTC). Executable part 9,136 characters, md5 6cd0a268ebb516507085e9beee76bc0f, equal to the ledger's statements[1]
--   read back. twin.ottoq_sim_record_ready_promises is now md5 a5cd09d49ae31a6adebc875b7a329cfd (prosrc) and
--   public.ottoq_ready_promise_grade 9058f3a5e684fcc52bc9e50bb1984a99. The estimator (bc718022), Kaplan-Meier and the
--   tick are 0739's and 0736's, untouched, and so is the owner app (ottoq_owner_car 683bf45b): it is called, not changed.
--
--   Dry-run first, on live, rolled back by a closing exception: P0-P2, the six patches (each anchor once), V1-V3, and an
--   end to end check on arm 82's run (busy day) at its hour 6 (2026-09-01 17:00 UTC). Three of its cars were put in the
--   line with a charge, a wash and PM, and their itineraries were given what the owner app reads: car 1 two planned legs
--   ending 90 and 240 minutes on, car 2 an active leg ending 150 on, car 3 none. The recorder wrote 3 promises in 664
--   ms with owner_read true and the app's times 240, 150 and none minutes on, and the grade counted 2 with an app time.
--   Rolled back in full: no lineage row, no snapshot, the recorder still 9a733c10 and no dry-run visit left.
--
--   Executed beside it on the scratch PostgreSQL by tests/test_ready_promise_sql.py (4 more tests, 17 in all, about 40
--   seconds), on the miniature depot taken through 0642 with the owner app's four functions as live
--   (tests/fixtures/owner_ready_by_stub.sql, md5 asserted).
