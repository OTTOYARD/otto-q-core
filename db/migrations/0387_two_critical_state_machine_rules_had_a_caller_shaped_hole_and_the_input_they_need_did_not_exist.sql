-- migration-version: 20260920185425
-- migration-name:    two_critical_state_machine_rules_had_a_caller_shaped_hole_and_the_input_they_need_did_not_exist
--
-- 0387  G44: SM.001 AND SM.003 NOW HAVE A CALLER. AND THE REASON THEY COULD NOT SIMPLY
--       BE CALLED IS THAT THE ACTOR THEY JUDGE WAS NEVER RECORDED -- 129,060 OF 129,060
--       STATE-CHANGE EVENTS SAID 'unknown', AND NOT ONE DECLARED TRANSITION ADMITS IT.
--
-- `forces_recert` **TRUE**. Engine-driven state changes now carry
-- `actor_type='ottoq_engine'` instead of `'unknown'`, which moves the events atom, and
-- two rules now log evaluations, which moves the rules atom.
--
-- ══ 1. WHAT G44 ACTUALLY IS ════════════════════════════════════════════════
--
-- `db/checks/0192`, re-derived by `0273`: of thirty declared rule codes the shield
-- evaluates twenty-one, at six probe points. The nine it does not evaluate have callable
-- evaluator functions and **no caller**, and six of the nine are `critical`. Both checks
-- reached the same diagnosis and stopped there: *"these are invariants over transitions and
-- outcomes, and a gate placed where something STARTS cannot check one."*
--
-- That diagnosis is right, and it is also not the whole obstacle. Each of the nine
-- DECLARES the action context it belongs at, and none of those contexts is a probe point:
--
--   SM.001 vehicle_transition_validity   critical   vehicle_state_change
--   SM.003 stall_transition_validity     critical   stall_state_change
--   SM.006 bess_transition_validity      critical   bess_state_change
--   SM.005 audit_note_required           critical   progression_decision_insert
--   HW.006 physical_presence             critical   task_completion
--   SM.004 role_gated_actions            critical   tech_override, emergency_stop, ...
--   SLA.002 max_queue_depth              warning    arrival, queue_admission
--   TW.002 overnight_staging             info       post_redeployment_staging
--   TW.004 tariff_window                 info       cost_advisory
--
-- The six live probe points are `task_start`, `stall_assignment`, `charge_session_start`,
-- `redeployment`, `policy_write`, `bess_dispatch`. **There is no probe at a transition, a
-- completion, or an arrival.** That is the shape of the hole.
--
-- ══ 2. AND THE HOOK ALREADY EXISTED, WHICH IS WHY THIS IS SMALL ════════════
--
-- `trg_ottoq_vehicles_state_change` and `trg_ottoq_stalls_state_change` are attached,
-- enabled, and fire `AFTER INSERT OR UPDATE FOR EACH ROW`. They compute the actor, the
-- depot, the data-source and a column diff -- and then record an EVENT. **They never ask
-- the shield whether the transition was legal.** So the fix is not a new mechanism; it is
-- one call inside a trigger that already runs on every transition. Nothing is duplicated
-- (rule 5) and nothing new has to be kept in step.
--
-- `ottoq_shield_probe` is likewise already the right entry point and needed no change: it
-- selects every active/shadow rule whose `applies_to_actions` contains the action context,
-- evaluates each through `ottoq_evaluate_rule_core` (which writes the evaluation row), and
-- returns **`would_block`** -- *"this rule, if enforced, blocks the action"*. That column is
-- purpose-built for measure-before-enforce. Because selection is driven by the rule's own
-- declaration, this probe also picks up any future rule that declares the same context,
-- with no second list to maintain.
--
-- ══ 3. THE PART THAT WOULD HAVE MADE A NAIVE WIRING WORSE THAN NOTHING ═════
--
-- `ottoq_eval_sm_transition_validity` reads `from_state`, `to_state` and `actor_type`, and
-- it fails a transition **twice over**: once if the (entity_kind, from, to) triple is not in
-- `ottoq_state_transitions`, and again if `actor_type` is not in that row's
-- `allowed_actor_types`. Measured before writing a line of this:
--
--   ottoq_state_transitions, status='active'     vehicle 41 · stall 10 · bess 17 · task 14
--   rows with an EMPTY allowed_actor_types       **0 of 82**
--   rows admitting 'unknown'                     **0 of 82**
--   vehicle/stall state_changed events whose
--     actor_type is 'unknown'                    **129,060 of 129,060**
--
-- The evaluator defaults `actor_type` to `'unknown'` when neither the context nor
-- `current_setting('ottoq.actor_type')` supplies one, and **nothing in this database sets
-- that GUC on the state-change path** (the one function that looked like it does,
-- `ottoq_trg_attribution_attach`, is about SDR cost attribution and matched only because it
-- passes a literal actor to an event). So a probe wired today would have failed **every**
-- transition on the role gate, and not one of those failures would have been about
-- state-machine legality. That is worse than no probe: it is a coverage number that looks
-- like enforcement and measures a missing input.
--
-- Two further traps the wiring avoids rather than discovers later:
--
--   * **The vacuous pass.** With `from_state` or `to_state` absent the evaluator returns
--     TRUE, reason `'no transition context'`. A probe that omitted them would log green
--     forever. Both are passed explicitly.
--   * **The no-op pass.** The trigger's churn filter deliberately lets `current_soc`
--     through as real signal, so SoC-only updates reach the probe site with the state
--     unchanged; the evaluator would return its `'no-op transition'` pass tens of thousands
--     of times. The probe is guarded on the state column actually moving. Logging green for
--     a comparison never made is the G28 defect class.
--
-- ══ 4. SO THIS MIGRATION DOES TWO THINGS, IN THE ONLY ORDER THAT WORKS ═════
--
-- **(a) Attribute the engine.** Inside a sim run the engine is the actor -- the twin
-- simulates its own technicians -- so the trigger now says `ottoq_engine`, which 62 of the
-- 82 transitions admit. With no active run it keeps `'unknown'`, because there the actor
-- genuinely is unidentified and inventing one would be worse than admitting none.
-- **Verified safe for KPI 4** before changing it: `ottoq_kpi_touch_actor_types` marks BOTH
-- `'unknown'` and `'ottoq_engine'` as `human_actor=false`, so `touch_events_per_turn` --
-- human interventions per asset-turn -- cannot move. Had `ottoq_engine` been marked human,
-- this change would have silently inflated a published KPI.
--
-- **(b) Probe the transition.** MEASURE ONLY. Both rules are declared
-- `enforcement='block'` with `override_allowed=false`, and nothing here acts on
-- `would_block`. Promotion is a separate decision under 2.9a's blind-spot doctrine, and it
-- cannot responsibly be taken before the pass rate is known -- which, until this migration,
-- was unknowable. Each probe carries its own exception handler: a probe must never abort a
-- tick.
--
-- ══ 5. WHAT THIS DOES NOT CLOSE ═══════════════════════════════════════════
--
-- Seven of the nine remain unevaluated and are deliberately out of scope, each for a
-- reason rather than for lack of time:
--
--   SM.006 `bess_state_change` -- same shape as these two and the next one to do; it needs
--     the BESS state column's own trigger, which is a different table and deserves its own
--     before/after measurement.
--   SM.005 `progression_decision_insert` -- wants a trigger on the decision ledger, not a
--     transition; the override path it judges may not occur in the twin at all, so a probe
--     could report a population of zero and that must be established first.
--   HW.006 `task_completion` -- needs a completion probe point, which does not exist; that
--     is a new probe site, not a new caller.
--   SM.004 -- gates `tech_override`, `emergency_stop`, `brain_pause` and four more. Those
--     actions may never be taken in the twin. Wiring a probe for an action nobody performs
--     would be the eighth "exists and never called" instance in this repo.
--   SLA.002 / TW.002 / TW.004 -- `arrival`, staging and tariff advisories; warning and info
--     severity, and the first needs an arrival probe point that also does not exist.
--
-- **So G44 moves from twenty-one of thirty to twenty-three of thirty, at seven probe points
-- rather than six** -- and the honest sentence stays a WIRING count, not a protection count,
-- because these two are measured and not enforced.

