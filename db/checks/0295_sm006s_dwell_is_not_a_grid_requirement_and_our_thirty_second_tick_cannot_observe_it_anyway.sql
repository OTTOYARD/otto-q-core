-- 0295  SM.006's "DWELL-THROUGH-STANDBY BETWEEN CHARGE AND DISCHARGE" IS **NOT** A GRID
--       REQUIREMENT — AND THE SHARPER FINDING IS THAT **OUR 30-SECOND TICK CANNOT OBSERVE THE
--       THING THE RULE FORBIDS**, SO THE 14.4% OF TRANSITIONS IT FLAGS ARE NOT EVIDENCE OF
--       ANYTHING. G96 DECIDED.
--
-- Read-only, and the only file tonight whose evidence is EXTERNAL. Scope: the SM.006 population
-- measured by `db/checks/0285` on the twin depot — **3,426 of 23,730 BESS power-state transitions
-- (14.4%) are direct `charge` <-> `discharge`**, which `SM.006.bess_transition_validity` forbids in
-- its own words: *"A BESS unit may only change power state along the admissible transition matrix
-- (dwell-through-standby between charge and discharge)."*
--
-- SM.006 is one of the seven active rule codes with no caller (`0292` §3), and one of the four
-- `critical` ones. Before wiring a `critical` rule that would fail 14.4% of live transitions, the
-- question is whether the rule is right. That question is **external** — it is about inverters, not
-- about our code — which makes it the one item in tonight's queue that needed a web source.
--
-- ══ 1. PROVENANCE FIRST, AND THE CONFIDENCE LABEL IS PART OF THE FINDING ═══
--
-- Searched 2026-09-20 (2026-09-21 01:4x UTC). **I did not read IEEE 1547-2018 itself** — it is
-- paywalled, and the search surfaced a university-hosted copy which I deliberately did not treat as
-- authoritative. Everything below is from **secondary summaries by credible institutions**, so this
-- is strong indicative evidence and NOT a settled vendor fact. Labelled that way on purpose:
-- CLAUDE.md rule 3 requires the claim, the version and the URL, and a fourth thing this repo keeps
-- learning — how much the source can actually bear.
--
--   CLAIM  IEEE 1547-2018 requires a DER mode transition to complete in **no greater than 30
--          seconds**, with output transitioning smoothly over a window of 5 to 300 seconds.
--   APPLIES TO  IEEE Std 1547-2018, whose DER definition explicitly includes energy storage
--          capable of exporting active power, with the whole standard applying.
--   SOURCES  NREL, "Highlights of IEEE Standard 1547-2018" (fy20osti/75436)
--            https://docs.nrel.gov/docs/fy20osti/75436.pdf
--            IREC, "How IEEE 1547.1-2020 Paves the Way for More Energy Storage"
--            https://irecusa.org/blog/regulatory-engagement/how-ieee-1547-1-2020-paves-the-way-for-more-energy-storage-a-smarter-grid/
--            Sandia National Laboratories, "Introduction to IEEE 1547" (2023 Vermont webinar)
--            https://www.sandia.gov/app/uploads/sites/273/2023/11/2023_Vermont_Webinar_Vartanian1.pdf
--
-- **THE DECISIVE READING: that is a CEILING on how long a transition may take, not a FLOOR
-- requiring a rest in standby.** Nothing found in any source imposes a minimum dwell, or requires
-- passing through standby, between charging and discharging. The corroborating direction is the
-- same: grid-support literature describes storage going from standby to full power in under a
-- second, and field reports describe inverters reversing charge/discharge within seconds.
--
-- **So SM.006's parenthetical is not grid legality.** It may still be a defensible BATTERY-HEALTH
-- preference — rapid cycle reversal is a real wear consideration — but that is a different claim,
-- with a different justification, and the rule does not make it.
--
-- ══ 2. AND THE FINDING THAT MATTERS MORE, WHICH IS ABOUT OUR CLOCK ═════════
--
-- **The twin's tick is 30 seconds** (`tick_interval_seconds = 30`, verified on both runs). IEEE
-- 1547-2018's transition ceiling is **also 30 seconds**. So a fully compliant inverter may begin
-- charging and be discharging by the next sample, **with the entire transition — standby dwell or
-- not — invisible between two ticks.**
--
-- Therefore: a `charge` -> `discharge` pair in consecutive `bess_snapshots` rows **is not evidence
-- that no dwell occurred.** It is evidence that our sampling interval is as coarse as the standard's
-- own allowance. The 3,426 flagged transitions are consistent with perfect compliance and with none
-- at all, and nothing at this resolution distinguishes them.
--
-- **This is the `0289` shape a fourth time, and now from the other direction:** there `offerable`
-- answered a narrower question than it was read as answering; here the DATA answers a coarser
-- question than the rule asks. Both are a predicate/observation mismatch, and both would have
-- produced a confident wrong number.
--
-- **AND IT EXPLAINS WHY WIRING SM.006 WOULD HAVE BEEN WORSE THAN LEAVING IT UNWIRED.** A `critical`
-- rule with `enforcement='block'` fired at `bess_state_change` would have refused 14.4% of BESS
-- transitions on the grounds of a dwell it cannot see, enforcing a requirement no source supports.
-- `0292` §3 listed SM.006 among "the input it needs does exist" cases. It does not: what exists is a
-- sample too coarse to carry the question.

