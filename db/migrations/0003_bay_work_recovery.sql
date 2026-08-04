-- migration-version: 20260804183836
-- migration-name:    bay_work_recovery

-- ============================================================================
-- 0003_bay_work_recovery.sql
--
-- THE SHORT VERSION, IN PLAIN LANGUAGE
--
-- When a car is pulled out of a charger before it is finished, it gets another
-- charger. Migration 0002 got that number from 0-out-of-38 to 7-out-of-12. When a car
-- is pulled out of a WASH BAY, a DETAIL BAY or a SERVICE BAY before it is finished, it
-- gets nothing. Not sometimes -- never. Five interrupted bay jobs in the last measured
-- run, zero replacements.
--
-- The reason turns out to be simple, and it is the reason the two numbers differ.
--
-- A car that is unplugged early still has a low battery. The battery is a physical fact
-- sitting in the car, and the engine looks at it directly -- "is your charge below your
-- target?" -- every single tick. So the need for charge RE-CREATES ITSELF. None of the
-- paperwork about the interruption has to work for charging to recover; the car itself
-- is the witness.
--
-- A car that is pulled out of a wash bay has no equivalent witness. The engine decides
-- who needs a bay by reading a MAINTENANCE SCHEDULE -- last washed at, last deep-cleaned
-- at, kilometres since service. And when the vehicle left the bay, the simulator stamped
-- that job "completed" and reset the schedule. In one case measured here it credited a
-- full 35-minute service job for 27 SECONDS of actual work. From that moment the car's
-- schedule says it is clean and serviced, so the bay logic will never look at it again --
-- while the outstanding-work ledger, a completely different record, still says the work
-- is owed. Two records of the same job, disagreeing, and the one the bay logic reads is
-- the one that was wrong.
--
-- That is a deadlock, and we watched it happen: vehicle 5cee8fb3 logged 33 consecutive
-- refusals to redeploy ("you still owe work") over 30 sim-minutes, and in that same 30
-- minutes was never once considered for a bay ("your schedule says you are fine").
--
-- THE FIX IS TO GIVE BAY WORK THE SECOND WITNESS THAT CHARGING ALREADY HAS.
-- The outstanding-work ledger now feeds the same "what does this vehicle need" card the
-- bay logic reads. If a job was booked, started, and taken away, the card says so --
-- regardless of what the maintenance schedule was told afterwards. Charging keeps its
-- battery; bays now have their ledger. That is the whole idea.
--
-- Two smaller things follow from it, and they are in this file too: a car that lost a
-- bay was being excluded from bays for as long as it still wanted charge (even when
-- there was no charger free for it to take), and resumed work needed a defined place in
-- the queue relative to new arrivals. Both are settled below, explicitly.
--
-- ============================================================================
-- SYMPTOM  (run 093c20f4-cf2d-4a6c-ab1c-693b98e51c0c, 179.8 sim-min, 112 arrivals,
--           preserved in public.phase13_bookings_424242 -- 710 rows, sim window
--           13:03:32.199 -> 15:59:15.928. All times SIM unless marked REAL.)
--   17 bookings were interrupted. 12 charging, 5 not (detail 2, service 2, staging 1).
--   Charging replacements: 7 of 12 = 58.3%.   Bay replacements: 0 of 5 = 0.0%.
--   Not one of the five ever produced so much as a REFUSAL from the bay loop, except
--   the staging one. There was no losing decision, because there was no decision.
--
-- CAUSE  (three defects; the first is the whole story, the other two are why the
--         first one is not enough on its own)
--
--   1. THE CARD HAS ONLY ONE DETECTOR, AND THE TWIN CAN FALSELY RESET IT.
--      public.ottoq_decide_tick section (4b) selects bay candidates entirely from
--      public.ottoq_vehicle_needs_card.must_do_now. That array is built from the
--      CADENCE PROFILE alone -- last_wash_at, last_deep_clean_at, last_calibration_at,
--      km_at_last_pm, cabin_condition, exterior_soil_level. The card touches
--      ottoq_visit_needs in exactly two places (open_work_min, open_must_do_min) and
--      both are scalar sums that feed RANKING only. Neither can put a service into
--      must_do_now. So a re-opened bay need is invisible to the only code that hands
--      out bays.
--      EVIDENCE, vehicle 5cee8fb3: interrupted at 15:25:26 after 0.46 of 35 planned
--      minutes (completion_ratio 0.013, minutes_remaining 34.54, atoms_reopened 1) --
--      and at REAL 15:10:17 the twin had already logged twin.service_completed from
--      in_service_bay. Cadence clock reset; ledger still owing; bay loop blind.
--      EVIDENCE, vehicle d075ca68 (2cd2cbf3): interrupted 15:24:58, 8.76 of 30.92
--      minutes, outstanding_restored 1, legs_replanned 1 -- then sat in
--      staged_awaiting_service for 34.3 sim-min with no bay decision of any kind.
--
--      CONTRAST -- THE CHARGE PATH, which is what tells us this is the bug. Section (3)
--      qualifies a vehicle with
--          AND v.current_soc < COALESCE((SELECT vn.target_soc ...), 85)
--      a LIVE PHYSICAL MEASUREMENT off vehicles.current_soc. No reference to
--      ottoq_visit_needs.atoms, to meta ? 'reopen', or to any interruption bookkeeping.
--      Charging has two independent detectors and the physical one always works.
--      Confirming this: 6 of the 7 charge replacements were booked in the SAME SECOND
--      as the release (14:12->14:12, 14:16->14:16, 14:54->14:54, 15:18->15:18) with
--      source='deterministic'. That is not the reopen machinery running. That is the
--      ordinary SoC-driven intake firing on the very next pass.
--
--   2. THE CHARGE FIREWALL EXCLUDES A CAR THAT COULD NOT GET A CHARGER ANYWAY.
--      Section (4b) skips any vehicle with 'charge' in must_do_now. Correct as a default
--      -- charge is the anchor leg. But vehicle 0ea2ccfe ended the run with
--      must_do_now = {charge, interior_deep_clean, software_update} after losing a detail
--      bay at 1.42 of 25 minutes. The detail work was owed AND must-do, and this one
--      predicate excluded it for the remaining 24.3 sim-min. Fixing (1) alone would not
--      have reached it.
--
--   3. RESUMED WORK HAD NO DEFINED PLACE IN THE QUEUE.
--      Even once the card lists the owed service, the vehicle sorts by overall_urgency --
--      which the twin has just reset to 'ok'. It would arrive in the cursor and lose
--      every tie to every fresh arrival, forever.
--
--   NOT A DEFECT, RECORDED SO IT IS NOT MISCOUNTED: the fifth case, vehicle 252ba623
--   (purpose 'staging', min_lost 23.26), is the ONE case that DID reach a decision --
--   ottoq_service_priority -> hold_no_bay / no_free_space at 15:27:52, the only
--   no-space refusal in the entire run. Staging is not a bay lane and this migration
--   does not touch it. Genuine scarcity is not a code defect and this file does not
--   manufacture capacity. The honest P0 denominator is therefore 4 BAY jobs, not 5.
--
-- FIX  (this file, in order)
--   §1  policy catalogue row for the one new dial (bay_resume_share_max).
--   §2  snapshots + guards for the three objects being replaced.
--   §3  public.ottoq_vehicle_needs_card -- ADD THE LEDGER DETECTOR. must_do_now becomes
--       cadence-due UNION ledger-owed; three new columns expose the ledger side.
--   §4  public.ottoq_decide_tick -- narrow the charge firewall for owed bay work, floor
--       resumed work at 'due', give it a per-lane per-tick budget so fresh arrivals are
--       not starved, and stamp the recovery so it is countable.
--   §5  public.ottoq_indepot_reassignment_guard -- P1(a) + P1(b): the three
--       born-approved fast paths stamp the SIM clock and write the audit object.
--   §6  public.ottoq_indepot_gate_latency -- P1(b): ONE canonical, never-mixed-domain
--       latency measurement, so the next person cannot recreate the same error.
--   §7  P1(c) THE EVICTION RE-BASELINE, recorded (read this before calling anything a
--       regression).
--   §8  post-snapshots.   §9 verification.
--
-- WHAT THIS FILE DELIBERATELY DOES NOT CHANGE
--   * It does not touch sections (1), (2), (3), (3b), (4) or (5) of ottoq_decide_tick.
--     The charge path is byte-for-byte identical, including Gate B in
--     ottoq_honour_reservation_proposal and the cuOpt 'source' passthrough.
--   * It does not change overall_urgency, open_work_min, open_must_do_min or
--     fits_window. Too many readers depend on them; the resumption floor is applied in
--     the bay cursor's own sort key instead, where its blast radius is one loop.
--   * It does not let bay work take a charger: ottoq.ottoq_enact_space_assignment still
--     refuses 'dcfc'/'l2' outright, and this file never calls it with either.
--   * It does not invent a new value for any closed vocabulary. p_source stays
--     'needs_card'; resumption is recorded on the DECISION row. (2026-08-01 leg_type.)
--   * It does not rewrite twin.ottoq_sim_vehicle_exception_handler. See §7 for the one
--     residual metric constant found there and why it is deferred to its own migration.
--   * It never DROPs anything and it never touches ottoq_events except to READ, in §9,
--     through a narrow indexed probe.
--
-- BLAST RADIUS
--   public.ottoq_vehicle_needs_card has four callers. Verified individually:
--     - public.ottoq_decide_tick (4b)          reads must_do_now  -> THIS IS THE TARGET.
--     - twin.ottoq_sim_advance_service_flow    reads must_do_now as EVIDENCE ONLY on the
--       hold receipt; its actual readiness predicate is `work_open`, computed directly
--       from ottoq_visit_needs. Widening must_do_now therefore CANNOT hold a vehicle
--       back from deployment. Vehicle-first doctrine is untouched -- checked, not assumed.
--     - ottoq.ottoq_book_workflow              reads minutes_to_deploy / fits_window /
--       overall_urgency only. None of the three changes.
--     - public.ottoq_service_priority          reads the per-service urgency columns and
--       the atom's own must_do flag. Does not read must_do_now.
--   must_do_legs is derived through public.ottoq_svc_to_leg_type, which is TOTAL
--   (ELSE 'service'), so no ledger value can reach a CHECK constraint. Belt and braces,
--   the ledger CTE only admits services that are in service_cadence_policy with a bay
--   lane, which is a closed catalogue set.
--
-- METHOD NOTE ON THE GUARDS  (§2)
--   Two different guard techniques, because the two targets have two different
--   provenances, and mixing them up is how a guard becomes decorative.
--   * ottoq_vehicle_needs_card and ottoq_decide_tick were NOT touched by 0002, so their
--     expected hashes are computed offline from db/baseline/, which was exported
--     verbatim on 2026-08-03. The extraction method was validated by recomputing 0002's
--     own published hash for ottoq_indepot_reassignment_guard
--     (141b5ff01c1bcf61d2fbc9a5aa66ce4a) from the same files and getting a byte match.
--   * ottoq_indepot_reassignment_guard WAS replaced by 0002, so its live body is not in
--     any baseline file and no offline hash of it can be trusted. It is guarded against
--     the post-snapshot 0002 itself recorded
--     (label '0002_approval_gate_decider_post'), which is the precise question we want
--     asked: has anything changed since 0002 was applied?
--   Any mismatch ABORTS. That is intended. Re-read the live body, re-base, re-run.
-- ============================================================================


-- ============================================================================
-- §1  POLICY CATALOGUE
--
-- One dial. Catalogue rows exist so OTTOCOMMAND / Nemotron can see and set it at all
-- (public.ottoq_policy_set refuses any param_key with no catalogue row).
-- ============================================================================
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects)
VALUES
  ('bay_resume_share_max',
   'Maximum share of a bay lane''s free spaces that RESUMED (previously interrupted) work may take in a single decide tick, while fresh work is also queued for that lane. Never rounds down to zero -- the defect being fixed is bay recovery of exactly zero.',
   0.5, 0, 1, 'bay allocation between resumed work and fresh arrivals')
ON CONFLICT (param_key) DO NOTHING;


-- ============================================================================
-- §2  SNAPSHOT, THEN GUARD  (house rule 1)
--
-- Recover any of these later with:
--   SELECT definition FROM public.ottoq_schema_snapshots
--    WHERE label = '0003_bay_work_recovery_pre' AND object_name = '<name>';
-- ============================================================================
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0003_bay_work_recovery_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_decide_tick', 'ottoq_indepot_reassignment_guard');

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0003_bay_work_recovery_pre', 'view', n.nspname, c.relname,
       pg_get_viewdef(c.oid, true), md5(pg_get_viewdef(c.oid, true))
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'v'
   AND c.relname = 'ottoq_vehicle_needs_card';

DO $guard$
DECLARE
  -- Computed offline from db/baseline/ (2026-08-03 export). See METHOD NOTE above.
  v_expect_fn CONSTANT jsonb := jsonb_build_object(
    'public.ottoq_decide_tick', 'd279aa48fda56492587123c50888396a');
  v_expect_vw CONSTANT text := '4f42015a3051a3c80fb39177bb9e72ea';
  k text; v_actual text; v_n int; v_snap text; v_snap_n int;
BEGIN
  -- ── functions carried straight from the baseline export ──
  FOR k IN SELECT jsonb_object_keys(v_expect_fn) LOOP
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
    ELSIF v_actual <> (v_expect_fn->>k) THEN
      RAISE EXCEPTION
        'GUARD: % live md5 % does not match expected %. Someone changed this function outside this migration (or the 2026-08-03 baseline export is stale). Re-read the live body, re-base, re-run. Nothing has been changed.',
        k, v_actual, (v_expect_fn->>k);
    END IF;
  END LOOP;

  -- ── the view, same provenance, guarded on pg_get_viewdef ──
  SELECT count(*), min(md5(rtrim(pg_get_viewdef(c.oid, true), E' \n\r\t')))
    INTO v_n, v_actual
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'v' AND c.relname = 'ottoq_vehicle_needs_card';

  IF COALESCE(v_n,0) = 0 THEN
    RAISE EXCEPTION 'GUARD: view public.ottoq_vehicle_needs_card does not exist. Aborting.';
  ELSIF v_actual <> v_expect_vw THEN
    RAISE EXCEPTION
      'GUARD: view public.ottoq_vehicle_needs_card live md5 % does not match expected %. Re-read the live definition (SELECT pg_get_viewdef(''public.ottoq_vehicle_needs_card''::regclass, true)), re-base this migration on it, re-run. Nothing has been changed.',
      v_actual, v_expect_vw;
  END IF;

  -- ── the 0002-owned function, guarded against 0002's own post-snapshot ──
  -- def_md5 there was recorded as md5(pg_get_functiondef(oid)) with no rtrim, so the
  -- comparison below is deliberately the un-rtrimmed one. Like for like.
  SELECT count(DISTINCT s.def_md5), min(s.def_md5)
    INTO v_snap_n, v_snap
    FROM public.ottoq_schema_snapshots s
   WHERE s.label = '0002_approval_gate_decider_post'
     AND s.schema_name = 'public'
     AND s.object_name = 'ottoq_indepot_reassignment_guard';

  IF COALESCE(v_snap_n,0) = 0 THEN
    RAISE EXCEPTION
      'GUARD: no 0002_approval_gate_decider_post snapshot for public.ottoq_indepot_reassignment_guard. This migration is based on the body 0002 installed; without that snapshot there is nothing to verify against. Aborting.';
  ELSIF v_snap_n > 1 THEN
    RAISE EXCEPTION
      'GUARD: % DISTINCT post-snapshot hashes for public.ottoq_indepot_reassignment_guard under label 0002_approval_gate_decider_post. Ambiguous baseline. Aborting.', v_snap_n;
  END IF;

  SELECT count(*), min(md5(pg_get_functiondef(p.oid)))
    INTO v_n, v_actual
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_indepot_reassignment_guard';

  IF COALESCE(v_n,0) <> 1 THEN
    RAISE EXCEPTION
      'GUARD: public.ottoq_indepot_reassignment_guard resolved to % routines, expected exactly 1. Aborting.', v_n;
  ELSIF v_actual <> v_snap THEN
    RAISE EXCEPTION
      'GUARD: public.ottoq_indepot_reassignment_guard live md5 % does not match the body migration 0002 installed (%). It has been changed outside the migration files since 2026-08-04. Re-read the live body, re-base, re-run. Nothing has been changed.',
      v_actual, v_snap;
  END IF;

  RAISE NOTICE '0003 guards passed: decide_tick, needs_card view, and the 0002-installed reassignment guard are all exactly what this migration was written against.';
END
$guard$;