-- ══ P0 PREFLIGHT ═══════════════════════════════════════════════════════════

DO $p0$
DECLARE v_n int; v_unknown bigint; v_total bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status IN ('running','paused')) THEN
    RAISE EXCEPTION '0387 P0: a sim run is running or paused -- this rewrites two triggers on the tick path';
  END IF;

  -- the premise: these two rules must currently have NO evaluations
  SELECT count(*) INTO v_n FROM public.ottoq_rule_evaluations
   WHERE rule_code IN ('SM.001.vehicle_transition_validity','SM.003.stall_transition_validity');
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0387 P0: SM.001/SM.003 already have % evaluations -- the premise of this migration is gone', v_n;
  END IF;

  -- the obstacle: no declared transition may admit 'unknown', or the attribution half is pointless
  SELECT count(*) INTO v_n FROM public.ottoq_state_transitions
   WHERE status='active' AND 'unknown' = ANY(allowed_actor_types);
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0387 P0: % active transitions admit ''unknown'' -- re-read section 3 before applying', v_n;
  END IF;

  -- and the actor must in fact be unset today
  SELECT count(*) FILTER (WHERE actor_type='unknown'), count(*) INTO v_unknown, v_total
    FROM public.ottoq_events
   WHERE event_type IN ('vehicle.state_changed','stall.state_changed');
  RAISE NOTICE '0387 P0: % of % state-change events carry actor_type=unknown', v_unknown, v_total;

  -- KPI 4 must not be able to move
  IF EXISTS (SELECT 1 FROM public.ottoq_kpi_touch_actor_types
              WHERE actor_type IN ('unknown','ottoq_engine') AND human_actor) THEN
    RAISE EXCEPTION '0387 P0: one of unknown/ottoq_engine is marked human_actor -- attributing the engine would move touch_events_per_turn';
  END IF;
  RAISE NOTICE '0387 P0: preconditions hold';
