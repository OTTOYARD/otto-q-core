-- migration-version: 20260921004457
-- migration-name:    the_branch_i_led_0392_with_is_gated_at_a_probe_point_i_did_not_look_for
--
-- 0393  `0392` SEEDED `orchestrator_agent` AS `shield_expected = true` AND CALLED IT "THE ONE PATH
--       THE L1 SHIELD DOES NOT GATE". IT IS GATED — `AI.001.agent_dial_within_envelope` AT
--       `policy_write`, **254 EVALUATIONS ON THE RUN `0392` ITSELF MEASURED**. THIS CORRECTS THE
--       DECLARATION ROW AND NOTHING ELSE.
--
-- `forces_recert` **FALSE**. One `UPDATE` to a declaration table that nothing on the tick path
-- reads, plus a comment. No function body, no frame, no enacting path. Safe while a run is live,
-- and one is (`e8b8eb3e`).
--
-- Full derivation in `db/checks/0292`. The chain, in four hops, each verifiable by one query:
--
--   (1) `ottoq-orchestrator-agent/index.ts` writes one depot-scoped `ottoq_decisions` row per
--       tick with no `rule_results`; its whole effect set is dial writes and ops actions.
--   (2) `public.ottoq_apply_ops_action` — **every whitelisted branch is a `ottoq_policy_set` call
--       and nothing else**, each clamped in its own branch; anything off-whitelist INSERTs into
--       `ottoq_ops_approvals` as `pending`, the human queue. The agent's entire physical reach is
--       policy dials: no stall, no vehicle, no booking.
--   (3) `public.ottoq_policy_set` calls `ottoq_shield_probe` with `policy_write`.
--   (4) 254 `ottoq_rule_evaluations` rows on run `e8b8eb3e`, `action_context='policy_write'`,
--       `entity_type='policy_param'`, code `AI.001.agent_dial_within_envelope`.
--
-- **So the edge function's own header — *"L1 shield still gates every physical effect; vehicle-first
-- inviolable"* — is accurate, and `0392` contradicted it from the data without reading the path it
-- describes.** The error direction is the one rule 6 calls the more dangerous: it made the product
-- look worse than it is, in a safety claim.
--
-- **WHY `shield_expected` BECOMES FALSE RATHER THAN THE ROW BEING DELETED.** The column means "this
-- branch chooses an action and should therefore pass `ottoq_shield_probe` *on this row*". For a
-- depot-scoped advisory record the answer is no, and saying so explicitly — with the reason and the
-- probe point that does the gating — is worth more than an absent row, which would read as
-- "undeclared" and be reported as a gap by `ottoq_shield_coverage`'s own verdict logic.
--
-- **AND THE REMEDY CHANGES SHAPE, WHICH IS THE POINT OF WRITING IT DOWN.** `0392` proposed routing
-- the agent through `ottoq_shield_and_log`. That function hardcodes `entity_type='vehicle'` and
-- `CONTINUE`s on any action with no `vehicle_id`, so it would **skip every agent row it was given**
-- — a remedy that compiles, runs, changes nothing, and closes the finding on paper. What is
-- actually needed is a **correlation id**: `ottoq_rule_evaluations.correlation_id` already exists,
-- so stamping one on the agent's decision and threading it into `ottoq_policy_set`'s probe call
-- joins the 254 evaluations back to the decision that caused them. Attribution, additive, and it
-- changes nothing about what the shield decides. Not built here — it touches the edge function and
-- a tick-path routine, so it waits with the other two deferred remedies.
--
-- `gate_intake_no_charge` is untouched and is now the only `shield_expected` gap: it books a
-- staging stall and emits `proceed_to_stall`, it is vehicle-scoped so `ottoq_shield_and_log` fits
-- it exactly, and unlike the agent there is no second probe point downstream because a staging
-- booking is not a policy write.

BEGIN;

