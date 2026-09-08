-- migration-version: 20260908084304
-- migration-name:    h_sdr_hashed_a_signature_computed_over_a_run_scoped_id
--
-- ---------------------------------------------------------------------------
-- 0218 — h_sdr hashed a signature computed over a run-scoped id. Corrects 0217.
--
-- 0217 said h_sdr was id-blind "the way 0139 made endst id-blind", listed the
-- run-scoped ids it excludes, and then included `payload_hash` on the reasoning
-- that it "derives from content". It does not. `payload_hash` is
-- ottoq_compute_event_hash(v_payload), and ottoq_emit_sdr builds v_payload with
--
--     'leg_id', p_leg_id, 'schedule_task_id', p_schedule_task_id
--
-- leg_id is a fresh uuid per run. So payload_hash differs between two arms of
-- the same seed BY CONSTRUCTION, and h_sdr could never have been equal.
--
-- Caught by round 25's first pair, 08:25 UTC, flagship busy_day/314159/12t:
--
--   eleven enforced atoms      ALL held, pair PASSED
--     fp 803698f3 · h_cmd 109e340b · h_dec 9abdb4af · h_evt 9c631343
--     h_bkg 174b8835 · h_nrg a9c6b693 · h_prop a79c1095 · h_cal 11a24626
--     h_rule fc69953b · h_rcl 0e67b89a (first enforced round, passed)
--   h_sdr, measured not judged  0df9a909 vs 65ec044e   DIFFERED
--
-- Diagnosed on the pair's own rows rather than guessed. Matching the 284 SDRs
-- across arms on (vin, operation_code, started_at), field by field:
--
--   tariff_id differs        0 of 284
--   total_cost_usd differs   0 of 284
--   ended_at differs         0 of 284
--   duration_min differs     0 of 284
--   source_kind differs      0 of 284
--   payload_hash differs   284 of 284      <- everything, and only this
--
-- Recomputing the whole h_sdr expression with payload_hash removed:
--
--   arm a  aad2d1be        arm b  aad2d1be        IDENTICAL
--
-- Two conclusions, and the first one matters more than the mistake:
--
-- 1. 0216 WORKED. With the one bad column gone, the SDR streams of a replayed
--    seed agree exactly — including the booking attribution, which was the
--    whole point. 23 of 284 rows used to bind to a different calendar claim;
--    now none do.
--
-- 2. The mistake is mine and it is the same class 0139 exists to prevent:
--    "derives from content" was reasoning, not measurement. The column was
--    never checked against a real pair before being promoted. One
--    `SELECT ottoq_hash_sdrs(a) = ottoq_hash_sdrs(b)` on the two committed
--    round-24 arms would have shown it in a second — and 0217's A3 DID run
--    exactly that comparison and saw them differ, and I read that as the
--    instrument working. It was, but for two reasons at once, and I only
--    counted the one I was looking for. A guard that fires can still be firing
--    for the wrong reason; the check is to ask what ELSE would make it fire.
--
--    The uncontaminated evidence that the instrument sees the booking blind
--    spot is 0216's A3, which compares the booking pick alone:
--    9446e834 / 885785db before, f242efbf on both arms after.
--
-- A FINDING THIS TURNED UP, not fixed here. The SDR is signed over a payload
-- that contains leg_id and schedule_task_id — run-scoped ids — and does NOT
-- contain booking_id or visit_id. So the settlement record's signature covers
-- an identifier that cannot survive a replay, and omits the attribution that
-- must. Both halves are wrong, in opposite directions. Fixing either moves
-- payload_hash on every future SDR and therefore h_evt on every column — a
-- full six-column recert — so it belongs with G10 (task #71), stated here so
-- it is not mistaken for covered ground.
--
-- forces_recert: FALSE. h_sdr is still measured, not enforced; no canon exists
-- for it yet and none moves.
-- ---------------------------------------------------------------------------

BEGIN;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0218_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_hash_sdrs';

DO $pre$
DECLARE v_md5 text; v_n int;
BEGIN
  SELECT left(md5(pg_get_functiondef(p.oid)),8) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_hash_sdrs';
  IF v_md5 IS DISTINCT FROM '820f3491' THEN
    RAISE EXCEPTION '0218 P0: ottoq_hash_sdrs is %, pinned 820f3491', v_md5;
  END IF;
  SELECT (length(p.prosrc)-length(replace(p.prosrc,'COALESCE(d.payload_hash,''-'')||''|''||','')))
         / length('COALESCE(d.payload_hash,''-'')||''|''||') INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_hash_sdrs';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0218 P0: the payload_hash term appears % times, want exactly 1', v_n;
  END IF;
  RAISE NOTICE '0218 P0: body 820f3491, one payload_hash term';
END $pre$;

CREATE OR REPLACE FUNCTION public.ottoq_hash_sdrs(p_run uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $hs$
  WITH bk AS (
    SELECT b.booking_id,
           lower(b.during)::text||'/'||upper(b.during)::text||'/'||
             COALESCE(sb.stall_code,'-')||'/'||b.state||'/'||COALESCE(b.purpose,'-') AS content
      FROM public.ottoq_stall_bookings b
      LEFT JOIN public.stalls sb ON sb.id = b.stall_id
     WHERE b.booking_id IN (SELECT d.booking_id
                              FROM public.ottoq_service_detail_records d
                             WHERE d.sim_run_id = p_run AND d.booking_id IS NOT NULL)
  ), sdr_rows AS (
    --: 0218. payload_hash is NOT here, and its absence is the point. It is
    --: ottoq_compute_event_hash over a payload containing leg_id -- a fresh
    --: uuid per run -- so it differs between two arms of the same seed by
    --: construction. 0217 included it on the reasoning that it "derives from
    --: content"; round 25's first pair measured 284 of 284 rows differing on
    --: that column and on nothing else.
    SELECT COALESCE(d.pack_id,'-')||'|'||COALESCE(d.operation_code,'-')||'|'||
           COALESCE(v.vin,'-')||'|'||COALESCE(d.asset_class_code,'-')||'|'||
           COALESCE(d.fleet_operator_id::text,'-')||'|'||
           COALESCE(dp.slug,'-')||'|'||COALESCE(st.stall_code,'-')||'|'||
           COALESCE(d.source_kind,'-')||'|'||
           COALESCE(d.started_at::text,'-')||'|'||COALESCE(d.ended_at::text,'-')||'|'||
           COALESCE(d.duration_min::text,'-')||'|'||COALESCE(d.energy_kwh::text,'-')||'|'||
           COALESCE(d.peak_kw::text,'-')||'|'||COALESCE(d.tariff_id::text,'-')||'|'||
           COALESCE(d.total_cost_usd::text,'-')||'|'||
           COALESCE(d.billable_amount_usd::text,'-')||'|'||
           COALESCE(d.currency,'-')||'|'||COALESCE(d.status,'-')||'|'||
           COALESCE(d.schema_version,'-')||'|'||COALESCE(d.data_source,'-')||'|'||
           'bk='||COALESCE(bk.content,'none')||'|'||
           'visit='||CASE WHEN d.visit_id IS NULL THEN 'none' ELSE 'set' END AS c
      FROM public.ottoq_service_detail_records d
      LEFT JOIN public.vehicles v  ON v.id  = d.vehicle_id
      LEFT JOIN public.stalls   st ON st.id = d.stall_id
      LEFT JOIN public.depots   dp ON dp.id = d.depot_id
      LEFT JOIN bk ON bk.booking_id = d.booking_id
     WHERE d.sim_run_id = p_run
  )
  SELECT md5(COALESCE(string_agg(c, E'\n' ORDER BY c), '')) FROM sdr_rows;
$hs$;

COMMENT ON FUNCTION public.ottoq_hash_sdrs(uuid) IS
  '0217, corrected by 0218: md5 over the run''s ServiceDetailRecord stream in content order. '
  'Id-blind -- vehicle by vin, stall and depot by code, BOOKING BY CONTENT rather than uuid. '
  'Excludes every run-scoped id, issued_at (wall clock), signature (derived from a random '
  'sdr_id) AND payload_hash (derived from a payload containing leg_id, so it cannot be equal '
  'across two arms of the same seed -- 0217 got this wrong and round 25 measured it, 284 of 284 '
  'rows). This is h_sdr in the pair verdict: measured, enforced once a flagship round shows the '
  'arms agree.';

-- A1. THE BAD TERM IS GONE AND THE GOOD ONES REMAIN --------------------------
DO $a1$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_hash_sdrs';
  IF position('d.payload_hash' in v_def) <> 0 THEN
    RAISE EXCEPTION '0218 A1: payload_hash is still hashed';
  END IF;
  IF position('bk.content' in v_def) = 0 OR position('d.total_cost_usd' in v_def) = 0 THEN
    RAISE EXCEPTION '0218 A1: the booking attribution or the money left the hash with it';
  END IF;
  RAISE NOTICE '0218 A1: payload_hash gone, attribution and money still hashed';
END $a1$;

-- A2. THE ARMS OF ROUND 25's PAIR NOW AGREE ---------------------------------
-- The falsifiable claim. These two runs are committed and unchanged; if the
-- corrected hash does not make them equal, the diagnosis was wrong.
DO $a2$
DECLARE v_a text; v_b text; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_service_detail_records
   WHERE sim_run_id='5861ea1d-10f6-46ff-8ad8-0145ab5def44';
  IF v_n = 0 THEN RAISE NOTICE '0218 A2 SKIPPED: round 25 arm a is gone'; RETURN; END IF;
  v_a := public.ottoq_hash_sdrs('5861ea1d-10f6-46ff-8ad8-0145ab5def44');
  v_b := public.ottoq_hash_sdrs('98095daf-8cc8-428a-a959-1e0916a8d3b4');
  IF v_a IS DISTINCT FROM v_b THEN
    RAISE EXCEPTION '0218 A2: the arms STILL disagree after removing payload_hash: % vs % — '
                    'payload_hash was not the only carrier and the diagnosis is incomplete',
                    left(v_a,8), left(v_b,8);
  END IF;
  IF v_a = md5('') THEN
    RAISE EXCEPTION '0218 A2: the hash is empty over % SDRs — it now reads nothing', v_n;
  END IF;
  RAISE NOTICE '0218 A2: round 25 arms agree at h_sdr % over % SDRs per arm', left(v_a,8), v_n;
END $a2$;

-- A3. AND IT IS STILL NOT BLIND TO THE THING IT WAS BUILT FOR ----------------
-- The pre-0216 arms bound 23 of 284 SDRs to a different booking. With
-- payload_hash gone, h_sdr must STILL tell them apart, or 0218 has fixed the
-- false positive by making the instrument useless.
DO $a3$
DECLARE v_a text; v_b text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_service_detail_records
                  WHERE sim_run_id='ea855128-30e9-45df-91ac-4ebd880419db') THEN
    RAISE NOTICE '0218 A3 SKIPPED: the round-24 arms are gone'; RETURN;
  END IF;
  v_a := public.ottoq_hash_sdrs('53317e05-19c4-4bd0-9315-12089f51cc6b');
  v_b := public.ottoq_hash_sdrs('ea855128-30e9-45df-91ac-4ebd880419db');
  IF v_a = v_b THEN
    RAISE EXCEPTION '0218 A3: h_sdr now AGREES (%) across the two pre-0216 arms, whose booking '
                    'picks are known to differ on 23 of 284 rows — removing payload_hash has '
                    'blinded the instrument to the defect it exists for', left(v_a,8);
  END IF;
  RAISE NOTICE '0218 A3: pre-0216 arms still separated, % vs %', left(v_a,8), left(v_b,8);
END $a3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0218_h_sdr_hashed_a_signature_computed_over_a_run_scoped_id', FALSE,
        'CORRECTS 0217. h_sdr included payload_hash, which is ottoq_compute_event_hash over a '
        'payload containing leg_id — a fresh uuid per run — so the hash could never be equal '
        'across two arms of one seed. Round 25 pair 1 measured it: 284 of 284 SDRs differ on '
        'payload_hash and 0 differ on tariff_id, total_cost_usd, ended_at, duration_min or '
        'source_kind. With the column removed both arms read aad2d1be, which also confirms 0216 '
        'worked — the booking attribution now reproduces. A2 re-asserts that on the committed '
        'arms and A3 re-asserts that the instrument still separates the pre-0216 pair, so the '
        'false positive is not being fixed by blinding it.',
        now());

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 03:43 AM CT (08:43:04 UTC), ledger version 20260908084304.
--
--   P0  body 820f3491, the payload_hash term exactly once
--   A1  payload_hash gone; the booking-content and money terms still present
--   A2  round 25's two committed arms now AGREE:  aad2d1be / aad2d1be
--   A3  the two pre-0216 arms are STILL separated: 1cc8a3ef / e1fe3504
--
-- A2 and A3 together are the point. A2 alone could be achieved by blinding the
-- instrument; A3 is what rules that out. And A2 is also the proof that 0216
-- worked — with the one column that could never agree removed, the SDR stream
-- of a replayed seed reproduces exactly, booking attribution included.
-- ---------------------------------------------------------------------------
