-- migration-version: 20260920041750
-- migration-name:    a_vehicle_parked_in_one_stall_was_still_holding_another
-- ════════════════════════════════════════════════════════════════════════════
-- 0369  A VEHICLE PARKED IN ONE STALL WAS STILL HOLDING ANOTHER, AND THE
--       RECLAIMER HAD NO RIGHT TO TAKE IT BACK.
--
--       forces_recert TRUE -- a third release class changes which stalls are
--       free on every tick of every arm.
-- ════════════════════════════════════════════════════════════════════════════
--
-- G84. The third and last layer of the same investigation. 0367 put the reclaimer
-- on the live path; 0368 stopped the reroute searching the wrong stall type. With
-- both in, the escalations that remain are legible for the first time, and they
-- say something 0367 cannot act on. From the enriched payload 0368 added, on run
-- `5b37ee46-ee1e-4b6f-a4c8-eec126ab7a10`:
--
--   escalated no_capacity, wanted 'dcfc', source 'payload', candidates_seen 2   x3
--   escalated no_capacity, wanted 'l2',   source 'payload', candidates_seen 4   x2
--   escalated no_capacity, wanted 'l2',   source 'payload', candidates_seen 2   x1
--
-- `candidates_seen` is the number of CALENDAR-FREE stalls the walk examined and
-- `ottoq_reserve_stall` refused. So the calendar and the reservation pointer
-- disagree about the same stall, and the reroute is where they collide. The
-- reactor's own comment has always said so -- "reserve-first walk (the legacy
-- pointer is the scarcer gate)" -- but the size of the gap had never been counted.
--
-- Measured on that run, on the twin depot, at 38 sim-minutes:
--
--   reserved-empty, UNEXPIRED stalls                                 50
--     holder is physically sitting in a DIFFERENT stall              36
--       of those, NO held/active booking for holder on this stall    21   <- releasable
--       of those, a held/active booking exists                      15   <- a real plan
--
--   and the reservation census that frames it:
--     dcfc        10 stalls, 10 reserved,  8 occupied
--     l2          30 stalls, 27 reserved, 24 occupied
--     staging    113 stalls, 101 reserved, 60 occupied, TTLs to 7h14m
--     wash_bay     3 stalls,  0 reserved,  0 occupied
--
-- A vehicle sitting in stall A cannot also occupy stall B. Its unexpired hold on
-- B is dead weight -- UNLESS the calendar says it is a plan, and for 15 of the 36
-- it does: charge now, staging place when the charge finishes. **Releasing on
-- "holder is elsewhere" alone would have destroyed those fifteen legitimate
-- plans.** The booking test is the entire safety of this class, and it is why this
-- is a separate migration rather than a wider predicate bolted onto 0367.
--
-- The hierarchy it encodes: THE CALENDAR IS THE AUTHORITY ON INTENT, the pointer
-- is a lock. A lock with no intent behind it is garbage; a lock with intent behind
-- it is untouchable. That is the same "assignment plus verification" pair
-- CLAUDE.md rule 6 protects, read in the direction nobody had read it.
--
-- AND ONE GUARD THAT IS NOT OPTIONAL. `ottoq_stall_bookings.sim_run_id` is NOT
-- NULL. On a production call (`p_sim_run_id IS NULL`) the booking test can never
-- find a row, so EVERY held stall would look unbacked and the reclaimer would
-- strip the whole site. The class is therefore gated on `p_sim_run_id IS NOT
-- NULL` -- twin-scoped until production bookings exist to test against. P1
-- asserts that gate is present in the body.

-- ══ P0. THE RECLAIMER IS THE 0367 VERSION AND NOT ALREADY PATCHED ═══════════
DO $p0$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_release_unusable_reservations';
  IF v_src IS NULL THEN RAISE EXCEPTION 'P0: reclaimer not found'; END IF;
  IF position('SKIP LOCKED' in v_src) = 0 THEN
    RAISE EXCEPTION 'P0: this is not the 0367 reclaimer -- apply 0367 first';
  END IF;
  IF position('v_by_orphan' in v_src) > 0 THEN
    RAISE EXCEPTION 'P0: already patched -- 0369 has been applied';
  END IF;
  RAISE NOTICE 'P0 ok';
END $p0$;

-- ══ P1. THE DEFECT IS LIVE, AND THE SAFE/UNSAFE SPLIT IS REAL ═══════════════
DO $p1$
DECLARE
  v_run uuid; v_clk timestamptz; v_elsewhere bigint; v_unbacked bigint; v_backed bigint;
