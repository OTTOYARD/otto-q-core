-- 0286  KPI 4 — `touch_events_per_turn`, "human interventions per asset-turn" — COUNTS THE
--       DETERMINISTIC SHIELD'S OWN SAFE-DEFAULT FALLBACKS AS HUMAN LABOUR. IT PUBLISHED
--       **1.459** ON A RUN WHOSE HUMAN-ATTRIBUTABLE FIGURE IS **0.171**. 8.5x, AND IN THE
--       DIRECTION THAT MAKES THE PRODUCT LOOK WORSE THAN IT IS.
--
-- Read-only. MEASURED, NOT FIXED — the remedy is one line and it still rests on a judgement
-- named in §4. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), completed
-- demo run `1efeb1cd-f9b6-4515-8e61-2e5a04121112` (busy_day, seed 101959, 1,059 ticks, ended
-- by `run_governor: reached the 540 sim-minute ceiling`). `ottoq_decisions` is
-- `class='engine'` and purges with its run, so the 12,082-row figures below are the table's
-- CURRENT contents, not all history.
--
-- ══ 1. THE NUMBER, AND ITS DECOMPOSITION ═══════════════════════════════════
--
--   touch_events_per_turn (published)              **1.459**
--     turns                                            392
--     touch_events                                     572
--       touch_events_operator                         **67**
--       touch_events_override                        **505**
--   human-attributable only:  67 / 392            =  **0.171**
--   overstatement                                   **8.5x**
--
-- **All 505 are the engine.** Every one carries `l2_engine='deterministic_v1'` and
-- `outcome_status='overridden_to_default'` — the L1 shield declining a proposed action and
-- taking its safe default. 272 at `task_start`, 231 at `redeployment`, 2 at
-- `stall_assignment`; 4.2% of the run's 11,943 decisions. **That is automation refusing to
-- act. It is the exact opposite of a human touching a vehicle**, and KPI 4 exists to count
-- the latter.
--
-- ══ 2. THE DEFECT IS AN ASYMMETRY INSIDE ONE VIEW ══════════════════════════
--
-- `public.ottoq_kpi_touch_events_per_turn` computes its two halves to different standards.
-- The operator half is scrupulous:
--
--     SELECT count(*) FROM ottoq_events e
--      WHERE e.sim_run_id = t.sim_run_id
--        AND e.actor_type IN (SELECT actor_type FROM ottoq_kpi_touch_actor_types
--                              WHERE human_actor)
--
-- `ottoq_kpi_touch_actor_types` is a careful table — it classifies `ottoq_engine`, `system`,
-- `system_scheduler`, `solar_controller` and `unknown` as `human_actor=false`, and `unknown`
-- carries its own note: *"deliberately NOT a touch: counting unknown as human would inflate
-- KPI-4 with every unattributed row."* Someone thought hard about exactly this failure.
--
-- **The override half applies no actor filter at all:**
--
--     SELECT count(*) FROM ottoq_decisions d
--      WHERE d.sim_run_id = t.sim_run_id AND (d.overridden OR d.override_id IS NOT NULL)
--
-- So the principle the view spends a whole lookup table enforcing on one side is simply
-- absent on the other, and the side without it contributes 88% of the number.
--
-- ══ 3. AND THE COLUMNS THAT WOULD EVIDENCE A HUMAN HAVE NEVER BEEN WRITTEN ══
--
-- Measured over every decision the table currently holds:
--
--   decisions                                     **12,082**
--   `override_id IS NOT NULL`                          **0**
--   `override_reason IS NOT NULL`                      **0**
--   `override_rule_code IS NOT NULL`                   **0**
--   `overridden` true with `override_id IS NULL`      **522**  (all of them)
--   rows in `public.ottoq_rule_overrides`               **0**
--
-- **No human override has ever been recorded anywhere in this engine** — not on the decision,
-- not in the overrides table. So the override half of KPI 4 has never once counted a human
-- intervention. It has only ever counted the shield, and the `OR override_id IS NOT NULL`
-- clause — the part that would catch a real one — has never matched a row.
--
-- **This is also the population SM.005 exists to police, and a measurement of it.** SM.005
-- (`critical`, "audit note on override") is one of the seven rules with an evaluator and no
-- caller (`0280` §5). Its subject is 522 overrides carrying no rule code, no reason and no
-- override record. If it were wired against this data it would fail all 522 — and unlike
-- SM.006 in `0285`, the input it needs does exist; it is simply, uniformly, absent.

