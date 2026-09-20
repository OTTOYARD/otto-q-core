-- migration-version: PENDING
-- migration-name:    the_frame_now_says_which_vehicles_are_overstaying_a_charge_stall
--
-- 0366  PUBLISH THE OVERSTAY TO THE DECISION FRAME, SO THE SIGNAL REACHES A
--       CONSUMER INSTEAD OF DYING IN A release_reason.
--
-- The wiring half of G81. `0365` made the overstay countable; this makes it
-- VISIBLE to everything that reads the frame. Additive only: one new key on each
-- vehicle. No existing key changes, so no current consumer's behaviour changes.
--
-- ══ 1. WHY THIS IS THE FIX AND NOT A REPORT ════════════════════════════════
--
-- `ottoq.ottoq_release_expired_bookings` already detects the overstay and names it
-- `release_reason = 'window_elapsed_occupied'`. G81 established that the string
-- occurs in exactly ONE object in the whole database -- the function that writes it
-- -- with no other routine, no view, no matview, and nothing in `edge-functions/`,
-- `bridge/`, `proposer/` or `metrics/`. **One writer, zero readers.**
--
-- Measured on run `3fb415d8`: **162** `window_elapsed_occupied` against **143**
-- clean `window_elapsed`, so more bookings expire with the asset still plugged in
-- than expire cleanly. `0365`'s first live read, at tick 634, found 8 concurrent
-- overstays including **NASH-DCFC-STALL-09 held 188 minutes past its window** --
-- one of only ten DCFC on the site -- and NASH-L2-STALL-31 at 241 minutes.
--
-- The consequence G80 measured: a vehicle whose charge booking was released still
-- occupies the stall, so `holds_charge_place` reads FALSE (correctly -- it holds no
-- *booked* charge place), `vehicle_is_held` therefore judges it plannable, and the
-- proposer offers it a SECOND charge stall it does not need. `b97789b5` was offered
-- `NASH-L2-STALL-19` while physically charging in `NASH-L2-STALL-31`.
--
-- **Nothing in that chain is a bug in the proposer.** It reasons correctly from
-- what it is shown. It is simply not shown the overstay, and that is a wiring
-- defect: the engine knows and does not say.
--
-- ══ 2. WHERE IT GOES, AND WHY THAT PLACE IS NOT A NEW INVENTION ════════════
--
-- Into the `g.facts >= 1` block of `ottoq_build_decision_frame`, immediately after
-- `holds_charge_place` -- the same block, the same gate and the same
-- `proposer_frame_facts` policy key that `0265`, `0287` and `0292` used to add the
-- hold facts. Rule 5: extend the mechanism that exists.
--
-- Measured rather than assumed: `g.facts >= 1` is the **only** tier in that
-- function (3 occurrences, no `>= 2` or `>= 3`), and `proposer_frame_facts` has
-- `max_value = 1` in the catalog, currently 1 on the live run. **So no new gate is
-- needed and none is invented.**
--
-- A TRAP AVOIDED AND WORTH RECORDING: the bridge's fire record prints
-- `frame_facts_version: 3`, which is the BRIDGE'S OWN constant and not this
-- function's tier. Reading it as a DB facts tier would have led to adding a
-- `g.facts >= 3` block that never fires, because the catalog caps the key at 1.
--
-- ══ 3. THE CLOCK, AGAIN, BECAUSE IT IS THE RECURRING DEFECT ════════════════
--
-- Coverage is judged against `g.clk`, which the function's own CTE already resolves
-- as `COALESCE((SELECT sim_clock_current FROM ottoq_sim_runs WHERE …), now())` --
-- sim when a run exists, wall only when there is no run at all. Its own comment
-- says why: *"all 40 flagship charge stalls are heartbeat-stale against now() and
-- fresh against the sim clock, so reading the wall clock here would make every
-- stall look dead."* `ottoq_stall_bookings.during` is a SIM range (0357), so this
-- reuses the right clock instead of introducing a second one. G77 is what happens
-- when a sim column meets `now()`.
--
-- ══ 4. WHAT IT DOES NOT DO ═════════════════════════════════════════════════
--
-- It does not change `holds_charge_place`, `has_live_booking`, `vehicle_is_held`,
-- or any proposer. Those stay exactly as they are, so **this file cannot change a
-- single assignment.** It only makes the fact available.
--
-- Consuming it is a separate, testable step in `proposer/forward_proposer.py`
-- (`vehicle_is_held` would treat an overstaying vehicle as placed-in-fact), and it
-- belongs in its own change with its own before/after on a paired seed -- because
-- that one DOES change what the engine offers. G80 needed three revisions for
-- moving faster than its evidence; this file declines to repeat that.
--
-- Charge stalls only (`l2`, `dcfc`). An overstay on a staging or wash place is real
-- and `0365` reports it, but the decision this key exists to inform is whether a
-- vehicle still needs a CHARGE place, and widening it here would blur that.
--
-- ══ 5. CLASSIFICATION ══════════════════════════════════════════════════════
--
-- `forces_recert: FALSE`, and the grounds are asserted by P4 rather than argued:
-- **no `ottoq_hash_*` atom function reads `ottoq_build_decision_frame`**, so none
-- of the fourteen can see this key.
--
-- Stated plainly because it is the one real consequence:
-- `ottoq_capture_decision_snapshot` DOES read the frame builder, so stored
-- `content_hash` values shift from here on. That is tolerable and not a recert
-- trigger because `content_hash` is deliberately **outside** the fourteen atoms
-- (CLAUDE.md, after `0216`/`0280`: it stays out until a flagship round promotes
-- it). Determinism is unaffected -- two arms on one seed still agree, since the new
-- key is a pure function of committed rows. What breaks is comparability of
-- `content_hash` ACROSS this change, which is what a version bump is for and what a
-- canon over the fourteen does not measure.
--
-- ══════════════════════════════════════════════════════════════════════════════

