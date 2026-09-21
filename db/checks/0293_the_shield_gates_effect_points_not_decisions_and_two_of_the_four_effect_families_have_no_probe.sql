-- 0293  THE L1 SHIELD IS ENFORCED AT **EFFECT POINTS**, NOT AT DECISIONS — AND TWO OF THE FOUR
--       EFFECT FAMILIES HAVE **NO PROBE AT ALL**. POWER AND POLICY ARE GATED AT A CHOKEPOINT THAT
--       COVERS EVERY CALLER; **SPACE AND MOVEMENT ARE GATED ONLY INLINE INSIDE
--       `ottoq_decide_tick`**, SO EVERY OTHER WRITER OF A BOOKING OR A MOVE IS UNCHECKED BY
--       CONSTRUCTION. THIS IS THE FINDING `0392` WAS GROPING AT AND GOT BACKWARDS TWICE.
--
-- Read-only. Scope: twin depot 11111111-1111-1111-1111-111111111111 (rule 8), live run
-- `e8b8eb3e-da9d-41ff-ab67-84b6998ba441` (busy_day, seed 100020), measured 2026-09-20 19:49 CT
-- (2026-09-21 00:49 UTC), tick 780, 06:15 CT, run in flight with the return wave arriving.
--
-- ══ 1. HOW THIS WAS ARRIVED AT, BECAUSE THE ROUTE IS THE EVIDENCE ══════════
--
-- `0392` built an action-side coverage instrument and reported five unshielded enacting branches.
-- `0292` retracted the first of them: the agent is gated at `policy_write`, one hop down from its
-- decision row. Then `ottoq_shield_coverage` — doing exactly its job — surfaced a **sixth** branch
-- as the run advanced, `reservation_reopt`, which had not existed in the census two hours earlier.
--
-- Reading it was alarming: `ottoq.ottoq_reoptimize_reservation_book` takes a vehicle `deployed` or
-- `en_route_to_depot` below 45% SoC holding a non-DCFC reservation, finds a free healthy DCFC
-- (preferring a fresh cuOpt proposal, else the local floor), calls `ottoq_reserve_stall` on the new
-- one, releases the old, rebuilds the workflow plan, sends `proceed_to_stall`, marks the cuOpt
-- proposal `enacted`, and writes an `'enacted'` decision — **with no `ottoq_shield_probe` anywhere
-- in the function.** Measured on this run: **9 enacted rebooks across 9 vehicles, 0 shielded,
-- ticks 364–658, one of them via the `cuopt` branch.**
--
-- **And then I applied `0292`'s own lesson before publishing, which is the only reason this file
-- says something true.** The question that retracted the agent claim is *"is it gated one hop
-- down?"*, so I asked it here too. **Answer: partly, and the part that is gated is the part that
-- matters most.** All nine rebooked vehicles accumulate `charge_session_start` evaluations on their
-- new stall — 5, 10 or 15 each, i.e. one, two or three sessions × the five codes `EN.001`
-- grid_capacity_ceiling, `EN.002` stall_power_ceiling, `EN.004`, `EN.005`, `HW.002`. **The power
-- draw IS gated.** And all nine show `stall_assignment` evaluations = **0**, so the space claim
-- never was.

WITH reopt AS (
  SELECT entity_id AS veh, tick_seq, (enacted_action->>'stall_id')::uuid AS new_stall,
         enacted_action->>'source' AS src
    FROM public.ottoq_decisions
   WHERE sim_run_id = 'e8b8eb3e-da9d-41ff-ab67-84b6998ba441'
     AND resolved_action_context = 'reservation_reopt'
     AND outcome_status = 'enacted')
