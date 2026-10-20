-- migration-version: 20261018113339
-- migration-name:    a_proposal_ages_on_the_clock_it_was_stamped_in
--
-- 0756  **A proposal ages on the clock it was stamped in.** (G473)
--       A proposal's created_at is its transaction's start (the column defaults to now()), and its two readers keep it
--       while GREATEST(expires_at, created_at + 35 minutes) >= now(). The disposer applied the same test to the machine's
--       clock, clock_timestamp(): one TTL, two clocks. In a transaction that runs a whole sweep arm or dial pair, now() is
--       the start, so a proposal stayed fresh to its readers until the transaction was 35 minutes old, and from then on the
--       disposer expired each in the tick it was made: an arm's decisions followed how fast the database ran it. A
--       correction to the research wing's instrument that restores 0122; it changes no arm that ends inside 35 minutes.
--
-- ══ §1 WHY, MEASURED (read-only, 2026-10-18 between 3:36 and 3:50 AM CT; db/checks/0451 §19, queries (40) and (41)) ═══
--
--   0122 (2026-08-30, "the sweep reads the clock the stamp was written in") found the decide's expiry sweep judging the
--   wall-stamped TTL by the SIM clock, which expired every proposal on its birth tick, and moved it to now(): "within a
--   determinism pair (one transaction) now() is frozen, so proposals no longer expire mid-pair". 0333 (2026-09-16) moved
--   that sweep into public.ottoq_dispose_external_proposals, as "expired in the selector's real-time TTL domain", and
--   wrote its three TTL tests against v_wall := clock_timestamp(), the clock it declared for its new disposed_at audit
--   stamp. Of the 86 sweep arms whose proposals survive, the 33 that ended inside 35 minutes of their first stamp expired
--   none of 1,129, and 42 of the 53 that ran past expired 1,527 of 3,645, none before the 35th minute. On the two
--   observer pairs (promise_normal's arm 96 against arm 93, promise_busy's arm 97 against arm 82) the expiries moved h_dec
--   and h_prop and no outcome atom. ottoq_dial_pair runs the control and then the treatment in one transaction, and the
--   second arm is the slow one, so in all 8 dial pairs since 2026-10-09 the treatment alone expired proposals (3-18
--   each); on pair 138, whose dial moved nothing, the only atoms that moved are h_dec and h_prop.
--
-- ══ §2 WHAT THIS CHANGES ═════════════════════════════════════════════════════════════════════════════════════════════
--
--   The disposer's three TTL tests (the status, the reason and the WHERE) read v_ttl_now := now(), the clock created_at is
--   stamped in and the readers read; disposed_at keeps v_wall, the machine's clock, as 0333's audit stamp. In one
--   transaction a proposal now lives until a newer one for its car, or a decision on its car, supersedes it, or its run is
--   finalized, which is what every arm that ended inside 35 minutes already did. A sweep arm or dial pair no longer
--   depends on the machine's speed, and a dial pair's two arms age their proposals alike. In production each tick is its
--   own transaction and now() is the tick's start: a proposal whose 35 minutes end while a tick is running, before its
--   disposer call, now expires one tick later, and nothing else moves.
--   Not changed: in a long transaction a proposal still never goes stale (G473's other face, 0122's choice). Ageing it on
--   its run's own clock, the sim clock in the twin and the real one in production, changes every arm's decisions and is a
--   certified change behind a dial. The stall_assignment refusals read the run's clock (v_clock) as before.
--
-- ══ §3 CHECKS ═════════════════════════════════════════════════════════════════════════════════════════════════════════
--
--   P0 nothing in flight. P1 the disposer is the body read (prosrc 13b31d98), with its v_wall declaration and each of its
--   three TTL tests once; both readers are the bodies read (ottoq_l2_external_proposal 97764998, ottoq_cuopt_defer_hold
--   f6146663), each tests the TTL against now() and reads no clock_timestamp(); created_at defaults to now(). P2 not
--   already applied. Pre-image to ottoq_schema_snapshots as '0756_pre'. Each anchor matches once. V1 the body less its
--   changes is its pre-image. V2 on live, inside a block rolled back by its own raise: a probe run row (a completed run's
--   scenario, status 'completed') and four proposals: one whose 35 minutes end after the transaction began and before the
--   machine's clock stays pending (the body before 0756 expired it), one 36 minutes old is expired as 'ttl_elapsed' with
--   disposed_at on the machine's clock, one stamped now stays pending, and a stall proposal naming no stall is refused as
--   'invalid_stall_id' as before; the reader keeps the first and the third and not the second; the probe leaves nothing
--   behind, in the proposals or in their disposition ledger. tests/test_proposal_ttl_stamp_clock_sql.py runs this file on
--   the scratch PostgreSQL against the live bodies (md5 asserted): the same proposals before and after it, the reader
--   beside the disposer across the 35th minute, the finalizer, V1, P1 and P2.
--
-- ══ §4 RECERT AND DIAL CLASSIFICATION ═════════════════════════════════════════════════════════════════════════════════
--
--   forces_recert FALSE: a certification pair runs both arms in one transaction, the recert runner's longest run in the
--   14 days to 2026-10-18 was 13.3 minutes (cron job 746), and this acts only past a transaction's 35th minute; no
--   verdict in the ledger has disagreed on proposals or decisions alone. forces_dial_restart FALSE: past the 35th minute
--   an arm's decisions and proposals were never reproducible (they followed the machine's speed), and on the three pairs
--   measured the expiries this removes moved h_dec and h_prop and no outcome, which is what the dial floor protects. A
--   restart would not repair the 8 one-sided dial pairs either (G473 and db/checks/0451 query (41) name them for whoever
--   reads their experiments), and it would re-queue every sweep cell on record, the 33 arms that never reached the 35th
--   minute among them. No dial: which clock a TTL is read on is not a setting.
--
-- ROLLBACK: EXECUTE the `definition` in ottoq_schema_snapshots WHERE label = '0756_pre';
--   DELETE FROM public.ottoq_cert_lineage WHERE name = '0756_a_proposal_ages_on_the_clock_it_was_stamped_in'.

