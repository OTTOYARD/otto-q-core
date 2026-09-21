-- migration-version: 20260920045844
-- migration-name:    the_shared_candidate_source_offered_charge_stalls_whose_charger_was_faulted
-- ════════════════════════════════════════════════════════════════════════════
-- 0372  THE SHARED CANDIDATE SOURCE OFFERED CHARGE STALLS WHOSE CHARGER WAS
--       FAULTED, AND CP-SAT IS WHAT NOTICED.
--
--       forces_recert TRUE -- it changes the candidate set every proposer sees.
-- ════════════════════════════════════════════════════════════════════════════
--
-- G88, and it was found by two instruments built in the last hour rather than by
-- reading code.
--
-- **THE SOLVER NOTICED FIRST.** The matched-frame comparison (`db/checks/0264`) ran
-- CP-SAT on four consecutive frames of the live run. It declined all four with
-- *"frame has 40 charge-capable stall(s) and not one is offerable this tick (N
-- charger_faulted, M occupied, K reserved)"* — while our own pointer census in the
-- same capture reported **4 charge stalls free**. Both were right: the four
-- pointer-free charge stalls were exactly the ones whose OCPP charger was `Faulted`.
-- CP-SAT checks charger health. The SQL path did not.
--
-- **THE COVERAGE GUARD FOUND THE REST.** `scripts/coverage-guard.sql`, written
-- tonight to mechanise BUILD_QUEUE's "look for what exists and is never called",
-- flagged `ottoq.ottoq_replan_after_charger_fault` as reachable only through a
-- function that nothing on the live path calls. Tracing it out:
--
--   * `ottoq.ottoq_replan_after_charger_fault` **does** check
--     `c2.station_state = 'Available'` when picking a replacement stall, goes through
--     `ottoq_indepot_reassignment_guard`, and falls back to temp-staging so a
--     displaced vehicle is never stranded. It is the right routine.
--   * Its only caller is `twin.ottoq_report_charger_fault`, whose `p_actor` defaults
--     to `'depot_tech'` and which `scenarios/mid_session_charger_fault.json` lists as
--     one of three **manual** fault-injection forms. So it is an operator entry
--     point, correctly not on the tick path -- **and therefore the twin's own 18
--     charger faults on this run never reached the charger-aware replan.**
--   * What carries them instead is the generic stranded-undercharge sweep. Measured
--     across five placement routines, only ONE consults charger health:
--
--       public.ottoq_l2_optimize_assignments      station_state ✓  chargers ✓
--       ottoq.ottoq_stall_free_between            ✗  ✗   <- the shared candidate source
--       ottoq.ottoq_react_to_refusals             ✗  ✗   <- the reroute walk
--       ottoq.ottoq_replan_stranded_undercharge   ✗  ✗   <- what actually carries faults
--       public.ottoq_release_unusable_reservations ✗ ✗   (places nothing; fine)
--
-- So the kernel's local optimizer was the only thing protecting the site from
-- offering a dead charger, and every proposer plus the reroute loop went through a
-- candidate source that did not.
--
-- **WHY THIS IS NOT A SAFETY INCIDENT, STATED BEFORE THE FIX.** `HW.002.charger_state_precondition`
-- (`critical`) requires `station_state='Available'` before a charging task begins and
-- is evaluated at the `stall_assignment` probe — 113 times on this run with **0
-- failures**, consistent with the local optimizer pre-filtering. Nothing charged
-- through a faulted charger. The exposure is narrower and real: **the reroute path
-- books through `ottoq_book_stall` directly rather than through `ottoq_decide_tick`,
-- so a reroute onto a faulted-charger stall faces neither the pre-filter nor the
-- probe.** On this run reroutes were overwhelmingly `staging` (8 `l2` and 1 `dcfc`
-- out of 90), so the live exposure is small — which is the argument for fixing it
-- now, while it is small, rather than the argument for leaving it.
--
-- The fix is one predicate in the shared source, scoped to charge types, matching
-- what the two charger-aware routines already do.