-- ══ P0. PREFLIGHT — assert the four hops rather than restate them ══════════
DO $p0$
DECLARE v_evals bigint; v_probe boolean; v_ops_writes_policy boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_enactment_branches
                  WHERE resolved_action_context = 'orchestrator_agent') THEN
    RAISE EXCEPTION '0393 P0: 0392''s declaration row for orchestrator_agent is absent'
      USING ERRCODE='22023';
  END IF;

  --: hop (3): the dial writer must call the probe, or the premise of this correction fails.
  SELECT prosrc LIKE '%ottoq_shield_probe%' INTO v_probe
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_set';
  IF NOT COALESCE(v_probe, false) THEN
    RAISE EXCEPTION '0393 P0: ottoq_policy_set does not call ottoq_shield_probe; the agent''s '
                    'dial path is NOT gated and 0392''s original note was right after all'
      USING ERRCODE='22023';
  END IF;

  --: hop (2): the agent's action applier must reach engine state only through policy writes.
  SELECT prosrc LIKE '%ottoq_policy_set%' AND prosrc LIKE '%ottoq_ops_approvals%'
    INTO v_ops_writes_policy
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_apply_ops_action';
  IF NOT COALESCE(v_ops_writes_policy, false) THEN
    RAISE EXCEPTION '0393 P0: ottoq_apply_ops_action no longer routes through ottoq_policy_set '
                    'and ottoq_ops_approvals; re-trace the agent''s effect set before applying'
      USING ERRCODE='22023';
  END IF;

  --: hop (4): and the gate must have actually fired, not merely be wired.
  SELECT count(*) INTO v_evals FROM public.ottoq_rule_evaluations
   WHERE action_context = 'policy_write' AND rule_code = 'AI.001.agent_dial_within_envelope';
  RAISE NOTICE '0393 P0: AI.001 at policy_write has % logged evaluation(s) currently held', v_evals;
  IF v_evals = 0 THEN
    RAISE EXCEPTION '0393 P0: no AI.001 evaluation survives. ottoq_rule_evaluations is '
                    'class=engine and purges, so 0 may mean a fresh run rather than an ungated '
                    'agent -- re-derive on a run that has ticked before applying'
      USING ERRCODE='22023';
  END IF;
END $p0$;

-- ══ P1. THE CORRECTION ═════════════════════════════════════════════════════
UPDATE public.ottoq_enactment_branches
   SET shield_expected = false,
       writer = '(edge function ottoq-orchestrator-agent, no database writer)',
       note =
         'CORRECTED BY 0393 -- 0392 declared this shield_expected=true and called it "the one '
         'path on which an AI changes engine state and the one path the L1 shield does not gate". '
         'That was wrong. The agent writes ONE depot-scoped decision row per tick whose whole '
         'effect set is dial writes and ops actions; ottoq_apply_ops_action reaches engine state '
         'only through ottoq_policy_set (anything off-whitelist goes to ottoq_ops_approvals, the '
         'human queue); and ottoq_policy_set calls ottoq_shield_probe with policy_write, where '
         'AI.001.agent_dial_within_envelope logged 254 evaluations on the very run 0392 measured. '
         'FALSE because this row is a depot-scoped advisory record: there is no vehicle for the '
         'vehicle-scoped shield to judge, and the gating that matters already happens one hop '
         'down. What IS missing is ATTRIBUTION -- nothing joins those 254 evaluations to the '
         'decision that caused them -- so agent_calls_with_no_l1_rules=1,120 of 1,120 is a '
         'correctly computed metric with a misleading name (the 0289 defect shape). The remedy is '
         'a correlation_id, NOT ottoq_shield_and_log, which hardcodes entity_type=vehicle and '
         'would skip every agent row it was given. See db/checks/0292.'
 WHERE resolved_action_context = 'orchestrator_agent';