-- ============================================================================
-- §3  public.ottoq_vehicle_needs_card  —  GIVE BAY WORK ITS SECOND WITNESS
--
-- ── DESIGN DECISIONS, AND WHY ───────────────────────────────────────────────
--
-- WHY THE CARD AND NOT THE TICK. The card is the object that answers "what does this
-- vehicle need". It already answers that question for charge using two independent
-- witnesses -- the cadence/atom manifest AND the battery. For bay work it had one, and
-- that one is writable by the twin. Fixing this inside ottoq_decide_tick would have
-- made the tick disagree with the card, which is exactly the shape of the booking-ledger
-- divergence of 2026-08-01: two places computing the same thing and drifting apart.
-- One detector, one place, every reader sees the same answer.
--
-- WHY THE LEDGER CTE IS NARROW. It admits an atom only when ALL of these hold:
--   * its service is in service_cadence_policy with lane wash_bay / detail / service_bay
--     (a CLOSED catalogue set -- 'charge' can never enter, and neither can a service the
--     bay loop has no space map for);
--   * the atom is not done / cancelled / skipped;
--   * the atom was MUST-DO (deferrable work does not get to jump a scarce bay);
--   * and there is INTERRUPTION EVIDENCE: the atom carries reopened_at or cut_short_at,
--     or the needs row carries meta->'reopen'.
-- That last clause is the difference between "re-detect what the depot took away" and
-- "send every vehicle with an open manifest to a bay". The measured shapes are covered:
-- 5cee8fb3 reopened one atom (atom-level evidence); d075ca68, 229f655b and 0ea2ccfe
-- reopened zero atoms but restored the row (row-level evidence, historically ~96% of
-- cases). Both routes are honoured.
--
-- WHAT IT DOES NOT DO. It does not touch overall_urgency, open_work_min,
-- open_must_do_min or fits_window. Widening urgency from the ledger would corrupt a
-- number that four functions and every cockpit read. The resumption priority is applied
-- in §4's sort key instead, where exactly one loop can see it.
--
-- RUN SCOPING. The new CTE is scoped to the card's own run
-- (n.sim_run_id = b.run_id OR n.sim_run_id IS NULL), which the two pre-existing scalar
-- sums are NOT. RECORDED, NOT FIXED: open_work_min / open_must_do_min still read every
-- run's rows. Changing them changes fits_window, which changes ranking in
-- ottoq_book_workflow and in this same bay loop, and that belongs in its own migration
-- with its own certification. Related known issue: ottoq_visit_needs.visit_key lacks run
-- scoping (2026-07-26).
--
-- COST. The card is a ~116-row / ~250 ms view evaluated ONCE per tick. This adds one
-- grouped scan of ottoq_visit_needs (already read twice here) joined to the small
-- service_cadence_policy catalogue. est_min is cast through a regex guard rather than
-- bare ::numeric, so a malformed atom cannot raise inside a view on the tick path.
--
-- NEW COLUMNS ARE APPENDED AT THE END, and no existing column changes name, type or
-- position, so CREATE OR REPLACE VIEW is legal and every existing SELECT keeps working:
--   owed_bay_svcs text[]   -- bay services this vehicle owes from interrupted work
--   owed_bay_min  numeric  -- estimated minutes of that owed work
--   rebook_owed   boolean  -- the P0 flag: this vehicle is owed a bay it already held
-- must_do_now keeps its name and its text[] type; its VALUE is now cadence UNION ledger.
-- deferrable_now excludes anything that became must-do, so the two lists cannot
-- contradict each other.
-- ============================================================================
CREATE OR REPLACE VIEW public.ottoq_vehicle_needs_card AS
 WITH run AS (
         SELECT DISTINCT ON (r_1.depot_id) r_1.depot_id,
            r_1.sim_run_id,
            COALESCE(r_1.sim_clock_current, r_1.sim_clock_start, now()) AS sim_clock
           FROM ottoq_sim_runs r_1
          ORDER BY r_1.depot_id, (r_1.status = 'running'::text) DESC, r_1.started_at DESC
        ), base AS (
         SELECT p.vehicle_id,
            p.profile_version,
            p.drawn_for_run,
            p.drawn_seed,
            p.drawn_at,
            p.drawn_at_sim_clock,
            p.battery_soh_pct,
            p.battery_chemistry,
            p.charge_accept_kw,
            p.pack_temp_c,
            p.dcfc_safe,
            p.dcfc_block_reason,
            p.cell_balance_due_at,
            p.min_ready_soc_pct,
            p.exterior_soil_level,
            p.cabin_condition,
            p.last_wash_at,
            p.last_deep_clean_at,
            p.wash_interval_h,
            p.deep_clean_interval_h,
            p.calib_interval_h,
            p.calib_interval_km,
            p.last_calibration_at,
            p.sensor_health_pct,
            p.software_version,
            p.sw_target_version,
            p.sw_update_size_mb,
            p.odometer_km,
            p.pm_interval_km,
            p.km_at_last_pm,
            p.last_pm_at,
            p.open_fault_codes,
            p.worst_fault_severity,
            p.tire_tread_mm,
            p.tire_rotation_due_km,
            p.brake_wear_pct,
            p.next_deploy_at,
            p.priority_class,
            p.assigned_shift,
            p.item_retrieval_pending,
            p.item_reported_at,
            p.item_description,
            p.updated_at,
            v.av_api_vehicle_id AS av_id,
            v.display_name,
            v.home_depot_id AS depot_id,
            v.current_state,
            v.current_soc,
            v.target_soc,
            v.battery_capacity_kwh,
            v.inlet_max_kw,
            r_1.sim_run_id AS run_id,
            COALESCE(r_1.sim_clock, now()) AS sim_clock
           FROM vehicle_need_profile p
             JOIN vehicles v ON v.id = p.vehicle_id
             LEFT JOIN run r_1 ON r_1.depot_id = v.home_depot_id
        ), owed AS (
         -- ══════════════════ 0003: THE LEDGER DETECTOR ══════════════════
         -- The bay analogue of `vehicles.current_soc`. Charging recovers after an
         -- interruption because the BATTERY re-asserts the need on its own; bay work had
         -- no such second witness, so when the twin credited a 0.46-minute service as
         -- complete the cadence clock reset and the work vanished from must_do_now.
         -- This CTE reads the OUTSTANDING-WORK LEDGER instead of the cadence clock.
         -- DELIBERATELY NARROW: only atoms carrying interruption evidence
         -- (atom-level `reopened_at`/`cut_short_at`, or a row-level meta->'reopen'
         -- stamp, which is the ~96%-of-the-time shape) and only work that was must-do.
         -- It therefore re-detects work the depot TOOK AWAY; it does not flood the bays
         -- with fresh cadence work. 'charge' can never enter here: the join to
         -- service_cadence_policy is restricted to the three BAY lanes.
         SELECT b.vehicle_id,
            COALESCE(array_agg(DISTINCT (a.value ->> 'svc'::text)), '{}'::text[]) AS owed_bay_svcs,
            COALESCE(sum(CASE WHEN (a.value ->> 'est_min'::text) ~ '^[0-9]+(\.[0-9]+)?$'::text
                              THEN (a.value ->> 'est_min'::text)::numeric ELSE 0::numeric END),
                     0::numeric) AS owed_bay_min
           FROM base b
             JOIN ottoq_visit_needs n ON n.vehicle_id = b.vehicle_id
              AND n.status = ANY (ARRAY['open'::text, 'in_progress'::text])
              -- run-scoped, unlike the two legacy scalar sums below: a previous run's
              -- ledger must never re-open a bay in this one.
              AND (n.sim_run_id = b.run_id OR n.sim_run_id IS NULL OR b.run_id IS NULL)
             CROSS JOIN LATERAL jsonb_array_elements(COALESCE(n.atoms, '[]'::jsonb)) a(value)
             JOIN service_cadence_policy p ON p.svc = (a.value ->> 'svc'::text) AND p.is_active
              AND p.lane = ANY (ARRAY['wash_bay'::text, 'detail'::text, 'service_bay'::text])
          WHERE lower(COALESCE(a.value ->> 'status'::text, 'pending'::text))
                  <> ALL (ARRAY['done'::text, 'cancelled'::text, 'skipped'::text])
            AND COALESCE((a.value ->> 'must_do'::text)::boolean, false)
            AND ((a.value ? 'reopened_at'::text) OR (a.value ? 'cut_short_at'::text)
                 OR (COALESCE(n.meta, '{}'::jsonb) ? 'reopen'::text))
          GROUP BY b.vehicle_id
        ), calc AS (
         SELECT b.vehicle_id,
            b.profile_version,
            b.drawn_for_run,
            b.drawn_seed,
            b.drawn_at,
            b.drawn_at_sim_clock,
            b.battery_soh_pct,
            b.battery_chemistry,
            b.charge_accept_kw,
            b.pack_temp_c,
            b.dcfc_safe,
            b.dcfc_block_reason,
            b.cell_balance_due_at,
            b.min_ready_soc_pct,
            b.exterior_soil_level,
            b.cabin_condition,
            b.last_wash_at,
            b.last_deep_clean_at,
            b.wash_interval_h,
            b.deep_clean_interval_h,
            b.calib_interval_h,
            b.calib_interval_km,
            b.last_calibration_at,
            b.sensor_health_pct,
            b.software_version,
            b.sw_target_version,
            b.sw_update_size_mb,
            b.odometer_km,
            b.pm_interval_km,
            b.km_at_last_pm,
            b.last_pm_at,
            b.open_fault_codes,
            b.worst_fault_severity,
            b.tire_tread_mm,
            b.tire_rotation_due_km,
            b.brake_wear_pct,
            b.next_deploy_at,
            b.priority_class,
            b.assigned_shift,
            b.item_retrieval_pending,
            b.item_reported_at,
            b.item_description,
            b.updated_at,
            b.av_id,
            b.display_name,
            b.depot_id,
            b.current_state,
            b.current_soc,
            b.target_soc,
            b.battery_capacity_kwh,
            b.inlet_max_kw,
            b.run_id,
            b.sim_clock,
                CASE
                    WHEN b.next_deploy_at IS NULL THEN NULL::integer
                    ELSE round(EXTRACT(epoch FROM b.next_deploy_at - b.sim_clock) / 60.0)::integer
                END AS minutes_to_deploy,
            GREATEST(0::numeric, COALESCE(b.min_ready_soc_pct, 80::numeric) - COALESCE(b.current_soc, 0)::numeric) AS soc_deficit_to_sla,
            GREATEST(0, COALESCE(b.target_soc, 90) - COALESCE(b.current_soc, 0)) AS soc_deficit_to_target,
            round(COALESCE(ottoq_estimate_charge_minutes(COALESCE(b.current_soc, 50)::numeric, COALESCE(b.target_soc, 90)::numeric, 150::numeric, COALESCE(b.inlet_max_kw, 150::numeric), COALESCE(b.battery_capacity_kwh, 75::numeric), COALESCE(b.pack_temp_c, 25::numeric), COALESCE(b.battery_soh_pct, 95::numeric), 1.0), 0::numeric))::integer AS est_charge_min,
            round(EXTRACT(epoch FROM b.sim_clock - b.last_wash_at) / 3600.0 / NULLIF(b.wash_interval_h, 0::numeric), 3) AS wash_ratio,
            round(EXTRACT(epoch FROM b.sim_clock - b.last_deep_clean_at) / 3600.0 / NULLIF(b.deep_clean_interval_h, 0::numeric), 3) AS deep_clean_ratio,
            round(EXTRACT(epoch FROM b.sim_clock - b.last_calibration_at) / 3600.0 / NULLIF(b.calib_interval_h, 0::numeric), 3) AS calib_ratio,
            round(GREATEST(0::numeric, b.odometer_km - COALESCE(b.km_at_last_pm, 0::numeric)) / NULLIF(b.pm_interval_km, 0::numeric), 3) AS pm_ratio,
            b.last_wash_at + make_interval(hours => COALESCE(b.wash_interval_h, 72::numeric)::integer) AS wash_due_at,
            b.last_deep_clean_at + make_interval(hours => COALESCE(b.deep_clean_interval_h, 336::numeric)::integer) AS deep_clean_due_at,
            b.last_calibration_at + make_interval(hours => COALESCE(b.calib_interval_h, 250::numeric)::integer) AS calib_due_at,
            GREATEST(0::numeric, b.odometer_km - COALESCE(b.km_at_last_pm, 0::numeric)) AS km_since_pm,
            b.software_version IS DISTINCT FROM b.sw_target_version AS sw_behind,
            ( SELECT COALESCE(sum((a.value ->> 'est_min'::text)::numeric), 0::numeric) AS "coalesce"
                   FROM ottoq_visit_needs n,
                    LATERAL jsonb_array_elements(n.atoms) a(value)
                  WHERE n.vehicle_id = b.vehicle_id AND n.status = 'open'::text) AS open_work_min,
            ( SELECT COALESCE(sum((a.value ->> 'est_min'::text)::numeric), 0::numeric) AS "coalesce"
                   FROM ottoq_visit_needs n,
                    LATERAL jsonb_array_elements(n.atoms) a(value)
                  WHERE n.vehicle_id = b.vehicle_id AND n.status = 'open'::text AND COALESCE((a.value ->> 'must_do'::text)::boolean, false)) AS open_must_do_min
           FROM base b
        ), grade AS (
         SELECT c.vehicle_id,
            c.profile_version,
            c.drawn_for_run,
            c.drawn_seed,
            c.drawn_at,
            c.drawn_at_sim_clock,
            c.battery_soh_pct,
            c.battery_chemistry,
            c.charge_accept_kw,
            c.pack_temp_c,
            c.dcfc_safe,
            c.dcfc_block_reason,
            c.cell_balance_due_at,
            c.min_ready_soc_pct,
            c.exterior_soil_level,
            c.cabin_condition,
            c.last_wash_at,
            c.last_deep_clean_at,
            c.wash_interval_h,
            c.deep_clean_interval_h,
            c.calib_interval_h,
            c.calib_interval_km,
            c.last_calibration_at,
            c.sensor_health_pct,
            c.software_version,
            c.sw_target_version,
            c.sw_update_size_mb,
            c.odometer_km,
            c.pm_interval_km,
            c.km_at_last_pm,
            c.last_pm_at,
            c.open_fault_codes,
            c.worst_fault_severity,
            c.tire_tread_mm,
            c.tire_rotation_due_km,
            c.brake_wear_pct,
            c.next_deploy_at,
            c.priority_class,
            c.assigned_shift,
            c.item_retrieval_pending,
            c.item_reported_at,
            c.item_description,
            c.updated_at,
            c.av_id,
            c.display_name,
            c.depot_id,
            c.current_state,
            c.current_soc,
            c.target_soc,
            c.battery_capacity_kwh,
            c.inlet_max_kw,
            c.run_id,
            c.sim_clock,
            c.minutes_to_deploy,
            c.soc_deficit_to_sla,
            c.soc_deficit_to_target,
            c.est_charge_min,
            c.wash_ratio,
            c.deep_clean_ratio,
            c.calib_ratio,
            c.pm_ratio,
            c.wash_due_at,
            c.deep_clean_due_at,
            c.calib_due_at,
            c.km_since_pm,
            c.sw_behind,
            c.open_work_min,
            c.open_must_do_min,
                CASE
                    WHEN c.soc_deficit_to_sla > 0::numeric AND COALESCE(c.minutes_to_deploy, 999999) < c.est_charge_min THEN 'critical'::text
                    WHEN c.soc_deficit_to_sla > 0::numeric THEN 'due'::text
                    WHEN c.soc_deficit_to_target > 5 THEN 'due_soon'::text
                    ELSE 'ok'::text
                END AS energy_urgency,
            ottoq_urgency_max(ottoq_service_urgency('exterior_wash'::text, c.wash_ratio),
                CASE
                    WHEN c.exterior_soil_level >= 0.85 THEN 'overdue'::text
                    WHEN c.exterior_soil_level >= 0.65 THEN 'due'::text
                    WHEN c.exterior_soil_level >= 0.45 THEN 'due_soon'::text
                    ELSE 'ok'::text
                END) AS wash_urgency,
            ottoq_urgency_max(ottoq_service_urgency('interior_deep_clean'::text, c.deep_clean_ratio),
                CASE
                    WHEN c.cabin_condition = 'biohazard'::text THEN 'critical'::text
                    WHEN c.cabin_condition = 'soiled'::text THEN 'overdue'::text
                    WHEN c.cabin_condition = 'light_litter'::text THEN 'due_soon'::text
                    ELSE 'ok'::text
                END) AS cabin_urgency,
            ottoq_urgency_max(ottoq_service_urgency('sensor_calibration'::text, c.calib_ratio),
                CASE
                    WHEN c.sensor_health_pct < 89::numeric THEN 'due'::text
                    WHEN c.sensor_health_pct < 91::numeric THEN 'due_soon'::text
                    ELSE 'ok'::text
                END) AS calib_urgency,
            ottoq_service_urgency('mechanical_pm'::text, c.pm_ratio) AS pm_urgency,
            ottoq_service_urgency('fault_repair'::text,
                CASE
                    WHEN c.worst_fault_severity = 1 THEN 2.00
                    WHEN c.worst_fault_severity <= 3 THEN 1.30
                    WHEN c.worst_fault_severity <= 5 THEN 0.80
                    ELSE 0.00
                END) AS fault_urgency,
                CASE
                    WHEN c.tire_tread_mm < 2.7 THEN 'critical'::text
                    WHEN c.tire_tread_mm < 3.0 THEN 'due'::text
                    WHEN c.tire_tread_mm < 4.0 THEN 'due_soon'::text
                    ELSE 'ok'::text
                END AS tire_urgency,
                CASE
                    WHEN c.brake_wear_pct >= 82::numeric THEN 'critical'::text
                    WHEN c.brake_wear_pct >= 80::numeric THEN 'due'::text
                    WHEN c.brake_wear_pct >= 65::numeric THEN 'due_soon'::text
                    ELSE 'ok'::text
                END AS brake_urgency,
            ottoq_service_urgency('software_update'::text,
                CASE
                    WHEN NOT c.software_version IS DISTINCT FROM c.sw_target_version THEN 0.00
                    WHEN c.software_version = '2026.26.2'::text THEN 1.30
                    ELSE 0.80
                END) AS software_urgency,
                CASE
                    WHEN c.item_retrieval_pending THEN 'due'::text
                    ELSE 'ok'::text
                END AS item_urgency
           FROM calc c
        ), mech AS (
         SELECT g.vehicle_id,
            g.profile_version,
            g.drawn_for_run,
            g.drawn_seed,
            g.drawn_at,
            g.drawn_at_sim_clock,
            g.battery_soh_pct,
            g.battery_chemistry,
            g.charge_accept_kw,
            g.pack_temp_c,
            g.dcfc_safe,
            g.dcfc_block_reason,
            g.cell_balance_due_at,
            g.min_ready_soc_pct,
            g.exterior_soil_level,
            g.cabin_condition,
            g.last_wash_at,
            g.last_deep_clean_at,
            g.wash_interval_h,
            g.deep_clean_interval_h,
            g.calib_interval_h,
            g.calib_interval_km,
            g.last_calibration_at,
            g.sensor_health_pct,
            g.software_version,
            g.sw_target_version,
            g.sw_update_size_mb,
            g.odometer_km,
            g.pm_interval_km,
            g.km_at_last_pm,
            g.last_pm_at,
            g.open_fault_codes,
            g.worst_fault_severity,
            g.tire_tread_mm,
            g.tire_rotation_due_km,
            g.brake_wear_pct,
            g.next_deploy_at,
            g.priority_class,
            g.assigned_shift,
            g.item_retrieval_pending,
            g.item_reported_at,
            g.item_description,
            g.updated_at,
            g.av_id,
            g.display_name,
            g.depot_id,
            g.current_state,
            g.current_soc,
            g.target_soc,
            g.battery_capacity_kwh,
            g.inlet_max_kw,
            g.run_id,
            g.sim_clock,
            g.minutes_to_deploy,
            g.soc_deficit_to_sla,
            g.soc_deficit_to_target,
            g.est_charge_min,
            g.wash_ratio,
            g.deep_clean_ratio,
            g.calib_ratio,
            g.pm_ratio,
            g.wash_due_at,
            g.deep_clean_due_at,
            g.calib_due_at,
            g.km_since_pm,
            g.sw_behind,
            g.open_work_min,
            g.open_must_do_min,
            g.energy_urgency,
            g.wash_urgency,
            g.cabin_urgency,
            g.calib_urgency,
            g.pm_urgency,
            g.fault_urgency,
            g.tire_urgency,
            g.brake_urgency,
            g.software_urgency,
            g.item_urgency,
            ottoq_urgency_max(g.pm_urgency, ottoq_urgency_max(g.tire_urgency, g.brake_urgency)) AS mech_urgency
           FROM grade g
        ), cand AS (
         SELECT m.vehicle_id,
            x.svc,
            x.urg,
            ottoq_service_must_do(x.svc, x.urg) AS is_must_do
           FROM mech m
             CROSS JOIN LATERAL ( VALUES ('charge'::text,m.energy_urgency,m.energy_urgency <> 'ok'::text), ('exterior_wash'::text,m.wash_urgency,true), ('interior_deep_clean'::text,m.cabin_urgency,true), ('sensor_calibration'::text,m.calib_urgency,true), ('mechanical_pm'::text,m.mech_urgency,true), ('fault_repair'::text,m.fault_urgency,COALESCE(m.worst_fault_severity::integer, 99) <= 3), ('software_update'::text,m.software_urgency,m.sw_behind), ('item_retrieval'::text,m.item_urgency,m.item_retrieval_pending)) x(svc, urg, applies)
          WHERE x.applies
        ), agg AS (
         SELECT cand.vehicle_id,
            COALESCE(array_agg(DISTINCT cand.svc) FILTER (WHERE cand.is_must_do), '{}'::text[]) AS must_do_now,
            COALESCE(array_agg(DISTINCT cand.svc) FILTER (WHERE NOT cand.is_must_do AND ottoq_urgency_rank(cand.urg) >= 2), '{}'::text[]) AS deferrable_now
           FROM cand
          GROUP BY cand.vehicle_id
        ), roll AS (
         SELECT m.vehicle_id,
            m.profile_version,
            m.drawn_for_run,
            m.drawn_seed,
            m.drawn_at,
            m.drawn_at_sim_clock,
            m.battery_soh_pct,
            m.battery_chemistry,
            m.charge_accept_kw,
            m.pack_temp_c,
            m.dcfc_safe,
            m.dcfc_block_reason,
            m.cell_balance_due_at,
            m.min_ready_soc_pct,
            m.exterior_soil_level,
            m.cabin_condition,
            m.last_wash_at,
            m.last_deep_clean_at,
            m.wash_interval_h,
            m.deep_clean_interval_h,
            m.calib_interval_h,
            m.calib_interval_km,
            m.last_calibration_at,
            m.sensor_health_pct,
            m.software_version,
            m.sw_target_version,
            m.sw_update_size_mb,
            m.odometer_km,
            m.pm_interval_km,
            m.km_at_last_pm,
            m.last_pm_at,
            m.open_fault_codes,
            m.worst_fault_severity,
            m.tire_tread_mm,
            m.tire_rotation_due_km,
            m.brake_wear_pct,
            m.next_deploy_at,
            m.priority_class,
            m.assigned_shift,
            m.item_retrieval_pending,
            m.item_reported_at,
            m.item_description,
            m.updated_at,
            m.av_id,
            m.display_name,
            m.depot_id,
            m.current_state,
            m.current_soc,
            m.target_soc,
            m.battery_capacity_kwh,
            m.inlet_max_kw,
            m.run_id,
            m.sim_clock,
            m.minutes_to_deploy,
            m.soc_deficit_to_sla,
            m.soc_deficit_to_target,
            m.est_charge_min,
            m.wash_ratio,
            m.deep_clean_ratio,
            m.calib_ratio,
            m.pm_ratio,
            m.wash_due_at,
            m.deep_clean_due_at,
            m.calib_due_at,
            m.km_since_pm,
            m.sw_behind,
            m.open_work_min,
            m.open_must_do_min,
            m.energy_urgency,
            m.wash_urgency,
            m.cabin_urgency,
            m.calib_urgency,
            m.pm_urgency,
            m.fault_urgency,
            m.tire_urgency,
            m.brake_urgency,
            m.software_urgency,
            m.item_urgency,
            m.mech_urgency,
            COALESCE(a.must_do_now, '{}'::text[]) AS must_do_now_raw,
            COALESCE(a.deferrable_now, '{}'::text[]) AS deferrable_now_raw,
            COALESCE(o.owed_bay_svcs, '{}'::text[]) AS owed_bay_svcs_raw,
            COALESCE(o.owed_bay_min, 0::numeric) AS owed_bay_min_raw,
            -- 0003: cadence-due UNION ledger-owed. This is the ONE place the two
            -- detectors are combined, so every reader downstream sees the same answer.
            ( SELECT COALESCE(array_agg(DISTINCT u.x), '{}'::text[]) AS "coalesce"
                   FROM unnest(COALESCE(a.must_do_now, '{}'::text[])
                               || COALESCE(o.owed_bay_svcs, '{}'::text[])) u(x)) AS must_do_all_raw
           FROM mech m
             LEFT JOIN agg a ON a.vehicle_id = m.vehicle_id
             LEFT JOIN owed o ON o.vehicle_id = m.vehicle_id
        )
 SELECT vehicle_id,
    av_id,
    display_name,
    depot_id,
    run_id,
    sim_clock,
    current_state,
    drawn_seed,
    profile_version,
    current_soc AS soc_pct,
    target_soc AS target_soc_pct,
    min_ready_soc_pct,
    soc_deficit_to_sla,
    soc_deficit_to_target,
    est_charge_min,
    battery_soh_pct,
    battery_chemistry,
    charge_accept_kw,
    pack_temp_c,
    dcfc_safe,
    dcfc_block_reason,
    cell_balance_due_at,
    energy_urgency,
    exterior_soil_level,
    cabin_condition,
    last_wash_at,
    wash_due_at,
    wash_ratio,
    wash_urgency,
    last_deep_clean_at,
    deep_clean_due_at,
    deep_clean_ratio,
    cabin_urgency,
    last_calibration_at,
    calib_due_at,
    calib_ratio,
    calib_urgency,
    sensor_health_pct,
    software_version,
    sw_target_version,
    sw_behind,
    sw_update_size_mb,
    software_urgency,
    odometer_km,
    km_since_pm,
    pm_interval_km,
    pm_ratio,
    pm_urgency,
    open_fault_codes,
    worst_fault_severity,
    fault_urgency,
    tire_tread_mm,
    tire_urgency,
    brake_wear_pct,
    brake_urgency,
    next_deploy_at,
    minutes_to_deploy,
    priority_class,
    assigned_shift,
    item_retrieval_pending,
    item_description,
    item_reported_at,
    item_urgency,
    must_do_all_raw AS must_do_now,
    ( SELECT COALESCE(array_agg(DISTINCT d.x), '{}'::text[]) AS "coalesce"
           FROM unnest(r.deferrable_now_raw) d(x)
          WHERE NOT (d.x = ANY (r.must_do_all_raw))) AS deferrable_now,
    open_work_min,
    open_must_do_min,
        CASE
            WHEN minutes_to_deploy IS NULL THEN true
            ELSE minutes_to_deploy::numeric >= GREATEST(est_charge_min::numeric, open_must_do_min)
        END AS fits_window,
    ( SELECT ottoq_urgency_max(ottoq_urgency_max(ottoq_urgency_max(ottoq_urgency_max(r.energy_urgency, r.wash_urgency), ottoq_urgency_max(r.cabin_urgency, r.calib_urgency)), ottoq_urgency_max(r.mech_urgency, r.fault_urgency)), ottoq_urgency_max(
                CASE
                    WHEN r.priority_class = 'critical'::text THEN 'critical'::text
                    ELSE 'ok'::text
                END, ottoq_urgency_max(r.software_urgency, r.item_urgency))) AS ottoq_urgency_max) AS overall_urgency,
    ( SELECT array_agg(DISTINCT ottoq_need_to_leg_type(x.x, r.dcfc_safe)) AS array_agg
           FROM unnest(r.must_do_all_raw) x(x)) AS must_do_legs,
    jsonb_build_object('vehicle_id', vehicle_id, 'av_id', av_id, 'as_of', sim_clock, 'commitment', jsonb_build_object('next_deploy_at', next_deploy_at, 'minutes_to_deploy', minutes_to_deploy, 'priority_class', priority_class, 'assigned_shift', assigned_shift), 'energy', jsonb_build_object('soc_pct', current_soc, 'target_soc_pct', target_soc, 'min_ready_soc_pct', min_ready_soc_pct, 'est_charge_min', est_charge_min, 'battery_soh_pct', battery_soh_pct, 'charge_accept_kw', charge_accept_kw, 'pack_temp_c', pack_temp_c, 'dcfc_safe', dcfc_safe, 'dcfc_block_reason', dcfc_block_reason, 'urgency', energy_urgency), 'cleanliness', jsonb_build_object('exterior_soil_level', exterior_soil_level, 'cabin_condition', cabin_condition, 'wash_due_at', wash_due_at, 'wash_ratio', wash_ratio, 'wash_urgency', wash_urgency, 'deep_clean_due_at', deep_clean_due_at, 'cabin_urgency', cabin_urgency), 'sensor_software', jsonb_build_object('calib_due_at', calib_due_at, 'calib_ratio', calib_ratio, 'calib_urgency', calib_urgency, 'sensor_health_pct', sensor_health_pct, 'software_version', software_version, 'sw_target_version', sw_target_version, 'sw_behind', sw_behind, 'software_urgency', software_urgency), 'mechanical', jsonb_build_object('odometer_km', odometer_km, 'km_since_pm', km_since_pm, 'pm_ratio', pm_ratio, 'pm_urgency', pm_urgency, 'open_fault_codes', to_jsonb(open_fault_codes), 'worst_fault_severity', worst_fault_severity, 'fault_urgency', fault_urgency, 'tire_tread_mm', tire_tread_mm, 'tire_urgency', tire_urgency, 'brake_wear_pct', brake_wear_pct, 'brake_urgency', brake_urgency), 'items', jsonb_build_object('pending', item_retrieval_pending, 'description', item_description, 'reported_at', item_reported_at), 'must_do_now', to_jsonb(must_do_all_raw), 'deferrable_now', to_jsonb(( SELECT COALESCE(array_agg(DISTINCT d2.x), '{}'::text[]) AS "coalesce"
           FROM unnest(r.deferrable_now_raw) d2(x)
          WHERE NOT (d2.x = ANY (r.must_do_all_raw)))), 'must_do_legs', to_jsonb(( SELECT array_agg(DISTINCT ottoq_need_to_leg_type(x.x, r.dcfc_safe)) AS array_agg
           FROM unnest(r.must_do_all_raw) x(x))), 'open_work_min', open_work_min, 'open_must_do_min', open_must_do_min, 'owed_bay_svcs', to_jsonb(owed_bay_svcs_raw), 'owed_bay_min', owed_bay_min_raw, 'rebook_owed', (COALESCE(array_length(owed_bay_svcs_raw, 1), 0) > 0)) AS need_statement,
    owed_bay_svcs_raw AS owed_bay_svcs,
    owed_bay_min_raw AS owed_bay_min,
    (COALESCE(array_length(owed_bay_svcs_raw, 1), 0) > 0) AS rebook_owed
   FROM roll r;

