-- migration-version: 20260921122812
-- migration-name:    the_bess_state_machine_gets_its_caller_and_the_table_gets_its_first_trigger_g96
--
-- 0399  G96, STEP 2 — THE LAST ONE. **SM.006 has had a callable evaluator and no caller since it
--       was written.** `0387` wired SM.001 and SM.003 the same way and deliberately left this one,
--       saying so in its own §5: *"SM.006 `bess_state_change` — same shape as these two and the
--       next one to do; it needs the BESS state column's own trigger, which is a different table
--       and deserves its own before/after measurement."* This is that measurement and that trigger.
--
-- `forces_recert` **TRUE**, and the reason is narrower than "a number moves". The rules atom is one
-- of the fourteen. This migration adds a NEW WRITER into it, and a new writer into an enforced atom
-- has to be proven to write identically in BOTH arms of a pair before the canon can rest on it —
-- ordering, timestamps and id minting are exactly where `0137`, `0139` and `0216` each went wrong.
-- Nothing else moves: no event is emitted (this table has never had a trigger, so it emits none
-- today and emits none after), and `ottoq.ottoq_world_fingerprint` hashes
-- `COALESCE(b.current_state,'-')` whose VALUES are untouched — `0397` already moved those.
--
-- **AND THE COST IS NOT ZERO, stated because `0397` was caught out by exactly this.** All **9**
-- canon columns currently read `status='current'`, `satisfies_floor=true`, certified 03:19–03:49
-- UTC today on engine_hash `cf3622a0`. The floor has fully drained. So this costs **nine**
-- re-certifications, not the "free window" `0397` §1b wrongly assumed when five had already
-- cleared. A window that is draining is not a window, and a drained one is not either.
--
-- ══ 1. THE BEFORE-MEASUREMENT, WHICH IS WHAT `0387` ASKED FOR ══════════════
--
-- Every transition the twin depot's battery has ever made, from consecutive `bess_snapshots.status`
-- per `system_id`, scored by hand against SM.006 **v2** (the transition matrix plus the role gate)
-- with the actor this trigger will supply:
--
--   from        → to            n       in matrix   ottoq_engine allowed   verdict
--   standby     → charging      7,731   yes         yes                    pass
--   charging    → standby       7,716   yes         yes                    pass
--   discharging → standby       4,636   yes         yes                    pass
--   standby     → discharging   4,620   yes         yes                    pass
--   charging    → discharging   2,024   yes         yes                    pass
--   discharging → charging      2,008   yes         yes                    pass
--                              ──────
--                              28,735                                      **6 of 6 pass**
--
-- **So wiring the probe today refuses nothing.** That is the whole reason it can be wired at all,
-- and it is a fact about three preconditions that were each false within the last eighteen hours:
--
--   * **Before `0397` it would have refused 4,032 of 28,735 (14.0%)** — `charging → discharging`
--     and `discharging → charging` were absent from the matrix, which is where SM.006 v1's
--     "dwell-through-standby" promise actually lived. `0295` established from IEEE 1547-2018 that
--     no source requires that dwell, and `0397` inserted the two rows. (14.0% here against
--     `0285`'s 14.4% is the same finding on a larger, later sample, not a disagreement.)
--   * **Before `0397` the unit column said `idle`**, a word neither the enum nor the matrix knows,
--     so a probe reading it would have failed EVERY transition into or out of rest.
--   * **With no actor it would refuse all 28,735 on the role gate.** Not one of the 19 active
--     `bess` rows admits `'unknown'`, and `0387` measured 129,060 of 129,060 state-change events
--     carrying exactly that. The attribution below is not decoration; without it this probe
--     measures a missing input and reports it as a state-machine violation.
--
-- ══ 2. WHERE THE PROBE GOES, AND WHY NOT INSIDE A WRITER ═══════════════════
--
-- `db/checks/0285` proposed the `bess_snapshots` INSERT, comparing to the previous row per
-- `system_id`. That was right for SM.006 **v1**, which had to see a dwell and therefore needed a
-- clock. **v2 is a pure transition-matrix rule**, so the natural site is where the state changes —
-- and the deciding measurement is that `UPDATE ... ottoq_bess_units` appears in **TEN** functions:
--
--   ottoq_cert_arm · ottoq_cert_arm_start · ottoq_cert_arm_wave · ottoq_fr1_cert_arm
--   ottoq_safety_cert_arm · ottoq_sim_run_scenario · ottoq_tick_invariance_reset_fleet
--   ottoq_trigger_emergency_cascade · twin.ottoq_sim_bess_apply_degradation
--   twin.ottoq_sim_bess_step
--
-- A probe inside one writer covers one of ten and silently exempts nine, which is the
-- `resolved_action_context` mistake `0292` taught — an instrument pointed at one path and read as
-- though it covered all of them. A row trigger covers the table.
--
-- **THE TABLE IS HOT AND THE TRIGGER IS DECLARED SO THAT DOES NOT MATTER.** `ottoq_bess_units`
-- holds **3 live rows** and has taken **225,304 updates** over its life — the tick writes SoC,
-- power and heartbeat every beat. So the trigger is `AFTER UPDATE OF current_state` **with a WHEN
-- clause**: Postgres evaluates `NEW.current_state IS DISTINCT FROM OLD.current_state` itself and
-- never enters the function otherwise, so the ~197k updates that move only SoC cost nothing at all.
-- `UPDATE OF` alone would not do it — it fires when the column is MENTIONED, not when it moves —
-- and the WHEN clause alone would still be evaluated on every update. Both, together.
--
-- That also closes 0387's third trap by construction: the evaluator returns a **`'no-op
-- transition'` pass** when from = to, so an unguarded probe would log green tens of thousands of
-- times for a comparison it never made. This one cannot be reached with from = to.
-- And the second trap, the **vacuous pass** — with `from_state` or `to_state` absent the evaluator
-- returns TRUE with reason `'no transition context'` — is closed by passing both explicitly from
-- OLD and NEW.
--
-- ══ 3. MEASURE ONLY ════════════════════════════════════════════════════════
--
-- `ottoq_shield_probe` logs every evaluation and RETURNS `would_block`; it blocks nothing itself.
-- Nothing here reads the return. SM.006 is declared `critical`/`enforcement='block'` and promoting
-- it is a SEPARATE decision under 2.9a's blind-spot doctrine — MEASURED first, ENFORCED only after
-- a flagship round. §1 says the expected refusal rate is zero, and that is a prediction from
-- history, not a licence to skip the measurement that tests it.
--
-- Own exception handler, per `0387`: a probe must never abort a tick. A BESS probe that raised
-- would take down `twin.ottoq_sim_bess_step` and with it the energy path.
--
-- ══ 4. WHAT THIS MOVES, AND THE ONE THING IT DOES NOT ══════════════════════
--
-- G44 goes from **23 of 30 declared rules at eight probe points** (`0292` §3) to **24 of 30 at
-- nine** — `bess_state_change` joins `task_start`, `stall_assignment`, `charge_session_start`,
-- `redeployment`, `policy_write`, `bess_dispatch`, `vehicle_state_change` and `stall_state_change`.
-- `0273`'s caveat governs unchanged and must travel with the number: **evaluated is a WIRING count,
-- not a protection count.** Six remain unevaluated — HW.006, SM.004, SM.005, SLA.002, TW.002,
-- TW.004 — and three of those are `critical`.
--
-- **AND THE THING IT DOES NOT FIX.** `bess_snapshots` has no `sim_run_id`, so the BESS series is
-- not run-scoped, never purged, and mixes every run into one series — `0285` said so and it is
-- still true. §1's 28,735 transitions span the engine's life at this depot and CANNOT carry a run
-- id. The probe's own output CAN: `ottoq_rule_evaluations` is run-scoped (`class='engine'`), so
-- from today SM.006's evaluations are citable per run even though its history is not.
--
-- ══ 5. `→ fault` IS THE ONE TRANSITION THIS ATTRIBUTION WOULD REFUSE ═══════
--
-- Three bess transitions into `fault` admit `{bess_controller, external_sensor}` and NOT
-- `ottoq_engine`. **Zero have ever occurred** — §1's census shows six shapes and no fault among
-- them; `0285` found `fault`, `offline` and `online` declared and unobserved. So this cannot fire
-- today. It is recorded rather than defended: if `ottoq_trigger_emergency_cascade` ever drives a
-- unit to `fault` inside a sim run, this probe will log a role-gate failure, and the right answer
-- then is for that function to set `ottoq.actor_type` to `bess_controller` around its write — not
-- to widen the matrix. The probe would be telling the truth: the engine is not the actor that
-- faults a battery.

BEGIN;

-- ── the trigger function ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ottoq_bess_units_state_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, ottoq, pg_temp
AS $fn$
DECLARE
  v_actor_type TEXT := COALESCE(NULLIF(current_setting('ottoq.actor_type', TRUE), ''), 'unknown');
  v_run        UUID;
BEGIN
  v_run := ottoq.ottoq_active_sim_run_id();

  -- ATTRIBUTE THE ENGINE, exactly as 0387 does for vehicles and stalls and for the same
  -- measured reason: NOTHING in this database sets `ottoq.actor_type` on a write path, and not
  -- one of the 19 active bess rows in ottoq_state_transitions admits 'unknown'. Without this
  -- line the probe fails every transition on the ROLE GATE and reports a missing input as a
  -- state-machine violation. Inside a sim run the engine is the actor -- the twin simulates its
  -- own controller. Outside a run it stays 'unknown', because there it genuinely is
  -- unidentified and inventing an actor would be worse than admitting none.
  IF v_actor_type = 'unknown' AND v_run IS NOT NULL THEN
    v_actor_type := 'ottoq_engine';
  END IF;

  -- MEASURE ONLY. ottoq_shield_probe logs every evaluation and returns would_block; nothing
  -- here reads it. SM.006 is critical/block and promoting it is a separate decision under
  -- 2.9a's blind-spot doctrine. Both states are passed EXPLICITLY: with either absent the
  -- evaluator returns its 'no transition context' pass and this would log green forever.
  BEGIN
    PERFORM 1 FROM public.ottoq_shield_probe(
      p_action_context := 'bess_state_change',
      p_entity_type    := 'bess',
      p_entity_id      := NEW.bess_id,
      p_context        := jsonb_build_object(
                            'from_state', OLD.current_state,
                            'to_state',   NEW.current_state,
                            'actor_type', v_actor_type),
      p_depot_id       := NEW.depot_id);
  EXCEPTION WHEN OTHERS THEN
    -- A probe must never abort a tick. This one sits under twin.ottoq_sim_bess_step, so a
    -- raise here would take the energy path down with it.
    RAISE WARNING 'ottoq_bess_units_state_change: SM.006 probe FAILED SAFELY %: %',
      SQLSTATE, SQLERRM;
  END;

  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.ottoq_bess_units_state_change() IS
  '0399 (G96 step 2). The first trigger this table has ever had. Probes SM.006 '
  'bess_transition_validity at action_context bess_state_change on a real state change, MEASURE '
  'ONLY -- the return of ottoq_shield_probe is deliberately not read. Attributes ottoq_engine '
  'inside a sim run because no writer sets ottoq.actor_type and no bess transition admits '
  '''unknown''; see 0387 for the same fix on vehicles and stalls.';

-- ── the trigger ───────────────────────────────────────────────────────────
-- BOTH `UPDATE OF current_state` AND the WHEN clause, on purpose. 3 live rows, 225,304 lifetime
-- updates: `UPDATE OF` fires when the column is MENTIONED rather than when it MOVES, and the WHEN
-- clause is what keeps the function body out of the ~197k SoC-only writes. Together they also make
-- the evaluator's 'no-op transition' pass unreachable, which is the G28 defect class.
DROP TRIGGER IF EXISTS trg_ottoq_bess_units_state_change ON public.ottoq_bess_units;
CREATE TRIGGER trg_ottoq_bess_units_state_change
  AFTER UPDATE OF current_state ON public.ottoq_bess_units
  FOR EACH ROW
  WHEN (NEW.current_state IS DISTINCT FROM OLD.current_state)
  EXECUTE FUNCTION public.ottoq_bess_units_state_change();

-- ══ PREFLIGHT — assert the four things that must hold, rather than trust them ══
-- 0387's P1/P2 pattern. Each of these was false at some point in the last eighteen hours, so
-- none of them is assumed.
DO $preflight$
DECLARE
  v_rules   TEXT;
  v_missing TEXT;
  v_n       INT;
BEGIN
  -- (a) the probe context must actually resolve to SM.006, or the probe evaluates NOTHING and
  --     logs a coverage number for an empty set.
  SELECT string_agg(r.rule_code, ',') INTO v_rules
    FROM public.ottoq_rules r
   WHERE r.status IN ('active','shadow')
     AND 'bess_state_change' = ANY(r.applies_to_actions);
  IF v_rules IS NULL OR v_rules NOT LIKE '%SM.006%' THEN
    RAISE EXCEPTION '0399 P(a): probe context ''bess_state_change'' does not resolve to SM.006 (got %)', v_rules;
  END IF;

  -- (b) the two reversal rows 0397 inserted must be present and active, or this probe refuses
  --     14.0% of the battery's transitions on a dwell 0295 showed no source requires.
  SELECT count(*) INTO v_n
    FROM public.ottoq_state_transitions
   WHERE entity_kind = 'bess' AND status = 'active'
     AND (from_state, to_state) IN (('charging','discharging'), ('discharging','charging'));
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0399 P(b): expected both bess reversal transitions active, found % -- 0397 is not in place', v_n;
  END IF;

  -- (c) every transition the twin depot has ever made must admit ottoq_engine. If one does not,
  --     this probe would start logging role-gate failures the moment it is attached, and a
  --     critical rule reporting failures for a reason that is not about legality is exactly what
  --     0387 refused to ship.
  SELECT string_agg(DISTINCT s.from_state||'→'||s.to_state, ', ') INTO v_missing
    FROM (
      SELECT lag(status::text) OVER (PARTITION BY system_id ORDER BY "timestamp", id) AS from_state,
             status::text AS to_state
        FROM public.bess_snapshots
       WHERE depot_id = '11111111-1111-1111-1111-111111111111'
    ) s
    LEFT JOIN public.ottoq_state_transitions m
           ON m.entity_kind = 'bess' AND m.status = 'active'
          AND m.from_state = s.from_state AND m.to_state = s.to_state
   WHERE s.from_state IS NOT NULL AND s.from_state <> s.to_state
     AND (m.transition_id IS NULL OR NOT ('ottoq_engine' = ANY(m.allowed_actor_types)));
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION '0399 P(c): observed bess transitions that SM.006 would refuse under ottoq_engine: %', v_missing;
  END IF;

  -- (d) the vocabulary must still be reconciled. 0397 unified idle→standby across four sites;
  --     if anything has written 'idle' since, this probe refuses every transition through rest.
  SELECT verdict INTO v_missing FROM public.ottoq_assert_bess_state_vocabulary();
  IF v_missing NOT LIKE 'reconciled%' THEN
    RAISE EXCEPTION '0399 P(d): bess state vocabulary is not reconciled: %', v_missing;
  END IF;

  -- (e) and the trigger itself is attached and enabled.
  SELECT count(*) INTO v_n
    FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'ottoq_bess_units'
     AND t.tgname = 'trg_ottoq_bess_units_state_change'
     AND NOT t.tgisinternal AND t.tgenabled <> 'D';
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0399 P(e): trg_ottoq_bess_units_state_change is not attached and enabled (found %)', v_n;
  END IF;

  RAISE NOTICE '0399 preflight: SM.006 resolves at bess_state_change, both reversals active, all observed transitions admit ottoq_engine, vocabulary reconciled, trigger live.';
END;
$preflight$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0399_the_bess_state_machine_gets_its_caller_and_the_table_gets_its_first_trigger_g96',
        TRUE,
        'G96 step 2, the last of it. SM.006.bess_transition_validity (critical) has had a callable '
        'evaluator and NO CALLER since it was written; 0387 wired SM.001 and SM.003 and left this '
        'one for its own table and its own before/after measurement. This adds the first trigger '
        'ottoq_bess_units has ever had -- AFTER UPDATE OF current_state with a WHEN clause, so the '
        'function body is never entered for the ~197k of 225,304 lifetime updates that move only '
        'SoC on 3 live rows. MEASURE ONLY: ottoq_shield_probe''s would_block is deliberately not '
        'read; promotion stays a separate decision under 2.9a. BEFORE-MEASUREMENT: all 28,735 '
        'transitions the twin depot has ever made fall in six shapes and SM.006 v2 passes 6 of 6 '
        'under actor ottoq_engine, so this refuses nothing -- but it would have refused 4,032 '
        '(14.0%) before 0397 inserted the two reversal rows, and it would refuse ALL 28,735 on the '
        'role gate without the ottoq_engine attribution, since no bess transition admits '
        '''unknown''. forces_recert TRUE for a narrow reason: this is a NEW WRITER into the rules '
        'atom, one of the fourteen, and a new writer into an enforced atom must be proven to write '
        'identically in both arms before the canon rests on it -- 0137, 0139 and 0216 are what that '
        'costs when it is assumed. Nothing else moves: the table emitted no event before and emits '
        'none now, and ottoq_world_fingerprint hashes current_state VALUES which 0397 already '
        'settled. Cost stated plainly: all 9 canon columns are current and satisfy floor as of '
        '03:19-03:49 UTC today, so this is nine re-certifications, not a free window.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

COMMIT;