BEGIN
  SELECT r.sim_run_id, COALESCE(r.sim_clock_current, r.sim_clock_start)
    INTO v_run, v_clk
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'running'
   ORDER BY r.started_at DESC LIMIT 1;
  IF v_run IS NULL THEN
    RAISE NOTICE 'P1: no running run on the twin depot; nothing to measure';
    RETURN;
  END IF;

  SELECT count(*) FILTER (WHERE elsewhere),
         count(*) FILTER (WHERE elsewhere AND NOT booked),
         count(*) FILTER (WHERE elsewhere AND booked)
    INTO v_elsewhere, v_unbacked, v_backed
    FROM (
      SELECT EXISTS (SELECT 1 FROM public.stalls s2
                      WHERE s2.current_vehicle_id = s.reserved_by AND s2.id <> s.id) AS elsewhere,
             EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                      WHERE b.sim_run_id = v_run AND b.stall_id = s.id
                        AND b.vehicle_id = s.reserved_by
                        AND b.state IN ('held','active'))                            AS booked
        FROM public.stalls s
       WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
         AND s.reserved_by IS NOT NULL
         AND s.current_vehicle_id IS NULL
         AND s.reservation_expires_at >= v_clk) z;

  RAISE NOTICE 'P1: holder-elsewhere %, of which unbacked % (releasable) and calendar-backed % (must survive)',
               v_elsewhere, v_unbacked, v_backed;
  --: NOT a failure when zero. The state moves every tick; this records the
  --: before-picture in the migration that changed it, which is the point.
END $p1$;