-- ============================================================================
-- §4  public.ottoq_decide_tick  —  LET THE RECOVERED NEED REACH A BAY
--
-- Only section (4b), the needs-card bay loop, is modified. Sections (1) energy,
-- (2) deploy, (3) charge, (3b) no-charge gate intake, (4) charge disposition, (5)
-- service sequencing and the inspect seam are reproduced BYTE-FOR-BYTE from the
-- 2026-08-03 baseline. That is why the md5 guard in §2 matters: it proves the text this
-- file is based on is the text that is running.
--
-- ── DESIGN DECISION 1: THE CHARGE FIREWALL IS NARROWED, NOT REMOVED ─────────
-- Charge remains the anchor leg. A vehicle with 'charge' in must_do_now still belongs to
-- section (3) -- EXCEPT when all three of these are true at once:
--     (a) it owes interrupted bay work (rebook_owed, i.e. the ledger, not the cadence);
--     (b) its energy_urgency is not 'critical' (an SLA-threatened car is never diverted);
--     (c) there is no free, Available, unreserved charger at this depot at this instant.
-- (c) is the load-bearing condition and it is not a guess: section (3) has already run
-- this tick, on this depot, using the identical availability predicate. If a plug had
-- been free this vehicle would already be on it -- it is still sitting in
-- staged_awaiting_service, which is the proof. So the bay costs the depot zero charging
-- throughput. It converts time the car would have spent parked waiting for a plug that
-- does not exist into finished work. The instant a charger frees, the exception stops
-- admitting new vehicles.
-- A car already inside a bay is NOT pulled back out for a charger: that would be an
-- in-depot reassignment and it goes through the gate, not through here.
--
-- ── DESIGN DECISION 2: PRIORITY BETWEEN RESUMED WORK AND FRESH ARRIVALS ─────
-- THIS IS THE ONE THE FOUNDER SHOULD READ. It changes how a scarce bay is allocated.
--
-- The atomic-visit doctrine says resumed work should generally win, and it does here --
-- but bounded, in two specific ways, because "resumed always wins" is how you starve the
-- front door.
--
--   FLOOR, NOT OVERRIDE. A job that was booked, started and then interrupted was must-do
--   when it was booked, so its effective urgency is floored at 'due' (rank 3). It is NOT
--   promoted to 'overdue' or 'critical'. Consequence, stated plainly: a fresh arrival
--   with OVERDUE or CRITICAL bay work still beats resumed work outright, every time. The
--   floor exists only to undo the twin's false cadence reset -- it restores the urgency
--   the work already had; it does not invent new urgency.
--
--   RESUMED WINS THE TIE. At equal effective urgency, is_resume sorts first. That is the
--   atomic-visit doctrine: finish what the depot already started before starting
--   something new. Same rule applies WITHIN a vehicle -- if a car owes an interrupted job
--   and also has fresh cadence work due, the interrupted job is picked first.
--
-- ── HOW FRESH ARRIVALS ARE PROTECTED FROM BEING STARVED ─────────────────────
-- Three independent mechanisms, none of which relies on the others:
--   1. THE FLOOR IS 'due', NOT 'critical'. Any fresh arrival whose bay work is genuinely
--      more urgent than 'due' outranks every resumed vehicle in the cursor. Resumption
--      cannot cut in front of urgent new work at all.
--   2. A PER-LANE, PER-TICK RESUMPTION BUDGET. At most
--      GREATEST(1, CEIL(free_bays_in_lane * bay_resume_share_max)) of this tick's
--      admissions in a lane may go to resumption -- and the budget is only enforced while
--      fresh candidates are actually queued for that same lane (fresh_waiting_lane > 0,
--      computed as a window function over the whole qualifying set, before the LIMIT).
--      With the depot's 3 wash and 2 service bays and the default share of 0.5, that is
--      1-2 per lane per tick. Over-budget resumptions are a plain CONTINUE: the vehicle
--      is sequenced, never dropped, and returns next tick with its floor intact.
--   3. THE BUDGET NEVER APPLIES TO AN EMPTY QUEUE. If no fresh work wants the lane, the
--      cap does not bite and free bays are never held empty on principle. Idle capacity
--      helps nobody.
--   And the counter-starvation guarantee in the other direction -- the one this whole
--   migration exists for -- is the GREATEST(1, ...): resumption's budget can never round
--   down to zero, because zero is precisely the bug being fixed.
--
-- ── WHY NOT SIMPLY GIVE RESUMED WORK ABSOLUTE PRIORITY ──────────────────────
-- Considered and rejected. Under a sustained interruption rate (bay faults, tech flags)
-- an absolute rule lets resumed vehicles hold both wash bays and both service bays
-- indefinitely while arriving vehicles queue at the gate. Throughput per ARRIVING
-- VEHICLE is the primary certified metric, and absolute priority optimises the wrong
-- denominator. The floor-plus-budget shape gets the 0-of-4 to a real number without
-- betting the arrival metric on it.
--
-- ── WHAT IS RECORDED, SO THE RESULT IS MEASURABLE INSTEAD OF BELIEVED ───────
-- Every bay decision row now carries, in context_frame: is_resume, eff_urgency_rank,
-- fresh_waiting_lane, resume_cap_lane. Every ENACTED one carries, in enacted_action:
-- resumed_bay_work (the P0 numerator) and resumed_need. So
-- "cut-short bay work re-booked into a space it holds" is countable from ottoq_decisions
-- directly, with no reconstruction and no join to ottoq_events.
--
-- ── SAFETY ──
-- No new failure mode is introduced on the tick path. The added SQL is one EXISTS, two
-- CASE expressions, one window function and two integer counters. Every new value is
-- COALESCEd at the point of use. Nothing here can raise; nothing here can abort the tick.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_decide_tick(p_sim_run_id uuid)
 RETURNS ottoq_decide_tick_result
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_clock timestamptz; v_tick bigint; v_snapshot_id uuid;
  v_req RECORD; v_ctx jsonb; v_proposal jsonb; v_action jsonb;
  v_blocks int; v_block_codes text[]; v_rule_rows jsonb; v_disarm jsonb;
  v_outcome text; v_over boolean; v_safe boolean;
  v_t0 timestamptz; v_prop_ms int; v_shield_ms int; v_enact_ms int;
  v_built int := 0; v_enacted int := 0; v_overc int := 0; v_deferred int := 0; v_errored int := 0; v_disn int := 0;
  v_bess RECORD; v_energy RECORD;
  v_total_fleet int; v_curr_deployed int; v_target_pct numeric; v_demand_target int; v_deploy_budget int;
  v_charge_cap_kw numeric; v_ev_committed_kw numeric := 0; v_stage_stall uuid;
  v_charge_leg RECORD; v_bkg uuid;
  v_stage_leg_id uuid; v_stage_until timestamptz;
  v_bay_leg_id uuid; v_bay_leg_type text; v_bay_dur interval; v_bay_until timestamptz;
  v_bay_bkg uuid; v_bay_purpose text;
  -- P1 (needs-card space routing)
  v_need RECORD; v_space jsonb;
  v_wash_phys int; v_svc_phys int; v_wash_open int; v_svc_open int;
  -- 0003 (bay work recovery): resumption budget per lane per tick.
  v_res_share numeric; v_wash_res_cap int; v_svc_res_cap int;
  v_wash_res_used int := 0; v_svc_res_used int := 0;