COMMENT ON COLUMN public.ottoq_enactment_branches.shield_expected IS
  'TRUE when this branch chooses an action and should therefore pass ottoq_shield_probe ON THIS '
  'ROW. FALSE when it RECORDS something that already happened -- the twin advancing its own '
  'world, or a reconciliation binding a vehicle already physically present -- OR when the action '
  'it describes is gated at a DIFFERENT probe point one hop down, which is the orchestrator_agent '
  'case (0393): its dials pass AI.001 at policy_write. FALSE therefore means "no shield is '
  'expected on this row", never "no shield applies to this action", and the note column must say '
  'which of those two it is. Getting that wrong in either direction is a safety claim, so 0393''s '
  'preflight asserts the effect path rather than trusting the note.';

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0393_the_branch_i_led_0392_with_is_gated_at_a_probe_point_i_did_not_look_for', false,
  'Corrects the ottoq_enactment_branches row 0392 seeded for orchestrator_agent: '
  'shield_expected true -> false, with the reason and the probe point that actually gates it. '
  'FALSE: one UPDATE to a declaration table nothing on the tick path reads, plus two comments. '
  'The correction itself: 0392 called the agent the one ungated path; measured, its entire '
  'physical reach is policy dials, ottoq_apply_ops_action routes them through ottoq_policy_set '
  '(off-whitelist actions go to the ottoq_ops_approvals human queue), ottoq_policy_set calls '
  'ottoq_shield_probe with policy_write, and AI.001.agent_dial_within_envelope logged 254 '
  'evaluations on run e8b8eb3e -- the same run 0392 measured. The error direction is the one '
  'rule 6 calls more dangerous: it made the product look worse than it is, in a safety claim. '
  'What survives is an attribution gap (nothing joins those evaluations to the agent decision) '
  'whose remedy is a correlation_id, not ottoq_shield_and_log -- that function hardcodes '
  'entity_type=vehicle and would skip every agent row. gate_intake_no_charge is untouched and is '
  'now the only shield_expected gap. db/checks/0292 also retires CLAUDE.md 2.5''s "twenty-one of '
  'thirty at six decision points": measured 23 of 30 at EIGHT, because 0387 wired SM.001 and '
  'SM.003, two of the nine codes 0273 listed as unevaluated, hours after 0273 was written.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ══ P2. POSTFLIGHT — the gap set must shrink to exactly one branch ══════════
DO $p2$
DECLARE v_run uuid; v_roll jsonb; v_gaps jsonb; v_names text;
BEGIN
  SELECT sr.sim_run_id INTO v_run FROM public.ottoq_sim_runs sr
   WHERE sr.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY sr.started_at DESC LIMIT 1;

  v_roll := public.ottoq_assert_shield_coverage(v_run);
  v_gaps := v_roll->'gap_branches';

  SELECT string_agg(g->>'branch', ', ' ORDER BY g->>'branch') INTO v_names
    FROM jsonb_array_elements(v_gaps) g;

  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_gaps) g
              WHERE g->>'branch' = 'orchestrator_agent') THEN
    RAISE EXCEPTION '0393 P2: orchestrator_agent is still reported as a gap after the UPDATE'
      USING ERRCODE='23514';
  END IF;

  --: and the identities 0392 P4 asserts must still hold after reclassification, or the two
  --: FILTERed sums have started double-counting.
  IF (v_roll->>'unshielded_gap')::bigint + (v_roll->>'unshielded_by_design')::bigint
     <> (v_roll->>'unshielded')::bigint THEN
    RAISE EXCEPTION '0393 P2: gap (%) + by_design (%) <> unshielded (%)',
      v_roll->>'unshielded_gap', v_roll->>'unshielded_by_design', v_roll->>'unshielded'
      USING ERRCODE='23514';
  END IF;

  RAISE NOTICE '0393 P2: run % — gap now % on branch(es) [%], by design %',
    v_run, v_roll->>'unshielded_gap', COALESCE(v_names, '(none)'),
    v_roll->>'unshielded_by_design';
END $p2$;

COMMIT;
