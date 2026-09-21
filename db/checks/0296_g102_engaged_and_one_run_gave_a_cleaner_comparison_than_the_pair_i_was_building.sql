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
-- **Figures below are as of tick 1101–1143, with the run still advancing**; the wave loop was
-- dispatched late (tick ~1093) because the run reached its wave near the governor ceiling, so this
-- is a **tail sample of the wave, not the whole wave**. Every count is `class='engine'`.
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