BEGIN;
SET LOCAL lock_timeout = '5s';

-- ── P0: nothing in flight ──
DO $inflight$
BEGIN
  IF public.ottoq_certification_in_flight(true) > 0 THEN
    RAISE EXCEPTION '0756 P0: a pair, the recert runner, a dial pair or a sweep is running right now';
  END IF;
END $inflight$;

-- ── P1: the disposer, its two readers and the stamp, as read ──
DO $p1$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc
       WHERE oid = 'public.ottoq_dispose_external_proposals(uuid,bigint,timestamp with time zone,boolean)'::regprocedure)
     IS DISTINCT FROM '13b31d984569d7d1336a3a99aa76fef7' THEN
    RAISE EXCEPTION '0756 P1: public.ottoq_dispose_external_proposals is not the body read (md5 13b31d98)';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_l2_external_proposal(uuid,text,text,uuid)'::regprocedure)
       IS DISTINCT FROM '97764998a612044544d7e0f40c365bf4'
     OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_cuopt_defer_hold(uuid,uuid,bigint)'::regprocedure)
       IS DISTINCT FROM 'f6146663badc26c219a575a5719ba61f' THEN
    RAISE EXCEPTION '0756 P1: a reader is not the body read (ottoq_l2_external_proposal 97764998, ottoq_cuopt_defer_hold f6146663)';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc
              WHERE oid IN ('public.ottoq_l2_external_proposal(uuid,text,text,uuid)'::regprocedure,
                            'public.ottoq_cuopt_defer_hold(uuid,uuid,bigint)'::regprocedure)
                AND (position('clock_timestamp' IN prosrc) > 0
                     OR prosrc !~ 'p\.created_at \+ interval ''35 minutes''\) >= now\(\)')) THEN
    RAISE EXCEPTION '0756 P1: a reader does not test the TTL against now()';
  END IF;
  IF (SELECT pg_get_expr(d.adbin, d.adrelid)
        FROM pg_attrdef d JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
       WHERE d.adrelid = 'public.ottoq_external_proposals'::regclass AND a.attname = 'created_at')
     IS DISTINCT FROM 'now()' THEN
    RAISE EXCEPTION '0756 P1: ottoq_external_proposals.created_at does not default to now()';
  END IF;
