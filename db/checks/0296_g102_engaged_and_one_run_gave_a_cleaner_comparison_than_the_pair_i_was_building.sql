-- 0296  G102 ENGAGED — AND THIS RUN HANDED ME A **WITHIN-RUN CONTROLLED COMPARISON** BETTER THAN
--       THE CROSS-RUN PAIR I HAD BEEN TRYING TO BUILD, BECAUSE IT PRODUCED **BOTH** KINDS OF
--       ABSTENTION AT ONCE: THE KIND THE FIX COVERS RAN AT **1.25 PER VEHICLE**, THE KIND IT DOES
--       NOT AT **30.5**. A 24x SEPARATION, SAME RUN, SAME FIRES, NO CONFOUND.
--       AND THE UNCOVERED KIND IS A NEW FINDING: ITS REASON IS ONE THE PROPOSER'S OWN AUTHOR
--       FLAGGED AS UNEXPECTED. **G106.**
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), run
-- `c9b0a87e-0d39-4bd8-9a91-12837b2995a3` (busy_day, seed 100020, speed 8.0,
-- `sim_clock_start` 2026-09-20T05:35:00+00 — identical to `e8b8eb3e` on every parameter).
-- **Figures in §1–§4 are as of tick 1101–1143 and are SUPERSEDED BY §5 and §6.** §5 re-measures at
-- tick 1234 (105 planning fires, separation 58x); **§6 is the finished run at tick 1335 — 229
-- planning fires, 332 suppressions, and the separation settling at 57x (97.22 against 1.70 per
-- vehicle)**. My "tail sample of the wave" caveat is withdrawn in §5 and stays withdrawn: 229
-- planning fires is far more than `e8b8eb3e`'s 42. Left in place rather than rewritten, because a
-- figure quoted at three sample sizes is the honest record of a moving measurement — and the
-- separation strengthening 24x -> 58x -> 57x as the sample grew is itself the evidence it is real.
-- **§5's DIAGNOSIS of G106 is RETRACTED inside §5 itself**; the finding stands, the cause does not.
-- Every count is `class='engine'` and `0395`'s reason for existing: §6 records them before the next
-- demo run purges them.
--
-- ══ 1. THE DIRECT EVIDENCE THAT THE FIX ENGAGED ════════════════════════════
--
-- `0294`'s check-in named the evidence in advance: *"the fire record carries NEW keys
-- `n_suppressed_not_due` and `n_not_due_remembered` — they are the direct evidence the fix
-- engaged. If `n_suppressed_not_due` is 0 across all fires, the fix did NOT engage and that is the
-- first thing to diagnose, not a null result."* Measured over the 37 planning fires:
--
--   `n_not_due_remembered`, peak                    **5**
--   `n_suppressed_not_due`, total                  **55**
--   planning fires that suppressed something   **21 of 37**
--
-- **55 vehicle-fires withheld.** Those are proposals that the pre-G102 loop would have submitted
-- and that carried no new information: the same vehicle, the same plan, not yet due.
--
-- **AND I NEARLY REPORTED THE OPPOSITE.** The first fires I sampled — ticks 1093 to 1101 — all read
-- `n_suppressed_not_due = 0` and `n_not_due_remembered = 0`, and I began writing the diagnosis for
-- a fix that had not engaged. **Those were simply the earliest fires, before any not-due abstention
-- had been produced to remember.** The suppression window here is short (planned start +35 min
-- against a 30-min window = 5 sim-minutes, about 37 wall-seconds at speed 8.0), so a sample taken
-- at the very start of a loop sees nothing and a sample over the whole loop sees 55. **A zero read
-- from the first N of a series is not a zero.**

SELECT max((fire->>'n_not_due_remembered')::int)            AS remembered_peak,
       sum((fire->>'n_suppressed_not_due')::int)            AS suppressed_total,
       count(*) FILTER (WHERE (fire->>'n_suppressed_not_due')::int > 0) AS fires_that_suppressed,
       count(*)                                             AS planning_fires
  FROM public.ottoq_proposer_fire_log
 WHERE sim_run_id = 'c9b0a87e-0d39-4bd8-9a91-12837b2995a3' AND status <> 'empty';

