-- migration-version: PENDING
-- migration-name:    the_settlement_record_binds_to_whichever_booking_the_heap_returned_first
--
-- NOTE on this header: APPLYING.md step 1 requires it, and 95 of the 215 files
-- in db/migrations do not have it — the convention lapsed after 0138, which
-- means scripts/gen-drift-sql.sh has been unable to regenerate the manifest,
-- which means Sections A-C of the drift alarm have been dark for 77 migrations.
-- Recorded as its own task; this file at least stops adding to the pile.
-- ---------------------------------------------------------------------------
-- 0216 — the settlement record binds to whichever booking the heap returned
--        first, and the scan that returns it is the twin's slowest habit.
--
-- Found by following a performance drift that turned out not to be a
-- regression at all (see the CORRECTION appended to 0215 and
-- db/canons/round24.md). The drift is real, its cause is here, and underneath
-- the cause was a live nondeterminism the certification cannot see.
--
-- ── THE SLOW PART ─────────────────────────────────────────────────────────
-- ottoq_stall_bookings has no index on leg_id. Two hot paths filter on it:
--
--   ottoq_trg_leg_done_sdr    AFTER UPDATE OF status WHEN new.status='done'.
--                             433 firings per 12-tick arm on the flagship.
--   ottoq_itin_leg_open       the NOT EXISTS (… bz.leg_id = v_leg) guard,
--                             once per leg opened — 685 legs per arm.
--
-- Measured plan for the trigger's lookup against the live 774,482-row table:
--
--   Limit (actual time=960.775..965.092 rows=0 loops=1)
--     Buffers: shared hit=236 read=50769
--     ->  Gather … Parallel Seq Scan on ottoq_stall_bookings
--           Filter: (leg_id = '…'::uuid)   Rows Removed by Filter: 387241
--   Execution Time: 965.175 ms
--
-- ≈2,236 sequential scans of that table per pair, and the table grows with
-- every run ever archived — so the cost of a fixed 12-tick workload is set by
-- how much history the database holds, not by the run. 389 s on 09-01, 801 s
-- on 09-08, monotone. Same defect class as db/checks/0098.
--
-- ── THE PART THAT MATTERS MORE ────────────────────────────────────────────
-- The trigger's read is:
--
--   SELECT b.booking_id, b.visit_id INTO v_booking, v_visit
--     FROM ottoq_stall_bookings b WHERE b.leg_id = NEW.leg_id LIMIT 1;
--
-- LIMIT 1, no ORDER BY, and 33 of 433 done-legs carry more than one booking
-- (up to 7 — the superseded plans left by supersede_churn). So which calendar
-- claim a ServiceDetailRecord settles is decided by the heap.
--
-- MEASURED on the 07:49 pair's own committed rows, comparing by the booking's
-- CONTENT rather than its id (ids differ between arms by construction):
--
--   arm a  53317e05    284 SDRs   booking-attribution hash 9446e834…
--   arm b  ea855128    284 SDRs   booking-attribution hash 885785db…   DIFFER
--   SDRs binding to a different booking on replay:  23 of 284  (8.1%)
--
-- That pair PASSED all thirteen atoms. It passed because nothing hashes
-- ottoq_service_detail_records — no fingerprint or ottoq_hash_* function reads
-- the table, verified against the catalog — and because ottoq_emit_sdr's
-- signed payload omits booking_id and visit_id, so the divergence never
-- reaches h_evt either. 0217 closes that blind spot; this migration closes the
-- hole it was hiding.
--
-- ── THE ORDER, AND WHY THIS ONE ───────────────────────────────────────────
-- Not invented. Measured, on all 202 done-legs that carry a booking:
--
--   exactly one booking in a settled state (not superseded/released/cancelled)
--                                                       188 of 202
--   more than one settled                                 0 of 202
--   no settled booking at all (every one churned)         14 of 202
--
-- So "the booking that actually happened" is never ambiguous when it exists.
-- The order puts it first and only then falls back to content:
--
--   ORDER BY (state IN ('superseded','released','cancelled')),  -- settled wins
--            lower(during), upper(during), stall_id, booked_at_sim, state
--
-- Every key is arm-stable: no random uuid (stall_id is a shared world id), no
-- clock reading. It separates all 267 bookings on done-legs in BOTH arms —
-- zero rows the key cannot order — so LIMIT 1 is now total, not lucky.
--
-- PROVEN BEFORE APPLYING, and re-asserted live in A3 below: replaying the pick
-- under the new order over the two committed arms gives
--   arm a  f242efbf…      arm b  f242efbf…      IDENTICAL
-- against 9446e834… / 885785db… today. 19 SDRs in arm a and 15 in arm b move,
-- and they move to the same answer.
--
-- WHAT THIS DELIBERATELY DOES NOT DO. It does not decide the modelling
-- question "which booking SHOULD a leg's SDR settle when several exist" beyond
-- "the one that was not superseded". Binding the SDR to the operation ledger
-- properly is G10 (task #71). And the SDR's signature still does not cover
-- booking_id or visit_id — putting them in ottoq_emit_sdr's payload moves
-- payload_hash on every future SDR and therefore h_evt on every column, which
-- is a full six-column recert and belongs with G10, not here.
--
-- forces_recert: FALSE — and for once that is proven rather than asserted. No
-- verdict atom reads ottoq_service_detail_records, so no canon can move. The
-- next round still runs: to confirm exactly that, and to measure the duration.
-- ---------------------------------------------------------------------------

BEGIN;

-- SNAPSHOT BEFORE REPLACE (APPLYING.md step 2) ------------------------------
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0216_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_trg_leg_done_sdr';

-- P0. PRECONDITIONS ---------------------------------------------------------
DO $pre$
DECLARE v_md5 text; v_anchor int; v_idx int;
BEGIN
  SELECT left(md5(pg_get_functiondef(p.oid)),8) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_trg_leg_done_sdr';
  IF v_md5 IS DISTINCT FROM '54226dc2' THEN
    RAISE EXCEPTION '0216 P0: ottoq_trg_leg_done_sdr is % , pinned 54226dc2 — the body moved under me', v_md5;
  END IF;

  SELECT (length(p.prosrc) - length(replace(p.prosrc,
            'FROM ottoq_stall_bookings b WHERE b.leg_id = NEW.leg_id LIMIT 1;','')))
         / length('FROM ottoq_stall_bookings b WHERE b.leg_id = NEW.leg_id LIMIT 1;')
    INTO v_anchor
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_trg_leg_done_sdr';
  IF v_anchor <> 1 THEN
    RAISE EXCEPTION '0216 P0: the unordered read appears % times, want exactly 1', v_anchor;
  END IF;

  SELECT count(*) INTO v_idx FROM pg_indexes
   WHERE schemaname='public' AND tablename='ottoq_stall_bookings' AND indexdef ILIKE '%(leg_id)%';
  IF v_idx <> 0 THEN
    RAISE EXCEPTION '0216 P0: a leg_id index already exists (%) — re-read before proceeding', v_idx;
  END IF;

  RAISE NOTICE '0216 P0: body 54226dc2, one unordered read, no leg_id index';
END $pre$;

-- 1. THE PICK BECOMES TOTAL -------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_trg_leg_done_sdr()
RETURNS trigger
LANGUAGE plpgsql
AS $sdr$
DECLARE v_op record; v_booking uuid; v_visit uuid; v_depot uuid;
BEGIN
  PERFORM set_config('search_path','twin, ottoq, public, extensions', true);
  SELECT oc.pack_id, oc.operation_code INTO v_op
    FROM ottoq_operation_catalog oc
   WHERE oc.leg_type = NEW.leg_type AND oc.emits_sdr
   ORDER BY oc.pack_id, oc.operation_code   -- 0216: unambiguous today (no leg_type
   LIMIT 1;                                 -- has two emits_sdr rows), ordered anyway
  IF v_op IS NULL THEN RETURN NEW; END IF;

  --: 0216. THE SETTLEMENT RECORD NAMES THE BOOKING THAT HAPPENED.
  --: A leg can carry several bookings — the superseded plans churn left behind.
  --: Measured: 188 of 202 done-legs have exactly ONE booking in a settled
  --: state, 0 have more than one, 14 have none at all. So "not superseded"
  --: decides it whenever it can, and content decides the rest. Every key is
  --: arm-stable; no uuid ordering, no clock. Without this the answer came from
  --: the heap and differed on 23 of 284 SDRs across a passing pair's two arms.
  SELECT b.booking_id, b.visit_id INTO v_booking, v_visit
    FROM ottoq_stall_bookings b
   WHERE b.leg_id = NEW.leg_id
   ORDER BY (b.state IN ('superseded','released','cancelled')),
            lower(b.during), upper(b.during), b.stall_id, b.booked_at_sim, b.state
   LIMIT 1;

  SELECT i.depot_id INTO v_depot
    FROM ottoq_vehicle_itineraries i WHERE i.itinerary_id = NEW.itinerary_id;

  PERFORM ottoq_emit_sdr(
    'itinerary_leg', v_op.operation_code, v_op.pack_id,
    NEW.vehicle_id, NEW.sim_run_id,
    NEW.leg_id, NULL, v_visit, v_booking,
    NEW.to_stall_id, v_depot,
    NEW.actual_start_sim, COALESCE(NEW.actual_end_sim, now()));
  RETURN NEW;
END;
$sdr$;

-- 2. THE INDEX THE TWO HOT PATHS HAVE ALWAYS NEEDED --------------------------
-- Partial on leg_id IS NOT NULL: 325,731 of 774,482 rows carry a leg.
CREATE INDEX ottoq_stall_bookings_leg_idx
    ON public.ottoq_stall_bookings USING btree (leg_id)
 WHERE leg_id IS NOT NULL;

COMMENT ON INDEX public.ottoq_stall_bookings_leg_idx IS
  '0216: ottoq_trg_leg_done_sdr and ottoq_itin_leg_open both filter leg_id. Without this each '
  'is a parallel seq scan of the whole table (965 ms measured at 774k rows), ~2,236 of them per '
  'certification pair, and the cost grows with total history rather than with the run.';

-- A1. THE ORDER IS IN THE INSTALLED BODY, NOT JUST IN THIS FILE -------------
DO $a1$
DECLARE v_def text; v_ord int; v_lim int; v_bare int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_trg_leg_done_sdr';
  v_ord := position('ORDER BY (b.state IN (''superseded'',''released'',''cancelled''))' in v_def);
  v_lim := position('lower(b.during), upper(b.during), b.stall_id, b.booked_at_sim, b.state' in v_def);
  v_bare := position('WHERE b.leg_id = NEW.leg_id LIMIT 1' in v_def);
  IF v_ord = 0 OR v_lim = 0 OR v_lim < v_ord THEN
    RAISE EXCEPTION '0216 A1: the ordered pick is not installed (ord=% keys=%)', v_ord, v_lim;
  END IF;
  IF v_bare <> 0 THEN
    RAISE EXCEPTION '0216 A1: the unordered read survives at position %', v_bare;
  END IF;
  RAISE NOTICE '0216 A1: ordered pick installed, unordered read gone';
END $a1$;

-- A2. THE PLANNER ACTUALLY USES THE INDEX -----------------------------------
-- FORMAT JSON, deliberately: a text EXPLAIN returns one row per plan line and
-- EXECUTE ... INTO would capture only the first ("Limit"), which names no index
-- and would make this assertion pass or fail for the wrong reason.
DO $a2$
DECLARE v_plan text;
BEGIN
  EXECUTE 'EXPLAIN (COSTS OFF, FORMAT JSON) SELECT b.booking_id FROM public.ottoq_stall_bookings b '
          'WHERE b.leg_id = ''00000000-0000-0000-0000-000000000001''::uuid '
          'ORDER BY (b.state IN (''superseded'',''released'',''cancelled'')), '
          'lower(b.during), upper(b.during), b.stall_id, b.booked_at_sim, b.state LIMIT 1'
    INTO v_plan;
  IF v_plan ILIKE '%Seq Scan on ottoq_stall_bookings%' THEN
    RAISE EXCEPTION '0216 A2: still a seq scan after the index: %', v_plan;
  END IF;
  IF v_plan NOT ILIKE '%ottoq_stall_bookings_leg_idx%' THEN
    RAISE EXCEPTION '0216 A2: the plan does not name the new index: %', v_plan;
  END IF;
  RAISE NOTICE '0216 A2: plan uses ottoq_stall_bookings_leg_idx';
END $a2$;

-- A3. THE CLAIM, RE-ASSERTED AGAINST THE TWO COMMITTED ARMS -----------------
-- Falsifiable both ways: the OLD picks must differ (or there was no defect and
-- this migration is unjustified) and the NEW order must make them agree (or
-- the fix does not fix it).
DO $a3$
DECLARE v_old_a text; v_old_b text; v_new_a text; v_new_b text; v_n int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs
                  WHERE sim_run_id IN ('53317e05-19c4-4bd0-9315-12089f51cc6b',
                                       'ea855128-30e9-45df-91ac-4ebd880419db')) THEN
    RAISE NOTICE '0216 A3 SKIPPED: the round-24 arms are no longer present';
    RETURN;
  END IF;

  CREATE TEMP TABLE a3_sdr ON COMMIT DROP AS
    SELECT CASE WHEN d.sim_run_id='53317e05-19c4-4bd0-9315-12089f51cc6b' THEN 'a' ELSE 'b' END AS arm,
           d.leg_id, d.booking_id AS old_pick,
           (SELECT v.vin FROM public.vehicles v WHERE v.id=d.vehicle_id) AS vin,
           d.operation_code, d.started_at
      FROM public.ottoq_service_detail_records d
     WHERE d.sim_run_id IN ('53317e05-19c4-4bd0-9315-12089f51cc6b',
                            'ea855128-30e9-45df-91ac-4ebd880419db')
       AND d.leg_id IS NOT NULL;

  CREATE TEMP TABLE a3_bk ON COMMIT DROP AS
    SELECT b.booking_id, b.leg_id,
           lower(b.during)::text||'/'||upper(b.during)::text||'/'||
             COALESCE(s.stall_code,'-')||'/'||b.state||'/'||COALESCE(b.purpose,'-') AS content,
           row_number() OVER (PARTITION BY b.leg_id ORDER BY
               (b.state IN ('superseded','released','cancelled')),
               lower(b.during), upper(b.during), b.stall_id, b.booked_at_sim, b.state) AS rk
      FROM public.ottoq_stall_bookings b
      LEFT JOIN public.stalls s ON s.id = b.stall_id
     WHERE b.leg_id IN (SELECT leg_id FROM a3_sdr);

  SELECT count(*) INTO v_n FROM a3_sdr WHERE arm='a';

  SELECT md5(string_agg(COALESCE(o.content,'NULL'), E'\n' ORDER BY t.vin, t.operation_code, t.started_at)),
         md5(string_agg(COALESCE(nx.content,'NULL'), E'\n' ORDER BY t.vin, t.operation_code, t.started_at))
    INTO v_old_a, v_new_a
    FROM a3_sdr t
    LEFT JOIN a3_bk o  ON o.booking_id = t.old_pick
    LEFT JOIN a3_bk nx ON nx.leg_id = t.leg_id AND nx.rk = 1
   WHERE t.arm='a';

  SELECT md5(string_agg(COALESCE(o.content,'NULL'), E'\n' ORDER BY t.vin, t.operation_code, t.started_at)),
         md5(string_agg(COALESCE(nx.content,'NULL'), E'\n' ORDER BY t.vin, t.operation_code, t.started_at))
    INTO v_old_b, v_new_b
    FROM a3_sdr t
    LEFT JOIN a3_bk o  ON o.booking_id = t.old_pick
    LEFT JOIN a3_bk nx ON nx.leg_id = t.leg_id AND nx.rk = 1
   WHERE t.arm='b';

  IF v_old_a = v_old_b THEN
    RAISE EXCEPTION '0216 A3: the two arms already agree on the OLD pick (%) — the defect this '
                    'migration claims to fix is not present and the change is unjustified', left(v_old_a,8);
  END IF;
  IF v_new_a IS DISTINCT FROM v_new_b THEN
    RAISE EXCEPTION '0216 A3: the new order does NOT make the arms agree: % vs %',
                    left(v_new_a,8), left(v_new_b,8);
  END IF;
  RAISE NOTICE '0216 A3: % SDRs per arm. old % / % differ; new % on both arms',
               v_n, left(v_old_a,8), left(v_old_b,8), left(v_new_a,8);
END $a3$;

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0216_the_settlement_record_binds_to_whichever_booking_the_heap_returned_first', FALSE,
        'ottoq_stall_bookings.leg_id had no index; ottoq_trg_leg_done_sdr (433 firings per 12-tick '
        'arm) and ottoq_itin_leg_open both filter it, so each was a 965 ms parallel seq scan of a '
        '774k-row table and the cost of a fixed workload grew with total history — 389 s on 09-01 '
        'to 801 s on 09-08 for one column. Underneath it the trigger picked the SDR''s booking with '
        'LIMIT 1 and no ORDER BY among up to 7 candidates: 23 of 284 SDRs bound to a different '
        'booking across the two arms of a PASSING pair. forces_recert FALSE because no verdict atom '
        'reads ottoq_service_detail_records — verified against the catalog, not assumed. 0217 '
        'promotes h_sdr so this class cannot hide again.',
        now());

COMMIT;
