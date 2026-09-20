-- migration-version: PENDING
-- migration-name:    a_stall_reservation_outlives_the_vehicle_that_can_no_longer_use_it
--
-- 0360  THE DEPOT IS 98% RESERVED AND 13% OCCUPIED. NOTHING RELEASES A
--       RESERVATION WHEN ITS HOLDER CAN NO LONGER USE IT.
--
-- Fixes G76 and, in the same file and deliberately, G77 -- because G77 is the
-- landmine directly under G76's obvious fix and shipping one without the other
-- would leave a loaded gun pointed at the stall calendar.
--
-- ══ 1. WHAT WAS MEASURED ═══════════════════════════════════════════════════
--
-- Live run `f14d5620` (busy_day, twin depot, rule 8), depot-wide over all 158
-- stalls: **155 carry a reservation, 21 hold a vehicle, 135 are reserved AND
-- empty, and only 2 are unclaimed by anything.** A proposer's legal move set is
-- ~1% of the site while 87% of the site is physically free.
--
-- The slice that matters most is the one CLAUDE.md rule 8 calls the pressure
-- valve: **113 staging stalls, all 113 reserved, 4 occupied.** And on the 40
-- charge stalls, 40 of 40 reserved with **zero truly free**.
--
-- Of those charge-stall reservations, 8 (all L2) were held by vehicles that
-- cannot drive to them -- 6 `tow_requested`, 2 `staged_for_departure` -- and
-- **no routine in this database mentions both `tow_requested` and
-- `reserved_by`** (position() over every prosrc, not LIKE: `_` is a wildcard).
--
-- It ACCUMULATES rather than holding steady, which is what makes it a leak
-- rather than a regime. Sampled once a minute across ticks 337-373, the
-- dead-weight count went **7 -> 9 -> 9 -> 9 -> 9 -> 11** while `truly_free`
-- stayed 0 of 40 and the CP-SAT bridge returned `status='empty'` on all six.
--
-- ══ 2. WHY THIS IS NOT A SOLVER PROBLEM, WHICH IS THE POINT ════════════════
--
-- Three symptoms were being read as solver quality and all three are this:
--
--   * the CP-SAT bridge abstains with "40 charge-capable stall(s) and not one is
--     offerable this tick (2 charger_faulted, 17 occupied, 21 reserved)" --
--     CORRECTLY. It is the honest proposer here.
--   * cuOpt lands 4 enacted / 7 refused / 60 superseded because it is proposing
--     into a fully pre-committed site, not because its objective is wrong.
--   * Nemotron's objective directive (`readiness_first` / `throughput_first` /
--     `energy_balanced`) is moot when no solver has a legal move.
--
-- **No optimiser can outperform another when neither has an admissible action.**
-- That is why this file is worth more than either solver, and why it comes first.
--
-- ══ 3. WHAT IT RELEASES, AND THE STATES IT DELIBERATELY DOES NOT ═══════════
--
-- A reservation is released when its holder is in a state that **cannot
-- possibly consume a depot service reservation**:
--
--     tow_requested          immobilised; it is not driving anywhere
--     staged_for_departure    staged to LEAVE, not to be serviced
--     en_route_to_deployment  already leaving
--     out_of_service          by definition
--
-- Chosen from the full 17-value `vehicle_state` enum, and the exclusions are the
-- substance of the design rather than an oversight:
--
--   * `en_route_to_depot` (29 vehicles) and `arrived_at_gate` -- a pre-arrival
--     reservation is the machinery working; releasing it would break the thing
--     `prearrival_charge_yields_to_solver` exists to protect.
--   * `staged_awaiting_service` (58) -- THIS IS THE GREENLIGHT QUEUE. Releasing
--     it would destroy exactly the staging-buffer behaviour the brief wants.
--   * `in_wash_bay` / `in_detail_bay` / `in_service_bay` -- a vehicle in one bay
--     holding a charge stall for its NEXT leg is a legitimate itinerary. Two such
--     reservations were measured and are left alone.
--   * `offline` (6) and `emergency_staged` (10) -- ambiguous, and a false release
--     costs churn. `offline` in particular could be a comms blip on a vehicle that
--     still intends to use its stall. **Left out on purpose; widen later with
--     evidence, per the measured-before-enforced doctrine of 2.9a.**
--   * `deployed` (67) -- out working. Excluded because a recall may legitimately
--     have reserved ahead of it.
--
-- THE INVARIANT THAT MAKES THIS SAFE: a stall whose holder is physically sitting
-- in it is NEVER released (`current_vehicle_id IS DISTINCT FROM reserved_by`).
-- 38 reservations are protected by that clause today. Without it this function
-- would desynchronise the calendar from physical reality, which is the one thing
-- CLAUDE.md rule 6 says never to do to either side.
--
-- MEASURED EFFECT, depot-scoped, at the moment of writing:
--     reserved stalls                                157
--     releasable by unusable holder                   39
--     releasable by sim-clock expiry                  11   (9 overlap)
--     releasable total                                41   = 26%
--     protected because the holder is in the stall     38
--   by stall type: staging 30 of 113 · l2 10 of 30 · dcfc 1 of 10
--   -- so the charge pool goes from **0 offerable to 11**, which is the whole
--   point: it is the difference between a solver having nothing to decide and
--   having a decision.
--
-- ══ 4. PART B IS G77, AND IT IS THE REASON THIS IS ONE FILE ════════════════
--
-- `ottoq_gc_stale_reservations` is the only pre-existing reclaimer. It clears
-- `reserved_by` where `reservation_expires_at < now()`. That column is written on
-- the **SIM** clock; `now()` is **WALL**. Measured on this run: wall is **4h46m
-- AHEAD** of sim, so of 156 reserved stalls **127 are live against sim and 0
-- against wall -- the function would clear all 156**, including every valid one.
-- Vehicles `staged_awaiting_service` would lose the stall they are queued for.
--
-- It is harmless today only because it is DEAD CODE: zero `cron.job` rows
-- reference it and no routine anywhere calls it. But G76 tells a reader that
-- reservations are not being reclaimed, and a reader who greps for a reaper finds
-- exactly this function and schedules it. **The obvious fix for G76 is the
-- trigger for G77.** So the clock is fixed here, in the same file, and the file
-- is still one concern: *a stall reservation is released when, and only when, it
-- cannot be used.*
--
-- The fix mirrors 0357's treatment of `ottoq_sim_release_depot`: resolve the sim
-- clock from the depot's running run and never fall back to `now()`. Its second
-- arm -- clear when no run is `running` for the depot -- is wall-clock-free and
-- already correct, so it is preserved verbatim. Note the ordering consequence:
-- with no running run the expiry arm can no longer fire, and that is right,
-- because the orphan arm already clears those rows for a better reason.
--
-- ══ 5. WHERE IT IS CALLED, AND WHY THERE ═══════════════════════════════════
--
-- `public.ottoq_sim_advance_tick` (2,426 chars -- small enough to read whole,
-- which is why it was chosen over editing the 83 KB `ottoq_decide_tick`), between
-- `ottoq_sim_advance_tick_world` and `ottoq_sim_decide_and_dispatch`:
--
--   * AFTER the world advances, so the sim clock is the current tick's;
--   * BEFORE the decide pass, so stalls freed this tick are visible to this
--     tick's own assignment and to the proposers, not the next one's.
--
-- Wrapped in `EXCEPTION WHEN OTHERS THEN RAISE WARNING`, matching the idiom this
-- same function already uses twice for its teardown seams. **A failure must never
-- abort decide_tick** (APPLYING.md) -- a rolled-back tick reads as "succeeded" in
-- cron and produces zero stall assignments. The function ALSO carries its own
-- internal exception handler and returns a jsonb `ok:false` rather than raising,
-- so it is a total function on both sides of the seam.
--
-- It returns counts by reason rather than a bare number, so the effect is
-- measurable from the tick rather than inferred -- "no number ships without a
-- run ID", and a reclaimer that cannot say what it reclaimed is not auditable.
--
-- ══ 6. CLASSIFICATION ══════════════════════════════════════════════════════
--
-- `forces_recert: TRUE`. It changes which stalls are free at a given tick, so it
-- changes assignment, bookings, and therefore the fingerprint. Every canon streak
-- should restart; a change this load-bearing that did NOT force recert would be
-- the defect.
--
-- ══════════════════════════════════════════════════════════════════════════════

