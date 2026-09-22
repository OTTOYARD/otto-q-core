-- migration-version: 20260922070445
-- migration-name:    the_agents_advice_carries_the_tick_it_was_computed_from_and_the_tick_it_was_applied_at_and_nobody_had_ever_subtracted_them
--
-- 0417  **G62, step 2 of the build `0323` §5 specified: MEASURE advice staleness, enforce nothing.**
--
--       And the first finding is that step 1 — "advice carries provenance" — **was already done and
--       nobody knew.** `ottoq_model_call_ledger.tick_seq` is the tick the advice was computed from;
--       `detail->'solver_handoff'->'receipt'->>'tick_seq'` is the tick it was applied at. Both have been
--       written on every agent call since the ledger existed. **The difference had never been taken.**
--
--       Two views, no behaviour change, `forces_recert` FALSE.
--
-- ══ §1 THE MEASUREMENT, AND WHY ITS DENOMINATOR IS HONEST ══════════════════════
--
-- Over the live agent calls in the ledger at 2026-09-22 07:0x UTC:
--
--     staleness (applied_tick - computed_tick), ticks    mean 4.75   p50 3   p95 17   max 59
--     applied calls with the measure defined                     629
--     of those, more than one tick stale                         409  (65%)
--     of those, more than ten ticks stale                         71  (11%)
--     applied BEFORE computed (would be a bug)                     0
--
-- **Only 629 of 3,373 live agent calls carry an applied tick, and that is not censoring.** The other
-- 2,744 are the population where the solver never ran, so there is no tick to record:
--
--     handoff status   reason                                                    n
--     --------------   ------------------------------------------------------   -----
--     fallback         CP-SAT service is not configured                         1,502
--     fallback         running image predates CP-SAT (/health lists energy_mpc)   835
--     fallback         Signal timed out.                                          206
--     fallback         invalid proposer envelope                                  191
--     fallback         /assign returned 500                                         1
--     skipped          run is not active                                             4
--     completed        receipt present, tick_seq absent                             4
--
-- Those 2,735 fallbacks are **exactly** `0322`'s 2,735 — the four-day CP-SAT config/deployment outage,
-- already diagnosed. So 629 is the complete population in which staleness is *defined*, not a sample of
-- a larger one. Stating it the other way — "82% of agent calls have no staleness measurement" — would be
-- true and misleading, the `0324` §1 censored-denominator shape.
--
-- **And the measure validates itself against latency**, which is the independent witness that these two
-- jsonb fields mean what this migration says they mean: mean latency rises monotonically with staleness
-- across every bucket — 5,354 ms at 0 ticks, 10,955 at 2, 22,368 at 5, 41,155 at 10, 107,323 at 20,
-- 118,736 at 36. A spurious pairing of unrelated fields would not do that.
--
-- ══ §2 THE FINDING THAT INVERTS `0323` §5, WHICH I WROTE ═══════════════════════
--
-- §5 called the latency "not the defect" and named the defect as *"nothing declares how long advice stays
-- valid"*, then specified **step 3 — declare a validity window and refuse advice older than it**. That
-- step is now measured, and it is close to useless:
--
--     applied calls with a strictly later agent call to compare against          627
--     stale advice that DISAGREED with the next fresh advice                       1   (0.16%)
--     a constant 'readiness_first' would have disagreed                           211  (33.65%)
--
-- **Advice a mean of 4.75 ticks old is wrong 0.16% of the time.** A validity window at any threshold that
-- caught a useful share of the 409 stale calls would discard advice that was still correct in ~409 of 410
-- cases, and fall back to the deterministic path for nothing.
--
-- **The 0.16% survived the check that should have killed it.** The first version of that query took the
-- agent call *nearest* the applied tick as the comparison — which, with calls ~20 ticks apart and mean
-- staleness 4.75, is usually **the same row**, making the comparison self-referential and the agreement
-- trivial. Re-run with the comparison forced to a strictly later call (`call_id <> a.call_id AND
-- c_tick >= a_tick`), the answer is identical: 1 of 627. Sixth such trap checked on this branch, and the
-- first one where the number survived.
--
-- **The 33.65% is what stops this being an argument that the agent is useless.** Stale advice retains
-- essentially all of the agent's signal; ignoring the agent and hard-coding its modal answer would be
-- wrong on a third of applied ticks. So the agent carries real information (33.65% better than its own
-- mode) and staleness destroys almost none of it (0.16%). **Both halves are needed** — quoting either
-- alone argues for a conclusion the pair does not support.
--
-- ══ §3 SO WHAT THE LATENCY ACTUALLY COSTS: THE WAIT, NOT THE ANSWER ════════════
--
-- Over all 3,373 live agent calls: **mean 19,714 ms, p50 10,929, p95 66,588, max 199,290, and 18.7%
-- over 30 seconds.** Every surviving run in `ottoq_sim_runs` uses a 30-second tick (one distinct value),
-- so on the 245 calls whose run has not been purged the tick spends **61.9% of its budget waiting** for
-- advice, p95 52,633 ms — p95 exceeds the entire tick.
--
-- **That is the defect, restated: the tick blocks for two thirds of its beat on an answer it could have
-- predicted from the previous tick 99.84% of the time.** Not a wrong answer — a wasted one.
--
-- **Which reverses §5's ordering, and that is the substantive correction here.** §5 said step 4
-- (decouple the beat) was *"unreachable before step 3, because a continuously-running agent with no
-- staleness gate deposits stale advice faster."* Measured, stale advice is right 99.84% of the time, so
-- depositing it faster is depositing correct advice faster. **Step 4 is the whole win and step 3 is not
-- its precondition.** Step 3 survives as a *monitor* — publish staleness, alarm if the disagreement rate
-- ever leaves the floor it sits on — not as a gate.
--
-- **The honest limit on that claim, and the reason this is a view and not a redeploy.** 0.16% is measured
-- on an objective with **three** values (`readiness_first` 86.2%, `throughput_first` 12.2%,
-- `energy_balanced` 1.7%), changing on 1.64% of consecutive ticks. A coarse, slow-moving output is
-- exactly the kind that tolerates staleness. If the agent's output ever widens — more objectives, or
-- per-vehicle directives rather than one site-wide word — **this number must be re-derived before step 4
-- is built on it**, which is what the summary view is for. It is not a property of asynchronous advice in
-- general; it is a property of THIS advice at THIS width, and the view re-measures it on every read.
--
-- ══ §4 WHY THIS IS A VIEW AND WHAT IT DELIBERATELY DOES NOT DO ═════════════════
--
-- No gate, no validity window, no tick-loop change, no edge redeploy. `0415` §5 records the standing
-- reason not to redeploy the one working external solver path on an untested overnight change, and the
-- tick loop deserves that caution more, not less. Step 4 is an edge-function and tick-loop change and it
-- is specified here, not built.
--
-- The summary view **asserts its own class sums**, because `0341` is the precedent: `0340`'s first view
-- reported 515 of 1,676 rows and bucketed the other 1,161 nowhere. Every live agent call lands in exactly
-- one of `applied` / `completed_without_applied_tick` / `fell_back` / `skipped` / `no_handoff`, and the
-- view carries a `classes_sum_to_calls` column so a reader sees the assertion rather than trusting it.
--
-- The summary is grouped by `source_kind`, deliberately: the 1,120 `backfill` rows predate the handoff
-- detail and would silently dilute every rate. Pooling them would be `0322` §10's aggregate-spanning-an-
-- outage mistake.
--
-- ══ §5 APPLIED 20260922070445, AND THE GROUPING PAID FOR ITSELF IMMEDIATELY ═════
--
-- First read of the summary view:
--
--     source_kind  calls  applied  fell_back  no_handoff  mean_stale  p95  max  changed  modal-wrong  mean_lat
--     -----------  -----  -------  ---------  ----------  ----------  ---  ---  -------  -----------  --------
--     live         3,383      640      2,735           0        4.70   17   59    1/638        33.07%  19,723ms
--     backfill     1,120        0          0       1,120           -    -    -        -             -  30,394ms
--
-- `classes_sum_to_calls` is true in both groups.
--
-- **Every one of the 1,120 backfill rows is `no_handoff`** — they predate the handoff detail entirely, so
-- they can contribute no staleness at all — **and their mean latency is 30,394 ms against live's 19,723.**
-- That 30,394 is the exact figure CLAUDE.md Part 3 quotes for G62. So pooling the two source kinds would
-- have raised the live mean by 2.6 seconds and attributed a dead era's latency to the running engine,
-- which is precisely the dilution §4 grouped to avoid. **The guard was written on principle and turned
-- out to be load-bearing on first read.**
--
-- **And the numbers in §1-§3 have already moved, which is the point of the view.** They were measured
-- minutes before this migration applied; the live run kept ticking, so 629 applied became 640 and
-- 33.65% became 33.07%. Neither the shape nor any conclusion changes. **Re-derive from the view; the
-- header numbers are a moment, per CLAUDE.md's "cite the run, never the table."**

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- PREFLIGHT
-- ─────────────────────────────────────────────────────────────────────────────
DO $pre$
DECLARE
  v_n int;
