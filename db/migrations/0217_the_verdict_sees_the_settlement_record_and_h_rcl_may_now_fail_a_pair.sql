-- migration-version: 20260908082227
-- migration-name:    the_verdict_sees_the_settlement_record_and_h_rcl_may_now_fail_a_pair
--
-- ---------------------------------------------------------------------------
-- 0217 — the verdict sees the settlement record, and h_rcl may now fail a pair.
--
-- Two promotions, both on the same rule the repo has used since 0139: an
-- instrument is added MEASURED first and ENFORCED only after a flagship round
-- shows the arms agree on it.
--
-- ── h_sdr: MEASURED, not judged ───────────────────────────────────────────
-- 0216 fixed a nondeterminism in ottoq_trg_leg_done_sdr that no atom could
-- see. The reason it could not be seen is the point of this migration:
-- ottoq_service_detail_records is read by NO fingerprint and NO ottoq_hash_*
-- function — checked against pg_proc, not remembered — and ottoq_emit_sdr's
-- signed payload omits booking_id and visit_id, so the divergence could not
-- reach h_evt either. 127k settlement records, the object CLAUDE.md 2.6 calls
-- the strategic centre of the build, entirely outside the certification.
--
-- h_sdr is id-blind, the way 0139 made endst id-blind: vehicle by vin, stall
-- and depot by code, booking by its CONTENT (window, stall, state, purpose)
-- rather than its uuid — because comparing raw booking uuids across two arms
-- would differ by construction and prove nothing. Run-scoped ids are excluded
-- entirely: sdr_id, sim_run_id, leg_id, visit_id, booking_id, sdr_event_id,
-- schedule_task_id, attribution_id, ocpp_session_id. issued_at is a wall clock
-- and is excluded. signature derives from the random sdr_id and is excluded;
-- payload_hash derives from content and is included.
--
-- WHAT h_sdr DOES NOT ANSWER, stated here so it is not mistaken for wider
-- cover later (round 22 learned this about h_rule the hard way): it does not
-- see which VISIT an SDR belongs to beyond present/absent, and it cannot see
-- anything the SDR does not store. It answers "did the same settlement records
-- get written, with the same money, against the same physical claim".
--
-- ENFORCEMENT IS DELIBERATELY NOT IN THIS FILE. h_sdr goes into the arm object
-- and nothing else. A3 below proves it would have caught 0216's defect on the
-- pre-fix arms; the round after this one proves the fix holds, and only then
-- does h_sdr join v_equal.
--
-- ── h_rcl: ENFORCED, the gate 0206 set is met ─────────────────────────────
-- 0206 shipped h_rcl with an explicit condition, quoted from its own COMMENT:
-- "measured from 0206, enforced after a flagship round shows the arms agree."
-- That has now happened twice on the flagship:
--
--   round 22 (09-07)  busy_day/314159/12t   h_rcl 0e67b89a  both arms
--   round 24 (09-08)  same column, 2 pairs  h_rcl 0e67b89a  all four arms
--
-- Same value across two rounds and six arms. The condition is met, so h_rcl
-- joins v_equal. Until now it was computed, stored, displayed — and unable to
-- fail anything, which is the state 0206 said it should not stay in.
--
-- forces_recert: FALSE. Neither change alters engine behaviour; both change
-- what the verdict looks at. No canon moves. h_sdr simply has no canon yet.
-- ---------------------------------------------------------------------------

BEGIN;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0217_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_determinism_pair';

