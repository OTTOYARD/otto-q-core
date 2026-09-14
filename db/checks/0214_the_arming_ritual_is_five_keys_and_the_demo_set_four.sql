-- 0214  THE ARMING RITUAL IS FIVE KEYS AND THE DEMO SET FOUR
--
-- Measured 2026-09-14. Read-only. Every section below re-runs.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS IS
--
-- db/checks/0213 recorded the rule: zero activations is evidence of nothing
-- until you know why, and named five cases. Case (b) is "a caller exists but
-- is forbidden or gated" -- the component is not broken, it is switched off.
--
-- This file is case (b), found by applying the rule to the largest open
-- defect. G49 (db/checks/0212 sec.8) measured that 23 of 23 CP-SAT
-- `noop_no_candidate` proposals named a stall that was booked in the same run
-- for a DIFFERENT vehicle, 18 of them booked BEFORE CP-SAT proposed. The
-- reading at the time was "the frame was stale in TIME."
--
-- That reading was incomplete. The frame was also blind in CONTENT, and the
-- blindness is the larger half, is measurable, and is one missing table row.
--
-- ---------------------------------------------------------------------------
-- THE APPARATUS THAT IS BUILT, AND DARK
--
-- Migration 0265 added to public.ottoq_build_decision_frame, per stall, the
-- facts the proposal selector itself pre-filters on -- the charger id, the
-- reservation and whether it is live against the SIM clock, the charger state
-- and heartbeat freshness, and one vehicle-blind `offerable` verdict -- plus
-- per vehicle its live reservation and whether it holds a live booking, plus a
-- top-level `selector` block naming the clock and the heartbeat window.
--
-- The consumer is built too, and was verified by reading it, not by counting
-- grep hits (the first count was misleading: the candidate filter reaches
-- stall_is_free THROUGH stall_block_reason, so a search for direct callers
-- finds only the diagnostic counter and suggests, wrongly, that nothing
-- filters on it):
--
--   proposer/forward_proposer.py:244  stall_is_free()       honours `offerable`
--                                     when the key is present; falls back to
--                                     the pre-0265 status/occupancy test when
--                                     it is absent.
--   proposer/forward_proposer.py:267  stall_block_reason()  calls stall_is_free
--                                     and attributes the refusal.
--   proposer/forward_proposer.py:683  frame_to_scenario()   calls
--                                     stall_block_reason per stall and
--                                     `continue`s on any reason -- the comment
--                                     on that branch reads "never offered to
--                                     the solver either way."
--
-- So: producer, consumer, candidate filter, graceful fallback, and a fire-record
-- contract stamp (frame_facts_version, feature-detected off the frame's own
-- `selector` block so a bridge cannot claim a contract it did not read) are all
-- built, tested and shipped.
--
-- The gate that enables them is the run-scoped policy key
-- `proposer_frame_facts`, catalogued by 0265 with default 0.
--
-- ---------------------------------------------------------------------------
-- SECTION 1 -- THE KEY HAS NEVER BEEN SET, AT ANY SCOPE, EVER
--
-- Expect zero rows. It is in the catalog and in no scope.
SELECT scope_type, scope_id::text, param_value, updated_by, updated_at
  FROM public.ottoq_policy_params
 WHERE param_key = 'proposer_frame_facts';

-- And it IS catalogued, so this is a key nobody set, not a key nobody declared
-- (contrast 0262, where the key existed in code and NOT in the catalog and
-- ottoq_policy_set answered {"ok":false,"error":"unknown_param"}).
SELECT param_key, default_value, min_value, max_value
  FROM public.ottoq_policy_param_catalog
 WHERE param_key = 'proposer_frame_facts';

-- ---------------------------------------------------------------------------
-- SECTION 2 -- THE RITUAL, AS THE ONLY TWO RUNS THAT EVER FIRED CP-SAT GOT IT
--
-- Both runs were armed by hand, by `d3_demo`, with FOUR keys each:
--
--   cuopt_first_refusal_max_defers = 1   the starvation bound / off switch
--   cuopt_propose_enabled          = 0   cuOpt quiesced
--   orchestrator_agent_enabled     = 0
--   proposer_hold_enabled          = 1   the one-tick right of first refusal
--
-- and NEITHER got proposer_frame_facts. Four of five, twice, by hand.
SELECT pp.scope_id::text AS run, pp.param_key, pp.param_value, pp.updated_by
  FROM public.ottoq_policy_params pp
 WHERE pp.scope_type = 'run'
   AND pp.scope_id IN (SELECT DISTINCT f.sim_run_id
                         FROM public.ottoq_proposer_fire_log f
                        WHERE f.declared_source IN ('cpsat','forward_lex'))
 ORDER BY pp.scope_id, pp.param_key;

-- ---------------------------------------------------------------------------
-- SECTION 3 -- SO EVERY CP-SAT FIRE READ A PRE-0265 FRAME
--
-- ottoq_policy_get resolves run -> depot -> global -> caller default. With no
-- row at any tier the frame builder's `g.facts` is 0 and the frame is, in the
-- 0265 catalog's own words, "byte-identical to its pre-0265 output."
SELECT f.sim_run_id, f.tick_seq, f.declared_source, f.status, f.n_submitted,
       public.ottoq_policy_get(f.sim_run_id, 'proposer_frame_facts', 0) AS facts_in_force,
       f.fire->>'frame_facts_version' AS bridge_saw_contract
  FROM public.ottoq_proposer_fire_log f
 WHERE f.declared_source IN ('cpsat','forward_lex')
 ORDER BY f.fired_at;
-- `bridge_saw_contract` is NULL on every row: the bridge asked the frame which
-- contract it was built under and the frame did not say, because the gate was
-- off. The blindness is recorded in the ledger as a null, which is exactly
-- what that field was added for.

