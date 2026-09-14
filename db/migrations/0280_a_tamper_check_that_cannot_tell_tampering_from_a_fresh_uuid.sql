-- migration-version: PENDING
-- migration-name:    0280_a_tamper_check_that_cannot_tell_tampering_from_a_fresh_uuid
--
-- 0280  A TAMPER CHECK THAT CANNOT TELL TAMPERING FROM A FRESH UUID
--
-- ---------------------------------------------------------------------------
-- THE MEASUREMENT  (db/checks/0216)
--
-- CLAUDE.md rule 6 names ottoq_decision_snapshots "the content-hashed
-- anti-cheat substrate". Measured 2026-09-14 against the live engine:
--
--   pair  seed 171717 / busy_day / 48 ticks / run_by cert_harness
--         BOTH arms validation_status = 'passed'
--         arm A 665b6437-cb1d-4819-bb03-878e97d6aed7
--         arm B 45132bcf-aa31-41da-92f2-c38932e4de36
--
--   ticks compared  48        identical  4        DIFFERING  44
--
-- and the cause is proven rather than argued, by a clean separation: the four
-- agreeing ticks are EXACTLY the ticks with zero active charging sessions and
-- the forty-four differing ticks are EXACTLY those with at least one. 4 of 4
-- and 44 of 44, no exceptions either way.
--
-- ottoq_capture_decision_snapshot hashes the WHOLE frame --
--
--   v_hash := encode(digest(jsonb_pretty(v_frame), 'sha256'), 'hex');
--
-- -- the frame's `sessions` block is built with 'id', cs.id ... ORDER BY cs.id,
-- and ocpp_sessions.id has column_default uuid_generate_v4(). A freshly minted
-- random uuid, in the digest AND in the sort key. The comment one line above
-- that digest call reads "deterministic content hash over the canonical
-- (key-sorted) frame text".
--
-- This is the third time: 0137 (the world fingerprint hashed a write
-- timestamp) and 0139 (the end-state fingerprint made id-blind) are the same
-- defect class.
--
-- ---------------------------------------------------------------------------
-- THE COUPLING THAT MAKES THIS NOT A ONE-LINE FIX
--
-- public.ottoq_assert_snapshot_integrity RE-COMPUTES the identical expression
-- and raises OTTOQ_SNAPSHOT_TAMPERED when it disagrees with the stored value:
--
--   v_recomputed := encode(digest(jsonb_pretty(v_row.frame), 'sha256'), 'hex');
--   IF v_recomputed <> v_row.content_hash THEN RAISE EXCEPTION ...
--
-- So the writer and the verifier are one algorithm in two places. Change the
-- writer alone and EVERY NEW SNAPSHOT READS AS TAMPERED. Change both without
-- versioning and every one of the existing rows does instead, because they were
-- written under the old algorithm and cannot be re-derived under the new one.
--
-- Hence the column. hash_algo is NULL on every pre-existing row -- meaning "the
-- raw-frame algorithm this row was actually written with" -- and 2 on
-- everything written from here. The verifier switches on it, so both
-- generations verify against the algorithm that produced them and neither is
-- weakened. No backfill, no rewrite, no DROP.
--
-- ---------------------------------------------------------------------------
-- WHAT IS NORMALISED, AND WHAT IS DELIBERATELY NOT
--
-- ottoq_frame_hash_payload drops `id` from each session object and re-sorts the
-- array on (stall_id, vehicle_id, started_at) -- a triple that is unique by
-- physics: one vehicle, at one stall, from one instant.
--
-- NOTHING ELSE IS TOUCHED. The measurement convicts the session id and only the
-- session id, and widening a fix past its evidence is how a hash stops meaning
-- anything. If some other field also varies, the round below will show it as a
-- residual and it gets its own file with its own measurement.
--
-- THE STORED FRAME IS UNCHANGED. Only the digest INPUT is normalised; the
-- `frame` column keeps full fidelity, session ids included, because that column
-- is evidence. And ottoq_build_decision_frame is NOT modified, so no proposer,
-- no selector and no consumer sees a different frame -- which keeps the blast
-- radius off the decide path's behaviour entirely.
--
-- ---------------------------------------------------------------------------
-- WHAT APPLYING THIS PROVES, AND WHAT IT DOES NOT
--
-- An earlier draft of this header said the file must not be applied outside a
-- certification window. That conflated two different things and is corrected
-- here rather than left to mislead:
--
--   APPLYING is safe on its own, and the assertions below carry it. Nothing in
--   this engine compares content_hash across runs today -- which is precisely
--   why db/checks/0216 could find it broken while pairs kept passing -- so
--   changing how it is computed breaks no consumer. The one real coupling,
--   the verifier, moves in the same file, and A1 requires 200 existing rows to
--   go on verifying under the algorithm that actually wrote them.
--
--   WHAT IS NOT PROVEN by applying is the end-to-end claim: that two arms of a
--   certification pair now agree on 48 of 48 ticks instead of 4. That needs a
--   pair to actually run, which is a ROUND, not a migration step. Until that
--   round exists, the honest sentence is "the known cause of the divergence is
--   removed and the removal is proven in isolation", NOT "the substrate is
--   deterministic". Nobody may quote the second sentence on the strength of
--   this file.
--
-- So content_hash stays OUT of the fourteen atoms until a round says otherwise.
-- The blind-spot promotion doctrine (0139 / 0206 / 0217 / 0225) is explicit:
-- an atom is added MEASURED first and ENFORCED only after a flagship round
-- shows the arms agree. This file is the MEASURED half.
--
-- A3 below is the strongest proof available without a round, and it is a real
-- one: it constructs two frames differing only in session ids and requires the
-- OLD expression to disagree and the NEW one to agree. Two-sided, in one file.