-- P0. No certification scheduled. -------------------------------------------
-- Follows 0358's shape rather than 0221's: the third check there ("no sim run
-- running") is deliberately omitted, because a demo run is not a certification
-- and the measurement this file is built on requires a live run.
DO $inflight$
DECLARE v_jobs text; v_pairs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0360 P0: certification jobs are still scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0360 P1: % certification pair(s) are active', v_pairs;
  END IF;

  RAISE NOTICE '0360 P0/P1: no certification scheduled, no pair running';
END $inflight$;

-- P2. The two functions this file replaces are the ones it was written against.
DO $guard$
DECLARE v_gc text; v_tick text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_gc
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_gc_stale_reservations';
  IF v_gc IS NULL THEN
    RAISE EXCEPTION '0360 P2: ottoq_gc_stale_reservations does not exist';
  END IF;
  IF v_gc <> 'e8d5835d1a5f387e70b98930738b839c' THEN
    RAISE EXCEPTION '0360 P2: ottoq_gc_stale_reservations changed under me (md5 %) '
                    '-- someone edited it since this file was written; re-read it '
                    'before replacing, or a fix is about to be deleted', v_gc;
  END IF;

  SELECT md5(pg_get_functiondef(p.oid)) INTO v_tick
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_advance_tick';
  IF v_tick IS NULL THEN
    RAISE EXCEPTION '0360 P2: ottoq_sim_advance_tick does not exist';
  END IF;
  IF v_tick <> 'a51d743f53175b93c03a63f0236c480c' THEN
    RAISE EXCEPTION '0360 P2: ottoq_sim_advance_tick changed under me (md5 %)', v_tick;
  END IF;

  RAISE NOTICE '0360 P2: both target functions match the definitions this file was written against';
END $guard$;

-- P3. The anchor the Part C substitution depends on occurs EXACTLY ONCE.
-- An anchored rewrite against an absent anchor silently does nothing, and against
-- a repeated one rewrites the wrong copy. Both are how a migration reports
-- success and changes nothing.
DO $anchor$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         regexp_matches(p.prosrc,
           'SELECT \* INTO d FROM ottoq_sim_decide_and_dispatch\(p_sim_run_id\);', 'g') AS m
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_advance_tick';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0360 P3: decide_and_dispatch anchor occurs % time(s), expected exactly 1', v_n;
  END IF;
  RAISE NOTICE '0360 P3: anchor is unique';
END $anchor$;

-- P4. The four states this file acts on are all real enum labels. A typo here
-- would compare to a string that can never match and the function would silently
-- release nothing -- a fix that reports success and does nothing.
DO $states$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(s, ', ') INTO v_missing
    FROM unnest(ARRAY['tow_requested','staged_for_departure',
                      'en_route_to_deployment','out_of_service']) AS s
   WHERE NOT EXISTS (
     SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
      WHERE t.typname = 'vehicle_state' AND e.enumlabel = s);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0360 P4: not vehicle_state labels: %', v_missing;
  END IF;
  RAISE NOTICE '0360 P4: all four unusable-holder states are real enum labels';
END $states$;

-- P5. The states this file must NOT act on are still enum labels too, so a future
-- rename cannot quietly turn an exclusion into a no-op that starts releasing the
-- greenlight queue.
DO $keep$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(s, ', ') INTO v_missing
    FROM unnest(ARRAY['staged_awaiting_service','en_route_to_depot','arrived_at_gate']) AS s
   WHERE NOT EXISTS (
     SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
      WHERE t.typname = 'vehicle_state' AND e.enumlabel = s);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0360 P5: protected states missing from vehicle_state: % '
                    '-- the exclusion list is stale and the greenlight queue is at risk', v_missing;
  END IF;
  RAISE NOTICE '0360 P5: the protected states still exist';
END $keep$;

-- ── SNAPSHOT BEFORE REPLACING ─────────────────────────────────────────────────
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0360_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_gc_stale_reservations','ottoq_sim_advance_tick');

-- ══ PART A — the reclaimer ═══════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ottoq_release_unusable_reservations(
          p_sim_run_id uuid,
          p_sim_clock  timestamptz DEFAULT NULL,
          p_depot_id   uuid        DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_clock     timestamptz;
  v_depot     uuid;
  v_by_state  bigint := 0;
  v_by_expiry bigint := 0;
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
      'ok', false, 'released', 0,
      'reason', 'no sim clock or depot resolvable; refusing to guess');
  END IF;

  WITH cand AS (
    SELECT s.id,
           --: cannot possibly consume a depot service reservation
           (v.current_state::text = ANY (ARRAY['tow_requested',
                                               'staged_for_departure',
                                               'en_route_to_deployment',
                                               'out_of_service'])) AS unusable_holder,
           (s.reservation_expires_at IS NOT NULL
            AND s.reservation_expires_at < v_clock)                AS sim_expired
      FROM public.stalls s
      LEFT JOIN public.vehicles v ON v.id = s.reserved_by
     WHERE s.depot_id     = v_depot
       AND s.reserved_by IS NOT NULL
       --: THE SAFETY INVARIANT. A stall whose holder is physically in it is never
       --: released -- that would desync the calendar from physical reality, and
       --: both sides of that pair are load-bearing (CLAUDE.md rule 6).
       AND s.current_vehicle_id IS DISTINCT FROM s.reserved_by
  ), doomed AS (
    SELECT id, unusable_holder, sim_expired
      FROM cand
     WHERE unusable_holder OR sim_expired
  ), cleared AS (
    UPDATE public.stalls s
       SET reserved_by             = NULL,
           reserved_at             = NULL,
           reservation_expires_at  = NULL
      FROM doomed d
     WHERE s.id = d.id
   RETURNING d.unusable_holder, d.sim_expired
  )
  SELECT count(*) FILTER (WHERE unusable_holder),
         --: expiry-only, so the two buckets sum to `released` without double count
         count(*) FILTER (WHERE sim_expired AND NOT unusable_holder)
    INTO v_by_state, v_by_expiry
    FROM cleared;

  RETURN jsonb_build_object(
    'ok',                 true,
    'released',           COALESCE(v_by_state, 0) + COALESCE(v_by_expiry, 0),
    'by_unusable_holder', COALESCE(v_by_state, 0),
    'by_sim_expiry',      COALESCE(v_by_expiry, 0),
    'sim_clock',          v_clock,
    'depot_id',           v_depot);

--: Total on its own account, not only behind the caller's handler. On the tick
--: path an unhandled error rolls back the whole tick and cron still reads
--: "succeeded" (APPLYING.md).
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('ok', false, 'released', 0,
    'sqlstate', SQLSTATE, 'msg', left(SQLERRM, 200));
END;
$function$;

COMMENT ON FUNCTION public.ottoq_release_unusable_reservations(uuid, timestamptz, uuid) IS
'0360. Releases a stall reservation when, and only when, it cannot be used. Two grounds: (a) the holder is in a vehicle_state that cannot possibly consume a depot service reservation -- tow_requested, staged_for_departure, en_route_to_deployment, out_of_service; (b) the reservation has expired against the SIM clock. Exists because G76 measured the twin depot at 155 of 158 stalls reserved and 21 occupied, with 135 reserved-and-empty and only 2 unclaimed -- so every proposer saw a legal move set of ~1% of a site that was 87% physically free, and the dead-weight count GREW 7 -> 11 across ticks 337-373. That is the upstream cause of the CP-SAT bridge abstaining "not one is offerable", of cuOpt''s 4 enacted / 7 refused / 60 superseded, and of Nemotron''s objective directive being moot: no optimiser can outperform another when neither has an admissible action. DELIBERATE EXCLUSIONS, which are the design: staged_awaiting_service is the GREENLIGHT QUEUE and is never touched; en_route_to_depot and arrived_at_gate hold legitimate pre-arrival reservations; the in-bay states may hold a charge stall for a later leg; offline and emergency_staged are ambiguous and left out until measured, per the measured-before-enforced doctrine. THE SAFETY INVARIANT: a stall whose holder is physically sitting in it is NEVER released (current_vehicle_id IS DISTINCT FROM reserved_by) -- 38 reservations were protected by that clause when this shipped. Never uses now(): reservation_expires_at is a sim-clock column and comparing it to wall time is G77, which would have cleared 156 of 156 reservations including 127 live ones. Returns counts by reason so the effect is measurable from the tick rather than inferred. Total function: returns ok:false rather than raising, because a failure must never abort decide_tick.';

-- ══ PART B — G77: the reaper stops comparing a sim column to wall time ═══════
-- Replaced rather than scheduled. It is still uncalled after this migration; what
-- changes is that scheduling it later is no longer catastrophic. Giving it a
-- caller is a separate decision and a separate file.
CREATE OR REPLACE FUNCTION public.ottoq_gc_stale_reservations()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH cleared AS (
    UPDATE stalls s
       SET reserved_by = NULL,
           reserved_at = NULL,
           reservation_expires_at = NULL
     WHERE s.reserved_by IS NOT NULL
       AND (
         -- 0360 / G77: expiry measured on the SIM clock of the depot's running
         -- run. This read `< now()`, and wall time runs AHEAD of the sim clock
         -- (4h46m on the run that caught it), so every reservation looked expired
         -- and this arm would have cleared 156 of 156 including 127 live ones.
         -- With no running run the subquery is NULL, the comparison is NULL, and
         -- this arm cannot fire -- which is correct, because the orphan arm below
         -- already clears exactly those rows, for a better reason.
         (s.reservation_expires_at IS NOT NULL
          AND s.reservation_expires_at < (
                SELECT r.sim_clock_current
                  FROM ottoq_sim_runs r
                 WHERE r.depot_id = s.depot_id AND r.status = 'running'
                 ORDER BY r.started_at DESC
                 LIMIT 1))
         OR
         -- Orphaned: no active sim run exists for this depot's reservations.
         -- Wall-clock-free and already correct; preserved verbatim.
         (NOT EXISTS (
           SELECT 1 FROM ottoq_sim_runs r
           WHERE r.depot_id = s.depot_id AND r.status = 'running'
         ))
       )
     RETURNING id
  )
  SELECT count(*) FROM cleared;
$function$;

COMMENT ON FUNCTION public.ottoq_gc_stale_reservations() IS
'Clears stall reservations that are expired or orphaned. 0360 fixed G77: the expiry arm compared reservation_expires_at -- a SIM-clock column -- against now(), which is WALL. Measured on run f14d5620, wall ran 4h46m ahead of the sim clock, so of 156 reserved stalls 127 were live against sim and 0 against wall: this function would have cleared ALL 156, and every vehicle staged_awaiting_service would have lost the stall it was queued for. It was harmless only because it is dead code -- zero cron jobs, zero callers -- but G76 tells a reader reservations are not being reclaimed, and the reader who greps for a reaper finds this. Now measured against the depot''s running run''s sim_clock_current; with no running run that arm cannot fire and the orphan arm handles those rows instead. STILL UNCALLED by design: giving it a caller is a separate decision. For the per-tick path use ottoq_release_unusable_reservations, which also handles the holder-state case this function cannot see.';

-- ══ PART C — call it once per tick, before the decide pass ═══════════════════
-- Anchored substitution, asserted unique by P3. Inserted AFTER the world advances
-- (so the sim clock is this tick's) and BEFORE decide_and_dispatch (so stalls
-- freed now are visible to this tick's assignment, not the next one's).
--
-- THE SUBSTITUTION RUNS OVER pg_get_functiondef, NOT prosrc, AND THAT IS NOT A
-- STYLE CHOICE -- IT IS THE SECOND DEFECT THIS FILE'S DRY-RUN CAUGHT.
-- The first draft rebuilt the CREATE OR REPLACE by hand with a typed-out
-- signature and `SET search_path TO 'public'`. Both were wrong against the live
-- catalog: `out_tick_minutes` is **numeric**, not integer, and the real
-- search_path is **twin, ottoq, public, extensions**. The body calls
-- `ottoq_sim_advance_tick_world`, `ottoq_sim_decide_and_dispatch` and
-- `ottoq_sim_release_depot` UNQUALIFIED, so replacing the function with a
-- public-only search_path would have left every one of them unresolvable and
-- **broken every tick** -- while the migration reported success.
-- Deriving the whole definition from the catalog and editing only the body makes
-- the signature, search_path, volatility and security attributes impossible to
-- get wrong, because they are never retyped.
DO $wire$
DECLARE
  v_def     text;
  v_anchor  text := 'SELECT * INTO d FROM ottoq_sim_decide_and_dispatch(p_sim_run_id);';
  v_inject  text;
  v_new     text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_advance_tick';

  IF v_def IS NULL THEN
    RAISE EXCEPTION '0360 Part C: ottoq_sim_advance_tick not found';
  END IF;

  v_inject :=
    '-- 0360 (G76): release reservations whose holder can no longer use them,' || E'\n' ||
    '  -- and those expired on the SIM clock, BEFORE this tick decides. The depot' || E'\n' ||
    '  -- was measured at 155 of 158 stalls reserved and 21 occupied, so every' || E'\n' ||
    '  -- proposer saw ~1% of a site that was 87% free. Never allowed to abort the' || E'\n' ||
    '  -- tick: the function returns ok:false rather than raising, and this handler' || E'\n' ||
    '  -- is the second line of that same defence.' || E'\n' ||
    '  BEGIN' || E'\n' ||
    '    PERFORM public.ottoq_release_unusable_reservations(p_sim_run_id);' || E'\n' ||
    '  EXCEPTION WHEN OTHERS THEN' || E'\n' ||
    '    RAISE WARNING ''0360 release_unusable_reservations: % %'', SQLSTATE, SQLERRM;' || E'\n' ||
    '  END;' || E'\n' || '  ' || v_anchor;

  v_new := replace(v_def, v_anchor, v_inject);

  IF v_new = v_def THEN
    RAISE EXCEPTION '0360 Part C: anchor not found at substitution time';
  END IF;

  --: pg_get_functiondef already IS a complete CREATE OR REPLACE statement, so the
  --: edited text is executed as-is. Safe because the injected block contains no
  --: dollar-quote tag that could terminate the body early.
  EXECUTE v_new;

  RAISE NOTICE '0360 Part C: release wired into ottoq_sim_advance_tick before the decide pass';
END $wire$;

-- P6. POST-CHECK — the wiring is really there, and the reclaimer is callable.
DO $post$
DECLARE v_n int; v_res jsonb; v_run uuid;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         regexp_matches(p.prosrc, 'ottoq_release_unusable_reservations', 'g') AS m
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_sim_advance_tick';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0360 P6: release call appears % time(s) in advance_tick, expected 1', v_n;
  END IF;

  --: and it must still be callable with the signature the tick uses
  SELECT r.sim_run_id INTO v_run
    FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY r.started_at DESC LIMIT 1;

  IF v_run IS NOT NULL THEN
    v_res := public.ottoq_release_unusable_reservations(v_run);
    IF (v_res->>'ok') IS NULL THEN
      RAISE EXCEPTION '0360 P6: reclaimer returned no ok key: %', v_res::text;
    END IF;
    RAISE NOTICE '0360 P6: wiring present and reclaimer returned %', v_res::text;
  ELSE
    RAISE NOTICE '0360 P6: wiring present; no twin-depot run to exercise the reclaimer against';
  END IF;
END $post$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0360_a_stall_reservation_outlives_the_vehicle_that_can_no_longer_use_it', true,
  'Changes which stalls are free at a given tick, so it changes assignment, bookings and the '
  'fingerprint. Every canon streak should restart -- a change this load-bearing that did NOT force '
  'recert would itself be the defect. Fixes G76: the twin depot measured 155 of 158 stalls reserved '
  'against 21 occupied, 135 reserved-and-empty, only 2 unclaimed, and the dead-weight count GREW '
  '7 -> 11 across ticks 337-373, so it is a leak rather than a regime. 41 of 157 reservations (26%) '
  'were releasable -- 39 by unusable holder state, 11 by sim-clock expiry, 9 overlapping -- taking '
  'the CHARGE pool from 0 offerable to 11 (l2 10 of 30, dcfc 1 of 10). That is the difference between '
  'a solver having nothing to decide and having a decision, which is why this outranks any solver '
  'work: the CP-SAT bridge abstaining "not one is offerable", cuOpt''s 4 enacted / 7 refused / 60 '
  'superseded, and Nemotron''s objective directive being moot are all ONE upstream cause. Deliberate '
  'exclusions are the design: staged_awaiting_service is the greenlight queue and is never touched, '
  'pre-arrival and in-bay holders keep their stalls, and offline / emergency_staged are left out as '
  'ambiguous pending measurement. Safety invariant: a stall whose holder is physically in it is never '
  'released (38 protected at ship time). ALSO fixes G77 in the same file deliberately, because G77 is '
  'the landmine under G76''s obvious fix: ottoq_gc_stale_reservations compared the sim-clock column '
  'reservation_expires_at to now(), and with wall 4h46m ahead of sim it would have cleared 156 of 156 '
  'reservations including 127 live ones. It stays uncalled; what changed is that scheduling it later '
  'is no longer catastrophic.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
