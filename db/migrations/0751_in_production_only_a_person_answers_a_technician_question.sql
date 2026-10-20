-- migration-version: 20261018112154
-- migration-name:    in_production_only_a_person_answers_a_technician_question
--
-- 0751  **In production only a person answers a technician's question.** (G465)
--       OTTO-Q asks the crew two kinds of question: may this car take an opportunistic top-off now, and is this work
--       green-lit. In the twin a simulated technician answers them in twin.ottoq_opportunistic_scan, by a seeded draw
--       (approve 70% of top-offs and 92% of green-lights), and the scan enacts an approved top-off: it moves the car and
--       claims a charger. Both tick paths call the scan on every tick, the production one (twin.ottoq_world_advance)
--       included, and the scan reads no feed mode. So at a depot a real feed drives, the twin's technician would answer
--       OTTO-Q's questions in place of the crew and move real cars on its own draw. Production is not live, so nothing
--       has been answered this way yet. A safety fix, not an experiment: at the twin depot nothing changes.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-18 between 12:37 and 12:55 AM CT; db/checks/0455) ══════════════════════════════
--
--   twin.ottoq_opportunistic_scan (prosrc md5 fce0e060) never names a feed mode. Its verdict loop, headed "TWIN: the
--   simulated tech verdict", takes every pending opportunistic_charge and tech_greenlight question at the run's depot
--   whose decide_after has passed and whose expires_at has not, and decides it by
--   ottoq_sim_seeded_random(seed, 'techdecide:...') < 0.70 or 0.92 unless a person recorded a verdict through
--   public.ottoq_ops_approval_decide (0487). An approved top-off is enacted: the car is moved to staged_awaiting_service,
--   ottoq.ottoq_enact_opportunistic_charge runs and the charger is claimed, decided_by 'twin_tech_sim', (1).
--   twin.ottoq_world_advance, the production_live tick, calls the scan outside every one of its feed-mode blocks, between
--   the visit atoms and the flow contract; public.ottoq_sim_advance_tick_world does the same, (2). The questions it
--   selects: ottoq.ottoq_plan_opportunistic_charges, which the scan itself calls first on every tick in both modes, raises
--   each top-off question with a decide_after 2-4 minutes on and an expires_at 35 minutes on, so the draw would answer
--   every top-off question in production. Green-lights: twin.ottoq_sim_advance_visit_atoms raises them only in its
--   sim-only completion branch, and ottoq.ottoq_stage_advance_approval raises them pending (only when
--   tech_approvals_required is set) with neither time, which the draw's filter never selects, (3). Production is not
--   live: no cron job calls twin.ottoq_world_advance, no production_live run is running (the nine on record are
--   completed, eight of them at the twin depot in sim mode), the only depots in external mode are a one-stall hardware
--   lab and the retired P2 fixture, and no top-off or green-light question has been raised at either, (4). The cutover
--   receipt of 2026-07-23 lists what external mode switches off; the simulated technician is not on it.
--
-- ══ §2 WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   twin.ottoq_opportunistic_scan, three anchored insertions: it reads its depot's feed mode once, as
--   twin.ottoq_sim_advance_visit_atoms does (a depot with none is the twin's), and at a depot the twin does not feed a
--   question with no verdict a person recorded is passed over: no draw, no enactment, and it stays pending. A verdict
--   recorded through public.ottoq_ops_approval_decide is applied as before, on the same path, so a top-off a person
--   approved is enacted exactly as today and decided_by names them. The expiry sweep is unchanged, so a question nobody
--   answers expires at its expires_at and no car waits on it forever. At a depot the twin feeds, the twin depot among
--   them, the scan does what it did.
--   Not changed: who asks, when, and what an approved top-off does; twin.ottoq_world_advance (its call stays where it
--   is); and ottoq.ottoq_plan_opportunistic_charges' seeded 2-4 minute decide_after, which in production only delays when
--   a person's verdict is applied (noted in G465, not changed here).
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the scan is the body read (prosrc md5 fce0e060) and the crew's door records its verdict as
--   it did when read (5edd194c); the twin depot is fed by the twin. P2 not already applied. Pre-image to
--   ottoq_schema_snapshots as '0751_pre'. Each anchor matches once. V1 the body less its insertions is its pre-image.
--   V2 on live, in a block rolled back by its own raise, at the twin depot on a completed run and a clock in 2031: with
--   the depot fed by the twin a green-light question nobody answered is decided by the draw (decided_by twin_tech_sim);
--   with the depot switched to external inside the block, the same kind of question stays pending, and one a person
--   declined is declined in their name; nothing is left behind.
--   tests/test_production_technician_sql.py executes the patched scan on the scratch PostgreSQL against its live body
--   (md5 asserted) and the twin's live seeded draw, with the planner and the enactment recorded by stand-ins.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE and forces_dial_restart FALSE. At a depot the twin feeds the two new statements are a read of one
--   depot row and a CONTINUE whose condition is false, so the scan decides and writes exactly what it did (V1: its body
--   less the insertions is its pre-image), and every certification arm, canon cell and dial experiment runs at the twin
--   depot, which the twin feeds (P1). No dial: whether a simulated technician may decide for a real depot is not a
--   setting.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0751_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0751_in_production_only_a_person_answers_a_technician_question'.

BEGIN;

SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0751 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the bodies read, the twin depot fed by the twin ──
DO $premises$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = to_regprocedure('twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'))
     IS DISTINCT FROM 'fce0e0609ef96ad49de836f95620b1f1' THEN
    RAISE EXCEPTION '0751 P1: twin.ottoq_opportunistic_scan is not the body read (md5 fce0e060)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.ottoq_ops_approval_decide(uuid,text,text)'))
     IS DISTINCT FROM '5edd194cfd677366964cdd174b9df243' THEN
    RAISE EXCEPTION '0751 P1: public.ottoq_ops_approval_decide is not the body read (md5 5edd194c)';
  END IF;
  IF (SELECT d.feed_mode FROM public.depots d WHERE d.id = '11111111-1111-1111-1111-111111111111')
     IS DISTINCT FROM 'sim' THEN
    RAISE EXCEPTION '0751 P1: the twin depot is not fed by the twin';
  END IF;
