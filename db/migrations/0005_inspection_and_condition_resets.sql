-- migration-version: PENDING
-- migration-name:    inspection_and_condition_resets

-- ============================================================================
-- 0005_inspection_and_condition_resets.sql
--
-- THE SHORT VERSION, IN PLAIN LANGUAGE
--
-- 0004 made a service completion move the ledger the depot actually reads. It worked --
-- 14 profiles moved, all completion-driven, zero spurious. And fleet health still got
-- WORSE across run 909: overdue-or-critical 75.9% at boot -> 82.8% at the end, rising
-- the whole way, and not one vehicle ever graded `ok`.
--
-- Two reasons, both measured, both the SAME disease 0004 diagnosed -- a fact kept in two
-- places, where the completion updates one and the decision reads the other.
--
--   (A) THE WORK THAT ACTUALLY GETS DONE IS NOT BAY WORK, AND ONLY BAY WORK COUNTS.
--       0004 wired the reset into ottoq_wear_mark_serviced, which the sim calls from
--       exactly one place: a BAY EXIT. But most completed work in this depot never sees
--       a bay. Inspections, cabin tidies, sensor cleans and item retrievals are performed
--       at a stall or at the charger and are closed by a different function entirely --
--       one that has never called the reset. The single biggest category of completed
--       work in the depot credits nothing.
--
--   (B) A CAR CAN BE PHYSICALLY CLEAN AND GRADE DIRTY FOREVER.
--       The card grades cleanliness on a date AND a condition, and 0004 only moved the
--       date. The condition columns on vehicle_need_profile are a snapshot taken once at
--       boot and never touched again -- so a vehicle that just left the detail bay still
--       reads `soiled`.
--
-- This file connects the completion path that was never wired, and makes the condition
-- columns move in the same transaction as the dates.
--
-- ============================================================================
-- DIAGNOSIS AS HANDED TO ME -- WHAT I CONFIRMED, WHAT I EXTENDED, WHAT I CORRECTED
--
-- Every number below was measured live on this database on 2026-08-04, against run
-- b049db50-6407-4b63-9666-a66c5922c067 ("run 909", sim_clock 13:00:00 -> 16:00:16, i.e.
-- 180 sim-min). No run is running: all ottoq_sim_runs rows read `completed`, so run 909's
-- data is intact and nothing here races a tick. Nothing in this section wrote anything.
--
--   CONFIRMED (1) -- INSPECTION IS THE DOMINANT COMPLETED WORK TYPE.
--     Done atoms in run 909, by service:
--         interior_inspection   90      <-- largest single work type
--         readiness_check       69      (a pre-departure check, not work)
--         interior_tidy         26
--         triage_check          24      (a diagnosis, not work)
--         item_retrieval         5
--         sensor_clean           5
--         remote_diagnostics     5
--         mechanical_pm          1
--     n = 225 done atoms. Excluding the two pure checks, interior_inspection is 90 of
--     132 = 68% of all completed work. The brief said "92 of 161"; I measure 90 with a
--     denominator of 132 (or 225 including checks). Same finding, and I state my own
--     denominator rather than adopt one I cannot reproduce.
--     The booking side agrees even more strongly: ottoq_stall_bookings with state='done'
--     reads inspect 190, staging 49, wash 17, service 7, detail 3. Real bay work --
--     wash + service + detail -- is 27 completions. Inspect alone is 190.
--
--   CONFIRMED (2) -- THE INSPECTION COMPLETION PATH NEVER CALLS THE RESET.
--     Scanning pg_get_functiondef across public, ottoq and twin for the string
--     'ottoq_wear_mark_serviced' returns exactly three functions, unchanged since 0004:
--         public.ottoq_wear_mark_serviced        (itself)
--         public.ottoq_ingest_service_complete   (the real-telemetry seam)
--         twin.ottoq_sim_advance_service_flow    (the SIM BAY EXIT, and only that)
--     Inspections do not exit a bay. They are performed at an `arrival_inspection` zone
--     stall booked by ottoq.ottoq_enact_inspection_seam, whose own completion bookkeeping
--     is this and only this -- quoted verbatim from the live body:
--         UPDATE public.ottoq_itinerary_legs l
--            SET status = 'done', actual_end_sim = p_clock
--          WHERE l.sim_run_id = p_sim_run_id
--            AND l.leg_type   = v_leg_type
--            AND l.status     = 'planned'
--            AND EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
--                         WHERE b.leg_id = l.leg_id AND b.sim_run_id = p_sim_run_id
--                           AND b.purpose = 'inspect' AND b.state = 'done');
--     It closes a leg. It does not touch a ledger, and it never calls anything that does.
--     Confirmed exactly as stated in the brief.
--
--   EXTENDED (3) -- IT IS NOT JUST INSPECTIONS. IT IS EVERY NON-BAY COMPLETION.
--     This is the finding the brief did not have, and it is bigger than the one it did.
--     The function that actually marks concurrent work finished is
--     twin.ottoq_sim_advance_visit_atoms. Its inner loop is the moment a service becomes
--     done in this system -- verbatim:
--         IF v_feed_sim AND v_a->>'status' = 'in_progress'
--            AND (v_a->>'ends_at')::timestamptz <= p_clock THEN
--           v_a := v_a || jsonb_build_object('status','done','done_at', v_a->'ends_at');
--           v_changed := true; v_total := v_total + 1;
--           PERFORM ottoq_close_atom_leg(...);
--     It closes the leg. It does not call ottoq_wear_mark_serviced -- confirmed by the
--     three-caller scan above. So in run 909 the following completions credited NOTHING:
--         interior_inspection  90    interior_tidy   26
--         item_retrieval        5    sensor_clean     5    remote_diagnostics 5
--     interior_tidy and sensor_clean matter especially, because ottoq_wear_mark_serviced
--     ALREADY contains the correct reset for both (cabin_litter_events = 0 and
--     soil_index = 0 respectively) -- written, tested, and unreachable outside a bay.
--     Fixing only the inspection path would have left 36 more completions uncredited and
--     required a second migration to find the same bug again.
--
--   CONFIRMED (4) -- THE CARD GRADES ON THE PROFILE'S CONDITION COLUMNS.
--     Quoted from the LIVE pg_get_viewdef('public.ottoq_vehicle_needs_card'), where `c`
--     resolves to vehicle_need_profile columns carried through base -> calc -> grade:
--         ottoq_urgency_max(ottoq_service_urgency('exterior_wash'::text, c.wash_ratio),
--             CASE WHEN c.exterior_soil_level >= 0.85 THEN 'overdue'
--                  WHEN c.exterior_soil_level >= 0.65 THEN 'due'
--                  WHEN c.exterior_soil_level >= 0.45 THEN 'due_soon'
--                  ELSE 'ok' END) AS wash_urgency,
--         ottoq_urgency_max(ottoq_service_urgency('interior_deep_clean'::text, c.deep_clean_ratio),
--             CASE WHEN c.cabin_condition = 'biohazard'    THEN 'critical'
--                  WHEN c.cabin_condition = 'soiled'       THEN 'overdue'
--                  WHEN c.cabin_condition = 'light_litter' THEN 'due_soon'
--                  ELSE 'ok' END) AS cabin_urgency,
--     Both halves confirmed exactly as the brief describes. The same shape recurs on four
--     more dimensions the brief did not enumerate, all reading profile columns that
--     nothing ever resets:
--         calib_urgency    ... c.sensor_health_pct < 89 / < 91
--         fault_urgency    ... c.worst_fault_severity = 1 / <= 3 / <= 5
--         software_urgency ... c.software_version IS DISTINCT FROM c.sw_target_version
--         item_urgency     ... CASE WHEN c.item_retrieval_pending THEN 'due' ELSE 'ok' END
--
--   CONFIRMED (5) -- THE SMOKING GUN, REPRODUCED, PLUS THE FLEET-WIDE VERSION.
--     Vehicle 99ddf4ff-96d7-4257-b1ce-cb9437335ce8, live right now:
--         wear.soil_index  0           profile.exterior_soil_level  0.595
--         wear.cabin_litter_events 0   profile.cabin_condition      'soiled'
--         wash_ratio 0.001             deep_clean_ratio 0.000
--         => wash_urgency 'due_soon', cabin_urgency 'overdue'
--     Physically spotless on both ledgers the twin maintains; graded overdue on the one
--     the depot reads. b2222222-0002-0002-0002-000000000001 is the same story:
--     soil_index 0, exterior_soil_level 0.855, wash_ratio 0.028 => wash_urgency 'overdue'.
--     And this is not two unlucky rows. Fleet-wide, n = 116:
--         exterior_soil_level <> soil_index                      116 of 116  (100%)
--         mean exterior_soil_level 0.462  vs  mean soil_index 0.217
--         cabin_litter_events = 0 but cabin_condition <> 'clean'  50 of 116  (43%)
--     THE READ LEDGER SAYS THIS FLEET IS 2.1x DIRTIER THAN THE TRUTHFUL LEDGER SAYS IT IS.
--     That is a large part of why 96 of 116 vehicles grade overdue-or-critical today.
--
--   CONFIRMED (6) -- THE WEAR TABLE'S COPIES ARE ALREADY MAINTAINED. DO NOT DUPLICATE.
--     ottoq_vehicle_wear.soil_index and .cabin_litter_events are accrued by
--     twin.ottoq_sim_advance_wear_counters and reset by ottoq_wear_mark_serviced PART 1,
--     which this file reproduces byte-for-byte and does not touch. Confirmed as stated.
--     Nothing in this migration writes ottoq_vehicle_wear. (0004 CORRECTION A still holds:
--     the negative km_at_last_pm values in that table are deliberate phase offsets.)
--
--   ─────────────────────────────────────────────────────────────────────────
--   CORRECTION A -- THE BRIEF'S INSPECTION MAP CANNOT BE BUILT AS SPECIFIED, AND
--   BUILDING IT ANYWAY WOULD BE THE MOST DANGEROUS THING IN THIS FILE.
--
--     The brief asks me to "map each inspection type to the profile column(s) it should
--     advance (e.g. sensor/calibration checks, tire/brake inspections, battery health)".
--     There are no inspection types. There is one:
--
--       * public.service_cadence_policy holds 15 active services. Exactly one is an
--         inspection: `interior_inspection`, lane 'cabin', est_min_default 4.
--       * public.ottoq_svc_to_leg_type maps it, and nothing else, to leg_type 'inspect':
--             WHEN p_svc = 'interior_inspection' THEN 'inspect'
--       * ottoq.ottoq_enact_inspection_seam hard-codes it:
--             c_svc CONSTANT text := 'interior_inspection';
--       * No sensor-inspection, tire-inspection, brake-inspection or battery-health
--         service string is emitted anywhere in the twin's vocabulary.
--
--     So there is no subtype to map, and the brief's own scope forbids the alternative:
--     "do NOT invent a subtype that isn't emitted". I am not inventing one.
--
--     AND THE DEEPER PROBLEM IS THAT AN INSPECTION IS NOT A SERVICE.
--     A 4-minute cabin inspection at an arrival stall OBSERVES the vehicle. It does not
--     calibrate a sensor, rotate a tire, service a brake or condition a battery. If I
--     credit `interior_inspection` with `last_calibration_at := now`, then 90 inspections
--     silently mark 90 calibrations done that nobody performed -- the fleet's health
--     numbers improve on this run and every one of those vehicles deploys carrying an
--     un-serviced sensor. Under ALWAYS-HOLD ("a vehicle never deploys with known
--     outstanding service") that is not a cosmetic error, it is the one error class the
--     doctrine exists to prevent. It would also destroy the very measurement this phase
--     is for: a convergence curve produced by crediting work that was never done proves
--     nothing at all.
--
--     WHAT AN INSPECTION LEGITIMATELY PRODUCES IS AN OBSERVATION, AND THAT IS EXACTLY
--     WHAT SCOPE (b) IS SHORT OF. So the inspection is wired to refresh the condition
--     reading from the truthful ledger, and to advance nothing else. That is the honest
--     map, and it happens to be the one the two halves of this brief were converging on.
--     Full map in §2.
--
--   CORRECTION B -- "MAKE THE CARD READ ottoq_vehicle_wear INSTEAD" IS THE WRONG
--   DIRECTION FOR THE ONE-LEDGER GOAL. THE ARROW POINTS THE OTHER WAY.
--
--     The brief asks me to decide deliberately whether the card should read the wear
--     table instead of the profile's copies, since one live ledger is the goal.
--     ⭐ DECIDED: NO. vehicle_need_profile stays the one ledger the card reads;
--        ottoq_vehicle_wear stays the run-scoped physics accumulator that FEEDS it.
--
--     Three reasons, in order of weight:
--
--       1. ottoq_vehicle_wear IS RUN-SCOPED AND DOES NOT EXIST IN PRODUCTION.
--          Its primary key is (vehicle_id, sim_run_id). In a real depot there is no
--          ottoq_sim_runs row, so there is no wear row, so a card that graded cleanliness
--          from soil_index would grade every real vehicle 'ok' forever. The needs card is
--          the PRODUCTION decision surface. Repointing it at a run-scoped table is
--          building a sim-only path, which is precisely the rule this repo forbids.
--          vehicle_need_profile is keyed on vehicle_id alone and survives a run change --
--          it is the only one of the two that can be the production ledger.
--
--       2. THE PROJECTION ALREADY EXISTS AND IS THE SYSTEM'S OWN IDENTITY, NOT MY IDEA.
--          ottoq_seed_vehicle_need_profiles already defines the profile column as the
--          wear column, verbatim from the live body:
--              round(COALESCE(d.soil_index, LEAST(1.0, 0.05 + 0.85 * d.r_soil * d.soil_rate))::numeric, 3) AS soil_lvl
--          exterior_soil_level IS soil_index -- same 0..1 scale (ottoq_vehicle_wear has
--          CHECK (soil_index >= 0 AND soil_index <= 1)), same rounding, copied at boot and
--          then frozen. The defect is not that a projection exists. It is that it is
--          performed ONCE. This file performs it at every completion. No new mapping is
--          introduced and no threshold is chosen.
--
--       3. REBUILDING A 24,588-CHARACTER VIEW TO CHANGE WHERE A GRADE COMES FROM IS A
--          TUNING CHANGE WEARING A WIRING COSTUME. Every urgency in the card would be in
--          the blast radius, and "dirty" would come to mean something different, which is
--          exactly what this migration is forbidden from doing.
--
--     Net: ONE ledger is read (the profile), ONE ledger is accrued (wear), and the link
--     between them is a copy performed at the moment of completion. Nothing is accrued
--     twice and nothing has two opinions.
--
-- CAUSE, IN ONE SENTENCE
--   0004 wired the completion reset into the bay exit, and most work in this depot never
--   goes near a bay -- and even the work that does only moved the dates, never the
--   conditions the same card grades on.
--
-- FIX  (this file, in order)
--   §1  snapshots + md5 guards for the three functions being replaced.
--   §2  public.ottoq_wear_mark_serviced -- the condition columns join the date columns,
--       in the same statement, same transaction. Scope (b). PART 1 untouched.
--   §3  twin.ottoq_sim_advance_visit_atoms -- the missing sim caller. One guarded
--       PERFORM. Scope (a), and everything in EXTENDED (3) with it.
--   §4  public.ottoq_run_boot_draw -- anchor the odometer watermark at boot, which is
--       the KNOWN LIMITATION from 0004. Fixed here; reasoning in §4.
--   §5  post-snapshots.  §6 verification.
--
-- WHAT THIS FILE DELIBERATELY DOES NOT DO
--   * It does NOT enable ottoq_apply_need_escalation. Still 0 callers, still dry-run by
--     default. Against a fleet that is 82.8% overdue it would make ~96 vehicles' bay work
--     mandatory at once against 2 service bays and 3 wash bays. That is a throughput
--     collapse, and it stays gated behind a fleet that has been SHOWN to converge.
--   * It does NOT retune one interval, must_do_at, threshold or multiplier. Every value
--     written below is either copied from an observed column (soil_index, sw_target_version,
--     drive_km_total, the atom's own ends_at) or is a literal already in the system's
--     closed vocabulary ('clean', 99, false). None is chosen by me.
--   * It does NOT write ottoq_vehicle_wear, and does NOT rebuild ottoq_vehicle_needs_card.
--   * It does NOT move interior deep-clean out of the bay system and does NOT make
--     exterior wash mileage-triggered. Both are founder decisions of 2026-08-04, both are
--     behaviour changes, and both need a ledger that moves first. §4 removes the last
--     blocker under the mileage one.
--   * It does NOT touch the LP formulation, CSR build, cuOpt parse path, Gate B,
--     verify_jwt, ottoq_events, or public.ottoq_decide_tick.
--
-- BLAST RADIUS
--   Three functions replaced, none created, none dropped -- so the routine count is
--   unchanged and no name needs justifying against db/baseline/functions_public.sql.
--     ottoq_wear_mark_serviced        2 callers, both PERFORM, return contract preserved.
--     ottoq_sim_advance_visit_atoms   called from the tick; body byte-identical except
--                                     one guarded PERFORM block (see §3).
--     ottoq_run_boot_draw             runs once at run boot, outside the tick entirely.
--   No table gains or loses a column: 0004 already added the two watermark columns and
--   they are live (confirmed in information_schema today). No index, no constraint, no
--   grant, no policy.
--   The protected phase-11/14 baseline is untouched by construction: nothing here books,
--   releases, picks or prices a space, and nothing here moves an urgency threshold.
--
-- VERIFY
--   §6, plus a bounded run of >= 139 sim-min captured AFTER the run is stopped, in the
--   SIM domain, gated on arrivals, primary metric per ARRIVING VEHICLE.
--   ⚠️ COMPARE LIKE FOR LIKE: run 909's own post-boot baseline is 75.9% overdue-or-critical,
--      NOT run 908's 84.5% (different sim_clock_start, different draw). The next run will
--      have its own boot baseline again; capture it at boot and compare against THAT.
--
-- METHOD NOTE ON THE md5 GUARDS
--   All three expected hashes were computed LIVE from this database at authoring time
--   (2026-08-04), compared as
--       md5(rtrim(pg_get_functiondef(oid), E' \n\r\t'))
--   so a trailing-newline difference cannot cause a false abort. If any live body has
--   drifted since, this migration REFUSES TO APPLY, changes nothing, and drops nothing.
--   Re-read the live body, re-base, re-run.
-- ============================================================================


-- ============================================================================
-- §1  SNAPSHOT, THEN GUARD  (house rule 1)
--
-- Recover any of these later with:
--   SELECT definition FROM public.ottoq_schema_snapshots
--    WHERE label = '0005_inspection_and_condition_resets_pre' AND object_name = '<fn>';
-- ============================================================================
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0005_inspection_and_condition_resets_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname = 'public' AND p.proname IN ('ottoq_wear_mark_serviced',
                                               'ottoq_run_boot_draw'))
    OR (n.nspname = 'twin'   AND p.proname  = 'ottoq_sim_advance_visit_atoms');

DO $guard$
DECLARE
  v_expect CONSTANT jsonb := jsonb_build_object(
    'public.ottoq_wear_mark_serviced',    '7fd07989b82ff8d767238ad5ed87b424',
    'twin.ottoq_sim_advance_visit_atoms', 'cb864b7ba0755c472f5467693fa25c71',
    'public.ottoq_run_boot_draw',         '8981e6d353e957b089294ea153cb77d8');
  k text; v_actual text; v_n int;
BEGIN
  FOR k IN SELECT jsonb_object_keys(v_expect) LOOP
    SELECT count(*), min(md5(rtrim(pg_get_functiondef(p.oid), E' \n\r\t')))
      INTO v_n, v_actual
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = split_part(k, '.', 1)
       AND p.proname = split_part(k, '.', 2);

    IF v_n = 0 THEN
      RAISE EXCEPTION
        'GUARD: % does not exist. This migration expected to REPLACE it, not create it. Aborting.', k;
    ELSIF v_n > 1 THEN
      RAISE EXCEPTION
        'GUARD: % has % overloads. This migration assumes exactly one signature. Aborting.', k, v_n;
    ELSIF v_actual <> (v_expect->>k) THEN
      RAISE EXCEPTION
        'GUARD: % live md5 % does not match expected %. Someone changed this function outside this migration. Re-read the live body, re-base, re-run. Nothing has been changed.',
        k, v_actual, (v_expect->>k);
    END IF;
  END LOOP;
  RAISE NOTICE 'GUARD: all three target functions match their expected definitions.';
END
$guard$;

-- A second guard on the thing the whole file assumes: 0004's watermark columns exist.
-- Cheaper to fail here with a sentence than to fail inside a tick with a 42703.
DO $cols$
DECLARE v_missing text[];
BEGIN
  SELECT array_agg(c) INTO v_missing FROM unnest(ARRAY[
      'wear_km_applied','wear_km_applied_run','exterior_soil_level','cabin_condition',
      'item_retrieval_pending','open_fault_codes','worst_fault_severity',
      'software_version','sw_target_version']) c
   WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                      WHERE table_schema='public' AND table_name='vehicle_need_profile'
                        AND column_name = c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'GUARD: vehicle_need_profile is missing % . Apply 0004 first. Aborting.', v_missing;
  END IF;
  RAISE NOTICE 'GUARD: vehicle_need_profile carries every column this migration writes.';
END
$cols$;


-- ============================================================================
-- §2  public.ottoq_wear_mark_serviced  — THE CONDITION COLUMNS JOIN THE DATES
--                                        (scope (b), and the receiving half of scope (a))
--
-- ── WHAT CHANGED, EXACTLY ───────────────────────────────────────────────────
-- PART 1 (the ottoq_vehicle_wear update) is reproduced BYTE-FOR-BYTE from 0004, which
-- reproduced it byte-for-byte from the original. It is certified and it is protected.
-- PART 2 (the vehicle_need_profile update, introduced by 0004) keeps every line it had --
-- the odometer advance, the four date resets, km_at_last_pm, the watermark -- and gains
-- the condition columns. Two mechanical additions make that possible:
--   * the existing SELECT that already reads drive_km_total now also reads soil_index,
--     and it already runs AFTER part 1, so it observes the POST-reset value;
--   * the vocabulary handled grows by three codes that were previously ELSE no-ops.
--
-- ── THE FULL SERVICE -> COLUMN MAP (dates from 0004, conditions new here) ───
-- Vocabulary is everything the two callers can pass: the bay array from
-- twin.ottoq_sim_advance_service_flow, the atom svc from twin.ottoq_sim_advance_visit_atoms
-- (new in §3), and whatever a technician or OEM reports through
-- public.ottoq_ingest_service_complete.
--
--   exterior_wash        -> last_wash_at        := p_clock                     [0004]
--                           exterior_soil_level := soil_index (now 0)          [NEW]
--   interior_deep_clean  -> last_deep_clean_at  := p_clock                     [0004]
--                           cabin_condition     := 'clean'                     [NEW]
--                           exterior_soil_level := soil_index (now 0)          [NEW]
--   interior_tidy        -> cabin_condition     := 'clean' IF 'light_litter'   [NEW]
--   sensor_clean         -> exterior_soil_level := soil_index (now 0)          [NEW]
--   sensor_calibration   -> last_calibration_at := p_clock                     [0004]
--   mechanical_pm        -> last_pm_at          := p_clock                     [0004]
--                           km_at_last_pm       := odometer_km, POST-advance   [0004]
--                           open_fault_codes    := '{}'                        [NEW]
--                           worst_fault_severity:= 99                          [NEW]
--   fault_repair         -> open_fault_codes    := '{}'                        [NEW]
--                           worst_fault_severity:= 99                          [NEW]
--   software_update      -> software_version    := sw_target_version           [NEW]
--   item_retrieval       -> item_retrieval_pending := false                    [NEW]
--   interior_inspection  -> exterior_soil_level := soil_index (observation)    [NEW]
--   cosmetic_repair      -> nothing (no due-date and no condition dimension)
--   readiness_check      -> nothing (a pre-departure check restores nothing)
--   triage_check         -> nothing (a diagnosis, not work)
--   remote_diagnostics   -> nothing (see GAP 2)
--   perimeter_walkaround -> nothing, and it does not error (see the totality note)
--   ANY of the above     -> exterior_soil_level refreshed from soil_index, and
--                           odometer_km advanced by the un-credited part of
--                           drive_km_total. Both unconditional: soil is observed and
--                           mileage accrues regardless of which service just finished.
--
-- ── WHY exterior_soil_level IS A COPY AND NOT A RULE ────────────────────────
-- The temptation is a per-service CASE: "wash zeroes it, tidy doesn't, ...". That would
-- be a SECOND opinion about how dirty the car is, sitting next to the twin's, free to
-- disagree with it -- which is the disease, re-introduced one layer down. Instead the
-- column takes the value the truthful ledger holds at that instant:
--       exterior_soil_level := round(soil_index, 3)
-- The rounding is not mine: it is the seeder's own expression, quoted in CORRECTION B.
-- Because PART 1 has already run, soil_index is 0 for exterior_wash / sensor_clean /
-- interior_deep_clean and the live accrued value for everything else. One expression
-- covers every service, and every future service, correctly and forever.
-- CONSEQUENCE, STATED PLAINLY: this inherits PART 1's pre-existing rule that a
-- `sensor_clean` zeroes soil_index. I do not agree that washing a sensor washes the body,
-- but PART 1's rule is certified behaviour and having the two ledgers disagree is strictly
-- worse than having one debatable rule. Recorded as GAP 1, not silently overridden here.
--
-- ── WHY cabin_condition IS A RULE AND NOT A COPY ────────────────────────────
-- Because there is nothing to copy. Unlike soil, the seeder does NOT derive
-- cabin_condition from ottoq_vehicle_wear.cabin_litter_events -- it draws it from an
-- independent random:
--       CASE WHEN c.r_cabin < 0.02 THEN 'biohazard'
--            WHEN c.r_cabin < 0.14 THEN 'soiled'
--            WHEN c.r_cabin < 0.45 THEN 'light_litter'
--            ELSE 'clean'
-- Inventing a litter-count -> label banding would be choosing two numbers, i.e. tuning,
-- which this file may not do. So the only writes are the ones a completion states with
-- certainty, using the seeder's own four labels and adding none:
--   * interior_deep_clean -> 'clean'. A deep clean is the depot's remediation for a
--     soiled or biohazard cabin; that is what the detail bay is for.
--   * interior_tidy -> 'clean' ONLY IF the cabin currently reads 'light_litter'. A tidy
--     clears litter. It does not fix soiling and it certainly does not clear a biohazard,
--     so it is not allowed to claim it did. This one predicate is the single judgement
--     call in this file. The conservative alternative was to leave cabin_condition to
--     deep cleans alone; I rejected it because PART 1 already zeroes cabin_litter_events
--     on interior_tidy, so declining here would manufacture a fresh divergence between
--     the two ledgers on the very fact this migration exists to reconcile.
--   * An inspection does NOT write it. See CORRECTION A -- observing a cabin is not
--     cleaning it, and there is no observation payload on either seam to write from.
--     This is why 50 of 116 vehicles reading `cabin_litter_events = 0` with a dirty label
--     will NOT all clear on the next run. Predicted here so the result cannot be
--     misread later as this migration failing. See GAP 3.
--
-- ── WHY worst_fault_severity := 99 AND NOT 0 OR NULL ────────────────────────
-- 99 is the sentinel PART 1 already uses for worst_open_dtc_rank on exactly these two
-- services, and the card's fault ladder is
--       CASE WHEN c.worst_fault_severity = 1 THEN 2.00 WHEN <= 3 THEN 1.30
--            WHEN <= 5 THEN 0.80 ELSE 0.00 END
-- so 99 lands on ELSE 0.00 -> 'ok'. 0 would land on `<= 3` and grade a repaired vehicle
-- 'overdue' forever -- the exact inversion this file is here to remove. Severity is a
-- rank where lower is worse, and reading it as a count is how that trap is sprung.
--
-- ── WHY software_version := sw_target_version IS NOT A CHOSEN VALUE ─────────
-- It copies a column already on the same row. "The update installed the version it was
-- targeting" is what a completed software_update means; the card's sw_behind is literally
-- `software_version IS DISTINCT FROM sw_target_version`. Same shape as 0004's
-- km_at_last_pm := odometer_km: an observed quantity moved, never a constant invented.
-- COALESCEd so a NULL target can never blank a real version string.
--
-- ── IDEMPOTENCY: HOW A COMPLETION CANNOT DOUBLE-APPLY ───────────────────────
--   1. EVERY NEW WRITE IS AN ABSOLUTE ASSIGNMENT, NOT AN INCREMENT. Copies
--      (exterior_soil_level, software_version), literals ('clean', 99, false, '{}') and
--      clock stamps all land on the same value the second, third and hundredth time.
--      There is no accumulator anywhere in PART 2 except the odometer.
--   2. THE ONE CONDITIONAL WRITE IS SELF-EXTINGUISHING. interior_tidy fires only while
--      cabin_condition = 'light_litter'; after it fires the value is 'clean' and the
--      predicate is false. Re-running is a no-op, and it can never walk a cabin backwards.
--   3. THE ODOMETER KEEPS 0004'S WATERMARK FENCE, unchanged: credit is
--      GREATEST(0, drive_km_total - wear_km_applied) and the watermark is then set to
--      drive_km_total in the same statement, run-scoped. §4 only changes WHERE the
--      watermark is first anchored, never how it is spent.
--   Net: safe to call any number of times, in any order, for any subset of services,
--   from either seam -- which matters, because ottoq_ingest_service_complete loops
--   FOREACH over p_services and an OEM may re-report a completion it already reported.
--
-- ── TOTAL FUNCTION OVER BOTH SEAMS, AND OVER AN OPEN VOCABULARY ─────────────
-- Unchanged from 0004 and re-stated because §3 widens the input set considerably. The
-- profile update is NOT conditional on the wear UPDATE having matched a row: in
-- production there is no sim run and no wear row, but the vehicle was still serviced and
-- its due dates still have to move. So the date resets need only p_clock and always
-- apply; the soil copy and the odometer advance need a wear row and, absent one, change
-- nothing rather than guessing. Every unmapped service code -- including
-- `perimeter_walkaround`, which is live in ottoq_visit_needs today and which §3 will now
-- route through here -- falls through every CASE and is a silent no-op, never an error.
-- That is the leg_type lesson: a seam between an OPEN vocabulary and a CLOSED set of
-- columns must be a TOTAL function, or one unmapped string aborts the transaction.
--
-- ── FAILURE IS LOUD, NEVER SILENT, NEVER FATAL ─────────────────────────────
-- Unchanged from 0004: the profile update is wrapped so a failure warns by name and
-- leaves PART 1 -- the certified behaviour -- standing. This function is now reachable
-- from two places inside a tick instead of one, so that property matters twice as much.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_wear_mark_serviced(p_vehicle_id uuid, p_sim_run_id uuid, p_service text, p_clock timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_wear_found boolean;
  v_drive_km   numeric;   -- ottoq_vehicle_wear.drive_km_total for this vehicle+run
  v_soil       numeric;   -- 0005: ottoq_vehicle_wear.soil_index, read AFTER part 1
BEGIN
  -- ══════════════ PART 1 — THE WEAR LEDGER (UNCHANGED, BYTE-FOR-BYTE) ══════════════
  UPDATE ottoq_vehicle_wear w SET
    soil_index = CASE WHEN p_service IN ('exterior_wash','sensor_clean','interior_deep_clean')
                      THEN 0 ELSE w.soil_index END,
    cabin_litter_events = CASE WHEN p_service IN ('interior_tidy','interior_deep_clean')
                      THEN 0 ELSE w.cabin_litter_events END,
    km_at_last_pm = CASE WHEN p_service = 'mechanical_pm'
                      THEN w.drive_km_total ELSE w.km_at_last_pm END,
    hours_at_last_calibration = CASE WHEN p_service = 'sensor_calibration'
                      THEN w.drive_hours_total ELSE w.hours_at_last_calibration END,
    calibrated_at = CASE WHEN p_service = 'sensor_calibration'
                      THEN p_clock ELSE w.calibrated_at END,
    open_dtc_count = CASE WHEN p_service IN ('fault_repair','mechanical_pm')
                      THEN 0 ELSE w.open_dtc_count END,
    worst_open_dtc_rank = CASE WHEN p_service IN ('fault_repair','mechanical_pm')
                      THEN 99 ELSE w.worst_open_dtc_rank END,
    updated_at = now()
  WHERE w.vehicle_id = p_vehicle_id AND w.sim_run_id = p_sim_run_id;

  -- Captured HERE, before anything else can move FOUND. See the header note.
  v_wear_found := FOUND;

  -- ══════════════ PART 2 — 0004: THE SAME TRUTH, IN THE LEDGER THAT IS READ ══════════════
  -- ══════════════          0005: ...INCLUDING THE CONDITION IT IS GRADED ON ══════════════
  -- Self-silencing by design: a failure here warns by name and leaves PART 1 standing.
  BEGIN
    -- The run-scoped counters. NULL in production (no run, no wear row), which the
    -- arithmetic below treats as "credit nothing / change nothing" rather than an error.
    -- 0005: soil_index is read HERE, i.e. AFTER part 1, so it is already 0 for the three
    -- services that clean the vehicle and is the live accrued value for every other.
    SELECT w.drive_km_total, w.soil_index
      INTO v_drive_km, v_soil
      FROM ottoq_vehicle_wear w
     WHERE w.vehicle_id = p_vehicle_id
       AND w.sim_run_id = p_sim_run_id
     LIMIT 1;

    UPDATE public.vehicle_need_profile p SET
      -- ── scope (b) of 0004: ODOMETER, ADVANCED IDEMPOTENTLY ────────────────
      -- Credit only the part of drive_km_total not already credited. A watermark from
      -- a different run (or none) means "unknown" -> credit 0 and re-anchor. 0005 §4
      -- anchors it at boot so the FIRST completion of a run credits real km.
      odometer_km = COALESCE(p.odometer_km, 0) + GREATEST(0,
                      COALESCE(v_drive_km, 0)
                      - CASE WHEN p.wear_km_applied_run IS NOT DISTINCT FROM p_sim_run_id
                             THEN COALESCE(p.wear_km_applied, COALESCE(v_drive_km, 0))
                             ELSE COALESCE(v_drive_km, 0) END),

      -- ── scope (a) of 0004: LAST-DONE, PER SERVICE ─────────────────────────
      -- Every branch is an absolute assignment of an observed clock. No accumulator,
      -- no chosen constant, no interval arithmetic. Unmapped codes fall through the
      -- ELSE and change nothing.
      last_wash_at = CASE WHEN p_service = 'exterior_wash'
                          THEN p_clock ELSE p.last_wash_at END,
      last_deep_clean_at = CASE WHEN p_service = 'interior_deep_clean'
                          THEN p_clock ELSE p.last_deep_clean_at END,
      last_calibration_at = CASE WHEN p_service = 'sensor_calibration'
                          THEN p_clock ELSE p.last_calibration_at END,
      last_pm_at = CASE WHEN p_service = 'mechanical_pm'
                          THEN p_clock ELSE p.last_pm_at END,

      -- PM mileage mark. Takes the POST-advance lifetime odometer -- recomputing the
      -- same advance expression inline, because SET clauses all read the row's OLD
      -- values and p.odometer_km above is not visible here. NOT wear.km_at_last_pm:
      -- that column is run-scoped and would read as ~zero lifetime km. See 0004.
      km_at_last_pm = CASE WHEN p_service = 'mechanical_pm'
                          THEN COALESCE(p.odometer_km, 0) + GREATEST(0,
                                 COALESCE(v_drive_km, 0)
                                 - CASE WHEN p.wear_km_applied_run IS NOT DISTINCT FROM p_sim_run_id
                                        THEN COALESCE(p.wear_km_applied, COALESCE(v_drive_km, 0))
                                        ELSE COALESCE(v_drive_km, 0) END)
                          ELSE p.km_at_last_pm END,

      -- ══════════ 0005 scope (b): THE CONDITION COLUMNS THE CARD ALSO GRADES ON ══════════

      -- EXTERIOR SOIL. A projection of the truthful ledger, not a per-service rule.
      -- Same 0..1 scale, same round(...,3) the seeder itself uses. When there is no wear
      -- row (production) the COALESCE leaves the column exactly as it was: no guess.
      -- This is also the ONLY thing an inspection writes -- an inspection observes.
      exterior_soil_level = COALESCE(round(v_soil, 3), p.exterior_soil_level),

      -- CABIN. Only what the completed work can honestly claim. A deep clean restores the
      -- cabin outright; a tidy clears litter and therefore may only lift 'light_litter'.
      -- Labels are the seeder's own vocabulary -- none invented. Self-extinguishing, so
      -- re-running is a no-op and a cabin can never be walked backwards.
      cabin_condition = CASE
                          WHEN p_service = 'interior_deep_clean' THEN 'clean'
                          WHEN p_service = 'interior_tidy'
                               AND p.cabin_condition = 'light_litter' THEN 'clean'
                          ELSE p.cabin_condition END,

      -- FAULTS. Mirrors PART 1's open_dtc_count = 0 / worst_open_dtc_rank = 99 for the
      -- same two services. 99 lands on the card's ELSE 0.00 branch = 'ok'; 0 would land
      -- on `<= 3` and grade a repaired vehicle overdue forever. Lower rank = worse.
      open_fault_codes = CASE WHEN p_service IN ('fault_repair','mechanical_pm')
                          THEN '{}'::text[] ELSE p.open_fault_codes END,
      worst_fault_severity = CASE WHEN p_service IN ('fault_repair','mechanical_pm')
                          THEN 99 ELSE p.worst_fault_severity END,

      -- SOFTWARE. Copies a column already on this row; sw_behind is defined as the
      -- inequality of these two. COALESCE so a NULL target cannot blank a real version.
      software_version = CASE WHEN p_service = 'software_update'
                          THEN COALESCE(p.sw_target_version, p.software_version)
                          ELSE p.software_version END,

      -- ITEMS. The retrieval IS the reset. item_reported_at / item_description are left
      -- alone deliberately: they are the record that it was reported, not the open flag.
      item_retrieval_pending = CASE WHEN p_service = 'item_retrieval'
                          THEN false ELSE p.item_retrieval_pending END,

      -- ── the watermark itself (0004, unchanged) ────────────────────────────
      -- Monotone within a run; re-anchored on a run change.
      wear_km_applied = CASE WHEN p.wear_km_applied_run IS NOT DISTINCT FROM p_sim_run_id
                             THEN GREATEST(COALESCE(p.wear_km_applied, 0), COALESCE(v_drive_km, 0))
                             ELSE COALESCE(v_drive_km, 0) END,
      wear_km_applied_run = p_sim_run_id,

      updated_at = now()
    WHERE p.vehicle_id = p_vehicle_id;

  EXCEPTION WHEN OTHERS THEN
    -- House rule 4. Loud, named, non-fatal. The wear ledger write above survives.
    RAISE WARNING 'ottoq_wear_mark_serviced: vehicle_need_profile reset FAILED SAFELY for vehicle % service %: % %',
                  p_vehicle_id, p_service, SQLSTATE, SQLERRM;
  END;

  RETURN v_wear_found;
END;
$function$;


-- ============================================================================
-- §3  twin.ottoq_sim_advance_visit_atoms  — WIRE THE COMPLETION PATH THAT WAS
--                                            NEVER WIRED                (scope (a))
--
-- ── WHY HERE, AND NOWHERE ELSE ──────────────────────────────────────────────
-- This is the exact instant a service becomes finished in the sim for all non-bay work.
-- Three candidate hook points were considered and two rejected:
--
--   * ottoq.ottoq_enact_inspection_seam -- its leg UPDATE fires exactly once per
--     inspection (WHERE status = 'planned' -> 'done'), and it is provably live: of the
--     190 `inspect` bookings that reached state='done' in run 909, 190 carry a leg_id and
--     190 of those legs are 'done'. A perfectly good hook. REJECTED because it only knows
--     a LEG TYPE, not which service was performed, and because it would fix inspections
--     alone and leave interior_tidy, sensor_clean and item_retrieval to a later migration.
--   * ottoq.ottoq_release_expired_bookings -- the generic closer that actually flips the
--     inspect booking to 'done'. REJECTED: it closes charge, temp_hold, staging and
--     perimeter_hold too, and a `purpose` is not a service.
--   * ⭐ HERE. The atom carries the true `svc` string, so the map in §2 receives exactly
--     what was performed. One insertion covers every non-bay service that exists today
--     and every one added later, for free.
--
-- ── ONE CHANGE, AND THE BODY IS OTHERWISE BYTE-IDENTICAL ────────────────────
-- A single guarded block is inserted immediately after the existing
-- `PERFORM ottoq_close_atom_leg(...)` in the branch that marks an atom done. Nothing else
-- in this 9,273-character function moves. In particular:
--   * the readiness_check branch further down is NOT hooked -- a pre-departure check
--     restores nothing, and crediting it would be exactly the CORRECTION A error;
--   * the triage `clear` branch is NOT hooked -- an atom cancelled by triage was never
--     performed, and a cancellation must never read as a completion;
--   * the `v_feed_sim` guard is inherited, not added: on a real-telemetry feed this branch
--     does not run at all, and completions arrive through
--     public.ottoq_ingest_service_complete, which has called ottoq_wear_mark_serviced
--     since 0004 ungated it. That is why this is a sim-only CALLER of a shared function
--     and not a sim-only PATH -- the same shape twin.ottoq_sim_advance_service_flow
--     already has for bay work.
--
-- ── IDEMPOTENCY: EXACTLY ONCE PER COMPLETION, STRUCTURALLY ──────────────────
-- The branch is entered only while the atom reads status = 'in_progress', and its first
-- act is to rewrite that atom to status = 'done'. The rewritten array is persisted by the
-- `IF v_changed THEN UPDATE ottoq_visit_needs SET atoms = v_new` at the end of the loop,
-- so the atom can never match again on any later tick. One completion, one call. That is
-- on top of §2's own idempotency, which would make repeats harmless anyway.
--
-- ── THE CLOCK IS THE ATOM'S, NOT THE TICK'S ─────────────────────────────────
-- p_clock is when the tick noticed; (v_a->>'ends_at') is when the work actually finished,
-- and it is what the function already writes into done_at and passes to
-- ottoq_close_atom_leg. Passing the same instant to the ledger keeps last_wash_at,
-- done_at and the leg's actual_end_sim agreeing to the second. COALESCEd to p_clock so a
-- malformed atom degrades instead of failing.
--
-- ── FAILURE MUST NEVER ABORT THE TICK ───────────────────────────────────────
-- This function has NO top-level EXCEPTION handler -- an unguarded RAISE inside it
-- unwinds the entire tick transaction, silently, while cron still reports `succeeded`.
-- That is the leg_type root cause verbatim and it is not being repeated: the call sits in
-- its own BEGIN ... EXCEPTION WHEN OTHERS THEN RAISE WARNING block, so a bad service
-- code, a missing profile row or a lock timeout costs one ledger update and nothing else.
-- The atom is still marked done and the leg is still closed either way.
--
-- ── COST ────────────────────────────────────────────────────────────────────
-- One function call per completed atom. Run 909 completed 225 atoms in 180 sim-min --
-- about 1.25 per sim-minute. §2 is two UPDATEs against a 116-row and a ~207-row table,
-- both by primary key. Immaterial against the measured ~181 ms decide budget, and it
-- writes no ottoq_events.
-- ============================================================================
CREATE OR REPLACE FUNCTION twin.ottoq_sim_advance_visit_atoms(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_seed bigint; v_rec RECORD; v_new jsonb; v_a jsonb; v_b jsonb;
  v_changed boolean; v_total int := 0;
  v_triage_done boolean; v_conf numeric; v_roll numeric; v_verdict text;
  v_escalations jsonb; v_tick bigint; v_feed_sim boolean := true;
BEGIN
  SELECT depot_id, COALESCE(random_seed,42), tick_count INTO v_depot, v_seed, v_tick
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;
  SELECT COALESCE(d.feed_mode,'sim')='sim' INTO v_feed_sim FROM depots d WHERE d.id = v_depot;
  v_feed_sim := COALESCE(v_feed_sim, true);

  FOR v_rec IN
    SELECT vn.vehicle_id
      FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
     WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress')
       AND v.current_state IN ('charging_dcfc','charging_l2','charge_complete_holding',
                               'staged_awaiting_service','staged_for_departure','arrived_at_gate')
       -- M3_cabin_at_charger: cabin work (interior tidy) is performed BY A
       -- TECHNICIAN AT THE CHARGER during the session, so it may only start while the
       -- vehicle is plugged in. Previously it could start in any of six states —
       -- including at the gate and while staged for departure — which is why only 5.8%
       -- of interior cleans actually overlapped a charge. charge_complete_holding is
       -- kept ONLY as a catch-up: without it a vehicle whose charge finished before the
       -- tech arrived would never be cleaned and SLA.004 would block its deploy forever.
       AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                    WHERE COALESCE(a->>'status','pending') = 'pending'
                      AND a->>'svc' <> 'readiness_check'
                      AND ( (a->>'concurrency' = 'cabin'
                               AND v.current_state IN ('charging_dcfc','charging_l2',
                                                       'charge_complete_holding'))
                         OR (a->>'concurrency' IN ('exterior','digital')) ))
     ORDER BY (vn.urgency = 'immediate_dispatch') DESC,
              (v.current_state IN ('charging_dcfc','charging_l2')) DESC,
              v.last_state_change ASC
     LIMIT 30
  LOOP
    PERFORM ottoq_start_concurrent_atoms(v_rec.vehicle_id, p_clock);
  END LOOP;

  FOR v_rec IN
    SELECT vn.visit_id, vn.vehicle_id, vn.atoms, v.current_state
      FROM ottoq_visit_needs vn JOIN vehicles v ON v.id = vn.vehicle_id
     WHERE vn.depot_id = v_depot AND vn.status IN ('open','in_progress')
       AND (EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                    WHERE a->>'status' = 'in_progress' AND (a->>'ends_at')::timestamptz <= p_clock)
         OR (v.current_state = 'staged_for_departure'
             AND EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                          WHERE a->>'svc' = 'readiness_check' AND COALESCE(a->>'status','pending') = 'pending')))
  LOOP
    v_new := '[]'::jsonb; v_changed := false; v_triage_done := false; v_escalations := '[]'::jsonb;
    FOR v_a IN SELECT * FROM jsonb_array_elements(v_rec.atoms) LOOP
      IF v_feed_sim AND v_a->>'status' = 'in_progress' AND (v_a->>'ends_at')::timestamptz <= p_clock THEN
        v_a := v_a || jsonb_build_object('status','done','done_at', v_a->'ends_at');
        v_changed := true; v_total := v_total + 1;
        -- N2/M4c: close the matching flow-contract leg with real times
        PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, v_a->>'svc',
                (v_a->>'started_at')::timestamptz, (v_a->>'ends_at')::timestamptz);

        -- ══════════ 0005: CREDIT THE LEDGER THE DEPOT ACTUALLY READS ══════════
        -- This is the line whose absence meant 90 inspections, 26 cabin tidies, 5 sensor
        -- cleans and 5 item retrievals in run 909 moved nothing at all. Shared function,
        -- shared with the real-telemetry seam -- see §3 header. Fully qualified so
        -- search_path can never resolve it somewhere else. Own handler: a ledger failure
        -- must never unwind the atom close, the leg close, or the tick.
        BEGIN
          PERFORM public.ottoq_wear_mark_serviced(
                    v_rec.vehicle_id, p_sim_run_id, v_a->>'svc',
                    COALESCE((v_a->>'ends_at')::timestamptz, p_clock));
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'ottoq_sim_advance_visit_atoms: need-ledger credit FAILED SAFELY vehicle=% svc=% %: %',
            v_rec.vehicle_id, v_a->>'svc', SQLSTATE, SQLERRM;
        END;

        IF v_a->>'svc' = 'triage_check' THEN v_triage_done := true; END IF;
        IF COALESCE((v_a->>'requires_tech_greenlight')::boolean,false) THEN
          INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, visit_id, sim_run_id, depot_id,
                 payload, requested_at, decide_after, expires_at, priority)
          SELECT 'tech_greenlight', v_rec.vehicle_id, v_rec.visit_id, p_sim_run_id, v_depot,
                 jsonb_build_object('svc', v_a->>'svc', 'est_min', v_a->>'est_min'),
                 p_clock,
                 p_clock + ((15 + floor(ottoq_sim_seeded_random(v_seed, v_rec.vehicle_id::text || ':glDelay') * 45))::text || ' minutes')::interval,
                 p_clock + interval '120 minutes', 'high'
          WHERE NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals ap
                             WHERE ap.vehicle_id = v_rec.vehicle_id AND ap.approval_type = 'tech_greenlight'
                               AND (ap.status = 'pending' OR ap.decided_at > p_clock - interval '60 minutes'));
        END IF;
      ELSIF v_a->>'svc' = 'readiness_check' AND COALESCE(v_a->>'status','pending') = 'pending'
         AND v_rec.current_state = 'staged_for_departure' THEN
        -- 0005 NOTE: deliberately NOT credited. A readiness check confirms the vehicle is
        -- fit to leave; it restores nothing, and there is no column it may honestly move.
        v_a := v_a || jsonb_build_object('status','done','done_at', to_jsonb(p_clock));
        v_changed := true; v_total := v_total + 1;
        PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, 'inspect',
                p_clock - interval '3 minutes', p_clock);
      END IF;
      v_new := v_new || jsonb_build_array(v_a);
    END LOOP;

    IF v_triage_done AND v_feed_sim THEN
      v_b := v_new; v_new := '[]'::jsonb;
      FOR v_a IN SELECT * FROM jsonb_array_elements(v_b) LOOP
        IF COALESCE((v_a->>'confirm_required')::boolean,false)
           AND COALESCE(v_a->>'status','pending') = 'pending' THEN
          v_conf := COALESCE((v_a->>'confidence')::numeric, 0.6);
          v_roll := ottoq_sim_seeded_random(v_seed, v_rec.vehicle_id::text || ':' || (v_a->>'svc') || ':verdict');
          v_verdict := CASE WHEN v_roll < v_conf THEN 'confirm'
                            WHEN v_roll < v_conf + (1 - v_conf) * 0.7 THEN 'clear'
                            ELSE 'escalate' END;
          IF v_verdict = 'confirm' THEN
            v_a := v_a || jsonb_build_object('confirm_required', false, 'triage_verdict', 'confirm');
          ELSIF v_verdict = 'clear' THEN
            -- 0005 NOTE: deliberately NOT credited. Cleared by triage means the work was
            -- never performed, so no ledger column may move. Cancellation is not completion.
            v_a := v_a || jsonb_build_object('status','cancelled','confirm_required',false,
                     'triage_verdict','clear','cleared_by_triage',true);
            PERFORM ottoq_close_atom_leg(p_sim_run_id, v_rec.vehicle_id, v_a->>'svc', p_clock, p_clock);
          ELSE
            v_a := v_a || jsonb_build_object('confirm_required', false, 'triage_verdict', 'escalate');
            IF v_a->>'svc' = 'interior_tidy' THEN
              v_escalations := v_escalations || jsonb_build_array(jsonb_build_object(
                'svc','interior_deep_clean','must_do',false,'deferrable',true,'est_min',20,
                'concurrency','bay','requires_bay','detail','carryover_eligible',true,'from_escalation',true));
            ELSIF v_a->>'svc' = 'sensor_clean' THEN
              v_escalations := v_escalations || jsonb_build_array(jsonb_build_object(
                'svc','sensor_calibration','must_do',false,'deferrable',true,'est_min',30,
                'concurrency','bay','requires_bay','service_bay','carryover_eligible',true,'from_escalation',true));
            ELSIF v_a->>'svc' = 'cosmetic_repair' THEN
              v_a := v_a || jsonb_build_object('requires_tech_greenlight', true);
            END IF;
          END IF;
          INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,action_context,resolved_action_context,
                 entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
          VALUES (p_sim_run_id, v_tick, p_clock, v_depot, 'task_start', 'triage_verdict',
                 'vehicle', v_rec.vehicle_id,
                 jsonb_build_object('svc', v_a->>'svc', 'confidence', v_conf),
                 jsonb_build_object('verb','triage'),
                 jsonb_build_object('verb','triage_' || v_verdict, 'svc', v_a->>'svc'),
                 'enacted', 0, 0);
        END IF;
        v_new := v_new || jsonb_build_array(v_a);
      END LOOP;
      IF jsonb_array_length(v_escalations) > 0 THEN
        FOR v_a IN SELECT * FROM jsonb_array_elements(v_escalations) LOOP
          IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_new) e WHERE e->>'svc' = v_a->>'svc') THEN
            v_new := v_new || jsonb_build_array(v_a);
          END IF;
        END LOOP;
      END IF;
      v_changed := true;
    END IF;

    IF v_changed THEN UPDATE ottoq_visit_needs SET atoms = v_new WHERE visit_id = v_rec.visit_id; END IF;
  END LOOP;

  UPDATE ottoq_visit_needs vn SET status =
    CASE WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                       WHERE COALESCE((a->>'carryover_eligible')::boolean,false)
                         AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled'))
         THEN 'carried_over' ELSE 'complete' END
  FROM vehicles v
  WHERE v.id = vn.vehicle_id AND vn.depot_id = v_depot
    AND vn.status IN ('open','in_progress')
    AND v.current_state IN ('deployed','en_route_to_deployment');
  RETURN v_total;
