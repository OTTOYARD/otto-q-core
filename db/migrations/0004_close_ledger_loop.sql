-- migration-version: PENDING
-- migration-name:    close_ledger_loop

-- ============================================================================
-- 0004_close_ledger_loop.sql
--
-- THE SHORT VERSION, IN PLAIN LANGUAGE
--
-- Every "is this vehicle due for anything?" question in OTTO-Q is answered from one
-- table: public.vehicle_need_profile. It holds when each vehicle was last washed, last
-- deep-cleaned, last calibrated, last given a PM, and at what mileage.
--
-- That table is written ONCE, at run boot, from a seeded random draw keyed off the
-- vehicle's UUID -- and then never touched again. Not by the sim, not by real
-- telemetry, not by anything. So "last washed at" never moves forward. The clock keeps
-- running and the last-done date does not, which means due dates only ever travel in
-- one direction: further into the past.
--
-- The result is that overdue is not an event, it is the resting state. 98 of 116
-- vehicles (84.5%) currently grade overdue-or-critical and not one grades ok. The
-- founder's doctrine -- "overdue is a failure state, not a trigger" -- is exactly
-- inverted at the data layer.
--
-- The fix is cheap because the correct code already exists and has always worked. On
-- every service completion, public.ottoq_wear_mark_serviced already writes the right
-- reset -- but into public.ottoq_vehicle_wear, a DIFFERENT table that the needs card
-- never joins. Two ledgers. The truthful one is unread; the read one is a hash of a
-- UUID. This migration makes the completion write BOTH, so the card reads a ledger
-- that service history actually moves.
--
-- ============================================================================
-- SYMPTOM  (measured live, 2026-08-04, this database)
--   public.vehicle_need_profile: 116 rows, 0 with updated_at > drawn_at, all 116 with
--   updated_at = drawn_at to the microsecond, exactly 1 distinct drawn_at across the
--   whole fleet. One writer only. Zero UPDATE statements against it anywhere in
--   public / ottoq / twin. Zero triggers.
--   public.ottoq_vehicle_needs_card: 65 critical, 33 overdue, 17 due, 1 due_soon,
--   0 ok.  n = 116.
--
-- DIAGNOSIS AS HANDED TO ME -- WHAT I CONFIRMED AND WHAT I DID NOT
--   Verified before writing a line of this file. Two parts of the brief were wrong and
--   are corrected below rather than implemented. A wrong premise poisons everything
--   downstream, so both are recorded here in full.
--
--   CONFIRMED (1) -- the ledger never moves.
--     SELECT count(*) FILTER (WHERE updated_at > drawn_at) FROM vehicle_need_profile
--       -> 0 of 116.
--
--   CONFIRMED (2) -- exactly one writer, and it is boot-only.
--     Scanning pg_get_functiondef over every function in public, ottoq and twin for
--     the string 'vehicle_need_profile' returns exactly two functions:
--       public.ottoq_seed_vehicle_need_profiles  -- INSERT ... ON CONFLICT DO UPDATE
--       public.ottoq_run_boot_draw               -- calls the seeder, writes nothing
--     No function anywhere contains an UPDATE against the table. Confirmed as stated.
--
--   CONFIRMED (3) -- ottoq_wear_mark_serviced writes the correct reset to the OTHER
--     table. Quoting the live body verbatim:
--         UPDATE ottoq_vehicle_wear w SET
--           soil_index = CASE WHEN p_service IN ('exterior_wash','sensor_clean',
--                             'interior_deep_clean') THEN 0 ELSE w.soil_index END,
--           km_at_last_pm = CASE WHEN p_service = 'mechanical_pm'
--                             THEN w.drive_km_total ELSE w.km_at_last_pm END,
--           calibrated_at = CASE WHEN p_service = 'sensor_calibration'
--                             THEN p_clock ELSE w.calibrated_at END,
--           ...
--         WHERE w.vehicle_id = p_vehicle_id AND w.sim_run_id = p_sim_run_id;
--     Every branch is right. It has simply never been connected to the table the
--     decisions are read from.
--
--   CONFIRMED (4) -- the needs card reads the seeded ledger, not the truthful one.
--     pg_get_viewdef('public.ottoq_vehicle_needs_card') matches 'vehicle_need_profile'
--     and does NOT match 'ottoq_vehicle_wear' anywhere in its 24,588 characters. The
--     six last-done fields it reads are last_wash_at, last_deep_clean_at,
--     last_calibration_at, last_pm_at, km_at_last_pm and odometer_km -- all from the
--     profile. This is the whole defect in one line of evidence.
--
--   CONFIRMED (5) -- both seams really do funnel through one function, so one change
--     covers sim AND production. The only two callers of ottoq_wear_mark_serviced are:
--       twin.ottoq_sim_advance_service_flow   (line 120) -- the SIM path
--       public.ottoq_ingest_service_complete  (line  35) -- the REAL-TELEMETRY seam
--     This is why the fix belongs in the shared function and nowhere else.
--     ...with one caveat that the brief did not mention -- see CORRECTION B.
--
--   ─────────────────────────────────────────────────────────────────────────
--   CORRECTION A -- SCOPE ITEM (c) IS FALSIFIED. THE NEGATIVE km_at_last_pm IS NOT A
--   DEFECT, IT IS LEAD-IN PHASE, AND "FIXING" IT WOULD BREAK THE FLEET ON PURPOSE.
--
--     The brief asks me to fix a negative km_at_last_pm, sampled at -38.4, -35.7,
--     -33.9. Those values are real, but they are NOT in vehicle_need_profile:
--         SELECT min(km_at_last_pm) FROM vehicle_need_profile      ->  0
--         SELECT count(*) ... WHERE km_at_last_pm < 0              ->  0 of 116
--     They are in public.ottoq_vehicle_wear:
--         min -89.892, 111 of 207 rows negative.
--     And they are written deliberately, by
--     public.ottoq_scenario_apply_fleet_overrides, under this comment, which is in the
--     live function body today:
--         -- (3) WEAR PHASE OFFSETS -- this is what turns a THUNDERING HERD into a
--         --     SUSTAINED stream. Without it every vehicle starts its PM /
--         --     calibration / soil clock at zero, so with a short interval the whole
--         --     fleet comes due in the same handful of ticks ... and the depot is
--         --     empty afterwards.
--         -- negative "km at last PM" == "already this far into the PM cycle at t0"
--     Every consumer reads it as a phase, never as an absolute:
--         ottoq_evaluate_return_need        drive_km_total - COALESCE(km_at_last_pm,0)
--         twin.ottoq_sim_generate_service_manifest   same expression
--         ottoq_twin_wear_window                     same expression
--     and the subtraction of a negative yields a correct, positive km-since-PM. Live
--     check: 0 of 207 rows have km_at_last_pm > drive_km_total, i.e. km-since-PM is
--     never negative anywhere in the table.
--     Clamping these to zero would set every vehicle's PM phase to 0 simultaneously
--     and re-create the exact synchronised fleet the offsets exist to prevent -- the
--     same failure mode the founder just called out for exterior wash ("not every
--     third night, which synchronises the fleet and manufactures a nightly peak").
--     SO IT IS NOT TOUCHED. Nothing in this migration writes ottoq_vehicle_wear.
--
--     THERE IS A REAL DEFECT NEARBY, and it IS fixed here -- §5. The seeder computes
--         km_at_last_pm := GREATEST(0, odo_km - km_since_pm)
--     and that GREATEST(0, ...) clamp fires for 26 of 116 vehicles. A clamped row
--     claims its last PM happened at odometer zero, so the card computes km-since-PM
--     as the entire lifetime odometer -- up to 169,957 km against a mean PM interval
--     of 7,816 km, a pm_ratio of 21x. The clamp does not prevent the bad number, it
--     launders it into a plausible-looking one. Same family as the brief's item (c),
--     opposite table, and the version that is actually wrong.
--
--   CORRECTION B -- THE REAL-TELEMETRY SEAM IS GATED ON A SIM RUN EXISTING, SO
--   "BOTH PATHS ARE COVERED" IS TRUE TODAY ONLY WHILE A SIM IS RUNNING.
--
--     public.ottoq_ingest_service_complete -- the production entry point a depot tech
--     or an OEM integration calls -- reaches the reset through this guard:
--         IF v_run.sim_run_id IS NOT NULL AND v_before - v_after > 0 THEN
--           FOREACH v_s IN ARRAY p_services LOOP
--             BEGIN PERFORM ottoq_wear_mark_serviced(...);
--             EXCEPTION WHEN OTHERS THEN NULL; END;
--     v_run is selected as the depot's run WHERE status = 'running'. In real
--     production there is no such row, so v_run.sim_run_id is NULL and the reset is
--     skipped entirely. Extending ottoq_wear_mark_serviced alone would therefore have
--     produced a SIM-ONLY fix -- precisely what the real-data ingestion seam rule
--     forbids. §4 removes that gate. The EXCEPTION ... THEN NULL is also replaced with
--     a named warning: a silent swallow on the production seam is how a depot ends up
--     believing a reset happened that did not.
--
-- CAUSE, IN ONE SENTENCE
--   Two ledgers were built for the same fact. Service completion updates the one
--   nobody reads.
--
-- FIX  (this file, in order)
--   §1  snapshots + md5 guards for the two functions being replaced.
--   §2  two bookkeeping columns on vehicle_need_profile -- the odometer watermark that
--       makes scope (b) idempotent. Additive, nullable, no rewrite.
--   §3  public.ottoq_wear_mark_serviced -- the whole point. Existing wear UPDATE kept
--       byte-for-byte; a second, independent UPDATE against vehicle_need_profile added
--       after it. Scope (a) + (b).
--   §4  public.ottoq_ingest_service_complete -- ungate the production seam
--       (CORRECTION B). One predicate and one exception handler. Nothing else.
--   §5  the GREATEST(0,...) clamp repair for the 26 laundered rows (CORRECTION A,
--       second half). Scope (c), as it actually exists.
--   §6  post-snapshots.  §7 verification queries.
--
-- WHAT THIS FILE DELIBERATELY DOES NOT DO
--   * It does NOT enable ottoq_apply_need_escalation. That function has 0 callers and
--     defaults to dry-run. Switching it on against a fleet that is 84.5% overdue would
--     make ~98 vehicles' bay work mandatory at once against 2 service bays and 3 wash
--     bays -- turning a silent failure into a throughput collapse. It is a later phase,
--     gated behind this one. One variable at a time.
--   * It does NOT retune a single must_do_at value, interval, threshold or multiplier.
--     Wiring and tuning must never share a migration or you cannot tell which caused
--     what. Every number this file writes is a copy of an observed quantity
--     (p_clock, drive_km_total, odometer_km) -- never a chosen one.
--   * It does NOT write ottoq_vehicle_wear. See CORRECTION A.
--   * It does NOT touch the LP formulation, CSR build, cuOpt parse path, Gate B,
--     verify_jwt, ottoq_events, or public.ottoq_decide_tick.
--   * It does NOT move interior deep-clean out of the bay system, and it does NOT make
--     exterior wash mileage-triggered. Both are founder decisions of 2026-08-04 and
--     both are behaviour changes; this file only makes the ledger they will read
--     truthful first.
--
-- BLAST RADIUS
--   Two functions replaced. ottoq_wear_mark_serviced has exactly 2 callers, both
--   listed above, both PERFORM (the boolean return is discarded by both) -- and the
--   return value is preserved anyway, see the note in §3. ottoq_ingest_service_complete
--   has no in-database callers; it is an entry point. vehicle_need_profile gains 2
--   nullable columns and no existing reader selects by ordinal position (the needs
--   card names all 41 columns explicitly), so the view is unaffected and is not
--   rebuilt.
--   The protected phase-11/14 baseline is untouched by construction: nothing here runs
--   inside decide_tick, nothing here books, releases or picks a space, and nothing here
--   changes any urgency threshold.
--
-- VERIFY
--   §7, plus a bounded run of >= 139 sim-min captured AFTER the run is stopped.
--   Primary metric is per ARRIVING VEHICLE. See MIGRATION_LOG.md.
--
-- METHOD NOTE ON THE md5 GUARDS
--   Unlike 0002, the expected hashes below were computed LIVE from this database at
--   authoring time (2026-08-04), not from db/baseline/*.sql, because §4's target
--   ottoq_ingest_service_complete is being read and re-based here directly. They are
--   compared against
--       md5(rtrim(pg_get_functiondef(oid), E' \n\r\t'))
--   so a trailing-newline difference cannot produce a false abort. If either live body
--   has drifted since, this migration REFUSES TO APPLY. That is intended: re-read the
--   live body, re-base, re-run. Nothing is dropped and nothing is changed on abort.
-- ============================================================================


-- ============================================================================
-- §1  SNAPSHOT, THEN GUARD  (house rule 1)
--
-- Recover either of these later with:
--   SELECT definition FROM public.ottoq_schema_snapshots
--    WHERE label = '0004_close_ledger_loop_pre' AND object_name = '<fn>';
-- ============================================================================
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0004_close_ledger_loop_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_wear_mark_serviced',
                     'ottoq_ingest_service_complete');

DO $guard$
DECLARE
  v_expect CONSTANT jsonb := jsonb_build_object(
    'public.ottoq_wear_mark_serviced',      '6a34100cdd88bc67f60982b7aebaffd9',
    'public.ottoq_ingest_service_complete', '5b11e1b31ba7f910559cd635afba585b');
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
  RAISE NOTICE 'GUARD: both target functions match their expected definitions.';
END
$guard$;


-- ============================================================================
-- §2  THE ODOMETER WATERMARK  (the mechanism scope (b) needs to be idempotent)
--
-- WHY A COLUMN AND NOT AN ARITHMETIC TRICK.
--   Scope (b) asks that odometer_km advance from ottoq_vehicle_wear.drive_km_total as
--   wear accrues. The naive form is
--       odometer_km := odometer_km + drive_km_total
--   and it is wrong twice over. drive_km_total is a RUNNING TOTAL, not a delta, so that
--   line adds the whole run's mileage again on every single call. And the caller can
--   and does call more than once for the same completion: ottoq_ingest_service_complete
--   loops FOREACH over p_services, and a real OEM integration may re-report a
--   completion it already reported. Under an additive update a re-report silently
--   inflates the odometer, which inflates km-since-PM, which brings PM due early
--   forever. An idempotent update needs to know how much of drive_km_total it has
--   already credited. That is a fact about the profile row, so it lives on the profile
--   row.
--
-- WHY IT IS ALSO RUN-SCOPED.
--   vehicle_need_profile is keyed on vehicle_id alone -- one row per vehicle, rewritten
--   in place at every run boot (ON CONFLICT (vehicle_id) DO UPDATE). drive_km_total, by
--   contrast, is keyed (vehicle_id, sim_run_id) and RESTARTS AT ZERO each run. So a
--   watermark carried over from a previous run would sit above the new run's counter
--   and suppress every advance until the new run happened to exceed it. Storing which
--   run the watermark belongs to makes a run change re-anchor instead of suppress. This
--   is the same composite-fence lesson twin.ottoq_sim_advance_wear_counters already
--   learned the hard way and documents in its own R3 comment ("p_tick_seq is a PER-RUN
--   counter restarting at 1, so the second soak run matched tick-for-tick and updated
--   ZERO rows silently").
--
-- WHY THIS DOES NOT NEED THE SEEDER CHANGED.
--   Re-anchoring on run change is exactly what boot already implies: the seeder writes
--   odometer_km := lifetime_base + drive_km_total, i.e. it has ALREADY credited the new
--   run's mileage-to-date. Treating a run change as "watermark unknown" makes the first
--   post-boot completion credit zero and simply record where the counter stands, which
--   is precisely right and leaves ottoq_seed_vehicle_need_profiles untouched. One fewer
--   200-line function in the blast radius.
--
-- ADDITIVE AND NULLABLE ON PURPOSE: ADD COLUMN with no default and no NOT NULL is a
-- catalogue-only operation in PostgreSQL 11+ -- no table rewrite, no lock held for the
-- length of a scan, safe on a live database. NULL is a meaningful value here: "no
-- mileage has been credited to this row yet", which is the correct initial state.
-- ============================================================================
ALTER TABLE public.vehicle_need_profile
  ADD COLUMN IF NOT EXISTS wear_km_applied     numeric,
  ADD COLUMN IF NOT EXISTS wear_km_applied_run uuid;

COMMENT ON COLUMN public.vehicle_need_profile.wear_km_applied IS
  'Watermark: how much of ottoq_vehicle_wear.drive_km_total has already been credited into odometer_km. Makes the odometer advance in ottoq_wear_mark_serviced idempotent under repeated or replayed service completions. NULL = nothing credited yet.';
COMMENT ON COLUMN public.vehicle_need_profile.wear_km_applied_run IS
  'The sim_run_id wear_km_applied belongs to. drive_km_total restarts at zero each run, so a watermark from a different run must re-anchor rather than suppress. NULL/mismatch = re-anchor, credit zero.';


-- ============================================================================
-- §3  public.ottoq_wear_mark_serviced  — CLOSE THE LOOP  (scope (a) and (b))
--
-- ── WHAT CHANGED ────────────────────────────────────────────────────────────
-- The existing UPDATE against ottoq_vehicle_wear is reproduced BYTE-FOR-BYTE. It is
-- correct and it is protected: every current behaviour that depends on soil_index,
-- km_at_last_pm, calibrated_at or the DTC counters resetting is unchanged. What is
-- added is a SECOND, INDEPENDENT update -- against vehicle_need_profile, the table the
-- decisions are actually read from.
--
-- ── THE SERVICE -> COLUMN MAP, AND WHY EACH ENTRY IS WHAT IT IS ─────────────
-- The vocabulary is closed and known: these are every value the two callers can pass.
-- twin.ottoq_sim_advance_service_flow passes, by bay:
--     in_wash_bay    -> exterior_wash, sensor_clean
--     in_detail_bay  -> interior_deep_clean, exterior_wash, interior_tidy
--     in_service_bay -> mechanical_pm, sensor_calibration, fault_repair, cosmetic_repair
-- ottoq_ingest_service_complete passes whatever the technician / OEM reports, from the
-- same vocabulary.
--
--   exterior_wash        -> last_wash_at        := p_clock
--   sensor_clean         -> (no profile column; wear.soil_index already handles it)
--   interior_deep_clean  -> last_deep_clean_at  := p_clock
--   interior_tidy        -> (no profile column; wear.cabin_litter_events handles it)
--   sensor_calibration   -> last_calibration_at := p_clock
--   mechanical_pm        -> last_pm_at          := p_clock
--                           km_at_last_pm       := odometer_km, POST-advance
--   fault_repair         -> (no profile column in scope; see GAP 2 below)
--   cosmetic_repair      -> (nothing; cosmetic work has no due-date dimension)
--   ANY of the above     -> odometer_km advanced by the un-credited part of
--                           drive_km_total (scope (b)); unconditional, because mileage
--                           accrues regardless of which service just finished.
--
-- WHY km_at_last_pm TAKES odometer_km AND NOT wear.drive_km_total.
--   This is the trap in this migration and it is worth being explicit about. The two
--   tables carry the same column NAME on two different SCALES:
--       ottoq_vehicle_wear.km_at_last_pm    RUN-scoped. Range measured: -89.9 .. 62.8
--                                           against drive_km_total 0 .. 159.
--       vehicle_need_profile.km_at_last_pm  LIFETIME. Range measured: 0 .. ~170,000.
--   Copying the first into the second -- the obvious reading of "mirror the truthful
--   ledger" -- would set every serviced vehicle's lifetime PM mark to roughly zero and
--   make it MAXIMALLY overdue the instant it was serviced. The correct lifetime
--   statement of "PM was just done" is "PM was done at the odometer reading it is
--   showing right now", so km_at_last_pm := the freshly-advanced odometer_km.
--
-- ── IDEMPOTENCY: HOW A COMPLETION IS GUARANTEED NOT TO DOUBLE-ADVANCE ───────
-- Three independent reasons, and they cover the two different kinds of write here:
--   1. THE DATE RESETS ARE ABSOLUTE ASSIGNMENTS, NOT INCREMENTS.
--      last_wash_at := p_clock is naturally idempotent: applying it twice with the
--      same p_clock leaves the identical value. There is no accumulator to inflate.
--      Same for last_deep_clean_at, last_calibration_at and last_pm_at.
--   2. THE ODOMETER ADVANCE IS FENCED BY A WATERMARK (§2).
--      The credited amount is GREATEST(0, drive_km_total - wear_km_applied), and
--      wear_km_applied is then set to drive_km_total in the same statement. A second
--      call with an unchanged drive_km_total computes GREATEST(0, 0) = 0 and adds
--      nothing. This holds for the FOREACH loop inside ottoq_ingest_service_complete
--      (four reported services credit the mileage once, not four times), for an OEM
--      replaying a completion, and for the sim path calling once per service code in
--      an array. GREATEST(0, ...) also makes the advance monotone: a wear counter that
--      somehow moved backwards can never rewind the odometer.
--   3. THE WATERMARK IS RUN-SCOPED, so a new run re-anchors instead of double-counting
--      the mileage the seeder already folded into odometer_km at boot (§2).
--   Net: this function is safe to call any number of times, in any order, for any
--   subset of services, from either seam.
--
-- ── TOTAL FUNCTION OVER BOTH SEAMS ─────────────────────────────────────────
-- The profile update is deliberately NOT conditional on the wear UPDATE having matched
-- a row. In production there is no sim run and therefore no ottoq_vehicle_wear row: the
-- wear UPDATE matches nothing and FOUND is false, but the vehicle was still serviced and
-- its due dates still have to move. So:
--   * the date resets need only p_clock and always apply;
--   * the odometer advance needs drive_km_total, and when there is no wear row it
--     credits zero and leaves the odometer alone -- no error, no guess;
--   * km_at_last_pm still takes whatever odometer_km reads, which in production is the
--     value the ingestion seam maintains.
-- An unknown service code is a no-op on every branch rather than an error. This is the
-- leg_type lesson: a seam between an OPEN vocabulary (what a technician or an OEM can
-- report) and a CLOSED one (the columns we keep) must be a TOTAL function, or one
-- unmapped string aborts the whole transaction.
--
-- ── FAILURE IS LOUD, NEVER SILENT, AND NEVER FATAL ─────────────────────────
-- The profile update is wrapped so that a failure warns by name and lets the wear
-- update -- the pre-existing, certified behaviour -- stand. This function is reachable
-- from the twin service flow inside a tick; it must never be the reason a tick aborts.
-- That is the leg_type root cause in one sentence, and it is not being repeated here.
--
-- ── RETURN VALUE PRESERVED ─────────────────────────────────────────────────
-- The old body ended `RETURN FOUND`, where FOUND referred to the wear UPDATE. Adding
-- statements after it would silently change what FOUND reports. The wear result is
-- therefore captured into v_wear_found IMMEDIATELY after its UPDATE and returned, so
-- the contract is bit-identical for both callers. (Both PERFORM it today and discard
-- the result -- but a return value that quietly changes meaning is exactly the kind of
-- thing that is fine until it is not.)
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
  -- Self-silencing by design: a failure here warns by name and leaves PART 1 standing.
  BEGIN
    -- The run-scoped mileage counter. NULL in production (no run, no wear row), which
    -- the arithmetic below treats as "credit nothing" rather than as an error.
    SELECT w.drive_km_total INTO v_drive_km
      FROM ottoq_vehicle_wear w
     WHERE w.vehicle_id = p_vehicle_id
       AND w.sim_run_id = p_sim_run_id
     LIMIT 1;

    UPDATE public.vehicle_need_profile p SET
      -- ── scope (b): ODOMETER, ADVANCED IDEMPOTENTLY ────────────────────────
      -- Credit only the part of drive_km_total not already credited. A watermark from
      -- a different run (or none) means "unknown" -> credit 0 and re-anchor.
      odometer_km = COALESCE(p.odometer_km, 0) + GREATEST(0,
                      COALESCE(v_drive_km, 0)
                      - CASE WHEN p.wear_km_applied_run IS NOT DISTINCT FROM p_sim_run_id
                             THEN COALESCE(p.wear_km_applied, COALESCE(v_drive_km, 0))
                             ELSE COALESCE(v_drive_km, 0) END),

      -- ── scope (a): LAST-DONE, PER SERVICE ─────────────────────────────────
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
      -- that column is run-scoped and would read as ~zero lifetime km. See the header.
      km_at_last_pm = CASE WHEN p_service = 'mechanical_pm'
                          THEN COALESCE(p.odometer_km, 0) + GREATEST(0,
                                 COALESCE(v_drive_km, 0)
                                 - CASE WHEN p.wear_km_applied_run IS NOT DISTINCT FROM p_sim_run_id
                                        THEN COALESCE(p.wear_km_applied, COALESCE(v_drive_km, 0))
                                        ELSE COALESCE(v_drive_km, 0) END)
                          ELSE p.km_at_last_pm END,

      -- ── the watermark itself ──────────────────────────────────────────────
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
-- §4  public.ottoq_ingest_service_complete  — UNGATE THE PRODUCTION SEAM
--
-- CORRECTION B, implemented. Two changes, both inside the block quoted in the header,
-- and nothing else in this 60+ line function is altered:
--
--   1. `IF v_run.sim_run_id IS NOT NULL AND v_before - v_after > 0`
--      becomes
--      `IF v_before - v_after > 0`.
--      The sim-run precondition made the ledger reset unreachable in real production,
--      where no ottoq_sim_runs row has status='running'. It was harmless while the
--      only thing downstream was a run-keyed wear table; it is not harmless now that
--      the same call also moves vehicle_need_profile, which is NOT run-keyed and is
--      what production would actually read. Never build a sim-only path.
--      The `v_before - v_after > 0` half is KEPT deliberately: it means "at least one
--      open workflow atom actually matched what was reported". A report that matches
--      nothing is already logged as a warning ten lines below; it must not silently
--      reset a due date.
--
--   2. `EXCEPTION WHEN OTHERS THEN NULL` becomes a named RAISE WARNING.
--      A swallowed exception on the production ingestion seam is how a depot ends up
--      believing a reset happened that did not -- the same failure shape as the cron
--      job that reported `succeeded` while every decide_tick was aborting. Still
--      non-fatal: one bad service code must not fail the technician's whole report.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_ingest_service_complete(p_vehicle_id uuid, p_source text DEFAULT 'production'::text, p_actor text DEFAULT 'depot_tech'::text, p_services text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_veh    vehicles%ROWTYPE;
  v_run    ottoq_sim_runs%ROWTYPE;
  v_clock  timestamptz;
  v_s      text;
  v_before int; v_after int;
BEGIN
  SELECT * INTO v_veh FROM vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'reason', 'vehicle_not_found'); END IF;

  SELECT * INTO v_run FROM ottoq_sim_runs
   WHERE depot_id = v_veh.home_depot_id AND status = 'running'
   ORDER BY started_at DESC LIMIT 1;
  v_clock := COALESCE(v_run.sim_clock_current, now());

  IF p_services IS NOT NULL AND array_length(p_services, 1) > 0 THEN
    IF v_veh.current_state IN ('deployed','en_route_to_deployment','offline') THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'vehicle_not_in_depot', 'state', v_veh.current_state::text);
    END IF;
    SELECT COUNT(*) INTO v_before FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open','in_progress')
       AND a->>'svc' = ANY(p_services) AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled');
    PERFORM ottoq_mark_visit_atoms_done(p_vehicle_id, p_services, v_clock);
    SELECT COUNT(*) INTO v_after FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
     WHERE vn.vehicle_id = p_vehicle_id AND vn.status IN ('open','in_progress')
       AND a->>'svc' = ANY(p_services) AND COALESCE(a->>'status','pending') NOT IN ('done','cancelled');
    -- ══════ 0004: the sim-run precondition is GONE. See §4 header. ══════
    -- v_run.sim_run_id may be NULL here; ottoq_wear_mark_serviced treats that as
    -- "no wear row" and still moves the profile's due dates, which is the whole point.
    IF v_before - v_after > 0 THEN
      FOREACH v_s IN ARRAY p_services LOOP
        BEGIN PERFORM ottoq_wear_mark_serviced(p_vehicle_id, v_run.sim_run_id, v_s, v_clock);
        EXCEPTION WHEN OTHERS THEN
          -- 0004: was `THEN NULL`. Loud, named, still non-fatal.
          RAISE WARNING 'ottoq_ingest_service_complete: wear/profile reset FAILED SAFELY for vehicle % service %: % %',
                        p_vehicle_id, v_s, SQLSTATE, SQLERRM;
        END;
      END LOOP;
    END IF;
    BEGIN
      PERFORM ottoq_record_event(
        p_actor_type := 'depot_tech', p_actor_id := p_actor,
        p_event_type := 'ops.services_completed_reported', p_entity_type := 'vehicle', p_entity_id := p_vehicle_id,
        p_payload := jsonb_build_object('services', to_jsonb(p_services), 'atoms_matched', v_before - v_after,
                                        'state', v_veh.current_state::text, 'source', p_source),
        p_severity := CASE WHEN v_before - v_after = 0 THEN 'warning' ELSE 'info' END,
        p_ingest_source := 'production', p_data_source := 'production',
        p_sim_run_id := v_run.sim_run_id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    RETURN jsonb_build_object('ok', v_before - v_after > 0, 'vehicle_id', p_vehicle_id,
      'services_reported', to_jsonb(p_services), 'atoms_matched', v_before - v_after,
      'note', CASE WHEN v_before - v_after = 0 THEN 'no open workflow atoms matched the reported services' ELSE NULL END);
  END IF;

  IF v_veh.current_state NOT IN ('in_wash_bay','in_detail_bay','in_service_bay') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_in_bay', 'state', v_veh.current_state::text);
  END IF;
  UPDATE vehicles SET config = jsonb_set(COALESCE(config,'{}'::jsonb), '{service_done}', 'true'::jsonb)
   WHERE id = p_vehicle_id;
  BEGIN
    PERFORM ottoq_record_event(
      p_actor_type := 'depot_tech', p_actor_id := p_actor,
      p_event_type := 'ops.service_marked_complete', p_entity_type := 'vehicle', p_entity_id := p_vehicle_id,
      p_payload := jsonb_build_object('state', v_veh.current_state::text, 'source', p_source),
      p_severity := 'info', p_ingest_source := 'production', p_data_source := 'production',
      p_sim_run_id := v_run.sim_run_id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RETURN jsonb_build_object('ok', true, 'vehicle_id', p_vehicle_id, 'state', v_veh.current_state::text);
END;
$function$;


-- ============================================================================
-- §5  THE 26 LAUNDERED PM ROWS  (scope (c), as the defect actually exists)
--
-- CORRECTION A, second half. ottoq_seed_vehicle_need_profiles computes
--     km_at_last_pm := GREATEST(0, odo_km - km_since_pm)
-- and the clamp fires whenever the seeded km-since-PM exceeds the drawn lifetime
-- odometer. MEASURED: 26 of 116 rows sit at exactly 0. A row at 0 does not read as
-- "clamped", it reads as "this vehicle's last PM was performed at odometer zero", so
-- the card computes
--     km_since_pm = GREATEST(0, odometer_km - km_at_last_pm) = the ENTIRE lifetime
-- and pm_ratio goes to 21x on the worst row (169,957 km against a 7,816 km mean
-- interval). The clamp did not prevent a bad number, it disguised one.
--
-- THE REPAIR IS A DATA REPAIR, NOT A TUNING CHANGE. It restates each affected row in
-- terms it already carries: a vehicle whose PM mark is unusable is placed at the most
-- recent PM boundary at or below its own odometer --
--     km_at_last_pm := odometer_km - MOD(odometer_km, pm_interval_km)
-- No constant is invented and no threshold is moved. The vehicle keeps its own
-- odometer and its own interval; only the impossible claim "last PM at 0 km" is
-- replaced by the nearest possible one. Because MOD spreads with the odometer, the
-- repaired rows land at scattered points in their cycles rather than all at once --
-- it preserves the phase spread that CORRECTION A explains, instead of collapsing it.
--
-- SCOPED TIGHT ON PURPOSE. Only rows where the clamp actually fired are touched, and
-- only when a positive pm_interval_km exists to reason with. Rows that were never
-- clamped are left exactly as drawn, so this cannot move a vehicle that was fine.
-- Idempotent: after the repair no row satisfies km_at_last_pm = 0 with a positive
-- odometer, so re-running changes nothing.
--
-- NOT FIXED IN THE SEEDER. The clamp itself lives in a 200-line boot function whose
-- draw governs the whole fleet's initial condition; changing it changes every future
-- run's starting state, which is a tuning decision, and tuning does not share a
-- migration with wiring. Recorded as GAP 3 below.
-- ============================================================================
UPDATE public.vehicle_need_profile p
   SET km_at_last_pm = p.odometer_km - MOD(p.odometer_km, p.pm_interval_km),
       updated_at    = now()
 WHERE COALESCE(p.km_at_last_pm, 0) = 0
   AND COALESCE(p.odometer_km, 0)   > 0
   AND COALESCE(p.pm_interval_km, 0) > 0;


-- ============================================================================
-- §6  POST-SNAPSHOT
-- ============================================================================
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0004_close_ledger_loop_post', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_wear_mark_serviced',
                     'ottoq_ingest_service_complete');


-- ============================================================================
-- §7  VERIFICATION
--
-- V1 and V2 are static and can be run the moment this migration lands. V3-V6 are
-- RUNTIME proof and require a bounded run of >= 139 sim-min, captured AFTER the run
-- is stopped, in the SIM domain, gated on arrivals. Runtime proof over source
-- inspection: this file's entire claim is that a completion now moves a due date, and
-- only a run can show that.
--
-- ⚠️ Starting a run purges the prior one. Preserve V3-V6 into a non-`ottoq`-prefixed
--    table BEFORE the next run starts, as MIGRATION_LOG.md already records for 0002/0003.
--
-- V1 -- the clamp is gone and nothing else moved. Expect laundered_rows_remaining = 0
--       and pm_mark_above_odometer = 0.
--   SELECT count(*) FILTER (WHERE COALESCE(km_at_last_pm,0) = 0
--                             AND COALESCE(odometer_km,0)  > 0) AS laundered_rows_remaining,
--          count(*) FILTER (WHERE km_at_last_pm > odometer_km) AS pm_mark_above_odometer,
--          round(max((odometer_km - km_at_last_pm) / NULLIF(pm_interval_km,0)), 2) AS worst_pm_ratio,
--          count(*) AS n
--     FROM public.vehicle_need_profile;
--   BASELINE BEFORE THIS MIGRATION: 26 laundered, worst_pm_ratio 21.x, n = 116.
--
-- V2 -- the phase offsets in the OTHER table are untouched. This is the CORRECTION A
--       guard rail. Expect wear_negative_km_at_last_pm = 111, unchanged, and
--       km_since_pm_negative = 0. If the first number moved, something in this
--       migration wrote ottoq_vehicle_wear and it must not.
--   SELECT count(*) FILTER (WHERE km_at_last_pm < 0)              AS wear_negative_km_at_last_pm,
--          count(*) FILTER (WHERE km_at_last_pm > drive_km_total) AS km_since_pm_negative,
--          count(*) AS n
--     FROM public.ottoq_vehicle_wear;
--
-- V3 -- THE HEADLINE. The ledger is alive. Before this migration this was 0 of 116, by
--       construction, in every run ever recorded. Any number > 0 is the first time a
--       service completion has ever moved the table the decisions are read from.
--   SELECT count(*) FILTER (WHERE updated_at > drawn_at) AS profiles_moved_after_boot,
--          count(*) AS n,
--          count(DISTINCT date_trunc('second', updated_at)) AS distinct_update_moments
--     FROM public.vehicle_need_profile;
--
-- V4 -- convergence, which is the whole argument for the backfill choice below.
--       Expect overdue_or_critical to FALL against the 98/116 = 84.5% baseline, and
--       ok to rise from 0. Report BOTH as a fraction of the 116 denominator AND per
--       ARRIVING VEHICLE, which is the primary metric.
--   SELECT overall_urgency, count(*) FROM public.ottoq_vehicle_needs_card
--    GROUP BY 1 ORDER BY 2 DESC;
--   BASELINE: critical 65, overdue 33, due 17, due_soon 1, ok 0.  n = 116.
--
-- V5 -- idempotency, proven rather than asserted. Call the function twice with an
--       unchanged wear counter and confirm the odometer does not move. Run inside a
--       transaction and ROLL BACK.
--   BEGIN;
--     SELECT vehicle_id, odometer_km AS before_km, wear_km_applied
--       FROM public.vehicle_need_profile ORDER BY vehicle_id LIMIT 1;
--     -- call it three times with the same clock, as a re-reported completion would
--     SELECT public.ottoq_wear_mark_serviced(
--              (SELECT vehicle_id FROM public.vehicle_need_profile ORDER BY vehicle_id LIMIT 1),
--              (SELECT sim_run_id FROM public.ottoq_sim_runs ORDER BY started_at DESC LIMIT 1),
--              'mechanical_pm', now()) FROM generate_series(1,3);
--     SELECT vehicle_id, odometer_km AS after_km, wear_km_applied, km_at_last_pm
--       FROM public.vehicle_need_profile ORDER BY vehicle_id LIMIT 1;
--   ROLLBACK;
--   EXPECT: after_km - before_km is credited AT MOST ONCE, and identical whether the
--   function was called once or three times.
--
-- V6 -- the protected baseline did not regress. Re-measure, do not assume:
--       cut-short charging recovery 58.3% | approvals 48/48 decided, 0 pending,
--       median 8.2 sim-min | 0 real double-bookings | no starvation | phantoms 0 |
--       reverse coverage 100% | emission invariant 1.000 | work done per arrival 1.625 |
--       assignments per arrival ex-inspect 0.946 | inspection-zone parking 0%.
--       Nothing in this file runs inside decide_tick or touches a booking, so the
--       expectation is no movement at all. Measure it anyway.
--
-- ============================================================================
-- THE BACKFILL QUESTION — DECIDED, AND WHY
--
-- On the first run after this lands the fleet is still 84.5% overdue from its seeded
-- values. Two options were on the table:
--   (i)  leave it, and let it converge as services complete;
--   (ii) re-seed profiles at boot from a realistic distribution so the fleet starts
--        plausible.
--
-- ⭐ RECOMMENDED AND IMPLEMENTED: (i). No backfill of the last-done dates. §5 repairs
--    26 impossible PM marks and nothing else is reset.
--
-- The reasoning, in order of weight:
--
--   1. OPTION (ii) IS A TUNING CHANGE WEARING A BACKFILL COSTUME, AND THIS FILE IS
--      FORBIDDEN FROM TUNING. The 84.5% is not an accident and not a bug in the
--      wiring -- it is the arithmetic of the seeder's own multipliers. It draws
--      last-done times as a uniform fraction of MORE than one interval:
--          wash_ago_h   = 1.45 x random x wash_interval_h    -> P(overdue) = 31%
--          calib_ago_h  = 1.50 x random x calib_interval_h   -> P(overdue) = 33%
--          deep_ago_h   = 1.18 x random x 336h               -> P(overdue) = 15%
--          km_since_pm  = 1.45 x random x pm_interval_km     -> P(overdue) = 31%
--      Four near-independent dimensions at roughly a third each, plus faults, software
--      and energy, and 84.5% is exactly what falls out. "Re-seeding from a realistic
--      distribution" means changing 1.45 and 1.50 to something at or below 1.0. That
--      is retuning the interval model, which the scope explicitly forbids in this
--      migration: wiring and tuning must never share a file or you cannot tell which
--      one caused the change you measured.
--
--   2. CONVERGENCE IS THE PROOF. THE OVERDUE FLEET IS THE EXPERIMENT, NOT THE PROBLEM.
--      A fleet that starts overdue and drains as services complete is a strong,
--      unambiguous signal that a completion now moves the ledger -- V3 and V4 above
--      measure exactly that, against a baseline (98/116, and 0 of 116 ever updated)
--      that is already recorded. Re-seed the fleet clean and that signal disappears:
--      a clean fleet stays clean whether the wiring works or not, and the one run that
--      could have proven this migration proves nothing. Deleting your own control arm
--      to make the first screenshot look better is a bad trade.
--
--   3. IT IS THE REVERSIBLE CHOICE. (i) leaves every prior run's initial conditions
--      intact, so the >=139 sim-min certification stays comparable to the phase-11/14
--      baselines this repo protects. (ii) changes the starting state of every future
--      run and silently invalidates that comparison -- and unlike a function, a
--      changed distribution leaves no md5 to notice it by.
--
--   4. THE USUAL OBJECTION DOES NOT APPLY HERE. The risk of starting overdue is that
--      ALWAYS-HOLD binds hard and ~98 vehicles demand mandatory bay work against 2
--      service bays and 3 wash bays. That risk is real -- and it is exactly why
--      ottoq_apply_need_escalation stays OFF in this migration. With escalation off,
--      an overdue grade is an urgency reading, not a mandate, so a fleet that starts
--      overdue costs throughput nothing while it converges. The two decisions are
--      deliberately paired: leaving the fleet overdue is only safe BECAUSE escalation
--      is not enabled here, and enabling escalation is only safe AFTER the ledger has
--      been shown to drain. That ordering is the phase gate.
--
--   IF CONVERGENCE FAILS -- the falsifiable version. If after a >=139 sim-min run V3
--   shows profiles_moved_after_boot > 0 but V4 shows overdue_or_critical essentially
--   flat, then the ledger is being written and is still not draining, and the cause is
--   arrival throughput or must_do selection rather than the wiring. That is a
--   different migration and this file should not be blamed for it. Recording the
--   prediction now is what makes the next result mean something.
--
-- ============================================================================
-- GAPS FOUND WHILE VERIFYING — RECORDED, DELIBERATELY NOT FIXED HERE
--
-- GAP 1 — CLOSING THE LOOP ON DATES CLOSES ROUGHLY TWO THIRDS OF IT, NOT ALL.
--   Several urgency dimensions in ottoq_vehicle_needs_card are ottoq_urgency_max() of
--   a TIME ratio and a CONDITION reading, and this migration only moves the time half:
--       wash_urgency  = MAX(f(last_wash_at), f(exterior_soil_level))
--       cabin_urgency = MAX(f(last_deep_clean_at), f(cabin_condition))
--       calib_urgency = MAX(f(last_calibration_at), f(sensor_health_pct))
--   MEASURED on the 38 vehicles currently wash-overdue: 24 are time-driven and WILL
--   clear when last_wash_at moves; 14 are soil-driven and will NOT, because
--   exterior_soil_level is a second, stale copy of a fact ottoq_vehicle_wear.soil_index
--   already tracks correctly. Same shape for cabin (30 rows) and faults (11 rows,
--   open_fault_codes / worst_fault_severity never reset after fault_repair).
--   Not fixed here because it is a DIFFERENT defect -- duplicated condition state
--   across two tables -- and merging those copies changes what "dirty" means, which is
--   a tuning question. Expect V4 to improve substantially but not to reach 0 overdue,
--   and do not read the remainder as this migration failing.
--
-- GAP 2 — fault_repair and cosmetic_repair have no vehicle_need_profile counterpart at
--   all, so a completed repair cannot lower fault_urgency. Folded into GAP 1's fix.
--
-- GAP 3 — the GREATEST(0, ...) clamp in ottoq_seed_vehicle_need_profiles is still
--   there. §5 repairs the 26 rows it has already produced; the next boot will produce
--   a fresh batch. The seeder fix belongs with the interval retune (see the backfill
--   note, reason 1), because both are edits to the same draw.
--
-- GAP 4 — twin.ottoq_sim_advance_service_flow marks the WHOLE bay array serviced on
--   exit, so a vehicle leaving the wash bay is recorded as having had both
--   exterior_wash AND sensor_clean regardless of what its workflow actually asked for.
--   Pre-existing, unchanged here, and it will now propagate into vehicle_need_profile
--   as well as ottoq_vehicle_wear -- i.e. this migration makes an existing
--   over-marking defect more visible without making it worse. Worth its own pass.
-- ============================================================================