SELECT r.veh, r.tick_seq AS reopt_tick, r.src,
       (SELECT count(*) FROM public.ottoq_rule_evaluations e
         WHERE e.sim_run_id = 'e8b8eb3e-da9d-41ff-ab67-84b6998ba441'
           AND e.action_context = 'charge_session_start'
           AND (e.entity_id = r.new_stall OR e.entity_id = r.veh))
         AS charge_session_start_evals,
       (SELECT count(*) FROM public.ottoq_rule_evaluations e
         WHERE e.sim_run_id = 'e8b8eb3e-da9d-41ff-ab67-84b6998ba441'
           AND e.action_context = 'stall_assignment' AND e.entity_id = r.veh)
         AS stall_assignment_evals
  FROM reopt r ORDER BY r.tick_seq;

-- ══ 2. SO THE ARCHITECTURE IS CHOKEPOINT GATING, AND IT IS HALF BUILT ══════
--
-- One query over the effect points settles the whole shape — does each call `ottoq_shield_probe`:
--
--   **GATED AT THE CHOKEPOINT (covers every caller, forever):**
--     `public.ottoq_policy_set`            -> `policy_write`,        AI.001, 254 evals this run
--     `twin.ottoq_sim_start_charge_session`-> `charge_session_start`, 5 codes, 335 evals this run
--
--   **NO PROBE AT ALL:**
--     `ottoq.ottoq_book_stall`             the CALENDAR write
--     `public.ottoq_reserve_stall`         the POINTER claim
--     `ottoq.ottoq_emit_vehicle_command`   the MOVEMENT command
--     `public.ottoq_comms_send_command`    the MOVEMENT command
--
-- **That is the finding, and it is structural rather than a list of forgetful callers.** The shield
-- gates **power** and **policy** at a chokepoint, so every writer of a dial or a charge session is
-- covered whether or not its author remembered. It gates **space** and **movement** nowhere — those
-- are checked only by the probe blocks written inline in `ottoq_decide_tick`, so coverage for the
-- two effect families that physically move vehicles around a yard is **exactly the set of callers
-- that happen to live inside one 83,000-character function.**
--
-- Which is why the census kept finding branches: `gate_intake_no_charge` books a staging stall and
-- commands a move; `reservation_reopt` reserves a DCFC and commands a move. Neither is a lapse by
-- its author — **there is no chokepoint for either of them to have used.**
--
-- **AND IT EXPLAINS THE ONE NUMBER 2.5 IS MOST QUOTED ON.** CLAUDE.md 2.5 says the safe way to
-- consume a nondeterministic proposer is *"behind an inviolable deterministic shield."* On this run
-- **one cuOpt proposal was enacted straight into a DCFC reservation through
-- `ottoq_reoptimize_reservation_book`** — the `cuopt` row above — with the space claim passing no
-- rule. The power it will draw is gated at session start, so the site cap holds; the *stall choice*
-- was the solver's, unreviewed. That is a narrow exception and it should be stated as one, not
-- generalised: **1 of 9 rebooks on one run, and the claim to fix is about SPACE, not POWER.**

SELECT n.nspname||'.'||p.proname AS effect_point,
       (p.prosrc LIKE '%ottoq_shield_probe%') AS calls_probe,
       CASE n.nspname||'.'||p.proname
         WHEN 'public.ottoq_policy_set'             THEN 'policy'
         WHEN 'twin.ottoq_sim_start_charge_session' THEN 'power'
         WHEN 'ottoq.ottoq_book_stall'              THEN 'space (calendar)'
         WHEN 'public.ottoq_reserve_stall'          THEN 'space (pointer)'
         ELSE 'movement' END AS effect_family
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.proname IN ('ottoq_policy_set', 'ottoq_sim_start_charge_session', 'ottoq_book_stall',
                     'ottoq_reserve_stall', 'ottoq_emit_vehicle_command', 'ottoq_comms_send_command')
 ORDER BY 2 DESC, 3, 1;

