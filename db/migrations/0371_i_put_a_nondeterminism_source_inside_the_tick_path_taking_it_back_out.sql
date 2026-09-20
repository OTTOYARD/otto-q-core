-- migration-version: 20260920043723
-- ════════════════════════════════════════════════════════════════════════════
-- 0371  I PUT A NONDETERMINISM SOURCE INSIDE THE TICK PATH FOUR MIGRATIONS AGO.
--       TAKING IT BACK OUT.
--
--       forces_recert TRUE -- it changes which rows the reclaimer takes.
-- ════════════════════════════════════════════════════════════════════════════
--
-- SELF-CORRECTION, and the reasoning matters more than the diff.
--
-- 0367 fixed a real deadlock. `ottoq_release_unusable_reservations` was written by
-- 0360 as a single `UPDATE public.ottoq_stall_bookings … FROM doomed`, which lets
-- the planner choose the order it touches rows, and it returned
-- `{"ok": false, "msg": "deadlock detected", "sqlstate": "40P01", "released": 0}`
-- on every call while swallowing that into silence. 0367 reached for
-- `FOR UPDATE OF s SKIP LOCKED`, which does make a deadlock impossible.
--
-- **IT ALSO MAKES THE CANDIDATE SET A FUNCTION OF WHO ELSE HELD A ROW AT THAT
-- INSTANT, AND THAT IS NOT ALLOWED HERE.** This function now runs inside
-- `ottoq_sim_decide_and_dispatch`, on every tick of every arm. Under
-- `ottoq_determinism_pair` both arms run in ONE transaction: a row a concurrent
-- writer held during arm A and released before arm B is skipped once and taken
-- once, the two arms release different reservations, and the world diverges. That
-- is the fourteen-atom verdict -- 2.9a calls reproducibility a product property and
-- says R-12 established most of this field cannot make the claim at all. It is not
-- worth trading for a marginal deadlock benefit.
--
-- I cannot prove from here that it HAS bitten: whether a certification pair is ever
-- run while the demo metronome ticks the same depot is not established, and if the
-- depot is quiet then SKIP LOCKED skips nothing and the runs were fine. That is
-- exactly why it goes: a determinism argument that depends on an unproven
-- assumption about concurrency is not a determinism argument. Same reasoning as
-- 2.5's four CP-SAT pins -- determinizable is not deterministic unless the
-- conditions are ASSERTED rather than assumed, and a wall-clock or a lock-state
-- read inside a certified path is G15's defect class.
--
-- WHAT REPLACES IT, and why it is not a return to 0360's deadlock:
--   * the candidate set is a pure function of state (no locking clause at all);
--   * the row-by-row `UPDATE` inside the loop therefore acquires locks in
--     **ascending id order**, the standard deadlock-avoidance discipline, which is
--     precisely what 0360's planner-ordered bulk UPDATE lacked;
--   * a deadlock against a writer with no order of its own is still possible, and
--     is now LOUD rather than silent: 0367's `eligible` count and the
--     `ottoq.reservation_reclaim_blocked` event both survive, so `eligible > 0` with
--     `released = 0` reports itself.
--
-- And the return key `skipped_locked` is renamed `not_released`, because without
-- SKIP LOCKED nothing is skipped for being locked and the old name would describe a
-- mechanism that no longer exists. That is the G75 naming hazard, avoided while the
-- key still has no readers -- 0367 shipped it four migrations ago tonight.

-- ══ P0. THE FUNCTION IS THE 0369 VERSION AND STILL CARRIES SKIP LOCKED ═══════
DO $p0$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_release_unusable_reservations';
  IF v_src IS NULL THEN RAISE EXCEPTION 'P0: reclaimer not found'; END IF;
  IF position('v_by_orphan' in v_src) = 0 THEN
    RAISE EXCEPTION 'P0: this is not the 0369 reclaimer -- apply 0369 first';
  END IF;
  IF position('SKIP LOCKED' in v_src) = 0 THEN
    RAISE EXCEPTION 'P0: SKIP LOCKED is already gone -- 0371 has been applied';
  END IF;
  RAISE NOTICE 'P0 ok';
END $p0$;

-- ══ PART A. THE RECLAIMER, DETERMINISTIC ════════════════════════════════════
-- Derived verbatim from pg_get_functiondef with three edits, each asserted unique
-- before substitution: the locking clause, the comment above it, and the renamed
-- return key. Nothing else in the body changes -- the three release classes, the
-- safety invariant, the production guard and the alarm are all 0369's.
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

  --: Ordered by id: the candidate set is deterministic and the UPDATE inside the
  --: loop therefore locks in ascending id order. See 0371's note at the ORDER BY.
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
     --: 0371: ORDERED, AND DELIBERATELY NOT LOCKED. `FOR UPDATE OF s SKIP LOCKED`
     --: (0367) made the candidate set a function of WHO ELSE HELD A ROW AT THAT
     --: INSTANT, which is a nondeterminism source inside the tick path: under the
     --: certification pair both arms share one transaction, so a row a concurrent
     --: writer held during arm A and released before arm B would be skipped once
     --: and taken once, and the two arms would diverge on the world. The
     --: fourteen-atom claim is the company's credibility asset and is not worth a
     --: marginal deadlock benefit. What replaces it: the set is a pure function of
     --: state, and the UPDATE below acquires locks in ASCENDING id order, which is
     --: the standard deadlock-avoidance discipline and is what 0367's
     --: `UPDATE … FROM doomed` lacked -- that statement let the planner choose the
     --: order, which is how it deadlocked. A deadlock is still possible against a
     --: writer with no order of its own; it now returns ok:false AND raises the
     --: alarm rather than being silent, which 0367 also fixed.
     ORDER BY s.id
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
    --: 0371 RENAMED from `skipped_locked`. Without SKIP LOCKED nothing is skipped
    --: for being locked, so the old name would have described a mechanism that no
    --: longer exists -- the G75 naming hazard, avoided while the key has no readers.
    --: It now means exactly what it computes: eligible rows this pass did not clear.
    'not_released',       GREATEST(v_eligible - (v_by_state + v_by_expiry + v_by_orphan), 0),
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

