-- migration-version: 20260919161129
-- migration-name:    0330_sweep_two_asks_if_the_vehicle_is_in_the_stall_and_never_if_it_is_coming
-- ============================================================================
-- 0330 — SWEEP 2 TOOK SPACES AWAY FROM VEHICLES THAT WERE STANDING IN THE YARD
--        WAITING FOR THEM, BECAUSE IT ASKS WHERE THE VEHICLE *IS* AND NEVER
--        WHETHER IT IS *COMING*.
-- ============================================================================
-- This corrects 0329, which I wrote, on evidence 0328 had already collected and
-- I read wrongly. The paired runs are in db/checks/0249. Clipped to a matched
-- 870 sim-minute horizon, seed 771771 / busy_day / flagship, the only
-- difference being one run-scoped dial:
--
--                                     control   treatment
--   space conflicts                       134          19     -86%   GOOD
--   p50 time-to-service (min)              60          30     halved GOOD
--   p95 time-to-service (min)             243         480     +97%   BAD
--   turns completed                       332         295            BAD
--   returns_unserved                        0           1            BAD
--
-- And the mechanism of the harm, counted rather than inferred -- how many times
-- a SINGLE vehicle had a claim taken out from under it:
--
--   vehicles that lost a claim             30          80
--   worst single vehicle                    3          12
--   vehicles that lost 3 or more            1          22
--
-- One vehicle lost its space twelve times. That is starvation, and it is the
-- exact explanation of p50 down with p95 up: freeing a space lets whoever is
-- ready NOW win, and the vehicle that just lost re-enters the same race on
-- equal terms and can lose again, indefinitely.
--
-- ── WHY, AND IT WAS ALREADY IN 0328'S LEDGER ───────────────────────────────
-- 0328 recorded where the blocking vehicle was at every refusal:
--   arrived_at_gate 60% · staged_awaiting_service 22.5% · en_route_to_depot 17.5%
-- Every one of those is a vehicle AT THE DEPOT OR ON ITS WAY TO IT. 0329's
-- sweep 2 then retires a `held` claim on nothing but an elapsed grace period.
-- It asks whether the vehicle is IN THE STALL. It never asks whether the
-- vehicle is COMING. So it takes the space from precisely the population it
-- then starves.
--
-- The asymmetry shows in the firing counts. Sweep 1 carries two independent
-- witnesses that the vehicle has LEFT; it fired 4 times and did no measurable
-- harm. Sweep 2 carries no witness of intent at all; it fired 158 times and did
-- all of it.
--
-- ── WHAT THIS FILE CHANGES ─────────────────────────────────────────────────
-- 1. SPLITS THE DIAL, so the half that works is not hostage to the half that
--    does not. `space_departure_release_enabled` keeps sweep 1;
--    `space_noshow_release_enabled` is new and gates sweep 2. Both default 0.
--
-- 2. GIVES SWEEP 2 AN INTENT WITNESS, built the same way sweep 1's witnesses
--    were: POSITIVE EVIDENCE OF ABSENCE, never absence of evidence. A held
--    claim is retired only when the vehicle is provably not going to take it:
--      (a) its state is on an explicit list of states that mean gone from the
--          site or unable to drive to a stall -- offline, deployed,
--          en_route_to_deployment, out_of_service, tow_requested; OR
--      (b) it is positively sitting in a DIFFERENT stall, i.e. it took
--          something else instead.
--    Anything else -- at the gate, in staging, en route, charging, holding,
--    staged for departure, emergency staged -- KEEPS ITS CLAIM.
--
--    The list is an allow-list on purpose. A vehicle_state added later is not
--    on it, so a new state defaults to KEEPING the claim. The failure mode of
--    a stale allow-list is a space held too long; the failure mode of a stale
--    deny-list is a space taken from a vehicle that was coming for it. Those
--    are not equally bad, and 0249 is what it cost to learn that.
--
-- ── WHAT THIS FILE DOES NOT DO ─────────────────────────────────────────────
-- It does not add priority, ageing, or any queue ordering. Starvation is
-- prevented here by not creating it, not by compensating for it afterwards. If
-- a later measurement shows vehicles still losing repeatedly, ageing is the
-- next instrument and it belongs in the selection predicate, not in a release
-- sweep. Both dials stay 0; nothing in this file changes behaviour until a run
-- sets one.
--
-- ── THE PREDICTION THIS FILE MAKES, FOR THE NEXT PAIR TO JUDGE ─────────────
-- P1. With the witness in place, sweep-2 releases fall sharply from 158 and the
--     starvation counts return toward the control's 30 / worst 3 / one at 3+.
-- P2. Conflicts stay well below the control's 134, because sweep 1 and the
--     legitimate part of sweep 2 still retire genuinely abandoned claims.
-- P3. p95 returns to at or below the control's 243, and returns_unserved to 0.
-- NOT PREDICTED, and deliberately: that the combined change is net-positive.
-- 0249 is what happens when that gets assumed instead of measured.
-- ============================================================================

