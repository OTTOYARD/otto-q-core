-- 0186  The proposer was never heard, and 'pending' did not say so -- the first
--       live D3 cycles read from the ledger, then the same run with the hold on.
--
-- STATUS: READER. Every query is read-only. Run against run
-- af2def1b-8413-4eba-a434-637444b06bb9 (run_by proposer_demo, busy_day / 424242,
-- started 2026-09-13 00:26 UTC). §1 is the failure that 0262 and the L-58/L-59/L-60
-- proposer fixes came from; §2 is the cycle after them. Numbers in comments are
-- what the queries returned when the section was written; re-run, do not quote.
--
-- THE READING RULE. ottoq_external_proposals.status is the DOOR's view: 'pending'
-- means nobody has disposed of the row yet. It does not say whether anything ever
-- will. A row for a vehicle that already holds a booking stays 'pending' until its
-- TTL because the decide path re-decides a vehicle only while it holds none; a row
-- whose vehicle the local heuristic decided in the same tick is 'superseded'. Neither
-- is a refusal. A refusal is an ottoq_decisions row with proposed_action->>'source'
-- naming the proposer and outcome_status <> 'enacted' and enacted_action->'blocked_by'
-- carrying rule codes. Count THOSE, and count enactments the same way; the door's
-- status column cannot answer "was the proposer heard".

-- =========================================================================
-- 1. FIRES 3 AND 4 (hold OFF -- proposer_hold_enabled was refused by ottoq_policy_set,
--    see 0262). What the door recorded vs what the shield saw.
--    MEASURED 2026-09-13 01:00 UTC: fire 3 = 38 rows (4 stall rows + 34 abstains),
--    fire 4 = 16 rows (6 stall rows + 10 abstains); statuses 34 superseded / 20 pending /
--    0 enacted / 0 refused; ottoq_decisions rows with source forward_lex: 0.
-- =========================================================================
SELECT f.fire_id, f.tick_seq, f.status AS fire_status, f.n_submitted, f.n_planned, f.n_abstained,
       (SELECT jsonb_object_agg(s, n) FROM (
          SELECT e.status s, count(*) n FROM public.ottoq_external_proposals e
           WHERE e.proposal_id = ANY (f.proposal_ids) GROUP BY 1) x) AS door_statuses,
       (SELECT count(*) FROM public.ottoq_decisions d
         WHERE d.sim_run_id = f.sim_run_id AND d.proposed_action->>'source' = 'forward_lex'
           AND d.tick_seq > f.tick_seq AND d.tick_seq <= f.tick_seq + 2) AS shield_saw_within_2_ticks
  FROM public.ottoq_proposer_fire_log f
 WHERE f.sim_run_id = 'af2def1b-8413-4eba-a434-637444b06bb9'
 ORDER BY f.fire_id;

-- 1b. WHY. For every stall row fire 3 or 4 submitted: was the vehicle decided again at
--     all after the fire, and by whom. A vehicle with no later stall_assignment decision
--     already held a booking (the staged_awaiting_service case); one decided by
--     '<local>' in the same tick was superseded before the selector ran.
--     MEASURED: of the 10 stall rows, 6 vehicles were never decided again (booked), 4
--     were decided by the local heuristic at the fire's own tick + 2 (the world tick had
--     moved the free stalls first).
SELECT f.fire_id, left(e.entity_id::text, 8) AS veh, e.status AS door_status,
       left(e.proposal->>'stall_id', 8) AS proposed_stall,
       (SELECT jsonb_agg(jsonb_build_object('tick', d.tick_seq, 'src', COALESCE(d.proposed_action->>'source','<local>'),
                                            'out', d.outcome_status, 'stall', left(d.enacted_action->>'stall_id', 8)) ORDER BY d.tick_seq)
          FROM public.ottoq_decisions d
         WHERE d.sim_run_id = e.sim_run_id AND d.entity_id = e.entity_id
           AND d.action_context = 'stall_assignment' AND d.tick_seq >= f.tick_seq) AS later_stall_decisions
  FROM public.ottoq_proposer_fire_log f
  JOIN public.ottoq_external_proposals e ON e.proposal_id = ANY (f.proposal_ids)
 WHERE f.sim_run_id = 'af2def1b-8413-4eba-a434-637444b06bb9' AND f.fire_id IN (3, 4)
   AND NOT COALESCE((e.proposal->>'abstain')::boolean, false)
 ORDER BY f.fire_id, e.entity_id;

-- 1c. THE HOLD WAS OFF, AND WHY. Both keys must resolve >= 1 at run scope for an arrival
--     to be held: proposer_hold_enabled (the gate, 0259) and cuopt_first_refusal_max_defers
--     (the arm cap; 0152 set the global tier to 0). No deferral row was ever written for
--     this run before the keys were set.
--     MEASURED at 01:00 UTC: hold 0, max_defers 0, deferral rows 0.
SELECT public.ottoq_policy_get('af2def1b-8413-4eba-a434-637444b06bb9', 'proposer_hold_enabled', 0)          AS hold_gate,
       public.ottoq_policy_get('af2def1b-8413-4eba-a434-637444b06bb9', 'cuopt_first_refusal_max_defers', 1) AS arm_cap,
       (SELECT count(*) FROM public.ottoq_cuopt_deferrals WHERE sim_run_id = 'af2def1b-8413-4eba-a434-637444b06bb9') AS deferral_rows,
       (SELECT jsonb_object_agg(param_key, param_value) FROM public.ottoq_policy_params
         WHERE scope_type = 'run' AND scope_id = 'af2def1b-8413-4eba-a434-637444b06bb9') AS run_params;