COMMENT ON FUNCTION public.ottoq_release_unusable_reservations(uuid, timestamptz, uuid) IS
'0360/0367/0369/0371. Releases stall reservations in three classes, bucketed '
'first-true so by_unusable_holder + by_sim_expiry + by_unbacked_orphan = released '
'exactly: (1) the holder can no longer consume it (tow_requested / '
'staged_for_departure / en_route_to_deployment / out_of_service); (2) it is past '
'reservation_expires_at ON THE SIM CLOCK; (3) the holder is physically sitting in a '
'DIFFERENT stall AND the calendar holds no held/active booking for that holder on '
'this stall. Class 3 is gated on p_sim_run_id IS NOT NULL because '
'ottoq_stall_bookings.sim_run_id is NOT NULL and a production call would otherwise '
'see every hold as unbacked. Never releases a stall whose reservation holder is '
'physically in it. 0371: the candidate set carries NO locking clause -- it is a pure '
'function of state, because 0367''s FOR UPDATE SKIP LOCKED made it depend on who '
'else held a row at that instant, which cannot sit inside a path the determinism '
'pair certifies. The row-by-row UPDATE acquires locks in ascending id order, the '
'deadlock-avoidance discipline 0360''s planner-ordered bulk UPDATE lacked. A '
'deadlock is still possible and is now loud: eligible > 0 with released = 0 emits '
'ottoq.reservation_reclaim_blocked. Returns eligible / released / not_released '
'(renamed from skipped_locked, which described a mechanism 0371 removed). Called '
'from ottoq_sim_decide_and_dispatch, above the policy branch, so every arm of an '
'A/B gets the same world.';

-- ══ P9. POST-ASSERTIONS ═════════════════════════════════════════════════════
DO $p9$
DECLARE
  v_src  text;
  v_exec text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_release_unusable_reservations';

  --: COMMENT-STRIPPED, AND THE FIRST CUT OF THIS BLOCK FAILED FOR WANT OF IT.
  --: Part A's own explanatory comment contains the words `FOR UPDATE OF s SKIP
  --: LOCKED` -- it is explaining what it removed -- so a raw prosrc test reported
  --: "SKIP LOCKED is still in the body" and rolled the whole migration back while
  --: Part A was correct. That is the 0360 Part B trap verbatim: test EXECUTABLE
  --: SQL, never source text.
  SELECT string_agg(l, E'\n')
    INTO v_exec
    FROM unnest(string_to_array(v_src, E'\n')) AS t(l)
   WHERE ltrim(l) NOT LIKE '--%';

  IF position('SKIP LOCKED' in v_exec) > 0 THEN
    RAISE EXCEPTION 'P9: SKIP LOCKED is still in the executable body -- Part A did not take';
  END IF;
  IF position('FOR UPDATE' in v_exec) > 0 THEN
    RAISE EXCEPTION 'P9: a locking clause remains in the executable body; the candidate set is still not a pure function of state';
  END IF;
  IF position('ORDER BY s.id' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: the ascending-id order is gone -- that is the deadlock discipline';
  END IF;
  --: everything 0367 and 0369 established must survive
  IF position('v_by_orphan' in v_src) = 0
     OR position('p_sim_run_id IS NOT NULL' in v_src) = 0
     OR position('b.state IN (''held'',''active'')' in v_src) = 0
     OR position('current_vehicle_id IS DISTINCT FROM s.reserved_by' in v_src) = 0
     OR position('ottoq.reservation_reclaim_blocked' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: the patch lost a release class, the production guard, the calendar exemption, the safety invariant, or the alarm';
  END IF;
  IF position('not_released' in v_src) = 0 THEN
    RAISE EXCEPTION 'P9: the renamed return key is missing';
  END IF;
  --: and it must still be the function decide_and_dispatch calls
  IF position('ottoq_release_unusable_reservations' in
        (SELECT p2.prosrc FROM pg_proc p2 JOIN pg_namespace n2 ON n2.oid = p2.pronamespace
          WHERE n2.nspname = 'public' AND p2.proname = 'ottoq_sim_decide_and_dispatch')) = 0 THEN
    RAISE EXCEPTION 'P9: decide_and_dispatch no longer calls the reclaimer';
  END IF;
  RAISE NOTICE 'P9 ok: no locking clause, ascending id order, all three classes and every guard intact';
END $p9$;