SELECT touch_events_per_turn AS published,
       touch_events, turns, touch_events_operator, touch_events_override,
       round(touch_events_operator::numeric / NULLIF(turns,0), 3) AS human_only,
       round(touch_events_per_turn
             / NULLIF(round(touch_events_operator::numeric / NULLIF(turns,0), 3), 0), 1)
         AS overstatement_factor
  FROM public.ottoq_kpi_touch_events_per_turn
 WHERE sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112';

SELECT COALESCE(l2_engine,'(null)')          AS l2_engine,
       COALESCE(outcome_status,'(null)')     AS outcome_status,
       action_context,
       count(*)                              AS n,
       count(*) FILTER (WHERE override_id      IS NOT NULL) AS with_override_id,
       count(*) FILTER (WHERE override_reason  IS NOT NULL) AS with_reason,
       count(*) FILTER (WHERE override_rule_code IS NOT NULL) AS with_rule_code
  FROM public.ottoq_decisions
 WHERE sim_run_id = '1efeb1cd-f9b6-4515-8e61-2e5a04121112' AND overridden
 GROUP BY 1,2,3 ORDER BY n DESC;

SELECT count(*) AS decisions_currently_held,
       count(*) FILTER (WHERE override_id IS NOT NULL)            AS with_override_id,
       count(*) FILTER (WHERE overridden)                          AS overridden_flag,
       count(*) FILTER (WHERE overridden AND override_id IS NULL)  AS flag_but_no_record,
       count(*) FILTER (WHERE override_reason IS NOT NULL)         AS with_reason,
       (SELECT count(*) FROM public.ottoq_rule_overrides)          AS rule_override_rows
  FROM public.ottoq_decisions;

-- ══ 4. THE FIX IS ONE LINE, AND THE JUDGEMENT UNDER IT IS NOT MINE ═════════
--
-- The narrow change: give the override half the filter the operator half already has. The
-- clean form is to count only overrides that EVIDENCE a human, which the schema already
-- provides a pointer for — `override_id IS NOT NULL` — and drop the bare `overridden` flag:
--
--     WHERE d.sim_run_id = t.sim_run_id AND d.override_id IS NOT NULL
--
-- On today's data that makes KPI 4 read **0.171** instead of 1.459.
--
-- **Why I have not applied it.** Two reasons, and the first is the real one.
--
--   (a) **It changes a published headline KPI, and the direction is favourable to us.** KPI 4
--       is one of the canonical five and it is the automation claim; this edit improves it by
--       8.5x. A change that flatters the product is exactly the change that must not be made
--       by the person who found it, on their own reading of what `overridden` means. Rule 6's
--       discipline — unquantified claims forbidden in BOTH directions — applies to fixes as
--       much as to sentences.
--   (b) **`overridden` may carry a meaning I have not found.** Every instance today is
--       `deterministic_v1` / `overridden_to_default`, but the column is old, the table is
--       purged, and "all 12,082" is the current contents rather than the engine's life. If
--       some caller sets `overridden` for a genuine human action without writing
--       `override_id`, the proposed predicate would then UNDER-count. The check that settles
--       it is one query against a fresh run after any human path is exercised — and no human
--       path exists in the twin today, which is itself the answer to a different question.
--
-- **Recommended, for Chase:** apply the predicate change together with wiring SM.005, because
-- they are the same finding seen twice. SM.005 says an override must carry an audit note; 522
-- overrides carry none; and KPI 4 counts those same 522 as human labour. Fixing the KPI
-- without wiring the rule leaves the engine free to keep producing unaudited overrides that
-- no longer show up anywhere. **Tracked as G97, open.**
--
-- ══ 5. WHAT IS NOT CLAIMED ═════════════════════════════════════════════════
--
-- * **Not that KPI 4 has always been wrong by 8.5x.** The factor is a property of this run's
--   mix — 505 shield fallbacks against 67 operator events. A run with more operator events
--   and fewer fallbacks would show a smaller factor. What is run-independent is the missing
--   filter and the never-populated columns.
-- * **Not that the other four KPIs are affected.** They are not: `touch_events_per_turn` is
--   the only one of the five that reads `ottoq_decisions.overridden`. All eight published
--   fields still report `not_reproducible: []` on this run.
-- * **Not that 0.171 is the true figure.** It is the figure under the recommended predicate.
--   Whether 67 `ottoq_events` rows with human actor types are themselves all genuine touches
--   is a separate question this file does not open.