DO $pre$
DECLARE v_src text; v_n int;
BEGIN
  -- P1. 0329's sweep is live and is the version this file was written against.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_release_departed_spaces';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0330 P1: ottoq.ottoq_release_departed_spaces not found -- 0329 is not applied';
  END IF;
  IF position('space_noshow_release_enabled' in v_src) > 0 THEN
    RAISE EXCEPTION '0330 P1: the dial is already split; nothing to do';
  END IF;
  IF position('no_show_grace_elapsed' in v_src) = 0 THEN
    RAISE EXCEPTION '0330 P1: sweep 2 is not where this file expects it';
  END IF;
  RAISE NOTICE '0330 P1: 0329 sweep found, dial not yet split';

  -- P2. Neither dial is set anywhere but a completed run, so this file cannot
  --     change any live behaviour by changing what the dials mean.
  -- LEFT JOIN deliberately. An INNER join here would silently DROP every
  -- global- and depot-scope row -- scope_id is not a run id for those -- so the
  -- check would pass precisely when the dial was set at the widest scope. That
  -- is the defect class this whole thread is about, caught in its own guard.
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params pp
    LEFT JOIN public.ottoq_sim_runs r ON r.sim_run_id = pp.scope_id
   WHERE pp.param_key='space_departure_release_enabled'
     AND (pp.scope_type <> 'run'
          OR r.status IS NULL
          OR r.status NOT IN ('completed','failed','aborted'));
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0330 P2: the departure dial is set on a live scope; quiesce before changing its meaning';
  END IF;
  RAISE NOTICE '0330 P2: no live scope carries the departure dial';
END $pre$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0330 pre: ottoq_release_departed_spaces before the intent witness',
       'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='ottoq' AND p.proname='ottoq_release_departed_spaces';

-- ── THE SECOND DIAL ────────────────────────────────────────────────────────
INSERT INTO public.ottoq_policy_param_catalog
       (param_key, description, default_value, min_value, max_value, affects)
VALUES ('space_noshow_release_enabled',
        '0330. When 1, sweep 2 of ottoq_release_departed_spaces retires a held '
        'dcfc/l2/staging claim whose grace has elapsed AND whose vehicle is '
        'provably not coming for it -- state on the absent-from-site list, or '
        'positively occupying a different stall. Split out of '
        'space_departure_release_enabled because 0249 measured sweep 2 causing '
        'all of that change''s harm (158 releases, 22 vehicles starved) while '
        'sweep 1 fired 4 times harmlessly. Default 0.',
        0, 0, 1, 'ottoq.ottoq_release_departed_spaces')
ON CONFLICT (param_key) DO NOTHING;

