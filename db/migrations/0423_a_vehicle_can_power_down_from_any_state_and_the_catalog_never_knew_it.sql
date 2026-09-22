-- migration-version: PENDING
-- migration-name:    a_vehicle_can_power_down_from_any_state_and_the_catalog_never_knew_it
--
-- 0423  **`SM.001` fails on 23.2% of everything it judges — 6,298 of 27,144 evaluations, every one
--       `severity='critical'` — and 6,227 of them are vehicles powering down and powering up, which the
--       transition catalog has never admitted. The same blind spot makes `SM.006`, which enforces
--       `block`, actually REFUSE 13 legitimate BESS writes. Diagnosed in `db/checks/0331`.**
--
--       `forces_recert` **TRUE**: `rules` is one of the fourteen atoms and this changes the verdict of
--       thousands of evaluations per run.
--
-- ══ §1 THE THREE PARTS ════════════════════════════════════════════════════════
--
--   (A) **Power-down and power-up, declared across every vehicle state.** `charging_l2 -> offline` (448
--       observed) is a charging vehicle losing power or comms; `tow_requested -> offline` (1) is a towed
--       vehicle powered down; `offline -> deployed` (2,176) is `0412`'s own *"a vehicle powering on
--       already out on the road."* All physically real, none declared.
--   (B) **The six transitions of `0331` §4**, all `actor=ottoq_engine`, all ordinary depot operations —
--       most sharply `arrived_at_gate -> in_detail_bay` (22) and `-> in_service_bay` (17), where `0412`
--       declared the wash bay with the reasoning *"the gate could dispatch to a CHARGER but not to a
--       BAY"* and then declared only one of the three bays.
--   (C) **One `set_config`, so the actor label stops depending on whether a run is active.**
--
-- ══ §2 WHY (A) IS EVERY STATE AND NOT THE FIFTEEN PAIRS OBSERVED ══════════════
--
-- The census saw 12 states power down and 3 power up. Declaring exactly those would encode this
-- month's scenario mix into the state machine: `ottoq_tick_invariance_reset_fleet` resets whatever state
-- a vehicle happens to be in, and a scenario that parks a vehicle in `emergency_staged` or
-- `service_complete_holding` at teardown would reopen the same finding. **The claim being declared is
-- "a vehicle can power down from any state and power up into the state it is physically in"**, and that
-- claim is either true for all 16 or true for none.
--
-- Three `offline -> Y` rows already exist and are LEFT ALONE — `offline -> arrived_at_gate`
-- (`power_on_at_depot`), `-> staged_awaiting_service` (`seed_into_queue`), `-> staged_for_departure`
-- (`seed_ready`). They say the same thing in more specific words, and `ON CONFLICT DO NOTHING` keeps
-- their triggers and descriptions rather than flattening them into this migration's generic ones.
--
-- ══ §3 THE DESIGN I REJECTED, BECAUSE IT WAS TIDIER AND WRONG ═════════════════
--
-- The obvious fix is a `twin_harness` actor: set it in the reset, declare the lifecycle transitions for
-- it alone, keep `ottoq_engine` out so the shield still fails an engine that powers a vehicle down
-- mid-run. **It builds a simulation-only branch into the SHIELD** — the one layer that must be identical
-- in both worlds — and `ottoyarddepot-sim/AGENTS.md` names that as the thing not to do: *"If you build a
-- code path that only works because this is a simulation, you have broken the pitch."*
--
-- **The residual, stated rather than buried:** after (A), an engine that powers a vehicle down mid-run
-- no longer fails SM.001. That is the price. It is the right trade because SM.001 is `shadow` — it never
-- blocked that write — while what it *was* doing, burying 71 real findings under 6,227 false ones, is a
-- live cost to anyone reading the ledger.
--
-- ══ §4 (C) IS THE ONLY PART THAT CHANGES WHAT IS ALLOWED ══════════════════════
--
-- All three row-level state-change triggers derive the actor like this:
--
--     v_actor_type := COALESCE(NULLIF(current_setting('ottoq.actor_type', TRUE), ''), 'unknown');
--     v_run        := ottoq.ottoq_active_sim_run_id();
--     IF v_actor_type = 'unknown' AND v_run IS NOT NULL THEN v_actor_type := 'ottoq_engine'; END IF;
--
-- So **who acted is inferred from whether a run is active**, not from anything the caller said. Measured
-- (`0331` §3c): 13 of 13 blocked `bess_state_change` rows have `sim_run_id IS NULL`; 190 of 190 allowed
-- rows have a run. Identical transition, identical caller, opposite outcome.
--
-- The fix is one line in `ottoq_tick_invariance_reset_fleet`, which is the caller that writes
-- `current_state='standby'` on every BESS unit at arm boot: say `ottoq_engine` explicitly. **This adds
-- no authority** — whenever a run is active that same write is already labelled `ottoq_engine` 190 times
-- out of 190. It makes the label consistent instead of contingent. The `set_config` is transaction-local
-- and therefore outlives the reset within the pair, which is harmless for exactly that reason: the value
-- it pins is the value the promotion would have produced anyway.
--
-- ══ §5 WHAT THIS DOES NOT DO ══════════════════════════════════════════════════
--
-- It does not improve coverage, and the sentence to refuse is *"SM.001's pass rate went from 76.8% to
-- ~100%."* It is the same shield judged against a catalog that finally describes the system it judges.
-- It does not touch SM.003 (25,874 evaluations, zero failures) or the nine codes that remain unprobed.
-- And it does not address `0326` §6's finding that a code counts as "evaluated" when only one of the
-- contexts it declares is probed.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_n int;
BEGIN
  -- P1. The failures this migration exists to remove are actually there. If SM.001 is already clean,
  --     something else changed and this migration is declaring transitions nobody performs.
  SELECT count(*) INTO v_n FROM public.ottoq_rule_evaluations
   WHERE action_context='vehicle_state_change' AND NOT passed
     AND (context->>'to_state'='offline' OR context->>'from_state'='offline');
  IF v_n < 100 THEN
    RAISE EXCEPTION '0423 P1: only % run-edge SM.001 failures -- re-derive db/checks/0331 before '
                    'declaring 29 transitions to fix a problem that may no longer exist', v_n;
  END IF;

  -- P2. The BESS transitions (C) unblocks are ALREADY DECLARED. If they were not, the fix would be a
  --     catalog gap and not an actor problem, and §4's whole argument would be wrong.
  SELECT count(*) INTO v_n FROM public.ottoq_state_transitions
   WHERE entity_kind='bess' AND to_state='standby' AND from_state IN ('charging','discharging')
     AND status='active' AND 'ottoq_engine' = ANY(allowed_actor_types);
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0423 P2: expected 2 declared bess *->standby transitions allowing ottoq_engine, '
                    'found % -- 0331 §3 read the catalog wrong, stop and re-derive', v_n;
  END IF;

  -- P3. The reset does not already set the actor, and it is the caller that writes BESS standby.
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet'
     AND position('ottoq.actor_type' in pg_get_functiondef(p.oid)) = 0
     AND pg_get_functiondef(p.oid) ~ 'current_state\s*=\s*''standby''';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0423 P3: ottoq_tick_invariance_reset_fleet either already sets the actor or no '
                    'longer writes BESS standby -- re-read it before editing';
  END IF;

  -- P4. No run in flight. This changes what the shield permits mid-tick.
  SELECT count(*) INTO v_n FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0423 P4: % run(s) running/paused', v_n;
  END IF;
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- (A) POWER-DOWN AND POWER-UP, ACROSS EVERY VEHICLE STATE
--     Generated from the state vocabulary rather than typed, so the claim in §2
--     ("all 16 or none") is structural and not a list someone can half-update.
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_state_transitions
  (entity_kind, from_state, to_state, trigger_event, allowed_actor_types, description, introduced_in, status)