END; $function$;


-- ============================================================================
-- §4  public.ottoq_run_boot_draw  — ANCHOR THE ODOMETER WATERMARK AT BOOT
--
--     THE KNOWN LIMITATION FROM 0004. FIXED HERE, AND HERE IS WHY.
--
-- ── THE DEFECT, PRECISELY ───────────────────────────────────────────────────
-- 0004 added a run-scoped watermark so the odometer advance is idempotent. It works. But
-- the watermark is first written by the FIRST COMPLETION, not at boot, and the "unknown
-- run" branch credits zero and merely anchors:
--       GREATEST(0, drive_km_total - drive_km_total) = 0
-- So a vehicle's first completion of a run credits nothing, and only a SECOND completion
-- credits real km. In 180 sim-min of run 909 no vehicle had two bay completions, and the
-- measured result is 0 of 116 odometers ever moving off their seeded integer. Idempotency
-- proven; advance unproven. Worse than unproven -- every kilometre driven between boot
-- and a vehicle's first completion is dropped on the floor permanently, because the
-- anchor is taken at first-completion time and silently swallows it.
--
-- ── WHY IT IS FIXED NOW AND NOT NEXT ────────────────────────────────────────
-- The founder has chosen MILEAGE-TRIGGERED EXTERIOR WASH -- folded into an arrival the
-- vehicle was already making, rather than "every third night", which synchronises the
-- fleet and manufactures a nightly peak. That design cannot be built, let alone measured,
-- on an odometer that never moves. Leaving it would mean the next migration ships a
-- mileage rule against a frozen counter and reads zeros, and the phase after that spends
-- its time finding out why. The fix is five lines in a function that runs once per run,
-- outside the tick, and it changes no draw and no starting value.
--
-- ── WHY IT BELONGS HERE AND NOT IN THE SEEDER ───────────────────────────────
-- ottoq_seed_vehicle_need_profiles is a 12,475-character boot draw whose every
-- multiplier governs the fleet's initial condition. 0004 kept it out of the blast radius
-- deliberately and this file keeps that discipline: editing an INSERT column list inside
-- it means re-emitting the whole draw, and a draw edit is a tuning change by definition.
-- ottoq_run_boot_draw is the 5,585-character wrapper that CALLS the seeder, and appending
-- a statement after that call is additive and legible. Same effect, a fifth of the risk.
--
-- ── WHY THIS IS THE CORRECT ANCHOR VALUE, NOT A CHOSEN ONE ──────────────────
-- The seeder writes, verbatim from the live body:
--       round((COALESCE(d.lifetime_mi * 1.60934, 20000 + 160000 * d.r_odo)
--              + COALESCE(d.drive_km_total, 0))::numeric, 0)  AS odo_km
-- i.e. odometer_km at boot ALREADY INCLUDES this run's mileage-to-date. So the amount
-- already credited is exactly drive_km_total as it stands at boot, and that is what the
-- watermark must equal. Setting it to anything else would either double-count that
-- mileage or discard it. The value is read from the table, never chosen.
--
-- ── SAFETY ──────────────────────────────────────────────────────────────────
-- Placed inside the seeder's EXISTING guarded block, after the seeder call, so it is
-- covered by the same "a profile failure must NEVER abort a run boot" handler that is
-- already there -- with its own RAISE WARNING so the two failures are distinguishable in
-- the log. Vehicles with no wear row are simply not updated (their watermark stays NULL,
-- which 0004 already treats correctly as "re-anchor, credit zero"). Idempotent: re-running
-- a boot draw rewrites the same value from the same source.
--
-- Everything else in this function is reproduced byte-for-byte.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_run_boot_draw(p_sim_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_run   ottoq_sim_runs%ROWTYPE;
  v_seed  bigint;
  v_n     int := 0;
  v_world jsonb := '{}'::jsonb;
  v_key   text;
  v_manifest jsonb;
  v_t0    timestamptz := clock_timestamp();
  v_profiles jsonb := jsonb_build_object('ok', false, 'skipped', true);
  v_anchored int := 0;   -- 0005: how many odometer watermarks were anchored at boot
BEGIN
  SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'run not found'); END IF;
  v_seed := COALESCE(v_run.random_seed, 42);

  -- ---- 1. PER-VEHICLE CONDITION DRAW (config = hot-loop truth; cards = provenance)
  WITH fleet AS (
    SELECT v.id
      FROM vehicles v
     WHERE v.home_depot_id = v_run.depot_id AND v.category = 'autonomous' AND v.is_active
  ), draws AS (
    SELECT id,
      round((88 + 12 * (1 - power(ottoq_sim_seeded_random(v_seed, 'veh_soh:'    || id::text), 2)))::numeric, 1) AS soh,
      round((0.88 + 0.30 * ottoq_sim_seeded_random(v_seed, 'veh_cons:'          || id::text))::numeric, 3)      AS cons,
      round((0.85 + 0.25 * ottoq_sim_seeded_random(v_seed, 'veh_curve:'         || id::text))::numeric, 3)      AS curve,
      round((0.5 + 1.5 * power(ottoq_sim_seeded_random(v_seed, 'veh_soil:'      || id::text), 2))::numeric, 3)  AS soil,
      round((6500 + 3000 * ottoq_sim_seeded_random(v_seed, 'veh_pm:'            || id::text))::numeric, 0)      AS pm_km,
      round((180 + 140 * ottoq_sim_seeded_random(v_seed, 'veh_calib:'           || id::text))::numeric, 0)      AS calib_h,
      round((0.80 + 0.45 * ottoq_sim_seeded_random(v_seed, 'veh_svcspd:'        || id::text))::numeric, 3)      AS svcspd,
      (2 + floor(3 * ottoq_sim_seeded_random(v_seed, 'veh_washcad:'             || id::text)))::int             AS washcad,
      ottoq_sim_seeded_random(v_seed, 'veh_washphase:' || id::text)                                             AS washphase
    FROM fleet
  ), cfg AS (
    UPDATE vehicles v SET config = COALESCE(v.config, '{}'::jsonb) || jsonb_build_object(
        'battery_soh_pct',      d.soh,
        'consumption_scalar',   d.cons,
        'charge_curve_scalar',  d.curve,
        'soil_rate',            d.soil,
        'pm_interval_km',       d.pm_km,
        'calib_interval_h',     d.calib_h,
        'service_speed_scalar', d.svcspd,
        'wash_cadence_cycles',  d.washcad,
        'cycles_since_wash',    floor(d.washcad * d.washphase)::int,
        'condition_drawn_run',  p_sim_run_id::text)
      FROM draws d WHERE v.id = d.id
      RETURNING v.id, d.soh, d.cons, d.curve, d.soil, d.pm_km, d.calib_h, d.svcspd, d.washcad
  ), cards AS (
    INSERT INTO ottoq_variability_cards
      (sim_run_id, var_key, scope_instance, lifespan, bucket_key, value, drawn_at_clock, drawn_at_tick)
    SELECT p_sim_run_id, x.k, c.id::text, 'run', 'run', x.val, v_run.sim_clock_start, 0
      FROM cfg c CROSS JOIN LATERAL (VALUES
        ('veh_battery_soh_pct',      c.soh),
        ('veh_consumption_scalar',   c.cons),
        ('veh_charge_curve_scalar',  c.curve),
        ('veh_soil_rate',            c.soil),
        ('veh_pm_interval_km',       c.pm_km),
        ('veh_calib_interval_h',     c.calib_h),
        ('veh_service_speed_scalar', c.svcspd),
        ('veh_wash_cadence_cycles',  c.washcad::numeric)) AS x(k, val)
    ON CONFLICT (sim_run_id, var_key, scope_instance, bucket_key) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM cfg;

  -- ---- 1b. RICH PER-VEHICLE NEED PROFILE (energy / cleanliness / sensor+software /
  --          mechanical / operational commitment / items). Runs AFTER the condition draw
  --          so it inherits soh / soil_rate / pm_interval_km / calib_interval_h.
  --          Wrapped: a profile failure must NEVER abort a run boot.
  BEGIN
    v_profiles := ottoq_seed_vehicle_need_profiles(p_sim_run_id);
  EXCEPTION WHEN OTHERS THEN
    v_profiles := jsonb_build_object('ok', false, 'error', SQLERRM);
    RAISE WARNING 'boot_draw: need-profile seeding failed: %', SQLERRM;
  END;

  -- ---- 1c. 0005: ANCHOR THE ODOMETER WATERMARK AT BOOT.
  --          The seeder has just written odometer_km = lifetime_base + drive_km_total, so
  --          drive_km_total as it stands RIGHT NOW is exactly the mileage already credited.
  --          Recording it here is what lets a vehicle's FIRST completion of the run credit
  --          real kilometres instead of anchoring silently and crediting zero. Read from
  --          the table, never chosen. Own handler: this must never abort a boot either.
  BEGIN
    UPDATE public.vehicle_need_profile p
       SET wear_km_applied     = COALESCE(w.drive_km_total, 0),
           wear_km_applied_run = p_sim_run_id
      FROM public.ottoq_vehicle_wear w
     WHERE w.vehicle_id = p.vehicle_id
       AND w.sim_run_id = p_sim_run_id;
    GET DIAGNOSTICS v_anchored = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    v_anchored := -1;
    RAISE WARNING 'boot_draw: odometer watermark anchoring failed SAFELY: % %', SQLSTATE, SQLERRM;
  END;

  -- ---- 2. WORLD DAY-0 DRAW (every run/day/block world card dealt before tick 1)
  FOR v_key IN
    SELECT var_key FROM ottoq_variability_catalog
     WHERE lifespan IN ('run','day','block') AND COALESCE(scope,'') <> 'vehicle'
  LOOP
    BEGIN
      v_world := v_world || jsonb_build_object(v_key,
        ottoq_twin_deal(p_sim_run_id, v_key, 'global', v_run.sim_clock_start,
                        (v_run.sim_clock_start::date - DATE '2020-01-01'), 0, 'global'));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;

  -- ---- 3. THE BOOT MANIFEST (loading-screen + Black Box content)
  SELECT jsonb_build_object(
    'ok', true, 'drawn_at', now(), 'seed', v_seed, 'vehicles_drawn', v_n,
    'draw_ms', round(EXTRACT(epoch FROM (clock_timestamp() - v_t0)) * 1000),
    'need_profiles', v_profiles,
    'odometer_watermarks_anchored', v_anchored,
    'world_day0', v_world,
    'fleet_condition', (
      SELECT jsonb_object_agg(k, jsonb_build_object('min', mn, 'avg', av, 'max', mx))
      FROM (
        SELECT var_key AS k, round(min(value),2) AS mn, round(avg(value),2) AS av, round(max(value),2) AS mx
          FROM ottoq_variability_cards
         WHERE sim_run_id = p_sim_run_id AND var_key LIKE 'veh\_%' ESCAPE '\'
         GROUP BY var_key) s))
  INTO v_manifest;

  UPDATE ottoq_sim_runs
     SET payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object('boot_draw', v_manifest)
   WHERE sim_run_id = p_sim_run_id;

  RETURN v_manifest;
END;
$function$;


-- ============================================================================
-- §5  POST-SNAPSHOT
-- ============================================================================
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0005_inspection_and_condition_resets_post', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname = 'public' AND p.proname IN ('ottoq_wear_mark_serviced',
                                               'ottoq_run_boot_draw'))
    OR (n.nspname = 'twin'   AND p.proname  = 'ottoq_sim_advance_visit_atoms');