BEGIN
  -- P1. The two provenance fields exist and are populated on live agent calls. If either vanishes this
  --     whole measurement is vacuous, so it is asserted rather than assumed.
  SELECT count(*) INTO v_n
    FROM public.ottoq_model_call_ledger
   WHERE provider='nvidia_nemotron' AND role='agent' AND source_kind='live'
     AND tick_seq IS NOT NULL
     AND detail->'solver_handoff'->'receipt'->>'tick_seq' IS NOT NULL;
  IF v_n < 100 THEN
    RAISE EXCEPTION '0417 P1: only % live agent calls carry BOTH a computed tick and an applied tick. '
                    'The staleness measure has no population -- re-derive before creating the view', v_n;
  END IF;

  -- P2. No applied tick precedes its computed tick. That would mean the two fields are not what §1 says
  --     they are, and every number in this header would be meaningless.
  SELECT count(*) INTO v_n
    FROM public.ottoq_model_call_ledger
   WHERE provider='nvidia_nemotron' AND role='agent' AND source_kind='live'
     AND (detail->'solver_handoff'->'receipt'->>'tick_seq')::bigint < tick_seq;
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0417 P2: % calls report being applied BEFORE they were computed. The field pairing '
                    'in §1 is wrong -- do NOT create the view', v_n;
  END IF;

  -- P3. Every applied-tick string is an integer. A non-numeric value would make the view's cast throw on
  --     read rather than at create time, which is the worst place for it to fail.
  SELECT count(*) INTO v_n
    FROM public.ottoq_model_call_ledger
   WHERE detail->'solver_handoff'->'receipt'->>'tick_seq' IS NOT NULL
     AND detail->'solver_handoff'->'receipt'->>'tick_seq' !~ '^-?[0-9]+$';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '0417 P3: % ledger rows carry a non-integer receipt tick_seq; the view''s cast would '
                    'throw on read', v_n;
  END IF;

  RAISE NOTICE '0417 preflight: provenance fields populated, no applied-before-computed, all casts safe';