-- ---------------------------------------------------------------------------
-- WHAT THIS DOES AND DOES NOT EXPLAIN
--
-- DOES: with the gate off, a stall reserved for another vehicle, or sitting on
-- a faulted or silent charger, carries none of the three facts that would have
-- excluded it, and `stall_is_free` falls back to status-and-occupancy -- which
-- a reserved-but-empty stall passes. CP-SAT was therefore OFFERED points the
-- door would refuse, and named them. That is the 23/23 shape, at the source.
--
-- DOES NOT: it does not make the TIME staleness disappear. Even with every
-- fact present, a frame read at T and submitted at T+delta can be overtaken --
-- 5 of the 23 were booked between the read and the proposal, and no content
-- fix reaches those. Frame-staleness detection remains its own item. The
-- honest split is: the blindness is the larger half and is one row; the
-- staleness is the residual and needs an instrument.
--
-- NOT CLAIMED: that turning the key on would have made all 23 win. It would
-- have stopped them being PROPOSED. An abstention naming a real scarcity and a
-- proposal that is discarded at the door are different ledger facts, and only
-- the first is honest.
--
-- ---------------------------------------------------------------------------
-- WHY IT WAS MISSED, WHICH IS THE FINDING WORTH KEEPING
--
-- Arming a run for the agentic layer is a FIVE-KEY HAND RITUAL with no
-- function, no script and no check behind it. Nothing in the repository arms a
-- proposer run; `grep -rn policy_set --include=*.py --include=*.sh
-- --include=*.yml` returns nothing. The keys were set in a session, from
-- memory, and a run that is armed four ways out of five looks -- to the fire
-- log, to the census, to ottoq_intelligence_status() and to a reader -- exactly
-- like a run that is armed.
--
-- That is 0277's defect one rung further out. 0277 fixed a census that could
-- not tell "has proposed" from "has never existed." This is a system that
-- cannot tell "armed" from "armed except for the key that matters."
--
-- The fix is not to set the row. Setting the row by hand is what produced this.
-- The fix is that arming becomes one call that cannot be done partially, and
-- partial arming becomes a state the system reports -- migration 0278.
--
-- ---------------------------------------------------------------------------
-- SECTION 4 -- A THIRD KEY WITH 0262'S ORIGINAL BUG, STILL OPEN
--
-- Noticed while pinning the key set; recorded here, deliberately NOT fixed in
-- 0278, because it belongs to the A/B rig and not to the agentic arm, and
-- bundling a policy-dimension key into a proposer-dimension arm is the exact
-- conflation db/checks/0146 warns about.
--
-- `proposer_seat` (0261: which assignment policy owns the in-tick fallback --
-- seat 0 is otto_q, non-zero delegates to ottoq_l2_propose_stall_seat) is read
-- by four live functions and is NOT in ottoq_policy_param_catalog. So the
-- setter refuses it:
--
--   SELECT ottoq_policy_set('run', <run>, 'proposer_seat', 1, 'x');
--   -> {"ok": false, "error": "unknown_param", "param": "proposer_seat"}
--
-- ...while 12 rows for it exist in ottoq_policy_params, written around the
-- setter. That is 0262's finding exactly, on a third key. The setter returns
-- ok:false rather than raising, so a caller that does not read the receipt is
-- told nothing.
SELECT (SELECT count(*) FROM public.ottoq_policy_params WHERE param_key='proposer_seat') AS rows_written,
       (SELECT count(*) FROM public.ottoq_policy_param_catalog WHERE param_key='proposer_seat') AS catalog_rows,
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname IN ('public','twin') AND p.prosrc LIKE '%proposer_seat%') AS live_readers;

-- ---------------------------------------------------------------------------
-- SECTION 5 -- THE GUARD SCRIPT CLEARED THIS FILE'S OWN MIGRATION, WRONGLY
--
-- Not a database finding; recorded here because it was found while applying
-- 0278 and it would have caused the exact drift it exists to prevent.
--
-- scripts/exec-digest.py --check refuses to let a migration be condensed when
-- comment-only lines live inside a body the DATABASE WILL STORE -- strip them
-- and the stored function differs from the committed file, which is the
-- file-vs-database drift G18 exists to prevent and scripts/check-drift.sql
-- would be right to flag. Its docstring calls this "the trap this tool refuses
-- to walk into."
--
-- It walked into it. The classifier was:
--
--   STORED_TAGS = ('$function$', '$procedure$', '$body$')
--
-- -- a naming CONVENTION, not a rule Postgres enforces. `CREATE OR REPLACE
-- FUNCTION f() ... AS $$ ... $$` stores its body exactly as `$function$` does,
-- but every `$$` region was exempt because DO blocks use `$$` too. So a
-- migration whose function bodies are quoted `$$` got a clean bill of health
-- while carrying stored comments.
--
-- 0278 has 12 such lines across two functions and the tool said
-- "safe to condense".
--
-- FIXED in the same commit: a `$$` region is now classified by WHAT OPENS IT --
-- the nearest preceding statement keyword. CREATE ... FUNCTION/PROCEDURE means
-- stored; DO means exempt; unknown means stored, because the failure that
-- matters is a false CLEAR, not a false alarm.
--
-- The fix was regression-tested against all 277 migrations rather than argued:
--
--   verdicts changed:  2  (0030_geometry_guard_db.sql, 0278)
--   verdicts same:   275
--   digest hashes:   277 of 277 bit-identical  (the condensing path itself is
--                    untouched; only the --check classifier moved)
--
-- Both changes are true positives. 0030 declares
-- public.ottoq_check_layout_geometry with a `$$` body carrying 52 comment-only
-- lines; the old tool would have cleared it to be condensed.