-- P0/P1. No certification scheduled or in flight.
DO $inflight$
DECLARE v_jobs text; v_pairs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0366 P0: certification jobs are still scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0366 P1: % certification pair(s) are active', v_pairs;
  END IF;

  RAISE NOTICE '0366 P0/P1: no certification scheduled, no pair running';
END $inflight$;

-- P2. The frame builder is the one this file was written against. There are TWO
-- overloads of this name; only the 2-arg one carries a body worth guarding (the
-- 1-arg is a 92-character wrapper), so the check names its signature explicitly.
DO $guard$
DECLARE v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_build_decision_frame'
     AND pg_get_function_identity_arguments(p.oid) = 'p_depot_id uuid, p_sim_run_id uuid';
  IF v_md5 IS NULL THEN
    RAISE EXCEPTION '0366 P2: the 2-arg ottoq_build_decision_frame does not exist';
  END IF;
  IF v_md5 <> '66ecfbbdad07a9150d7c6e2718d818e7' THEN
    RAISE EXCEPTION '0366 P2: ottoq_build_decision_frame changed under me (md5 %)', v_md5;
  END IF;
  RAISE NOTICE '0366 P2: frame builder matches the definition this file was written against';
END $guard$;

-- P3. The anchor occurs exactly once, the key is not already present, and the
-- facts tier is the one this file targets. All three, because an anchored rewrite
-- that misses reports success and changes nothing.
DO $anchor$
DECLARE v_anchor int; v_existing int; v_tier1 int; v_higher int;
BEGIN
  SELECT (SELECT count(*) FROM regexp_matches(p.prosrc, '''holds_charge_place''', 'g')),
         (SELECT count(*) FROM regexp_matches(p.prosrc, 'occupies_charge_stall_unbooked', 'g')),
         (SELECT count(*) FROM regexp_matches(p.prosrc, 'g\.facts >= 1', 'g')),
         (SELECT count(*) FROM regexp_matches(p.prosrc, 'g\.facts >= [2-9]', 'g'))
    INTO v_anchor, v_existing, v_tier1, v_higher
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_build_decision_frame'
     AND pg_get_function_identity_arguments(p.oid) = 'p_depot_id uuid, p_sim_run_id uuid';

  IF v_anchor <> 1 THEN
    RAISE EXCEPTION '0366 P3: holds_charge_place anchor occurs % time(s), expected 1', v_anchor;
  END IF;
  IF v_existing <> 0 THEN
    RAISE EXCEPTION '0366 P3: the key is already present -- already applied';
  END IF;
  IF v_tier1 < 1 THEN
    RAISE EXCEPTION '0366 P3: no g.facts >= 1 block found; the gate this file relies on is gone';
  END IF;
  IF v_higher > 0 THEN
    RAISE EXCEPTION '0366 P3: a higher facts tier now exists (% occurrence(s)); re-read the '
                    'function and decide which tier this key belongs to', v_higher;
  END IF;
  RAISE NOTICE '0366 P3: anchor unique, key absent, single facts tier as expected';
END $anchor$;

-- P4. THE forces_recert:FALSE GROUNDS. None of the fourteen atom functions may
-- read the frame builder. If one ever does, this key enters the verdict and the
-- classification is wrong -- the G28 defect class, a canon called green by a
-- narrower test than the enforcement.
DO $hash$
DECLARE v_atoms int; v_names text;
BEGIN
  SELECT count(*), string_agg(p.proname, ', ' ORDER BY p.proname)
    INTO v_atoms, v_names
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname LIKE 'ottoq_hash_%'
     AND position('ottoq_build_decision_frame' in p.prosrc) > 0;
  IF v_atoms > 0 THEN
    RAISE EXCEPTION '0366 P4: % hash atom function(s) read the frame builder (%) -- '
                    'reclassify forces_recert TRUE before applying', v_atoms, v_names;
  END IF;
  RAISE NOTICE '0366 P4: no ottoq_hash_* atom reads the frame builder, so the fourteen cannot see this key';
