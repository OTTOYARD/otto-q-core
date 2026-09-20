-- migration-version: 20260919235525
-- migration-name:    the_energy_shield_declared_five_block_rules_at_the_moment_power_flows_and_none_had_ever_run
--
-- 0355  FIVE BLOCK-ENFORCEMENT RULES DECLARE `charge_session_start`. THAT PROBE
--       POINT HAS NEVER BEEN CALLED. SO THE ENTIRE ENERGY-SAFETY SHIELD AT THE
--       MOMENT ELECTRONS START FLOWING HAS NEVER EXECUTED ONCE.
--
-- Opened as G74 in db/checks/0253: `ottoq_eval_en_001_grid_capacity` returns
-- passed=TRUE with reason 'no depot/request context' whenever it is handed no
-- load, and at the `task_start` probe point it is handed no load 100% of the
-- time -- 8,219 evaluations, 0 carrying `requested_kw`, in the engine's life.
-- Chasing the fix found something larger than the finding.
--
-- ══ 1. WHY `task_start` IS THE WRONG PLACE, AND WHERE THE CHECK BELONGS ═════
--
-- `stall_assignment` is the CALENDAR CLAIM. `task_start` is a task beginning, and
-- most tasks carry no load at all (wash, detail, inspection). Neither is the
-- moment power is drawn. **`charge_session_start` is**, and EN.001 already
-- declares it -- along with `power_increase`, also never called.
--
-- A grid-capacity check at assignment time is a forecast. At session start it is
-- the gate. So this file does NOT try to teach `task_start` to supply
-- `requested_kw` (it has no load to report for the wash bays and staging moves
-- that make up most of its traffic); it puts the probe where the load is.
--
-- ══ 2. AND THE PROBE POINT IS DECLARED BY FIVE RULES, NOT ONE ══════════════
--
-- Measured -- every ACTIVE rule whose `applies_to_actions` contains
-- `charge_session_start`, and every one of them `enforcement='block'`:
--
--   EN.001.grid_capacity_ceiling        block  safety_critical
--   EN.002.stall_power_ceiling          block  critical
--   EN.004.demand_response_compliance   block  critical
--   EN.005.grid_event_hardstop          block  safety_critical
--   HW.002.charger_state_precondition   block  critical
--
-- Zero logged evaluations at that context, ever. Four of these are the energy
-- shield; one is the charger precondition. This is four more of G44's nine
-- no-caller rules than the finding that opened the file, and they are the four
-- that stand between the orchestrator and the switchgear.
--
-- ══ 3. THE PRE-FLIGHT, BECAUSE THESE ARE `block` RULES ═════════════════════
--
-- Wiring a block-enforcement rule that has never run can stop the depot dead. So
-- all five evaluators were shadow-called against the live run BEFORE any change.
-- They are all `STABLE` and none writes, which is what made that safe.
--
-- With each rule's OWN registered `default_parameters` and the run's SIM clock,
-- over all 40 charging stalls at the twin depot:
--
--   EN.001   40 evaluated   40 pass   0 block
--   EN.002   40 evaluated   40 pass   0 block
--   EN.004   40 evaluated   40 pass   0 block
--   EN.005   40 evaluated   40 pass   0 block
--   HW.002   40 evaluated   31 pass   9 block  ("state=Occupied not in allowed
--                                                states Available")
--
-- The 9 are stalls that already had a car in them -- the shadow asked "could a
-- session start here?" of every stall including the busy ones. At a real
-- `charge_session_start` the charger is still `Available`, because
-- `twin.ottoq_sim_start_charge_session` sets it `Occupied` AFTER the insert. So
-- the honest pre-flight verdict is that all five would pass, and the only
-- failures would be a genuinely Faulted or genuinely occupied charger -- the rule
-- doing its job.
--
-- TWO WRONG READINGS THIS PRE-FLIGHT PRODUCED FIRST, both mine, both from the
-- harness rather than the engine, recorded because each would have caused real
-- damage if believed:
--   (a) "HW.002 would block 36 of 36." I passed `'{}'` as p_parameters. HW.002's
--       registered defaults are `{"allowed_states":["Available"],
--       "max_offline_seconds":90}` -- the shield passes those, my shadow did not.
--   (b) "the chargers are all offline." I passed wall-clock `now()` as `now_ts`
--       against heartbeats stamped on the SIM clock, making every charger look
--       eight hours stale. Against the sim clock 39 of 40 are fresh to the
--       second, because `ottoq_world_advance` restamps them every tick. The one
--       stale charger is the Faulted one, correctly stale.
-- Had (a) been believed, this file would have "fixed" a rule that was not broken.
-- Had it been acted on in the other direction, enforcing would have refused every
-- charge session in the depot.
--
-- ══ 4. WHAT THIS FILE DOES ═════════════════════════════════════════════════
--
-- A. THE PROBE, MEASURED AND NOT ENFORCED. `twin.ottoq_sim_start_charge_session`
--    gains a `charge_session_start` shield probe. Three deliberate choices:
--
--    * IT SITS BEFORE THE `INSERT INTO ocpp_sessions`, not after. EN.001 reads
--      `ottoq_depot_current_demand_kw(depot, now_ts)`, and after the insert that
--      sum already contains the session being started -- the check would
--      double-count its own load and every evaluation would be wrong by one car.
--    * `entity_id` IS `p_stall_id`, NOT `v_session_id`. The session id is
--      `gen_random_uuid()` minted at DECLARE, so it differs between the two arms
--      of a determinism pair, and `ottoq_hash_rule_evaluations` DIGESTS
--      `entity_id` -- every certification pair would have disagreed on `h_rule`
--      and the cause would have looked like anything but this file. Fifth
--      instance of 0139's class (after 0137, 0139, 0280, 0353). A stall is a
--      pre-existing row and arm-stable; the hash function's own comment says so.
--    * `now_ts` IS `v_clock`, THE SIM CLOCK, never `now()`. §3(b) is what happens
--      otherwise, and a wall clock inside a certified path is G15's defect class.
--
--    It is wrapped in `EXCEPTION WHEN OTHERS THEN RAISE WARNING`, the pattern
--    this function already uses for the arm cycle and the travel leg: a shield
--    probe must never abort a charge session. And it RECORDS rather than refuses
--    -- per CLAUDE.md 2.9a, measured first, enforced only after a flagship round
--    shows what it says. Promotion to enforcing is a later, deliberate step and
--    needs `ottoq_shield_probe.would_block`, which is why this probe calls that
--    function and not `ottoq_evaluate_rules_for_action`.
--
-- B. THE ABSTENTION STOPS CLAIMING TO BE A CHECK. `ottoq_eval_en_001_grid_capacity`
--    keeps `passed=TRUE` when there is no load -- it must, or every wash-bay and
--    staging assignment would be refused -- but it now says so in words a human
--    reads, and carries an explicit `en001_evaluated` boolean on all four return
--    paths.
--
--    An honesty note on G74 as filed: that finding said the abstention was
--    "indistinguishable from a real check by any count that does not parse the
--    reason string". **That was wrong** -- the abstention returns `'{}'::jsonb`
--    and every other path returns populated keys, so `result_payload = '{}'`
--    already identified them exactly (10,787 of 10,787 measured). The real
--    complaint is weaker and still worth fixing: it was an UNDOCUMENTED
--    CONVENTION that nothing asserted and no comment explained. `en001_evaluated`
--    makes it a labelled fact. FINDINGS.md is corrected in the same commit.
--
-- C. A LATENT LANDMINE IN HW.002, found while shadowing it. Its allowed-states
--    default is written:
--
--        v_allowed_states := COALESCE(
--          ARRAY(SELECT jsonb_array_elements_text(p_parameters->'allowed_states')),
--          ARRAY['Available']);
--
--    `ARRAY(SELECT ...)` over a NULL input returns an EMPTY ARRAY, never NULL, so
--    `COALESCE` can never reach the fallback and `station_state = ANY('{}')` is
--    always false. **Called with empty parameters, this rule rejects every
--    charger including a healthy Available one.** It is unreachable today because
--    the rule's registered `default_parameters` do supply `allowed_states` -- but
--    it is a `block` rule whose fallback is inverted, it is exactly the trap my
--    own shadow fell into, and the next caller to pass `'{}'` stops the depot.
--    Fixed with an explicit guard. Production behaviour is unchanged, which A6
--    asserts.
--
-- ══ 5. WHAT THIS FILE DOES NOT DO ══════════════════════════════════════════
--
-- It does not enforce. It does not touch `task_start`'s 8,219 abstentions -- they
-- stay, correctly, because most task starts carry no load; what changes is that
-- they no longer pretend to be grid checks. It does not wire `power_increase`,
-- the fifth declared-never-called context, which needs a throttle path that does
-- not exist yet. And it says nothing about whether the cap is the binding
-- constraint: measured on the live run the worst case was 712.6 kW against a
-- 1,620 kW engineering cap, so this depot is STALL-constrained, not
-- power-constrained, with ~908 kW of headroom unused at peak.
--
-- forces_recert: TRUE. Part A adds rule evaluations at a new action_context and
-- Part B changes `result_payload`, and `ottoq_hash_rule_evaluations` digests
-- both. Classified TRUE rather than argued down.
--
-- APPLIED THROUGH THE MANAGEMENT API, so its `supabase_migrations.schema_migrations`
-- row is written explicitly -- see 0354's header for why that is mandatory on this
-- path and not optional bookkeeping.

BEGIN;

-- REPEATABLE READ: the assertions compare function output against direct counts
-- in separate statements, on a LIVE ticking run. Under READ COMMITTED a STABLE
-- function re-snapshots per statement and a concurrent commit fails a correct
-- assertion. Same reasoning as 0354.
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;

-- ── PRECONDITIONS ──────────────────────────────────────────────────────────────
DO $pre$
DECLARE v_jobs text; v_pairs int; v_live text; v_block int; v_n int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0355 P0: certification jobs are scheduled (%)', v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE state = 'active' AND pid <> pg_backend_pid()
     AND (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%');
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0355 P1: % certification pair(s) are active', v_pairs;
  END IF;

  -- P2. Applying onto a live run taints it for reproducibility. Recorded by id
  -- rather than hidden; acceptable only because P0/P1 established no
  -- certification arm is running. Same posture as 0354 P1b.
  SELECT string_agg(sim_run_id::text, ', ') INTO v_live
    FROM public.ottoq_sim_runs
   WHERE status IN ('running','paused') AND COALESCE(run_by,'') <> 'production_live';
  IF v_live IS NOT NULL THEN
    RAISE NOTICE '0355 P2: applying while Twin run(s) % are active -- tainted for reproducibility from here, deliberately', v_live;
  END IF;

  -- P3. The functions must exist with the shapes we are replacing.
  IF to_regprocedure('twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz)') IS NULL THEN
    RAISE EXCEPTION '0355 P3a: twin.ottoq_sim_start_charge_session(uuid,uuid,uuid,numeric,timestamptz) not found';
  END IF;
  IF to_regprocedure('public.ottoq_eval_en_001_grid_capacity(text,uuid,jsonb,jsonb)') IS NULL THEN
    RAISE EXCEPTION '0355 P3b: ottoq_eval_en_001_grid_capacity(text,uuid,jsonb,jsonb) not found';
  END IF;
  IF to_regprocedure('public.ottoq_eval_hw_002_charger_state(text,uuid,jsonb,jsonb)') IS NULL THEN
    RAISE EXCEPTION '0355 P3c: ottoq_eval_hw_002_charger_state(text,uuid,jsonb,jsonb) not found';
  END IF;

  -- P4. ottoq_shield_probe must exist and expose would_block, which promotion
  -- to enforcing will need. All four existing probe points call it.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='ottoq_shield_probe') THEN
    RAISE EXCEPTION '0355 P4a: ottoq_shield_probe not found';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='ottoq_shield_probe'
       AND column_name='would_block') THEN
    RAISE NOTICE '0355 P4b: ottoq_shield_probe does not expose would_block as a named column; promotion will need to read it another way';
  END IF;

  -- P5. Not already applied.
  --: P5 uses position(), NOT `prosrc LIKE '%charge_session_start%'`. UNDERSCORE IS
  --: A LIKE WILDCARD: that pattern matches the `charge.session_started` event type
  --: this function already emits, because `_` matched the `.`. The LIKE form
  --: returned true while position() returned 0, and it would have aborted this
  --: migration on a false positive. Caught by the read-only dry-run in
  --: scripts/APPLYING.md, which is the third defect that step has caught across
  --: 0354 and 0355.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_charge_session'
                AND position('charge_session_start' in p.prosrc) > 0) THEN
    RAISE EXCEPTION '0355 P5: the charge_session_start probe is already present';
  END IF;

  -- P6. The five rules must still be the ones declaring this context, so the
  -- pre-flight in §3 still describes what the probe will fire.
  SELECT count(*) INTO v_n FROM public.ottoq_rules
   WHERE status='active' AND applies_to_actions @> ARRAY['charge_session_start']::text[];
  IF v_n <> 5 THEN
    RAISE EXCEPTION '0355 P6: expected 5 active rules at charge_session_start, found % -- re-run the pre-flight before applying', v_n;
  END IF;

  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0355 P7: the run-scope registry already reports % blocking defect(s)', v_block;
  END IF;