SELECT tick_interval_seconds AS twin_tick_seconds,
       30 AS ieee_1547_2018_transition_ceiling_seconds,
       'a compliant transition may complete inside one tick, so consecutive-sample '
       'charge->discharge is not evidence that no dwell occurred' AS why_unobservable
  FROM public.ottoq_sim_runs
 WHERE sim_run_id = 'c9b0a87e-0d39-4bd8-9a91-12837b2995a3';

-- the rule's own text, so the claim above is checkable against the declaration rather than my note
SELECT rule_code, severity, enforcement, applies_to_actions, description
  FROM public.ottoq_rules
 WHERE rule_code = 'SM.006.bess_transition_validity' AND status = 'active';

-- ══ 3. THE DECISION, WHICH IS MINE PER CHASE'S 2026-09-21 INSTRUCTION ══════
--
-- **G96: do NOT wire SM.006 as written. Split it, and drop the dwell clause from the rule.**
--
--   (a) **Keep the transition matrix.** "A BESS unit may only change power state along the
--       admissible matrix" is a real state-machine invariant, observable at any resolution, and
--       exactly the kind of thing `0387` wired successfully for SM.001 and SM.003. That half can be
--       enforced honestly.
--   (b) **Delete "(dwell-through-standby between charge and discharge)" from the description**, or
--       move it to a separate, non-`critical`, non-`block` rule whose rationale cites battery wear
--       rather than grid legality — and which is NOT enforced until the twin samples finely enough
--       to see a transition. A rule that asserts a grid requirement which no source supports is the
--       `0231` defect in rule form: a declaration relied upon for a property nothing establishes.
--
-- **NOT BUILT HERE.** Editing a `critical` rule's declaration is a versioned change to
-- `ottoq_rules` (the archive-a-row-and-supersede pattern), and wiring (a) is a new probe at
-- `bess_state_change` — a tick-path change, `forces_recert TRUE`. Both wait for run `c9b0a87e` to
-- finish, for the same reason everything else tonight waited: the measurement in flight must not be
-- perturbed by the thing being measured against it.
--
-- ══ 4. WHAT I WOULD ASK HERMES, AND WHY IT IS WORTH ASKING ═════════════════
--
-- This is precisely the shape CLAUDE.md rule 3 reserves for Hermes: not blocking, benefits from a
-- survey, and needs a primary source I cannot reach. A request file is the right next step rather
-- than more searching by me, and the questions are narrow enough to answer:
--
--   1. Does IEEE 1547-2018 (or 1547.1-2020) impose any MINIMUM time in a non-exporting state
--      between active-power absorption and active-power injection? Cite clause.
--   2. Do the major grid-tied BESS inverter vendors document a required dwell or a minimum
--      reversal interval for charge<->discharge? Name the product, firmware version and page.
--   3. Is there a battery-health basis for a dwell that is quantified per chemistry — and if so, in
--      what units, so a rule could be parameterised rather than asserted?
--
-- **Until that comes back, the honest sentence about SM.006:** *"Its state-machine half is
-- enforceable and unwired; its dwell half asserts a grid requirement no source we have found
-- supports, and our 30-second tick could not observe it even if it existed."*

-- OPEN-ITEM: SM.006's dwell clause should be split out of the rule and the transition matrix wired separately -- a versioned ottoq_rules edit plus a new bess_state_change probe, forces_recert TRUE, deferred until run c9b0a87e finishes. Tracked as G96.
-- OPEN-ITEM: the IEEE 1547 reading here rests on secondary institutional summaries, not the standard itself; a Hermes request with the three questions in section 4 is the right way to make it primary. Tracked as G96.