END $hash$;

-- P5. The enum labels this file compares against must be real. `stall_type` is an
-- enum, and a typo would compare against a label that cannot exist -- the key
-- would read FALSE for every vehicle and look installed.
DO $enum$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(s, ', ') INTO v_missing
    FROM unnest(ARRAY['l2','dcfc']) AS s
   WHERE NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
                      WHERE t.typname = 'stall_type_enum' AND e.enumlabel = s)
     AND NOT EXISTS (SELECT 1 FROM public.stalls st WHERE st.stall_type::text = s);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0366 P5: no stall carries stall_type %; the predicate would never match', v_missing;
  END IF;
  RAISE NOTICE '0366 P5: l2 and dcfc are real stall types present in the data';
END $enum$;

-- ── SNAPSHOT BEFORE REPLACING ─────────────────────────────────────────────────
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0366_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_build_decision_frame'
   AND pg_get_function_identity_arguments(p.oid) = 'p_depot_id uuid, p_sim_run_id uuid';

-- ══ THE CHANGE — one additive key ════════════════════════════════════════════
-- Derived from pg_get_functiondef rather than retyped, per 0360's lesson: this
-- function's real search_path is 'twin, ottoq, public, extensions' and a
-- hand-written signature nearly broke every tick once already.
DO $wire$
DECLARE
  v_def    text;
  v_anchor text := '''holds_charge_place'', (COALESCE(rsv.is_charge, false) OR COALESCE(bkg.has_charge, false)),';
  v_inject text;
  v_new    text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_build_decision_frame'
     AND pg_get_function_identity_arguments(p.oid) = 'p_depot_id uuid, p_sim_run_id uuid';

  IF v_def IS NULL THEN
    RAISE EXCEPTION '0366: frame builder not found at substitution time';
  END IF;
  IF position(v_anchor in v_def) = 0 THEN
    RAISE EXCEPTION '0366: holds_charge_place anchor not present in the definition';
  END IF;

  v_inject := v_anchor || E'\n' ||
    '        --: 0366 (G81). THE OVERSTAY, PUBLISHED. True when this vehicle' || E'\n' ||
    '        --: physically occupies a CHARGE stall for which no booking covers the' || E'\n' ||
    '        --: clock -- i.e. ottoq_release_expired_bookings has already stamped' || E'\n' ||
    '        --: release_reason = ''window_elapsed_occupied'' and the asset never left.' || E'\n' ||
    '        --: Measured 162 times against 143 clean expiries on run 3fb415d8, with' || E'\n' ||
    '        --: a DCFC held 188 minutes past its window.' || E'\n' ||
    '        --:' || E'\n' ||
    '        --: holds_charge_place answers "do I hold a BOOKED charge place" and is' || E'\n' ||
    '        --: correctly false here; this answers "am I sitting in one anyway". A' || E'\n' ||
    '        --: consumer that conflates them re-offers a stall to a vehicle already' || E'\n' ||
    '        --: drawing power (G80). Deliberately a SEPARATE key: overwriting' || E'\n' ||
    '        --: holds_charge_place would change proposer behaviour silently.' || E'\n' ||
    '        --: g.clk is the run''s sim clock; `during` is a SIM range (0357) and a' || E'\n' ||
    '        --: now() comparison here is G77.' || E'\n' ||
    '        ''occupies_charge_stall_unbooked'', EXISTS (' || E'\n' ||
    '          SELECT 1 FROM public.stalls s_ov' || E'\n' ||
    '           WHERE s_ov.current_vehicle_id = v.id' || E'\n' ||
    '             AND s_ov.stall_type::text IN (''l2'', ''dcfc'')' || E'\n' ||
    '             AND NOT EXISTS (' || E'\n' ||
    '               SELECT 1 FROM public.ottoq_stall_bookings b_ov' || E'\n' ||
    '                WHERE b_ov.sim_run_id = p_sim_run_id' || E'\n' ||
    '                  AND b_ov.stall_id   = s_ov.id' || E'\n' ||
    '                  AND b_ov.vehicle_id = v.id' || E'\n' ||
    '                  AND b_ov.state IN (''held'', ''active'')' || E'\n' ||
    '                  AND b_ov.during @> g.clk)),';

  v_new := replace(v_def, v_anchor, v_inject);
  IF v_new = v_def THEN
    RAISE EXCEPTION '0366: substitution produced no change';
  END IF;

  EXECUTE v_new;
  RAISE NOTICE '0366: occupies_charge_stall_unbooked published on every frame vehicle';
END $wire$;

-- P6. POST-CHECK — present once, the function still runs, and the key actually
-- agrees with 0365's independent instrument. The last of these is the one that
-- matters: a key that is always false would look installed and say nothing.
DO $post$
DECLARE v_n int; v_run uuid; v_frame jsonb; v_flagged int; v_instrument int;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
         regexp_matches(p.prosrc, 'occupies_charge_stall_unbooked', 'g') AS m
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_build_decision_frame'
     AND pg_get_function_identity_arguments(p.oid) = 'p_depot_id uuid, p_sim_run_id uuid';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0366 P6: the key appears % time(s), expected 1', v_n;
  END IF;

  SELECT sr.sim_run_id INTO v_run FROM public.ottoq_sim_runs sr
   WHERE sr.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY sr.started_at DESC LIMIT 1;

  IF v_run IS NULL THEN
    RAISE NOTICE '0366 P6: key present once; no twin-depot run to exercise the frame against';
    RETURN;
  END IF;

  --: the function must still BUILD -- an additive key that breaks the frame is
  --: worse than no key, and every proposer reads this
  v_frame := public.ottoq_build_decision_frame('11111111-1111-1111-1111-111111111111', v_run);
  IF v_frame IS NULL OR v_frame->'vehicles' IS NULL THEN
    RAISE EXCEPTION '0366 P6: the frame no longer builds a vehicles block';
  END IF;

  SELECT count(*) INTO v_flagged
    FROM jsonb_array_elements(v_frame->'vehicles') AS e
   WHERE (e.value->>'occupies_charge_stall_unbooked')::boolean;

  SELECT count(*) INTO v_instrument
    FROM public.ottoq_stall_overstays(v_run)
   WHERE stall_type IN ('l2','dcfc');

  --: AGREEMENT, not equality: 0365 counts STALLS and this counts VEHICLES, and a
  --: vehicle could in principle occupy two. They must both see the population or
  --: one of them is wrong.
  IF v_instrument > 0 AND v_flagged = 0 THEN
    RAISE EXCEPTION '0366 P6: 0365 reports % charge-stall overstay(s) and the frame flags '
                    'NONE -- the published key disagrees with the instrument', v_instrument;
  END IF;

  RAISE NOTICE '0366 P6: key present once, frame builds, % vehicle(s) flagged against '
               '% charge-stall overstay(s) from 0365', v_flagged, v_instrument;
END $post$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0366_the_frame_now_says_which_vehicles_are_overstaying_a_charge_stall', false,
  'forces_recert FALSE, grounds asserted by P4: no ottoq_hash_* atom function reads '
  'ottoq_build_decision_frame, so none of the fourteen can see the new key. STATED PLAINLY because it is '
  'the one real consequence: ottoq_capture_decision_snapshot DOES read the frame builder, so stored '
  'content_hash values shift from here on -- tolerable and not a recert trigger because content_hash is '
  'deliberately OUTSIDE the fourteen (CLAUDE.md after 0216/0280: it stays out until a flagship round '
  'promotes it). Determinism is unaffected: the key is a pure function of committed rows, so two arms on '
  'one seed still agree; what breaks is comparability of content_hash ACROSS this change. The wiring half '
  'of G81. ottoq_release_expired_bookings already detects the overstay and names it '
  'release_reason=''window_elapsed_occupied'', and that string had ONE writer and ZERO readers anywhere in '
  'the database or the repo -- 162 occurrences against 143 clean expiries on run 3fb415d8, with a DCFC '
  'held 188 minutes past its window and an L2 at 241. The consequence (G80): holds_charge_place reads '
  'false for an overstaying vehicle -- CORRECTLY, it holds no BOOKED charge place -- so vehicle_is_held '
  'judges it plannable and the proposer offers it a second charge stall it does not need. Nothing in that '
  'chain is a proposer bug; it reasons correctly from what it is shown and is simply not shown the '
  'overstay. Added to the EXISTING g.facts >= 1 block beside holds_charge_place, reusing the '
  'proposer_frame_facts gate that 0265/0287/0292 used (rule 5); measured, that is the only tier in the '
  'function and the catalog caps the key at 1. A trap recorded: the bridge prints frame_facts_version 3, '
  'which is the BRIDGE''S constant, not this function''s tier -- treating it as one would have added a '
  'g.facts >= 3 block that never fires. DELIBERATELY A SEPARATE KEY: overwriting holds_charge_place would '
  'change proposer behaviour silently. THIS FILE CANNOT CHANGE AN ASSIGNMENT -- it only publishes the '
  'fact; consuming it in vehicle_is_held is a separate change with its own paired-seed before/after, '
  'because G80 needed three revisions for moving faster than its evidence. P6 asserts the published key '
  'AGREES with 0365''s independent instrument rather than merely existing: a key that is always false '
  'would look installed and say nothing.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