-- ══ PART A. THE RECLAIMER, WITH THE THIRD CLASS AND A THIRD BUCKET ══════════
-- Derived verbatim from pg_get_functiondef with seven edits, each asserted unique
-- before substitution. The three buckets are bucketed FIRST-TRUE in the order
-- unusable_holder -> sim_expired -> unbacked_orphan, so they sum to `released`
-- exactly -- the property 0341 had to retrofit into a view that lacked it.
CREATE OR REPLACE FUNCTION public.ottoq_release_unusable_reservations(p_sim_run_id uuid, p_sim_clock timestamp with time zone DEFAULT NULL::timestamp with time zone, p_depot_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_clock     timestamptz;
  v_depot     uuid;
  v_eligible  bigint := 0;
  v_by_state  bigint := 0;
  v_by_expiry bigint := 0;
  v_by_orphan bigint := 0;  /* 0369 */
  v_rec       RECORD;
BEGIN
  --: NEVER now(). reservation_expires_at is a SIM-clock column (G77), and the
  --: fallback chain ends at the run's own start rather than a wall clock -- the
  --: pattern 0357 installed in ottoq_sim_release_depot.
  SELECT COALESCE(p_sim_clock, r.sim_clock_current, r.sim_clock_start),
         COALESCE(p_depot_id, r.depot_id)
    INTO v_clock, v_depot
    FROM public.ottoq_sim_runs r
   WHERE r.sim_run_id = p_sim_run_id;

  v_clock := COALESCE(v_clock, p_sim_clock);
  v_depot := COALESCE(v_depot, p_depot_id);

  --: Refuse rather than guess. A reclaimer that cannot establish its own clock
  --: or scope must do nothing: releasing on a guessed clock is G77 again.
  IF v_clock IS NULL OR v_depot IS NULL THEN
    RETURN jsonb_build_object(
      'ok', false, 'released', 0, 'eligible', 0,
      'reason', 'no sim clock or depot resolvable; refusing to guess');
  END IF;

  --: 0367: counted WITHOUT a lock, so "nothing to do" and "could take nothing"
  --: are different numbers. 0360 could not tell them apart and therefore
  --: reported a deadlock as silence.
  SELECT count(*) INTO v_eligible
    FROM public.stalls s
    LEFT JOIN public.vehicles v ON v.id = s.reserved_by
   WHERE s.depot_id = v_depot
     AND s.reserved_by IS NOT NULL
     AND s.current_vehicle_id IS DISTINCT FROM s.reserved_by
     AND ( v.current_state::text = ANY (ARRAY['tow_requested','staged_for_departure',
                                              'en_route_to_deployment','out_of_service'])
        OR (s.reservation_expires_at IS NOT NULL AND s.reservation_expires_at < v_clock)
        --: 0369 (G84): THE UNBACKED ORPHAN. A vehicle physically sitting in stall A
        --: cannot also occupy stall B, so its unexpired hold on B is dead weight --
        --: UNLESS the calendar says otherwise, which is the whole safety of this
        --: class. A held/active booking for that holder on that stall is a real
        --: forward plan (charge now, staging place when done) and is never touched.
        --: Measured on run 5b37ee46: of 50 reserved-empty unexpired stalls, 36 were
        --: held by a vehicle sitting elsewhere; of those, 21 had NO booking
        --: (releasable) against 15 that did (legitimate plans). Releasing on
        --: "holder elsewhere" alone would have destroyed those 15.
        OR ( p_sim_run_id IS NOT NULL
            --: GUARD, AND IT IS NOT OPTIONAL. ottoq_stall_bookings.sim_run_id is
            --: NOT NULL, so on a production call (p_sim_run_id IS NULL) the booking
            --: test below could never find a row and EVERY held stall would look
            --: unbacked. This class is twin-scoped until production bookings exist
            --: to test against.
            AND EXISTS (SELECT 1 FROM public.stalls s_in
                         WHERE s_in.current_vehicle_id = s.reserved_by
                           AND s_in.id <> s.id)
            AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                             WHERE b.sim_run_id = p_sim_run_id
                               AND b.stall_id   = s.id
                               AND b.vehicle_id = s.reserved_by
                               AND b.state IN ('held','active')) ) );

  --: SKIP LOCKED is the whole deadlock fix. Ordered by id so the lock order is
  --: at least stable for anything else that adopts the same order.
  FOR v_rec IN
    SELECT s.id AS stall_id,
           (v.current_state::text = ANY (ARRAY['tow_requested','staged_for_departure',
                                               'en_route_to_deployment','out_of_service'])) AS unusable_holder,
           (s.reservation_expires_at IS NOT NULL
            AND s.reservation_expires_at < v_clock) AS sim_expired  /* 0369 */
      FROM public.stalls s
      LEFT JOIN public.vehicles v ON v.id = s.reserved_by
     WHERE s.depot_id = v_depot
       AND s.reserved_by IS NOT NULL
       --: THE SAFETY INVARIANT. A stall whose holder is physically in it is never
       --: released -- that would desync the calendar from physical reality, and
       --: both sides of that pair are load-bearing (CLAUDE.md rule 6).
       AND s.current_vehicle_id IS DISTINCT FROM s.reserved_by
       AND ( v.current_state::text = ANY (ARRAY['tow_requested','staged_for_departure',
                                                'en_route_to_deployment','out_of_service'])
          OR (s.reservation_expires_at IS NOT NULL AND s.reservation_expires_at < v_clock)
          OR ( p_sim_run_id IS NOT NULL
            --: GUARD, AND IT IS NOT OPTIONAL. ottoq_stall_bookings.sim_run_id is
            --: NOT NULL, so on a production call (p_sim_run_id IS NULL) the booking
            --: test below could never find a row and EVERY held stall would look
            --: unbacked. This class is twin-scoped until production bookings exist
            --: to test against.
            AND EXISTS (SELECT 1 FROM public.stalls s_in
                         WHERE s_in.current_vehicle_id = s.reserved_by
                           AND s_in.id <> s.id)
            AND NOT EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                             WHERE b.sim_run_id = p_sim_run_id
                               AND b.stall_id   = s.id
                               AND b.vehicle_id = s.reserved_by
                               AND b.state IN ('held','active')) ) )
     ORDER BY s.id
     FOR UPDATE OF s SKIP LOCKED
  LOOP
    UPDATE public.stalls s
       SET reserved_by            = NULL,
           reserved_at            = NULL,
           reservation_expires_at = NULL
     WHERE s.id = v_rec.stall_id;

    --: FIRST-TRUE, in this order, so the three buckets sum to `released` with no
    --: double count -- the property 0341 had to retrofit into a view that lacked it.
    IF v_rec.unusable_holder THEN
      v_by_state := v_by_state + 1;
    ELSIF v_rec.sim_expired THEN
      v_by_expiry := v_by_expiry + 1;
    ELSE
      v_by_orphan := v_by_orphan + 1;
    END IF;
  END LOOP;

  --: THE ALARM. Eligible rows that none of which could be taken is the state
  --: 0360 could not report, and the state it was actually in for its whole life.
  IF v_eligible > 0 AND (v_by_state + v_by_expiry + v_by_orphan) = 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type   := 'ottoq_engine',
        p_actor_id     := 'reservation_reclaimer',
        p_event_type   := 'ottoq.reservation_reclaim_blocked',
        p_entity_type  := 'depot',
        p_entity_id    := v_depot,
        p_depot_id     := v_depot,
        p_payload      := jsonb_build_object('eligible', v_eligible, 'released', 0,
                                            'sim_clock', v_clock),
        p_severity     := 'warning',
        p_ingest_source := 'production',
        p_data_source  := CASE WHEN p_sim_run_id IS NULL THEN 'production' ELSE 'twin' END,
        p_sim_run_id   := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  RETURN jsonb_build_object(
    'ok',                 true,
    'eligible',           v_eligible,
    'released',           v_by_state + v_by_expiry + v_by_orphan,
    'skipped_locked',     GREATEST(v_eligible - (v_by_state + v_by_expiry + v_by_orphan), 0),
    'by_unusable_holder', v_by_state,
    'by_sim_expiry',      v_by_expiry,
    'by_unbacked_orphan', v_by_orphan,
    'sim_clock',          v_clock,
    'depot_id',           v_depot);