-- P0. PRECONDITIONS ---------------------------------------------------------
DO $pre$
DECLARE v_md5 text; v_a int; v_b int;
BEGIN
  SELECT left(md5(pg_get_functiondef(p.oid)),8),
         (length(p.prosrc)-length(replace(p.prosrc,'''h_rcl'', public.ottoq_hash_recall_decisions(v_run))','')))
           / length('''h_rcl'', public.ottoq_hash_recall_decisions(v_run))'),
         (length(p.prosrc)-length(replace(p.prosrc,'AND (v_arms[1]->>''ticks'') = (v_arms[2]->>''ticks'')','')))
           / length('AND (v_arms[1]->>''ticks'') = (v_arms[2]->>''ticks'')')
    INTO v_md5, v_a, v_b
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';

  IF v_md5 IS DISTINCT FROM '788ed4b7' THEN
    RAISE EXCEPTION '0217 P0: ottoq_determinism_pair is %, pinned 788ed4b7', v_md5;
  END IF;
  IF v_a <> 1 OR v_b <> 1 THEN
    RAISE EXCEPTION '0217 P0: anchors appear arm=% equal=%, want 1 and 1', v_a, v_b;
  END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair') <> 1 THEN
    RAISE EXCEPTION '0217 P0: more than one ottoq_determinism_pair overload — the rewrite would be ambiguous';
  END IF;
  RAISE NOTICE '0217 P0: body 788ed4b7, both anchors exactly once, one overload';
END $pre$;

-- 1. THE HASH ---------------------------------------------------------------
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
           COALESCE(d.payload_hash,'-')||'|'||
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
  '0217: md5 over the run''s ServiceDetailRecord stream in content order. Id-blind by '
  'construction — vehicle by vin, stall and depot by code, BOOKING BY CONTENT rather than uuid, '
  'because the booking a settlement record attributes to is exactly what 0216 found was chosen by '
  'the heap. Excludes every run-scoped id, issued_at (wall clock) and signature (derived from a '
  'random sdr_id); includes payload_hash (derived from content). This is h_sdr in the pair '
  'verdict: measured from 0217, enforced after a flagship round shows the arms agree — the same '
  'gate 0206 set for h_rcl and 0217 now closes.';

-- 2. THE ARM OBJECT CARRIES IT (catalog-derived rewrite) --------------------
DO $rw$
DECLARE
  v_def text;
  v_old text := $f$'h_rcl', public.ottoq_hash_recall_decisions(v_run))$f$;
  v_new text := $f$'h_rcl', public.ottoq_hash_recall_decisions(v_run), 'h_sdr', public.ottoq_hash_sdrs(v_run))$f$;
  v_old2 text := $f$AND (v_arms[1]->>'ticks') = (v_arms[2]->>'ticks')$f$;
  v_new2 text := $f$AND (v_arms[1]->>'h_rcl') = (v_arms[2]->>'h_rcl')   -- 0217: the gate 0206 set is met
         AND (v_arms[1]->>'ticks') = (v_arms[2]->>'ticks')$f$;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';

  IF (length(v_def)-length(replace(v_def, v_old, '')))/length(v_old) <> 1 THEN
    RAISE EXCEPTION '0217: arm anchor not exactly once in the catalog definition';
  END IF;
  IF (length(v_def)-length(replace(v_def, v_old2, '')))/length(v_old2) <> 1 THEN
    RAISE EXCEPTION '0217: equal anchor not exactly once in the catalog definition';
  END IF;

  v_def := replace(v_def, v_old,  v_new);
  v_def := replace(v_def, v_old2, v_new2);
  EXECUTE v_def;
  RAISE NOTICE '0217: ottoq_determinism_pair rewritten from its own catalog definition';
END $rw$;

-- A1. BOTH EDITS ARE IN THE INSTALLED BODY ----------------------------------
DO $a1$
DECLARE v_def text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF position($$'h_sdr', public.ottoq_hash_sdrs(v_run)$$ in v_def) = 0 THEN
    RAISE EXCEPTION '0217 A1: the arm object does not carry h_sdr';
  END IF;
  IF position($$(v_arms[1]->>'h_rcl') = (v_arms[2]->>'h_rcl')$$ in v_def) = 0 THEN
    RAISE EXCEPTION '0217 A1: h_rcl is not enforced in v_equal';
  END IF;
  IF position($$(v_arms[1]->>'h_sdr')$$ in v_def) <> 0 THEN
    RAISE EXCEPTION '0217 A1: h_sdr is being ENFORCED — this file measures it only';
  END IF;
  RAISE NOTICE '0217 A1: h_sdr measured, h_rcl enforced, h_sdr not enforced';
END $a1$;