SELECT 'vehicle', s, 'offline', 'power_down', ARRAY['ottoq_engine','av_vehicle'],
       'A vehicle powers down, or loses power and comms, while in ' || s || '. 0423: the catalog '
       'admitted no power-down from anywhere, so 3,197 of these per census read as critical '
       'state-machine violations attributed to the engine (db/checks/0331 §2).',
       '0423', 'active'
  FROM unnest(ARRAY['arrived_at_gate','charge_complete_holding','charging_dcfc','charging_l2','deployed',
                    'emergency_staged','en_route_to_deployment','en_route_to_depot','in_detail_bay',
                    'in_service_bay','in_wash_bay','out_of_service','service_complete_holding',
                    'staged_awaiting_service','staged_for_departure','tow_requested']) AS s
ON CONFLICT (entity_kind, from_state, to_state) DO NOTHING;

INSERT INTO public.ottoq_state_transitions
  (entity_kind, from_state, to_state, trigger_event, allowed_actor_types, description, introduced_in, status)
SELECT 'vehicle', 'offline', s, 'power_on_into_state', ARRAY['ottoq_engine','av_vehicle'],
       'A vehicle powers on already in ' || s || ' -- 0412''s "a vehicle powering on already out on the '
       'road", generalised. 0423: three specific cases were already declared (power_on_at_depot, '
       'seed_into_queue, seed_ready) and are left with their own triggers by ON CONFLICT DO NOTHING.',
       '0423', 'active'
  FROM unnest(ARRAY['arrived_at_gate','charge_complete_holding','charging_dcfc','charging_l2','deployed',
                    'emergency_staged','en_route_to_deployment','en_route_to_depot','in_detail_bay',
                    'in_service_bay','in_wash_bay','out_of_service','service_complete_holding',
                    'staged_awaiting_service','staged_for_departure','tow_requested']) AS s