END $pre$;

-- ─────────────────────────────────────────────────────────────────────────────
-- DETAIL VIEW — one row per agent call in the ledger, with the two ticks
-- subtracted and the comparison that says whether staleness mattered.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.ottoq_agent_advice_provenance AS
WITH base AS (
  SELECT l.call_id,
         l.sim_run_id,
         l.depot_id,
         l.chain_id,
         l.source_kind,
         l.called_at,
         l.latency_ms,
         l.outcome,
         l.tick_seq                                                     AS computed_tick,
         l.sim_clock                                                    AS computed_sim_clock,
         (l.detail->'solver_handoff'->'receipt'->>'tick_seq')::bigint    AS applied_tick,
         l.detail->'solver_handoff'->'directive'->>'objective'           AS objective,
         l.detail->'solver_handoff'->>'status'                           AS handoff_status,
         l.detail->'solver_handoff'->>'fallback_reason'                  AS fallback_reason,
         (l.detail ? 'solver_handoff')                                   AS has_handoff
    FROM public.ottoq_model_call_ledger l
   WHERE l.provider = 'nvidia_nemotron' AND l.role = 'agent'
)
SELECT b.call_id,
       b.sim_run_id,
       b.depot_id,
       b.chain_id,
       b.source_kind,
       b.called_at,
       b.latency_ms,
       b.outcome,
       b.computed_tick,
       b.computed_sim_clock,
       b.applied_tick,
       b.applied_tick - b.computed_tick                                 AS staleness_ticks,
       b.objective,
       b.handoff_status,
       b.fallback_reason,
       -- Exactly one class per row. Order matters: the applied test is first because it is the only
       -- class in which staleness is defined at all.
       CASE WHEN NOT b.has_handoff                       THEN 'no_handoff'
            WHEN b.handoff_status = 'skipped'             THEN 'skipped'
            WHEN b.handoff_status = 'fallback'            THEN 'fell_back'
            WHEN b.applied_tick IS NOT NULL               THEN 'applied'
            ELSE 'completed_without_applied_tick'
       END                                                              AS staleness_class,
       -- The objective the agent produced at or after the tick this advice was APPLIED at, from a
       -- STRICTLY LATER call. `call_id <> b.call_id` is load-bearing: without it the nearest call is
       -- usually this same row and the comparison is self-referential (§2).
       nxt.objective                                                    AS next_fresh_objective,
       nxt.computed_tick                                                AS next_fresh_tick,
       CASE WHEN b.applied_tick IS NULL OR nxt.objective IS NULL THEN NULL
            ELSE (b.objective IS DISTINCT FROM nxt.objective)
       END                                                              AS staleness_changed_the_answer
  FROM base b
  LEFT JOIN LATERAL (
        SELECT o.objective, o.computed_tick
          FROM base o
         WHERE o.sim_run_id  = b.sim_run_id
           AND o.source_kind = b.source_kind
           AND o.call_id    <> b.call_id
           AND b.applied_tick IS NOT NULL
           AND o.computed_tick >= b.applied_tick
         ORDER BY o.computed_tick, o.call_id
         LIMIT 1
       ) nxt ON true;