BEGIN
  SELECT depot_id, sim_clock_current, tick_count INTO v_depot, v_clock, v_tick
    FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN ROW(0,NULL,0,0,0,0,0,0,0)::ottoq_decide_tick_result; END IF;
  v_snapshot_id := ottoq_capture_decision_snapshot(p_sim_run_id, v_tick, v_depot, v_clock);

  -- P1 BAY RELEASE. twin.ottoq_sim_advance_service_flow STEP 1 moves a vehicle OUT of a bay
  -- back to staged_awaiting_service and never clears stalls.current_vehicle_id or
  -- vehicles.current_stall_id; nothing else clears a bay either. Physical bay occupancy is
  -- switched ON below, so without this sweep the 3 wash / 2 service bays would fill and
  -- NEVER free - a permanent depot deadlock after five vehicles. Release-only: this call can
  -- free a space but can never claim one, and it never touches dcfc/l2 stalls.
  -- BOOKING LIFECYCLE. Promote held -> active for every booking whose vehicle is now
  -- physically standing on its stall, BEFORE the release sweep below. This is what gives
  -- 'active' a meaning, and what lets the sweep close a REAL occupancy as 'done' (with its
  -- window truncated to the true end) instead of lumping it in with forward reservations
  -- that nobody ever used. Release-only and non-fatal, like the sweep itself.
  PERFORM ottoq.ottoq_activate_present_bookings(p_sim_run_id, v_clock);

  -- HONOUR OR RE-PLAN, NEVER LET IT ROT (2026-08-02). Runs BEFORE the release sweep on
  -- purpose: a bay reservation whose vehicle is still bolted to a charger is slid forward
  -- to when the car can actually be there, so the sweep below never sees it as a no-show.
  -- Bounded defers + explicit give-up: it can free a window or move one, never claim one.
  PERFORM ottoq.ottoq_reconcile_bay_reservations(p_sim_run_id, v_depot, v_clock);

  PERFORM ottoq.ottoq_release_vacated_spaces(p_sim_run_id, v_depot, v_clock);

  -- NO BAY ENTRY WITHOUT A BOOKING. twin.ottoq_sim_advance_service_flow STEP 2 admits
  -- vehicles into wash/detail/service bays on STAFF capacity and claims no stall at all,
  -- so those occupancies were invisible to the forward calendar -- which is how 22
  -- vehicles came to be "in" 2 physical service bays. OTTO-Q reconciles here: book what
  -- is physically there, in place, against a real stall. Release-only for chargers,
  -- non-fatal, and it never moves a vehicle that is already standing in a real bay.
  PERFORM ottoq.ottoq_bind_unbooked_bay_occupants(p_sim_run_id, v_depot, v_clock);

  SELECT lmp_usd_per_mwh INTO v_energy FROM ottoq_grid_snapshots WHERE sim_run_id=p_sim_run_id ORDER BY sim_clock_at DESC LIMIT 1;

  -- (1) ENERGY / BESS
  FOR v_bess IN SELECT bess_id, current_soc_pct FROM ottoq_bess_units WHERE depot_id = v_depot LOOP
    v_built := v_built + 1; v_t0 := clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := jsonb_build_object('depot_id',v_depot,'now_ts',v_clock,'bess_id',v_bess.bess_id,
              'bess_soc_pct',v_bess.current_soc_pct,'lmp_usd_mwh',COALESCE(v_energy.lmp_usd_per_mwh,40));
    v_proposal := ottoq_l2_propose_bess(v_bess.bess_id, v_depot, v_ctx);
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN
      v_deferred := v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'bess_dispatch','bess',v_bess.bess_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      CONTINUE;
    END IF;
    v_ctx := v_ctx || jsonb_build_object('requested_kw', v_proposal->>'requested_kw', 'action', v_proposal->>'action');
    v_t0 := clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('bess_dispatch','bess',v_bess.bess_id,v_ctx,NULL,v_depot);
    v_shield_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_bess(v_bess.bess_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1; END IF;
    v_t0 := clock_timestamp();
    IF v_outcome='enacted' THEN PERFORM ottoq_apply_bess_setpoint(v_bess.bess_id, (v_action->>'requested_kw')::numeric, 250, v_clock); END IF;
    v_enact_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'bess_dispatch','bess_dispatch','bess',v_bess.bess_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- (2) DEPLOY-READINESS
  SELECT COUNT(*) INTO v_total_fleet FROM vehicles WHERE category='autonomous' AND home_depot_id=v_depot;
  SELECT COUNT(*) INTO v_curr_deployed FROM vehicles
    WHERE category='autonomous' AND home_depot_id=v_depot AND current_state IN ('deployed','en_route_to_deployment');
  SELECT COALESCE((s.fleet_overrides->>'target_deployed_fraction')::numeric, 0.55) INTO v_target_pct
    FROM ottoq_sim_runs r LEFT JOIN ottoq_sim_scenarios s ON s.scenario_code = COALESCE(r.scenario_code,'normal_day')
   WHERE r.sim_run_id = p_sim_run_id;
  v_demand_target := FLOOR(v_total_fleet * ottoq_deploy_target_fraction(EXTRACT(HOUR FROM (v_clock AT TIME ZONE 'America/Chicago'))::int, ottoq_policy_get(p_sim_run_id,'deploy_peak_fraction',COALESCE(v_target_pct, 0.90))));
  v_deploy_budget := GREATEST(v_demand_target - v_curr_deployed, 0);

  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       AND v.current_state='staged_for_departure'
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
             WHERE vn.vehicle_id = v.id AND (vn.sim_run_id = p_sim_run_id OR vn.sim_run_id IS NULL) AND vn.status IN ('open','in_progress')
               AND ((a->>'svc' = 'software_update' AND COALESCE(a->>'status','pending') = 'in_progress')
                 OR (COALESCE((a->>'must_do')::boolean,false) AND a->>'svc' <> 'readiness_check'
                     AND COALESCE(a->>'status','pending') IN ('pending','in_progress'))))
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn2 WHERE vn2.vehicle_id = v.id
             AND vn2.status IN ('open','in_progress') AND vn2.urgency = 'overnight_hold'
             AND vn2.dispatch_due_at IS NOT NULL AND vn2.dispatch_due_at > v_clock)
       AND NOT EXISTS (SELECT 1 FROM ottoq_visit_needs vn3, jsonb_array_elements(vn3.atoms) a3
             WHERE vn3.vehicle_id = v.id AND vn3.status IN ('open','in_progress')
               AND COALESCE((a3->>'requires_tech_greenlight')::boolean,false)
               AND NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals ap
                     WHERE ap.vehicle_id = v.id AND ap.approval_type = 'tech_greenlight'
                       AND ap.status = 'approved' AND ap.created_at >= vn3.created_at))
     ORDER BY v.current_soc DESC, v.id LIMIT GREATEST(v_deploy_budget,0)
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('redeployment','vehicle',v_req.vehicle_id,v_depot,v_clock);
    -- A1: cuOpt/Nemotron may propose the redeploy; heuristic is the safe fallback.
    v_proposal := COALESCE(
      ottoq_l2_external_proposal(p_sim_run_id, 'redeployment', 'vehicle', v_req.vehicle_id),
      ottoq_l2_propose_deploy(v_req.vehicle_id, v_depot, v_ctx));
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN v_deferred:=v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'redeployment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      CONTINUE; END IF;
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('redeployment','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_deploy(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1;
      -- BRAIN/TWIN SEPARATION: OTTO-Q does NOT mutate vehicle state. It emits the
      -- command below; ottoq_sim_dispatch_vehicle (twin) performs the transition
      -- atomically with the dispatch record. Writing 'en_route_to_deployment'
      -- here created a limbo the rate-limited twin could not drain (task #169).
      PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'dispatch', jsonb_build_object('soc', v_req.current_soc), v_clock);
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,deploy_readiness,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'redeployment','redeployment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,CASE WHEN v_outcome='enacted' THEN 'ready' ELSE 'held' END,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- P0 (2026-08-03): A REOPENED NEED IS A FIRST-CLASS DEMAND.
  -- ottoq.ottoq_readmit_resumed_visits was unreachable: its emergency_staged /
  -- retrieved_staged pair is produced ONLY by tow retrieval, whose dwell gate compares a
  -- REAL-clock last_state_change (clobbered by the BEFORE UPDATE trigger) against the SIM
  -- clock and is therefore never true. This stage is keyed on the NEED instead, so a
  -- cut-short charge competes for a plug in the SAME tick, through the SAME intake
  -- cursors below, as a fresh arrival. Self-silencing; can never abort the tick.
  PERFORM ottoq.ottoq_readmit_reopened_needs(p_sim_run_id, v_depot, v_clock);

  -- (3) STALL ASSIGNMENT
  -- P2 RIGHT OF FIRST REFUSAL (2026-08-02). Advance the cuOpt deferral
  -- ledger EXACTLY ONCE per decide tick, before the candidate cursor is opened.
  -- roll() step 1 releases every vehicle that a PREVIOUS tick held, so a hold can
  -- never span two consecutive decide ticks; step 2 then consumes this tick's
  -- freshly armed rows. roll() swallows its own errors: if the ledger is broken
  -- the engine simply behaves exactly as it did before this change.
  PERFORM public.ottoq_cuopt_defer_roll(p_sim_run_id, v_tick);
  v_charge_cap_kw := ottoq_active_charge_cap_kw(p_sim_run_id, v_depot, v_clock);
  IF v_charge_cap_kw IS NOT NULL THEN
    SELECT COALESCE(SUM(LEAST(COALESCE(st.connector_max_kw,50), COALESCE(vv.inlet_max_kw,250)) * CASE WHEN COALESCE(st.connector_max_kw,50)<=50 THEN 1.0 WHEN COALESCE(vv.current_soc,50)<55 THEN 0.85 WHEN COALESCE(vv.current_soc,50)<75 THEN 0.55 ELSE 0.30 END),0) INTO v_ev_committed_kw
      FROM vehicles vv JOIN stalls st ON st.id = vv.current_stall_id
     WHERE vv.home_depot_id = v_depot AND vv.current_state IN ('charging_dcfc','charging_l2');
  END IF;

  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       -- P2 RIGHT OF FIRST REFUSAL (2026-08-02). Hold this vehicle out of the local
       -- greedy path for EXACTLY ONE decide tick while a cuOpt solve is in flight,
       -- so the optimizer's answer is not pre-empted by the stall it was solving for.
       -- ottoq_cuopt_defer_hold is READ-ONLY and goes FALSE the moment a usable
       -- proposal exists for this vehicle (right of FIRST REFUSAL, not veto) -- the
       -- vehicle then enters the cursor normally and the proposal is ENACTED here.
       -- It also goes FALSE unconditionally on the next decide tick. No vehicle can
       -- starve: see public.ottoq_cuopt_defer_roll / _arm.
       AND NOT public.ottoq_cuopt_defer_hold(p_sim_run_id, v.id, v_tick)
       AND (v.current_state = 'arrived_at_gate'
            OR (v.current_state = 'staged_awaiting_service' AND EXISTS (
                 SELECT 1 FROM stalls s2
                   JOIN ottoq_ocpp_chargers c2 ON c2.charger_id = s2.ocpp_charger_id
                  WHERE s2.depot_id = v_depot
                    AND s2.stall_type::text IN ('dcfc','l2')
                    AND s2.current_vehicle_id IS NULL
                    AND c2.station_state = 'Available'
                    AND (s2.reserved_by IS NULL OR s2.reserved_by = v.id
                         OR s2.reservation_expires_at <= v_clock))))
       AND v.current_soc < COALESCE((SELECT vn.target_soc FROM ottoq_visit_needs vn
              WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
              ORDER BY vn.created_at DESC LIMIT 1), 85)
     ORDER BY (SELECT vn.urgency = 'immediate_dispatch' FROM ottoq_visit_needs vn
                 WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                 ORDER BY vn.created_at DESC LIMIT 1) DESC NULLS LAST,
              v.current_soc ASC, v.id
     -- charging_staff gate: general techs plug in / unplug and do the interior
     -- clean at the stall, so STAFF (not stalls) cap how many cars can be on
     -- charge at once. Neutral staffing (cap >= the 45 physical charge stalls)
     -- leaves the cursor unbounded, so this is a no-op until the knob moves.
     LIMIT (CASE
              WHEN ottoq_sim_lane_capacity(p_sim_run_id, 'charging_staff', 45) >= 45
                THEN 2147483647
              ELSE GREATEST(0,
                     ottoq_sim_lane_capacity(p_sim_run_id, 'charging_staff', 45)
                     - (SELECT count(*) FROM vehicles vc
                         WHERE vc.home_depot_id = v_depot
                           AND vc.current_state IN ('charging_dcfc','charging_l2')))
            END)
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('stall_assignment','vehicle',v_req.vehicle_id,v_depot,v_clock);
    v_proposal := ottoq_honour_reservation_proposal(p_sim_run_id, v_req.vehicle_id, v_depot, v_ctx);
    v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN v_deferred:=v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'stall_assignment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      IF (SELECT current_stall_id FROM vehicles WHERE id = v_req.vehicle_id) IS NULL THEN
        -- DOCTRINE (Chase 2026-07-28): never a gate queue; temp vs perimeter is chosen by
          -- PURPOSE and duration, not by whichever staging stall sorts first.
          DECLARE v_disp jsonb; v_hold jsonb;
          BEGIN
            v_disp := ottoq_arrival_disposition(p_sim_run_id, v_depot, v_req.vehicle_id, v_clock);
            IF (v_disp->>'action') IN ('perimeter_hold','temp_stage_await_resource','temp_stage_tech_hold','quarantine') THEN
              v_hold := ottoq_book_hold_stall(
                          p_sim_run_id, v_depot, v_req.vehicle_id,
                          COALESCE((v_disp->>'stage_from')::timestamptz, v_clock),
                          COALESCE((v_disp->>'stage_until')::timestamptz, v_clock + interval '30 minutes'));
              IF COALESCE((v_hold->>'booked')::boolean, false) THEN
                SELECT b.stall_id INTO v_stage_stall
                  FROM ottoq_stall_bookings b WHERE b.booking_id = (v_hold->>'booking_id')::uuid;
                IF v_stage_stall IS NOT NULL
                   AND ottoq_reserve_stall(v_stage_stall, v_req.vehicle_id, v_clock, 900) THEN
                  UPDATE vehicles SET current_stall_id = v_stage_stall,
                         current_state = 'staged_awaiting_service'::vehicle_state,
                         last_state_change = v_clock
                   WHERE id = v_req.vehicle_id;
                  UPDATE stalls SET current_vehicle_id = v_req.vehicle_id, status = 'occupied'
                   WHERE id = v_stage_stall;
                END IF;
              END IF;
            END IF;
          END;
      END IF;
      CONTINUE; END IF;
    v_ctx := v_ctx || jsonb_build_object('stall_id', v_proposal->>'stall_id', 'requested_kw', v_proposal->>'requested_kw');
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('stall_assignment','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_stall(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal;
      IF ottoq_reserve_stall((v_action->>'stall_id')::uuid, v_req.vehicle_id, v_clock, 600) THEN
        UPDATE stalls SET current_vehicle_id = NULL, reserved_by = NULL, reservation_expires_at = NULL, status = 'available'
         WHERE current_vehicle_id = v_req.vehicle_id AND id <> (v_action->>'stall_id')::uuid;
        UPDATE vehicles SET current_state=(CASE WHEN v_action->>'stall_type'='dcfc' THEN 'charging_dcfc' ELSE 'charging_l2' END)::vehicle_state, current_stall_id=(v_action->>'stall_id')::uuid, last_state_change=v_clock WHERE id=v_req.vehicle_id;
        UPDATE stalls SET current_vehicle_id=v_req.vehicle_id, status='occupied' WHERE id=(v_action->>'stall_id')::uuid;
        PERFORM ottoq_claim_tick_kw(p_sim_run_id, v_tick, v_depot, (v_action->>'requested_kw')::numeric, v_req.vehicle_id);
        PERFORM ottoq_start_concurrent_atoms(v_req.vehicle_id, v_clock);
        PERFORM ottoq_plan_visit_itinerary(p_sim_run_id, v_req.vehicle_id, v_clock);

        -- FORWARD AVAILABILITY / P0: ENACTMENT AND CALENDAR ARE ONE ACT.
        -- Every stall assignment that reaches this line - cuopt, deterministic, greedy and
        -- reservation_honoured all return through v_action above - is now recorded on the
        -- forward calendar in THIS transaction, against the EXACT stall enacted.
        --
        -- Previously the booking sat inside "IF v_charge_leg.leg_id IS NOT NULL", and the planner
        -- emits a charge leg only when the visit-need manifest carries an svc='charge' atom. When
        -- it does not, that branch never ran: 51 enacted charge assignments, 0 charge bookings,
        -- 0% end-to-end coverage. The booking no longer depends on a planned leg existing.
        --
        -- The leg is still PREFERRED when present, for two reasons: it carries the real timed
        -- window, and stamping to_stall_id is the existing sentinel that removes the leg from both
        -- booking cursors (ottoq_book_workflow / ottoq_find_and_book_stall), suppressing the second
        -- independent stall search. The calendar still RECORDS the decision, it never re-derives it.
        SELECT l.leg_id, l.leg_type, l.planned_start_sim, l.planned_end_sim
          INTO v_charge_leg
          FROM public.ottoq_itinerary_legs l
         WHERE l.sim_run_id  = p_sim_run_id
           AND l.vehicle_id  = v_req.vehicle_id
           AND l.status      = 'planned'
           AND l.to_stall_id IS NULL
           AND l.leg_type IN ('charge_dcfc','charge_l2')
           AND l.planned_start_sim IS NOT NULL
           AND l.planned_end_sim   IS NOT NULL
           AND l.planned_end_sim   > v_clock
         ORDER BY l.seq
         LIMIT 1;

        -- p_purpose is left NULL so the purpose is derived from the stall ACTUALLY taken, not from
        -- what the planner intended. The helper supersedes phantom overlaps, is idempotent on
        -- (run, stall, vehicle, purpose, window), and can never abort this tick.
        v_bkg := ottoq.ottoq_record_enacted_booking(
                   p_sim_run_id, (v_action->>'stall_id')::uuid, v_req.vehicle_id, v_clock,
                   v_charge_leg.leg_id, v_charge_leg.planned_start_sim, v_charge_leg.planned_end_sim,
                   NULL, COALESCE(v_action->>'source','deterministic'));

        IF v_bkg IS NOT NULL AND v_charge_leg.leg_id IS NOT NULL THEN
          UPDATE public.ottoq_itinerary_legs
             SET to_stall_id = (v_action->>'stall_id')::uuid
           WHERE leg_id = v_charge_leg.leg_id;
        END IF;

        v_outcome:='enacted'; v_enacted:=v_enacted+1;
        v_ev_committed_kw := v_ev_committed_kw + COALESCE((v_action->>'requested_kw')::numeric,0);
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'begin_charge', jsonb_build_object('stall_id', v_action->>'stall_id', 'stall_type', v_action->>'stall_type', 'requested_kw', v_action->>'requested_kw'), v_clock);
      ELSE v_action:=ottoq_l1_safe_default_stall(v_req.vehicle_id,v_ctx); v_outcome:='deferred_stale_entity'; v_deferred:=v_deferred+1; END IF;
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'stall_assignment','stall_assignment','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- (3b) GATE INTAKE — NO-CHARGE ARRIVALS
  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v
     WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
       AND v.current_state = 'arrived_at_gate'
       AND v.current_stall_id IS NULL
       AND EXISTS (SELECT 1 FROM ottoq_visit_needs vn
                    WHERE vn.vehicle_id = v.id AND vn.status IN ('open','in_progress')
                      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(vn.atoms) a
                                       WHERE a->>'svc' = 'charge' AND COALESCE(a->>'status','pending') <> 'done'))
  LOOP
    SELECT s.id INTO v_stage_stall FROM stalls s
     WHERE s.depot_id = v_depot AND s.stall_type = 'staging'
       AND s.zone IS DISTINCT FROM 'arrival_inspection'
       AND s.current_vehicle_id IS NULL
       AND (s.reserved_by IS NULL OR s.reservation_expires_at <= v_clock)
     ORDER BY (s.staging_role = 'temp') DESC, s.distance_from_entrance NULLS LAST, s.id LIMIT 1;
    IF v_stage_stall IS NOT NULL AND ottoq_reserve_stall(v_stage_stall, v_req.vehicle_id, v_clock, 900) THEN
      UPDATE vehicles SET current_stall_id = v_stage_stall,
             current_state = 'staged_awaiting_service'::vehicle_state,
             last_state_change = v_clock,
             config = jsonb_set(COALESCE(config,'{}'::jsonb), '{svc_step}',
               to_jsonb(CASE WHEN EXISTS (SELECT 1 FROM ottoq_visit_needs vn2, jsonb_array_elements(vn2.atoms) a2
                                           WHERE vn2.vehicle_id = v_req.vehicle_id AND vn2.status IN ('open','in_progress')
                                             AND a2->>'svc' IN ('mechanical_pm','fault_repair','sensor_calibration')
                                             AND COALESCE((a2->>'must_do')::boolean,false)
                                             AND COALESCE(a2->>'status','pending') = 'pending')
                            THEN 'need_service' ELSE 'need_deploy' END))
       WHERE id = v_req.vehicle_id;
      UPDATE stalls SET current_vehicle_id = v_req.vehicle_id, status = 'occupied' WHERE id = v_stage_stall;
      PERFORM ottoq_start_concurrent_atoms(v_req.vehicle_id, v_clock);
      v_built := v_built + 1; v_enacted := v_enacted + 1;
      PERFORM ottoq_plan_visit_itinerary(p_sim_run_id, v_req.vehicle_id, v_clock);
      -- CALENDAR (staging). The single biggest gap: the whole service-only intake path
      -- enacted a stall and wrote NOTHING to the forward-occupancy calendar.
      -- We RECORD the stall the intake ALREADY picked above. We must NOT call
      -- ottoq_book_hold_stall here: it runs its OWN independent search, which is exactly
      -- the decision/calendar divergence fixed on 2026-08-01.
      SELECT l.leg_id INTO v_stage_leg_id
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
         AND l.status = 'planned' AND l.leg_type = 'stage' AND l.to_stall_id IS NULL
         AND l.planned_end_sim > v_clock
       ORDER BY l.seq LIMIT 1;
      -- The car holds this staging stall until its itinerary is done: nothing in (4) or (5)
      -- clears stalls.current_vehicle_id, only (3)'s charge branch and redeploy do.
      -- Hard-capped so a runaway itinerary can never reserve a space indefinitely.
      SELECT max(l.planned_end_sim) INTO v_stage_until
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
         AND l.status = 'planned' AND l.planned_end_sim > v_clock;
      v_stage_until := GREATEST(
        LEAST(
          COALESCE(v_stage_until,
                   v_clock + make_interval(mins => ottoq_policy_get(p_sim_run_id,'staging_hold_default_min',30)::int)),
          v_clock + make_interval(mins => ottoq_policy_get(p_sim_run_id,'staging_hold_max_min',480)::int)),
        v_clock + interval '1 minute');
      v_bkg := ottoq.ottoq_book_stall(p_sim_run_id, v_stage_stall, v_req.vehicle_id,
                 'staging', v_clock, v_stage_until, NULL, v_stage_leg_id,
                 ottoq.ottoq_booking_authorship('gate_intake_staging'));
      IF v_bkg IS NOT NULL THEN
        UPDATE public.ottoq_stall_bookings SET source = COALESCE(source, 'gate_intake_staging')
         WHERE booking_id = v_bkg;
      END IF;
      IF v_bkg IS NOT NULL AND v_stage_leg_id IS NOT NULL THEN
        -- same sentinel the charge path uses: a stamped to_stall_id removes the leg from
        -- ottoq_book_workflow's cursor, so no second independent search can re-derive it.
        UPDATE public.ottoq_itinerary_legs SET to_stall_id = v_stage_stall
         WHERE leg_id = v_stage_leg_id;
      END IF;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'stall_assignment','gate_intake_no_charge','vehicle',v_req.vehicle_id,
              jsonb_build_object('stall_id',v_stage_stall,'staging_pick','temp_first'),
              jsonb_build_object('verb','gate_intake','stall_id',v_stage_stall),
              jsonb_build_object('verb','gate_intake','stall_id',v_stage_stall,'booking_id',v_bkg),
              'enacted',0,0);
      PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'proceed_to_stall', jsonb_build_object('stall_id', v_stage_stall, 'reason', 'gate_intake'), v_clock);
    END IF;
  END LOOP;

  -- (4) CHARGE DISPOSITION
  FOR v_req IN
    SELECT v.id AS vehicle_id, v.current_soc, v.fleet_operator_id
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       AND v.current_state='charge_complete_holding'
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id LIMIT 40
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('task_start','vehicle',v_req.vehicle_id,v_depot,v_clock) || jsonb_build_object('requires_charging','false','service','wash');
    v_proposal := ottoq_l2_propose_charge_disposition(v_req.vehicle_id, v_depot, v_ctx || jsonb_build_object('sim_run_id', p_sim_run_id));
    v_prop_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    IF (v_proposal->>'abstain')::boolean THEN v_deferred:=v_deferred+1;
      INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)
      VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','vehicle',v_req.vehicle_id,v_ctx,v_proposal,'{}'::jsonb,'noop_no_candidate',v_prop_ms,v_prop_ms);
      CONTINUE; END IF;
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('task_start','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_charge_disposition(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1;
      IF COALESCE(v_action->>'verb','admit_wash') = 'skip_wash' THEN
        -- SERVICE-NEED ROUTING (2026-08-01): no wash/detail work outstanding, so do
        -- NOT burn one of the depot's 3 wash bays on a clean car. Advance the vehicle
        -- inside the SAME atomic visit to what it does still need. Nothing is booked
        -- and no stall is claimed, so the calendar cannot over-report.
        UPDATE vehicles SET current_state='staged_awaiting_service', last_state_change=v_clock,
               config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',
                                to_jsonb(COALESCE(v_action->>'next_step','need_deploy'))) WHERE id=v_req.vehicle_id;
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'stage',
                jsonb_build_object('reason','no_wash_need','next_step',COALESCE(v_action->>'next_step','need_deploy')), v_clock);
        v_action := COALESCE(v_action,'{}'::jsonb) || jsonb_build_object('bay_booked', false, 'bay_stall_type', 'none');
      ELSE
      -- BAY ENTRY MOVED BELOW THE HELPER (Phase 3). It used to happen HERE, before any
      -- bay had been claimed or booked: if ottoq_enact_space_assignment then found no free
      -- bay, the vehicle was already 'in_wash_bay' with no stall and no calendar row --
      -- a bay physically occupied while the calendar showed it free. The state flip and
      -- the enter_wash command are now gated on the booking, exactly as (4b) already was.
      -- CALENDAR (wash/detail bay). CHOOSE + CLAIM + RECORD, one act.
      -- ottoq_enact_space_assignment picks the bay, reserves it, writes
      -- vehicles.current_stall_id and books the window in THIS transaction. The bay entry
      -- below is GATED on that result: no free bay means no entry, and the miss is recorded
      -- on the decision row as verb 'hold_no_bay'. The calendar can under-report a REFUSAL
      -- but it can no longer report a bay as free while a vehicle is standing in it.
      SELECT l.leg_id, l.leg_type, (l.planned_end_sim - l.planned_start_sim)
        INTO v_bay_leg_id, v_bay_leg_type, v_bay_dur
        FROM public.ottoq_itinerary_legs l
       WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
         AND l.status = 'planned' AND l.to_stall_id IS NULL
         AND l.leg_type IN ('wash','detail')
       ORDER BY l.seq LIMIT 1;
      IF v_bay_leg_id IS NULL THEN
        -- FALLBACK -- THIS IS WHY leg_id WAS NULL ON EVERY ENACTED BOOKING (11 of 11 on
        -- run 4332b898, against 94 of 94 on the planner path). The forward planner
        -- ottoq_book_workflow books the leg AHEAD of time and stamps to_stall_id, so the
        -- cursor above (to_stall_id IS NULL) found nothing and enactment booked a SECOND
        -- row on a possibly different stall with no leg. Adopt the planned leg instead:
        -- ottoq_enact_space_assignment honours its reservation and
        -- ottoq_record_enacted_booking adopts that row rather than duplicating it.
        SELECT l.leg_id, l.leg_type, (l.planned_end_sim - l.planned_start_sim)
          INTO v_bay_leg_id, v_bay_leg_type, v_bay_dur
          FROM public.ottoq_itinerary_legs l
         WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
           AND l.status IN ('planned','active')
           AND l.leg_type IN ('wash','detail')
         ORDER BY (l.status = 'active') DESC, l.seq LIMIT 1;
      END IF;
      -- TOTAL allow-list leg_type -> purpose. Only the two wash-lane leg types can reach
      -- here; nothing is ever passed through to the CLOSED 9-label purpose CHECK.
      -- (no detail_bay stalls are seeded - detail shares the wash lane, as in ottoq_book_workflow)
      v_bay_purpose := CASE WHEN COALESCE(v_action->>'bay_kind', v_bay_leg_type) = 'detail' THEN 'detail' ELSE 'wash' END;
      v_bay_until := v_clock + GREATEST(
        COALESCE(v_bay_dur,
                 make_interval(mins => ottoq_policy_get(p_sim_run_id,'wash_bay_default_min',25)::int)),
        interval '1 minute');
      v_space := ottoq.ottoq_enact_space_assignment(p_sim_run_id, v_depot, v_req.vehicle_id,
                     'wash_bay', v_bay_purpose, v_clock, v_bay_until,
                     v_bay_leg_id, 'charge_disposition');
      v_bay_bkg := NULLIF(v_space->>'booking_id','')::uuid;
      IF v_bay_bkg IS NOT NULL AND v_bay_leg_id IS NOT NULL THEN
        UPDATE public.ottoq_itinerary_legs
           SET to_stall_id = (SELECT b.stall_id FROM public.ottoq_stall_bookings b
                               WHERE b.booking_id = v_bay_bkg)
         WHERE leg_id = v_bay_leg_id;
      END IF;
      IF COALESCE((v_space->>'assigned')::boolean, false) THEN
        -- ENTRY AND CALENDAR ARE ONE ACT. A real wash bay has been claimed AND booked in
        -- this transaction, so the command names the stall, the booking and the leg.
        UPDATE vehicles SET current_state='in_wash_bay', last_state_change=v_clock,
               config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',to_jsonb('washing'::text)) WHERE id=v_req.vehicle_id;
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'enter_wash',
                jsonb_build_object('stall_id',   v_space->>'stall_id',
                                   'booking_id', v_space->>'booking_id',
                                   'leg_id',     v_bay_leg_id,
                                   'purpose',    v_bay_purpose), v_clock);
        v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                    || jsonb_build_object('bay_booked', v_bay_bkg IS NOT NULL,
                                          'bay_purpose', v_bay_purpose,
                                          'bay_stall_type', 'wash_bay',
                                          'stall_id', v_space->>'stall_id',
                                          'booking_id', v_space->>'booking_id',
                                          'leg_id', v_bay_leg_id);
      ELSE
        -- NO BAY -> DO NOT ENTER ONE. The vehicle is left exactly where this proposer's own
        -- 'wash_lane_full_hold' abstain leaves it (charge_complete_holding) and is retried
        -- next tick. No state write, no command, no booking. Throughput cannot regress:
        -- this branch is only reachable when there is genuinely no bookable wash bay, and
        -- release step (b) hard-frees stale bay stalls earlier in this same tick.
        v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                    || jsonb_build_object('verb','hold_no_bay', 'bay_booked', false,
                                          'bay_purpose', v_bay_purpose,
                                          'bay_stall_type', 'wash_bay');
        v_outcome := 'noop_no_candidate'; v_enacted := v_enacted - 1; v_deferred := v_deferred + 1;
      END IF;
      END IF;
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','task_start','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- ══════════════════════════════════════════════════════════════════════════════════
  -- (4b) NEEDS-CARD SPACE ROUTING  —  P1, 2026-08-01
  --
  -- WHAT THIS CLOSES. Before this block the engine literally could not decide "send this
  -- vehicle to the wash bay". The ONLY door into in_wash_bay/in_detail_bay was section (4),
  -- whose cursor is current_state='charge_complete_holding'. Measured on run c177c1ca over
  -- 573 ticks: ZERO admit_wash decisions, 5 skip_wash — while 371 vehicles were promoted
  -- straight from staged_awaiting_service to staged_for_departure by (5), a state from which
  -- no wash/detail door existed at all. That is the whole reason 51 of 51 (and 209 of 209
  -- before) enacted assignments were charging while 3 wash bays sat 100 pct idle.
  --
  -- WHAT IT DOES. For each vehicle HOLDING in staging, read public.ottoq_vehicle_needs_card,
  -- take the highest-priority must-do need that requires a SPACE, and place the vehicle into
  -- the space that need's lane requires — through ottoq_enact_space_assignment, so choosing
  -- the stall and writing the forward-calendar booking are ONE act against the SAME stall
  -- (the P0 rule, now extended past chargers).
  --
  -- SPACE MAP is read from service_cadence_policy.lane, never hardcoded, and is TOTAL:
  --   lane 'wash_bay'    (exterior_wash)                        -> wash_bay,    purpose 'wash'
  --   lane 'detail'      (interior_deep_clean)                  -> wash_bay,    purpose 'detail'
  --        ^ zero detail_bay stalls are seeded; detail shares the wash lane, exactly as
  --          ottoq_book_workflow and twin STEP 2 already do.
  --   lane 'service_bay' (fault_repair, sensor_calibration,
  --                       mechanical_pm, cosmetic_repair)       -> service_bay, purpose 'service'
  --   lane 'anchor'      (charge)      -> NOT HANDLED HERE, see CHARGE FIREWALL.
  --   lane 'cabin'/'exterior'/'digital'/'gate' -> NO SPACE AT ALL. That work overlaps
  --        charging and is already started at the stall by ottoq_start_concurrent_atoms;
  --        spending one of 3 wash or 2 service bays on it would be a straight loss.
  --   any lane the catalogue gains later -> no space, silently skipped. TOTAL FUNCTION
  --        (the 2026-08-01 leg_type lesson): an unknown lane can never reach a CHECK.
  --
  -- ══ ORDERING / PRIORITY RULE ══
  --   WITHIN a vehicle : lowest service_cadence_policy.sequence_order wins, so the visit is
  --     worked in the catalogue's own order (fault_repair 30 -> wash 40 -> detail 45 ->
  --     calibration 55 -> pm 60 -> cosmetic 70). One space at a time; the vehicle comes back
  --     through this block on a later tick for the next item, inside ONE atomic visit.
  --   ACROSS vehicles  : 1. urgency rank DESC (critical > overdue > due > due_soon > ok)
  --                      2. fits_window DESC  — do not burn a scarce bay on work that
  --                         provably cannot finish before the vehicle is due out
  --                      3. minutes_to_deploy ASC — earliest deadline first (EDF)
  --                      4. open_must_do_min ASC — shortest job first, so a scarce bay
  --                         clears more vehicles per hour
  --                      5. vehicle_id — deterministic, seed-stable tiebreak
  --
  -- ══ CHARGE FIREWALL — five independent reasons this cannot regress charging ══
  --  1. Sections (1),(2),(3),(3b) are byte-for-byte unchanged by this migration, including
  --     Gate B in ottoq_honour_reservation_proposal and the cuOpt 'source' passthrough.
  --  2. This block only ever asks for 'wash_bay' or 'service_bay', and
  --     ottoq_enact_space_assignment REFUSES 'dcfc'/'l2' outright. No path built here can
  --     reserve, occupy or book a charger.
  --  3. Any vehicle whose card still lists 'charge' in must_do_now is SKIPPED and left to
  --     section (3). Charge is the anchor leg (sequence_order 10): energy first, then bays.
  --  4. It runs AFTER (3), so every charge decision this tick is already made and its stalls
  --     already reserved before one bay is considered.
  --  5. Separate staff pools: charging is capped by 'charging_staff', wash by
  --     LEAST(cleaning_staff, wash_supervisor), service by 'service_staff'. Bay work cannot
  --     consume a charging tech.
  --  NET EFFECT ON CHARGING IS POSITIVE: today a vehicle in a bay still holds the l2/dcfc
  --  stall it charged on, because nothing clears it. Occupying the bay moves
  --  vehicles.current_stall_id, which fires trg_sync_stall_occupancy and hands that charger
  --  straight back to section (3). Chargers are freed sooner, never later.
  --
  -- ══ ANTI-STARVATION ══ wash and service headroom are computed with the TWIN'S OWN
  -- capacity formulas, verbatim, so this block can never admit past the lane the twin itself
  -- would allow, and the two lanes are counted separately so neither can starve the other.
  --
  -- ══ IN-DEPOT REASSIGNMENT / ZONES ══ the cursor is restricted to current_state
  -- 'staged_awaiting_service', a HOLDING state. It structurally cannot pick up a vehicle that
  -- is charging, washing or being serviced, so it can never re-route work in progress and
  -- therefore never needs ottoq_indepot_reassignment_guard — this is forward progression to
  -- the next due leg of the same visit, which is exactly what (4) and (5) already do. Zone C
  -- (malfunction / congestion / flag) vehicles are skipped and left to the exception path
  -- that owns them. Zone is NOT required to be 'A' here: ottoq_approach_zone fails closed to
  -- 'B' for any vehicle with no approach-band row, which is every in-depot vehicle, so an
  -- A-only test would silently disable the whole block.
  --
  -- ══ COST ══ ottoq_vehicle_needs_card is a 116-row / ~250 ms view. It is evaluated ONCE per
  -- tick and only after two cheap pre-checks find both a waiting vehicle and lane headroom.
  -- ══════════════════════════════════════════════════════════════════════════════════
  SELECT count(*) FILTER (WHERE s.stall_type = 'wash_bay'::stall_type),
         count(*) FILTER (WHERE s.stall_type = 'service_bay'::stall_type)
    INTO v_wash_phys, v_svc_phys
    FROM stalls s
   WHERE s.depot_id = v_depot AND s.status NOT IN ('maintenance','closed');

  IF COALESCE(v_wash_phys,0) + COALESCE(v_svc_phys,0) > 0
     AND EXISTS (SELECT 1 FROM vehicles v
                  WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
                    AND v.current_state = 'staged_awaiting_service') THEN

    v_wash_open := GREATEST(0,
      LEAST(ottoq_sim_lane_capacity(p_sim_run_id,'cleaning_staff', GREATEST(COALESCE(v_wash_phys,0),1)),
            ottoq_depot_staffing_count(v_depot,'wash_supervisor'))
      - (SELECT count(*) FROM vehicles
          WHERE home_depot_id = v_depot AND current_state IN ('in_wash_bay','in_detail_bay')));
    v_svc_open := GREATEST(0,
      ottoq_sim_lane_capacity(p_sim_run_id,'service_staff', GREATEST(COALESCE(v_svc_phys,0),1))
      - (SELECT count(*) FROM vehicles
          WHERE home_depot_id = v_depot AND current_state = 'in_service_bay'));

    -- ══════════════ 0003 ANTI-STARVATION BUDGET ══════════════
    -- Resumed bay work outranks fresh work at equal urgency (see the cursor below), so
    -- without a ceiling a queue of interrupted vehicles could take an entire lane and
    -- fresh arrivals would wait. This caps how many of THIS TICK'S admissions per lane
    -- may go to resumption -- but ONLY while fresh candidates are actually competing for
    -- that same lane (fresh_waiting_lane > 0 in the loop). With no fresh demand the cap
    -- does not bite and idle bays are never held empty on principle.
    --   GREATEST(1, ...) is load-bearing: the defect being fixed is bay recovery of ZERO,
    --   so resumption must never be budgeted down to nothing.
    --   share 0.5 => at most half a lane's free bays (rounded up) per tick. With the
    --   depot's 3 wash / 2 service bays that is 1-2 per lane per tick, and the loop runs
    --   every tick, so five interrupted vehicles clear in a handful of ticks.
    v_res_share := LEAST(GREATEST(COALESCE(ottoq_policy_get(p_sim_run_id,'bay_resume_share_max',0.5),0.5), 0), 1);
    v_wash_res_cap := GREATEST(1, CEIL(COALESCE(v_wash_open,0) * v_res_share))::int;
    v_svc_res_cap  := GREATEST(1, CEIL(COALESCE(v_svc_open,0)  * v_res_share))::int;

    IF COALESCE(v_wash_open,0) + COALESCE(v_svc_open,0) > 0 THEN
      FOR v_need IN
        WITH card AS (
          SELECT c.vehicle_id, c.overall_urgency, c.must_do_now, c.minutes_to_deploy,
                 c.fits_window, c.open_must_do_min,
                 -- 0003: the ledger detector and the energy grade, read straight off the card.
                 c.owed_bay_svcs, c.rebook_owed, c.energy_urgency
            FROM public.ottoq_vehicle_needs_card c
           WHERE c.depot_id = v_depot
             -- CHARGE FIRST (full-service visit doctrine, anchor leg): if energy is still a
             -- must-do, this vehicle belongs to section (3), not to a bay.
             --
             -- ══════════════ 0003: ONE NARROW EXCEPTION, AND WHY ══════════════
             -- MEASURED (run 093c20f4, vehicle 0ea2ccfe): its end-of-run card read
             -- must_do_now = {charge, interior_deep_clean, software_update}. The detail bay
             -- it had been pulled out of was still owed AND still must-do, and this single
             -- predicate excluded it anyway -- for the whole rest of the run.
             -- The exception is deliberately the narrowest one that fixes that case:
             --   (a) the vehicle OWES interrupted bay work (ledger, not cadence);
             --   (b) energy is not 'critical' -- a vehicle that will miss its SLA on charge
             --       is still section (3)'s, always;
             --   (c) there is NO free, available, unreserved charger at this depot RIGHT NOW.
             -- (c) is the load-bearing one. Section (3) has already run this tick with the
             -- very same availability predicate; if a plug existed this vehicle would be on
             -- it. So the bay costs the depot no charging whatsoever -- it is time the car
             -- would otherwise spend parked in staging waiting for a plug that does not exist.
             -- The moment a charger frees, the exception stops applying to new vehicles, and
             -- a car already in a bay is finishing an atomic leg, not being held off energy.
             AND ( NOT ('charge' = ANY (COALESCE(c.must_do_now, '{}'::text[])))
                   OR ( COALESCE(c.rebook_owed, false)
                        AND COALESCE(c.energy_urgency, 'ok') <> 'critical'
                        AND NOT EXISTS (
                              SELECT 1 FROM stalls s3
                                JOIN ottoq_ocpp_chargers c3 ON c3.charger_id = s3.ocpp_charger_id
                               WHERE s3.depot_id = v_depot
                                 AND s3.stall_type::text IN ('dcfc','l2')
                                 AND s3.current_vehicle_id IS NULL
                                 AND c3.station_state = 'Available'
                                 AND (s3.reserved_by IS NULL OR s3.reserved_by = c.vehicle_id
                                      OR s3.reservation_expires_at <= v_clock)) ) )
        ), spaced AS (
          SELECT k.vehicle_id, k.overall_urgency, k.minutes_to_deploy, k.fits_window,
                 k.open_must_do_min, x.svc, p.lane, p.sequence_order,
                 -- 0003: is THIS pick a resumption of work the depot already took away?
                 COALESCE(x.svc = ANY (COALESCE(k.owed_bay_svcs, '{}'::text[])), false) AS is_resume,
                 -- 0003: EFFECTIVE urgency. A job that was booked, started and then
                 -- interrupted was must-do when it was booked, so it is at least 'due' --
                 -- even if the twin has since reset its cadence clock by crediting a
                 -- 0.46-minute service as finished (run 093c20f4, vehicle 5cee8fb3). Floor
                 -- it at 'due' (rank 3) and no higher: fresh 'overdue'/'critical' work still
                 -- wins outright, so this can never starve a genuinely urgent new arrival.
                 -- overall_urgency itself is NOT touched -- too many readers depend on it.
                 GREATEST(public.ottoq_urgency_rank(k.overall_urgency),
                          CASE WHEN x.svc = ANY (COALESCE(k.owed_bay_svcs, '{}'::text[]))
                               THEN public.ottoq_urgency_rank('due') ELSE 0 END) AS eff_rank,
                 CASE p.lane WHEN 'wash_bay'    THEN 'wash_bay'
                             WHEN 'detail'      THEN 'wash_bay'
                             WHEN 'service_bay' THEN 'service_bay' END AS stall_type,
                 CASE p.lane WHEN 'wash_bay'    THEN 'wash'
                             WHEN 'detail'      THEN 'detail'
                             WHEN 'service_bay' THEN 'service' END AS purpose,
                 CASE p.lane WHEN 'wash_bay'    THEN 'in_wash_bay'
                             WHEN 'detail'      THEN 'in_detail_bay'
                             WHEN 'service_bay' THEN 'in_service_bay' END AS new_state,
                 CASE p.lane WHEN 'wash_bay'    THEN 'wash_time'
                             WHEN 'detail'      THEN 'detail_time'
                             WHEN 'service_bay' THEN 'maintenance_time' END AS time_key,
                 CASE p.lane WHEN 'wash_bay'    THEN 9
                             WHEN 'detail'      THEN 25
                             ELSE 40 END AS base_min
            FROM card k
            CROSS JOIN LATERAL unnest(k.must_do_now) AS x(svc)
            JOIN public.service_cadence_policy p ON p.svc = x.svc AND p.is_active
           WHERE p.lane IN ('wash_bay','detail','service_bay')
        ), pick AS (
          -- SEQUENCE inside the visit: the catalogue's own order -- except that 0003 puts
          -- UNFINISHED work first. If a vehicle both owes an interrupted job and has fresh
          -- cadence work due, finish what the depot already started. That is the atomic
          -- full-service visit read literally.
          SELECT DISTINCT ON (s.vehicle_id) s.*
            FROM spaced s
           ORDER BY s.vehicle_id, s.is_resume DESC, s.sequence_order, s.svc
        ), ranked AS (
          SELECT pk.vehicle_id, pk.svc, pk.lane, pk.stall_type, pk.purpose, pk.new_state,
                 pk.time_key, pk.base_min, pk.overall_urgency, pk.minutes_to_deploy,
                 pk.fits_window, pk.open_must_do_min, pk.sequence_order, pk.is_resume,
                 pk.eff_rank, v.fleet_operator_id
            FROM pick pk
            JOIN vehicles v ON v.id = pk.vehicle_id
           WHERE v.home_depot_id = v_depot AND v.category = 'autonomous'
             AND v.current_state = 'staged_awaiting_service'
             AND COALESCE(public.ottoq_approach_zone(pk.vehicle_id, p_sim_run_id),'B') <> 'C'
        )
        SELECT rk.*,
               -- 0003: how many FRESH candidates are competing for this same lane this tick.
               -- Window functions are evaluated over the whole qualifying set BEFORE the
               -- LIMIT, so this is the true competing demand, not just what fits in 20 rows.
               -- The resumption budget below only bites when this is > 0.
               count(*) FILTER (WHERE NOT rk.is_resume) OVER (PARTITION BY rk.stall_type)
                 AS fresh_waiting_lane
          FROM ranked rk
         ORDER BY rk.eff_rank DESC,
                  rk.is_resume DESC,
                  rk.fits_window DESC NULLS LAST,
                  rk.minutes_to_deploy ASC NULLS LAST,
                  rk.open_must_do_min ASC NULLS LAST,
                  rk.vehicle_id
         LIMIT 20
      LOOP
        IF v_need.stall_type = 'wash_bay'    AND COALESCE(v_wash_open,0) <= 0 THEN CONTINUE; END IF;
        IF v_need.stall_type = 'service_bay' AND COALESCE(v_svc_open,0)  <= 0 THEN CONTINUE; END IF;
        -- 0003 ANTI-STARVATION: hold resumption to its per-lane share of THIS tick's
        -- admissions, and only while fresh work is actually queued for the same lane.
        -- Skipping here is a pure CONTINUE: the vehicle keeps its place in the next tick's
        -- cursor with its 'due' floor intact, so nothing is dropped, only sequenced.
        IF COALESCE(v_need.is_resume,false) AND COALESCE(v_need.fresh_waiting_lane,0) > 0 THEN
          IF v_need.stall_type = 'wash_bay'    AND v_wash_res_used >= COALESCE(v_wash_res_cap,1) THEN CONTINUE; END IF;
          IF v_need.stall_type = 'service_bay' AND v_svc_res_used  >= COALESCE(v_svc_res_cap,1)  THEN CONTINUE; END IF;
        END IF;

        v_built := v_built + 1; v_t0 := clock_timestamp();
        v_over := false; v_safe := false; v_block_codes := '{}'; v_rule_rows := NULL;
        v_ctx := ottoq_build_decision_context('task_start','vehicle',v_need.vehicle_id,v_depot,v_clock)
                 || jsonb_build_object('need', v_need.svc, 'lane', v_need.lane,
                      'stall_type', v_need.stall_type, 'purpose', v_need.purpose,
                      'overall_urgency', v_need.overall_urgency,
                      'minutes_to_deploy', v_need.minutes_to_deploy,
                      'fits_window', v_need.fits_window,
                      'open_must_do_min', v_need.open_must_do_min,
                      'sequence_order', v_need.sequence_order,
                      -- 0003: make bay RECOVERY countable straight off the decision row.
                      'is_resume', COALESCE(v_need.is_resume,false),
                      'eff_urgency_rank', v_need.eff_rank,
                      'fresh_waiting_lane', v_need.fresh_waiting_lane,
                      'resume_cap_lane', CASE WHEN v_need.stall_type = 'wash_bay'
                                              THEN v_wash_res_cap ELSE v_svc_res_cap END,
                      'requires_charging','false','service', v_need.purpose);
        v_proposal := jsonb_build_object('abstain', false, 'verb','assign_stall',
                        'resolved_action_context','stall_assignment', 'source','needs_card',
                        'vehicle_id', v_need.vehicle_id, 'stall_type', v_need.stall_type,
                        'purpose', v_need.purpose, 'need', v_need.svc, 'requested_kw', 0,
                        -- 0003: recorded on the PROPOSAL, not on the booking. p_source of
                        -- ottoq.ottoq_enact_space_assignment is deliberately left at the
                        -- existing literal 'needs_card' -- inventing a new vocabulary value
                        -- for a downstream writer is exactly the 2026-08-01 leg_type trap.
                        'is_resume', COALESCE(v_need.is_resume,false));
        v_prop_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;

        v_t0 := clock_timestamp();
        SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
               jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
          INTO v_blocks, v_block_codes, v_rule_rows
          FROM ottoq_shield_probe('task_start','vehicle',v_need.vehicle_id,v_ctx,v_need.fleet_operator_id,v_depot);
        v_shield_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;

        v_t0 := clock_timestamp();
        IF COALESCE(v_blocks,0) > 0 THEN
          -- SHIELD BLOCKS => take NO space. The vehicle stays in staging and section (5)
          -- handles it exactly as today. Bays are ADDITIVE, so a refusal here can only ever
          -- return the engine to its pre-P1 behaviour - never worse.
          v_action := jsonb_build_object('verb','hold_no_space','reason','shield_block');
          v_safe := true; v_over := true; v_outcome := 'overridden_to_default'; v_overc := v_overc + 1;
        ELSE
          -- TIMING BELONGS TO THE TWIN. ottoq_sim_service_minutes is the exact function
          -- twin STEP 2 uses for its own admissions, so routing a car here cannot invent a
          -- new dwell regime. The planner's timed leg is preferred whenever one exists.
          SELECT l.leg_id, l.planned_end_sim INTO v_bay_leg_id, v_bay_until
            FROM public.ottoq_itinerary_legs l
           WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_need.vehicle_id
             AND l.status = 'planned' AND l.to_stall_id IS NULL
             AND l.leg_type = public.ottoq_svc_to_leg_type(v_need.svc)
             AND l.planned_end_sim IS NOT NULL AND l.planned_end_sim > v_clock
           ORDER BY l.seq LIMIT 1;
          v_bay_until := GREATEST(
            COALESCE(v_bay_until,
                     v_clock + make_interval(mins => GREATEST(
                       ottoq_sim_service_minutes(p_sim_run_id, v_need.time_key, v_need.base_min)::int, 1))),
            v_clock + interval '1 minute');

          v_space := ottoq.ottoq_enact_space_assignment(
                       p_sim_run_id, v_depot, v_need.vehicle_id, v_need.stall_type,
                       v_need.purpose, v_clock, v_bay_until, v_bay_leg_id, 'needs_card');

          IF COALESCE((v_space->>'assigned')::boolean, false) THEN
            UPDATE vehicles
               SET current_state = v_need.new_state::vehicle_state,
                   last_state_change = v_clock,
                   config = jsonb_set(
                              jsonb_set(COALESCE(config,'{}'::jsonb), '{svc_step}',
                                to_jsonb(CASE WHEN v_need.stall_type = 'service_bay'
                                              THEN 'servicing' ELSE 'washing' END)),
                              '{service_ends_at}', to_jsonb(v_bay_until::text))
             WHERE id = v_need.vehicle_id;
            IF v_need.stall_type = 'wash_bay' THEN
              v_wash_open := v_wash_open - 1;
              IF COALESCE(v_need.is_resume,false) THEN v_wash_res_used := v_wash_res_used + 1; END IF;
            ELSE
              v_svc_open := v_svc_open - 1;
              IF COALESCE(v_need.is_resume,false) THEN v_svc_res_used := v_svc_res_used + 1; END IF;
            END IF;
            v_action := v_proposal || v_space
                        || jsonb_build_object('verb','assign_stall',
                             'stall_id', v_space->>'stall_id',
                             'bay_booked', (v_space->>'booking_id') IS NOT NULL,
                             -- 0003: THE P0 NUMERATOR. A true here is one unit of
                             -- "cut-short bay work re-booked into a space it holds".
                             'resumed_bay_work', COALESCE(v_need.is_resume,false),
                             'resumed_need', CASE WHEN COALESCE(v_need.is_resume,false)
                                                  THEN v_need.svc ELSE NULL END);
            v_outcome := 'enacted'; v_enacted := v_enacted + 1;
            PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_need.vehicle_id,
              'proceed_to_stall',
              jsonb_build_object('stall_id', v_space->>'stall_id',
                                 'reason', 'needs_card_' || v_need.purpose,
                                 'need', v_need.svc), v_clock);
          ELSE
            v_action := v_proposal || COALESCE(v_space,'{}'::jsonb)
                        || jsonb_build_object('verb','hold_no_space',
                             'resumed_bay_work', COALESCE(v_need.is_resume,false));
            v_outcome := 'noop_no_candidate'; v_deferred := v_deferred + 1;
          END IF;
        END IF;
        v_enact_ms := EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
        -- action_context 'task_start' matches the probe context used by (4) and (5) for bay
        -- admissions; resolved_action_context 'stall_assignment' is the HONEST classification
        -- because a space really was claimed AND booked - which is also what makes bays
        -- finally countable in the enacted_stall_by_space_type metric that read 51/51 charging.
        INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
        VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','stall_assignment','vehicle',v_need.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
      END LOOP;
    END IF;
  END IF;

  -- (5) SERVICE SEQUENCING
  FOR v_req IN
    SELECT v.id AS vehicle_id, v.fleet_operator_id, v.config->>'svc_step' AS svc_step
      FROM vehicles v WHERE v.home_depot_id=v_depot AND v.category='autonomous'
       AND v.current_state='staged_awaiting_service'
     ORDER BY v.last_state_change ASC NULLS FIRST, v.id LIMIT 40
  LOOP
    v_built:=v_built+1; v_t0:=clock_timestamp(); v_over:=false; v_safe:=false; v_block_codes:='{}'; v_disarm:='[]'::jsonb;
    v_ctx := ottoq_build_decision_context('task_start','vehicle',v_req.vehicle_id,v_depot,v_clock) || jsonb_build_object('svc_step', v_req.svc_step, 'requires_charging','false','service','service');
    -- A1: cuOpt/Nemotron may propose the service order; heuristic is the fallback.
    v_proposal := COALESCE(
      ottoq_l2_external_proposal(p_sim_run_id, 'service_sequencing', 'vehicle', v_req.vehicle_id),
      ottoq_l2_propose_service(v_req.vehicle_id, v_depot, v_ctx));
    v_prop_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    SELECT count(*) FILTER (WHERE would_block), array_agg(rule_code) FILTER (WHERE would_block),
           jsonb_agg(jsonb_build_object('rule_code',rule_code,'passed',passed,'reason',reason,'enforcement_taken',enforcement_taken,'severity',severity))
      INTO v_blocks, v_block_codes, v_rule_rows
      FROM ottoq_shield_probe('task_start','vehicle',v_req.vehicle_id,v_ctx,v_req.fleet_operator_id,v_depot);
    v_shield_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    v_t0:=clock_timestamp();
    IF COALESCE(v_blocks,0)>0 THEN v_action:=ottoq_l1_safe_default_service(v_req.vehicle_id,v_ctx); v_safe:=true; v_over:=true; v_outcome:='overridden_to_default'; v_overc:=v_overc+1;
    ELSE
      v_action:=v_proposal; v_outcome:='enacted'; v_enacted:=v_enacted+1;
      IF v_action->>'verb'='admit_service' THEN
        -- BAY ENTRY MOVED BELOW THE HELPER (Phase 3) -- same defect and same fix as (4).
        -- CALENDAR (service bay). CHOOSE + RECORD ONLY, never gating - same contract as (4).
        SELECT l.leg_id, (l.planned_end_sim - l.planned_start_sim)
          INTO v_bay_leg_id, v_bay_dur
          FROM public.ottoq_itinerary_legs l
         WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
           AND l.status = 'planned' AND l.to_stall_id IS NULL
           AND l.leg_type IN ('service','mechanical_pm','fault_repair','sensor_calibration','cosmetic_repair')
         ORDER BY l.seq LIMIT 1;
        IF v_bay_leg_id IS NULL THEN
          -- FALLBACK: adopt the leg the forward planner already booked (see section (4)).
          SELECT l.leg_id, (l.planned_end_sim - l.planned_start_sim)
            INTO v_bay_leg_id, v_bay_dur
            FROM public.ottoq_itinerary_legs l
           WHERE l.sim_run_id = p_sim_run_id AND l.vehicle_id = v_req.vehicle_id
             AND l.status IN ('planned','active')
             AND l.leg_type IN ('service','mechanical_pm','fault_repair','sensor_calibration','cosmetic_repair')
           ORDER BY (l.status = 'active') DESC, l.seq LIMIT 1;
        END IF;
        -- TOTAL allow-list: all five of those leg types collapse to the single legal
        -- purpose 'service'. The leg_type itself is NEVER passed through.
        v_bay_until := v_clock + GREATEST(
          COALESCE(v_bay_dur,
                   make_interval(mins => ottoq_policy_get(p_sim_run_id,'service_bay_default_min',45)::int)),
          interval '1 minute');
        v_space := ottoq.ottoq_enact_space_assignment(p_sim_run_id, v_depot, v_req.vehicle_id,
                       'service_bay', 'service', v_clock, v_bay_until,
                       v_bay_leg_id, 'service_sequencing');
        v_bay_bkg := NULLIF(v_space->>'booking_id','')::uuid;
        IF v_bay_bkg IS NOT NULL AND v_bay_leg_id IS NOT NULL THEN
          UPDATE public.ottoq_itinerary_legs
             SET to_stall_id = (SELECT b.stall_id FROM public.ottoq_stall_bookings b
                                 WHERE b.booking_id = v_bay_bkg)
           WHERE leg_id = v_bay_leg_id;
        END IF;
        IF COALESCE((v_space->>'assigned')::boolean, false) THEN
          UPDATE vehicles SET current_state='in_service_bay', last_state_change=v_clock,
                 config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',to_jsonb('servicing'::text)) WHERE id=v_req.vehicle_id;
          PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'enter_service',
                  jsonb_build_object('stall_id',   v_space->>'stall_id',
                                     'booking_id', v_space->>'booking_id',
                                     'leg_id',     v_bay_leg_id,
                                     'purpose',    'service'), v_clock);
          v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                      || jsonb_build_object('bay_booked', v_bay_bkg IS NOT NULL,
                                            'bay_purpose', 'service',
                                            'bay_stall_type', 'service_bay',
                                            'stall_id', v_space->>'stall_id',
                                            'booking_id', v_space->>'booking_id',
                                            'leg_id', v_bay_leg_id);
        ELSE
          -- NO BAY -> DO NOT ENTER ONE. Identical in effect to this proposer's own
          -- 'hold_in_queue': the vehicle stays in staged_awaiting_service and is retried.
          v_action := COALESCE(v_action,'{}'::jsonb) || COALESCE(v_space,'{}'::jsonb)
                      || jsonb_build_object('verb','hold_no_bay', 'bay_booked', false,
                                            'bay_purpose', 'service',
                                            'bay_stall_type', 'service_bay');
          v_outcome := 'noop_no_candidate'; v_enacted := v_enacted - 1; v_deferred := v_deferred + 1;
        END IF;
      ELSIF v_action->>'verb' = 'hold_in_queue' THEN
        -- SERVICE-NEED HOLD: must-do bay work outstanding and no free bay (or the
        -- shield blocked). Leave the vehicle in staged_awaiting_service - no state
        -- write at all - so the service queue keeps it instead of redeploying a
        -- vehicle with mandatory work open. The proposer bounds this with a
        -- patience threshold, so a hold can never strand a vehicle.
        NULL;
      ELSE
        UPDATE vehicles SET current_state='staged_for_departure', last_state_change=v_clock,
               config=jsonb_set(COALESCE(config,'{}'::jsonb),'{svc_step}',to_jsonb('ready'::text)) WHERE id=v_req.vehicle_id;
        PERFORM ottoq_emit_vehicle_command(p_sim_run_id, v_depot, v_req.vehicle_id, 'stage', jsonb_build_object('ready', true), v_clock);
      END IF;
    END IF;
    v_enact_ms:=EXTRACT(MILLISECOND FROM (clock_timestamp()-v_t0))::int;
    INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,resolved_action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,overridden,override_rule_codes,rule_results,safe_default_taken,outcome_status,propose_latency_ms,shield_latency_ms,enact_latency_ms,total_latency_ms)
    VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,'task_start','task_start','vehicle',v_req.vehicle_id,v_ctx,v_proposal,v_action,v_over,v_block_codes,COALESCE(v_rule_rows,'[]'::jsonb),v_safe,v_outcome,v_prop_ms,v_shield_ms,v_enact_ms,COALESCE(v_prop_ms,0)+COALESCE(v_shield_ms,0)+COALESCE(v_enact_ms,0));
  END LOOP;

  -- A3: close the external-proposal lifecycle for this tick — consumed
  -- (entity got an enacted decision) → 'enacted'; past-freshness → 'expired'.
  UPDATE ottoq_external_proposals p SET status='enacted'
   WHERE p.sim_run_id=p_sim_run_id AND p.status='pending'
     AND EXISTS (SELECT 1 FROM ottoq_decisions d
                  WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick
                    AND d.entity_id=p.entity_id AND d.outcome_status='enacted'
                    AND d.enacted_action->>'source' = p.source);
  -- honest pre-emption: the entity was decided this tick, but NOT by this proposal
  UPDATE ottoq_external_proposals p SET status='superseded'
   WHERE p.sim_run_id=p_sim_run_id AND p.status='pending'
     AND EXISTS (SELECT 1 FROM ottoq_decisions d
                  WHERE d.sim_run_id=p_sim_run_id AND d.tick_seq=v_tick
                    AND d.entity_id=p.entity_id AND d.outcome_status='enacted');
  UPDATE ottoq_external_proposals p SET status='expired'
   WHERE p.sim_run_id=p_sim_run_id AND p.status='pending'
     AND GREATEST(COALESCE(p.expires_at, p.created_at+interval '35 minutes'), p.created_at+interval '35 minutes') < v_clock;

  -- ══════════════════ BUILD 3: THE INSPECT SEAM (ADDITIVE) ══════════════════
  -- 177 inspect legs ended the prior run still 'planned' across 110 arriving vehicles
  -- while 14 inspection stalls per depot sat idle, because (1) the needs card never
  -- emits 'interior_inspection', (2) this tick's bay loop filters to lanes
  -- wash_bay/detail/service_bay and inspection is lane 'cabin', and (3) inspection
  -- stalls are stall_type='staging' so no caller could address them.
  -- Placed HERE, last, on purpose: charging (3), the bay loop and service sequencing
  -- (5) have all already run, so the seam can only take vehicles nothing else claimed.
  -- It never raises (see the handler inside) -- the 2026-08-01 leg_type lesson.
  v_enacted := v_enacted + COALESCE(
    ottoq.ottoq_enact_inspection_seam(p_sim_run_id, v_depot, v_tick, v_snapshot_id, v_clock), 0);

  PERFORM ottoq.ottoq_link_bookings_to_decisions(p_sim_run_id, v_tick);

  RETURN ROW(v_tick, v_clock, v_built, v_enacted, v_overc, v_deferred, v_errored, v_disn,
             (SELECT COALESCE(SUM(total_latency_ms),0) FROM ottoq_decisions WHERE sim_run_id=p_sim_run_id AND tick_seq=v_tick))::ottoq_decide_tick_result;