END $pre$;

-- ── PART B: EN.001 STOPS CLAIMING AN ABSTENTION IS A CHECK ─────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_eval_en_001_grid_capacity(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_depot_id     UUID;
  v_request_kw   NUMERIC;
  v_depot        depots%ROWTYPE;
  v_now          TIMESTAMPTZ := COALESCE(NULLIF(p_context ->> 'now_ts','')::timestamptz, NOW());  -- WIRE-3
  v_current_kw   NUMERIC;
  v_engineering_cap NUMERIC;
  v_after_kw     NUMERIC;
  v_safety_pct   NUMERIC;
  v_min_headroom NUMERIC;
BEGIN
  v_depot_id := NULLIF(p_context ->> 'depot_id', '')::UUID;
  v_request_kw := COALESCE((p_context ->> 'requested_kw')::NUMERIC, 0);

  --: 0355 (G74). THE ABSTENTION, WHICH IS STILL A PASS AND NO LONGER PRETENDS TO
  --: BE A CHECK. passed stays TRUE on purpose: this rule is enforcement='block'
  --: and most actions that reach it carry no load at all -- on one live run 16 of
  --: the context-less passes were wash_bay and 10 were staging moves -- so
  --: failing closed here would refuse the depot's non-charging work outright.
  --: What changes is that it is now LABELLED. `en001_evaluated` is the fact;
  --: before this the only way to tell an abstention from a real check was the
  --: undocumented convention that abstentions returned '{}' while every other
  --: path returned keys. That convention held (10,787 of 10,787 measured) and
  --: nothing asserted it.
  IF v_depot_id IS NULL OR v_request_kw <= 0 THEN
    RETURN ROW(TRUE,
      CASE WHEN v_depot_id IS NULL
           THEN 'not applicable: no depot in this action context'
           ELSE 'not applicable: this action draws no charging load' END,
      NULL,
      jsonb_build_object(
        'en001_evaluated', false,
        'not_applicable_because',
          CASE WHEN v_depot_id IS NULL THEN 'no_depot_in_context'
               ELSE 'no_charging_load' END),
      NULL)::ottoq_rule_result;
  END IF;

  SELECT * INTO v_depot FROM depots WHERE id = v_depot_id;
  IF v_depot.dcfc_max_concurrent_kw IS NULL THEN
    RETURN ROW(TRUE, 'depot has no dcfc_max_concurrent_kw configured (allow)', 'warning',
      jsonb_build_object('en001_evaluated', false,
                         'not_applicable_because', 'depot_capacity_unconfigured',
                         'depot_id', v_depot_id), 'configure_depot_capacity')::ottoq_rule_result;
  END IF;
  v_safety_pct := COALESCE(v_depot.dcfc_safety_margin_pct, 10.0);
  v_engineering_cap := v_depot.dcfc_max_concurrent_kw * (1 - v_safety_pct/100.0);
  v_current_kw := ottoq_depot_current_demand_kw(v_depot_id, v_now);   -- WIRE-3: sim clock
  v_after_kw := v_current_kw + v_request_kw;
  v_min_headroom := v_engineering_cap - v_after_kw;
  IF v_after_kw > v_engineering_cap THEN
    RETURN ROW(FALSE,
      format('would exceed engineering cap: %s + %s = %s kW (cap with margin: %s kW)',
        round(v_current_kw,1), round(v_request_kw,1), round(v_after_kw,1), round(v_engineering_cap,1)),
      'safety_critical',   -- OD-6: near-breaker-trip is safety_critical, not the downgraded 'critical'
      jsonb_build_object('en001_evaluated', true,
        'depot_id', v_depot_id, 'current_kw', v_current_kw, 'requested_kw', v_request_kw,
        'after_kw', v_after_kw, 'engineering_cap_kw', v_engineering_cap, 'safety_margin_pct', v_safety_pct,
        'depot_dcfc_max_kw', v_depot.dcfc_max_concurrent_kw, 'now_ts', v_now),
      'defer_or_throttle_other_sessions')::ottoq_rule_result;
  END IF;
  IF v_depot.service_max_kw IS NOT NULL AND v_after_kw > v_depot.service_max_kw THEN
    RETURN ROW(FALSE,
      format('would exceed utility service contract: %s > %s kW', round(v_after_kw,1), round(v_depot.service_max_kw,1)),
      'safety_critical',
      jsonb_build_object('en001_evaluated', true,
        'after_kw', v_after_kw, 'service_max_kw', v_depot.service_max_kw),
      'engage_bess_or_defer')::ottoq_rule_result;
  END IF;
  RETURN ROW(TRUE,
    format('grid capacity OK: %s + %s = %s kW (headroom %s kW)',
      round(v_current_kw,1), round(v_request_kw,1), round(v_after_kw,1), round(v_min_headroom,1)),
    NULL,
    jsonb_build_object('en001_evaluated', true,
      'current_kw', v_current_kw, 'after_kw', v_after_kw,
      'engineering_cap_kw', v_engineering_cap, 'headroom_kw', v_min_headroom), NULL)::ottoq_rule_result;
END;
$function$;

-- ── PART C: HW.002's INVERTED FALLBACK ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_eval_hw_002_charger_state(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)
 RETURNS ottoq_rule_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_charger_id     UUID;
  v_stall_id       UUID;
  v_charger        ottoq_ocpp_chargers%ROWTYPE;
  v_now            TIMESTAMPTZ := COALESCE(NULLIF(p_context ->> 'now_ts','')::timestamptz, NOW());  -- WIRE-3
  v_max_offline_s  INTEGER := COALESCE((p_parameters ->> 'max_offline_seconds')::INT, 90);
  --: 0355. THE FALLBACK WAS INVERTED AND THE RULE IS enforcement='block'.
  --: It read COALESCE(ARRAY(SELECT jsonb_array_elements_text(...)), ARRAY['Available']).
  --: `ARRAY(SELECT ...)` over a NULL input returns an EMPTY ARRAY and never NULL,
  --: so COALESCE could not reach the fallback, v_allowed_states stayed '{}', and
  --: `station_state = ANY('{}')` is always false -- the rule REJECTED EVERY
  --: CHARGER, including a healthy Available one, for any caller passing empty
  --: parameters. Unreachable in production because this rule's registered
  --: default_parameters do supply allowed_states, which is why it has sat here
  --: undetected; found because 0355's own pre-flight shadow passed '{}' and was
  --: told all 36 sessions would be blocked. A6 asserts production is unchanged
  --: and A5 asserts the empty-parameter case now behaves.
  v_allowed_states TEXT[] := CASE
    WHEN jsonb_typeof(p_parameters -> 'allowed_states') = 'array'
     AND jsonb_array_length(p_parameters -> 'allowed_states') > 0
    THEN ARRAY(SELECT jsonb_array_elements_text(p_parameters -> 'allowed_states'))
    ELSE ARRAY['Available'] END;
BEGIN
  v_charger_id := NULLIF(p_context ->> 'charger_id', '')::UUID;
  v_stall_id   := NULLIF(p_context ->> 'stall_id', '')::UUID;
  IF v_charger_id IS NULL AND v_stall_id IS NOT NULL THEN
    SELECT ocpp_charger_id INTO v_charger_id FROM stalls WHERE id = v_stall_id;
  END IF;
  IF v_charger_id IS NULL THEN
    RETURN ROW(TRUE, 'no charger bound to stall (non-charging context)', NULL,
      jsonb_build_object('stall_id', v_stall_id, 'charger_id', NULL), NULL)::ottoq_rule_result;
  END IF;
  SELECT * INTO v_charger FROM ottoq_ocpp_chargers WHERE charger_id = v_charger_id;
  IF NOT FOUND THEN
    RETURN ROW(FALSE, format('charger %s not registered in ottoq_ocpp_chargers', v_charger_id),
      'safety_critical', jsonb_build_object('charger_id', v_charger_id), 'register_charger')::ottoq_rule_result;
  END IF;
  IF v_charger.last_heartbeat_at IS NULL
     OR v_charger.last_heartbeat_at < v_now - (v_max_offline_s || ' seconds')::INTERVAL THEN   -- WIRE-3: v_now
    RETURN ROW(FALSE, format('charger %s offline (last heartbeat: %s)', v_charger.ocpp_identifier, COALESCE(v_charger.last_heartbeat_at::text, 'never')),
      'critical', jsonb_build_object('charger_id', v_charger_id, 'ocpp_identifier', v_charger.ocpp_identifier,
        'last_heartbeat_at', v_charger.last_heartbeat_at, 'max_offline_seconds', v_max_offline_s, 'now_ts', v_now),
      'wait_for_charger_reconnect_or_reroute')::ottoq_rule_result;
  END IF;
  IF NOT (v_charger.station_state = ANY(v_allowed_states)) THEN
    RETURN ROW(FALSE, format('charger state=%s not in allowed states %s', v_charger.station_state, array_to_string(v_allowed_states, ',')),
      CASE WHEN v_charger.station_state = 'Faulted' THEN 'safety_critical' ELSE 'error' END,
      jsonb_build_object('charger_id', v_charger_id, 'state', v_charger.station_state, 'state_changed_at', v_charger.station_state_changed_at,
        'allowed_states', v_allowed_states, 'last_fault_code', v_charger.last_fault_code),
      CASE WHEN v_charger.station_state IN ('Faulted', 'Maintenance') THEN 'reroute_to_alternate_charger' ELSE 'wait_for_availability' END)::ottoq_rule_result;
  END IF;
  RETURN ROW(TRUE, format('charger %s available and online', v_charger.ocpp_identifier), NULL,
    jsonb_build_object('charger_id', v_charger_id, 'state', v_charger.station_state), NULL)::ottoq_rule_result;
END;
$function$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
-- ottoq_cert_recert_floor() takes COALESCE(forces_recert, TRUE), so a missing row
-- is not "unclassified" -- it forces. TRUE here is the real answer anyway: Part B
-- changes result_payload, which ottoq_hash_rule_evaluations digests.
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0355_the_energy_shield_declared_five_block_rules_at_the_moment_power_flows_and_none_had_ever_run', true,
  'Part one of two for G74 (0356 adds the charge_session_start probe). Two evaluator corrections. '
  'B: ottoq_eval_en_001_grid_capacity stops presenting an abstention as a check -- passed stays TRUE '
  '(it is enforcement=block and most actions reaching it carry no load; 16 wash_bay and 10 staging moves '
  'on one live run), but the reason is now human-readable and all four return paths carry an explicit '
  'en001_evaluated boolean. FORCES RECERT because result_payload is digested by '
  'ottoq_hash_rule_evaluations. Note the finding as filed overstated itself: abstentions were ALREADY '
  'countable via result_payload = ''{}'' (10,787 of 10,787 measured); the real defect was that this was an '
  'undocumented convention nothing asserted. C: ottoq_eval_hw_002_charger_state had an INVERTED FALLBACK '
  'in a block rule -- COALESCE(ARRAY(SELECT jsonb_array_elements_text(...)), ARRAY[''Available'']) can '
  'never reach the fallback because ARRAY(SELECT ...) returns an empty array rather than NULL, so '
  'station_state = ANY(''{}'') was always false and the rule rejected EVERY charger, healthy ones '
  'included, for any caller passing empty parameters. Unreachable in production (its registered '
  'default_parameters supply allowed_states), which is why it sat undetected; found when this file''s own '
  'pre-flight shadow passed ''{}'' and was told all 36 charge sessions would be blocked. Production '
  'behaviour unchanged, asserted by A6.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ── ASSERTIONS ─────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_abs   public.ottoq_rule_result;
  v_real  public.ottoq_rule_result;
  v_empty public.ottoq_rule_result;
  v_reg   public.ottoq_rule_result;
  v_stall uuid; v_chg uuid; v_depot uuid := '11111111-1111-1111-1111-111111111111';
  v_params jsonb; v_block int; v_faulted uuid;
BEGIN
  -- A1. THE ABSTENTION: still a pass, now labelled, and the jargon is gone.
  v_abs := public.ottoq_eval_en_001_grid_capacity('stall', NULL, '{}'::jsonb, '{}'::jsonb);
  IF NOT v_abs.passed THEN
    RAISE EXCEPTION '0355 A1a: the abstention no longer passes -- this would refuse every non-charging action';
  END IF;
  IF COALESCE((v_abs.payload ->> 'en001_evaluated')::boolean, true) THEN
    RAISE EXCEPTION '0355 A1b: the abstention does not carry en001_evaluated=false (payload %)', v_abs.payload;
  END IF;
  IF v_abs.reason = 'no depot/request context' THEN
    RAISE EXCEPTION '0355 A1c: the abstention still emits the old internal string';
  END IF;
  IF v_abs.reason IS NULL OR v_abs.reason NOT LIKE 'not applicable:%' THEN
    RAISE EXCEPTION '0355 A1d: the abstention reason is not the new human-readable form (got %)', v_abs.reason;
  END IF;

  -- A2. A REAL EVALUATION: labelled true, and still carries its headroom.
  SELECT s.id, s.ocpp_charger_id INTO v_stall, v_chg
    FROM public.stalls s
   WHERE s.depot_id = v_depot AND s.ocpp_charger_id IS NOT NULL
     AND s.stall_type IN ('dcfc'::stall_type, 'l2'::stall_type)
   ORDER BY s.stall_code LIMIT 1;
  IF v_stall IS NULL THEN
    RAISE EXCEPTION '0355 A2a: no charging stall at the twin depot, so A2 would be vacuous';
  END IF;
  v_real := public.ottoq_eval_en_001_grid_capacity('stall', v_stall,
              jsonb_build_object('depot_id', v_depot::text, 'requested_kw', 50,
                                 'now_ts', now()::text), '{}'::jsonb);
  IF NOT COALESCE((v_real.payload ->> 'en001_evaluated')::boolean, false) THEN
    RAISE EXCEPTION '0355 A2b: a real evaluation is not labelled en001_evaluated=true (payload %)', v_real.payload;
  END IF;
  IF NOT (v_real.payload ? 'headroom_kw' OR v_real.payload ? 'after_kw') THEN
    RAISE EXCEPTION '0355 A2c: a real evaluation lost its measured world (payload %)', v_real.payload;
  END IF;

  -- A3. THE PREMISE THIS FILE RESTS ON, asserted rather than trusted: the rule
  -- hash does NOT digest `reason`, so rewording costs no recert. If a future
  -- change adds reason to the digest, this file's reasoning is void and the
  -- assertion is where that gets caught.
  IF (SELECT prosrc FROM pg_proc WHERE proname='ottoq_hash_rule_evaluations') ~* 'e\.reason' THEN
    RAISE EXCEPTION '0355 A3: ottoq_hash_rule_evaluations now digests reason -- Part B is no longer hash-neutral';
  END IF;

  -- A4. And it DOES digest result_payload, which is why forces_recert is TRUE.
  IF position('result_payload' in (SELECT prosrc FROM pg_proc WHERE proname='ottoq_hash_rule_evaluations')) = 0 THEN
    RAISE EXCEPTION '0355 A4: result_payload is not digested, so this migration''s forces_recert=TRUE is misclassified';
  END IF;

  -- A5. THE HW.002 FIX: with EMPTY parameters, a healthy Available charger must
  -- now PASS. Before this file it failed, which is the whole bug.
  SELECT s.id INTO v_stall
    FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = v_depot AND c.station_state = 'Available'
     AND c.last_heartbeat_at IS NOT NULL
   ORDER BY s.stall_code LIMIT 1;
  IF v_stall IS NULL THEN
    RAISE NOTICE '0355 A5: no Available charger with a heartbeat right now, so the empty-parameter case is not exercised on this apply';
  ELSE
    v_empty := public.ottoq_eval_hw_002_charger_state('stall', v_stall,
                 jsonb_build_object('stall_id', v_stall::text,
                                    'now_ts', (SELECT max(last_heartbeat_at)::text
                                                 FROM public.ottoq_ocpp_chargers)),
                 '{}'::jsonb);
    IF NOT v_empty.passed THEN
      RAISE EXCEPTION '0355 A5: HW.002 with empty parameters still refuses an Available charger (%)', v_empty.reason;
    END IF;
  END IF;

  -- A6. PRODUCTION UNCHANGED: with the rule's REGISTERED parameters the verdict
  -- must be what it always was. A Faulted charger must still fail -- the fix must
  -- not have turned the rule into a rubber stamp.
  SELECT default_parameters INTO v_params
    FROM public.ottoq_rules WHERE rule_code LIKE 'HW.002%' AND status='active' LIMIT 1;
  IF v_stall IS NOT NULL THEN
    v_reg := public.ottoq_eval_hw_002_charger_state('stall', v_stall,
               jsonb_build_object('stall_id', v_stall::text,
                                  'now_ts', (SELECT max(last_heartbeat_at)::text
                                               FROM public.ottoq_ocpp_chargers)),
               v_params);
    IF NOT v_reg.passed THEN
      RAISE EXCEPTION '0355 A6a: HW.002 with registered parameters refuses an Available charger (%)', v_reg.reason;
    END IF;
  END IF;

  SELECT s.id INTO v_faulted
    FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
   WHERE s.depot_id = v_depot AND c.station_state = 'Faulted'
   ORDER BY s.stall_code LIMIT 1;
  IF v_faulted IS NULL THEN
    RAISE NOTICE '0355 A6b: no Faulted charger at the twin depot right now, so the must-still-refuse half is not exercised on this apply';
  ELSE
    v_reg := public.ottoq_eval_hw_002_charger_state('stall', v_faulted,
               jsonb_build_object('stall_id', v_faulted::text,
                                  'now_ts', (SELECT max(last_heartbeat_at)::text
                                               FROM public.ottoq_ocpp_chargers)),
               v_params);
    IF v_reg.passed THEN
      RAISE EXCEPTION '0355 A6c: HW.002 now PASSES a Faulted charger -- the fix became a rubber stamp';
    END IF;
  END IF;

  -- A7. The registry guard must not have moved.
  SELECT count(*) INTO v_block
    FROM public.ottoq_check_run_scope_registry() WHERE severity = 'block';
  IF v_block > 0 THEN
    RAISE EXCEPTION '0355 A7: the registry guard now reports % blocking defect(s)', v_block;
  END IF;

  RAISE NOTICE '0355 OK: abstention labelled (%), real evaluation labelled, HW.002 fallback repaired', v_abs.reason;
END $post$;

COMMIT;