-- ---------------------------------------------------------------------------
-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0280 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0280 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0280 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0280 P-: nothing in flight';
END $inflight$;

-- P1. THE TWO BODIES ARE THE ONES THIS WAS WRITTEN AGAINST --------------------
-- The md5 guard APPLYING.md calls the thing that stops a silent clobber of
-- somebody's hotfix. Both are pinned because both are replaced.
DO $p1$
DECLARE v_cap text; v_ass text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_cap
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_capture_decision_snapshot';
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_ass
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_assert_snapshot_integrity';
  IF v_cap IS DISTINCT FROM 'c264c40477e2613280d2909a4dfa849d' THEN
    RAISE EXCEPTION '0280 P1: ottoq_capture_decision_snapshot is %, pinned c264c404...', v_cap;
  END IF;
  IF v_ass IS DISTINCT FROM 'a9ca34babd2472d0382a82f143a36dd8' THEN
    RAISE EXCEPTION '0280 P1: ottoq_assert_snapshot_integrity is %, pinned a9ca34ba...', v_ass;
  END IF;
  RAISE NOTICE '0280 P1: both bodies match their pins';
END $p1$;

-- P2. THE DEFECT IS STILL THERE (two-sided: this file needs the broken world) --
-- Reads the very pair db/checks/0216 measured. If somebody already fixed this,
-- the file's header is stale and it must not be applied on top.
DO $p2$
DECLARE v_diff int; v_same int;
BEGIN
  SELECT count(*) FILTER (WHERE a.content_hash <> b.content_hash),
         count(*) FILTER (WHERE a.content_hash =  b.content_hash)
    INTO v_diff, v_same
    FROM public.ottoq_decision_snapshots a
    JOIN public.ottoq_decision_snapshots b USING (tick_seq)
   WHERE a.sim_run_id='665b6437-cb1d-4819-bb03-878e97d6aed7'
     AND b.sim_run_id='45132bcf-aa31-41da-92f2-c38932e4de36';
  IF v_diff <> 44 OR v_same <> 4 THEN
    RAISE EXCEPTION '0280 P2: the reference pair now reads % differing / % identical, '
                    '0216 measured 44 / 4. Re-measure before applying.', v_diff, v_same;
  END IF;
  RAISE NOTICE '0280 P2: reference pair still 44 differing / 4 identical';