END;
$function$;


-- ============================================================================
-- §5  public.ottoq_indepot_reassignment_guard  —  P1(a) + P1(b)
--
-- THE DEFECT, IN ONE SENTENCE: three branches of this function approve their own
-- request on the spot, and all three recorded WHEN using the real wall clock on rows
-- whose request time is a simulated clock, and recorded WHY not at all.
--
-- WHAT CHANGES
--   * decided_at is stamped COALESCE(sim_clock, now()) -- the SAME domain the row's
--     requested_at_sim is in. In production (no sim run) that is now(), which is
--     correct, and payload.clock_domain already says 'real' there.
--   * each of the three writes the same payload.decision object the auto-gate writes,
--     with verdict / reason / decided_at_sim / decider / copilot_* / doctrine, plus
--     fast_path=true, fast_path_basis and latency_min=0.
--
-- WHAT DOES NOT CHANGE, ON PURPOSE
--   * These paths stay FAST. A vehicle that cannot safely continue does not wait 8
--     sim-minutes for a gate to answer a question whose answer is already known. The
--     brief asked for auditable and sim-domain, not slower, and slower would be wrong.
--   * The gate_mode strings are untouched, so every phase-10/11/12/13 harness section
--     keeps comparing like with like.
--   * requested_at / decide_after / expires_at keep their real-clock meaning, exactly as
--     0002 decided, for exactly 0002's reason: re-interpreting them would rewrite the
--     meaning of every historical row and every dashboard reading them.
--
-- SCOPE NOTE: the brief named only vehicle_fault_critical_immobilizing (2 of 48). All
-- THREE born-approved branches have the identical defect --
-- resource_fault_auto_reroute and vehicle_fault_not_in_service were simply not exercised
-- often enough in that run to show up. Fixing one and leaving two would have left the
-- latency measurement able to break again on the next run that happens to trip them.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_indepot_reassignment_guard(p_vehicle_id uuid, p_sim_run_id uuid, p_reason text DEFAULT 'optimization'::text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_veh vehicles%ROWTYPE;
  v_approval uuid;
  -- 0002: the SIM clock this depot is actually living in, and the two latencies
  -- that govern how long a gated decision may sit unanswered.
  v_clock_sim timestamptz;
  v_auto_min  numeric;
  v_maxp_min  numeric;
  v_sev text;
  v_mid boolean;
  v_enforce numeric;
  v_pay jsonb;
  v_immob boolean;
  v_req numeric;
  v_defer_class text;
  v_bay boolean;
  v_si boolean;          -- service-incompatible: the SERVICE cannot safely continue in place
  v_si_basis text;
  v_fault_class text;
  -- 0003 (P1a/P1b): the audit object and the sim-domain decision stamp that the three
  -- born-approved fast paths were missing.
  v_dec jsonb;
  v_dec_at timestamptz;
BEGIN
  SELECT * INTO v_veh FROM vehicles WHERE id = p_vehicle_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('allowed', false, 'reason', 'vehicle_not_found'); END IF;

  IF v_veh.current_state IN ('deployed','en_route_to_depot','en_route_to_deployment','offline') THEN
    RETURN jsonb_build_object('allowed', true, 'mode', 'outside_walls');
  END IF;

  v_sev     := lower(COALESCE(p_payload->>'severity',''));
  v_mid     := v_veh.current_state IN ('in_wash_bay','in_detail_bay','in_service_bay','charging_dcfc','charging_l2');
  v_bay     := v_veh.current_state IN ('in_wash_bay','in_detail_bay','in_service_bay');
  v_enforce := COALESCE(ottoq_policy_get(p_sim_run_id, 'indepot_guard_enforce', 1), 1);
  v_pay     := COALESCE(p_payload, '{}'::jsonb)
               || jsonb_build_object('reason', p_reason, 'state', v_veh.current_state::text, 'mid_service', v_mid);

  -- ══════════════ 0002: STAMP THE CLOCK DOMAIN ONTO THE ROW ══════════════
  -- This function stamps requested_at / decide_after / expires_at with now() -- the REAL
  -- wall clock. The other writer of this table (ottoq.ottoq_plan_opportunistic_charges)
  -- stamps the same three columns with the SIM clock. Two writers, two domains, same
  -- columns: any reader that compares them to a sim clock is silently wrong for half the
  -- rows, and that is exactly how 55 approvals became undecidable AND unexpirable.
  --
  -- The real columns are DELIBERATELY LEFT ALONE. Re-interpreting them would rewrite the
  -- meaning of every historical row and of every dashboard that reads them. Instead the
  -- sim-domain triple is added ALONGSIDE, inside the payload, and the row now says which
  -- domain it belongs to. A reader picks the matching domain; nothing has to guess.
  -- (The cleaner long-term shape is real *_sim columns, as ottoq_stall_bookings already
  -- has with booked_at_sim. That is a schema change and belongs in its own migration.)
  SELECT r.sim_clock_current INTO v_clock_sim FROM ottoq_sim_runs r WHERE r.sim_run_id = p_sim_run_id;
  v_auto_min := GREATEST(COALESCE(ottoq_policy_get(p_sim_run_id,'indepot_reassign_auto_decide_min',8),8), 0);
  v_maxp_min := GREATEST(COALESCE(ottoq_policy_get(p_sim_run_id,'indepot_reassign_max_pending_min',30),30), v_auto_min);
  v_pay := v_pay || CASE
             WHEN v_clock_sim IS NULL
               -- No sim run: production. The real clock IS the domain, so nothing to add.
               THEN jsonb_build_object('clock_domain','real')
             ELSE jsonb_build_object('clock_domain','sim',
                    'requested_at_sim', v_clock_sim,
                    'decide_after_sim', v_clock_sim + (v_auto_min || ' minutes')::interval,
                    'expires_at_sim',   v_clock_sim + (v_maxp_min || ' minutes')::interval)
           END;

  -- ══════════ 0003 (P1a + P1b): THE FAST PATH IS STILL A DECISION ══════════
  -- THE DEFECT. Three branches below insert their approval ALREADY 'approved'. All three
  -- stamped decided_at with now() -- the REAL wall clock -- on rows whose requested_at_sim
  -- is a SIM timestamp, and none of them wrote a payload.decision audit object. Two
  -- consequences, both measured on run 093c20f4:
  --   (a) 2 of 48 gate rows had no audit trail at all, so "who decided this, on what
  --       basis" was answerable for 46 rows and unanswerable for 2.
  --   (b) latency computed as (decided_at - payload.requested_at_sim) subtracted a SIM
  --       timestamp from a REAL one on exactly those 2 rows. That is what produced the
  --       nonsense range "min 0.01 / max 22.18 sim-min"; only the median 8.27 survived.
  --       This is the 8th instance of the sim-vs-real clock-domain bug class here, and
  --       the second one to occur INSIDE a measurement rather than inside a decision.
  --
  -- THE FIX, AND WHAT IT DELIBERATELY DOES NOT DO. These paths stay FAST. A vehicle that
  -- genuinely cannot continue safely does NOT wait 8 sim-minutes for a gate to answer a
  -- question whose answer is already known. Nothing about WHEN they act changes -- only
  -- that they now say, in the sim domain and in the same shape the auto-gate uses, what
  -- was decided and why. latency_min is stamped 0 because it IS 0, honestly.
  --
  -- The real requested_at / decide_after / expires_at columns are still left alone, for
  -- the reason given above: rewriting them would rewrite every historical row.
  v_dec_at := COALESCE(v_clock_sim, now());

  -- ESCAPE HATCH A: policy kill-switch restores the pre-fix auto-allow for all fault traffic.
  IF v_enforce < 1 AND p_reason IN ('resource_fault','vehicle_fault') THEN
    RETURN jsonb_build_object('allowed', true, 'mode', 'legacy_auto_allow', 'recorded', false);
  END IF;

  -- RESOURCE FAULT: the SPACE broke. The vehicle physically cannot stay, so it still moves --
  -- but it is now RECORDED as a gated decision instead of being silently waved through.
  IF p_reason = 'resource_fault' THEN
    v_dec := jsonb_build_object('decision', jsonb_build_object(
               'verdict',                'approved',
               'reason',                 'zone_c_reopener_resource_fault_space_unusable',
               'decided_at_sim',         v_clock_sim,
               'decided_at_domain',      CASE WHEN v_clock_sim IS NULL THEN 'real' ELSE 'sim' END,
               'latency_min',            0,
               'fast_path',              true,
               'fast_path_basis',        'space_unusable_vehicle_cannot_remain',
               'decider',                'ottoq_indepot_safety_carveout_v1',
               'copilot_seen',           false,
               'copilot_recommendation', 'not_consulted_safety_fast_path',
               'copilot_binding',        false,
               'doctrine',               'nemotron_reviews_ottoq_decides'));
    INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
           requested_at, decide_after, expires_at, priority, status, decided_at, decided_by)
    VALUES ('indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
            v_pay || jsonb_build_object('gate_mode','resource_fault_auto_reroute',
                                        'auto_reason','space_unusable_vehicle_must_move')
                  || v_dec,
            now(), now(), now() + interval '30 minutes', 'high', 'approved', v_dec_at,
            'auto_gate:resource_fault')
    RETURNING approval_id INTO v_approval;
    RETURN jsonb_build_object('allowed', true, 'mode', 'resource_fault_auto_reroute',
                              'recorded', true, 'approval_id', v_approval, 'preserve_work', true,
                              'rebook_required', true);
  END IF;

  -- VEHICLE FAULT: the vehicle broke; the bay itself is fine.
  IF p_reason = 'vehicle_fault' THEN

    -- No atomic work to protect. Allow, audited. (Unchanged.)
    IF NOT v_mid THEN
      v_dec := jsonb_build_object('decision', jsonb_build_object(
                 'verdict',                'approved',
                 'reason',                 'zone_c_reopener_vehicle_fault_no_atomic_work_to_protect',
                 'decided_at_sim',         v_clock_sim,
                 'decided_at_domain',      CASE WHEN v_clock_sim IS NULL THEN 'real' ELSE 'sim' END,
                 'latency_min',            0,
                 'fast_path',              true,
                 'fast_path_basis',        'not_mid_service_nothing_to_cut_short',
                 'decider',                'ottoq_indepot_safety_carveout_v1',
                 'copilot_seen',           false,
                 'copilot_recommendation', 'not_consulted_safety_fast_path',
                 'copilot_binding',        false,
                 'doctrine',               'nemotron_reviews_ottoq_decides'));
      INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
             requested_at, decide_after, expires_at, priority, status, decided_at, decided_by)
      VALUES ('indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
              v_pay || jsonb_build_object('gate_mode','vehicle_fault_not_in_service')
                    || v_dec,
              now(), now(), now() + interval '30 minutes', 'normal', 'approved', v_dec_at,
              'auto_gate:vehicle_fault_not_in_service')
      RETURNING approval_id INTO v_approval;
      RETURN jsonb_build_object('allowed', true, 'mode', 'vehicle_fault_not_in_service',
                                'recorded', true, 'approval_id', v_approval);
    END IF;

    -- ══════════════ PHASE 10 FIX A (kept) ══════════════
    -- SEVERITY IS A CONSEQUENCE RATING, NOT A DISPOSITION.
    v_immob      := COALESCE((p_payload->>'immobilizing')::boolean, false);
    v_fault_class:= NULLIF(p_payload->>'fault_class','');
    v_req        := COALESCE(ottoq_policy_get(p_sim_run_id,'indepot_critical_requires_immobilizing',1),1);

    -- ══════════════ PHASE 12 FIX (P2) — IMMOBILIZING IS NOT A LICENCE TO CUT THE WORK ══════════════
    -- MEASURED (phase 11, seed 424242): all 12 work-cutting evictions came through this branch,
    -- 10 of them off charging_l2, destroying 595.56 of the 641.30 minutes -- avg 66.17 min each,
    -- max 139.96. The predicate that let them through was `immobilizing`, and immobilizing is
    -- the WRONG question for a vehicle sitting on a plug.
    --   "Immobilizing" answers: can the vehicle LEAVE UNDER ITS OWN POWER?  -> tow vs drive-away.
    --   It does NOT answer: can the SERVICE SAFELY CONTINUE WHERE IT IS?
    -- A charger does not care that the drive system, steering or brakes are broken. A vehicle
    -- that cannot move cannot be "evicted" at all -- it must be TOWED, and it keeps occupying
    -- that stall until the tow arrives, so terminating the charge buys the depot nothing and
    -- throws away the energy work. The faults that genuinely forbid continuing in place are the
    -- ENERGY/THERMAL ones (HV isolation, battery thermal, charge-system) plus anything in a BAY,
    -- where the cycle physically requires the vehicle to move.
    -- `service_incompatible` is the new explicit signal (production: the OEM fault code's
    -- class). TOTAL FUNCTION: a caller that does not send it falls back to the old
    -- `immobilizing` behaviour, so no other caller changes.
    v_si := COALESCE((p_payload->>'service_incompatible')::boolean, v_immob);
    v_si_basis := CASE WHEN p_payload ? 'service_incompatible' THEN 'fault_class' ELSE 'legacy_immobilizing_fallback' END;
    IF v_immob AND v_bay THEN
      -- A vehicle that cannot move cannot complete a wash/detail/service cycle.
      v_si := true; v_si_basis := 'immobilizing_in_bay';
    END IF;

    IF v_sev = 'critical' AND (v_si OR v_req < 1) THEN
      -- ZONE C, genuine: the service cannot continue in place. Evict -- safety first, and the
      -- tow/tech path must never deadlock -- but it is a GATED, AUDITED decision and the caller
      -- is told it MUST preserve the outstanding work and RE-BOOK it.
      -- gate_mode string is deliberately UNCHANGED so phase-10/11/12 harness sections stay
      -- like-for-like; the narrowed basis is stamped alongside it.
      -- 0003 (P1a): THIS is the carve-out the adversarial pass flagged. It stays a fast
      -- path -- an immobilised vehicle must never queue behind paperwork -- but it now
      -- stamps the SIM clock and carries the same payload.decision object the auto-gate
      -- writes, so it is auditable and its latency is measurable in one domain.
      v_dec := jsonb_build_object('decision', jsonb_build_object(
                 'verdict',                'approved',
                 'reason',                 'zone_c_reopener_vehicle_fault_service_cannot_continue_in_place',
                 'decided_at_sim',         v_clock_sim,
                 'decided_at_domain',      CASE WHEN v_clock_sim IS NULL THEN 'real' ELSE 'sim' END,
                 'latency_min',            0,
                 'fast_path',              true,
                 'fast_path_basis',        COALESCE(v_si_basis,'unknown'),
                 'decider',                'ottoq_indepot_safety_carveout_v1',
                 'copilot_seen',           false,
                 'copilot_recommendation', 'not_consulted_safety_fast_path',
                 'copilot_binding',        false,
                 'doctrine',               'nemotron_reviews_ottoq_decides'));
      INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
             requested_at, decide_after, expires_at, priority, status, decided_at, decided_by)
      VALUES ('indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
              v_pay || jsonb_build_object('gate_mode','vehicle_fault_critical_immobilizing',
                        'immobilizing', v_immob,
                        'service_incompatible', v_si,
                        'evict_basis', v_si_basis,
                        'fault_class', v_fault_class,
                        'auto_reason', CASE WHEN v_req < 1 THEN 'policy_immobilizing_check_disabled'
                                            ELSE 'service_cannot_continue_in_place' END,
                        'work_disposition','outstanding_work_must_survive_as_due_and_be_rebooked')
                    || v_dec,
              now(), now(), now() + interval '30 minutes', 'high', 'approved', v_dec_at,
              'auto_gate:vehicle_fault_critical_immobilizing')
      RETURNING approval_id INTO v_approval;
      RETURN jsonb_build_object('allowed', true, 'mode', 'vehicle_fault_critical_immobilizing',
                                'recorded', true, 'approval_id', v_approval, 'preserve_work', true,
                                'rebook_required', true,
                                'service_incompatible', v_si, 'evict_basis', v_si_basis,
                                'immobilizing', v_immob, 'fault_class', v_fault_class);
    END IF;

    -- MID-SERVICE, SERVICE CAN CONTINUE: DEFER. The atomic visit finishes first; the exception
    -- handler resumes the eviction afterwards. THREE defer classes, three budgets:
    --   immobilizing_awaiting_tow  -- broken but charge-safe: it is going nowhere without a tow
    --                                 anyway, so let the plug finish. BOUNDED budget, never open.
    --   critical_not_immobilizing  -- short budget, acted on quickly.
    --   major                      -- original budget.
    -- NO DEADLOCK: every class still exits on service-window-complete, left-service-state,
    -- technician approval (this row is inserted HIGH priority and is visible immediately), or a
    -- bounded budget expiry. The tow/tech path is never closed, only sequenced.
    v_defer_class := CASE WHEN v_immob            THEN 'immobilizing_awaiting_tow'
                          WHEN v_sev='critical'   THEN 'critical_not_immobilizing'
                          ELSE 'major' END;
    INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
           requested_at, decide_after, expires_at, priority)
    SELECT 'indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
           v_pay || jsonb_build_object('gate_mode','deferred_awaiting_tech',
                                       'defer_class', v_defer_class,
                                       'immobilizing', v_immob,
                                       'service_incompatible', v_si,
                                       'fault_class', v_fault_class),
           now(), now(), now() + interval '30 minutes',
           CASE WHEN v_sev='critical' OR v_immob THEN 'high' ELSE 'normal' END
    WHERE NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals a
                       WHERE a.vehicle_id = p_vehicle_id AND a.approval_type = 'indepot_reassign'
                         AND a.status = 'pending')
    RETURNING approval_id INTO v_approval;
    IF v_approval IS NULL THEN
      -- AUDIT-STAMP RESCUE: the INSERT was suppressed because a pending indepot_reassign
      -- already exists for this vehicle. The decision IS still audited -- by THAT row -- so
      -- return its id instead of NULL. MEASURED (live run 4921c87d): 24 of 45 deferrals lost
      -- their audit stamp this way; phase 10/11 never hit it because no other writer left
      -- pending approvals behind.
      SELECT a.approval_id INTO v_approval FROM ottoq_ops_approvals a
       WHERE a.vehicle_id = p_vehicle_id AND a.approval_type = 'indepot_reassign'
         AND a.status = 'pending' ORDER BY a.requested_at DESC LIMIT 1;
    END IF;
    RETURN jsonb_build_object('allowed', false, 'mode', 'deferred_awaiting_tech',
                              'defer_class', v_defer_class,
                              'immobilizing', v_immob, 'service_incompatible', v_si,
                              'fault_class', v_fault_class,
                              'approval_id', v_approval, 'state', v_veh.current_state::text);
  END IF;

  -- Everything else (optimization / congestion / operator request) defers, as before.
  INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id,
         payload, requested_at, decide_after, expires_at, priority)
  SELECT 'indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
         v_pay, now(), now(), now() + interval '30 minutes', 'normal'
  WHERE NOT EXISTS (SELECT 1 FROM ottoq_ops_approvals a
                     WHERE a.vehicle_id = p_vehicle_id AND a.approval_type = 'indepot_reassign'
                       AND a.status = 'pending')
  RETURNING approval_id INTO v_approval;
    IF v_approval IS NULL THEN
    -- AUDIT-STAMP RESCUE: the INSERT was suppressed because a pending indepot_reassign
    -- already exists for this vehicle. The decision IS still audited -- by THAT row -- so
    -- return its id instead of NULL. MEASURED (live run 4921c87d): 24 of 45 deferrals lost
    -- their audit stamp this way; phase 10/11 never hit it because no other writer left
    -- pending approvals behind.
    SELECT a.approval_id INTO v_approval FROM ottoq_ops_approvals a
     WHERE a.vehicle_id = p_vehicle_id AND a.approval_type = 'indepot_reassign'
       AND a.status = 'pending' ORDER BY a.requested_at DESC LIMIT 1;
  END IF;
  RETURN jsonb_build_object('allowed', false, 'mode', 'awaiting_tech_approval',
                            'approval_id', v_approval, 'state', v_veh.current_state::text);