END $p0$;

-- ══ THE TWO TRIGGER FUNCTIONS ══════════════════════════════════════════════
-- Both reproduced verbatim from pg_get_functiondef at 2026-09-20 18:54 UTC with exactly
-- two insertions each, every anchor asserted unique before this file was written. No
-- existing statement is altered -- the event each trigger records is unchanged except for
-- the actor it now names truthfully.

CREATE OR REPLACE FUNCTION public.ottoq_vehicles_state_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  DECLARE
    v_payload      JSONB;
    v_diff         JSONB;
    v_actor_type   TEXT := COALESCE(NULLIF(current_setting('ottoq.actor_type', TRUE), ''), 'unknown');
    v_actor_id     TEXT := NULLIF(current_setting('ottoq.actor_id', TRUE), '');
    v_event_type   TEXT;
    v_run          UUID;
    v_depot        UUID;
    v_data_source  TEXT;
  BEGIN
    v_run := ottoq.ottoq_active_sim_run_id();

    -- ══════════════════════════ 0387 (G44) ══════════════════════════
    -- ATTRIBUTE THE ENGINE. `ottoq.actor_type` is read here and by
    -- ottoq_eval_sm_transition_validity, and NOTHING IN THE DATABASE SETS IT on this
    -- path: measured, 129,060 of 129,060 vehicle/stall state_changed events carried
    -- actor_type='unknown'. Meanwhile all 82 rows of ottoq_state_transitions declare a
    -- non-empty allowed_actor_types and NOT ONE admits 'unknown', so probing the
    -- state-machine rules without fixing this first would have failed every transition
    -- on the role gate and said nothing at all about transition legality.
    -- Inside a sim run the engine is the actor -- the twin simulates its technicians --
    -- so say so. Production (no active run) keeps 'unknown', because there it genuinely
    -- is unidentified and inventing an actor would be worse than admitting none.
    -- SAFE FOR KPI 4: ottoq_kpi_touch_actor_types marks BOTH 'unknown' and
    -- 'ottoq_engine' human_actor=false, so touch_events_per_turn cannot move.
    IF v_actor_type = 'unknown' AND v_run IS NOT NULL THEN
      v_actor_type := 'ottoq_engine';
    END IF;

    -- 0228 (G16). Provenance is a property of the FEED, not of whether a run id
    -- happened to be set. The certification harness resets the fleet before
    -- sim_start_run points the GUC at the new run, so the old rule stamped 116
    -- events a pair 'production' about work the twin did. 0073 settled this for
    -- the SDR emitter -- feed_mode 'external' is the real world, everything else
    -- is the twin -- and this is that decision, propagated.
    --
    -- current_depot_id first, home_depot_id as the fallback: a deployed vehicle
    -- has no current depot and still belongs to one. If neither is set there is
    -- nothing to ask, and the old run-id rule is the honest default.
    v_depot := COALESCE(NEW.current_depot_id, NEW.home_depot_id);
    SELECT CASE WHEN d.feed_mode = 'external' THEN 'production' ELSE 'twin' END
      INTO v_data_source
      FROM public.depots d WHERE d.id = v_depot;
    v_data_source := COALESCE(
      v_data_source,
      CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END);

    IF TG_OP = 'INSERT' THEN
      v_event_type := 'vehicle.created';
      v_payload := jsonb_build_object('new', to_jsonb(NEW));
      PERFORM ottoq_record_event(
        p_actor_type        := v_actor_type,
        p_actor_id          := v_actor_id,
        p_event_type        := v_event_type,
        p_entity_type       := 'vehicle',
        p_entity_id         := NEW.id,
        p_depot_id          := v_depot,   -- 0228 part B: was never passed
        p_fleet_operator_id := NEW.fleet_operator_id,
        p_payload           := v_payload,
        p_new_state         := to_jsonb(NEW),
        p_ingest_source     := 'trigger',
        p_data_source       := v_data_source,
        p_sim_run_id        := v_run
      );
      RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
      IF to_jsonb(OLD) = to_jsonb(NEW) THEN
        RETURN NEW;
      END IF;
      v_diff := ottoq_jsonb_diff(to_jsonb(OLD), to_jsonb(NEW));
      -- ══════════════════════════ 0015 ══════════════════════════
      -- Skip pure-timestamp churn: only clock columns moved, no state change.
      -- `last_state_change` ADDED. It is the timestamp OF a state change, and the twin
      -- stamps it on rows whose state did not move -- which is why 56,544 of 69,917
      -- `vehicle.state_changed` rows (80.9%) carried a diff of nothing but these three
      -- clock keys. An event asserting a state change in which nothing changed state is
      -- information-free, and dropping it cannot affect ottoq_event_new_state()'s
      -- fold-forward reconstruction, which only ever reads non-clock diff keys.
      -- `current_soc` is deliberately NOT in this list: SOC is real signal.
      IF NOT EXISTS (
        SELECT 1 FROM jsonb_object_keys(v_diff) AS k
         WHERE k <> ALL (ARRAY['updated_at','current_soc_updated_at','last_state_change'])
      ) THEN
        RETURN NEW;
      END IF;

      -- ══════════════════════════ 0387 (G44) ══════════════════════════
      -- SM.001.vehicle_transition_validity has had a callable evaluator and NO CALLER since it was written. Probe it
      -- HERE because a state-machine invariant is a property of a TRANSITION, and all six
      -- existing probe points sit where something STARTS -- db/checks/0192 and 0273
      -- diagnosed exactly that and stopped at the diagnosis.
      --
      -- MEASURE ONLY. ottoq_shield_probe logs every evaluation and returns `would_block`;
      -- nothing here reads it. The rule is declared enforcement='block', and promoting it
      -- is a SEPARATE decision under 2.9a's blind-spot doctrine -- which cannot be taken
      -- before the pass rate is known, and until this line existed it could not be.
      --
      -- Guarded on the state column actually moving: without that, SoC-only updates reach
      -- this point (the churn filter above deliberately lets current_soc through as real
      -- signal) and the evaluator would return its 'no-op transition' pass tens of
      -- thousands of times -- logging green for comparisons it never made, which is the
      -- G28 defect class.
      --
      -- Own exception handler: a probe must never abort a tick.
      IF NEW.current_state IS DISTINCT FROM OLD.current_state THEN
        BEGIN
          PERFORM 1 FROM public.ottoq_shield_probe(
            p_action_context    := 'vehicle_state_change',
            p_entity_type       := 'vehicle',
            p_entity_id         := NEW.id,
            p_context           := jsonb_build_object(
                                     'from_state',  OLD.current_state,
                                     'to_state',    NEW.current_state,
                                     'actor_type',  v_actor_type),
            p_fleet_operator_id := NEW.fleet_operator_id,
            p_depot_id          := v_depot);
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'ottoq_vehicles_state_change: SM.001 probe FAILED SAFELY %: %',
            SQLSTATE, SQLERRM;
        END;
      END IF;
      v_event_type := 'vehicle.state_changed';
      v_payload := jsonb_build_object('diff', v_diff);
      PERFORM ottoq_record_event(
        p_actor_type        := v_actor_type,
        p_actor_id          := v_actor_id,
        p_event_type        := v_event_type,
        p_entity_type       := 'vehicle',
        p_entity_id         := NEW.id,
        p_depot_id          := v_depot,   -- 0228 part B: was never passed
        p_fleet_operator_id := NEW.fleet_operator_id,
        p_payload           := v_payload,
        p_new_state         := to_jsonb(NEW),
        p_ingest_source     := 'trigger',
        p_data_source       := v_data_source,
        p_sim_run_id        := v_run
      );
      RETURN NEW;
    END IF;
    RETURN NEW;
  END;
  $function$;

