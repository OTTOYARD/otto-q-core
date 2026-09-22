-- migration-version: 20260922042212
-- migration-name:    the_state_machine_never_learned_that_a_vehicle_can_break_while_parked
--
-- 0412  **Thirteen transitions the engine performs as normal business and `ottoq_state_transitions`
--       does not declare. `SM.001.vehicle_transition_validity` has been reporting all of them into
--       a shadow log, so 265 of the 593 undeclared-transition occurrences it has flagged are the
--       TABLE's omission and not the engine's misbehaviour.**
--
--       `forces_recert` TRUE — this changes `ottoq_rule_evaluations` content, which is the `rules`
--       atom, one of the fourteen.
--
--       **SM.001 is NOT promoted out of `shadow` here.** Promotion requires a clean full-day run
--       first; see §4. Flipping it today would block the wash bay, the detail bay and the departure
--       path, because those are three of the gaps this migration closes.
--
-- ══ THE DIAGNOSIS IS `db/checks/0321`; THIS IS ITS FIRST HALF ═══════════════
--
-- `0321` took its census from ONE run, `d68d05bb`, and reported 26 missing transitions over 374
-- occurrences. **Every occurrence figure below is instead re-derived across every surviving run in
-- `ottoq_events`, because a one-run census is a lower bound and the first attempt at this migration
-- was rolled back by its own verify for exactly that reason** (see §3's note). Measured all-run:
--
--     41 active `vehicle` rows declared
--     30 distinct observed transitions undeclared, over 593 occurrences
--
--         12 operational gaps      211   <-- closed here, rows (1)-(3)
--          1 triage step            54   <-- closed here, row (4)
--         11 end-of-run resets     265   <-- deliberately left, group (b)
--          4 return-to-service      31   <-- deliberately left, group (a)
--          2 boot-state landings    32   <-- deliberately left, group (c)
--
-- So this migration closes 265 of 593 occurrences, and the 328 that remain are the three groups
-- named below — none of them an oversight.
--
-- **The single detail that explains it:** `deployed -> tow_requested` IS declared, with
-- `trigger_event='incident_tow'` and `allowed_actor_types={ottoq_engine,av_vehicle}`. None of the
-- six IN-DEPOT fault entries is. The state machine was written when a vehicle could only break
-- while DRIVING; `twin.ottoq_sim_vehicle_exception_handler` — which faults vehicles parked on a
-- charger — was added later, and the table never learned about it.
--
-- ══ WHAT THIS MIGRATION ADDS, AND WHY EACH ONE IS UNAMBIGUOUS ══════════════
--
-- **(1) Six in-depot fault entries.** A vehicle can break while parked. `deployed ->
-- tow_requested` is the precedent and these carry the same actor set, because the same engine path
-- raises them:
--
--     charging_l2 -> tow_requested                 37 occurrences
--     staged_awaiting_service -> tow_requested     35
--     staged_for_departure -> tow_requested         9
--     charge_complete_holding -> tow_requested      2
--     charging_dcfc -> tow_requested                1
--     arrived_at_gate -> tow_requested              1
--
-- **(2) Four service-dispatch and departure entries.** Pure workflow, and the depot cannot
-- function without them — the inverse transitions (`in_wash_bay -> staged_awaiting_service`,
-- `in_detail_bay -> staged_awaiting_service`) are already declared, so the table admits the exit
-- from a bay and not the entry to it:
--
--     charge_complete_holding -> staged_for_departure  38
--     staged_awaiting_service -> in_wash_bay           37
--     staged_awaiting_service -> in_detail_bay         17
--     arrived_at_gate -> in_wash_bay                    2
--
-- The fourth is the one `0321` missed entirely: it does not occur on `d68d05bb` and only appears
-- once the census spans every surviving run. `arrived_at_gate -> charging_dcfc` and `-> charging_l2`
-- are already declared, so the gate could dispatch a vehicle to a CHARGER but not to a BAY — the
-- same omission shape as the in-depot faults.
--
-- **(3) Two deployment paths.** Both are the engine releasing a ready vehicle:
--
--     staged_for_departure -> en_route_to_depot    28
--     staged_awaiting_service -> deployed           4
--
-- **(4) One triage step, and this is the only judgement call in the file.**
--
--     tow_requested -> emergency_staged            54
--
-- Admitted because it moves a broken vehicle to a SAFE STAGING SPOT and does not return it to
-- service. The existing table's intent is visible in its own rows: `tow_requested ->
-- out_of_service` and `tow_requested -> arrived_at_gate` are both `{command_center_operator,
-- depot_supervisor}`. **So the designer gated RETURN TO SERVICE behind a human and left triage
-- unspecified.** This grants triage to the engine and nothing more.
--
-- ══ WHAT THIS MIGRATION DELIBERATELY DOES NOT ADD ══════════════════════════
--
-- 328 of the 593 remain, and every one is either mechanical or a real question. **None of them is
-- an oversight, and legalising them is not mine to decide.**
--
-- **(a) RETURN TO SERVICE AFTER AN INCIDENT — 31 occurrences, and this is a safety policy choice.**
--
--     tow_requested -> staged_awaiting_service     25
--     emergency_staged -> en_route_to_depot         3
--     tow_requested -> en_route_to_depot            2
--     tow_requested -> charge_complete_holding      1
--
-- The table already says a human authorizes recovery. `emergency_staged ->
-- staged_awaiting_service` IS declared with `{command_center_operator, depot_supervisor}` and the
-- engine did it anyway five times — **that is `0321` §4, a defect in the ENGINE, and widening the
-- gate would erase the finding rather than fix it.** The other four are the same shape without a
-- declared row. Chase wants automated triage (his words: *"disaster avoidance and triage"*), so
-- these may well become legal — but **automatic move-to-safety and automatic return-to-service are
-- different decisions**, and only the first is taken here.
--
-- **(b) THE END-OF-RUN RESET — 265 occurrences, the largest group by far.** Eleven transitions
-- ending in `offline`, all from `public.ottoq_sim_release_depot` — one per vehicle per run, which is
-- why this group grows with the number of surviving runs and not with depot activity. These are not
-- operational and must not be legalised for `ottoq_engine`: a vehicle going from `charging_l2`
-- straight to `offline` mid-shift is precisely the mid-operation disappearance SM.001 should catch.
-- They need a reset-scoped actor, and none of the five functions that write `offline` declares
-- `ottoq.actor_type` today — so that is plumbing, not data, and it is its own change.
--
-- **(c) BOOT-STATE SYNTHESIS — 32 occurrences over two transitions.**
--
--     offline -> charge_complete_holding           20
--     offline -> deployed                          12
--
-- The first is a vehicle powering on already charge-complete without having charged; the second is a
-- vehicle powering on already out on the road. `offline -> arrived_at_gate` and
-- `offline -> staged_awaiting_service` ARE declared (`power_on_at_depot`, `seed_into_queue`), so
-- booting is anticipated and these two landing states are not. Left failing as a question about
-- boot-state synthesis: the honest fix is either to declare the landing states the seeder actually
-- uses, or to make the seeder route every vehicle through a declared one.
--
-- **Expected residual after this migration: 593 -> 328**, as
-- 265 reset + 31 return-to-service + 32 boot-state. §3's verify does NOT assert that arithmetic —
-- it asserts the stronger and stabler thing, that the operational bucket is EMPTY.
--
-- ══ §4 THE PROMOTION ORDER, WHICH IS FORCED ════════════════════════════════
--
--   1. this migration (the unambiguous table gaps)
--   2. a reset-scoped actor for group (b)
--   3. the engine fix for `0321` §4 — request approval or do not transition
--   4. Chase's decision on group (a)
--   5. a clean full-day run showing residual failures are only group (c)
--   6. **only then** `SM.001` from `shadow` to `block`
--
-- That is CLAUDE.md 2.9a's blind-spot promotion doctrine — MEASURED first, ENFORCED after a clean
-- round — applied to a rule instead of a determinism atom.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_n     int;
  v_enf   text;
  v_bad   text;
BEGIN
  -- P1. The table is the shape this migration assumes: 41 active vehicle rows, all role-gated.
  SELECT count(*) INTO v_n FROM public.ottoq_state_transitions
   WHERE entity_kind='vehicle' AND status='active';
  IF v_n <> 41 THEN
    RAISE EXCEPTION '0412 P1: expected 41 active vehicle transitions, found % -- re-derive db/checks/0321 before adding rows', v_n;
  END IF;

  -- P2. THE PRECEDENT EXISTS. deployed -> tow_requested must already be declared for
  --     ottoq_engine, because the six in-depot entries below copy its actor set.
  SELECT count(*) INTO v_n FROM public.ottoq_state_transitions
   WHERE entity_kind='vehicle' AND status='active'
     AND from_state='deployed' AND to_state='tow_requested'
     AND 'ottoq_engine' = ANY(allowed_actor_types);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0412 P2: deployed -> tow_requested is not declared for ottoq_engine; the '
                    'in-depot fault rows have no precedent to copy';
  END IF;

  -- P3. NONE of the thirteen rows exists yet.
  SELECT count(*), string_agg(from_state||' -> '||to_state, ', ')
    INTO v_n, v_bad
    FROM public.ottoq_state_transitions
   WHERE entity_kind='vehicle' AND status='active'
     AND (from_state, to_state) IN (
       ('charging_l2','tow_requested'), ('staged_awaiting_service','tow_requested'),
       ('staged_for_departure','tow_requested'), ('charge_complete_holding','tow_requested'),
       ('charging_dcfc','tow_requested'), ('arrived_at_gate','tow_requested'),
       ('staged_awaiting_service','in_wash_bay'), ('staged_awaiting_service','in_detail_bay'),
       ('arrived_at_gate','in_wash_bay'),
       ('charge_complete_holding','staged_for_departure'),
       ('staged_awaiting_service','deployed'), ('staged_for_departure','en_route_to_depot'),
       ('tow_requested','emergency_staged'));
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0412 P3: % of the thirteen rows already exist (%) -- this migration is not idempotent by design', v_n, v_bad;
  END IF;

  -- P4. THE HUMAN GATE THIS MIGRATION REFUSES TO WIDEN is still human-only. If someone has already
  --     granted the engine recovery rights, 0321 §4's finding is gone and this file's reasoning
  --     about group (a) needs redoing.
  SELECT count(*) INTO v_n FROM public.ottoq_state_transitions
   WHERE entity_kind='vehicle' AND status='active'
     AND from_state='emergency_staged' AND to_state='staged_awaiting_service'
     AND NOT ('ottoq_engine' = ANY(allowed_actor_types));
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0412 P4: emergency_staged -> staged_awaiting_service is no longer human-only; '
                    're-read db/checks/0321 section 4 before proceeding';
  END IF;

  -- P5. SM.001 IS STILL IN SHADOW, and this migration must not be the thing that promotes it.
  SELECT enforcement INTO v_enf FROM public.ottoq_rules
   WHERE rule_code='SM.001.vehicle_transition_validity' AND status='active';
  IF v_enf IS DISTINCT FROM 'shadow' THEN
    RAISE EXCEPTION '0412 P5: SM.001 enforcement is %, expected shadow. If it is already blocking, '
                    'adding rows changes live behaviour and needs its own risk read', v_enf;
  END IF;

  RAISE NOTICE '0412 preflight: 41 declared, precedent present, thirteen rows absent, human gate intact, SM.001 in shadow';
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- (1) Six in-depot fault entries. A vehicle can break while parked.
--     Actor set copied from the deployed -> tow_requested precedent: the same
--     engine path (twin.ottoq_sim_vehicle_exception_handler) raises all of them.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_state_transitions
  (entity_kind, from_state, to_state, trigger_event, allowed_actor_types, description, introduced_in, status)
VALUES
  ('vehicle','charging_l2','tow_requested','indepot_fault_tow', ARRAY['ottoq_engine','av_vehicle'],
   'Vehicle faulted while charging on L2. Raised by twin.ottoq_sim_vehicle_exception_handler, which '
   'evicts from the stall and requests a tow. 0412: the table previously admitted faults only from '
   'deployed, so every in-depot fault read as an invalid transition.', '0412', 'active'),
  ('vehicle','charging_dcfc','tow_requested','indepot_fault_tow', ARRAY['ottoq_engine','av_vehicle'],
   'Vehicle faulted while charging on DCFC. See charging_l2 -> tow_requested.', '0412', 'active'),
  ('vehicle','staged_awaiting_service','tow_requested','indepot_fault_tow', ARRAY['ottoq_engine','av_vehicle'],
   'Vehicle faulted while queued for service. The largest in-depot fault population after L2.', '0412', 'active'),
  ('vehicle','charge_complete_holding','tow_requested','indepot_fault_tow', ARRAY['ottoq_engine','av_vehicle'],
   'Vehicle faulted while holding post-charge.', '0412', 'active'),
  ('vehicle','staged_for_departure','tow_requested','indepot_fault_tow', ARRAY['ottoq_engine','av_vehicle'],
   'Vehicle faulted after being staged to depart but before deploying.', '0412', 'active'),
  ('vehicle','arrived_at_gate','tow_requested','indepot_fault_tow', ARRAY['ottoq_engine','av_vehicle'],
   'Vehicle faulted at the gate on arrival, before being assigned anywhere.', '0412', 'active');

-- ─────────────────────────────────────────────────────────────────────────────
-- (2) Service dispatch and departure. The table already admits the EXIT from a
--     bay (in_wash_bay -> staged_awaiting_service) and not the ENTRY to it.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_state_transitions
  (entity_kind, from_state, to_state, trigger_event, allowed_actor_types, description, introduced_in, status)
VALUES
  ('vehicle','staged_awaiting_service','in_wash_bay','service_dispatch_wash', ARRAY['ottoq_engine'],
   'Engine dispatches a queued vehicle into a wash bay. The inverse transition was already '
   'declared; 0412 adds the entry.', '0412', 'active'),
  ('vehicle','arrived_at_gate','in_wash_bay','gate_direct_dispatch_wash', ARRAY['ottoq_engine'],
   'A vehicle arriving dirty is dispatched straight from the gate into a wash bay without queuing. '
   'arrived_at_gate -> charging_dcfc and -> charging_l2 were already declared, so the gate could '
   'dispatch to a CHARGER but not to a BAY -- the same omission shape as the in-depot faults.', '0412', 'active'),
  ('vehicle','staged_awaiting_service','in_detail_bay','service_dispatch_detail', ARRAY['ottoq_engine'],
   'Engine dispatches a queued vehicle into a detail bay. The inverse was already declared.', '0412', 'active'),
  ('vehicle','charge_complete_holding','staged_for_departure','stage_for_departure_after_charge', ARRAY['ottoq_engine'],
   'A charge-complete vehicle with no outstanding service atoms is staged to depart directly, '
   'without re-entering the service queue.', '0412', 'active');

-- ─────────────────────────────────────────────────────────────────────────────
-- (3) Deployment paths. The engine releasing a ready vehicle.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_state_transitions
  (entity_kind, from_state, to_state, trigger_event, allowed_actor_types, description, introduced_in, status)
VALUES
  ('vehicle','staged_awaiting_service','deployed','deploy_from_queue', ARRAY['ottoq_engine'],
   'A queued vehicle is deployed without a departure-staging step, when demand is called and no '
   'service atom is outstanding.', '0412', 'active'),
  ('vehicle','staged_for_departure','en_route_to_depot','departure_recalled_before_deploy', ARRAY['ottoq_engine'],
   'A staged vehicle is recalled before it deploys and re-enters the inbound leg.', '0412', 'active');

-- ─────────────────────────────────────────────────────────────────────────────
-- (4) Triage to safe staging -- the one judgement call, and the narrow one.
--     Moves a broken vehicle somewhere safe. Does NOT return it to service:
--     tow_requested -> out_of_service and -> arrived_at_gate remain human-only,
--     which is how the original designer gated recovery.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_state_transitions
  (entity_kind, from_state, to_state, trigger_event, allowed_actor_types, description, introduced_in, status)
VALUES
  ('vehicle','tow_requested','emergency_staged','incident_triage_to_safe_staging', ARRAY['ottoq_engine','command_center_operator'],
   'Automatic triage: a tow-requested vehicle is moved to emergency staging. Granted to the engine '
   'because it moves a broken vehicle to safety and does NOT return it to service -- '
   'tow_requested -> out_of_service and tow_requested -> arrived_at_gate stay '
   '{command_center_operator, depot_supervisor}. 0412 deliberately does not grant the engine any '
   'return-to-service transition; see db/checks/0321 section 4.', '0412', 'active');

-- ─────────────────────────────────────────────────────────────────────────────
-- The lineage row the recert floor reads. TRUE this time, and stated plainly.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0412_the_state_machine_never_learned_that_a_vehicle_can_break_while_parked', true,
  'Adds thirteen rows to ottoq_state_transitions. SM.001 is evaluated at vehicle_state_change and '
  'logs a pass/fail per transition, so declaring thirteen previously-missing transitions flips the '
  'passed flag and reason on 265 of the 593 undeclared-transition occurrences measured across every '
  'surviving run. ottoq_rule_evaluations is the rules '
  'atom, one of the fourteen, so every canon column is legitimately invalidated. No engine '
  'behaviour changes: SM.001 stays in shadow, so nothing that happened before is blocked now.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert,
                                 note          = EXCLUDED.note,
                                 classified_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_n      int;
  v_gaps   int;
  v_reset  int;
  v_return int;
  v_boot   int;
  v_unclassified text;
  v_enf    text;
BEGIN
  -- V1. Twelve rows landed, all active, all role-gated (the column is NOT NULL but an empty array
  --     would disable the gate silently).
  SELECT count(*) INTO v_n FROM public.ottoq_state_transitions
   WHERE entity_kind='vehicle' AND introduced_in='0412' AND status='active'
     AND cardinality(allowed_actor_types) > 0;
  IF v_n <> 13 THEN
    RAISE EXCEPTION '0412 V1: % of 13 rows present, active and role-gated', v_n;
  END IF;
  SELECT count(*) INTO v_n FROM public.ottoq_state_transitions
   WHERE entity_kind='vehicle' AND status='active';
  IF v_n <> 54 THEN
    RAISE EXCEPTION '0412 V1: expected 54 active vehicle transitions (41 + 13), found %', v_n;
  END IF;

  -- V2. NO RETURN-TO-SERVICE TRANSITION WAS GRANTED TO THE ENGINE. This is the safety assertion of
  --     the file: if a later edit widens one of these, this verify is where it should be caught.
  SELECT count(*) INTO v_n FROM public.ottoq_state_transitions
   WHERE entity_kind='vehicle' AND status='active'
     AND 'ottoq_engine' = ANY(allowed_actor_types)
     AND (   (from_state='emergency_staged' AND to_state IN ('staged_awaiting_service','en_route_to_depot'))
          OR (from_state='tow_requested'    AND to_state IN ('staged_awaiting_service','en_route_to_depot',
                                                            'charge_complete_holding','arrived_at_gate',
                                                            'out_of_service')));
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0412 V2: % return-to-service transition(s) are now granted to ottoq_engine. '
                    'This migration must never do that -- see db/checks/0321 section 4', v_n;
  END IF;

  -- V3. EVERY OPERATIONAL GAP IS CLOSED. Asserted as BUCKET EMPTINESS rather than arithmetic,
  --     and the first attempt at this migration is why: it asserted
  --     `gaps = reset + return + boot` and failed at 330 <> 328, because
  --     `arrived_at_gate -> in_wash_bay` (2 occurrences) existed in the wider event set and not in
  --     the single run the header was derived from. Two lessons, both worth the rollback:
  --
  --       (a) A gap census taken from ONE run is a lower bound. `ottoq_events` carries every
  --           surviving run, and the recert runner adds more while you work — so the denominator
  --           moves and any assertion on a total is stale before it lands.
  --       (b) Asserting a partition SUMS correctly is weaker than asserting the bucket you claim to
  --           have emptied IS empty. The second cannot be satisfied by a coincidence of totals.
  --
  --     So: after this insert, no missing transition may classify as operational or triage.
  WITH observed AS (
    SELECT payload->'diff'->'current_state'->>'from' AS f,
           payload->'diff'->'current_state'->>'to'   AS t,
           count(*) AS n
      FROM public.ottoq_events
     WHERE event_type='vehicle.state_changed'
       AND payload->'diff' ? 'current_state'
       AND payload->'diff'->'current_state'->>'from'
           IS DISTINCT FROM payload->'diff'->'current_state'->>'to'
     GROUP BY 1,2
  ), missing AS (
    SELECT o.f, o.t, o.n FROM observed o
     LEFT JOIN public.ottoq_state_transitions s
            ON s.entity_kind='vehicle' AND s.from_state=o.f AND s.to_state=o.t AND s.status='active'
     WHERE s.transition_id IS NULL
  )
  SELECT coalesce(sum(n),0),
         coalesce(sum(n) FILTER (WHERE t='offline'),0),
         coalesce(sum(n) FILTER (WHERE t <> 'offline' AND f <> 'offline'
                                   AND f IN ('tow_requested','emergency_staged')),0),
         coalesce(sum(n) FILTER (WHERE f='offline'),0),
         coalesce(string_agg(DISTINCT f||' -> '||t, ', ')
                  FILTER (WHERE t <> 'offline' AND f <> 'offline'
                            AND f NOT IN ('tow_requested','emergency_staged')), '')
    INTO v_gaps, v_reset, v_return, v_boot, v_unclassified
    FROM missing;

  IF v_gaps = 0 THEN
    RAISE WARNING '0412 V3: no observed transitions are missing -- the run data may have been '
                  'purged, so the residual could not be verified';
  ELSIF v_unclassified <> '' THEN
    RAISE EXCEPTION '0412 V3: these observed transitions are still undeclared and are neither '
                    'reset, boot-state nor return-to-service, so they are operational gaps this '
                    'migration failed to close: %', v_unclassified;
  END IF;

  -- V4. SM.001 was NOT promoted. The whole point of the forced order in section 4.
  SELECT enforcement INTO v_enf FROM public.ottoq_rules
   WHERE rule_code='SM.001.vehicle_transition_validity' AND status='active';
  IF v_enf IS DISTINCT FROM 'shadow' THEN
    RAISE EXCEPTION '0412 V4: SM.001 enforcement is now % -- this migration must leave it in shadow', v_enf;
  END IF;

  RAISE NOTICE '0412 verify: 54 active vehicle transitions, 0 engine return-to-service grants, '
               'residual % = reset % + return-to-service % + boot-state %, SM.001 still shadow',
               v_gaps, v_reset, v_return, v_boot;
END $post$;

COMMIT;