-- ══ P0. THE FUNCTION IS AS READ, AND DOES NOT ALREADY CHECK ══════════════════
DO $p0$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_stall_free_between';
  IF v_src IS NULL THEN RAISE EXCEPTION 'P0: ottoq_stall_free_between not found'; END IF;
  IF position('ottoq_ocpp_chargers' in v_src) > 0 THEN
    RAISE EXCEPTION 'P0: it already consults the charger table -- 0372 has been applied';
  END IF;
  --: the two properties this patch must not disturb
  IF position('''maintenance'',''closed''' in replace(v_src, ' ', '')) = 0 THEN
    RAISE EXCEPTION 'P0: the maintenance/closed filter is not where this patch expects it';
  END IF;
  IF position('''held'',''active'',''done'',''interrupted''' in replace(v_src, ' ', '')) = 0 THEN
    RAISE EXCEPTION 'P0: the calendar state set has changed; re-derive Part A before applying';
  END IF;
  RAISE NOTICE 'P0 ok';
END $p0$;

-- ══ P1. HOW MANY STALLS THIS REMOVES RIGHT NOW ══════════════════════════════
DO $p1$
DECLARE v_faulted bigint; v_free_and_faulted bigint;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE s.current_vehicle_id IS NULL
                            AND s.reserved_by IS NULL
                            AND s.status = 'available')
    INTO v_faulted, v_free_and_faulted
    FROM public.stalls s
    JOIN public.ottoq_ocpp_chargers ch ON ch.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
     AND s.stall_type::text IN ('dcfc','l2')
     AND ch.station_state = 'Faulted';
  --: NOT a failure at zero; faults come and go on a ~115-minute repair cycle.
  RAISE NOTICE 'P1: charge stalls with a Faulted charger = % (of which % read free by the pointer and would have been offered)',
               v_faulted, v_free_and_faulted;
END $p1$;