CREATE OR REPLACE FUNCTION public.ottoq_stalls_state_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
  DECLARE
    v_payload      JSONB;
    v_diff         JSONB;
    v_actor_type   TEXT := COALESCE(NULLIF(current_setting('ottoq.actor_type', TRUE), ''), 'unknown');
    v_actor_id     TEXT := NULLIF(current_setting('ottoq.actor_id', TRUE), '');
    v_event_type   TEXT;
    v_run          UUID;
    v_data_source  TEXT;
  BEGIN
    v_run := ottoq.ottoq_active_sim_run_id();

    -- ══════════════════════════ 0387 (G44) ══════════════════════════
    -- ATTRIBUTE THE ENGINE. `ottoq.actor_type` is read here and by
    -- ottoq_eval_sm_transition_validity, and NOTHING IN THE DATABASE SETS IT on this
    -- path: measured, 129,060 of 129,060 vehicle/stall state_changed events carried
    -- actor_type='unknown'. Meanwhile all 82 rows of ottoq_state_transitions declare a
    -- non-empty allowed_actor_types and NOT ONE admits 'unknown', so probing the
    -- state-machine rules without fixing this first would have failed every transition
    -- on the role gate and said nothing at all about transition legality.
    -- Inside a sim run the engine is the actor -- the twin simulates its technicians --
    -- so say so. Production (no active run) keeps 'unknown', because there it genuinely
    -- is unidentified and inventing an actor would be worse than admitting none.
    -- SAFE FOR KPI 4: ottoq_kpi_touch_actor_types marks BOTH 'unknown' and
    -- 'ottoq_engine' human_actor=false, so touch_events_per_turn cannot move.
    IF v_actor_type = 'unknown' AND v_run IS NOT NULL THEN
      v_actor_type := 'ottoq_engine';
    END IF;

    -- 0228 (G16). See the vehicles trigger. A stall always carries its depot,
    -- so there is no COALESCE chain to walk -- but the same fallback is kept
    -- for the case where the depot row is missing, because a trigger that
    -- cannot answer should say what it used to say rather than say NULL.
    SELECT CASE WHEN d.feed_mode = 'external' THEN 'production' ELSE 'twin' END
      INTO v_data_source
      FROM public.depots d WHERE d.id = NEW.depot_id;
    v_data_source := COALESCE(
      v_data_source,
      CASE WHEN v_run IS NULL THEN 'production' ELSE 'twin' END);

    IF TG_OP = 'INSERT' THEN
      v_event_type := 'stall.created';
      PERFORM ottoq_record_event(
        p_actor_type    := v_actor_type,
        p_actor_id      := v_actor_id,
        p_event_type    := v_event_type,
        p_entity_type   := 'stall',
        p_entity_id     := NEW.id,
        p_depot_id      := NEW.depot_id,
        p_payload       := jsonb_build_object('new', to_jsonb(NEW)),
        p_new_state     := to_jsonb(NEW),
        p_ingest_source := 'trigger',
        p_data_source   := v_data_source,
        p_sim_run_id    := v_run
      );
      RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
      IF to_jsonb(OLD) = to_jsonb(NEW) THEN RETURN NEW; END IF;
      v_diff := ottoq_jsonb_diff(to_jsonb(OLD), to_jsonb(NEW));
      IF NOT EXISTS (
        SELECT 1 FROM jsonb_object_keys(v_diff) AS k
         WHERE k <> ALL (ARRAY['updated_at','reservation_expires_at','reserved_at'])
      ) THEN
        RETURN NEW;
      END IF;

      -- ══════════════════════════ 0387 (G44) ══════════════════════════
      -- SM.003.stall_transition_validity has had a callable evaluator and NO CALLER since it was written. Probe it
      -- HERE because a state-machine invariant is a property of a TRANSITION, and all six
      -- existing probe points sit where something STARTS -- db/checks/0192 and 0273
      -- diagnosed exactly that and stopped at the diagnosis.
      --
      -- MEASURE ONLY. ottoq_shield_probe logs every evaluation and returns `would_block`;
      -- nothing here reads it. The rule is declared enforcement='block', and promoting it
      -- is a SEPARATE decision under 2.9a's blind-spot doctrine -- which cannot be taken
      -- before the pass rate is known, and until this line existed it could not be.
      --
      -- Guarded on the state column actually moving: without that, SoC-only updates reach
      -- this point (the churn filter above deliberately lets current_soc through as real
      -- signal) and the evaluator would return its 'no-op transition' pass tens of
      -- thousands of times -- logging green for comparisons it never made, which is the
      -- G28 defect class.
      --
      -- Own exception handler: a probe must never abort a tick.
      IF NEW.status IS DISTINCT FROM OLD.status THEN
        BEGIN
          PERFORM 1 FROM public.ottoq_shield_probe(
            p_action_context := 'stall_state_change',
            p_entity_type    := 'stall',
            p_entity_id      := NEW.id,
            p_context        := jsonb_build_object(
                                  'from_state', OLD.status,
                                  'to_state',   NEW.status,
                                  'actor_type', v_actor_type),
            p_depot_id       := NEW.depot_id);
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'ottoq_stalls_state_change: SM.003 probe FAILED SAFELY %: %',
            SQLSTATE, SQLERRM;
        END;
      END IF;
      v_event_type := 'stall.state_changed';
      v_payload := jsonb_build_object('diff', v_diff);
      PERFORM ottoq_record_event(
        p_actor_type     := v_actor_type,
        p_actor_id       := v_actor_id,
        p_event_type     := v_event_type,
        p_entity_type    := 'stall',
        p_entity_id      := NEW.id,
        p_depot_id       := NEW.depot_id,
        p_payload        := v_payload,
        p_new_state      := to_jsonb(NEW),
        p_ingest_source  := 'trigger',
        p_data_source    := v_data_source,
        p_sim_run_id     := v_run
      );
      RETURN NEW;
    END IF;
    RETURN NEW;
  END;
  $function$;