END $p2$;

-- P3. THE COLUMN DOES NOT EXIST YET -------------------------------------------
DO $p3$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_decision_snapshots'
     AND column_name='hash_algo';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0280 P3: hash_algo already exists; this file has run before';
  END IF;
  RAISE NOTICE '0280 P3: hash_algo is absent, as expected';
END $p3$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0280_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_capture_decision_snapshot','ottoq_assert_snapshot_integrity',
                     'ottoq_frame_hash_payload');

-- ---------------------------------------------------------------------------
-- 1. THE COLUMN. NULL means "written under the raw-frame algorithm"; it is not
-- backfilled and must never be, because NULL is the true statement about those
-- rows and any value we invented for them would be a guess about history.
ALTER TABLE public.ottoq_decision_snapshots
  ADD COLUMN IF NOT EXISTS hash_algo smallint;

COMMENT ON COLUMN public.ottoq_decision_snapshots.hash_algo IS
'0280. Which algorithm produced content_hash for THIS row. NULL = the original '
'raw-frame digest, encode(digest(jsonb_pretty(frame),''sha256''),''hex''), which '
'is nondeterministic because the frame carries ocpp_sessions.id (a uuid_generate_v4 '
'default) both as a hashed value and as the sessions array''s sort key -- see '
'db/checks/0216. 2 = the id-blind payload from ottoq_frame_hash_payload. Never '
'backfill: NULL is the true statement about a row written before the fix.';

-- ---------------------------------------------------------------------------
-- 2. THE NORMALISED PAYLOAD. IMMUTABLE and pure, so the verifier and the writer
-- cannot drift: there is one definition of what gets hashed and both call it.
CREATE OR REPLACE FUNCTION public.ottoq_frame_hash_payload(p_frame jsonb)
RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $function$
  SELECT COALESCE(p_frame, '{}'::jsonb) || jsonb_build_object('sessions', COALESCE((
    SELECT jsonb_agg(t.obj ORDER BY t.obj->>'stall_id', t.obj->>'vehicle_id',
                                    t.obj->>'started_at')
      FROM (SELECT (e.value - 'id') AS obj
              FROM jsonb_array_elements(COALESCE(p_frame->'sessions', '[]'::jsonb)) AS e) t
  ), '[]'::jsonb));
$function$;

COMMENT ON FUNCTION public.ottoq_frame_hash_payload(jsonb) IS
'0280. The decision frame reduced to what is actually reproducible: the sessions '
'array with its minted `id` removed and re-sorted on (stall_id, vehicle_id, '
'started_at), a triple unique by physics. Everything else is passed through '
'untouched, deliberately -- db/checks/0216 convicts the session id and only the '
'session id, and widening a fix past its evidence is how a hash stops meaning '
'anything.';

-- ---------------------------------------------------------------------------
-- 3. THE WRITER.
CREATE OR REPLACE FUNCTION public.ottoq_capture_decision_snapshot(
  p_sim_run_id uuid, p_tick_seq bigint, p_depot_id uuid, p_sim_clock timestamptz)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE
  v_existing uuid;
  v_frame    jsonb;
  v_hash     text;
  v_counts   jsonb;
  v_id       uuid;
