-- migration-version: 20261106174427
-- migration-name:    a_recall_deferred_for_want_of_a_stall_opens_no_visit
--
-- 0802  **A recall that is deferred for want of a stall opens no visit.** (G520)
--
-- ══ §1 WHAT IS WRONG (FINDINGS G520; traced in the research lab, 2026-11-06 between 08:47 and 08:52 UTC) ══════════════
--
--   A car out at work is called home in three places (the twin's deployed-telemetry step at AP-4,
--   ottoq_decide_return_on_signal, and ottoq_plan_dispatch_tick's surplus_to_demand recall of an overnight hold), and each
--   books the car's appointment first through ottoq.ottoq_book_appointment, which opens the car's visit (the service
--   manifest, ottoq_derive_visit_needs) before it looks for a stall. When the need is deferrable and no stall is free the
--   booking returns secured = false, and every caller leaves the car out at work, to try again next tick ("a deferrable
--   need with no free stall keeps the car deployed and earning, retrying next tick"). The visit it opened stays: the same
--   tick the visit step's last statement (twin.ottoq_sim_advance_visit_atoms) closes every visit whose car is deployed,
--   so it closes `complete` (or `carried_over`) with nothing done, and the next tick's attempt opens another
--   (twin.ottoq_sim_advance_deployed_telemetry stamps the car's last_state_change every tick, so each attempt's visit has
--   its own clock and key). Car 05b0de6f (a Zoox overnight hold) was given visits at 11:20, 11:25 and 11:30 PM while out
--   and turned for home at 11:35. On the 150-car 24-hour lab day 63 of 651 visits (9.7%) were these, and the scorecard
--   counted them as visits still in the depot at the horizon (185 for 125 cars); 12 and 4 on the two 116-car 24-hour days,
--   none on a 12-hour day (6 AM-6 PM). No stall is booked by them, so they take no capacity: the defect is the count.
--
-- ══ §2 WHAT THIS CHANGES ════════════════════════════════════════════════════════════════════════════════════════════
--
--   Two anchored insertions in ottoq.ottoq_book_appointment, nothing else. The work from opening the visit to the stall
--   search runs in a block of its own, and when the search finds no stall, the call opened the visit (the car had none
--   open) and the need is deferrable, the block is rolled back whole: the visit, its plan and itinerary, the car's
--   manifest and charge plan, as if the call had not been made. The answer is the one every caller reads today
--   (secured false, no_free_stall), with visit_opened false beside it. The car stays out at work exactly as before and the
--   visit opens on the attempt that secures a stall, or on a need that cannot wait (unchanged: that car goes home with its
--   visit open). A visit the car already had open is never touched.
--
--   Rule 9: no car's need is moved. A deferred car's services are derived when it is actually called home, from the car as
--   it is then, as the last phantom's were; what an earlier visit still owed is carried into that visit as before (0698,
--   and the carry-over of carryover_eligible atoms, which no longer passes through a chain of phantoms).
--
-- ══ §3 CHECKS ══════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 not applied; the function is the body as it stands (prosrc md5 7017c172, production read
--   2026-11-06 08:51:47 UTC, and the lab). Each anchor matches once. V1 the body less its insertions is its pre-image.
--   V2 on a probe rolled back with its rows: a twin car with no open visit, booked against a depot with no stalls (the
--   search finds nothing, as on a full depot), opens no visit when the need can wait and opens one when it cannot.
--   V3 the patched body is byte for byte the one the lab ran.
--
-- ══ §4 LINEAGE ═════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert TRUE and forces_dial_restart TRUE: a run with deferred recalls writes fewer visit rows and draws its
--   variability cards at fewer moments, so a canon or a dial pair recorded before is not the twin's world (rule 12:
--   testing is off; nothing acts on either).
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0802_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0802_a_recall_deferred_for_want_of_a_stall_opens_no_visit'.

BEGIN;

SET LOCAL lock_timeout = '5s';

DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0802 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