-- ══ POSTFLIGHT ════════════════════════════════════════════════════════════

DO $p1$
DECLARE v_n int;
BEGIN
  -- both probes present, both guarded, both attributing
  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.proname IN ('ottoq_vehicles_state_change','ottoq_stalls_state_change')
     AND p.prosrc LIKE '%ottoq_shield_probe%'
     AND p.prosrc LIKE '%IS DISTINCT FROM%'
     AND p.prosrc LIKE '%ottoq\_engine%'
     AND p.prosrc LIKE '%FAILED SAFELY%';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0387 P1: expected 2 patched triggers carrying probe+guard+attribution+handler, found %', v_n;
  END IF;

  -- the triggers must still be attached and enabled; a rewritten function that lost its
  -- trigger would be a silent no-op
  SELECT count(*) INTO v_n FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
   WHERE NOT t.tgisinternal
     AND p.proname IN ('ottoq_vehicles_state_change','ottoq_stalls_state_change')
     AND t.tgenabled = 'O';
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0387 P1: expected 2 enabled state-change triggers, found %', v_n;
  END IF;
  RAISE NOTICE '0387 P1: both triggers patched, attached and enabled';
END $p1$;

DO $p2$
DECLARE v_n int; v_rules text[];
BEGIN
  -- NO LIVE MUTATION HERE, DELIBERATELY. The obvious postflight is to perform a real
  -- transition and assert the probe logged -- and the way to undo it is RAISE, which inside
  -- a migration rolls back the migration, not the test. (Caught while writing this file.)
  -- So the transition path test is a SEPARATE rolled-back script, recorded in
  -- db/checks/0280, and what is asserted here is the thing a source grep cannot fake:
  -- that ottoq_shield_probe actually resolves these action contexts to these rules.
  SELECT array_agg(r.rule_code ORDER BY r.rule_code) INTO v_rules
    FROM public.ottoq_rules r
   WHERE r.status IN ('active','shadow')
     AND 'vehicle_state_change' = ANY(r.applies_to_actions);
  IF NOT ('SM.001.vehicle_transition_validity' = ANY(COALESCE(v_rules,'{}'::text[]))) THEN
    RAISE EXCEPTION '0387 P2: the probe context ''vehicle_state_change'' does not resolve to SM.001 (got %) -- the probe would evaluate nothing', v_rules;
  END IF;

  SELECT array_agg(r.rule_code ORDER BY r.rule_code) INTO v_rules
    FROM public.ottoq_rules r
   WHERE r.status IN ('active','shadow')
     AND 'stall_state_change' = ANY(r.applies_to_actions);
  IF NOT ('SM.003.stall_transition_validity' = ANY(COALESCE(v_rules,'{}'::text[]))) THEN
    RAISE EXCEPTION '0387 P2: the probe context ''stall_state_change'' does not resolve to SM.003 (got %) -- the probe would evaluate nothing', v_rules;
  END IF;

  -- and the evaluator must be reachable under the name the rule declares
  SELECT count(*) INTO v_n FROM public.ottoq_rules r
   WHERE r.rule_code IN ('SM.001.vehicle_transition_validity','SM.003.stall_transition_validity')
     AND r.status='active'
     AND to_regprocedure(r.evaluator_function || '(text,uuid,jsonb,jsonb)') IS NOT NULL;
  IF v_n < 2 THEN
    RAISE EXCEPTION '0387 P2: only % of 2 declared evaluators resolve to a callable function', v_n;
  END IF;
  RAISE NOTICE '0387 P2: both contexts resolve to their rule and both evaluators are callable';