ON CONFLICT (entity_kind, from_state, to_state) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- (B) THE SIX REAL ENGINE TRANSITIONS (db/checks/0331 §4)
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_state_transitions
  (entity_kind, from_state, to_state, trigger_event, allowed_actor_types, description, introduced_in, status)
VALUES
  ('vehicle','arrived_at_gate','in_detail_bay','gate_direct_dispatch_detail', ARRAY['ottoq_engine'],
   'A vehicle arriving with a known detailing need is dispatched straight from the gate into a detail '
   'bay without queuing. 0412 declared the wash-bay form of this with the reasoning "the gate could '
   'dispatch to a CHARGER but not to a BAY" and then declared one of the three bays. 22 observed.',
   '0423', 'active'),
  ('vehicle','arrived_at_gate','in_service_bay','gate_direct_dispatch_service', ARRAY['ottoq_engine'],
   'A vehicle arriving with a known service need is dispatched straight from the gate into a service '
   'bay without queuing. Same omission as the detail bay above. 17 observed (G132).', '0423', 'active'),
  ('vehicle','charging_l2','staged_for_departure','depart_from_charger', ARRAY['ottoq_engine'],
   'A charging vehicle with no outstanding service atoms is called for departure before the charge '
   'completes. 0412 declared the same decision one step later (charge_complete_holding -> '
   'staged_for_departure); this is it taken at the charger. 14 observed.', '0423', 'active'),
  ('vehicle','staged_for_departure','charge_complete_holding','return_to_holding_from_departure', ARRAY['ottoq_engine'],
   'A staged vehicle is returned to the post-charge holding pool rather than deployed -- demand '
   'withdrawn, or a later departure slot assigned. 10 observed.', '0423', 'active'),
  ('vehicle','staged_awaiting_service','charge_complete_holding','hold_without_charging', ARRAY['ottoq_engine'],
   'A queued vehicle already at target SoC is moved into the post-charge holding pool without ever '
   'entering a charger. 4 observed.', '0423', 'active'),
  ('vehicle','charge_complete_holding','in_service_bay','dispatch_to_service_from_holding', ARRAY['ottoq_engine'],
   'A vehicle holding post-charge is dispatched into a service bay directly. The detail-bay and '
   'wash-bay forms were declared by 0412; the service bay was not. 4 observed.', '0423', 'active')