END;
$function$;


-- ============================================================================
-- §6  public.ottoq_indepot_gate_latency  —  P1(b), THE MEASUREMENT ITSELF
--
-- The reported range "min 0.01 / max 22.18 sim-min" was not a slow gate and not a fast
-- one. It was a subtraction between two different clocks. §5 stops NEW rows being
-- created that way; this view stops the SUBTRACTION being written that way, by anyone,
-- ever again.
--
-- THE RULE THE VIEW ENFORCES: a latency is emitted only when both endpoints are in the
-- SAME domain. Sim rows use payload.requested_at_sim -> payload.decision.decided_at_sim.
-- Real rows (production, or legacy rows predating 0002) use requested_at -> decided_at.
-- Anything that cannot be measured in one domain returns NULL with
-- clock_domain='unmeasurable' -- an explicit refusal to answer, never a number that
-- looks plausible. Legacy rows written before 0002/0003 land there by design; that is
-- the honest answer for them.
--
-- This is a VIEW rather than a number in a document because the number goes stale on
-- every run and the definition does not.
-- ============================================================================
CREATE OR REPLACE VIEW public.ottoq_indepot_gate_latency AS
 SELECT ap.approval_id,
    ap.sim_run_id,
    ap.depot_id,
    ap.vehicle_id,
    ap.status,
    ap.decided_by,
    (ap.payload ->> 'gate_mode'::text) AS gate_mode,
    (ap.payload -> 'decision'::text ->> 'verdict'::text) AS verdict,
    (ap.payload -> 'decision'::text ->> 'reason'::text) AS verdict_reason,
    COALESCE((ap.payload -> 'decision'::text ->> 'fast_path'::text)::boolean, false) AS fast_path,
    (ap.payload ? 'decision'::text) AS has_audit_object,
        CASE
            WHEN (ap.payload ->> 'requested_at_sim'::text) IS NOT NULL
                 AND (ap.payload -> 'decision'::text ->> 'decided_at_sim'::text) IS NOT NULL
              THEN 'sim'::text
            WHEN (ap.payload ->> 'requested_at_sim'::text) IS NULL
                 AND ap.decided_at IS NOT NULL AND ap.requested_at IS NOT NULL
              THEN 'real'::text
            ELSE 'unmeasurable'::text
        END AS clock_domain,
        -- NEVER mixes domains. One branch per domain, and NULL when neither is complete.
        CASE
            WHEN (ap.payload ->> 'requested_at_sim'::text) IS NOT NULL
                 AND (ap.payload -> 'decision'::text ->> 'decided_at_sim'::text) IS NOT NULL
              THEN round(EXTRACT(epoch FROM ((ap.payload -> 'decision'::text ->> 'decided_at_sim'::text)::timestamptz
                                             - (ap.payload ->> 'requested_at_sim'::text)::timestamptz))::numeric
                         / 60.0, 2)
            WHEN (ap.payload ->> 'requested_at_sim'::text) IS NULL
                 AND ap.decided_at IS NOT NULL AND ap.requested_at IS NOT NULL
              THEN round(EXTRACT(epoch FROM (ap.decided_at - ap.requested_at))::numeric / 60.0, 2)
            ELSE NULL::numeric
        END AS latency_min,
    ap.requested_at,
    ap.decided_at,
    ((ap.payload ->> 'requested_at_sim'::text))::timestamptz AS requested_at_sim,
    ((ap.payload -> 'decision'::text ->> 'decided_at_sim'::text))::timestamptz AS decided_at_sim
   FROM public.ottoq_ops_approvals ap
  WHERE ap.approval_type = 'indepot_reassign'::text;