BEGIN
  SELECT snapshot_id INTO v_existing
    FROM ottoq_decision_snapshots WHERE sim_run_id = p_sim_run_id AND tick_seq = p_tick_seq;
  IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;

  v_frame := ottoq_build_decision_frame(p_depot_id, p_sim_run_id);
  -- 0280: hash the ID-BLIND payload, not the raw frame. The raw frame carries
  -- ocpp_sessions.id (uuid_generate_v4) in the digest AND in the sessions sort
  -- key, which made two arms of a PASSING certification pair disagree on 44 of
  -- 48 ticks (db/checks/0216). The stored `frame` is unchanged and keeps full
  -- fidelity; only what gets digested is normalised.
  v_hash := encode(digest(jsonb_pretty(public.ottoq_frame_hash_payload(v_frame)),
                          'sha256'), 'hex');
  v_counts := jsonb_build_object(
    'vehicles', jsonb_array_length(COALESCE(v_frame->'vehicles','[]'::jsonb)),
    'stalls',   jsonb_array_length(COALESCE(v_frame->'stalls','[]'::jsonb)),
    'sessions', jsonb_array_length(COALESCE(v_frame->'sessions','[]'::jsonb))
  );

  INSERT INTO ottoq_decision_snapshots (sim_run_id, tick_seq, depot_id, sim_clock,
                                        content_hash, frame, frame_counts, hash_algo)
  VALUES (p_sim_run_id, p_tick_seq, p_depot_id, p_sim_clock, v_hash, v_frame, v_counts, 2)
  ON CONFLICT (sim_run_id, tick_seq) DO NOTHING
  RETURNING snapshot_id INTO v_id;

  IF v_id IS NULL THEN
    SELECT snapshot_id INTO v_id FROM ottoq_decision_snapshots
     WHERE sim_run_id = p_sim_run_id AND tick_seq = p_tick_seq;
  END IF;
  RETURN v_id;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 4. THE VERIFIER, moved in lockstep and switching on the row's own algorithm.