-- ══ PART A. THE SHARED CANDIDATE SOURCE, CHARGER-AWARE ══════════════════════
-- Derived verbatim from pg_get_functiondef with ONE predicate inserted after the
-- zone filter. Nothing else changes: the calendar state set, the occupancy guard,
-- the ordering and the limit are untouched.
CREATE OR REPLACE FUNCTION ottoq.ottoq_stall_free_between(p_sim_run_id uuid, p_depot_id uuid, p_from timestamp with time zone, p_to timestamp with time zone, p_stall_type text DEFAULT NULL::text, p_staging_role text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_zones text[] DEFAULT NULL::text[])
 RETURNS TABLE(stall_id uuid, stall_code text, stall_type text, staging_role text, zone text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  WITH g AS MATERIALIZED (
    SELECT
      (public.ottoq_policy_get(p_sim_run_id, 'calendar_occupancy_guard', 0) >= 1) AS guard_on,
      GREATEST(public.ottoq_policy_get(p_sim_run_id, 'occupied_stall_horizon_min',     45), 1) AS horizon_min,
      GREATEST(public.ottoq_policy_get(p_sim_run_id, 'occupied_stall_horizon_max_min', 240), 1) AS horizon_max_min,
      COALESCE((SELECT r.sim_clock_current FROM public.ottoq_sim_runs r
                 WHERE r.sim_run_id = p_sim_run_id), p_from) AS now_sim
  )
  SELECT s.id, s.stall_code, s.stall_type::text, s.staging_role, s.zone
  FROM public.stalls s CROSS JOIN g
  WHERE s.depot_id = p_depot_id
    AND s.status NOT IN ('maintenance','closed')
    AND (p_stall_type   IS NULL OR s.stall_type::text = p_stall_type)
    AND (p_staging_role IS NULL OR s.staging_role     = p_staging_role)
    AND (p_zones        IS NULL OR s.zone             = ANY (p_zones))
    -- ══════════════════ 0372 (G88): CHARGER HEALTH IS THE THIRD GATE ══════════════════
    -- A charge stall whose OCPP charger reports 'Faulted' cannot charge, so offering it
    -- is never correct -- and this function is the SHARED candidate source for every
    -- proposer and for ottoq.ottoq_react_to_refusals' reroute walk. Before this it
    -- checked the stall's own `status` and the calendar and not the charger, so a
    -- faulted-charger stall read as available: CP-SAT declined a frame where our own
    -- pointer census said 4 charge stalls were free, and all four were the faulted ones
    -- (db/checks/0264 §2). The only two routines that DID check are
    -- ottoq_l2_optimize_assignments and ottoq_replan_after_charger_fault, and the
    -- second is reachable only from a human-reported fault.
    -- Scoped to charge types on purpose: a staging stall has no charger to fault, and a
    -- wash or service bay is gated by its own status. Heartbeat freshness is NOT checked
    -- here even though HW.002 requires it, because that needs a staleness threshold this
    -- function has no business choosing; every charger on the twin depot currently
    -- reports a heartbeat, so the omission changes nothing today and is named rather
    -- than hidden.
    AND NOT (
          s.stall_type::text IN ('dcfc','l2')
      AND EXISTS (SELECT 1 FROM public.ottoq_ocpp_chargers ch
                   WHERE ch.charger_id   = s.ocpp_charger_id
                     AND ch.station_state = 'Faulted')
    )
    -- ══════════════════ CALENDAR READ — MUST MATCH THE CONSTRAINT ══════════════════
    -- 2026-08-03 (P1): state set aligned to ottoq_stall_bookings_no_overlap_v3:
    -- held / active / done / interrupted. Any divergence between what the picker
    -- treats as busy and what the database refuses to double-book turns straight back
    -- into silent oversubscription (the 2026-08-02 finding: picker read held/active,
    -- which had been emptied every tick, so 22 vehicles were booked into ONE bay).
    -- 'done' and 'interrupted' are REAL past occupancy. Both are safe to include only
    -- because every close path TRUNCATES `during` to the true end of occupancy --
    -- verified 2026-08-03: 40 of 40 interrupted rows have upper(during) <= released_at,
    -- phantom tail 0.00 min -- so neither can block a window the vehicle did not use.
    -- 'released' / 'superseded' mean the occupancy never happened and remain invisible.
    AND NOT EXISTS (
      SELECT 1 FROM public.ottoq_stall_bookings b
      WHERE b.stall_id   = s.id
        AND b.sim_run_id = p_sim_run_id
        AND b.state IN ('held','active','done','interrupted')
        AND b.during && tstzrange(p_from, p_to, '[)')
    )
    -- ============================ OCCUPANCY GUARD ============================
    AND (
      NOT g.guard_on
      OR s.current_vehicle_id IS NULL
      OR NOT (
           tstzrange(
             g.now_sim,
             GREATEST(
               g.now_sim + interval '1 second',
               LEAST(
                 COALESCE(
                   (SELECT min(l.planned_end_sim)
                      FROM public.ottoq_itinerary_legs l
                     WHERE l.sim_run_id       = p_sim_run_id
                       AND l.vehicle_id       = s.current_vehicle_id
                       AND l.to_stall_id      = s.id
                       AND l.status IN ('planned','active','in_progress')
                       AND l.planned_end_sim  > g.now_sim),
                   g.now_sim + make_interval(mins => g.horizon_min::int)),
                 g.now_sim + make_interval(mins => g.horizon_max_min::int))
             ), '[)')
           && tstzrange(p_from, p_to, '[)')
         )
    )
  ORDER BY s.distance_from_entrance NULLS LAST, s.stall_code
  LIMIT GREATEST(p_limit, 1)
$function$
;

-- ══ P9. POST-ASSERTIONS ═════════════════════════════════════════════════════
DO $p9$
DECLARE v_src text; v_exec text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'ottoq' AND p.proname = 'ottoq_stall_free_between';
  --: comment-stripped, per 0371's lesson: Part A's own comment names the table
  SELECT string_agg(l, E'\n') INTO v_exec
    FROM unnest(string_to_array(v_src, E'\n')) AS t(l)
   WHERE ltrim(l) NOT LIKE '--%';

  IF position('ottoq_ocpp_chargers' in v_exec) = 0 THEN
    RAISE EXCEPTION 'P9: the charger predicate is not in the executable body -- Part A did not take';
  END IF;
  IF position('Faulted' in v_exec) = 0 THEN
    RAISE EXCEPTION 'P9: the Faulted test is missing';
  END IF;
  --: scoped to charge types, or it would silently change staging behaviour
  IF position('''dcfc'', ''l2''' in v_exec) = 0 AND position('''dcfc'',''l2''' in replace(v_exec,' ','')) = 0 THEN
    RAISE EXCEPTION 'P9: the predicate is not scoped to charge stall types';
  END IF;
  --: everything the picker already guaranteed must survive
  IF position('maintenance' in v_exec) = 0
     OR position('interrupted' in v_exec) = 0
     OR position('calendar_occupancy_guard' in v_exec) = 0
     OR position('distance_from_entrance' in v_exec) = 0 THEN
    RAISE EXCEPTION 'P9: the patch lost the status filter, the calendar state set, the occupancy guard, or the ordering';
  END IF;
  RAISE NOTICE 'P9 ok: charger-aware, scoped to charge types, every prior guarantee intact';
END $p9$;

COMMENT ON FUNCTION ottoq.ottoq_stall_free_between(uuid, uuid, timestamptz, timestamptz, text, text, integer, text[]) IS
'THE SHARED CANDIDATE SOURCE. Returns stalls free over [p_from, p_to) for a depot, '
'optionally filtered by stall type, staging role and zone. Three gates, and all three '
'are load-bearing: the stall''s own status (never maintenance or closed), the CALENDAR '
'(no ottoq_stall_bookings row in held/active/done/interrupted overlapping the window -- '
'this set must match ottoq_stall_bookings_no_overlap_v3 exactly or oversubscription '
'returns), and 0372: for dcfc/l2 stalls, the OCPP charger must not be Faulted. That '
'third gate exists because CP-SAT declined a frame our own pointer census called 4-free '
'and was right -- all four were faulted (db/checks/0264). Heartbeat freshness is not '
'checked here although HW.002 requires it; that needs a staleness threshold this '
'function should not choose. The occupancy guard (calendar_occupancy_guard policy) '
'additionally excludes a stall a vehicle is physically in for the horizon it is '
'expected to stay. Ordered by distance from the entrance, then stall code.';

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
-- Written HERE and not only through a side call, which is why CI went red five ways
-- on this branch: tests/test_migration_hygiene.py reads the FILE, and
-- ottoq_cert_recert_floor() treats a migration with no lineage row as forcing a
-- recert, so a missing INSERT restarts every certification column's streak. The row
-- is already in the database under the unprefixed name; this INSERT carries the
-- current PREFIXED convention and ON CONFLICT keeps them one row rather than two.
-- Both join correctly either way -- 0226 strips the NNNN_ prefix from both sides.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0372_the_shared_candidate_source_offered_charge_stalls_whose_charger_was_faulted', true,
  'Engine: ottoq.ottoq_stall_free_between, the shared candidate source for every proposer '
  'and for the reroute walk, now excludes dcfc/l2 stalls whose OCPP charger reports '
  'Faulted. Found because CP-SAT declined four matched frames as having no offerable '
  'charge stall while our own pointer census reported 4 free -- the four were the faulted '
  'ones (db/checks/0264). Of five placement routines only ottoq_l2_optimize_assignments '
  'consulted charger health; ottoq_replan_after_charger_fault does too but is reachable '
  'only from a human-reported fault, so the twin''s own 18 faults never reached it. '
  'Heartbeat freshness deliberately not checked. Changes the candidate set every proposer '
  'sees, so it invalidates canons.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