-- ══ 3. `0392`'s INSTRUMENT ASKS THE WRONG QUESTION, ONE HOUR OLD ═══════════
--
-- `ottoq_enactment_branches.shield_expected` asks *"should this branch pass the probe ON THIS
-- ROW?"*. Three of the six branches now measured are gated at a different probe point than the row
-- they are recorded on, so that question produces a GAP verdict for correctly-gated behaviour. **An
-- instrument that cries gap three times out of four will be ignored, which is worse than not having
-- it.**
--
-- The right question is two questions:
--   (a) which effect families does this branch touch — policy, power, space, movement?
--   (b) for each, is there a probe on the path, wherever it sits?
--
-- `db/migrations/0394` reshapes the declaration table to ask that: `effect_families text[]` and
-- `gated_downstream_at text`, with the verdict computed from whether every family the branch
-- touches has a gate somewhere. Under it the six branches read:
--
--   orchestrator_agent      policy                    gated at policy_write            OK
--   bay_reconcile           (records a fact)          n/a                              OK
--   itinerary_amended       (twin world progression)  n/a                              OK
--   triage_verdict          (twin world progression)  n/a                              OK
--   reservation_reopt       space + movement + power  power only                       **GAP**
--   gate_intake_no_charge   space + movement          none                             **GAP**
--
-- Two gaps, both on the two effect families that have no chokepoint. **The number to carry is not
-- "170 unshielded enacted decisions" — it is "space and movement have no probe."**
--
-- ══ 4. THE REMEDY, AND IT IS THE CONNECTOR CHASE ASKED ABOUT ═══════════════
--
-- **Put the probe in `ottoq_reserve_stall` and `ottoq_book_stall`, not in each caller.** The
-- codebase already contains two working exemplars of exactly this — `ottoq_policy_set` covers every
-- dial writer, `ottoq_sim_start_charge_session` covers every charge — so this is extending a
-- pattern the engine already trusts, not importing one. One probe inside each chokepoint covers
-- `gate_intake_no_charge`, `reservation_reopt`, and every future writer nobody has thought of,
-- which is the class of fix that stops the census from finding a seventh branch next week.
--
-- **Movement is the harder half and should not be rushed.** `ottoq_emit_vehicle_command` and
-- `ottoq_comms_send_command` carry every verb, not only `proceed_to_stall`, and a probe there gates
-- the downlink rather than the decision — including commands the twin sends to itself. The
-- defensible first step is space only, where the two chokepoints are narrow and the five
-- `stall_assignment` codes already exist to run in them.
--
-- **NOT BUILT HERE, AND THE REASON IS NOT TIMIDITY.** A probe inside `ottoq_reserve_stall` changes
-- what the tick path is allowed to do, on every caller at once — `forces_recert TRUE`, and the kind
-- of change that must be measured on a pair rather than reasoned about. It also cannot be honestly
-- evaluated while `0263` §1 stands: **four of the five `stall_assignment` codes are charge-specific
-- and cannot judge a parking hold**, so dropping them into `ottoq_book_stall` would gate staging
-- with charge rules and refuse nothing while appearing to. **The space chokepoint needs a
-- parking-competent rule before it needs a probe** — and that ordering is the finding, not an
-- excuse. Recorded as **G101**.
--
-- ══ 5. AND THE METHOD NOTE, EARNED THREE TIMES TONIGHT ═════════════════════
--
-- Three claims in a row went wrong the same way, and the third was caught only because the second
-- had just been retracted: `0289` read `offerable` outside its domain; `0392` read
-- `resolved_action_context` as though it recorded what had been checked; this file nearly read a
-- missing `rule_results` as an ungated DCFC rebook. **All three are the same error — a field that
-- answers one question, read as answering a stricter one — and the fix each time was the same
-- single query: follow the effect to where it lands and ask what runs there.**
--
-- So the standing check, stated so it can be applied mechanically: **before calling any path
-- ungated, enumerate the effect families it touches and find the probe on each one's path. A
-- decision row is never evidence of gating in this engine, because this engine gates effects.**