-- ── THE WITNESS, AS ONE DECLARATIVE PREDICATE ──────────────────────────────
CREATE OR REPLACE FUNCTION ottoq.ottoq_vehicle_absent_from_site(p_state text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $fn$
  -- Is this vehicle provably NOT about to take a stall at this site?
  --
  -- ALLOW-LIST, and that direction is the whole point. A vehicle_state added
  -- after this migration is NOT on the list, so it defaults to KEEPING the
  -- claim. The cost of a stale allow-list is a space held too long; the cost of
  -- a stale deny-list is a space taken from a vehicle that was coming for it.
  -- db/checks/0249 measured the second: one vehicle lost its space 12 times.
  --
  -- Deliberately ABSENT from this list, with reasons:
  --   en_route_to_depot        -- it is coming; this is 17.5% of 0328's blockers
  --   arrived_at_gate          -- it is here; 60% of 0328's blockers
  --   staged_awaiting_service  -- it is here and waiting; 22.5%
  --   charging_*, in_*_bay, *_holding, staged_for_departure
  --                            -- at the site, mid-cycle, may still be owed this
  --   emergency_staged         -- at the site under an exception; never scavenge
  SELECT p_state IN ('offline',                -- not at the site, not returning
                     'deployed',               -- out working
                     'en_route_to_deployment', -- leaving
                     'out_of_service',         -- will not drive to a stall
                     'tow_requested');         -- will not drive to a stall
$fn$;

COMMENT ON FUNCTION ottoq.ottoq_vehicle_absent_from_site(text) IS
  '0330. Allow-list of vehicle states meaning the vehicle is gone from the site '
  'or cannot drive to a stall, so a held claim of its own may be retired. New '
  'states default to FALSE (keep the claim) by construction.';

-- W1. The witness must answer FALSE for every state 0328 actually observed
--     blocking, or this file has not fixed the thing it claims to fix.
DO $w1$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(s, ', ') INTO v_bad
    FROM unnest(ARRAY['en_route_to_depot','arrived_at_gate','staged_awaiting_service',
                      'charging_dcfc','charging_l2','charge_complete_holding',
                      'in_wash_bay','in_detail_bay','in_service_bay',
                      'service_complete_holding','staged_for_departure',
                      'emergency_staged']) s
   WHERE ottoq.ottoq_vehicle_absent_from_site(s);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0330 W1: the witness would still scavenge from a vehicle at or approaching the site: %', v_bad;
  END IF;

  SELECT string_agg(s, ', ') INTO v_bad
    FROM unnest(ARRAY['offline','deployed','en_route_to_deployment',
                      'out_of_service','tow_requested']) s
   WHERE NOT ottoq.ottoq_vehicle_absent_from_site(s);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0330 W1: the witness refuses to release a genuinely abandoned claim: %', v_bad;
  END IF;

  -- and it must be total over the live enum: every label classified, none missed
  SELECT string_agg(e.enumlabel, ', ') INTO v_bad
    FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
   WHERE t.typname='vehicle_state'
     AND ottoq.ottoq_vehicle_absent_from_site(e.enumlabel) IS NULL;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0330 W1: the witness returns NULL for %', v_bad;
  END IF;
  RAISE NOTICE '0330 W1: witness keeps the claim for all 12 at-site states, releases for all 5 absent states, total over the enum';
END $w1$;

-- ── THE SWEEP, REWRITTEN ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION ottoq.ottoq_release_departed_spaces(
  p_sim_run_id uuid, p_depot_id uuid, p_clock timestamptz)
RETURNS int LANGUAGE plpgsql AS $fn$
DECLARE v_dep_on int; v_nos_on int; v_grace int; v_dep int := 0; v_nos int := 0;
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;

  -- 0330: TWO dials now. 0249 measured sweep 2 causing all of 0329's harm while
  -- sweep 1 fired 4 times harmlessly, so they are no longer switched together.
  v_dep_on := COALESCE(public.ottoq_policy_get(p_sim_run_id,'space_departure_release_enabled',0),0)::int;
  v_nos_on := COALESCE(public.ottoq_policy_get(p_sim_run_id,'space_noshow_release_enabled',0),0)::int;
  IF v_dep_on <> 1 AND v_nos_on <> 1 THEN RETURN 0; END IF;

  v_grace := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'booking_no_show_grace_min',15),15)::int, 0);

  -- ── SWEEP 1: DEPARTURE. Unchanged from 0329. An `active` claim whose vehicle
  -- has left, on two independent witnesses (the VEHICLE says it is positively
  -- in a different stall; the STALL disowns it) plus no open OCPP session on a
  -- charge place. This is the half 0249 found harmless.
  IF v_dep_on = 1 THEN
    WITH cand AS (
      SELECT b.booking_id, lower(b.during) AS lo, upper(b.during) AS hi,
             GREATEST(lower(b.during) + interval '1 second',
                      LEAST(upper(b.during), p_clock)) AS clip_hi
        FROM public.ottoq_stall_bookings b
        JOIN public.stalls   s ON s.id = b.stall_id
        JOIN public.vehicles v ON v.id = b.vehicle_id
       WHERE b.sim_run_id = p_sim_run_id
         AND s.depot_id   = p_depot_id
         AND s.stall_type IN ('dcfc'::stall_type,'l2'::stall_type,'staging'::stall_type)
         AND b.state      = 'active'
         AND b.during @> p_clock
         AND v.current_stall_id IS NOT NULL
         AND v.current_stall_id <> b.stall_id
         AND s.current_vehicle_id IS DISTINCT FROM b.vehicle_id
         AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions os
                          WHERE os.sim_run_id = b.sim_run_id
                            AND os.stall_id   = b.stall_id
                            AND os.vehicle_id = b.vehicle_id
                            AND os.ended_at IS NULL)
    ), upd AS (
      UPDATE public.ottoq_stall_bookings b
         SET state = CASE WHEN ottoq.ottoq_occupancy_cut_short(
                                 EXTRACT(epoch FROM (c.hi - c.lo))::numeric,
                                 EXTRACT(epoch FROM (c.clip_hi - c.lo))::numeric)
                          THEN 'interrupted' ELSE 'done' END,
             released_at    = p_clock,
             release_reason = CASE WHEN ottoq.ottoq_occupancy_cut_short(
                                         EXTRACT(epoch FROM (c.hi - c.lo))::numeric,
                                         EXTRACT(epoch FROM (c.clip_hi - c.lo))::numeric)
                                   THEN 'departed_before_planned_end'
                                   ELSE 'departed_stall' END,
             during = tstzrange(c.lo, c.clip_hi, '[)')
        FROM cand c WHERE b.booking_id = c.booking_id
      RETURNING 1 AS one
    ) SELECT count(*) INTO v_dep FROM upd;
  END IF;

  -- ── SWEEP 2: NO-SHOW, NOW WITH AN INTENT WITNESS.
  -- 0329 asked only whether the vehicle was IN the stall, so it scavenged from
  -- vehicles standing at the gate and in staging waiting for that very space --
  -- 158 releases, 22 vehicles starved, one of them 12 times (db/checks/0249).
  -- A held claim is now retired only on POSITIVE evidence the vehicle is not
  -- coming for it:
  --   (a) its state is on the absent-from-site allow-list, or
  --   (b) it is positively occupying a DIFFERENT stall -- it took another.
  -- The grace period is kept as a settling guard, not as the reason.
  IF v_nos_on = 1 THEN
    WITH cand AS (
      SELECT b.booking_id
        FROM public.ottoq_stall_bookings b
        JOIN public.stalls   s ON s.id = b.stall_id
        JOIN public.vehicles v ON v.id = b.vehicle_id
       WHERE b.sim_run_id = p_sim_run_id
         AND s.depot_id   = p_depot_id
         AND s.stall_type IN ('dcfc'::stall_type,'l2'::stall_type,'staging'::stall_type)
         AND b.state      = 'held'
         AND b.during @> p_clock
         AND lower(b.during) + make_interval(mins => v_grace) <= p_clock
         AND v.current_stall_id IS DISTINCT FROM b.stall_id
         AND s.current_vehicle_id IS DISTINCT FROM b.vehicle_id
         AND (   ottoq.ottoq_vehicle_absent_from_site(v.current_state::text)   -- (a)
              OR (v.current_stall_id IS NOT NULL                               -- (b)
                  AND v.current_stall_id <> b.stall_id))
         AND NOT EXISTS (SELECT 1 FROM public.ocpp_sessions os
                          WHERE os.sim_run_id = b.sim_run_id
                            AND os.stall_id   = b.stall_id
                            AND os.vehicle_id = b.vehicle_id
                            AND os.ended_at IS NULL)
    ), upd AS (
      UPDATE public.ottoq_stall_bookings b
         SET state='released', released_at=p_clock, release_reason='no_show_vehicle_not_coming'
        FROM cand c WHERE b.booking_id = c.booking_id
      RETURNING 1 AS one
    ) SELECT count(*) INTO v_nos FROM upd;
  END IF;

  RETURN v_dep + v_nos;

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'ottoq_release_departed_spaces: FAILED sqlstate=% msg=% run=% depot=%',
    SQLSTATE, SQLERRM, p_sim_run_id, p_depot_id;
  RETURN 0;