END $p1$;

-- ── P2: once ──
DO $once$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage
              WHERE name = '0756_a_proposal_ages_on_the_clock_it_was_stamped_in') THEN
    RAISE EXCEPTION '0756 P2: already applied';
  END IF;
END $once$;

-- ── the pre-image ──
INSERT INTO public.ottoq_schema_snapshots (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0756_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_dispose_external_proposals(uuid,bigint,timestamp with time zone,boolean)'::regprocedure;

-- ── the disposer: its TTL on the clock the stamp was written in ──
CREATE TEMP TABLE _0756_patch (seq int, c_old text, c_new text) ON COMMIT DROP;
INSERT INTO _0756_patch VALUES
  -- 1: the TTL's clock, beside the audit stamp's
  (1, $o1$  v_wall  timestamptz := clock_timestamp();
$o1$,
   $n1$  v_wall  timestamptz := clock_timestamp();
  -- 0756 (G473): the TTL is read on the clock created_at is stamped in, now(), as 0122 wrote it and as
  -- ottoq_l2_external_proposal and ottoq_cuopt_defer_hold read it; v_wall stays disposed_at's audit stamp (0333). Read
  -- on the machine's clock, a sweep arm or a dial pair, one transaction, expired every new proposal once it was 35
  -- minutes old, so its decisions followed the machine's speed.
  v_ttl_now timestamptz := now();
$n1$),
  -- 2: the status
  (2, $o2$p.created_at + interval '35 minutes') < v_wall THEN 'expired'$o2$,
      $n2$p.created_at + interval '35 minutes') < v_ttl_now THEN 'expired'$n2$),
  -- 3: the reason
  (3, $o3$p.created_at + interval '35 minutes') < v_wall THEN 'ttl_elapsed'$o3$,
      $n3$p.created_at + interval '35 minutes') < v_ttl_now THEN 'ttl_elapsed'$n3$),
  -- 4: which pending rows are disposed
  (4, $o4$p.created_at + interval '35 minutes') < v_wall
       OR ($o4$,
      $n4$p.created_at + interval '35 minutes') < v_ttl_now
       OR ($n4$);

DO $patch$
DECLARE p record; v_def text; n int;
BEGIN
  v_def := pg_get_functiondef('public.ottoq_dispose_external_proposals(uuid,bigint,timestamp with time zone,boolean)'::regprocedure);
  FOR p IN SELECT * FROM _0756_patch ORDER BY seq LOOP
    n := (length(v_def) - length(replace(v_def, p.c_old, ''))) / length(p.c_old);
    IF n <> 1 THEN
      RAISE EXCEPTION '0756: anchor % matches % times, not 1', p.seq, n;
    END IF;
    v_def := replace(v_def, p.c_old, p.c_new);
  END LOOP;
  IF position('< v_wall' IN v_def) > 0 THEN
    RAISE EXCEPTION '0756: a TTL test still reads the machine''s clock';
  END IF;
  EXECUTE v_def;
  IF pg_get_functiondef('public.ottoq_dispose_external_proposals(uuid,bigint,timestamp with time zone,boolean)'::regprocedure)
     IS DISTINCT FROM v_def THEN
    RAISE EXCEPTION '0756: the disposer is not stored as patched';
  END IF;
END $patch$;

-- ── V1: the patched body less its changes is its pre-image ──
DO $v1$
DECLARE v_body text; p record;
BEGIN
  SELECT prosrc INTO v_body FROM pg_proc
   WHERE oid = 'public.ottoq_dispose_external_proposals(uuid,bigint,timestamp with time zone,boolean)'::regprocedure;
  FOR p IN SELECT * FROM _0756_patch ORDER BY seq DESC LOOP
    v_body := replace(v_body, p.c_new, p.c_old);
  END LOOP;
  IF md5(v_body) IS DISTINCT FROM '13b31d984569d7d1336a3a99aa76fef7' THEN
    RAISE EXCEPTION '0756 V1: the disposer less its changes is not its pre-image (md5 %)', md5(v_body);
  END IF;