ON CONFLICT (entity_kind, from_state, to_state) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- (C) THE ACTOR LABEL STOPS DEPENDING ON WHETHER A RUN IS ACTIVE
--     Surgical splice, asserted by byte delta -- same discipline as 0421/0422.
-- ─────────────────────────────────────────────────────────────────────────────
DO $fix$
DECLARE
  v_def    text;
  v_new    text;
  v_anchor text;
  v_insert text;
  v_hits   int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet';

  -- Splice immediately after the function's opening BEGIN, which is the first 'BEGIN' that is followed
  -- by a newline in the body. Anchoring on the AS $function$ ... BEGIN boundary keeps this independent
  -- of anything in the DECLARE block.
  v_anchor := E'AS $function$\nDECLARE';
  v_hits := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0423 (C): the function header anchor occurs % times, expected 1 -- refusing to splice',
                    v_hits;
  END IF;

  v_anchor := E'\nBEGIN\n';
  v_hits := (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor);
  IF v_hits <> 1 THEN
    RAISE EXCEPTION '0423 (C): "\nBEGIN\n" occurs % times in the definition, expected exactly 1 -- the '
                    'function has nested blocks now and the splice point is ambiguous', v_hits;
  END IF;

  v_insert :=
E'\nBEGIN\n'
'  -- 0423(C): SAY WHO IS ACTING, rather than letting the row triggers infer it from whether a run is\n'
'  -- active. All three state-change triggers promote actor `unknown` to `ottoq_engine` only when\n'
'  -- ottoq_active_sim_run_id() is non-NULL; during this reset it can be NULL, and SM.006 (enforcement\n'
'  -- `block`) then REFUSES the BESS standby write below. Measured in db/checks/0331 §3c: 13 of 13\n'
'  -- blocked bess rows have sim_run_id NULL, 190 of 190 allowed rows have a run. This adds no\n'
'  -- authority -- it pins the value the promotion produces anyway -- it only makes it deterministic.\n'
'  PERFORM set_config(''ottoq.actor_type'', ''ottoq_engine'', true);\n';

  v_new := replace(v_def, v_anchor, v_insert);

  IF length(v_new) - length(v_def) <> length(v_insert) - length(v_anchor) THEN
    RAISE EXCEPTION '0423 (C): byte delta is % but the literals differ by % -- something else changed',
                    length(v_new) - length(v_def), length(v_insert) - length(v_anchor);
  END IF;

  EXECUTE v_new;
  RAISE NOTICE '0423 (C): installed, +% bytes', length(v_new) - length(v_def);
END $fix$;

-- ─────────────────────────────────────────────────────────────────────────────
-- LINEAGE
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0423_a_vehicle_can_power_down_from_any_state_and_the_catalog_never_knew_it',
  true,
  'Declares vehicle power-down (any state -> offline) and power-up (offline -> any state) as ordinary '
  'transitions for ottoq_engine/av_vehicle, plus the six real engine transitions of db/checks/0331 §4 '
  '(including arrived_at_gate -> in_detail_bay / in_service_bay, which 0412 missed by declaring only the '
  'wash bay). And sets ottoq.actor_type explicitly in ottoq_tick_invariance_reset_fleet so SM.006 '
  '(enforcement=block) stops refusing the BESS standby write: 13 of 13 blocked rows had sim_run_id NULL, '
  '190 of 190 allowed rows had a run, identical transition and caller. TRUE because `rules` is one of the '
  'fourteen atoms and thousands of evaluations per run change verdict. NOT a coverage improvement -- the '
  'same shield judged against a catalog that finally describes the system; the sentence "SM.001 went from '
  '76.8% to ~100%" must not be quoted as one. Residual: an engine that powers a vehicle down mid-run no '
  'longer fails SM.001, accepted because SM.001 is shadow and never blocked it, while burying 71 real '
  'findings under 6,227 false ones was a live cost. A twin_harness actor was designed and rejected: it '
  'would put a simulation-only branch in the shield.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert,
                                 note          = EXCLUDED.note,
                                 classified_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_n     int;
  v_left  int;
  v_src   text;