END $p2$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0387_two_critical_state_machine_rules_had_a_caller_shaped_hole_and_the_input_they_need_did_not_exist', true,
  'G44, partially. SM.001 and SM.003 (both critical) had callable evaluators and no caller. '
  '0192 and 0273 diagnosed why -- a state-machine invariant is a property of a TRANSITION and '
  'all six live probe points sit where something STARTS -- and stopped at the diagnosis. The '
  'hook already existed: trg_ottoq_vehicles_state_change and trg_ottoq_stalls_state_change are '
  'attached, enabled, fire AFTER INSERT OR UPDATE FOR EACH ROW, compute the actor and diff, and '
  'record an EVENT without ever asking the shield. ottoq_shield_probe was already the right '
  'entry point, selecting rules by their own applies_to_actions and returning would_block. '
  'BUT A NAIVE WIRING WOULD HAVE BEEN WORSE THAN NOTHING: ottoq_eval_sm_transition_validity '
  'fails a transition either on legality or on the role gate, all 82 active rows of '
  'ottoq_state_transitions declare a non-empty allowed_actor_types, NOT ONE admits ''unknown'', '
  'and 129,060 of 129,060 vehicle/stall state_changed events carried actor_type=''unknown'' '
  'because nothing in the database sets that GUC on this path. So every transition would have '
  'failed the role gate and no failure would have been about state-machine legality. This '
  'therefore does two things in the only workable order: attributes the engine inside a sim run '
  '(ottoq_engine is admitted by 62 of 82 transitions; production keeps ''unknown'' because there '
  'the actor genuinely is unidentified), having first VERIFIED that ottoq_kpi_touch_actor_types '
  'marks both ''unknown'' and ''ottoq_engine'' human_actor=false so touch_events_per_turn cannot '
  'move; then probes the transition, MEASURE ONLY, guarded on the state column actually moving '
  '(the churn filter lets current_soc through, so an unguarded probe would log the evaluator''s '
  '''no-op transition'' pass tens of thousands of times -- the G28 shape) and passing from_state/'
  'to_state explicitly (absent them the evaluator returns a vacuous ''no transition context'' '
  'pass). Each probe has its own exception handler because a probe must never abort a tick. '
  'Nothing acts on would_block: both rules are enforcement=block and promotion is a separate '
  'decision under 2.9a, un-takeable before the pass rate is known. G44 moves from 21 of 30 at '
  'six probe points to 23 of 30 at seven, and stays a WIRING count rather than a protection '
  'count. Seven rules remain out of scope with a reason each (see the file header). '
  'forces_recert TRUE: the events atom moves because the actor is now named, and the rules atom '
  'moves because two rules now log.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
