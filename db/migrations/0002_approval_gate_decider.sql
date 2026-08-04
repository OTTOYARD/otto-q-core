-- migration-version: 20260804140958
-- migration-name:    approval_gate_decider

-- ============================================================================
-- 0002_approval_gate_decider.sql
--
-- THE SHORT VERSION, IN PLAIN LANGUAGE
--
-- When something goes wrong with a vehicle inside the depot walls, OTTO-Q does not
-- just move it. It writes down the question -- "may I pull this car out of its bay?"
-- -- as an approval, because doctrine says a vehicle already inside the walls is not
-- re-routed without a technician in the loop. That is the in-depot reassignment gate,
-- and it is correct.
--
-- The problem is that nothing ever answered the question. Fifty-five of these
-- approvals were raised in the last measured run and not one of them was ever
-- decided. They could not even expire. And because a car with an unanswered question
-- is not allowed to be moved, twenty-seven of the twenty-nine vehicles holding
-- unfinished service work were forbidden from ever going back and finishing it.
--
-- That is why cut-short work has never once been re-booked: 0 of 38, then 0 of 52,
-- three phases running. It was never a matter of running the simulation for longer.
-- The cars were barred at the door before they ever reached the part of the system
-- that hands out spaces.
--
-- ============================================================================
-- SYMPTOM
--   public.ottoq_ops_approvals is an absorbing state for approval_type
--   'indepot_reassign'. 55 pending rows, 55 distinct vehicles, one run, none ever
--   decided and none ever expired. 27 of the 29 vehicles holding an open cut-short
--   need (93.1%) were barred from ottoq.ottoq_readmit_reopened_needs by those rows.
--   Nemotron had reviewed 0 of the 55 (no row carried payload->'copilot').
--
-- CAUSE  (three defects, one family)
--   1. CLOCK DOMAIN. A generic decider does exist -- twin.ottoq_opportunistic_scan --
--      and it ran, and it worked: in the same run it decided 9 opportunistic_charge
--      rows. Its cursor is not filtered by approval_type, so it was eligible to decide
--      these rows too. It was defeated by one predicate:
--          AND ap.decide_after <= p_clock AND ap.expires_at > p_clock
--      p_clock is the SIM clock. public.ottoq_indepot_reassignment_guard stamps
--      decide_after / expires_at with now() -- the REAL clock. In the measured run the
--      two were 4h28m apart, so decide_after <= sim_clock was false for all 55 AND
--      expires_at <= sim_clock was false for all 55. Neither decidable nor expirable.
--      This is the 7th instance of this bug class in this codebase.
--   2. TWO BELIEFS, ONE EVENT. twin.ottoq_sim_vehicle_exception_handler flips
--      config.exception.status from 'pending_approval' to 'technician_approved' and
--      never touches the approvals ledger. The vehicle record then says a technician
--      approved; the ledger says nobody did. Same event, two contradictory records.
--   3. A FUNCTION ARGUING WITH ITSELF. ottoq.ottoq_readmit_reopened_needs emits
--      'gate','resumption_is_not_reroute_no_tech_approval_required' while the cursor
--      six lines above it excludes any vehicle holding a pending approval. The code
--      and its own stated doctrine disagreed, and the code was winning.
--   PAIRED: the tow-retrieval predicate compares vehicles.last_state_change (REAL --
--      the BEFORE UPDATE trigger on vehicles overwrites it with NOW()) against the SIM
--      clock. It fired ZERO times, which is what made ottoq_readmit_resumed_visits
--      double-dead: it needs the emergency_staged / retrieved_staged pair that only
--      tow retrieval produces. Fixing approvals without this would leave genuinely
--      broken vehicles unable to leave.
--
-- FIX  (this file, in order)
--   §1  policy catalogue rows for the three new dials.
--   §2  snapshots + md5 guards for all five functions being replaced.
--   §3  NEW public.ottoq_decide_indepot_approvals -- OTTO-Q's own decider.
--   §4  public.ottoq_indepot_reassignment_guard -- stamp the SIM-domain trio into the
--       payload alongside the untouched real columns, so a reader can tell which clock
--       a row belongs to.
--   §5  twin.ottoq_opportunistic_scan -- type-filter it to the twin's own approvals.
--   §6  ottoq.ottoq_readmit_reopened_needs -- call the decider; narrow the exclusion;
--       make the emitted doctrine string match the code.
--   §7  ottoq.ottoq_readmit_resumed_visits -- same narrowing (second blocked path).
--   §8  twin.ottoq_sim_vehicle_exception_handler -- resolve the approval in the same
--       transaction as the technician flip; resolve the auto_staged path; fix the tow
--       clock domain; add a named safety net.
--   §9  post-snapshots.  §10 verification queries.
--
--   WHAT THIS FILE DELIBERATELY DOES NOT CHANGE:
--   * It does NOT delete the "NOT EXISTS (pending approval)" clause. Blanket removal
--     is a doctrine breach. The clause is narrowed, and the gate is made to work.
--   * It does NOT let Nemotron decide anything. Nemotron's recommendation is read and
--     recorded; it is never allowed to change a verdict.
--   * It does NOT touch the LP formulation, CSR build, cuOpt parse path, Gate B,
--     verify_jwt, ottoq_events, or public.ottoq_decide_tick.
--   * It does NOT widen the bay no-show grace, and it does not change any defer budget.
--
-- BLAST RADIUS
--   ottoq_ops_approvals writers: 13 functions + 2 edge functions. Five are touched
--   here; the other eight are unaffected because the real requested_at / decide_after /
--   expires_at columns keep their exact current meaning -- the sim-domain values are
--   ADDED inside payload, never substituted.
--   The phase-11 baseline is protected by construction, and specifically by the choice
--   of verdict for the deferral class -- see the DESIGN DECISIONS note in §3.
--
-- VERIFY
--   §10, plus a bounded run of >= 139 sim-min captured AFTER the run is stopped.
--   Primary metric is per ARRIVING VEHICLE. See MIGRATION_LOG.md.
--
-- METHOD NOTE ON THE md5 GUARDS
--   The expected hashes below were computed offline from db/baseline/*.sql, which the
--   baseline README states was exported verbatim via pg_get_functiondef(oid) on
--   2026-08-03. They are compared against
--       md5(rtrim(pg_get_functiondef(oid), E' \n\r\t'))
--   so that a trailing-newline difference between the export and the live server cannot
--   produce a false abort. If any live body has genuinely drifted since the export,
--   this migration REFUSES TO APPLY. That is the intended behaviour, not a defect:
--   re-read the live body, re-base the change on it, and re-run.
-- ============================================================================


-- ============================================================================
-- §1  POLICY CATALOGUE
--
-- Catalogue rows exist so OTTOCOMMAND / Nemotron can see and set these dials at all
-- (public.ottoq_policy_set refuses any param_key with no catalogue row).
--
-- GAP, RECORDED NOT FIXED: public.ottoq_policy_get looks up global scope with
-- "scope_type='global' AND scope_id IS NULL", but ottoq_policy_params.scope_id is
-- NOT NULL -- so a global-scope policy row cannot exist and that lookup can never
-- match. The practical consequence is that the in-code defaults below ARE the
-- effective defaults, and tuning has to be done at depot or run scope. That is a
-- separate concern and belongs in its own migration.
-- ============================================================================
INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value, min_value, max_value, affects)
VALUES
  ('indepot_reassign_auto_decide_min',
   'Sim-minutes a pending in-depot reassignment approval waits before OTTO-Q decides it itself. Non-zero on purpose: a zero-latency gate is cosmetic.',
   8, 0, 120, 'in-depot reassignment gate latency'),
  ('indepot_reassign_max_pending_min',
   'Hard sim-minute ceiling on how long an in-depot reassignment approval may stay pending. On expiry it is resolved as expired. The no-vehicle-waits-forever backstop.',
   30, 1, 480, 'in-depot reassignment gate backstop'),
  ('indepot_reassign_auto_decide_enabled',
   'Kill switch for the auto-decider verdict (1=on, 0=off). The expiry backstop keeps running either way, so switching this off can never re-create an absorbing state.',
   1, 0, 1, 'in-depot reassignment gate')
ON CONFLICT (param_key) DO NOTHING;


-- ============================================================================
-- §2  SNAPSHOT, THEN GUARD  (house rule 1)
--
-- Recover any of these later with:
--   SELECT definition FROM public.ottoq_schema_snapshots
--    WHERE label = '0002_approval_gate_decider_pre' AND object_name = '<fn>';
-- ============================================================================
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0002_approval_gate_decider_pre', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname = 'public' AND p.proname IN ('ottoq_indepot_reassignment_guard',
                                               'ottoq_decide_indepot_approvals'))
    OR (n.nspname = 'twin'   AND p.proname IN ('ottoq_opportunistic_scan',
                                               'ottoq_sim_vehicle_exception_handler'))
    OR (n.nspname = 'ottoq'  AND p.proname IN ('ottoq_readmit_reopened_needs',
                                               'ottoq_readmit_resumed_visits'));

DO $guard$
DECLARE
  v_expect CONSTANT jsonb := jsonb_build_object(
    'public.ottoq_indepot_reassignment_guard',       '141b5ff01c1bcf61d2fbc9a5aa66ce4a',
    'twin.ottoq_opportunistic_scan',                 'a4b08baf4af53ff445775703da04b6ef',
    'ottoq.ottoq_readmit_reopened_needs',            'f11f0c18840747fdf79ae9de2c014bc5',
    'ottoq.ottoq_readmit_resumed_visits',            '55566af427fa7da9203091a5e6caa3a7',
    'twin.ottoq_sim_vehicle_exception_handler',      '6dda25ad38e70340c1eee2e9b14d2c5c');
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
        'GUARD: % live md5 % does not match expected %. Someone changed this function outside this migration (or the 2026-08-03 baseline export is stale). Re-read the live body, re-base, re-run. Nothing has been changed.',
        k, v_actual, (v_expect->>k);
    END IF;
  END LOOP;
  RAISE NOTICE 'GUARD: all 5 target functions match their expected definitions.';
END
$guard$;


-- ============================================================================
-- §3  THE DECIDER  (defect a)
--
-- ── DESIGN DECISIONS, AND WHY ───────────────────────────────────────────────
--
-- WHY A DECIDER AND NOT A DELETED CLAUSE.
--   The obvious "fix" is to drop the NOT EXISTS clause that blocks the vehicles. That
--   is a doctrine breach: Zone-C says a fault-reopened itinerary passes the in-depot
--   reassignment gate. So the gate is kept and made to actually function.
--
-- THE LATENCY IS NON-ZERO ON PURPOSE:  indepot_reassign_auto_decide_min = 8 sim-min.
--   A gate that answers instantly is not a gate, it is a comment. Eight sim-minutes is
--   a deliberate, defensible number rather than a round one:
--     * it is BELOW the shortest defer budget (indepot_defer_max_min_critical = 10), so
--       the decision is reached while it still means something instead of always being
--       pre-empted by a timeout;
--     * it is well below the 30-minute pending ceiling, so a row is always decided
--       before it can expire;
--     * it is below tow_retrieval_min (25), so a broken vehicle's paperwork is never
--       what is holding up its tow.
--   It is a policy dial, so an operator can raise it to model a slower yard, or set it
--   to 0 to model an unmanned one -- and if they set it to 0 that is now an explicit,
--   recorded choice rather than an accident of the code.
--
-- THE VERDICTS ARE A POLICY, NOT A COIN FLIP.
--   (twin.ottoq_opportunistic_scan decides by seeded probability. That is right for
--   simulating a technician's mood about an opportunistic top-up. It is NOT right for
--   a doctrine gate, which is why this decider exists separately.)
--     gate_mode = 'deferred_awaiting_tech'  ->  DECLINED
--       The system already answered this question when it deferred: the atomic visit
--       finishes first. Declining records that answer and closes the row. It does NOT
--       approve, and that distinction protects the phase-11 baseline: the exception
--       handler treats an APPROVED row as 'technician_approved' and carries the
--       eviction out immediately, so auto-approving here would cut live work at 8
--       minutes instead of at the 10/45/180-minute bounded budget and would inflate
--       "evictions cutting live work" and "minutes destroyed". Declined and pending
--       are indistinguishable to the exception handler, so the eviction machinery is
--       byte-for-byte unchanged. The ONLY behavioural change is that the readmission
--       cursors are no longer barred.
--     reason in (vehicle_fault, resource_fault, congestion, malfunction, flag) -> APPROVED
--       These are exactly the Zone-C re-openers. The itinerary is legitimately re-opened.
--     everything else (default 'optimization')  ->  DECLINED
--       Zone C forbids re-optimising a vehicle that has already approached. An
--       optimisation-motivated reassignment inside the walls is the precise thing the
--       gate exists to refuse, and refusing it explicitly is a better answer than
--       leaving it unanswered forever.
--
-- IF NEMOTRON IS UNREACHABLE, THIS STILL RESOLVES, AND IT FAILS CONSERVATIVE.
--   Standing doctrine: Nemotron REVIEWS -- approve / hold / reject with a rationale --
--   and NEVER decides. So this decider never waits for it and never reads a verdict
--   from it. It reads payload->'copilot' if the review happens to have landed, records
--   what it said and whether it agreed, and stamps copilot_binding=false. The verdict
--   is computed from policy alone.
--   Fail-safe direction: absence of a review changes nothing, and the verdict set
--   above is already the conservative one -- decline the fault deferral (do not cut
--   live work), decline the optimisation re-route (do not change a frozen plan),
--   approve only where the vehicle is already broken or blocked and the alternative is
--   a deadlock. An advisor that cannot be reached must never be able to stall the
--   depot, and must never be able to authorise a change of plan by its silence.
--
-- NOBODY WAITS FOREVER -- FOUR INDEPENDENT ESCAPE HATCHES.
--   1. the 8-minute auto-decide above;
--   2. the hard expiry sweep below (indepot_reassign_max_pending_min = 30 sim-min),
--      which runs EVEN WHEN THE KILL SWITCH IS OFF -- so switching the decider off can
--      degrade the gate but can never restore the absorbing state;
--   3. the tow-retrieval clock fix in §8 -- a genuinely broken vehicle always leaves,
--      and its exit is never gated on an approval at all;
--   4. the bounded defer budgets already in the exception handler, untouched here.
--
-- DOMAIN DISCIPLINE. Every comparison in this function names its clock domain and
-- compares like with like. Rows carrying payload->>'requested_at_sim' are compared in
-- the SIM domain against p_clock; rows without it (legacy rows, and production rows
-- where there is no sim run) are compared in the REAL domain against now(). No
-- expression ever mixes the two. This also means the 55 stranded legacy rows are
-- resolved on the first tick after this migration, with no backfill script: they are
-- real-domain and hours old.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ottoq_decide_indepot_approvals(
  p_sim_run_id uuid,
  p_depot_id   uuid,
  p_clock      timestamptz
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rec      RECORD;
  v_enabled  numeric;
  v_auto_min numeric;
  v_maxp_min numeric;
  v_verdict  text;
  v_reason   text;
  v_decided  int := 0;
  v_appr     int := 0;
  v_decl     int := 0;
  v_expired  int := 0;
BEGIN
  IF p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;

  v_enabled  := COALESCE(public.ottoq_policy_get(p_sim_run_id,'indepot_reassign_auto_decide_enabled',1),1);
  v_auto_min := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'indepot_reassign_auto_decide_min',8),8), 0);
  v_maxp_min := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'indepot_reassign_max_pending_min',30),30), v_auto_min);

  -- ── STAGE 1: THE VERDICT ──────────────────────────────────────────────────
  IF v_enabled >= 1 THEN
    FOR v_rec IN
      SELECT ap.approval_id,
             ap.vehicle_id,
             COALESCE(ap.payload->>'gate_mode','') AS gate_mode,
             COALESCE(ap.payload->>'reason','')    AS gate_reason,
             ap.payload->'copilot'                 AS copilot
        FROM public.ottoq_ops_approvals ap
       WHERE ap.depot_id      = p_depot_id
         AND ap.status        = 'pending'
         AND ap.approval_type = 'indepot_reassign'
         AND CASE
               WHEN ap.payload->>'requested_at_sim' IS NOT NULL
                 THEN (ap.payload->>'requested_at_sim')::timestamptz
                        <= p_clock - (v_auto_min || ' minutes')::interval   -- SIM  vs SIM
               ELSE ap.requested_at
                        <= now()   - (v_auto_min || ' minutes')::interval   -- REAL vs REAL
             END
       ORDER BY ap.requested_at
       LIMIT 200                     -- bounded per tick; the sweep below is the backstop
    LOOP
      IF v_rec.gate_mode = 'deferred_awaiting_tech' THEN
        v_verdict := 'declined';
        v_reason  := 'atomic_visit_protected_bounded_defer_budget_governs';
      ELSIF v_rec.gate_reason IN ('vehicle_fault','resource_fault','congestion','malfunction','flag') THEN
        v_verdict := 'approved';
        v_reason  := 'zone_c_reopener_' || v_rec.gate_reason;
      ELSE
        v_verdict := 'declined';
        v_reason  := 'zone_c_forbids_reroute_without_malfunction_congestion_or_flag';
      END IF;

      UPDATE public.ottoq_ops_approvals ap
         SET status     = v_verdict,
             -- decided_at is stamped in the SAME domain the row was requested in.
             decided_at = CASE WHEN ap.payload->>'requested_at_sim' IS NOT NULL THEN p_clock ELSE now() END,
             decided_by = 'ottoq_auto_gate:v1',
             payload    = COALESCE(ap.payload,'{}'::jsonb) || jsonb_build_object(
                            'decision', jsonb_build_object(
                              'verdict',                v_verdict,
                              'reason',                 v_reason,
                              'decided_at_sim',         p_clock,
                              'latency_min',            v_auto_min,
                              'decider',                'ottoq_indepot_auto_gate_v1',
                              -- Nemotron REVIEWS, OTTO-Q DECIDES. Recorded, never binding.
                              'copilot_seen',           (v_rec.copilot IS NOT NULL),
                              'copilot_recommendation', COALESCE(v_rec.copilot->>'recommendation','unavailable'),
                              'copilot_binding',        false,
                              'doctrine',               'nemotron_reviews_ottoq_decides'))
       WHERE ap.approval_id = v_rec.approval_id
         AND ap.status      = 'pending';        -- lost-update guard

      IF FOUND THEN
        v_decided := v_decided + 1;
        IF v_verdict = 'approved' THEN v_appr := v_appr + 1; ELSE v_decl := v_decl + 1; END IF;
      END IF;
    END LOOP;
  END IF;

  -- ── STAGE 2: THE BACKSTOP ─────────────────────────────────────────────────
  -- Runs unconditionally, including when the kill switch is off. Nothing this system
  -- does may leave a vehicle holding an unanswerable question forever.
  UPDATE public.ottoq_ops_approvals ap
     SET status     = 'expired',
         decided_at = CASE WHEN ap.payload->>'requested_at_sim' IS NOT NULL THEN p_clock ELSE now() END,
         decided_by = 'ottoq_auto_gate:expired_undecided',
         payload    = COALESCE(ap.payload,'{}'::jsonb) || jsonb_build_object(
                        'decision', jsonb_build_object(
                          'verdict',         'expired',
                          'reason',          'max_pending_exceeded_no_vehicle_waits_forever',
                          'decided_at_sim',  p_clock,
                          'max_pending_min', v_maxp_min,
                          'decider',         'ottoq_indepot_auto_gate_v1'))
   WHERE ap.depot_id      = p_depot_id
     AND ap.status        = 'pending'
     AND ap.approval_type = 'indepot_reassign'
     AND CASE
           WHEN ap.payload->>'requested_at_sim' IS NOT NULL
             THEN (ap.payload->>'requested_at_sim')::timestamptz
                    <= p_clock - (v_maxp_min || ' minutes')::interval       -- SIM  vs SIM
           ELSE ap.requested_at
                    <= now()   - (v_maxp_min || ' minutes')::interval       -- REAL vs REAL
         END;
  GET DIAGNOSTICS v_expired = ROW_COUNT;

  -- ONE summary event per tick. Event-write amplification is the known tick-cost
  -- driver here, so this never emits per row.
  IF v_decided > 0 OR v_expired > 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'indepot_approval_decider',
        p_event_type := 'ottoq.indepot_approvals_decided',
        p_entity_type := 'depot', p_entity_id := p_depot_id, p_depot_id := p_depot_id,
        p_payload := jsonb_build_object(
          'decided', v_decided, 'approved', v_appr, 'declined', v_decl, 'expired', v_expired,
          'auto_decide_min', v_auto_min, 'max_pending_min', v_maxp_min,
          'enabled', (v_enabled >= 1),
          'doctrine','the_gate_must_answer_not_absorb',
          'copilot_role','reviews_never_decides'),
        p_severity := CASE WHEN v_expired > 0 THEN 'warning' ELSE 'info' END,
        p_ingest_source := 'ottoq', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'indepot_approvals_decided summary event dropped: % %', SQLSTATE, SQLERRM;
    END;
  END IF;

  RETURN v_decided + v_expired;

EXCEPTION WHEN OTHERS THEN
  -- House rule 4. This is reached from ottoq_decide_tick. It warns by name and
  -- returns zero; it never propagates.
  RAISE WARNING 'ottoq_decide_indepot_approvals FAILED SAFELY: % %', SQLSTATE, SQLERRM;
  RETURN 0;
END;
$function$;


-- ============================================================================
-- §4  public.ottoq_indepot_reassignment_guard  — SAY WHICH CLOCK THE ROW IS ON
--
-- One table, two writers, two clock domains, same three columns. That is what made
-- the 55 rows both undecidable and unexpirable. The real columns are left exactly as
-- they are -- rewriting their meaning would change every historical row and every
-- dashboard reading them. The sim-domain trio is added ALONGSIDE, in the payload,
-- together with an explicit clock_domain tag so no reader has to guess.
-- This is the ONLY change to this function. All five INSERT paths pick it up for free
-- because they all build their payload from v_pay.
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

  -- ESCAPE HATCH A: policy kill-switch restores the pre-fix auto-allow for all fault traffic.
  IF v_enforce < 1 AND p_reason IN ('resource_fault','vehicle_fault') THEN
    RETURN jsonb_build_object('allowed', true, 'mode', 'legacy_auto_allow', 'recorded', false);
  END IF;

  -- RESOURCE FAULT: the SPACE broke. The vehicle physically cannot stay, so it still moves --
  -- but it is now RECORDED as a gated decision instead of being silently waved through.
  IF p_reason = 'resource_fault' THEN
    INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
           requested_at, decide_after, expires_at, priority, status, decided_at, decided_by)
    VALUES ('indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
            v_pay || jsonb_build_object('gate_mode','resource_fault_auto_reroute',
                                        'auto_reason','space_unusable_vehicle_must_move'),
            now(), now(), now() + interval '30 minutes', 'high', 'approved', now(),
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
      INSERT INTO ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
             requested_at, decide_after, expires_at, priority, status, decided_at, decided_by)
      VALUES ('indepot_reassign', p_vehicle_id, p_sim_run_id, v_veh.home_depot_id,
              v_pay || jsonb_build_object('gate_mode','vehicle_fault_not_in_service'),
              now(), now(), now() + interval '30 minutes', 'normal', 'approved', now(),
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
                        'work_disposition','outstanding_work_must_survive_as_due_and_be_rebooked'),
              now(), now(), now() + interval '30 minutes', 'high', 'approved', now(),
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
-- §5  twin.ottoq_opportunistic_scan  — OWNERSHIP MADE DELIBERATE
--
-- This is the function that COULD have decided the 55 rows: its cursor was never
-- filtered by approval_type. It was stopped only by the clock-domain accident that
-- §4 has just removed -- so without this change, the fix would hand a doctrine gate
-- to a seeded coin flip (it knows exactly two probabilities and neither is a policy).
-- The twin's simulated technician now decides the twin's own approvals only. The
-- in-depot reassignment gate belongs to OTTO-Q.
-- ============================================================================
CREATE OR REPLACE FUNCTION twin.ottoq_opportunistic_scan(p_sim_run_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot uuid; v_seed bigint; v_plan jsonb; v_appr_p numeric; v_gl_p numeric;
  v_rec RECORD; v_n int := 0;
  v_p numeric; v_scan jsonb; v_enact jsonb; v_stall uuid;
BEGIN
  SELECT depot_id, COALESCE(random_seed,42) INTO v_depot, v_seed FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  IF v_depot IS NULL THEN RETURN 0; END IF;
  v_plan := ottoq_feed_plan('service_manifest');
  v_appr_p := COALESCE((v_plan->>'opportunistic_approve_p')::numeric, 0.70);
  v_gl_p := COALESCE((v_plan->>'greenlight_approve_p')::numeric, 0.92);

  -- OTTO-Q owns the decision half
  v_scan := ottoq_plan_opportunistic_charges(p_sim_run_id, v_depot, p_clock, v_seed);
  v_n := COALESCE((v_scan->>'raised')::int, 0);

  -- TWIN: the simulated tech verdict
  FOR v_rec IN
    SELECT ap.approval_id, ap.approval_type, ap.vehicle_id, v.current_soc, COALESCE(v.target_soc,80) AS veh_target
      FROM ottoq_ops_approvals ap JOIN vehicles v ON v.id = ap.vehicle_id
     WHERE ap.depot_id = v_depot AND ap.status = 'pending'
       -- ══════ 0002: OWNERSHIP, MADE EXPLICIT INSTEAD OF ACCIDENTAL ══════
       -- This cursor was never type-filtered. It only knows TWO probabilities (line
       -- below: tech_greenlight vs everything-else), so if it ever reached an
       -- 'indepot_reassign' row it would settle a DOCTRINE GATE on a coin flip.
       -- Until now it was stopped only by an accident -- the real-vs-sim clock
       -- mismatch on decide_after. Migration 0002 removes that accident, so the
       -- filter has to become deliberate. The twin's simulated technician decides
       -- the twin's own questions; OTTO-Q decides the in-depot reassignment gate
       -- (public.ottoq_decide_indepot_approvals).
       AND ap.approval_type IN ('opportunistic_charge','tech_greenlight')
       AND ap.decide_after <= p_clock AND ap.expires_at > p_clock
  LOOP
    v_p := (CASE WHEN v_rec.approval_type = 'tech_greenlight' THEN v_gl_p ELSE v_appr_p END);
    IF ottoq_sim_seeded_random(v_seed, v_rec.approval_id::text || ':decide') < v_p THEN
      UPDATE ottoq_ops_approvals SET status='approved', decided_at=p_clock, decided_by='twin_tech_sim'
       WHERE approval_id = v_rec.approval_id;
      IF v_rec.approval_type = 'opportunistic_charge' THEN
        UPDATE vehicles SET current_state = 'staged_awaiting_service'::vehicle_state,
               last_state_change = p_clock
         WHERE id = v_rec.vehicle_id
           AND current_state IN ('staged_awaiting_service','staged_for_departure','charge_complete_holding');

        v_enact := ottoq_enact_opportunistic_charge(p_sim_run_id, v_rec.vehicle_id,
                     v_rec.current_soc, v_rec.veh_target, p_clock);

        v_stall := NULLIF(v_enact->>'stall_id','')::uuid;
        IF v_stall IS NOT NULL THEN
          UPDATE vehicles SET current_stall_id = v_stall WHERE id = v_rec.vehicle_id;
          UPDATE stalls SET current_vehicle_id = v_rec.vehicle_id, status = 'occupied'
           WHERE id = v_stall;
        END IF;
      END IF;
    ELSE
      UPDATE ottoq_ops_approvals SET status='declined', decided_at=p_clock, decided_by='twin_tech_sim'
       WHERE approval_id = v_rec.approval_id;
    END IF;
  END LOOP;
  -- 0002: same ownership rule for the expiry sweep. An indepot_reassign row is expired
  -- by OTTO-Q's decider on the SIM clock, not here on a column that may be real-domain.
  UPDATE ottoq_ops_approvals SET status='expired'
   WHERE depot_id = v_depot AND status = 'pending'
     AND approval_type IN ('opportunistic_charge','tech_greenlight')
     AND expires_at <= p_clock;
  RETURN v_n;
END; $function$;


-- ============================================================================
-- §6  ottoq.ottoq_readmit_reopened_needs  — DECIDE THE GATE, THEN READ IT
--
-- Two changes. First it now runs the decider before opening its own cursor, so a row
-- that becomes decidable this tick unblocks its vehicle in the SAME tick. Second the
-- exclusion is narrowed (defect c) and the emitted doctrine string is corrected so the
-- function stops contradicting itself in its own audit trail.
-- ============================================================================
CREATE OR REPLACE FUNCTION ottoq.ottoq_readmit_reopened_needs(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rec RECORD;
  v_n int := 0; v_escalated int := 0;
  v_max int; v_dwell numeric; v_attempts int;
  v_legs int := 0; v_planned int := 0;
  v_svc_step text; v_needs_charge boolean;
  v_decided int := 0;   -- 0002: approvals this tick's decider resolved, for the audit line
BEGIN
  IF p_sim_run_id IS NULL OR p_depot_id IS NULL OR p_clock IS NULL THEN RETURN 0; END IF;

  -- ══════════ 0002: DECIDE THE GATE BEFORE YOU READ IT ══════════
  -- Deliberately ABOVE the policy early-return below: the decider must run on every
  -- decide tick even when readmission itself is switched off, otherwise turning
  -- readmission off would silently re-create the absorbing state it exists to drain.
  -- This is the only call site, and decide_tick calls this function unconditionally
  -- once per depot per tick, so the decider runs exactly once per decide tick.
  -- (A later migration should promote this to its own named stage inside
  -- ottoq_decide_tick; that function is ~915 lines and reproducing it here would
  -- break the one-concern-per-file rule for no behavioural gain.)
  -- Self-silencing: a broken decider must never cost us a readmission.
  BEGIN
    v_decided := COALESCE(public.ottoq_decide_indepot_approvals(p_sim_run_id, p_depot_id, p_clock), 0);
  EXCEPTION WHEN OTHERS THEN
    v_decided := 0;
    RAISE WARNING 'indepot approval decider failed safely: % %', SQLSTATE, SQLERRM;
  END;

  IF COALESCE(public.ottoq_policy_get(p_sim_run_id,'reopened_need_readmit_enabled',1),1) < 1
    THEN RETURN 0; END IF;

  -- SAME cap as the old path. Never hit in cert (max observed 2); a need that cannot be
  -- placed ESCALATES TO A FLAG, it never loops.
  v_max   := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'visit_readmit_max_attempts',3),3)::int, 0);
  -- SIM-DOMAIN dwell. exception.flagged_at lives inside config jsonb, so unlike
  -- last_state_change it is NOT clobbered by the BEFORE UPDATE trigger. Verified sim-domain
  -- on live data: range 13:38-16:29 against a sim clock of 13:30-16:29.
  v_dwell := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'reopened_need_dwell_min',5),5), 0);

  FOR v_rec IN
    SELECT vh.id, vh.fleet_operator_id, vh.current_state::text AS vstate,
           COALESCE(vh.config,'{}'::jsonb) AS config, vn.visit_id, vn.atoms
      FROM vehicles vh
      JOIN LATERAL (
        SELECT n.visit_id, n.atoms
          FROM public.ottoq_visit_needs n
         WHERE n.vehicle_id = vh.id
           AND n.status = 'open'
           AND n.meta ? 'reopen'                       -- proves this visit was cut short
           AND (n.sim_run_id = p_sim_run_id OR n.sim_run_id IS NULL)
           AND EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(n.atoms,'[]'::jsonb)) a
                        WHERE lower(COALESCE(a->>'status','pending')) NOT IN ('done','cancelled'))
         ORDER BY n.created_at DESC LIMIT 1
      ) vn ON true
     WHERE vh.home_depot_id = p_depot_id
       AND vh.category = 'autonomous'
       -- the post-fault HOLDING states. Structurally cannot pick up a vehicle that is
       -- charging, washing or being serviced, so it can never re-route work in progress.
       AND vh.current_state IN ('tow_requested','emergency_staged')
       -- the fault must be CLEARED. Same set tow retrieval itself accepts.
       AND COALESCE(vh.config->'exception'->>'status','')
             IN ('auto_staged','technician_approved','retrieved_staged')
       -- a car that cannot drive cannot be sent to a plug.
       AND COALESCE((vh.config->'exception'->>'immobilizing')::boolean, false) = false
       AND COALESCE((vh.config->'exception'->>'flagged_at')::timestamptz, p_clock)
             <= p_clock - make_interval(mins => v_dwell::int)
       -- ══════════ 0002: THE IN-DEPOT REASSIGNMENT GATE, NARROWED ══════════
       -- WAS: "AND NOT EXISTS (any pending indepot_reassign or tech_greenlight)".
       -- That clause and the doctrine string this function emits directly contradicted
       -- each other, and the clause was winning: 27 of the 29 vehicles holding cut-short
       -- work were barred here, by the very approval row that RECORDED the decision to
       -- protect that work. Blocking a resumption on the fault deferral that caused the
       -- interruption is circular.
       -- DOCTRINE CALL (confirmed): a vehicle resuming ITS OWN interrupted work is
       -- completing the ATOMIC visit. The gate governs a CHANGE of plan; finishing the
       -- plan you already had is not one. So the gate is NOT blanket-removed -- it is
       -- still honoured for every pending approval that really is a change of plan
       -- (tech_greenlight, and any indepot_reassign raised for optimisation / congestion
       -- / an operator request) and is ignored ONLY for this vehicle's own fault deferral.
       AND NOT EXISTS (
             SELECT 1 FROM public.ottoq_ops_approvals ap
              WHERE ap.vehicle_id = vh.id
                AND ap.status = 'pending'
                AND ( ap.approval_type = 'tech_greenlight'
                   OR ( ap.approval_type = 'indepot_reassign'
                        AND COALESCE(ap.payload->>'gate_mode','') <> 'deferred_awaiting_tech'
                        AND COALESCE(ap.payload->>'reason','') NOT IN ('vehicle_fault','resource_fault') ) ))
     -- oldest interruption first: the work that has waited longest resumes first.
     ORDER BY COALESCE((vh.config->'exception'->>'flagged_at')::timestamptz, p_clock)
     LIMIT 40
  LOOP
    v_attempts := COALESCE((v_rec.config->'exception'->>'readmit_attempts')::int, 0);

    -- THRASH BOUND: at the cap, FLAG. Never loop.
    IF v_attempts >= v_max THEN
      UPDATE vehicles
         SET config = jsonb_set(jsonb_set(COALESCE(config,'{}'::jsonb),
                        '{exception,status}',            to_jsonb('resume_escalated'::text)),
                        '{exception,resume_escalated_at}', to_jsonb(p_clock))
       WHERE id = v_rec.id;
      v_escalated := v_escalated + 1;
      CONTINUE;
    END IF;

    -- (a) DROP STALE HOLDS. An eviction can leave the vehicle named on the stall it was
    --     thrown out of, which silently withholds a space from the yard.
    UPDATE stalls s
       SET reserved_by = NULL, reservation_expires_at = NULL
     WHERE s.depot_id = p_depot_id AND s.reserved_by = v_rec.id;

    -- (b) THE LEG GOES BACK TO 'planned'. Both enactment cursors draw status='planned'.
    --     Scoped strictly to legs whose OWN booking was interrupted.
    UPDATE public.ottoq_itinerary_legs l
       SET status            = 'planned',
           to_stall_id       = NULL,
           actual_start_sim  = NULL,
           actual_end_sim    = NULL,
           planned_start_sim = p_clock,
           planned_end_sim   = p_clock + make_interval(secs => GREATEST(COALESCE(l.planned_duration_s,900),300)),
           duration_basis    = COALESCE(l.duration_basis,'{}'::jsonb)
                               || jsonb_build_object('replanned_from','interrupted',
                                                     'replanned_at', p_clock,
                                                     'replan_reason','atomic_visit_resume')
     WHERE l.sim_run_id = p_sim_run_id
       AND l.vehicle_id = v_rec.id
       AND l.status = 'active'
       AND l.actual_end_sim IS NULL
       AND EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                    WHERE b.leg_id = l.leg_id AND b.state = 'interrupted');
    GET DIAGNOSTICS v_legs = ROW_COUNT;

    v_needs_charge := EXISTS (
      SELECT 1 FROM jsonb_array_elements(COALESCE(v_rec.atoms,'[]'::jsonb)) a
       WHERE a->>'svc' = 'charge'
         AND lower(COALESCE(a->>'status','pending')) NOT IN ('done','cancelled'));
    v_svc_step := CASE WHEN v_needs_charge THEN 'need_charge' ELSE 'need_service' END;

    -- (c) RE-ADMIT to the HOLDING state the intake cursors already read. No space is
    --     claimed here on purpose -- see the header.
    UPDATE vehicles
       SET current_state = 'staged_awaiting_service'::vehicle_state,
           last_state_change = p_clock,
           config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(COALESCE(config,'{}'::jsonb),
                      '{exception,status}',           to_jsonb('readmitted_resume'::text)),
                      '{exception,readmit_attempts}', to_jsonb(v_attempts + 1)),
                      '{exception,readmitted_at}',    to_jsonb(p_clock)),
                      '{svc_step}',                   to_jsonb(v_svc_step))
     WHERE id = v_rec.id;

    -- (d) NO REVIVABLE LEG -> BUILD ONE from the open needs row.
    IF v_legs = 0 THEN
      BEGIN
        v_planned := COALESCE(public.ottoq_plan_visit_itinerary(p_sim_run_id, v_rec.id, p_clock), 0);
      EXCEPTION WHEN OTHERS THEN
        v_planned := 0;
        RAISE WARNING 'reopened-need re-plan failed for %: % %', v_rec.id, SQLSTATE, SQLERRM;
      END;
    END IF;

    v_n := v_n + 1;
  END LOOP;

  -- ONE summary event per tick (event-write amplification is the known tick-cost driver).
  IF v_n > 0 OR v_escalated > 0 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'readmit_reopened_needs',
        p_event_type := 'ottoq.reopened_need_readmitted',
        p_entity_type := 'depot', p_entity_id := p_depot_id, p_depot_id := p_depot_id,
        p_payload := jsonb_build_object('readmitted', v_n, 'escalated', v_escalated,
                      'max_attempts', v_max, 'dwell_min', v_dwell,
                      'doctrine','reopened_need_is_first_class_demand',
                      -- 0002: the old string claimed no tech approval was required while
                      -- the cursor above demanded exactly that. Both now say the same thing.
                      'approvals_auto_decided', v_decided,
                      'gate','resumption_honours_gate_except_own_fault_deferral',
                      'gate_basis','completing_the_atomic_visit_is_not_a_change_of_plan'),
        p_severity := CASE WHEN v_escalated > 0 THEN 'warning' ELSE 'info' END,
        p_ingest_source := 'ottoq', p_data_source := 'twin', p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'reopened_need_readmitted summary event dropped: % %', SQLSTATE, SQLERRM;
    END;
  END IF;

  RETURN v_n;
EXCEPTION WHEN OTHERS THEN
  -- never allowed to abort ottoq_decide_tick (the leg_type-abort lesson of 2026-08-01).
  RAISE WARNING 'ottoq_readmit_reopened_needs FAILED: % %', SQLSTATE, SQLERRM;
  RETURN 0;
END;
$function$;


-- ============================================================================
-- §7  ottoq.ottoq_readmit_resumed_visits  — THE SECOND BLOCKED PATH
--
-- Identical exclusion, identical narrowing. This path was double-dead: barred by the
-- approval clause AND unreachable because it needs the emergency_staged /
-- retrieved_staged pair that only tow retrieval produces, and tow retrieval fired zero
-- times. §8 revives the other half.
-- ============================================================================
CREATE OR REPLACE FUNCTION ottoq.ottoq_readmit_resumed_visits(p_sim_run_id uuid, p_depot_id uuid, p_clock timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_rec RECORD; v_n int := 0; v_max int; v_attempts int;
  v_legs int := 0; v_planned int := 0; v_svc_step text; v_needs_charge boolean;
BEGIN
  IF p_depot_id IS NULL THEN RETURN 0; END IF;
  v_max := GREATEST(COALESCE(public.ottoq_policy_get(p_sim_run_id,'visit_readmit_max_attempts',3)::int, 3), 0);

  FOR v_rec IN
    SELECT vh.id, vh.fleet_operator_id, vh.current_stall_id,
           COALESCE(vh.config,'{}'::jsonb) AS config,
           vn.visit_id, vn.atoms
      FROM vehicles vh
      JOIN LATERAL (
        SELECT n.visit_id, n.atoms
          FROM public.ottoq_visit_needs n
         WHERE n.vehicle_id = vh.id
           AND n.status = 'open'
           AND n.meta ? 'reopen'                      -- proves this visit was actually cut short
           AND EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(n.atoms,'[]'::jsonb)) a
                        WHERE lower(COALESCE(a->>'status','pending')) NOT IN ('done','cancelled'))
         ORDER BY n.created_at DESC LIMIT 1
      ) vn ON true
     WHERE vh.home_depot_id = p_depot_id
       AND vh.category = 'autonomous'
       AND vh.current_state = 'emergency_staged'
       AND COALESCE(vh.config->'exception'->>'status','') = 'retrieved_staged'
       -- ══════════ 0002: THE IN-DEPOT REASSIGNMENT GATE, NARROWED ══════════
       -- WAS: "AND NOT EXISTS (any pending indepot_reassign or tech_greenlight)".
       -- That clause and the doctrine string this function emits directly contradicted
       -- each other, and the clause was winning: 27 of the 29 vehicles holding cut-short
       -- work were barred here, by the very approval row that RECORDED the decision to
       -- protect that work. Blocking a resumption on the fault deferral that caused the
       -- interruption is circular.
       -- DOCTRINE CALL (confirmed): a vehicle resuming ITS OWN interrupted work is
       -- completing the ATOMIC visit. The gate governs a CHANGE of plan; finishing the
       -- plan you already had is not one. So the gate is NOT blanket-removed -- it is
       -- still honoured for every pending approval that really is a change of plan
       -- (tech_greenlight, and any indepot_reassign raised for optimisation / congestion
       -- / an operator request) and is ignored ONLY for this vehicle's own fault deferral.
       AND NOT EXISTS (
             SELECT 1 FROM public.ottoq_ops_approvals ap
              WHERE ap.vehicle_id = vh.id
                AND ap.status = 'pending'
                AND ( ap.approval_type = 'tech_greenlight'
                   OR ( ap.approval_type = 'indepot_reassign'
                        AND COALESCE(ap.payload->>'gate_mode','') <> 'deferred_awaiting_tech'
                        AND COALESCE(ap.payload->>'reason','') NOT IN ('vehicle_fault','resource_fault') ) ))
  LOOP
    v_attempts := COALESCE((v_rec.config->'exception'->>'readmit_attempts')::int, 0);

    -- ── THRASH BOUND: at the cap, FLAG. Never loop. ──────────────────────────────────────
    IF v_attempts >= v_max THEN
      UPDATE vehicles
         SET config = jsonb_set(jsonb_set(COALESCE(config,'{}'::jsonb),
                        '{exception,status}', to_jsonb('resume_escalated'::text)),
                        '{exception,resume_escalated_at}', to_jsonb(p_clock))
       WHERE id = v_rec.id;
      BEGIN
        PERFORM public.ottoq_record_event(
          p_actor_type := 'ottoq_engine', p_actor_id := 'readmit_resumed_visits',
          p_event_type := 'ottoq.replan_escalated',
          p_entity_type := 'vehicle', p_entity_id := v_rec.id,
          p_fleet_operator_id := v_rec.fleet_operator_id, p_depot_id := p_depot_id,
          p_payload := jsonb_build_object('visit_id', v_rec.visit_id, 'attempts', v_attempts,
                        'max_attempts', v_max, 'reason','readmit_cap_reached',
                        'doctrine','bounded_replan_then_flag'),
          p_severity := 'warning', p_ingest_source := 'twin', p_data_source := 'twin',
          p_sim_run_id := p_sim_run_id);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'readmit escalation stamp dropped: % %', SQLSTATE, SQLERRM;
      END;
      CONTINUE;
    END IF;

    -- ── (a) DROP STALE HOLDS. An eviction can leave the vehicle named on the stall it was
    --        thrown out of. Left in place that stall keeps the vehicle in ZONE C via
    --        ottoq_approach_band.c_hardware, and it silently withholds a space from the yard.
    UPDATE stalls s
       SET reserved_by = NULL, reservation_expires_at = NULL
     WHERE s.depot_id = p_depot_id
       AND s.reserved_by = v_rec.id
       AND s.id IS DISTINCT FROM v_rec.current_stall_id;

    -- ── (b) THE LEG GOES BACK TO 'planned'. 48 of the 52 measured interruptions left their
    --        leg stranded at status='active', and BOTH enactment cursors draw
    --        status='planned' AND to_stall_id IS NULL AND planned_end_sim > clock. Scoped
    --        strictly to legs whose OWN booking was interrupted, so nothing else moves.
    UPDATE public.ottoq_itinerary_legs l
       SET status            = 'planned',
           to_stall_id       = NULL,
           actual_start_sim  = NULL,
           actual_end_sim    = NULL,
           planned_start_sim = p_clock,
           planned_end_sim   = p_clock + make_interval(secs => GREATEST(COALESCE(l.planned_duration_s,900), 300)),
           duration_basis    = COALESCE(l.duration_basis,'{}'::jsonb)
                               || jsonb_build_object('replanned_from','interrupted',
                                                     'replanned_at', p_clock,
                                                     'replan_reason','atomic_visit_resume')
     WHERE l.sim_run_id = p_sim_run_id
       AND l.vehicle_id = v_rec.id
       AND l.status = 'active'
       AND l.actual_end_sim IS NULL
       AND EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
                    WHERE b.leg_id = l.leg_id AND b.state = 'interrupted');
    GET DIAGNOSTICS v_legs = ROW_COUNT;

    v_needs_charge := EXISTS (
      SELECT 1 FROM jsonb_array_elements(COALESCE(v_rec.atoms,'[]'::jsonb)) a
       WHERE a->>'svc' = 'charge'
         AND lower(COALESCE(a->>'status','pending')) NOT IN ('done','cancelled'));
    v_svc_step := CASE WHEN v_needs_charge THEN 'need_charge' ELSE 'need_service' END;

    -- ── (c) RE-ADMIT. The twin owns vehicle state; OTTO-Q is not mutating it here.
    UPDATE vehicles
       SET current_state = 'staged_awaiting_service'::vehicle_state,
           last_state_change = p_clock,
           config = jsonb_set(jsonb_set(jsonb_set(jsonb_set(COALESCE(config,'{}'::jsonb),
                      '{exception,status}',           to_jsonb('readmitted_resume'::text)),
                      '{exception,readmit_attempts}', to_jsonb(v_attempts + 1)),
                      '{exception,readmitted_at}',    to_jsonb(p_clock)),
                      '{svc_step}',                   to_jsonb(v_svc_step))
     WHERE id = v_rec.id;

    -- ── (d) NO REVIVABLE LEG -> BUILD ONE. ottoq_plan_visit_itinerary reads the open needs
    --        row and emits fresh 'planned' legs for every atom that is not done/cancelled.
    --        It early-returns when a planned leg already exists, so calling it after (b)
    --        would be a no-op anyway; gated for clarity and to avoid duplicate legs.
    IF v_legs = 0 THEN
      BEGIN
        v_planned := COALESCE(public.ottoq_plan_visit_itinerary(p_sim_run_id, v_rec.id, p_clock), 0);
      EXCEPTION WHEN OTHERS THEN
        v_planned := 0;
        RAISE WARNING 'resume re-plan failed for %: % %', v_rec.id, SQLSTATE, SQLERRM;
      END;
    ELSE
      v_planned := 0;
    END IF;

    v_n := v_n + 1;
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type := 'ottoq_engine', p_actor_id := 'readmit_resumed_visits',
        p_event_type := 'ottoq.visit_resume_readmitted',
        p_entity_type := 'vehicle', p_entity_id := v_rec.id,
        p_fleet_operator_id := v_rec.fleet_operator_id, p_depot_id := p_depot_id,
        p_payload := jsonb_build_object(
          'visit_id', v_rec.visit_id,
          'from_state','emergency_staged', 'to_state','staged_awaiting_service',
          'legs_replanned', v_legs, 'legs_created', v_planned,
          'needs_charge', v_needs_charge, 'svc_step', v_svc_step,
          'readmit_attempts', v_attempts + 1, 'max_attempts', v_max,
          'doctrine','atomic_visit_resume_not_reroute',
          'gate','indepot_reassignment_gate_narrowed_own_fault_deferral_ignored'),
        p_severity := 'info', p_ingest_source := 'twin', p_data_source := 'twin',
        p_sim_run_id := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'visit_resume_readmitted audit event dropped: % %', SQLSTATE, SQLERRM;
    END;
  END LOOP;

  RETURN v_n;
EXCEPTION WHEN OTHERS THEN
  -- Never allowed to abort the twin tick (cf. the leg_type abort root cause).
  RAISE WARNING 'ottoq_readmit_resumed_visits FAILED: % %', SQLSTATE, SQLERRM;
  RETURN 0;
END;
$function$;


-- ============================================================================
-- §8  twin.ottoq_sim_vehicle_exception_handler  — ONE FACT, AND A TOW THAT ARRIVES
--
-- (b) The technician flip and the approval row are now written together -- both or
--     neither. The auto_staged path is resolved too, rather than left asking
--     permission for something that has already happened.
-- PAIRED FIX: tow retrieval compared a REAL-clock column to the SIM clock and
--     therefore never fired. Both stamps and both comparisons now name their domain.
-- Plus a named top-level safety net (house rule 4).
-- ============================================================================
CREATE OR REPLACE FUNCTION twin.ottoq_sim_vehicle_exception_handler(p_depot_id uuid, p_sim_clock timestamp with time zone, p_sim_run_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_seed bigint; v_rec RECORD; v_sev text; v_n int := 0;
  v_per_tick numeric;
  v_approve_delay_min numeric := 12; v_stall uuid;
  v_plan jsonb;
  v_gate jsonb; v_mid boolean; v_ends timestamptz; v_remaining numeric;
  v_stall_code text; v_defer_max numeric; v_resume_reason text; v_evict jsonb;
  v_immob boolean; v_immob_share numeric; v_defer_max_crit numeric;
  v_booking uuid; v_starts timestamptz; v_reopened int; v_budget numeric;
  v_bk_hi timestamptz; v_purpose text;
  v_roll numeric; v_si_share numeric; v_si boolean; v_fault_class text;
  v_defer_max_immob numeric; v_defer_class text;
  v_appr_n int := 0;      -- 0002: approval rows resolved alongside a technician decision
  v_tow_min numeric;      -- 0002: tow-retrieval dwell, compared in an EXPLICIT clock domain
BEGIN
  v_seed := abs(hashtextextended(p_depot_id::text || p_sim_clock::text || 'vexc', 17));
  v_per_tick  := COALESCE(ottoq_policy_get(p_sim_run_id, 'vehicle_fault_rate_per_tick', 0.004), 0.004);
  v_defer_max := COALESCE(ottoq_policy_get(p_sim_run_id, 'indepot_defer_max_min', 45), 45);
  -- A critical-but-mobile fault is deferred on a MUCH shorter budget than a major one.
  v_defer_max_crit := COALESCE(ottoq_policy_get(p_sim_run_id, 'indepot_defer_max_min_critical', 10), 10);
  -- An IMMOBILIZING but charge-safe fault gets the longest bounded budget: the vehicle is not
  -- going anywhere without a tow, so the plug may as well finish. BOUNDED -- never open-ended.
  v_defer_max_immob := COALESCE(ottoq_policy_get(p_sim_run_id, 'indepot_defer_max_min_immobilizing', 180), 180);
  -- TUNABLE ASSUMPTION, not a measured fact: the share of CRITICAL faults that immobilize the
  -- vehicle. In production this is the OEM fault code's drivable/not-drivable bit.
  v_immob_share := COALESCE(ottoq_policy_get(p_sim_run_id, 'vehicle_fault_immobilizing_share', 0.35), 0.35);
  -- ══════════════ P2: FAULT CLASS TAXONOMY ══════════════
  -- `immobilizing` and `service_incompatible` are DERIVED from ONE roll against a documented
  -- class taxonomy, not rolled independently -- physics correlates them, and in production this
  -- is a single lookup from the OEM fault code. Ordering the classes by cumulative share on the
  -- SAME roll key ('immob:'||id) that phase 10/11 used means the immobilizing bit is
  -- BIT-IDENTICAL to before and service_incompatible is a STRICT SUBSET of it -- so any change
  -- in evictions is provably the narrowed predicate, not a re-drawn seed.
  --   roll <  0.099  hv_battery_thermal      immobilizing=Y  service_incompatible=Y
  --   roll <  0.18   charge_system_fault     immobilizing=Y  service_incompatible=Y
  --   roll <  0.282  drive_actuator_failure  immobilizing=Y  service_incompatible=N
  --   roll <  0.35   steering_brake_fault    immobilizing=Y  service_incompatible=N
  --   roll <  0.65   compute_stack_fault     immobilizing=N  service_incompatible=N
  --   else           sensor_suite_fault      immobilizing=N  service_incompatible=N
  v_si_share := LEAST(COALESCE(ottoq_policy_get(p_sim_run_id,'vehicle_fault_service_incompatible_share',0.18),0.18),
                      v_immob_share);

  FOR v_rec IN
    SELECT id, current_state, current_stall_id, fleet_operator_id, config, last_state_change
      FROM vehicles
     WHERE home_depot_id = p_depot_id AND category = 'autonomous'
       AND current_state IN ('charging_dcfc','charging_l2','in_wash_bay','in_detail_bay',
                             'in_service_bay','charge_complete_holding','staged_awaiting_service')
       AND NOT jsonb_exists(config, 'exception')
  LOOP
    IF ottoq_sim_seeded_random(v_seed, 'roll:'||v_rec.id::text) < v_per_tick THEN
      v_sev := CASE WHEN ottoq_sim_seeded_random(v_seed,'sev:'||v_rec.id::text) < 0.35 THEN 'critical' ELSE 'major' END;
      v_roll := ottoq_sim_seeded_random(v_seed,'immob:'||v_rec.id::text);
      -- Only a critical fault can be immobilizing (unchanged predicate, unchanged draw).
      v_immob := (v_sev = 'critical') AND v_roll < v_immob_share;
      v_si    := (v_sev = 'critical') AND v_roll < v_si_share;
      v_fault_class := CASE
        WHEN v_sev <> 'critical'                THEN 'non_critical_' || v_sev
        WHEN v_roll < v_si_share * 0.55         THEN 'hv_battery_thermal'
        WHEN v_roll < v_si_share                THEN 'charge_system_fault'
        WHEN v_roll < v_si_share + (v_immob_share - v_si_share) * 0.6 THEN 'drive_actuator_failure'
        WHEN v_roll < v_immob_share             THEN 'steering_brake_fault'
        WHEN v_roll < 0.65                      THEN 'compute_stack_fault'
        ELSE 'sensor_suite_fault' END;

      v_mid := v_rec.current_state IN ('in_wash_bay','in_detail_bay','in_service_bay','charging_dcfc','charging_l2');

      -- Remaining work for the AUDIT STAMP. Booking window first, config second, else unknown.
      v_ends := NULL; v_starts := NULL; v_booking := NULL;
      SELECT b.booking_id, lower(b.during), upper(b.during), b.purpose INTO v_booking, v_starts, v_ends, v_purpose
        FROM ottoq_stall_bookings b
       WHERE b.vehicle_id = v_rec.id AND b.sim_run_id = p_sim_run_id
         AND b.state IN ('held','active') AND b.during @> p_sim_clock
       ORDER BY upper(b.during) DESC LIMIT 1;
      IF v_ends IS NULL THEN
        v_ends := NULLIF(v_rec.config->>'service_ends_at','')::timestamptz;
      END IF;
      v_remaining := CASE WHEN v_ends IS NULL THEN NULL
                          ELSE round(EXTRACT(epoch FROM (v_ends - p_sim_clock))::numeric / 60.0, 2) END;

      -- GATE THE YANK. Both bits are on the wire now, so the guard can tell "cannot drive"
      -- apart from "the service cannot continue here".
      IF v_mid THEN
        v_gate := ottoq_indepot_reassignment_guard(
                    v_rec.id, p_sim_run_id, 'vehicle_fault',
                    jsonb_build_object('severity', v_sev, 'from_state', v_rec.current_state::text,
                                       'immobilizing', v_immob,
                                       'service_incompatible', v_si,
                                       'fault_class', v_fault_class,
                                       'service_ends_at', v_ends, 'min_remaining', v_remaining,
                                       'source','vehicle_exception_handler'));
      ELSE
        v_gate := jsonb_build_object('allowed', true, 'mode', 'not_in_service');
      END IF;

      IF NOT COALESCE((v_gate->>'allowed')::boolean, true) THEN
        -- DEFERRED: the vehicle STAYS in its bay and finishes the atomic visit.
        UPDATE vehicles
           SET config = jsonb_set(COALESCE(config,'{}'::jsonb), '{exception}',
                 jsonb_build_object('type','vehicle_fault','severity',v_sev,'flagged_at',p_sim_clock,
                   'status','deferred_awaiting_tech','gate_mode', v_gate->>'mode',
                   'defer_class', v_gate->>'defer_class', 'immobilizing', v_immob,
                   'service_incompatible', COALESCE((v_gate->>'service_incompatible')::boolean, v_si),
                   'fault_class', v_fault_class,
                   'approval_id', v_gate->>'approval_id', 'service_ends_at', v_ends,
                   'deferred_from_state', v_rec.current_state::text,
                   'deferred_with_min_remaining', v_remaining))
         WHERE id = v_rec.id;
        PERFORM ottoq_record_event(
          p_actor_type:='ottoq_engine', p_actor_id:='vehicle_exception_handler',
          p_event_type:='ottoq.bay_eviction_deferred',
          p_entity_type:='vehicle', p_entity_id:=v_rec.id, p_fleet_operator_id:=v_rec.fleet_operator_id,
          p_depot_id:=p_depot_id,
          p_payload:= jsonb_build_object('severity',v_sev,'from_state',v_rec.current_state::text,
            'gate_mode', v_gate->>'mode', 'defer_class', v_gate->>'defer_class',
            'immobilizing', v_immob, 'service_incompatible', COALESCE((v_gate->>'service_incompatible')::boolean, v_si),
            'fault_class', v_fault_class, 'approval_id', v_gate->>'approval_id',
            'min_remaining', v_remaining, 'disposition','work_protected_eviction_deferred'),
          p_severity:='warning', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
        v_n := v_n + 1;
        CONTINUE;
      END IF;

      -- ALLOWED: perform the yank, now fully audited.
      SELECT stall_code INTO v_stall_code FROM stalls WHERE id = v_rec.current_stall_id;

      -- ══════════ THE WORK MUST SURVIVE AS DUE, AND MUST BE RE-BOOKED ══════════
      v_reopened := 0;
      IF v_mid THEN
        v_reopened := public.ottoq_reopen_visit_atoms(
                        v_rec.id,
                        ottoq.ottoq_state_service_atoms(v_rec.current_state::text),
                        COALESCE(v_starts, v_rec.last_state_change),
                        'vehicle_fault_eviction');
        IF v_booking IS NOT NULL THEN
          UPDATE ottoq_stall_bookings b
             SET state='interrupted', released_at=p_sim_clock,
                 release_reason='vehicle_fault_eviction',
                 during = tstzrange(lower(b.during),
                            GREATEST(lower(b.during) + interval '1 second',
                                     LEAST(upper(b.during), p_sim_clock)), '[)')
           WHERE b.booking_id = v_booking AND b.state IN ('held','active');
          PERFORM ottoq.ottoq_emit_booking_interrupted(
            p_sim_run_id, p_depot_id, v_booking, v_rec.id, v_rec.current_stall_id,
            v_purpose, p_sim_clock, 'vehicle_fault_eviction',
            EXTRACT(epoch FROM (v_ends - v_starts))::numeric,
            EXTRACT(epoch FROM (p_sim_clock - v_starts))::numeric,
            v_reopened, 0, 'vehicle_exception_handler');
        END IF;
        PERFORM twin.ottoq_demand_rebook_after_eviction(
                  p_sim_run_id, p_depot_id, v_rec.id, v_rec.fleet_operator_id,
                  p_sim_clock, 'vehicle_fault_eviction', v_remaining, v_purpose,
                  v_rec.current_state::text);
      END IF;

      v_evict := jsonb_build_object('at', p_sim_clock, 'cause','vehicle_fault','severity',v_sev,
                   'stall_code', v_stall_code, 'stall_id', v_rec.current_stall_id,
                   'from_state', v_rec.current_state::text,
                   'interrupted_with_min_remaining', v_remaining,
                   'gate_mode', v_gate->>'mode', 'gate_approval_id', v_gate->>'approval_id',
                   'immobilizing', v_immob,
                   'service_incompatible', COALESCE((v_gate->>'service_incompatible')::boolean, v_si),
                   'evict_basis', v_gate->>'evict_basis', 'fault_class', v_fault_class,
                   'atoms_reopened', v_reopened,
                   'booking_closed', v_booking, 'was_mid_service', v_mid);

      IF v_rec.current_stall_id IS NOT NULL THEN
        UPDATE stalls SET current_vehicle_id = NULL WHERE id = v_rec.current_stall_id;
      END IF;
      UPDATE vehicles
         SET current_state = 'tow_requested'::vehicle_state, current_stall_id = NULL, last_state_change = p_sim_clock,
             config = jsonb_set(
                        jsonb_set(COALESCE(config,'{}'::jsonb), '{exception}',
                          jsonb_build_object('type','vehicle_fault','severity',v_sev,'flagged_at',p_sim_clock,
                            -- 0002: SIM-DOMAIN tow stamp. vehicles.last_state_change is
                            -- overwritten with NOW() by the BEFORE UPDATE trigger on
                            -- vehicles, so it can never be compared to a sim clock.
                            'tow_requested_at', p_sim_clock,
                            'immobilizing', v_immob, 'service_incompatible', v_si, 'fault_class', v_fault_class,
                            'status', CASE WHEN v_sev='critical' THEN 'auto_staged' ELSE 'pending_approval' END)),
                        '{bay_eviction}', v_evict)
       WHERE id = v_rec.id;

      PERFORM ottoq_record_event(
        p_actor_type:='ottoq_engine', p_actor_id:='vehicle_exception_handler',
        p_event_type:= CASE WHEN v_sev='critical' THEN 'vehicle.exception_auto_staged' ELSE 'vehicle.exception_proposed' END,
        p_entity_type:='vehicle', p_entity_id:=v_rec.id, p_fleet_operator_id:=v_rec.fleet_operator_id, p_depot_id:=p_depot_id,
        p_payload:= jsonb_build_object('severity',v_sev,'from_state',v_rec.current_state::text,
          'disposition', CASE WHEN v_sev='critical' THEN 'auto_offline_override' ELSE 'staged_pending_technician_approval' END,
          'immobilizing', v_immob, 'service_incompatible', v_si, 'fault_class', v_fault_class,
          'gate_mode', v_gate->>'mode'),
        p_severity:= CASE WHEN v_sev='critical' THEN 'critical' ELSE 'warning' END,
        p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);

      IF v_mid THEN
        PERFORM ottoq_record_event(
          p_actor_type:='ottoq_engine', p_actor_id:='vehicle_exception_handler',
          p_event_type:='ottoq.bay_eviction',
          p_entity_type:='vehicle', p_entity_id:=v_rec.id, p_fleet_operator_id:=v_rec.fleet_operator_id,
          p_depot_id:=p_depot_id, p_payload:= v_evict,
          p_severity:= CASE WHEN v_sev='critical' THEN 'critical' ELSE 'warning' END,
          p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
      END IF;
      v_n := v_n + 1;
    END IF;
  END LOOP;

  -- DEFERRED RESUME -- THE ESCAPE HATCH. A deferred fault is never forgotten and never
  -- deadlocks: it is carried out as soon as the protected work is done, the vehicle has left
  -- the space on its own, a technician approved, or the bounded defer budget expires.
  FOR v_rec IN
    SELECT id, current_state, current_stall_id, fleet_operator_id, config, last_state_change
      FROM vehicles
     WHERE home_depot_id = p_depot_id AND category = 'autonomous'
       AND config->'exception'->>'status' = 'deferred_awaiting_tech'
  LOOP
    v_ends       := NULLIF(v_rec.config->'exception'->>'service_ends_at','')::timestamptz;
    v_mid        := v_rec.current_state IN ('in_wash_bay','in_detail_bay','in_service_bay','charging_dcfc','charging_l2');
    v_sev        := COALESCE(v_rec.config->'exception'->>'severity','major');
    v_defer_class:= COALESCE(v_rec.config->'exception'->>'defer_class','');
    v_immob      := COALESCE((v_rec.config->'exception'->>'immobilizing')::boolean, false);
    v_fault_class:= v_rec.config->'exception'->>'fault_class';
    -- THREE BUDGETS, ALL BOUNDED. Immobilizing-but-charge-safe gets the longest one because the
    -- vehicle cannot leave without a tow anyway; it still expires, so nothing deadlocks.
    v_budget     := CASE WHEN v_defer_class = 'immobilizing_awaiting_tow' THEN v_defer_max_immob
                         WHEN v_sev='critical' THEN v_defer_max_crit
                         ELSE v_defer_max END;
    v_resume_reason := NULL;
    IF NOT v_mid THEN
      v_resume_reason := 'left_service_state';
    ELSIF v_ends IS NOT NULL AND v_ends <= p_sim_clock THEN
      v_resume_reason := 'service_window_complete';
    ELSIF EXISTS (SELECT 1 FROM ottoq_ops_approvals a
                   WHERE a.approval_id = NULLIF(v_rec.config->'exception'->>'approval_id','')::uuid
                     AND a.status = 'approved') THEN
      v_resume_reason := 'technician_approved';
    ELSIF (v_rec.config->'exception'->>'flagged_at')::timestamptz
            <= p_sim_clock - (v_budget || ' minutes')::interval THEN
      v_resume_reason := CASE WHEN v_defer_class = 'immobilizing_awaiting_tow' THEN 'immobilizing_defer_budget_expired'
                              WHEN v_sev='critical' THEN 'critical_defer_budget_expired'
                              ELSE 'defer_budget_expired' END;
    END IF;

    IF v_resume_reason IS NULL THEN CONTINUE; END IF;

    SELECT stall_code INTO v_stall_code FROM stalls WHERE id = v_rec.current_stall_id;

    -- Work survives here too: if the vehicle is STILL mid-service when the deferral is
    -- carried out, the eviction IS cutting live work and must re-plan AND re-book it.
    v_reopened := 0; v_booking := NULL; v_starts := NULL; v_bk_hi := NULL; v_purpose := NULL;
    v_remaining := 0;
    IF v_mid THEN
      SELECT b.booking_id, lower(b.during), upper(b.during), b.purpose INTO v_booking, v_starts, v_bk_hi, v_purpose
        FROM ottoq_stall_bookings b
       WHERE b.vehicle_id = v_rec.id AND b.sim_run_id = p_sim_run_id
         AND b.state IN ('held','active') AND b.during @> p_sim_clock
       ORDER BY upper(b.during) DESC LIMIT 1;
      -- ══════════ P2 MEASUREMENT FIX: STOP STAMPING ZERO ══════════
      -- This path hardcoded `interrupted_with_min_remaining = 0`, which is why
      -- `deferred_awaiting_tech` appeared to destroy 0.00 minutes. MEASURED (phase 11,
      -- reconstructed from each deferral's own min_remaining minus elapsed defer time):
      -- 24 of the 45 deferred resumes closed a LIVE booking and really destroyed ~1,359.78
      -- minutes -- 2.1x the immobilizing path's 641.30, invisible because of this constant.
      -- The window upper bound is read BEFORE the clipping UPDATE below, so this is the true
      -- remaining work at the moment the space was taken away.
      v_remaining := GREATEST(
        COALESCE(round(EXTRACT(epoch FROM (COALESCE(v_bk_hi, v_ends) - p_sim_clock))::numeric / 60.0, 2), 0), 0);
      v_reopened := public.ottoq_reopen_visit_atoms(
                      v_rec.id,
                      ottoq.ottoq_state_service_atoms(v_rec.current_state::text),
                      COALESCE(v_starts, v_rec.last_state_change),
                      'vehicle_fault_eviction_deferred_resumed');
      IF v_booking IS NOT NULL THEN
        UPDATE ottoq_stall_bookings b
           SET state='interrupted', released_at=p_sim_clock,
               release_reason='vehicle_fault_eviction_deferred_resumed',
               during = tstzrange(lower(b.during),
                          GREATEST(lower(b.during) + interval '1 second',
                                   LEAST(upper(b.during), p_sim_clock)), '[)')
         WHERE b.booking_id = v_booking AND b.state IN ('held','active');
        PERFORM ottoq.ottoq_emit_booking_interrupted(
          p_sim_run_id, p_depot_id, v_booking, v_rec.id, v_rec.current_stall_id,
          v_purpose, p_sim_clock, 'vehicle_fault_eviction_deferred_resumed',
          EXTRACT(epoch FROM (v_bk_hi - v_starts))::numeric,
          EXTRACT(epoch FROM (p_sim_clock - v_starts))::numeric,
          v_reopened, 0, 'vehicle_exception_handler_deferred_resume');
      END IF;
      PERFORM twin.ottoq_demand_rebook_after_eviction(
                p_sim_run_id, p_depot_id, v_rec.id, v_rec.fleet_operator_id,
                p_sim_clock, 'vehicle_fault_eviction_deferred_resumed', v_remaining, v_purpose,
                v_rec.current_state::text);
    END IF;

    v_evict := jsonb_build_object('at', p_sim_clock, 'cause','vehicle_fault_deferred_resumed',
                 'severity', v_sev, 'stall_code', v_stall_code, 'stall_id', v_rec.current_stall_id,
                 'from_state', v_rec.current_state::text, 'resume_reason', v_resume_reason,
                 'gate_mode','deferred_awaiting_tech',
                 'defer_class', v_defer_class, 'immobilizing', v_immob, 'fault_class', v_fault_class,
                 'defer_budget_min', v_budget,
                 'deferred_at', v_rec.config->'exception'->>'flagged_at',
                 'atoms_reopened', v_reopened, 'booking_closed', v_booking,
                 'interrupted_with_min_remaining', v_remaining, 'was_mid_service', v_mid);

    IF v_rec.current_stall_id IS NOT NULL THEN
      UPDATE stalls SET current_vehicle_id = NULL WHERE id = v_rec.current_stall_id;
    END IF;
    UPDATE vehicles
       SET current_state = 'tow_requested'::vehicle_state, current_stall_id = NULL,
           last_state_change = p_sim_clock,
           config = jsonb_set(
                      jsonb_set(
                        jsonb_set(config, '{exception,status}',
                          to_jsonb(CASE WHEN v_sev='critical' THEN 'auto_staged' ELSE 'pending_approval' END)),
                        -- 0002: the deferred path reaches tow_requested LATER than
                        -- flagged_at, so it needs its own sim-domain stamp too.
                        '{exception,tow_requested_at}', to_jsonb(p_sim_clock)),
                      '{bay_eviction}', v_evict)
     WHERE id = v_rec.id;

    PERFORM ottoq_record_event(
      p_actor_type:='ottoq_engine', p_actor_id:='vehicle_exception_handler',
      p_event_type:='ottoq.bay_eviction',
      p_entity_type:='vehicle', p_entity_id:=v_rec.id, p_fleet_operator_id:=v_rec.fleet_operator_id,
      p_depot_id:=p_depot_id, p_payload:= v_evict,
      p_severity:='warning', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
    v_n := v_n + 1;
  END LOOP;

  FOR v_rec IN
    SELECT id, fleet_operator_id FROM vehicles
     WHERE home_depot_id = p_depot_id AND category = 'autonomous'
       AND config->'exception'->>'status' = 'pending_approval'
       AND (config->'exception'->>'flagged_at')::timestamptz <= p_sim_clock - (v_approve_delay_min || ' minutes')::interval
  LOOP
    UPDATE vehicles SET config = jsonb_set(config, '{exception,status}', to_jsonb('technician_approved'::text))
     WHERE id = v_rec.id;

    -- ══════════ 0002 (b): "TECHNICIAN APPROVED" IS NOW ONE FACT ══════════
    -- This loop used to flip config.exception.status to 'technician_approved' and stop
    -- there, leaving the matching ottoq_ops_approvals row sitting at 'pending' forever.
    -- The system therefore held two contradictory beliefs about the same event: the
    -- vehicle record said a technician had approved, the approvals ledger said nobody
    -- had. Both writes are now in the SAME statement sequence inside the SAME plpgsql
    -- transaction -- both happen or neither does.
    -- CLOCK DOMAIN: decided_at is stamped in the SAME domain the row was requested in
    -- (§4 tags every new row; rows without the tag are real-domain). The decision itself
    -- was reached on the sim clock -- config.exception.flagged_at is sim-domain -- so the
    -- sim instant is always recorded in the payload as well, in both branches.
    UPDATE ottoq_ops_approvals ap
       SET status      = 'approved',
           decided_at  = CASE WHEN ap.payload->>'requested_at_sim' IS NOT NULL
                              THEN p_sim_clock ELSE now() END,
           decided_by  = 'auto_gate:technician_approved_offline_inspection',
           payload     = COALESCE(ap.payload,'{}'::jsonb) || jsonb_build_object(
                           'decision', jsonb_build_object(
                             'verdict','approved',
                             'reason','technician_approved_vehicle_offline_same_transaction',
                             'decided_at_sim', p_sim_clock,
                             'decider','twin.ottoq_sim_vehicle_exception_handler'))
     WHERE ap.vehicle_id    = v_rec.id
       AND ap.status        = 'pending'
       AND ap.approval_type = 'indepot_reassign';
    GET DIAGNOSTICS v_appr_n = ROW_COUNT;

    PERFORM ottoq_record_event(
      p_actor_type:='command_center_operator', p_actor_id:='technician_in_loop', p_event_type:='vehicle.technician_approved',
      p_entity_type:='vehicle', p_entity_id:=v_rec.id, p_fleet_operator_id:=v_rec.fleet_operator_id, p_depot_id:=p_depot_id,
      p_payload:= jsonb_build_object('action','approved_offline_inspection',
                                     'approvals_resolved', v_appr_n),
      p_severity:='info', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
    v_n := v_n + 1;
  END LOOP;

  -- ══════════ 0002 (b2): THE auto_staged PATH ══════════
  -- A 'critical' fault sets config.exception.status straight to 'auto_staged' -- the
  -- system took the vehicle offline WITHOUT waiting for a human. If a pending approval
  -- row is still sitting there asking permission, that row is asking about something
  -- that has already happened. RESOLVE IT (rather than never creating it): the request
  -- was real, it was audited, and the ledger should record how it ended. Recording it as
  -- approved-because-superseded keeps the audit trail honest and stops the row from
  -- barring the vehicle from ever resuming its outstanding work.
  -- The vehicle is already in tow_requested here, so this can never cut live work: the
  -- deferred-resume loop above only ever looks at 'deferred_awaiting_tech' vehicles.
  UPDATE ottoq_ops_approvals ap
     SET status     = 'approved',
         decided_at = CASE WHEN ap.payload->>'requested_at_sim' IS NOT NULL
                           THEN p_sim_clock ELSE now() END,
         decided_by = 'auto_gate:auto_staged_supersedes_request',
         payload    = COALESCE(ap.payload,'{}'::jsonb) || jsonb_build_object(
                        'decision', jsonb_build_object(
                          'verdict','approved',
                          'reason','vehicle_already_auto_staged_request_is_moot',
                          'decided_at_sim', p_sim_clock,
                          'decider','twin.ottoq_sim_vehicle_exception_handler'))
   WHERE ap.status = 'pending'
     AND ap.approval_type = 'indepot_reassign'
     AND EXISTS (SELECT 1 FROM vehicles v
                  WHERE v.id = ap.vehicle_id
                    AND v.home_depot_id = p_depot_id
                    AND v.category = 'autonomous'
                    AND v.current_state = 'tow_requested'
                    AND v.config->'exception'->>'status' = 'auto_staged');

  -- (3) TOW RETRIEVAL -- never closed, never gated. A genuinely broken vehicle always leaves.
  --
  -- ══════════ 0002: THE CLOCK-DOMAIN BUG THAT KEPT BROKEN VEHICLES PINNED ══════════
  -- WAS: "last_state_change <= p_sim_clock - tow_retrieval_min".
  -- vehicles.last_state_change is REAL-clock: the BEFORE UPDATE trigger on vehicles
  -- overwrites it with NOW() on every state change, so whatever a caller assigns is
  -- discarded. p_sim_clock is SIM-clock. Comparing them is meaningless, and in the
  -- measured run it was never true -- tow retrieval fired ZERO times, which is why
  -- ottoq.ottoq_readmit_resumed_visits (which needs the emergency_staged /
  -- retrieved_staged pair that ONLY tow retrieval produces) was double-dead.
  -- This is the 7th instance of this bug class in this codebase.
  --
  -- NOW: every comparison names its domain and compares like with like.
  --   SIM  branch: exception.tow_requested_at (stamped above, sim) vs p_sim_clock (sim).
  --                Falls back to exception.flagged_at, also sim-domain, for rows that
  --                entered tow_requested before this migration.
  --   REAL branch: rows with neither stamp (legacy, or written by some other path) are
  --                compared last_state_change (real) vs now() (real). Without this a
  --                legacy vehicle would wait forever for a stamp that will never be
  --                written, because nothing updates it once it is already tow_requested.
  v_tow_min := GREATEST(COALESCE(ottoq_policy_get(p_sim_run_id,'tow_retrieval_min',25),25), 0);
  FOR v_rec IN
    SELECT vh.id, vh.fleet_operator_id FROM vehicles vh
     WHERE vh.home_depot_id = p_depot_id AND vh.category = 'autonomous'
       AND vh.current_state = 'tow_requested'
       AND COALESCE(vh.config->'exception'->>'status','auto_staged') IN ('auto_staged','technician_approved')
       AND CASE
             WHEN COALESCE(NULLIF(vh.config->'exception'->>'tow_requested_at',''),
                           NULLIF(vh.config->'exception'->>'flagged_at','')) IS NOT NULL
               THEN COALESCE(NULLIF(vh.config->'exception'->>'tow_requested_at','')::timestamptz,
                             NULLIF(vh.config->'exception'->>'flagged_at','')::timestamptz)
                      <= p_sim_clock - (v_tow_min || ' minutes')::interval    -- SIM  vs SIM
             ELSE vh.last_state_change
                      <= now()       - (v_tow_min || ' minutes')::interval    -- REAL vs REAL
           END
  LOOP
    v_plan := ottoq_stage_after_tow_retrieval(v_rec.id, p_sim_run_id, p_depot_id, p_sim_clock);
    v_stall := NULLIF(v_plan->>'stall_id','')::uuid;
    IF v_stall IS NOT NULL THEN
      UPDATE vehicles
         SET current_state = 'emergency_staged'::vehicle_state, current_stall_id = v_stall,
             last_state_change = p_sim_clock,
             config = jsonb_set(COALESCE(config,'{}'::jsonb), '{exception,status}', to_jsonb('retrieved_staged'::text))
       WHERE id = v_rec.id;
      UPDATE stalls SET current_vehicle_id = v_rec.id, status = 'occupied' WHERE id = v_stall;
      PERFORM ottoq_record_event(
        p_actor_type:='ottoq_engine', p_actor_id:='incident_triage',
        p_event_type:='vehicle.tow_retrieved_staged',
        p_entity_type:='vehicle', p_entity_id:=v_rec.id, p_fleet_operator_id:=v_rec.fleet_operator_id,
        p_depot_id:=p_depot_id,
        p_payload:=jsonb_build_object('reserved_stall_id', v_stall),
        p_severity:='info', p_ingest_source:='twin', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
      v_n := v_n + 1;
    END IF;
  END LOOP;

  -- (4) SWEEPER
  UPDATE stalls s SET current_vehicle_id = NULL, status = 'available'
   WHERE s.depot_id = p_depot_id AND s.stall_type = 'staging' AND s.current_vehicle_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM vehicles v WHERE v.id = s.current_vehicle_id AND v.current_stall_id = s.id);

  -- (5) RE-ADMIT TO THE INTERRUPTED VISIT  --  PHASE 11.
  v_n := v_n + COALESCE(ottoq.ottoq_readmit_resumed_visits(p_sim_run_id, p_depot_id, p_sim_clock), 0);

  RETURN v_n;

-- 0002 (house rule 4): this function is reached from twin.ottoq_world_advance and,
-- through it, from the tick. It had no handler of its own -- an error propagated out and
-- the caller's blanket handler reported it as an anonymous twin failure. It now fails
-- loudly and by name, and can never take a tick down with it.
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'twin.ottoq_sim_vehicle_exception_handler FAILED SAFELY: % %', SQLSTATE, SQLERRM;
  RETURN 0;
END;
$function$;


-- ============================================================================
-- §9  POST-SNAPSHOT
-- ============================================================================
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0002_approval_gate_decider_post', 'function', n.nspname, p.proname,
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE (n.nspname = 'public' AND p.proname IN ('ottoq_indepot_reassignment_guard',
                                               'ottoq_decide_indepot_approvals'))
    OR (n.nspname = 'twin'   AND p.proname IN ('ottoq_opportunistic_scan',
                                               'ottoq_sim_vehicle_exception_handler'))
    OR (n.nspname = 'ottoq'  AND p.proname IN ('ottoq_readmit_reopened_needs',
                                               'ottoq_readmit_resumed_visits'));


-- ============================================================================
-- §10  VERIFY  — read-only. Paste the real output into MIGRATION_LOG.md.
--
-- "Applied without error" is not verification. V1-V3 can be run immediately; V4-V6
-- need a bounded run of >= 139 sim-min, captured AFTER the run is STOPPED, in the SIM
-- domain, with the denominator stated. Starting a run purges the prior one, so
-- preserve anything you need into a non-'ottoq'-prefixed table FIRST.
-- ============================================================================
--
-- V1. THE ABSORBING STATE IS GONE. Was: 55 pending, 0 ever decided.
--     Expect every indepot_reassign row to reach a terminal status.
-- SELECT status, count(*), count(decided_by) AS with_decider,
--        count(*) FILTER (WHERE payload ? 'decision') AS with_audited_decision
--   FROM public.ottoq_ops_approvals
--  WHERE approval_type = 'indepot_reassign'
--  GROUP BY 1 ORDER BY 1;
--
-- V2. NOTHING IS DOUBLY ABSORBING. Expect 0 rows: no pending indepot_reassign older
--     than the ceiling in ITS OWN clock domain.
-- SELECT count(*) AS stuck_beyond_ceiling
--   FROM public.ottoq_ops_approvals ap
--  WHERE ap.status='pending' AND ap.approval_type='indepot_reassign'
--    AND CASE WHEN ap.payload->>'requested_at_sim' IS NOT NULL
--             THEN (ap.payload->>'requested_at_sim')::timestamptz
--                    <= (SELECT sim_clock_current FROM ottoq_sim_runs r
--                         WHERE r.sim_run_id = ap.sim_run_id) - interval '30 minutes'
--             ELSE ap.requested_at <= now() - interval '30 minutes' END;
--
-- V3. "TECHNICIAN APPROVED" IS ONE FACT. Expect 0 rows: no vehicle claiming a
--     technician approved it while its approval row is still pending.
-- SELECT count(*) AS contradictions
--   FROM vehicles v
--   JOIN public.ottoq_ops_approvals ap ON ap.vehicle_id = v.id
--  WHERE v.config->'exception'->>'status' IN ('technician_approved','auto_staged')
--    AND ap.status = 'pending' AND ap.approval_type = 'indepot_reassign';
--
-- V4. THE HEADLINE. Cut-short work re-booked. Was 0 of 38, then 0 of 52, then 0 of 6
--     reachable. Denominator = vehicles with an open reopened need and >= 1 atom not
--     done/cancelled. PRIMARY METRIC IS PER ARRIVING VEHICLE -- state yours.
-- SELECT count(*) FILTER (WHERE has_space) AS rebooked,
--        count(*)                          AS candidates,
--        round(100.0*count(*) FILTER (WHERE has_space)/NULLIF(count(*),0),1) AS pct
--   FROM ( SELECT n.vehicle_id,
--                 EXISTS (SELECT 1 FROM public.ottoq_stall_bookings b
--                          WHERE b.vehicle_id = n.vehicle_id
--                            AND b.sim_run_id = n.sim_run_id
--                            AND b.booked_at_sim >= n.created_at) AS has_space
--            FROM public.ottoq_visit_needs n
--           WHERE n.status='open' AND n.meta ? 'reopen'
--             AND EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(n.atoms,'[]'::jsonb)) a
--                          WHERE lower(COALESCE(a->>'status','pending')) NOT IN ('done','cancelled'))
--        ) s;
--
-- V5. TOW RETRIEVAL FIRES AT ALL. Was zero. (ottoq_events is 9 GB -- this is a narrow,
--     indexed, time-bounded probe of ONE event type, never a scan.)
-- SELECT count(*) AS tow_retrievals
--   FROM public.ottoq_events
--  WHERE event_type = 'vehicle.tow_retrieved_staged'
--    AND occurred_at >= now() - interval '2 hours';
--
-- V6. THE BASELINE IS INTACT. Re-certify against public.phase11_cert_424242.
--     Watch in particular: evictions cutting live work (20.3%), minutes destroyed
--     (641.30), gate protection (90.0%). The deferral verdict is DECLINED precisely so
--     these do not move -- declined and pending are indistinguishable to the exception
--     handler. If they moved, that assumption is wrong and this migration is wrong.
--
-- ============================================================================
-- AFTERWARDS  (scripts/APPLYING.md steps 5-8)
--   1. Put the real version the database assigned into the header above.
--   2. bash scripts/gen-drift-sql.sh
--   3. Add the row to MIGRATION_LOG.md, including the V1-V6 output.
--   4. Commit, then run scripts/check-drift.sql live. It must report CLEAN.
-- ============================================================================