END $premises$;

-- ── P2: not already applied ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0751_in_production_only_a_person_answers_a_technician_question') THEN
    RAISE EXCEPTION '0751 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0751_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'::regprocedure;

-- ── the scan: only a depot the twin feeds has a simulated technician ──
CREATE TEMP TABLE _0751_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0751_patch VALUES
  -- 1: the scan's feed mode
  (1, $o1$  v_rec RECORD; v_n int := 0;
$o1$,
   $n1$  v_rec RECORD; v_n int := 0;
  v_feed_sim boolean := true;   -- 0751 (G465)
$n1$),
  -- 2: read once, as the visit atoms read it
  (2, $o2$  IF v_depot IS NULL THEN RETURN 0; END IF;
$o2$,
   $n2$  IF v_depot IS NULL THEN RETURN 0; END IF;
  -- 0751 (G465): only a depot the twin feeds has a simulated technician. A depot with no feed mode is the twin's.
  SELECT COALESCE(d.feed_mode, 'sim') = 'sim' INTO v_feed_sim FROM public.depots d WHERE d.id = v_depot;
  v_feed_sim := COALESCE(v_feed_sim, true);
$n2$),
  -- 3: at a depot a real feed drives, only a person's verdict answers
  (3, $o3$    v_p := (CASE WHEN v_rec.approval_type = 'tech_greenlight' THEN v_gl_p ELSE v_appr_p END);
$o3$,
   $n3$    v_p := (CASE WHEN v_rec.approval_type = 'tech_greenlight' THEN v_gl_p ELSE v_appr_p END);
    -- 0751 (G465): at a depot a real feed drives, nobody simulated answers. A verdict a person recorded (0487) is
    -- applied below as before; a question nobody has answered stays pending until someone does, or it expires.
    CONTINUE WHEN NOT v_feed_sim AND v_rec.op_verdict IS NULL;
$n3$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'::regprocedure);
  FOR p IN SELECT * FROM _0751_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0751: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  EXECUTE v_def;
  IF pg_get_functiondef('twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0751: the scan is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the patched body less its insertions is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'twin.ottoq_opportunistic_scan(uuid,timestamp with time zone)'::regprocedure;
  FOR p IN SELECT * FROM _0751_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM 'fce0e0609ef96ad49de836f95620b1f1' THEN
    RAISE EXCEPTION '0751 V1: the scan less its insertions is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: on live, rolled back by its own raise ──
DO $v2$
DECLARE
  v_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_t constant timestamptz := '2031-01-01 12:00:00+00';
  v_run uuid; v_car uuid; v_a uuid; v_b uuid; v_c uuid; r record;
BEGIN
  SELECT x.sim_run_id INTO v_run FROM public.ottoq_sim_runs x
   WHERE x.depot_id = v_depot AND x.status = 'completed' ORDER BY x.started_at DESC LIMIT 1;
  SELECT v.id INTO v_car FROM public.vehicles v WHERE v.home_depot_id = v_depot ORDER BY v.id LIMIT 1;
  IF v_run IS NULL OR v_car IS NULL THEN
    RAISE EXCEPTION '0751 V2: no completed run or car at the twin depot to probe with';
  END IF;
  BEGIN
    -- fed by the twin: the simulated technician answers
    INSERT INTO public.ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload, requested_at,
                                           decide_after, expires_at)
    VALUES ('tech_greenlight', v_car, v_run, v_depot, '{"probe": "0751 V2, rolled back"}'::jsonb,
            v_t - interval '10 minutes', v_t - interval '1 minute', v_t + interval '60 minutes')
    RETURNING approval_id INTO v_a;
    PERFORM twin.ottoq_opportunistic_scan(v_run, v_t);
    SELECT a.status, a.decided_by INTO r FROM public.ottoq_ops_approvals a WHERE a.approval_id = v_a;
    IF r.status NOT IN ('approved', 'declined') OR r.decided_by IS DISTINCT FROM 'twin_tech_sim' THEN
      RAISE EXCEPTION '0751 V2: at the twin-fed depot the simulated technician did not answer (%)', row_to_json(r);
    END IF;

    -- a real feed: nobody simulated answers, a person's verdict does
    UPDATE public.depots SET feed_mode = 'external' WHERE id = v_depot;
    INSERT INTO public.ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload, requested_at,
                                           decide_after, expires_at)
    VALUES ('tech_greenlight', v_car, v_run, v_depot, '{"probe": "0751 V2, rolled back"}'::jsonb,
            v_t - interval '10 minutes', v_t - interval '1 minute', v_t + interval '60 minutes')
    RETURNING approval_id INTO v_b;
    INSERT INTO public.ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload, requested_at,
                                           decide_after, expires_at)
    VALUES ('tech_greenlight', v_car, v_run, v_depot,
            '{"probe": "0751 V2, rolled back", "operator_verdict": {"verdict": "declined", "by": "pulse"}}'::jsonb,
            v_t - interval '9 minutes', v_t - interval '1 minute', v_t + interval '60 minutes')
    RETURNING approval_id INTO v_c;
    PERFORM twin.ottoq_opportunistic_scan(v_run, v_t);
    SELECT a.status, a.decided_by, a.decided_at INTO r FROM public.ottoq_ops_approvals a WHERE a.approval_id = v_b;
    IF r.status <> 'pending' OR r.decided_by IS NOT NULL OR r.decided_at IS NOT NULL THEN
      RAISE EXCEPTION '0751 V2: at an externally fed depot an unanswered question was decided (%)', row_to_json(r);
    END IF;
    SELECT a.status, a.decided_by INTO r FROM public.ottoq_ops_approvals a WHERE a.approval_id = v_c;
    IF r.status <> 'declined' OR r.decided_by IS DISTINCT FROM 'operator:pulse' THEN
      RAISE EXCEPTION '0751 V2: at an externally fed depot a person''s verdict was not applied (%)', row_to_json(r);
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'OT751', MESSAGE = 'probe passed';
  EXCEPTION WHEN SQLSTATE 'OT751' THEN
    NULL;
  END;
  IF (SELECT d.feed_mode FROM public.depots d WHERE d.id = v_depot) IS DISTINCT FROM 'sim'
     OR EXISTS (SELECT 1 FROM public.ottoq_ops_approvals WHERE approval_id IN (v_a, v_b, v_c)) THEN
    RAISE EXCEPTION '0751 V2: the probe left something behind';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0751_in_production_only_a_person_answers_a_technician_question', false, false,
        'G465. twin.ottoq_opportunistic_scan, three anchored insertions: it reads its depot''s feed mode once, and at a '
        'depot the twin does not feed a top-off or green-light question with no verdict a person recorded is passed over, '
        'so the simulated technician never draws for a real depot; a recorded verdict is applied as before, and the '
        'expiry sweep is unchanged. At a twin-fed depot the new statements read one row and continue on a false '
        'condition (V1: body less insertions is its pre-image), and every certification arm, canon cell and dial '
        'experiment runs at the twin depot, which the twin feeds (P1).',
        now());

COMMIT;

-- ══ APPLIED 2026-10-18 11:21:54 UTC (6:21 AM CT), ledger version 20261018112154 ══════════════════════════════════════
--
--   Dry-run first on live, read at 11:21:22 UTC (6:21 AM CT): the executable part in one execute_sql ending in a block
--   that raises, so it rolled back. Every premise and check passed, V2's switch of the twin depot to an external feed
--   included (rolled back with it), and the scan after it read 5c991974d364622df215e75c66c6078c. Then through
--   apply_migration with nothing in flight (the file's own P0 at the apply; no run live, read after). The text sent,
--   BEGIN through COMMIT and one newline, is 9,048 characters, md5 de25b9d22f398cfd788e5dca13fe9777, equal to the
--   ledger's statements[1] read back; its executable part is 9,032 characters, md5 e6985bafaae5ea1103acdd08b25e7924,
--   equal to this file's. twin.ottoq_opportunistic_scan is now md5 5c991974d364622df215e75c66c6078c (prosrc) and carries
--   'CONTINUE WHEN NOT v_feed_sim AND v_rec.op_verdict IS NULL'; the twin depot still reads feed_mode 'sim'.