--: Total on its own account, not only behind the caller's handler. On the tick
--: path an unhandled error rolls back the whole tick and cron still reads
--: "succeeded" (APPLYING.md).
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'released', 0, 'eligible', v_eligible,
    'sqlstate', SQLSTATE, 'msg', left(SQLERRM, 200));
END;
$function$
;

-- ══ P9. POST-ASSERTIONS ═════════════════════════════════════════════════════
DO $p9$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_release_unusable_reservations';
  IF position('v_by_orphan' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: the orphan bucket is missing -- Part A did not take';
  END IF;
  --: THE GUARD. Without it a production call strips the whole site.
  IF position('p_sim_run_id IS NOT NULL' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: the production guard is missing -- refuse to ship this';
  END IF;
  IF position('b.state IN (''held'',''active'')' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: the calendar-backed exemption is missing -- this would destroy real plans';
  END IF;
  --: everything 0367 established must survive
  IF position('SKIP LOCKED' in v_src) = 0
     OR position('current_vehicle_id IS DISTINCT FROM s.reserved_by' in v_src) = 0
     OR position('ottoq.reservation_reclaim_blocked' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: the patch lost SKIP LOCKED, the safety invariant, or the alarm';
  END IF;
  RAISE NOTICE 'P9 ok: three classes, three buckets, production guarded, calendar-backed plans exempt';
END $p9$;

COMMENT ON FUNCTION public.ottoq_release_unusable_reservations(uuid, timestamptz, uuid) IS
'0360/0367/0369. Releases stall reservations in three classes, bucketed first-true '
'so by_unusable_holder + by_sim_expiry + by_unbacked_orphan = released exactly: '
'(1) the holder can no longer consume it (tow_requested / staged_for_departure / '
'en_route_to_deployment / out_of_service); (2) it is past reservation_expires_at ON '
'THE SIM CLOCK; (3) 0369 -- the holder is physically sitting in a DIFFERENT stall '
'AND the calendar holds no held/active booking for that holder on this stall. Class '
'3 is gated on p_sim_run_id IS NOT NULL because ottoq_stall_bookings.sim_run_id is '
'NOT NULL and a production call would otherwise see every hold as unbacked. Never '
'releases a stall whose reservation holder is physically in it. Takes rows FOR '
'UPDATE SKIP LOCKED so it can never be a deadlock participant; contended rows are '
'counted in skipped_locked and left for the next tick. Emits '
'ottoq.reservation_reclaim_blocked when eligible > 0 and released = 0. Called from '
'ottoq_sim_decide_and_dispatch, above the policy branch, so every arm of an A/B '
'gets the same world.';

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
-- Written HERE and not only through a side call, which is why CI went red five ways
-- on this branch: tests/test_migration_hygiene.py reads the FILE, and
-- ottoq_cert_recert_floor() treats a migration with no lineage row as forcing a
-- recert, so a missing INSERT restarts every certification column's streak. The row
-- is already in the database under the unprefixed name; this INSERT carries the
-- current PREFIXED convention and ON CONFLICT keeps them one row rather than two.
-- Both join correctly either way -- 0226 strips the NNNN_ prefix from both sides.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0369_a_vehicle_parked_in_one_stall_was_still_holding_another', true,
  'Engine: ottoq_release_unusable_reservations gains a third release class -- the '
  'unbacked orphan, where the reservation holder is physically sitting in a different '
  'stall AND the calendar holds no held/active booking for that holder on the reserved '
  'stall. Measured on run 5b37ee46: of 50 reserved-empty unexpired stalls, 36 were held '
  'by a vehicle sitting elsewhere, 21 of those unbacked (releasable) and 15 '
  'calendar-backed (legitimate forward plans that must survive). Gated on p_sim_run_id IS '
  'NOT NULL because ottoq_stall_bookings.sim_run_id is NOT NULL and a production call '
  'would otherwise see every hold as unbacked. Three buckets are first-true so they sum '
  'to released. Changes which stalls are free on every tick, so it invalidates canons.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