COMMENT ON VIEW public.ottoq_indepot_gate_latency IS
 'In-depot reassignment gate latency, measured strictly within one clock domain. latency_min is NULL and clock_domain is ''unmeasurable'' rather than mixing a SIM requested_at_sim with a REAL decided_at -- the error that produced the bogus 0.01-22.18 sim-min range on run 093c20f4. Do not compute gate latency any other way.';


-- ============================================================================
-- §7  P1(c) — THE EVICTION RE-BASELINE.  READ THIS BEFORE CALLING ANYTHING A
--     REGRESSION.  (Recorded here because a comment in a committed file is the
--     only artefact that survives; a number in a chat log does not.)
--
-- WHAT PEOPLE WILL SEE AND MISREAD
--   Phase 11 published:  evictions cutting live work 20.3%   gate protection 90.0%
--                        minutes destroyed 641.30 (immobilizing path only)
--   Run 093c20f4 shows:  evictions cutting live work 31.8%   gate protection 84.4%
--                        minutes destroyed 276.78
--   The first two numbers moved in the "wrong" direction. THEY ARE NOT REGRESSIONS.
--
-- WHY. The deferred-resume path of twin.ottoq_sim_vehicle_exception_handler used to
-- write a CONSTANT into its own numerator:
--       'interrupted_with_min_remaining', 0
-- so 'deferred_awaiting_tech' appeared to destroy 0.00 minutes no matter how much live
-- work it actually cut. Phase 11's "20.3%" and "90.0%" were computed over a numerator
-- that was structurally incapable of counting that path. Reconstructed from each
-- deferral's own min_remaining minus its elapsed defer time: 24 of 45 deferred resumes
-- closed a LIVE booking and really destroyed ~1,359.78 minutes -- 2.1x the immobilizing
-- path's 641.30, and completely invisible.
--
-- THE CORRECTED COMPARISON, LIKE FOR LIKE:
--       phase 11, reconstructed:  ~1,359.78 + 641.30 minutes destroyed
--       run 093c20f4, measured:       276.78 minutes destroyed  (-56.8% vs 641.30 alone,
--                                     and roughly -86% against the reconstructed total)
--   Phase 11 was WORSE. The apparent rise from 20.3% to 31.8% is a measurement that
--   started working, not a system that started failing.
--
-- ⭐ RE-BASELINE FROM RUN 093c20f4, NOT FROM PHASE 11. Phase 11's eviction percentages
--   are void as a comparison basis and must not be quoted again.
--
-- STATE OF THE CODE, VERIFIED IN THIS MIGRATION (not assumed)
--   The constant is GONE. All four emission sites now pass a measured v_remaining,
--   read from the booking's window upper bound BEFORE the clipping UPDATE, i.e. the true
--   remaining work at the instant the space was taken away:
--     twin.ottoq_sim_vehicle_exception_handler  immobilizing path      (measured)
--     twin.ottoq_sim_vehicle_exception_handler  deferred-resume path   (measured)
--     twin.ottoq_sim_bay_fault_handler          config stamp           (measured)
--     twin.ottoq_sim_bay_fault_handler          event payload          (measured)
--   Nothing in this file needed to change for that, and nothing in this file did.
--
-- ⚠️ ONE RESIDUAL CONSTANT, RECORDED AND DEFERRED -- NOT FIXED HERE.
--   Both exception-handler paths still call
--       ottoq.ottoq_emit_booking_interrupted(..., v_reopened, 0, '<source>')
--   where that literal 0 is the p_legs_replanned argument. It is an ASSERTION, not a
--   MEASUREMENT: neither path re-plans a leg itself, so 0 happens to be true today, but
--   nobody counted it, and 'legs_replanned' is a published field of the
--   booking_interrupted contract. Deferred deliberately: correcting it means replacing
--   the ~500-line twin.ottoq_sim_vehicle_exception_handler, which 0002 owns, and this
--   file already carries three replacements and one doctrine change. ONE CONCERN PER
--   FILE. It belongs in 0004 alongside the leg-replan accounting itself.
--   Anyone reading legs_replanned=0 off the deferred path before then: that zero has not
--   been measured. atoms_reopened, outstanding_restored and minutes_remaining on the
--   same payload HAVE been.
-- ============================================================================