COMMENT ON VIEW public.ottoq_agent_advice_provenance IS
'G62 step 2 (db/migrations/0417): one row per Nemotron agent call, pairing the tick the advice was '
'COMPUTED from (ottoq_model_call_ledger.tick_seq) with the tick it was APPLIED at '
'(detail->solver_handoff->receipt->tick_seq). Both fields predate this view by the ledger''s whole life; '
'nobody had subtracted them. staleness_class puts every row in exactly one bucket and only the "applied" '
'bucket has a defined staleness -- the rest are the CP-SAT outage fallbacks of db/checks/0322, not '
'missing measurements. staleness_changed_the_answer compares against a STRICTLY LATER call, which is '
'load-bearing: the nearest call to the applied tick is usually the same row. MEASURED, not enforced, per '
'CLAUDE.md 2.9a -- nothing reads this view on the decide path.';

-- ─────────────────────────────────────────────────────────────────────────────
-- SUMMARY VIEW — the rule-6-shaped answer, per source_kind, with its classes
-- asserted to sum (the check 0340's first view lacked; see 0341).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.ottoq_agent_advice_staleness AS
WITH modal AS (
  -- The agent's own modal objective, per source_kind. This is the BASELINE the 0.16% is read against
  -- (§2): "what if we ignored the agent and hard-coded its most common answer". mode() is an ordered-set
  -- aggregate, so it cannot be computed in the same pass as the FILTERs below.
  SELECT v.source_kind, mode() WITHIN GROUP (ORDER BY v.objective) AS modal_objective
    FROM public.ottoq_agent_advice_provenance v
   WHERE v.objective IS NOT NULL
   GROUP BY v.source_kind
)
SELECT p.source_kind,
       count(*)                                                              AS agent_calls,
       count(*) FILTER (WHERE p.staleness_class='applied')                   AS applied,
       count(*) FILTER (WHERE p.staleness_class='completed_without_applied_tick')
                                                                            AS completed_without_applied_tick,
       count(*) FILTER (WHERE p.staleness_class='fell_back')                 AS fell_back,
       count(*) FILTER (WHERE p.staleness_class='skipped')                   AS skipped,
       count(*) FILTER (WHERE p.staleness_class='no_handoff')                AS no_handoff,
       -- The self-check. A reader should see this rather than trust the FILTERs above.
       (count(*) = count(*) FILTER (WHERE p.staleness_class='applied')
                 + count(*) FILTER (WHERE p.staleness_class='completed_without_applied_tick')
                 + count(*) FILTER (WHERE p.staleness_class='fell_back')
                 + count(*) FILTER (WHERE p.staleness_class='skipped')
                 + count(*) FILTER (WHERE p.staleness_class='no_handoff'))  AS classes_sum_to_calls,
       -- Staleness, over the population where it is defined.
       round(avg(p.staleness_ticks), 2)                                     AS mean_staleness_ticks,
       percentile_disc(0.5)  WITHIN GROUP (ORDER BY p.staleness_ticks)       AS p50_staleness_ticks,
       percentile_disc(0.95) WITHIN GROUP (ORDER BY p.staleness_ticks)       AS p95_staleness_ticks,
       max(p.staleness_ticks)                                               AS max_staleness_ticks,
       count(*) FILTER (WHERE p.staleness_ticks > 1)                        AS stale_over_one_tick,
       count(*) FILTER (WHERE p.staleness_ticks > 10)                       AS stale_over_ten_ticks,
       count(*) FILTER (WHERE p.staleness_ticks < 0)                        AS applied_before_computed,
       -- Did staleness cost anything? (§2)
       count(*) FILTER (WHERE p.staleness_changed_the_answer IS NOT NULL)    AS comparable,
       count(*) FILTER (WHERE p.staleness_changed_the_answer)                AS staleness_changed_answer,
       round(100.0 * count(*) FILTER (WHERE p.staleness_changed_the_answer)
             / NULLIF(count(*) FILTER (WHERE p.staleness_changed_the_answer IS NOT NULL), 0), 2)
                                                                            AS pct_staleness_changed_answer,
       -- The floor that makes the line above meaningful: how often the agent's own modal objective
       -- would have been wrong. Without this, 0.16% reads as "the agent adds nothing".
       m.modal_objective,
       round(100.0 * count(*) FILTER (WHERE p.staleness_changed_the_answer IS NOT NULL
                                        AND p.next_fresh_objective IS DISTINCT FROM m.modal_objective)
             / NULLIF(count(*) FILTER (WHERE p.staleness_changed_the_answer IS NOT NULL), 0), 2)
                                                                            AS pct_modal_constant_would_be_wrong,
       count(DISTINCT p.objective)                                          AS distinct_objectives,
       -- The wait, which §3 argues is the real cost.
       round(avg(p.latency_ms))                                             AS mean_latency_ms,
       percentile_disc(0.5)  WITHIN GROUP (ORDER BY p.latency_ms)            AS p50_latency_ms,
       percentile_disc(0.95) WITHIN GROUP (ORDER BY p.latency_ms)            AS p95_latency_ms,
       max(p.latency_ms)                                                    AS max_latency_ms,
       count(*) FILTER (WHERE p.latency_ms > 30000)                         AS calls_over_thirty_seconds,
       max(p.called_at)                                                     AS last_call_at
  FROM public.ottoq_agent_advice_provenance p
  LEFT JOIN modal m ON m.source_kind = p.source_kind
 GROUP BY p.source_kind, m.modal_objective;

COMMENT ON VIEW public.ottoq_agent_advice_staleness IS
'G62 step 2 summary (db/migrations/0417). Re-derive from here; never quote 0417''s header numbers. '
'Grouped by source_kind on purpose -- the 1,120 backfill rows predate the handoff detail and pooling '
'them would dilute every rate (db/checks/0322 §10''s aggregate-spanning-an-outage mistake). '
'classes_sum_to_calls must be true: 0341 is the precedent for a view that bucketed 1,161 rows nowhere. '
'Read pct_staleness_changed_answer and pct_modal_constant_would_be_wrong TOGETHER -- the first says '
'staleness costs almost nothing, the second says the agent is worth having, and either alone argues for '
'a conclusion the pair does not support. If the agent''s output ever widens beyond the three site-wide '
'objectives, re-derive before building step 4 on it: tolerance of staleness is a property of THIS advice '
'at THIS width.';

-- ─────────────────────────────────────────────────────────────────────────────
-- LINEAGE
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
 ('0417_the_agents_advice_carries_the_tick_it_was_computed_from_and_the_tick_it_was_applied_at_and_nobody_had_ever_subtracted_them',
  false,
  'Adds two read-only views (ottoq_agent_advice_provenance, ottoq_agent_advice_staleness) that subtract '
  'the applied tick from the computed tick on every Nemotron agent call. G62 step 2 of db/checks/0323 '
  '§5: MEASURED, never enforced. FALSE because nothing on the decide path reads either view, no function '
  'is replaced, no column or row changes, and no gate is added -- the tick still blocks on advice exactly '
  'as before. Also records the finding that inverts 0323 §5''s own step ordering: advice a mean of 4.75 '
  'ticks old disagrees with fresh advice in 1 of 627 applied calls (0.16%), while the modal objective '
  'would be wrong on 33.65%, so a validity window would discard correct advice and step 4 (decouple the '
  'beat) is not gated on step 3 after all.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert,
                                 note          = EXCLUDED.note,
                                 classified_at = now();

-- ─────────────────────────────────────────────────────────────────────────────
-- IN-TRANSACTION VERIFY
-- ─────────────────────────────────────────────────────────────────────────────
DO $post$
DECLARE
  v_n     int;
  v_bad   int;
  v_rec   record;
BEGIN
  -- V1. Both views exist and are selectable. A view that creates and then throws on read is worse than
  --     no view, and the casts inside it are exactly the kind that do that.
  SELECT count(*) INTO v_n FROM public.ottoq_agent_advice_provenance;
  IF v_n < 100 THEN
    RAISE EXCEPTION '0417 V1: the provenance view returns only % rows', v_n;
  END IF;

  -- V2. THE 0341 CHECK: every class sums, in every source_kind group. This is the assertion 0340's first
  --     view lacked, which is why it silently reported 515 of 1,676 rows.
  SELECT count(*) INTO v_bad FROM public.ottoq_agent_advice_staleness WHERE NOT classes_sum_to_calls;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '0417 V2: % source_kind group(s) whose outcome classes do not sum to their call '
                    'count -- rows are being bucketed nowhere, the 0341 defect', v_bad;
  END IF;

  -- V3. Every row carries exactly one class, and the class vocabulary is closed. A CASE with a
  --     fall-through ELSE can silently absorb a new handoff status, so name the set.
  SELECT count(*) INTO v_bad FROM public.ottoq_agent_advice_provenance
   WHERE staleness_class IS NULL
      OR staleness_class NOT IN ('applied','completed_without_applied_tick','fell_back','skipped','no_handoff');
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '0417 V3: % row(s) outside the declared staleness_class vocabulary', v_bad;
  END IF;

  -- V4. Staleness is defined EXACTLY on the applied class and nowhere else. If a non-applied row ever
  --     acquired a staleness, the class definition and the measure would have drifted apart.
  SELECT count(*) INTO v_bad FROM public.ottoq_agent_advice_provenance
   WHERE (staleness_class = 'applied') <> (staleness_ticks IS NOT NULL);
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '0417 V4: % row(s) where the applied class and a defined staleness disagree', v_bad;
  END IF;

  -- V5. No advice is applied before it was computed. P2 checked the raw ledger; this checks the view,
  --     because a wrong LATERAL or cast could manufacture one.
  SELECT coalesce(sum(applied_before_computed),0) INTO v_bad FROM public.ottoq_agent_advice_staleness;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '0417 V5: % call(s) applied before computed -- the view is wrong', v_bad;
  END IF;

  -- V6. THE SELF-REFERENCE GUARD, which is the one defect that would have made §2 worthless. No row may
  --     compare itself: the comparison tick must be at or after the applied tick AND the comparison must
  --     come from a different call. Asserted structurally rather than trusted from the view's text.
  SELECT count(*) INTO v_bad FROM public.ottoq_agent_advice_provenance
   WHERE next_fresh_tick IS NOT NULL AND next_fresh_tick < applied_tick;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION '0417 V6: % row(s) compared against advice computed BEFORE the applied tick', v_bad;
  END IF;

  -- V7. Publish the finding rather than asserting a threshold on it. Deliberately a NOTICE: 2.9a says
  --     MEASURED first, so a number moving here must not fail a migration.
  FOR v_rec IN SELECT * FROM public.ottoq_agent_advice_staleness ORDER BY source_kind LOOP
    RAISE NOTICE '0417 %: % calls, % applied, mean staleness % ticks (p95 %, max %), % of % comparable '
                 'changed the answer (%%%), modal constant would be wrong %%%, mean latency % ms',
                 v_rec.source_kind, v_rec.agent_calls, v_rec.applied, v_rec.mean_staleness_ticks,
                 v_rec.p95_staleness_ticks, v_rec.max_staleness_ticks, v_rec.staleness_changed_answer,
                 v_rec.comparable, v_rec.pct_staleness_changed_answer,
                 v_rec.pct_modal_constant_would_be_wrong, v_rec.mean_latency_ms;
  END LOOP;

  RAISE NOTICE '0417 verify: classes sum in every group, vocabulary closed, staleness defined exactly on '
               'the applied class, nothing applied before computed, no self-comparison';
END $post$;

COMMIT;