-- ============================================================================
-- §6  VERIFICATION
--
-- V1 is static and can be run the moment this lands. V2-V4 are static-but-idempotency
-- proofs, run in a transaction and ROLLED BACK. V5-V8 are RUNTIME proof and need a
-- bounded run of >= 139 sim-min, in the SIM domain (booked_at_sim), captured AFTER the
-- run is stopped, gated on arrivals, primary metric PER ARRIVING VEHICLE.
--
-- ⚠️ Starting a run purges the prior one. Preserve run 909's numbers into a
--    NON-`ottoq`-prefixed table BEFORE the next run starts, as 0002/0003/0004 record.
-- ⚠️ NEVER disable cron job 12 -- it IS the START engine.
--
-- V1 -- the wiring exists and points where this file says it does. Expect 4 rows:
--       ottoq_ingest_service_complete, ottoq_sim_advance_service_flow,
--       ottoq_sim_advance_visit_atoms  (NEW), ottoq_wear_mark_serviced (itself).
--       Before this migration there were 3. That one extra row is scope (a).
--   SELECT n.nspname||'.'||p.proname AS fn
--     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind = 'f'
--      AND pg_get_functiondef(p.oid) LIKE '%ottoq_wear_mark_serviced%'
--    ORDER BY 1;
--
-- V2 -- the condition columns actually move, and only for the right service. Run in a
--       transaction and ROLL BACK; touches no committed state.
--   BEGIN;
--     SELECT vehicle_id, exterior_soil_level, cabin_condition, item_retrieval_pending,
--            worst_fault_severity, software_version, sw_target_version
--       FROM public.vehicle_need_profile
--      WHERE vehicle_id = '99ddf4ff-96d7-4257-b1ce-cb9437335ce8';
--     -- BASELINE TODAY: soil 0.595, cabin 'soiled', wear.soil_index = 0
--     SELECT public.ottoq_wear_mark_serviced(
--              '99ddf4ff-96d7-4257-b1ce-cb9437335ce8'::uuid,
--              'b049db50-6407-4b63-9666-a66c5922c067'::uuid,
--              'interior_deep_clean', now());
--     SELECT vehicle_id, exterior_soil_level, cabin_condition FROM public.vehicle_need_profile
--      WHERE vehicle_id = '99ddf4ff-96d7-4257-b1ce-cb9437335ce8';
--     -- EXPECT: exterior_soil_level 0.595 -> 0.000 (copied from soil_index),
--     --         cabin_condition 'soiled' -> 'clean', and cabin_urgency for that vehicle
--     --         drops from 'overdue' to 'ok' in ottoq_vehicle_needs_card.
--   ROLLBACK;
--
-- V3 -- idempotency, proven not asserted. Call three times with an unchanged wear counter
--       and confirm nothing accumulates. Roll back.
--   BEGIN;
--     SELECT odometer_km AS before_km, wear_km_applied, cabin_condition
--       FROM public.vehicle_need_profile ORDER BY vehicle_id LIMIT 1;
--     SELECT public.ottoq_wear_mark_serviced(
--              (SELECT vehicle_id FROM public.vehicle_need_profile ORDER BY vehicle_id LIMIT 1),
--              (SELECT sim_run_id FROM public.ottoq_sim_runs ORDER BY started_at DESC LIMIT 1),
--              'interior_tidy', now()) FROM generate_series(1,3);
--     SELECT odometer_km AS after_km, wear_km_applied, cabin_condition
--       FROM public.vehicle_need_profile ORDER BY vehicle_id LIMIT 1;
--   ROLLBACK;
--   EXPECT: after_km - before_km credited AT MOST ONCE and identical for 1 vs 3 calls;
--   cabin_condition either unchanged or 'light_litter'->'clean' exactly once.
--
-- V4 -- TOTALITY. An unmapped service code must be a no-op, never an error. This is the
--       leg_type regression test. Roll back.
--   BEGIN;
--     SELECT public.ottoq_wear_mark_serviced(
--              (SELECT vehicle_id FROM public.vehicle_need_profile ORDER BY vehicle_id LIMIT 1),
--              (SELECT sim_run_id FROM public.ottoq_sim_runs ORDER BY started_at DESC LIMIT 1),
--              'perimeter_walkaround', now());
--     SELECT public.ottoq_wear_mark_serviced(
--              (SELECT vehicle_id FROM public.vehicle_need_profile ORDER BY vehicle_id LIMIT 1),
--              (SELECT sim_run_id FROM public.ottoq_sim_runs ORDER BY started_at DESC LIMIT 1),
--              'a_service_that_does_not_exist', now());
--   ROLLBACK;
--   EXPECT: both return without error and without a WARNING from the PART 2 handler.
--
-- V5 -- THE HEADLINE FOR SCOPE (a). Inspections and cabin work now credit the ledger.
--       Capture AFTER the run is stopped. Before this migration the only profiles that
--       moved were the 14 bay completions of 0004.
--   SELECT count(*) FILTER (WHERE updated_at > drawn_at) AS profiles_moved_after_boot,
--          count(*) AS n,
--          count(DISTINCT date_trunc('second', updated_at)) AS distinct_update_moments
--     FROM public.vehicle_need_profile;
--   AND cross-check the driver -- done atoms by svc for the run, which is the population
--   that should now be crediting:
--   SELECT a->>'svc' AS svc, count(*) AS done_atoms
--     FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
--    WHERE vn.sim_run_id = '<new run>' AND a->>'status' = 'done'
--    GROUP BY 1 ORDER BY 2 DESC;
--   RUN 909 BASELINE: 14 profiles moved; done atoms interior_inspection 90,
--   readiness_check 69, interior_tidy 26, triage_check 24, item_retrieval 5,
--   sensor_clean 5, remote_diagnostics 5, mechanical_pm 1  (n = 225).
--
-- V6 -- THE HEADLINE FOR SCOPE (b). The two ledgers agree instead of diverging.
--   SELECT count(*) AS n,
--          count(*) FILTER (WHERE p.exterior_soil_level IS DISTINCT FROM round(w.soil_index,3))
--            AS soil_diverged,
--          round(avg(p.exterior_soil_level),3) AS avg_profile_soil,
--          round(avg(w.soil_index),3)          AS avg_wear_soil,
--          count(*) FILTER (WHERE w.cabin_litter_events = 0 AND p.cabin_condition <> 'clean')
--            AS litter_zero_but_dirty_label
--     FROM public.vehicle_need_profile p
--     JOIN public.ottoq_vehicle_wear w
--       ON w.vehicle_id = p.vehicle_id AND w.sim_run_id = '<new run>';
--   RUN 909 BASELINE: n 116, soil_diverged 116 (100%), avg_profile_soil 0.462,
--   avg_wear_soil 0.217, litter_zero_but_dirty_label 50.
--   EXPECT soil_diverged to fall sharply -- but ONLY for vehicles that completed some
--   work; a vehicle that never arrived is never touched, and that is correct.
--   litter_zero_but_dirty_label will NOT go to 0. See GAP 3; predicted in advance.
--
-- V7 -- CONVERGENCE. Report against the NEW run's OWN post-boot baseline, not 909's.
--       Capture the boot baseline immediately after boot and the end state after stop.
--   SELECT overall_urgency, count(*) FROM public.ottoq_vehicle_needs_card
--    GROUP BY 1 ORDER BY 2 DESC;
--   RUN 909: boot 75.9% overdue-or-critical -> end 82.8%
--            (critical 56, overdue 40, due 17, due_soon 3, ok 0.  n = 116).
--   ⚠️ Do NOT compare against run 908's 84.5%: different sim_clock_start, different draw.
--   Also report PER ARRIVING VEHICLE, which is the primary metric: of the vehicles that
--   arrived during the window, what fraction ended better-graded than they arrived.
--
-- V8 -- THE ODOMETER FINALLY MOVES (§4). Before this migration: 0 of 116, always.
--   SELECT count(*) FILTER (WHERE wear_km_applied_run IS NOT NULL) AS anchored_at_boot,
--          count(*) FILTER (WHERE odometer_km <> round(odometer_km))  AS moved_off_seed,
--          round(max(odometer_km - km_at_last_pm), 1)                 AS worst_km_since_pm,
--          count(*) AS n
--     FROM public.vehicle_need_profile;
--   The boot manifest also reports it directly now:
--   SELECT payload->'boot_draw'->>'odometer_watermarks_anchored' FROM public.ottoq_sim_runs
--    WHERE sim_run_id = '<new run>';
--   EXPECT anchored_at_boot = 116 at boot, and moved_off_seed > 0 after the run --
--   the seeder writes odometer_km as round(...,0), so any vehicle that has been credited
--   real kilometres carries a fractional part. Crude, and it is a proof.
--
-- V9 -- THE PROTECTED BASELINE DID NOT REGRESS. Re-measure, never assume:
--       charging cut-short recovery 93.3% | approvals 0 pending | 0 real double-bookings |
--       no starvation | phantoms 0 | reverse coverage 100% | emission invariant 1.000 |
--       work per arrival | assignments per arrival ex-inspect | inspection-zone parking 0% |
--       check-drift.sql CLEAN.
--       Nothing in this file books, releases or prices a space, so the expectation is no
--       movement. Measure it anyway. Method: union-of-intervals CLIPPED to the window,
--       stalls scoped by depot_id, captured only after the run is stopped.
--
-- ============================================================================
-- THE FALSIFIABLE PREDICTION -- WHAT WOULD MEAN THIS FILE IS WRONG
--
-- Recorded before the run so the next result means something.
--
--   * IF V5 shows profiles_moved_after_boot jumping well past 0004's 14 AND V7 shows
--     overdue-or-critical FALLING against the new run's own boot baseline -- the wiring
--     was the binding constraint and this phase is done.
--
--   * IF V5 jumps but V7 stays flat -- the ledger is being written and the fleet still is
--     not draining, and the cause is NOT the wiring. The most likely cause is already
--     visible in the run 909 numbers: 190 inspect completions against 27 real bay
--     completions, i.e. the depot is spending its capacity on 4-minute inspections while
--     2 service bays and 3 wash bays serve ~96 overdue vehicles. That is a THROUGHPUT and
--     must_do-selection problem, it is a different migration, and this file should not be
--     credited or blamed for it. I have deliberately NOT manufactured convergence by
--     crediting inspections with service they did not perform -- see CORRECTION A -- so
--     if this outcome appears, it is the honest one.
--
--   * IF V7 IMPROVES A LOT AND V5 BARELY MOVES -- suspect §2's condition copy is doing
--     all the work and read it as a WARNING, not a win: it would mean the fleet was never
--     as dirty as the card claimed, and the intervals need re-examining (a tuning phase),
--     not that service throughput improved.
--
-- ============================================================================
-- GAPS FOUND WHILE VERIFYING — RECORDED, DELIBERATELY NOT FIXED HERE
--
-- GAP 1 — `sensor_clean` ZEROES THE BODY-SOIL INDEX, WHICH IS PROBABLY WRONG.
--   PART 1 has always contained
--       soil_index = CASE WHEN p_service IN ('exterior_wash','sensor_clean','interior_deep_clean') THEN 0 ...
--   Washing a sensor is not washing the vehicle. §2 inherits this rather than contradict
--   it, because one debatable rule beats two ledgers with different opinions. Now that
--   the profile projects soil_index, this rule is visible on the card for the first time,
--   so it will be measurable. Fixing it means editing PART 1, which is certified
--   behaviour, and it changes what "dirty" means -- a tuning decision, not wiring.
--
-- GAP 2 — SENSOR HEALTH, TIRES AND BRAKES STILL HAVE NO RESET, ON PURPOSE.
--   calib_urgency also grades on sensor_health_pct (< 89 / < 91), tire_urgency on
--   tire_tread_mm, brake_urgency on brake_wear_pct. A completed sensor_calibration
--   plausibly restores sensor health -- but to WHAT number? There is no sensor-health
--   column anywhere in ottoq_vehicle_wear to copy from, so any value would be one I chose,
--   i.e. tuning, which this file may not do. Tires and brakes are worse: no service in the
--   emitted vocabulary restores them at all (there is no tire_rotation and no brake
--   service in service_cadence_policy), and mechanical_pm is not a licence to invent one.
--   These need either a wear-table column to project from or a founder decision on the
--   restore value. Named, not guessed.
--
-- GAP 3 — cabin_condition CANNOT BE OBSERVED, ONLY REMEDIATED.
--   50 of 116 vehicles read cabin_litter_events = 0 (truthfully clean) with a dirty
--   cabin_condition label. §2 clears the label on a deep clean or a qualifying tidy, but
--   nothing OBSERVES a cabin back to 'clean', because the seeder derives the label from an
--   independent random rather than from litter, and inventing a litter -> label banding
--   would be choosing thresholds. Two honest fixes exist and both are tuning: derive the
--   label from cabin_litter_events with agreed bands, or let the inspection carry an
--   observation payload on both seams. Expect V6's litter_zero_but_dirty_label to fall
--   only by the number of cabins actually cleaned.
--
-- GAP 4 — THE SEEDER'S GREATEST(0, ...) PM CLAMP IS STILL THERE (0004 GAP 3, unchanged).
--   §5 of 0004 repaired the 26 rows it had already produced; the next boot produces a
--   fresh batch. Belongs with the interval retune, because both edit the same draw.
--
-- GAP 5 — THE WHOLE-BAY-ARRAY OVER-MARKING IS STILL THERE (0004 GAP 4, now wider).
--   twin.ottoq_sim_advance_service_flow marks the entire bay array serviced on exit, so a
--   vehicle leaving the wash bay is recorded as having had both exterior_wash AND
--   sensor_clean. §3 does NOT share this defect -- it credits the atom's own svc, one at a
--   time, which is exactly what was performed. But the bay path still over-marks, and it
--   now propagates into more profile columns than before. Worth its own pass.
--
-- GAP 6 — 190 INSPECT COMPLETIONS AGAINST 27 BAY COMPLETIONS.
--   Not a bug in anything this file touches, and the single biggest number in the run.
--   The depot completes seven times more 4-minute inspections than actual service. If the
--   fleet does not converge after this migration, start here, not in the ledger.
-- ============================================================================