END $v1$;

-- ── V2: on live, rolled back by its own raise ──
DO $v2$
DECLARE
  v_depot constant uuid := '11111111-1111-1111-1111-111111111111';
  v_src uuid; v_run uuid := gen_random_uuid();
  v_car_a uuid := gen_random_uuid(); v_car_b uuid := gen_random_uuid(); v_car_c uuid := gen_random_uuid();
  v_car_d uuid := gen_random_uuid();
  v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_mid timestamptz; r record;
BEGIN
  SELECT x.sim_run_id INTO v_src FROM public.ottoq_sim_runs x
   WHERE x.depot_id = v_depot AND x.status = 'completed' ORDER BY x.started_at DESC LIMIT 1;
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0756 V2: no completed run at the twin depot to copy a scenario from';
  END IF;
  BEGIN
    INSERT INTO public.ottoq_sim_runs (sim_run_id, scenario_id, scenario_code, depot_id, status, started_at,
                                       sim_clock_start, sim_clock_current, sim_clock_end, random_seed, run_by, policy)
    SELECT v_run, x.scenario_id, x.scenario_code, v_depot, 'completed', now(),
           '2031-01-01 12:00:00+00', '2031-01-01 12:00:00+00', '2031-01-02 12:00:00+00', 42, '0756_v2_probe', 'otto_q'
      FROM public.ottoq_sim_runs x WHERE x.sim_run_id = v_src;
    PERFORM pg_sleep(0.05);
    -- after the transaction began and before the machine's clock: where the two clocks disagree
    v_mid := now() + (clock_timestamp() - now()) / 2;
    INSERT INTO public.ottoq_external_proposals (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal,
                                                 source, status, created_at, expires_at, tick_seq)
    VALUES (v_run, v_depot, 'service_sequencing', 'vehicle', v_car_a, '{"verb": "admit_service"}', '0756_probe', 'pending',
            v_mid - interval '35 minutes', v_mid - interval '33 minutes', 1)
    RETURNING proposal_id INTO v_a;
    INSERT INTO public.ottoq_external_proposals (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal,
                                                 source, status, created_at, expires_at, tick_seq)
    VALUES (v_run, v_depot, 'service_sequencing', 'vehicle', v_car_b, '{"verb": "admit_service"}', '0756_probe', 'pending',
            now() - interval '36 minutes', now() - interval '34 minutes', 1)
    RETURNING proposal_id INTO v_b;
    INSERT INTO public.ottoq_external_proposals (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal,
                                                 source, status, expires_at, tick_seq)
    VALUES (v_run, v_depot, 'service_sequencing', 'vehicle', v_car_c, '{"verb": "admit_service"}', '0756_probe', 'pending',
            now() + interval '2 minutes', 1)
    RETURNING proposal_id INTO v_c;
    INSERT INTO public.ottoq_external_proposals (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal,
                                                 source, status, expires_at, tick_seq)
    VALUES (v_run, v_depot, 'stall_assignment', 'vehicle', v_car_d, '{"stall_id": "not-a-stall"}', '0756_probe', 'pending',
            now() + interval '2 minutes', 1)
    RETURNING proposal_id INTO v_d;

    PERFORM public.ottoq_dispose_external_proposals(v_run, 1, NULL, false);

    SELECT status, disposition_reason INTO r FROM public.ottoq_external_proposals WHERE proposal_id = v_a;
    IF r.status IS DISTINCT FROM 'pending' THEN
      RAISE EXCEPTION '0756 V2: a proposal whose 35 minutes end between the transaction''s start and the machine''s clock was %/%',
        r.status, r.disposition_reason;
    END IF;
    SELECT status, disposition_reason, disposed_at INTO r FROM public.ottoq_external_proposals WHERE proposal_id = v_b;
    IF r.status IS DISTINCT FROM 'expired' OR r.disposition_reason IS DISTINCT FROM 'ttl_elapsed' THEN
      RAISE EXCEPTION '0756 V2: a proposal 36 minutes old was %/%', r.status, r.disposition_reason;
    END IF;
    IF r.disposed_at <= now() THEN
      RAISE EXCEPTION '0756 V2: disposed_at is not the machine''s clock (%)', r.disposed_at;
    END IF;
    IF (SELECT status FROM public.ottoq_external_proposals WHERE proposal_id = v_c) IS DISTINCT FROM 'pending' THEN
      RAISE EXCEPTION '0756 V2: a proposal stamped now was disposed';
    END IF;
    SELECT status, disposition_reason INTO r FROM public.ottoq_external_proposals WHERE proposal_id = v_d;
    IF r.status IS DISTINCT FROM 'refused' OR r.disposition_reason IS DISTINCT FROM 'invalid_stall_id' THEN
      RAISE EXCEPTION '0756 V2: a stall proposal naming no stall was %/%', r.status, r.disposition_reason;
    END IF;
    IF public.ottoq_l2_external_proposal(v_run, 'service_sequencing', 'vehicle', v_car_a) IS NULL
       OR public.ottoq_l2_external_proposal(v_run, 'service_sequencing', 'vehicle', v_car_c) IS NULL
       OR public.ottoq_l2_external_proposal(v_run, 'service_sequencing', 'vehicle', v_car_b) IS NOT NULL THEN
      RAISE EXCEPTION '0756 V2: the reader and the disposer disagree on which proposals are fresh';
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'OT756', MESSAGE = 'probe passed';
  EXCEPTION WHEN SQLSTATE 'OT756' THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = v_run)
     OR EXISTS (SELECT 1 FROM public.ottoq_external_proposals WHERE sim_run_id = v_run OR source = '0756_probe')
     OR EXISTS (SELECT 1 FROM public.ottoq_proposal_disposition_ledger WHERE sim_run_id = v_run) THEN
    RAISE EXCEPTION '0756 V2: the probe left something behind';
  END IF;