DO $premises$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0802_a_recall_deferred_for_want_of_a_stall_opens_no_visit') THEN
    RAISE EXCEPTION '0802 P1: already applied';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('ottoq.ottoq_book_appointment(uuid,uuid,timestamp with time zone,text,text,boolean,numeric,numeric,uuid)'))
     IS DISTINCT FROM '7017c172ffaeb5c1fc59edca890777e5' THEN
    RAISE EXCEPTION '0802 P1: ottoq.ottoq_book_appointment is not the body as it stood (md5 7017c172)';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0802_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'ottoq.ottoq_book_appointment(uuid,uuid,timestamp with time zone,text,text,boolean,numeric,numeric,uuid)'::regprocedure;

CREATE TEMP TABLE _0802_patch (k int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0802_patch VALUES
(1,
$o$  IF NOT v_had_need THEN
    BEGIN
      PERFORM ottoq_sim_generate_service_manifest(p_vehicle_id, p_sim_run_id, NULL);
$o$,
$n$  -- 0802 (G520): from opening the visit to the stall search in a block of its own, rolled back whole when the search
  -- finds no stall for a need that can wait and this call opened the visit (the car stays out at work: no visit yet)
  BEGIN
  IF NOT v_had_need THEN
    BEGIN
      PERFORM ottoq_sim_generate_service_manifest(p_vehicle_id, p_sim_run_id, NULL);
$n$),
(2,
$o$  IF v_stall IS NULL THEN
    RETURN jsonb_build_object('secured', false, 'reason', 'no_free_stall',
                              'has_charge', v_has_charge, 'want_class', v_want_class);
  END IF;
$o$,
$n$  IF v_stall IS NULL THEN
    -- 0802 (G520): every caller leaves a car whose deferrable need found no stall out at work, retrying next tick; the
    -- visit this call opened would be closed unserved by the visit step the same tick, and another opened the next
    IF NOT v_had_need AND COALESCE(p_is_deferrable, false) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0097', MESSAGE = '0802: a recall deferred for want of a stall opens no visit';
    END IF;
    RETURN jsonb_build_object('secured', false, 'reason', 'no_free_stall',
                              'has_charge', v_has_charge, 'want_class', v_want_class);
  END IF;
  EXCEPTION WHEN SQLSTATE 'P0097' THEN
    RETURN jsonb_build_object('secured', false, 'reason', 'no_free_stall',
                              'has_charge', v_has_charge, 'want_class', v_want_class, 'visit_opened', false);
  END;
$n$);

UPDATE _0802_patch SET c_old = replace(c_old, E'\r\n', E'\n'), c_new = replace(c_new, E'\r\n', E'\n');

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('ottoq.ottoq_book_appointment(uuid,uuid,timestamp with time zone,text,text,boolean,numeric,numeric,uuid)'::regprocedure);
  FOR p IN SELECT * FROM _0802_patch ORDER BY k LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0802: anchor % matches % times, not 1', p.k, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('ottoq.ottoq_book_appointment(uuid,uuid,timestamp with time zone,text,text,boolean,numeric,numeric,uuid)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0802: the function is not stored as patched';
  END IF;
END $patch$;

DO $v1$
DECLARE p record; v_body text;
BEGIN
  v_body := pg_get_functiondef('ottoq.ottoq_book_appointment(uuid,uuid,timestamp with time zone,text,text,boolean,numeric,numeric,uuid)'::regprocedure);
  FOR p IN SELECT * FROM _0802_patch ORDER BY k DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM (SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0802_pre') THEN
    RAISE EXCEPTION '0802 V1: the function less its insertions is not its pre-image';
  END IF;
END $v1$;

-- ── V2: a twin car with no open visit, booked against a depot with no stalls (nothing found, as on a full depot): no
--    visit when the need can wait, one when it cannot. The probe and every row it wrote are rolled back. ──
DO $v2$
DECLARE
  v_veh uuid; a jsonb; b jsonb; n0 int; n1 int; n2 int;
  v_nostalls uuid := '00000000-0000-0000-0000-000000000802';
  t timestamptz := '2026-09-01 12:00:00+00';
BEGIN
  IF EXISTS (SELECT 1 FROM public.stalls WHERE depot_id = v_nostalls) THEN
    RAISE EXCEPTION '0802 V2: the probe depot holds stalls';
  END IF;
  SELECT v.id INTO v_veh FROM public.vehicles v
   WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111' AND v.category = 'autonomous'
     AND NOT EXISTS (SELECT 1 FROM public.ottoq_visit_needs vn
                      WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress'))
   ORDER BY v.id LIMIT 1;
  IF v_veh IS NULL THEN
    RAISE EXCEPTION '0802 V2: no twin car without an open visit to probe';
  END IF;
  BEGIN
    SELECT count(*) INTO n0 FROM public.ottoq_visit_needs WHERE vehicle_id = v_veh;
    a := ottoq.ottoq_book_appointment(v_veh, NULL, t, 'probe_0802', 'standard', true, 20, 50, v_nostalls);
    SELECT count(*) INTO n1 FROM public.ottoq_visit_needs WHERE vehicle_id = v_veh;
    b := ottoq.ottoq_book_appointment(v_veh, NULL, t, 'probe_0802', 'standard', false, 20, 50, v_nostalls);
    SELECT count(*) INTO n2 FROM public.ottoq_visit_needs WHERE vehicle_id = v_veh;
    RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '0802 V2: roll the probe back';
  EXCEPTION WHEN SQLSTATE 'P0099' THEN
    NULL;
  END;
  IF COALESCE((a->>'secured')::boolean, true) OR COALESCE((a->>'visit_opened')::boolean, true) OR n1 IS DISTINCT FROM n0 THEN
    RAISE EXCEPTION '0802 V2: a recall that can wait, with no stall, still opened a visit: % (% -> %)', a, n0, n1;
  END IF;
  IF COALESCE((b->>'secured')::boolean, true) OR n2 IS DISTINCT FROM n1 + 1 THEN
    RAISE EXCEPTION '0802 V2: a recall that cannot wait did not open its visit: % (% -> %)', b, n1, n2;
  END IF;
  RAISE NOTICE '0802 V2: deferred recall opened no visit (% -> %); a recall that cannot wait opened one (% -> %)', n0, n1, n1, n2;
END $v2$;

-- ── V3: the patched body is byte for byte the one the research lab ran ──
DO $v3$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'ottoq.ottoq_book_appointment(uuid,uuid,timestamp with time zone,text,text,boolean,numeric,numeric,uuid)'::regprocedure)
       IS DISTINCT FROM 'ed54d6d41281f605129fce092574ea65' THEN
    RAISE EXCEPTION '0802 V3: the patched body is not the one the lab ran (md5 %)',
      (SELECT md5(prosrc) FROM pg_proc
        WHERE oid = 'ottoq.ottoq_book_appointment(uuid,uuid,timestamp with time zone,text,text,boolean,numeric,numeric,uuid)'::regprocedure);
  END IF;
END $v3$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0802_a_recall_deferred_for_want_of_a_stall_opens_no_visit', true, true,
        'G520. ottoq_book_appointment rolls back the visit it opened when a deferrable recall finds no stall: the car stays '
        'out at work and its visit opens on the attempt that secures a stall. A run with deferred recalls writes fewer visit '
        'rows and draws its cards at fewer moments, so a canon or a dial pair recorded before is not the twin''s world.',
        now());

COMMIT;

-- APPLIED 2026-11-06 at 17:44:27 UTC (11:44 AM CT), ledger 20261106174427, through apply_migration, on Chase's word
--   ("Yes, just keep building", read 2026-11-06 by 13:20 UTC, in reply to the report that asked to approve 0798-0802
--   and gave the go-ahead for the battery planner), each apply confirmed by Chase at the connector's prompt (he opened
--   it at "Okay I have supabase open in a tab. Now what?"). Nothing live, the function at the md5 P1 names, 7017c172,
--   116 twin cars with no open visit and no stall at the probe depot (read 17:43:43 UTC). The text sent was this file
--   before its version line and this footer were set: 12,206 characters (12,868 bytes), md5 a481ee79, equal to the
--   ledger's statements[1] read back. P0, P1, the anchors, V1, V2 and V3 passed inside the apply. Read back at 17:44:33
--   UTC: md5(prosrc) of ottoq.ottoq_book_appointment ed54d6d4, the body the lab ran; no visit left by the probe and
--   none open; the lineage row TRUE/TRUE at 17:44:27 (rule 12: testing is off). On at the twin depot from the next demo
--   run. The lab template ottoq_lab took the same text and ledger row at 17:57 UTC.