-- A2. THE HASH IS NOT DEGENERATE --------------------------------------------
DO $a2$
DECLARE v_h text; v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_service_detail_records
   WHERE sim_run_id='53317e05-19c4-4bd0-9315-12089f51cc6b';
  IF v_n = 0 THEN RAISE NOTICE '0217 A2 SKIPPED: the round-24 arm is gone'; RETURN; END IF;
  v_h := public.ottoq_hash_sdrs('53317e05-19c4-4bd0-9315-12089f51cc6b');
  IF v_h IS NULL OR v_h = md5('') THEN
    RAISE EXCEPTION '0217 A2: h_sdr is empty over % SDRs — the hash reads nothing', v_n;
  END IF;
  RAISE NOTICE '0217 A2: h_sdr % over % SDRs', left(v_h,8), v_n;
END $a2$;

-- A3. THE INSTRUMENT WOULD HAVE CAUGHT 0216 ---------------------------------
-- The two round-24 arms were written BEFORE 0216, so their SDR rows still
-- carry the heap's picks. h_sdr must disagree across them. If it agrees, the
-- hash does not see the booking attribution and is not worth promoting.
DO $a3$
DECLARE v_a text; v_b text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_service_detail_records
                  WHERE sim_run_id='ea855128-30e9-45df-91ac-4ebd880419db') THEN
    RAISE NOTICE '0217 A3 SKIPPED: the round-24 arms are gone';
    RETURN;
  END IF;
  v_a := public.ottoq_hash_sdrs('53317e05-19c4-4bd0-9315-12089f51cc6b');
  v_b := public.ottoq_hash_sdrs('ea855128-30e9-45df-91ac-4ebd880419db');
  IF v_a = v_b THEN
    RAISE EXCEPTION '0217 A3: h_sdr AGREES (%) across two arms whose booking picks are known to '
                    'differ on 23 of 284 rows — the hash is blind to the very thing it is for', left(v_a,8);
  END IF;
  RAISE NOTICE '0217 A3: h_sdr % vs % on the pre-0216 arms — the blind spot is now visible',
               left(v_a,8), left(v_b,8);
END $a3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0217_the_verdict_sees_the_settlement_record_and_h_rcl_may_now_fail_a_pair', FALSE,
        'h_sdr added to the arm object, MEASURED not judged: ottoq_service_detail_records was read '
        'by no fingerprint and no ottoq_hash_* function, so 127k settlement records sat outside the '
        'certification and 0216''s defect could not fail a pair. Id-blind like endst; the booking is '
        'hashed by CONTENT because its uuid differs between arms by construction. A3 proves it '
        'disagrees across the two pre-0216 arms. h_rcl moves from measured to ENFORCED: 0206 set the '
        'gate as "after a flagship round shows the arms agree" and rounds 22 and 24 both returned '
        '0e67b89a across six arms. No engine behaviour changes; no canon moves.',
        now());

COMMIT;

-- ---------------------------------------------------------------------------
-- APPLIED 2026-09-08 03:22 AM CT (08:22:27 UTC), ledger version 20260908082227.
-- P0 (body 788ed4b7, both anchors once, one overload), A1, A2 and A3 passed;
-- A3 read h_sdr 833f61c9 vs 49714ab9 on the two pre-0216 arms.
--
-- CORRECTED THE SAME NIGHT BY 0218, which is the honest footer this file needs.
-- h_sdr as shipped here included payload_hash, and payload_hash is
-- ottoq_compute_event_hash over a payload containing leg_id — a fresh uuid per
-- run — so it could never be equal across two arms of one seed. Round 25's
-- first pair measured it: 284 of 284 SDRs differ on that column and 0 differ on
-- tariff_id, total_cost_usd, ended_at, duration_min or source_kind.
--
-- A3 above therefore passed for two reasons at once and I counted only the one
-- I was looking for. The uncontaminated evidence that h_sdr sees the booking
-- blind spot is 0216's A3, not this one.
--
-- The h_rcl half of this migration is unaffected and did its job: round 25's
-- pair 1 was the first round in which h_rcl could fail a pair, and it passed at
-- 0e67b89a, the same value rounds 22 and 24 recorded.
-- ---------------------------------------------------------------------------