END $v2$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
VALUES ('0756_a_proposal_ages_on_the_clock_it_was_stamped_in', false, false,
        'G473. public.ottoq_dispose_external_proposals, four anchored changes: its three TTL tests read now(), the clock '
        'created_at is stamped in and its two readers read, as 0122 wrote them; disposed_at keeps clock_timestamp() as '
        '0333''s audit stamp (V1: body less changes is its pre-image). Acts only past a transaction''s 35th minute: no '
        'certification pair reaches it (the recert runner''s longest run in 14 days was 13.3 minutes), and past it an '
        'arm''s decisions followed the machine''s speed; on the three pairs measured (db/checks/0451 §19) the expiries it '
        'removes moved h_dec and h_prop and no outcome. In production an expiry moves by at most one tick. No dial.',
        now());

COMMIT;

-- ══ APPLIED 2026-10-18 11:33:39 UTC (6:33 AM CT), ledger version 20261018113339 ══════════════════════════════════════
--
--   Dry-run first on live, read at 11:32:57 UTC (6:32 AM CT): the executable part in one execute_sql ending in a block
--   that raises, so it rolled back. Every premise and check passed, V2's probe run and its four proposals included, and
--   the disposer after it read 196b3a19a1453bc89c0cf0e1d61b2243, carrying 'v_ttl_now timestamptz := now();' and no '<
--   v_wall'. Then through apply_migration with nothing in flight (the file's own P0 at the apply; no run live, read
--   after). The dry run and the apply both sent the file's text less the blank line after BEGIN, which the copy dropped;
--   this file was then changed to hold exactly what the ledger holds, by removing that one blank line, so it reads as
--   applied (before, its executable part was 11,912 characters, md5 294dbb7c). The text sent, BEGIN through COMMIT and
--   one newline, is 11,927 characters, md5 8a7ed7774148c4df70a7f83cb1ed55c3, equal to the ledger's statements[1] read
--   back; its executable part is 11,911 characters, md5 0bb93a4ad17984d82dd3edae501e9275, equal to this file's now.
--   public.ottoq_dispose_external_proposals is now md5 196b3a19a1453bc89c0cf0e1d61b2243 (prosrc), carries 'v_ttl_now
--   timestamptz := now();' and no '< v_wall'.
