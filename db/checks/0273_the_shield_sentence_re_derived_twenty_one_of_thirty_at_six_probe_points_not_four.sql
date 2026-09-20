-- 0273  THE L1 SHIELD SENTENCE, RE-DERIVED AS CLAUDE.md ASKS: TWENTY-ONE OF THIRTY
--       AT **SIX** PROBE POINTS, NOT TWENTY OF TWENTY-NINE AT FOUR.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8).
--
-- CLAUDE.md Part 3's 2026-09-20 refresh carries a standing instruction against its own
-- 2.5: *"The 'twenty of twenty-nine at four probe points' sentence in 2.5 needs
-- re-deriving before it is spoken again."* This is that derivation. The sentence is
-- quoted outward, so it is worth getting exactly right, and **it moves in the direction
-- that flatters us, which is the direction to be most careful about.**
--
-- ══ 1. THE DENOMINATOR IS CONFIRMED: 53 ROWS, 30 CODES ══════════════════════
--
--   rule rows                                       **53**
--   distinct rule codes                             **30**
--   status='active'                        30 rows / 30 codes
--   status='archived'                      23 rows / 23 codes
--   **archived codes with no active sibling**          **0**
--
-- That last figure is the one that makes the clarification safe to repeat: every
-- archived row is a superseded version of a code that is still active, so "53 rules" and
-- "30 rules" are the same shield counted two ways, and there is no retired rule hiding
-- in the archive. CLAUDE.md's "53 rows / 30 codes" is correct as written.

SELECT count(*) AS rule_rows,
       count(DISTINCT rule_code) AS distinct_codes,
       count(*) FILTER (WHERE status = 'active') AS active_rows,
       count(DISTINCT rule_code) FILTER (WHERE status = 'active') AS active_codes,
       count(*) FILTER (WHERE status = 'archived') AS archived_rows,
       (SELECT count(DISTINCT a.rule_code) FROM public.ottoq_rules a
         WHERE a.status = 'archived'
           AND NOT EXISTS (SELECT 1 FROM public.ottoq_rules b
                            WHERE b.rule_code = a.rule_code AND b.status = 'active'))
                                              AS archived_only_codes
  FROM public.ottoq_rules;

-- ══ 2. THE NUMERATOR AND THE PROBE COUNT BOTH MOVE ══════════════════════════
--
-- Measured over every surviving run on the twin depot:
--
--   probe point              codes   evaluations
--   task_start                  13       137,787
--   stall_assignment             5         6,565
--   charge_session_start         5         4,475
--   redeployment                 6         1,596
--   policy_write                 1           345
--   bess_dispatch                1           282
--   ------------------------------------------------
--   **distinct probe points      6**
--   **distinct codes evaluated  21**  of 30 active
--
-- **`db/checks/0192` named FOUR probe points** -- task_start, stall_assignment,
-- redeployment, bess_dispatch. **`charge_session_start` and `policy_write` were
-- missed**, and the first of them is not marginal: 5 codes and 4,475 evaluations, more
-- traffic than redeployment and bess_dispatch combined.
--
-- **AND THE OMISSION WAS ALREADY CONTRADICTED INSIDE THIS REPO.** `FINDINGS.md` G89
-- states that *"EN.001.grid_capacity_ceiling caps aggregate charging at
-- `stall_assignment` and `charge_session_start`"*. So the fifth probe point was
-- documented in one file while another counted four, and neither noticed. That is a
-- cross-file consistency failure rather than a measurement error, and it is the reason
-- CLAUDE.md's instruction to re-derive before speaking exists.
--
-- **THE HONEST SENTENCE, AND IT IS THE ONE TO QUOTE:**
--
--   *"Twenty-one of thirty declared rules, at six decision points, every evaluation
--    logged."*

SELECT e.action_context,
       count(DISTINCT e.rule_code) AS codes_evaluated,
       count(*)                    AS evaluations
  FROM public.ottoq_rule_evaluations e
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY 1 ORDER BY 3 DESC;

SELECT count(DISTINCT e.action_context) AS probe_points,
       count(DISTINCT e.rule_code)      AS codes_evaluated,
       (SELECT count(DISTINCT rule_code) FROM public.ottoq_rules WHERE status = 'active')
                                        AS active_codes
  FROM public.ottoq_rule_evaluations e
  JOIN public.ottoq_sim_runs r ON r.sim_run_id = e.sim_run_id
 WHERE r.depot_id = '11111111-1111-1111-1111-111111111111';