-- A row written before this migration still verifies under the algorithm that
-- actually produced it; tamper detection is not weakened for either generation.
CREATE OR REPLACE FUNCTION public.ottoq_assert_snapshot_integrity(p_snapshot_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE
  v_row        ottoq_decision_snapshots%ROWTYPE;
  v_recomputed text;
BEGIN
  SELECT * INTO v_row FROM ottoq_decision_snapshots WHERE snapshot_id = p_snapshot_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'OTTOQ_SNAPSHOT_MISSING: %', p_snapshot_id USING ERRCODE = 'P0001';
  END IF;

  -- 0280: verify under the algorithm that WROTE this row. NULL is the original
  -- raw-frame digest and is left verifiable exactly as it was; 2 is the id-blind
  -- payload. An unknown value is refused rather than guessed -- a verifier that
  -- falls back on an unrecognised algorithm is not a verifier.
  IF v_row.hash_algo IS NULL THEN
    v_recomputed := encode(digest(jsonb_pretty(v_row.frame), 'sha256'), 'hex');
  ELSIF v_row.hash_algo = 2 THEN
    v_recomputed := encode(digest(jsonb_pretty(public.ottoq_frame_hash_payload(v_row.frame)),
                                  'sha256'), 'hex');
  ELSE
    RAISE EXCEPTION 'OTTOQ_SNAPSHOT_UNKNOWN_ALGO: snapshot % declares hash_algo %',
                    p_snapshot_id, v_row.hash_algo USING ERRCODE = 'P0001';
  END IF;

  IF v_recomputed <> v_row.content_hash THEN
    RAISE EXCEPTION 'OTTOQ_SNAPSHOT_TAMPERED: % expected % got %',
                    p_snapshot_id, v_row.content_hash, v_recomputed USING ERRCODE = 'P0001';
  END IF;
  RETURN TRUE;
END;
$function$;

-- ---------------------------------------------------------------------------
-- A1. EVERY PRE-EXISTING ROW STILL VERIFIES.
-- The failure this guards against is the one that matters most: a fix that
-- silently declares the entire history tampered. Sampled across runs rather
-- than taking the first N of one run.
DO $a1$
DECLARE v_id uuid; v_n int := 0;
BEGIN
  FOR v_id IN
    SELECT snapshot_id FROM public.ottoq_decision_snapshots
     WHERE hash_algo IS NULL ORDER BY captured_at DESC LIMIT 200
  LOOP
    PERFORM public.ottoq_assert_snapshot_integrity(v_id);
    v_n := v_n + 1;
  END LOOP;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'A1 INCONCLUSIVE: no legacy snapshot rows to verify against';
  END IF;
  RAISE NOTICE 'A1 OK: % legacy snapshots still verify under the raw-frame algorithm', v_n;
END $a1$;

-- A2. THE PAYLOAD ACTUALLY REMOVES THE ID AND REORDERS.
DO $a2$
DECLARE v_out jsonb;
BEGIN
  v_out := public.ottoq_frame_hash_payload(jsonb_build_object(
    'vehicles', '[]'::jsonb,
    'sessions', jsonb_build_array(
      jsonb_build_object('id','zzzzzzzz-0000-0000-0000-000000000001','stall_id','s2',
                         'vehicle_id','v2','started_at','2026-01-01T00:00:02Z'),
      jsonb_build_object('id','aaaaaaaa-0000-0000-0000-000000000002','stall_id','s1',
                         'vehicle_id','v1','started_at','2026-01-01T00:00:01Z'))));
  IF (v_out->'sessions'->0) ? 'id' OR (v_out->'sessions'->1) ? 'id' THEN
    RAISE EXCEPTION 'A2 FAILED: session id survived normalisation: %', v_out->'sessions';
  END IF;
  IF v_out->'sessions'->0->>'stall_id' <> 's1' THEN
    RAISE EXCEPTION 'A2 FAILED: sessions not re-sorted on stall_id; got %', v_out->'sessions';
  END IF;
  IF v_out->'vehicles' <> '[]'::jsonb THEN
    RAISE EXCEPTION 'A2 FAILED: a non-sessions key was altered';
  END IF;
  RAISE NOTICE 'A2 OK: id dropped, sessions re-sorted, everything else passed through';
END $a2$;

-- A3. THE HEADLINE, PROVEN BOTH WAYS IN ONE BLOCK.
-- Two frames identical but for their session uuids: the OLD expression must
-- DISAGREE (that is the bug, reproduced) and the NEW one must AGREE (that is
-- the fix, demonstrated). Either half failing means this file is wrong.
DO $a3$
DECLARE v_f1 jsonb; v_f2 jsonb; v_old1 text; v_old2 text; v_new1 text; v_new2 text;
BEGIN
  v_f1 := jsonb_build_object('stalls','[]'::jsonb,'sessions', jsonb_build_array(
            jsonb_build_object('id','11111111-1111-1111-1111-111111111111','stall_id','s1',
                               'vehicle_id','v1','started_at','2026-01-01T00:00:01Z',
                               'status','active','power_kw',50)));
  v_f2 := jsonb_build_object('stalls','[]'::jsonb,'sessions', jsonb_build_array(
            jsonb_build_object('id','22222222-2222-2222-2222-222222222222','stall_id','s1',
                               'vehicle_id','v1','started_at','2026-01-01T00:00:01Z',
                               'status','active','power_kw',50)));

  v_old1 := encode(digest(jsonb_pretty(v_f1), 'sha256'), 'hex');
  v_old2 := encode(digest(jsonb_pretty(v_f2), 'sha256'), 'hex');
  IF v_old1 = v_old2 THEN
    RAISE EXCEPTION 'A3 FAILED (bug half): the OLD expression agreed on two frames '
                    'differing only in session id -- the defect this file fixes is not '
                    'reproducible, so the file is built on a wrong story';
  END IF;

  v_new1 := encode(digest(jsonb_pretty(public.ottoq_frame_hash_payload(v_f1)), 'sha256'), 'hex');
  v_new2 := encode(digest(jsonb_pretty(public.ottoq_frame_hash_payload(v_f2)), 'sha256'), 'hex');
  IF v_new1 <> v_new2 THEN
    RAISE EXCEPTION 'A3 FAILED (fix half): the NEW payload still differs across session ids';
  END IF;
  RAISE NOTICE 'A3 OK: old digest differs on session id alone, new digest does not';
END $a3$;

-- A4. A REAL TAMPER IS STILL CAUGHT UNDER THE NEW ALGORITHM.
-- The whole point of the column is tamper detection; a normalised hash that no
-- longer notices an edited frame would be worse than the nondeterministic one.
DO $a4$
DECLARE v_f jsonb; v_clean text; v_edited text;
BEGIN
  v_f := jsonb_build_object('sessions', jsonb_build_array(
           jsonb_build_object('id','11111111-1111-1111-1111-111111111111','stall_id','s1',
                              'vehicle_id','v1','started_at','2026-01-01T00:00:01Z',
                              'power_kw',50)));
  v_clean  := encode(digest(jsonb_pretty(public.ottoq_frame_hash_payload(v_f)), 'sha256'), 'hex');
  v_edited := encode(digest(jsonb_pretty(public.ottoq_frame_hash_payload(
                jsonb_set(v_f, '{sessions,0,power_kw}', '250'::jsonb))), 'sha256'), 'hex');
  IF v_clean = v_edited THEN
    RAISE EXCEPTION 'A4 FAILED: editing a session power value did not move the hash -- '
                    'the normalisation is too wide and has stopped detecting tampering';
  END IF;
  RAISE NOTICE 'A4 OK: an edited frame still moves the new hash';
END $a4$;

-- A5. A ROW DECLARING AN UNKNOWN ALGORITHM IS REFUSED, NOT GUESSED.
DO $a5$
DECLARE v_id uuid; v_ok boolean := false;
BEGIN
  SELECT snapshot_id INTO v_id FROM public.ottoq_decision_snapshots
   WHERE hash_algo IS NULL ORDER BY captured_at DESC LIMIT 1;
  IF v_id IS NULL THEN RAISE EXCEPTION 'A5 INCONCLUSIVE: no row to test with'; END IF;
  UPDATE public.ottoq_decision_snapshots SET hash_algo = 99 WHERE snapshot_id = v_id;
  BEGIN
    PERFORM public.ottoq_assert_snapshot_integrity(v_id);
  EXCEPTION WHEN raise_exception THEN
    v_ok := position('OTTOQ_SNAPSHOT_UNKNOWN_ALGO' in SQLERRM) > 0;
  END;
  UPDATE public.ottoq_decision_snapshots SET hash_algo = NULL WHERE snapshot_id = v_id;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'A5 FAILED: an unknown hash_algo was not refused';
  END IF;
  IF (SELECT hash_algo FROM public.ottoq_decision_snapshots WHERE snapshot_id=v_id) IS NOT NULL THEN
    RAISE EXCEPTION 'A5 FAILED: the probe did not restore the row';
  END IF;
  PERFORM public.ottoq_assert_snapshot_integrity(v_id);
  RAISE NOTICE 'A5 OK: unknown algo refused, row restored and still verifies';
END $a5$;

-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0280_a_tamper_check_that_cannot_tell_tampering_from_a_fresh_uuid', false,
 'Makes ottoq_decision_snapshots.content_hash id-blind. Adds nullable hash_algo (NULL = the original raw-frame digest, never backfilled; 2 = the new payload), public.ottoq_frame_hash_payload (IMMUTABLE; drops the minted session id and re-sorts sessions on stall_id/vehicle_id/started_at, everything else passed through), and moves ottoq_capture_decision_snapshot and ottoq_assert_snapshot_integrity together so the writer and the verifier remain one algorithm. ottoq_build_decision_frame is NOT modified and the stored frame column is unchanged, so no proposer, selector or decide-path consumer sees a different frame and no scheduling behaviour changes. forces_recert=false: content_hash is not one of the fourteen atoms (which is why db/checks/0216 could find it broken while pairs passed), ottoq_determinism_pair does not read ottoq_decision_snapshots, and legacy rows keep verifying under their own algorithm (A1, 200 sampled). NOTE: this classification is about the ATOMS. The fix itself is unproven until a determinism pair shows 48 of 48 agreement instead of 4 -- that is a round, not a migration step, and this file must be applied inside such a window.',
 now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