BEGIN
  -- V1. Every observed failing transition is now declared. This is the point of the migration, asserted
  --     against the LEDGER rather than against the list this file typed.
  SELECT count(*) INTO v_left
    FROM (SELECT DISTINCT re.context->>'from_state' f, re.context->>'to_state' t
            FROM public.ottoq_rule_evaluations re
           WHERE re.action_context='vehicle_state_change' AND NOT re.passed) d
   WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_state_transitions s
                      WHERE s.entity_kind='vehicle' AND s.status='active'
                        AND s.from_state=d.f AND s.to_state=d.t);
  IF v_left <> 0 THEN
    RAISE EXCEPTION '0423 V1: % distinct transitions that SM.001 has failed are STILL undeclared', v_left;
  END IF;

  -- V2. The three pre-existing offline -> Y rows kept their own triggers. ON CONFLICT DO NOTHING is only
  --     correct if it actually did nothing to them.
  SELECT count(*) INTO v_n FROM public.ottoq_state_transitions
   WHERE entity_kind='vehicle' AND from_state='offline'
     AND trigger_event IN ('power_on_at_depot','seed_into_queue','seed_ready');
  IF v_n <> 3 THEN
    RAISE EXCEPTION '0423 V2: expected the 3 pre-existing offline rows to keep their triggers, found %', v_n;
  END IF;

  -- V3. Power-down is declared from every vehicle state, not a subset (§2's "all 16 or none").
  SELECT count(*) INTO v_n FROM public.ottoq_state_transitions
   WHERE entity_kind='vehicle' AND to_state='offline' AND status='active';
  IF v_n <> 16 THEN
    RAISE EXCEPTION '0423 V3: power-down declared from % states, expected 16', v_n;
  END IF;

  -- V4. NO transition anywhere names a simulation-only actor. §3's rejected design must not have crept
  --     back in through a copy-paste.
  SELECT count(*) INTO v_n FROM public.ottoq_state_transitions
   WHERE 'twin_harness' = ANY(allowed_actor_types) OR 'twin' = ANY(allowed_actor_types);
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0423 V4: % transition(s) name a simulation-only actor -- that is the design this '
                    'migration explicitly rejected', v_n;
  END IF;

  -- V5. (C) is installed once, and the BESS standby write it protects is still there.
  SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^' || chr(10) || ']*','','g')
    INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet';
  v_n := (length(v_src) - length(replace(v_src,'set_config(''ottoq.actor_type''','')))
        / length('set_config(''ottoq.actor_type''');
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0423 V5: the actor set_config appears % times, expected 1', v_n;
  END IF;
  IF v_src !~ 'current_state\s*=\s*''standby''' THEN
    RAISE EXCEPTION '0423 V5: the BESS standby write is gone from the reset -- the splice damaged it';
  END IF;

  -- V6. THE GUARDS THAT MUST SURVIVE the splice. Each is a named prior fix inside this function.
  FOREACH v_src IN ARRAY ARRAY['ottoq_bess_units','ottoq_ocpp_chargers','current_soc_source','target_soc']
  LOOP
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet'
       AND position(v_src in pg_get_functiondef(p.oid)) > 0;
    IF v_n <> 1 THEN
      RAISE EXCEPTION '0423 V6: guard "%" is missing from the installed reset', v_src;
    END IF;
  END LOOP;

  RAISE NOTICE '0423: verified. The catalog now admits power-down from every vehicle state, the six '
               'engine transitions of 0331 §4, and the reset says who it is.';
END $post$;

COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- AFTER THE NEXT SWEEP: re-run db/checks/0331 §1. SM.001's failed column should
-- fall from 6,298 toward 0 and SM.006's blocked rows should stop appearing.
-- Neither is a coverage improvement -- see §5.
-- ─────────────────────────────────────────────────────────────────────────────