-- ══ 2. THE COMPARISON, AND IT IS BETTER THAN THE ONE I PLANNED ═════════════
--
-- `0294` §2 is the record of me ruining a cross-run pair by changing three loop knobs while holding
-- the seed. The repair I proposed there was *another* run with one variable. **This run made that
-- unnecessary**, by accident: it produced **both** abstention kinds in the same fires, so the
-- comparison is between two populations inside one run rather than between two runs.
--
--   abstention kind                              rows   vehicles   per vehicle
--   ------------------------------------------   ----   --------   -----------
--   `bridge:not_due`  (G102's domain)               5          4      **1.25**
--     "planned to start at +35 min on dcfc …,
--      beyond this tick's 30-min window;
--      re-offered when due"
--   `(none)`  (NOT G102's domain)                 122          4      **30.5**
--     "no charge operation in the returned plan"
--
-- **A 24x separation between the kind the fix covers and the kind it does not — same run, same 37
-- fires, same seed, same loop configuration, same four-vehicle order of magnitude on each side.**
-- Nothing here is confounded by anything, because nothing differs except which code path the
-- abstention came from.
--
-- **And the 55 suppressions make the counterfactual explicit**: without the fix those 4 vehicles
-- would have produced roughly 60 not-due rows instead of 5. The measured 1.25 per vehicle IS the
-- suppression working, not an absence of demand for it.
--
-- **WHAT THIS DOES AND DOES NOT SETTLE.** It settles that G102 removes the churn *in its domain*,
-- with a number. It does **not** settle `0294`'s open question — whether `0390` moved CP-SAT's
-- enacted share — because that still needs the single-variable re-run, and this run cannot answer
-- it either: its loop caught only a tail of the wave. **G103 keeps that item; it is not closed
-- here.** And it does not show the churn *overall* falling, because §3.

WITH ab AS (
  SELECT COALESCE(proposal->'rationale'->>'abstained_by', '(none)') AS kind,
         COALESCE(proposal->'rationale'->>'reason', '(none)')       AS reason,
         entity_id
    FROM public.ottoq_external_proposals
   WHERE sim_run_id = 'c9b0a87e-0d39-4bd8-9a91-12837b2995a3'
     AND source = 'forward_lex'
     AND COALESCE(proposal->>'abstain', '') IN ('true', 't', '1'))
SELECT kind,
       count(*)                                                    AS rows_,
       count(DISTINCT entity_id)                                   AS vehicles,
       round(count(*)::numeric / NULLIF(count(DISTINCT entity_id), 0), 2) AS per_vehicle,
       left(max(reason), 96)                                       AS sample_reason
  FROM ab GROUP BY kind ORDER BY rows_ DESC;

-- ══ 3. G106 — THE DOMINANT CHURN SOURCE IS NOW A REASON THE AUTHOR CALLED UNEXPECTED ══
--
-- 122 of the 127 abstentions carry **"no charge operation in the returned plan"**, from **four
-- vehicles**. Read at its source, `proposer/forward_proposer.py` around line 1010:
--
--     charge = next((o for o in a["ops"] if o["op"] == "charge"), None)
--     if charge is None:
--         #: served is False -> the solver looked and could not place it.
--         #: served absent -> rejection was off, so no charge op means something
--         #: unexpected; say that rather than inventing a reason.
--         reason = ("the site could not serve this vehicle within its capacity"
--                   if a.get("served") is False else
--                   "no charge operation in the returned plan")
--
-- **The string we are seeing is the SECOND branch** — the one taken when `served` is *absent*,
-- which happens with `allow_rejection` off. Its own comment says that case means *"something
-- unexpected."* So this is **not** the normal capacity decline: that one reads *"the site could not
-- serve this vehicle within its capacity"* and arrives with `served: False`, and it does not appear
-- on this run at all.
--
-- **So the engine's dominant remaining churn is a state its author explicitly did not expect**:
-- the solver returns a plan in which an asset has no charge operation, while rejection is off and
-- the model is therefore supposed to serve every asset or declare the frame infeasible.
--
-- **TWO READINGS, AND I AM NOT CHOOSING BETWEEN THEM HERE.** Either (a) a vehicle is reaching the
-- solve that should not have (the serviceable filter admits something at or above its target SoC,
-- so the model correctly gives it no charge op), or (b) the plan's shape carries assets the charge
-- set does not cover. (a) would make this a filter defect in the proposer; (b) a contract mismatch
-- between the solver's output and the translator's assumption. **Which one is a code read, not a
-- measurement, and it is the next thing to do.**
--
-- **AND THE FIX SHAPE DIFFERS FROM G102's, WHICH IS THE POINT FOR SEAM 3.** A `not_due` abstention
-- carries `planned_start_min` — a *time* at which the answer changes, which is why suppression
-- works. "No charge operation" carries no such field and no such time: the answer changes when the
-- vehicle's STATE changes (SoC, needs), not when the clock advances. So suppressing it needs a
-- **frame delta** — "nothing relevant about this vehicle has moved since tick N" — which is exactly
-- the missing reverse channel `db/checks/0291` named as seam 3 and the one genuinely absent
-- component of the six. **This is its second concrete instance, and the first with a number.**
--
-- ══ 4. WHAT G102's CLAIM MAY NOW SAY ══════════════════════════════════════
--
-- **MAY:** *"In its own domain the fix removes the churn: 55 vehicle-fires suppressed across 21 of
-- 37 planning fires, and the not-due abstentions it governs ran at 1.25 per vehicle against 30.5
-- for the kind it does not govern — a 24x separation inside one run."*
--
-- **MAY NOT:** *"G102 fixed the churn."* It fixed one of two sources, and the other is now 96% of
-- the abstentions. I framed G102 as "the churn fix" when I built it; that framing was too broad and
-- this run is what narrows it.
--
-- **MAY NOT:** anything about `0390`'s effect on enacted share, or about CP-SAT's standing under
-- load from this run. The loop caught a tail of the wave (dispatched at tick ~1093 of a run whose
-- twin ended at 1189), so its enacted counts are a small sample and not comparable to
-- `e8b8eb3e`'s full-wave figures.

-- OPEN-ITEM: 122 of 127 abstentions on run c9b0a87e carry "no charge operation in the returned plan" -- the branch forward_proposer.py's own comment calls "something unexpected" (served absent, rejection off) -- from four vehicles at 30.5 each. Either the serviceable filter admits a vehicle that needs no charge, or the plan shape carries assets the charge set does not cover; deciding between them is a code read. Tracked as G106.
-- OPEN-ITEM: suppressing the "no charge operation" churn needs a frame delta rather than a due time, because unlike a not_due abstention it carries no time at which the answer changes -- seam 3's missing reverse channel from db/checks/0291, now with its second instance and a number. Tracked as G106.


-- ══ 5. RE-MEASURED AT TICK 1234, AND G106 IS NOW DIAGNOSED RATHER THAN POSED ══
--
-- The loop kept firing after §1–§4 were written. At tick 1234, **105 planning fires** (against the
-- 37 those sections quote, and against `e8b8eb3e`'s 42) and **176 suppressions**:
--
--   abstention kind                          rows   vehicles   per vehicle
--   `bridge:not_due`  (G102's domain)          10          7      **1.43**
--   `(none)`  "no charge operation"           417          5     **83.40**
--
-- **58x, up from 24x.** The separation strengthened with the sample, which is the direction a real
-- effect goes. §1's suppression count rose 55 -> 176 over the same interval.
--
-- ══ AND A CAUSE I PROPOSED AND THEN KILLED WITH THE ONE QUERY I HAD SKIPPED ══
--
-- §3 posed two readings — a proposer filter defect, or a solver/translator contract mismatch — and
-- said deciding was a code read. **I read the code, inferred a third reading from it, and it is
-- WRONG.** The retraction is worth more than the reading was, so both are here.
--
-- **WHAT I WROTE, AND WITHDRAW.** At tick 1234 the four abstaining vehicles read soc 84, 89, 89 and
-- 92. The admission filter is `soc < _resolved_target_soc(vehicle)` and `DEFAULT_TARGET_SOC_PCT =
-- 90`, so I concluded that a vehicle at 89 was being admitted for ONE percentage point of deficit,
-- reproducing inside a one-point band the very defect the constant's own comment records as fixed
-- ("…an asset with no charge segments, occupying the model and the plan and proposable to nothing").
-- I proposed a minimum-useful-deficit band as the fix.
--
-- **WHAT THE FIELD ACTUALLY SAYS.** `ottoq_build_decision_frame` sets the frame's `target_soc`
-- straight from `vehicles.target_soc` — confirmed in its own source, `'target_soc', v.target_soc`.
-- Measured on all six vehicles that carry the 872 `no charge operation` abstentions of the finished
-- run:
--
--   vehicle        soc   target_soc   deficit   abstentions
--   44444820…       57        100        43          84
--   616a06de…       84        100        16         228
--   96b10b07…       89        100        11         229
--   b2222222…       90        100        10          40
--   cadd7c81…       92        100         8         188
--   5ea53696…       97        100         3         103
--
-- **Every one carries an explicit `target_soc` of 100. The default never applied, and the smallest
-- deficit in the set is three points, not one.** A minimum-useful-deficit band set anywhere below 3
-- would have changed nothing for any of the six; set high enough to catch the 97 it would still
-- leave the other five, including **a vehicle 43 points below target abstaining 84 times.** No
-- deficit threshold explains that row, so no deficit threshold is the fix.
--
-- **AND THE DEFAULT IS DEAD CODE ON LIVE DATA, which is the checkable version of the same point.**
-- `SELECT count(*) FILTER (WHERE target_soc IS NULL) FROM public.vehicles` returns **0 of 226**, so
-- `_resolved_target_soc` has never once fallen through to `DEFAULT_TARGET_SOC_PCT` for a row this
-- frame produced. The fleet's own dominant target is **100 (140 of 226 vehicles), against 90 on 78**
-- — so the L-24 comment's argument that "90 is the number the kernel itself defaults to" is true of
-- the kernel and false of the fleet, and the number that actually governs admission is 100.
--
-- **THE LESSON, and it is the file's own subject turned on me.** 0289/0292/0295 are all one shape: a
-- field that answers a narrower question than the reader takes it to answer. Here I did worse than
-- misread a field — **I inferred its value from a default instead of selecting it**, in a check file
-- whose thesis is that you must read the field. One `SELECT target_soc` would have stopped the wrong
-- diagnosis before it was written. It cost nothing because it was caught before the fix was built;
-- had I built the band first, it would have shipped a no-op and closed G106 falsely.
--
-- **WHAT IS NOW MEASURED, AND WHAT IS OPEN.** MEASURED: six vehicles, targets all 100, deficits 3 to
-- 43, 872 of 875 rows on the reason `no charge operation in the returned plan`. **And the remaining
-- 3 rows retract §5's other claim** — `1225f10e…`, `5e93a514…` and `2cd2cbf3…` carry one row each of
-- *"the site could not serve this vehicle within its capacity"*, so the `served is False` branch DOES
-- appear on this run. It was absent at tick 1234 and present by tick 1335; "does not appear" was a
-- statement about a moment, exactly as the counts are.
-- **OPEN: why the plan contains no charge op for a vehicle 43 points down.** The plausible causes are
-- now capacity-shaped rather than threshold-shaped — no charge stall offerable in the ready-by window
-- under the three gates of 0372, a `charge_kinds` mismatch, or a window too short to fit a segment —
-- and the 872-row branch states no reason, so the plan does not say which. That is the frame-delta
-- work §3 described, and it is unchanged by tonight's retraction; what is gone is the cheap
-- alternative I thought I had found.

-- OPEN-ITEM: forward_lex plans no charge operation for six vehicles whose deficits against an explicit target_soc of 100 run from 3 to 43 percentage points, producing 872 of the run's 875 reasonless abstentions; the branch states no reason, so the frame delta that would name it is still the needed work. A minimum-useful-deficit band was proposed and is retracted -- it cannot explain a 43-point deficit. Tracked as G106.
-- OPEN-ITEM: DEFAULT_TARGET_SOC_PCT = 90 in proposer/forward_proposer.py is unreachable on live data -- zero of 226 vehicles carry a NULL target_soc, and the fleet's dominant explicit target is 100 on 140 vehicles against 90 on 78. The constant's L-24 comment argues 90 because the kernel defaults to it, which is true of the kernel and false of the fleet; whether admission should be governed by the fleet's 100 is a product question, not a code cleanup. Tracked as G106.

-- ══ 6. THE RUN FINISHED. THE FIVE KPIs, RECORDED BEFORE ANYTHING PURGES THEM ══
--
-- `c9b0a87e` reached `status='completed'` at tick **1335**, `failure_reason` *"run_governor: reached
-- the 540 sim-minute ceiling"* — the governor stopping it on plan, not a failure. **`0395` exists so
-- that these numbers are written down before the next demo run's `ottoq_purge_prior_runs` takes every
-- `class='engine'` table they are computed from to near zero.** Recorded here first, quoted anywhere
-- else second.
--
--   run_key   pack `robotaxi` · scenario `busy_day` · seed **100020** · policy `otto_q`
--             config_hash **89e34c73047dbd1eae2ea50f14c4eea5**
--             engine_hash **ec8dfa0380654d701136246c3c15d350**
--   not_reproducible  **[]**   (all eight published figures reproducible from the run ID)
--
--   KPI                                        c9b0a87e   e8b8eb3e   c8f678fb
--   1  asset_hours_available_per_day              26.64      48.04      57.89
--   2  service_point_turns_per_point_per_day       2.12       3.40       3.56
--   3  peak_site_kw                            1,071.8    1,113.8          —
--      peak_site_kw_demand                     1,058.0          —          —
--   4  touch_events_per_turn                      0.135      0.140      1.091*
--   5  p95_time_to_service_min                     71.1       58.1       39.6
--      p50_time_to_service_min                      0.8          —          —
--      returns_unserved                               11          6         11
--
--   * `c8f678fb`'s 1.091 is the PRE-`0391` definition. `0391` is holding: `touch_events_override` is
--     **0** while `touch_events_override_flag_only` is **246**, so the old numerator would have
--     published (44+246)/326 = **0.890** against the correct **0.135**. Third run in a row confirming
--     the shield's own safe defaults are not human labour.
--
-- **AND THE COMPARISON ACROSS THOSE COLUMNS IS NOT AN EXPERIMENT — SAY SO WHEREVER IT APPEARS.**
-- `e8b8eb3e` and `c9b0a87e` share seed, scenario, depot and `sim_clock_start`, and they differ on
-- **both** hashes: config_hash `0053a045…` -> `89e34c73…` (the three loop knobs of `0294` §2, plus a
-- longer horizon) and engine_hash `797d8dcef…` -> `ec8dfa038…` (migrations `0391`–`0395`). Two runs
-- sharing a seed are not a controlled pair; `ottoq_run_config_key` says so in its own field. The
-- three-column table above is a **trend log**, and the only controlled comparison tonight is the
-- within-run one of §1–§5.
--
-- ══ G103 IS UNCHANGED AND STILL WRONG BY MORE, WHICH IS THE ONE RED FLAG HERE ══
--
-- KPI 1's audit block reads `hours_clipped_to_window` = **-227.36** (it was -237.29 on `e8b8eb3e`).
-- A clip is a subtraction of hours outside the window; **a negative clip means hours were ADDED**, so
-- 26.64 is the post-clip number and 26.64 + (-227.36) would be the pre-clip one. Two runs, two
-- negative clips of the same magnitude: this is structural, not incidental. G103 stands open and is
-- the largest unexplained quantity in the KPI payload.
--
-- ══ AND THE RESULT THE LOOP WAS RUN FOR: forward_lex ENACTED FOR THE FIRST TIME ══
--
--   enacted, by source, 167 total
--     deterministic_v1        77      reservation_honoured      65
--     reservation_reopt       12      greedy_constrained         5
--     **forward_lex            4**    **cuopt                    2**
--     reservation_broken       1      reservation_reassigned     1
--
-- **On `e8b8eb3e` `forward_lex` enacted ZERO after ~900 proposals. Here it enacted 4, on 4 distinct
-- vehicles, at ticks 1106–1220.** That is the first time CP-SAT's proposals have been disposed into
-- the world by the deterministic path on a full-length run. It is a small number and it is not
-- nothing: propose/dispose is now demonstrated end to end with a real solver on one end of it.
--
-- **Quantified honestly, because rule 6's posture applies to our own solver too.** Of `forward_lex`'s
-- 1,503 rows, **892 are abstentions** and **611 are real proposals**; of those 611: **4 enacted, 3
-- refused, 8 expired, and 596 superseded (97.5%)**. So the churn §3 described is undiminished in the
-- state-keyed half — G102 withheld **332** vehicle-fires of the *time*-keyed half, and the 596 are
-- what remains. **The honest sentence: "CP-SAT proposed 611 stall assignments on this run, four were
-- enacted, three were refused by the shield, and 596 were superseded by its own next fire."**
-- Do not quote "4 enacted" without the 611, and do not quote the 611 without the 892 abstentions.
--
-- **One anomaly noted, not chased:** 23 of the 892 abstention rows carry `status='refused'`. An
-- abstention proposes nothing, so there should be nothing for the shield to refuse. Either the
-- disposition path labels an abstention's expiry as a refusal, or `refused_real` is over-counting.
-- It does not affect any figure above — the four enactments and the 611 are counted from `real` rows.

-- the run key and the five KPIs, re-derivable while this run's engine tables survive
SELECT jsonb_pretty(public.ottoq_kpi_five('c9b0a87e-0d39-4bd8-9a91-12837b2995a3'::uuid)) AS kpis;

-- OPEN-ITEM: KPI 1's audit hours_clipped_to_window is negative on two consecutive runs (-237.29 on e8b8eb3e, -227.36 on c9b0a87e); a clip that adds hours is structurally wrong and is the largest unexplained quantity in the KPI payload. Tracked as G103.
-- OPEN-ITEM: 23 of forward_lex's 892 abstention rows carry status='refused' on run c9b0a87e, but an abstention proposes nothing for the shield to refuse; either the disposition path mislabels an abstention's expiry or refused_real over-counts. Affects no published figure. Tracked as G106.