END $fn$;

COMMENT ON FUNCTION ottoq.ottoq_release_departed_spaces(uuid, uuid, timestamptz) IS
  '0330. Calendar-only release for dcfc/l2/staging, the 153 of the flagship''s '
  '158 stalls ottoq_release_vacated_spaces does not cover. Two independently '
  'gated sweeps: departure (space_departure_release_enabled) retires an active '
  'claim whose vehicle has left; no-show (space_noshow_release_enabled) retires '
  'a held claim only on positive evidence the vehicle is not coming. Never '
  'writes stalls or vehicles. Both dials default 0.';

DO $post$
DECLARE v_src text; v_n int; v_b boolean;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_release_departed_spaces';

  -- A1. Both dials are read, and each sweep is behind its own.
  IF position('space_departure_release_enabled' in v_src) = 0
     OR position('space_noshow_release_enabled' in v_src) = 0 THEN
    RAISE EXCEPTION '0330 A1: a dial is not read';
  END IF;
  IF position('IF v_dep_on = 1 THEN' in v_src) = 0
     OR position('IF v_nos_on = 1 THEN' in v_src) = 0 THEN
    RAISE EXCEPTION '0330 A1: the sweeps are not independently gated';
  END IF;

  -- A2. THE INTENT WITNESS IS IN SWEEP 2. This is the assertion this file
  --     exists for; without it the starvation of 0249 returns.
  IF position('ottoq_vehicle_absent_from_site' in v_src) = 0 THEN
    RAISE EXCEPTION '0330 A2: sweep 2 still has no intent witness';
  END IF;

  -- A3. Sweep 1 kept all three of its own witnesses. This file corrects sweep
  --     2; it must not quietly loosen the half that was working.
  IF position('v.current_stall_id IS NOT NULL' in v_src) = 0
     OR position('s.current_vehicle_id IS DISTINCT FROM b.vehicle_id' in v_src) = 0
     OR position('os.ended_at IS NULL' in v_src) = 0 THEN
    RAISE EXCEPTION '0330 A3: a sweep-1 witness went missing';
  END IF;

  -- A4. Still calendar-only. The reason 0329 was safe to ship at all.
  IF v_src ~* 'UPDATE\s+public\.stalls' OR v_src ~* 'UPDATE\s+public\.vehicles' THEN
    RAISE EXCEPTION '0330 A4: the sweep now writes physical state';
  END IF;

  -- A5. Both dials registered, both default 0, and no live scope sets either.
  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key IN ('space_departure_release_enabled','space_noshow_release_enabled')
     AND default_value=0 AND min_value=0 AND max_value=1;
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0330 A5: expected two dials at default 0 / range 0..1, found %', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE param_key='space_noshow_release_enabled';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0330 A5: the new dial is already set somewhere; this file must ship inert';
  END IF;

  -- A6. Inert proven by CALLING it on a run with neither dial set.
  SELECT ottoq.ottoq_release_departed_spaces(
           'c9b05a04-678f-4d27-9bb6-f93d2e501d64'::uuid,
           '11111111-1111-1111-1111-111111111111'::uuid, now()) = 0 INTO v_b;
  IF NOT v_b THEN
    RAISE EXCEPTION '0330 A6: the sweep acted with both dials unset';
  END IF;

  RAISE NOTICE '0330 A1-A6: dials split, sweep 2 has an intent witness, sweep 1 intact, calendar-only, inert and proven so by call';
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0330_sweep_two_asks_if_the_vehicle_is_in_the_stall_and_never_if_it_is_coming', true,
   'Corrects 0329 on evidence 0328 had already collected. db/checks/0249 measured 0329''s '
   'combined dial halving p50 time-to-service (60->30) and cutting conflicts 134->19 while '
   'DOUBLING p95 (243->480), dropping turns 332->295 and leaving one vehicle unserved -- '
   'because sweep 2 retired held claims on an elapsed grace alone, scavenging from vehicles '
   'that were at the gate (60% of 0328''s blockers), in staging (22.5%) or en route (17.5%). '
   '80 vehicles lost a claim, 22 of them three or more times, one twelve times. This file '
   'splits the dial (sweep 1 kept space_departure_release_enabled, which fired 4 times '
   'harmlessly; sweep 2 gets the new space_noshow_release_enabled) and gives sweep 2 an '
   'intent witness: ottoq_vehicle_absent_from_site, an ALLOW-list of five states, so a state '
   'added later defaults to KEEPING the claim. W1 asserts the witness keeps the claim for all '
   'twelve at-site states, releases for all five absent ones, and is total over the enum. '
   'Both dials default 0 and A6 proves inertness by calling the function. SHOULD move no '
   'canon; classified TRUE on 0320''s rule anyway.',
   now())
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- APPLIED 20260919161129 (2026-09-19 16:11:29 UTC / 11:11 AM CT)
-- ============================================================================
-- Window: quiesced and verified -- 0 other active backends, 0 live sim runs,
-- 0 certification cron jobs.
--
-- DIGEST, anchored on the LINE rather than the phrase (0329's lesson, and this
-- header deliberately does not contain that literal anywhere):
--   committed file body    635b4fd839fb6ce43dd22579ccedd93d   16806 chars
--   applied migration body 635b4fd839fb6ce43dd22579ccedd93d   16806 chars
-- Identical on the first attempt. Only the header was condensed.
--
-- RESULT, measured after apply:
--   dials registered            : 2   (departure + no-show, both default 0)
--   new dial SET anywhere       : 0   -- ships inert
--   witness function            : present
--   pre-snapshot                : 1
--   enum partition by witness   : 5 releasable / 12 protected  (W1's assertion,
--                                 re-measured from pg_enum after the fact)
--   A1-A6                       : all passed in the apply transaction
--   lineage forces_recert       : true
--
-- WHAT IS NOT PROVEN. P1, P2 and P3 in the header are predictions, not results.
-- The file changes no behaviour until a run sets a dial. Judging them needs a
-- fresh pair on seed 771771 against the control already captured in
-- db/checks/0249 (p95 243, p50 60, conflicts 134, turns 332, unserved 0,
-- 30 vehicles losing a claim, worst 3).
--
-- AND THE HONEST LIMIT OF W1. W1 proves the witness CLASSIFIES the twelve
-- at-site states as protected. It does not prove sweep 2 will therefore stop
-- starving vehicles -- that depends on which states the blockers are actually
-- in at the moment the sweep runs, which only a run can show. W1 is a test of
-- the predicate, not of the outcome, and the distinction is exactly the one
-- this repo keeps having to relearn.
-- ============================================================================