-- ══ 3. QUOTE THE CODES AND THE PROBES, NEVER THESE EVALUATION COUNTS ════════
--
-- `ottoq_rule_evaluations` is registered `class='engine'`. The 137,787 above is not
-- comparable to 2.5's 2,701,143 for the same probe -- **not because coverage fell, but
-- because the demo purge took the prior runs**, exactly as CLAUDE.md's 2026-09-20
-- refresh records for every engine table (rule evaluations 5,464,682 -> 74,719 in one
-- run). So:
--
--   * **"21 of 30 codes at 6 probe points" is STRUCTURAL** -- it is a property of where
--     the shield is wired, and it survives a purge because it is re-derivable from any
--     run.
--   * **The per-probe evaluation counts are per-surviving-run working data** and must
--     carry their measurement moment or not be quoted at all. Cite the run, never the
--     table.
--
-- ══ 4. THE NINE UNEVALUATED RULES ARE THE SAME NINE, AND SIX ARE STILL CRITICAL ═
--
-- This half of `0192` holds exactly, which is worth stating because the rest of the
-- sentence moved:
--
--   HW.006.physical_presence_verification      critical   hardware_safety
--   SM.001.vehicle_transition_validity         critical   state_machine
--   SM.003.stall_transition_validity           critical   state_machine
--   SM.004.role_gated_actions                  critical   role_authorization
--   SM.005.audit_note_required_on_overrides    critical   audit_integrity
--   SM.006.bess_transition_validity            critical   state_machine
--   SLA.002.max_queue_depth                    warning    sla_contract
--   TW.002.overnight_staging                   info       time_window
--   TW.004.tariff_window                       info       time_window
--
-- **Nine codes, six of them `critical`**, matching `0192`'s count and its diagnosis:
-- these are invariants over *transitions and outcomes* -- state-machine legality for
-- vehicle, stall and BESS, role gating, the audit note on an override, physical presence
-- at completion, queue depth at arrival -- and **a gate placed where something STARTS
-- cannot check one.** Their evaluator functions exist and are callable; nothing calls
-- them.
--
-- So G44 is unchanged and still open, and the coverage arithmetic around it is what
-- moved: **21 of 30 rather than 20 of 29, because the one code added since 09-08 IS
-- evaluated**, and the nine gaps did not grow.

SELECT r.rule_code, r.severity, r.category, r.enforcement
  FROM public.ottoq_rules r
 WHERE r.status = 'active'
   AND NOT EXISTS (SELECT 1 FROM public.ottoq_rule_evaluations e
                    JOIN public.ottoq_sim_runs s ON s.sim_run_id = e.sim_run_id
                   WHERE e.rule_code = r.rule_code
                     AND s.depot_id = '11111111-1111-1111-1111-111111111111')
 ORDER BY CASE r.severity WHEN 'safety_critical' THEN 0 WHEN 'critical' THEN 1
                          WHEN 'warning' THEN 2 ELSE 3 END, r.rule_code;

-- ══ 5. WHAT THIS DOES NOT SHOW ══════════════════════════════════════════════
--
-- **"Evaluated" here means "has at least one logged evaluation on this depot", which is
-- weaker than "is gated by".** A code can be evaluated at a probe and still not bind --
-- `db/checks/0263` §1 is the precedent: four of the five codes at `stall_assignment` are
-- charge-specific and cannot meaningfully judge a parking hold, and the one that applies
-- to any booking, `HW.004.stall_single_vehicle`, states in its own description that it
-- is enforced by a partial unique index rather than by the probe. So **21 of 30 is a
-- wiring count, not a protection count**, and the stronger claim -- how many rules
-- actually refuse something -- would need the pass/fail distribution per probe and is
-- not derived here.
--
-- Which direction that cuts: it means **21 of 30 is the optimistic bound**, and any
-- version of this sentence that implies 21 rules are actively preventing anything is
-- overstating. The safe form stays *"twenty-one of thirty declared rules are evaluated,
-- at six decision points, every evaluation logged."*