-- ============================================================================
-- §8  POST-SNAPSHOT
-- ============================================================================
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0003_bay_work_recovery_post', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('ottoq_decide_tick', 'ottoq_indepot_reassignment_guard');

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0003_bay_work_recovery_post', 'view', n.nspname, c.relname,
       pg_get_viewdef(c.oid, true), md5(pg_get_viewdef(c.oid, true))
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind = 'v'
   AND c.relname IN ('ottoq_vehicle_needs_card', 'ottoq_indepot_gate_latency');


-- ============================================================================
-- §9  VERIFY  — read-only. Paste the real output into MIGRATION_LOG.md.
--
-- "Applied without error" is not verification. V1-V3 run immediately. V4-V7 need a
-- bounded run of >= 139 sim-min, captured AFTER the run is STOPPED, in the SIM domain,
-- with the denominator stated, and gated on arrivals. PRIMARY METRIC IS PER ARRIVING
-- VEHICLE. Starting a run purges the prior one -- preserve anything you need into a
-- non-'ottoq'-prefixed table FIRST (phase13_bookings_424242 is the worked example).
-- ============================================================================
--
-- V1. THE LEDGER DETECTOR EXISTS AND IS SANE. Expect: the three new columns present,
--     rebook_owed true only for vehicles with interruption evidence, and NEVER 'charge'
--     inside owed_bay_svcs.
-- SELECT count(*) AS vehicles,
--        count(*) FILTER (WHERE rebook_owed)                       AS owed_a_bay,
--        count(*) FILTER (WHERE 'charge' = ANY (owed_bay_svcs))    AS charge_leaked_MUST_BE_0,
--        round(avg(owed_bay_min) FILTER (WHERE rebook_owed), 2)    AS avg_owed_min
--   FROM public.ottoq_vehicle_needs_card;
--
-- V2. THE CARD DID NOT LOSE ANYTHING. must_do_now must be a SUPERSET of what the
--     cadence alone produced, and must_do_now / deferrable_now must not intersect.
-- SELECT count(*) AS contradictions_MUST_BE_0
--   FROM public.ottoq_vehicle_needs_card c
--  WHERE EXISTS (SELECT 1 FROM unnest(c.deferrable_now) d(x)
--                 WHERE d.x = ANY (c.must_do_now));
--
-- V3. THE GATE LATENCY IS MEASURABLE IN ONE DOMAIN. Was: 2 of 48 rows unmeasurable and
--     silently mixed. Expect clock_domain='unmeasurable' only on rows predating 0003.
-- SELECT clock_domain, fast_path, count(*),
--        min(latency_min), round(avg(latency_min),2) AS avg, max(latency_min)
--   FROM public.ottoq_indepot_gate_latency
--  GROUP BY 1,2 ORDER BY 1,2;
--
-- V4. ⭐ THE P0 NUMBER, STRAIGHT OFF THE DECISION LEDGER. No reconstruction.
--     Denominator: bay bookings interrupted in this run. Numerator: enacted bay
--     assignments flagged resumed_bay_work.
-- SELECT count(*) FILTER (WHERE d.outcome_status = 'enacted'
--                           AND (d.enacted_action->>'resumed_bay_work')::boolean)  AS bay_work_resumed,
--        count(*) FILTER (WHERE (d.context_frame->>'is_resume')::boolean)          AS resume_candidates_seen,
--        count(*) FILTER (WHERE (d.context_frame->>'is_resume')::boolean
--                           AND d.outcome_status <> 'enacted')                     AS resume_refused,
--        count(*) FILTER (WHERE d.outcome_status = 'enacted'
--                           AND NOT COALESCE((d.enacted_action->>'resumed_bay_work')::boolean,false)
--                           AND d.enacted_action->>'source' = 'needs_card')        AS fresh_admitted
--   FROM public.ottoq_decisions d
--  WHERE d.sim_run_id = :run AND d.enacted_action->>'source' = 'needs_card';
--
-- V5. ⭐ FRESH ARRIVALS WERE NOT STARVED. This is the counter-check on Design Decision 2
--     and it is the one that can falsify this migration. fresh_admitted (V4) must stay
--     healthy, and no fresh candidate may be skipped for the budget: the budget only
--     ever CONTINUEs a RESUMED row, so a fresh vehicle can only ever lose to a lack of
--     bays, never to this change. Confirm by comparing bay admissions per ARRIVING
--     VEHICLE against run 093c20f4 (assignments/arrival ex-inspect 0.946).
-- SELECT count(DISTINCT d.entity_id) FILTER (WHERE d.outcome_status='enacted')::numeric
--        / NULLIF((SELECT count(*) FROM public.ottoq_events e
--                   WHERE e.sim_run_id = :run AND e.event_type = 'vehicle.arrived_at_gate'),0)
--          AS bay_admissions_per_arrival
--   FROM public.ottoq_decisions d
--  WHERE d.sim_run_id = :run AND d.enacted_action->>'source' = 'needs_card';
--
-- V6. THE CHARGE PATH DID NOT MOVE. The charge carve-out is supposed to be free. Expect
--     charge assignments per arriving vehicle to be flat against 093c20f4, and expect
--     ZERO bay admissions taken while a charger was actually free.
-- SELECT count(*) FILTER (WHERE (d.context_frame->>'is_resume')::boolean
--                           AND d.outcome_status = 'enacted')  AS resumed_bay_admissions,
--        count(*) FILTER (WHERE d.resolved_action_context = 'stall_assignment'
--                           AND d.enacted_action->>'source' <> 'needs_card'
--                           AND d.outcome_status = 'enacted')  AS charge_assignments
--   FROM public.ottoq_decisions d WHERE d.sim_run_id = :run;
--
-- V7. THE 0002 CERTIFICATION IS INTACT. Re-run the protect list and expect NO movement
--     except where this migration is supposed to move it:
--       cut-short work re-booked into a space it HELD   7/17 = 41.2%  -> must RISE
--       charging subset                                 7/12 = 58.3%  -> must NOT fall
--       approvals created / decided / pending            48/48/0      -> unchanged
--       median decide latency                            8.27 sim-min -> unchanged
--       emission invariant 1.000 | phantoms 0/254 | reverse coverage 100%
--       double-bookings 0 (361 in-scope) | starvation none | inspection-zone parking 0%
--     Anything else that moves is this migration's fault until proven otherwise.
--
-- V8. COVERAGE GAP FROM THE 0002 ADVERSARIAL PASS -- STILL OPEN, RECORDED HERE SO IT IS
--     NOT LOST. The decider's APPROVE branch (zone_c_reopener_*) and the narrowed
--     readmit gate's STILL-BARRED branch remain unexercised, because run 093c20f4
--     contained zero genuine re-routes. §5 of THIS file makes the three fast paths
--     write zone_c_reopener_* reasons, so V3 above will now show them the moment a
--     resource_fault or vehicle_fault occurs -- which is partial coverage, not full.
--     A scenario knob that injects a congestion/flag event is still needed for the
--     decider's own approve branch. Own migration, own certification.
--
-- ============================================================================
-- AFTERWARDS  (scripts/APPLYING.md steps 5-8)
--   1. Put the real version the database assigned into the header above.
--   2. bash scripts/gen-drift-sql.sh
--   3. Add the row to MIGRATION_LOG.md, including the V1-V7 output.
--   4. Commit, then run scripts/check-drift.sql live. It must report CLEAN.
--      If it reports a routine-count delta: this file adds ZERO routines and TWO views
--      (ottoq_indepot_gate_latency is new; ottoq_vehicle_needs_card is replaced in
--      place). Diff live object names against db/baseline/ and confirm exactly one
--      addition before touching any expected count.
-- ============================================================================
