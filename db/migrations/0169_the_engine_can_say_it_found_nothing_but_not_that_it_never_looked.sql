-- 0169  The engine can say it found nothing. It cannot say it never looked.
--       ENGINE CHANGE. forces_recert = TRUE. Its own certification round.
--
--       WRITTEN, NOT APPLIED. Do not apply while a certification round is in
--       flight. See "How to apply this" at the bottom - it has a falsifiable
--       prediction attached and applying it without checking that prediction
--       wastes the only chance to check it.
--
--
-- THE GAP, IN THE ENGINE'S OWN VOCABULARY
-- ----------------------------------------
-- ottoq_decisions.outcome_status today carries: enacted, noop_no_candidate,
-- overridden_to_default. On one 24-tick flagship run: 2,444 enacted, 319
-- noop_no_candidate, 2 overridden_to_default.
--
-- 'noop_no_candidate' means "I considered this asset and had nothing for it."
-- There is NO status meaning "I never considered this asset." And the engine
-- routinely does not consider assets, because three loops in ottoq_decide_tick
-- carry a bare per-tick work cap:
--
--   line 453   LIMIT 40   release loop   (charge_complete_holding)
--   line 794   LIMIT 20   SEATING loop   (the one that puts a vehicle in a stall)
--   line 937   LIMIT 40   service loop   (staged_awaiting_service)
--
-- A vehicle ranked 21st in the seating loop produces no row at all. Afterwards
-- it is indistinguishable from a vehicle that was considered and declined.
--
-- This is the distinction CLAUDE.md rule 6 demands of cuOpt - the ledger exists
-- "precisely to make 'never invoked' distinguishable from 'invoked N times,
-- abstained M'" - and what OTTO-Defense's brief means by "every directive
-- carries a reason code." The seating loop, which decides whether an asset gets
-- served at all, fails both.
--
-- MEASURED FIRST (db/checks/0078 §6): the seating cap runs at 8.1-10.3 vehicles
-- per tick against its budget of 20. It is SLACK on nearly every tick and is NOT
-- what strands assets. This migration is therefore NOT a fix for the stranding
-- in 0077 §5 - that cause is still unidentified - and must not be sold as one.
--
-- It is worth building anyway, for the reason 0078 §6 demonstrated on itself:
-- answering "does the cap bind?" took THREE queries, the first two were wrong,
-- and the third still ended qualified - purely because a booking does not record
-- which loop seated it and a tick does not record that it was oversubscribed.
-- That is the difference between measuring the engine and inferring it.
--
--
-- WHAT THIS CHANGES
-- ------------------
-- 1. The seating cap becomes a policy parameter, resolved by ottoq_policy_get
--    (run -> depot -> global -> literal default) at its CURRENT value of 20. At
--    the default this is a zero-behaviour change, which is precisely what makes
--    it safe to certify against the round-8 canons.
--
-- 2. The seating loop's LIMIT is replaced by a rank computed over the whole
--    qualifying set, so the loop can SEE the candidates the budget excludes.
--    Candidates past the budget are recorded as
--    outcome_status = 'deferred_tick_budget' and skipped with a pure CONTINUE.
--
--    The window function fresh_waiting_lane at line 785 is unaffected: window
--    functions are already evaluated over the whole qualifying set before LIMIT
--    (the code says so at line 782). Removing the LIMIT does not change what any
--    surviving candidate sees. That is why this is behaviour-preserving.
--
-- 3. The other two caps (453, 937) are deliberately NOT touched here. One loop,
--    one migration, one certification round. If the seating recording proves out,
--    the same shape extends to them.
--
--
-- THE PREDICTION THIS MIGRATION MUST SATISFY
-- -------------------------------------------
-- Recording something that did not happen must not change what happens. So,
-- diffed against db/canons/round8.md, on EVERY column:
--
--     h_dec   MUST move      (new rows in ottoq_decisions, which h_dec hashes)
--     h_cmd   MUST NOT move  (no command is issued for a deferred vehicle)
--     h_bkg   MUST NOT move  (no booking changes - the assignments are identical)
--     h_nrg   MUST NOT move  (no energy command changes)
--
-- IF h_bkg MOVES, THIS MIGRATION CHANGED BEHAVIOUR AND IS WRONG. It is not a new
-- canon to be re-baselined; it is a defect to be reverted and re-diagnosed. The
-- most likely cause would be the removed LIMIT altering which candidates the
-- loop body reaches before its own CONTINUE guards.
--
-- This prediction is checkable only because round 8 committed all six canons to
-- db/canons/round8.md. Before that file existed it would have been checkable on
-- one column out of six.

-- ------------------------------------------------------- 1. the cap as policy

INSERT INTO public.ottoq_policy_param_catalog (param_key, description, default_value)
VALUES ('decide_seat_batch',
        'Max vehicles the seating loop in ottoq_decide_tick will consider per tick. Candidates ranked past this are recorded as deferred_tick_budget, not silently dropped. Default 20 = the literal it replaces (0169).',
        20)
ON CONFLICT (param_key) DO UPDATE SET description = EXCLUDED.description;

-- ------------------------------------------- 2. rank the whole qualifying set

DO $patch$
DECLARE v_src text; v_before text; v_after text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE p.prokind='f' AND n.nspname='public' AND p.proname='ottoq_decide_tick';

  -- (a) add the rank and the qualifying count; drop the LIMIT.
  --     Anchored on the ORDER BY + LIMIT block, which is unique to this loop.
  v_before :=
    '          FROM ranked rk'                              || chr(10) ||
    '         ORDER BY rk.eff_rank DESC,'                   || chr(10) ||
    '                  rk.is_resume DESC,'                  || chr(10) ||
    '                  rk.fits_window DESC NULLS LAST,'     || chr(10) ||
    '                  rk.minutes_to_deploy ASC NULLS LAST,'|| chr(10) ||
    '                  rk.open_must_do_min ASC NULLS LAST,' || chr(10) ||
    '                  rk.vehicle_id'                       || chr(10) ||
    '         LIMIT 20';
  v_n := (length(v_src) - length(replace(v_src, v_before, ''))) / length(v_before);
  IF v_n <> 1 THEN RAISE EXCEPTION '0169a: seating ORDER BY/LIMIT anchor must occur exactly once, found %', v_n; END IF;

  v_after :=
    '               -- 0169: rank over the WHOLE qualifying set so the loop can see the'   || chr(10) ||
    '               -- candidates the tick budget excludes, instead of dropping them'      || chr(10) ||
    '               -- before they are ever named. Same ordering as the LIMIT it replaces.'|| chr(10) ||
    '               , row_number() OVER (ORDER BY rk.eff_rank DESC,'                       || chr(10) ||
    '                                             rk.is_resume DESC,'                      || chr(10) ||
    '                                             rk.fits_window DESC NULLS LAST,'         || chr(10) ||
    '                                             rk.minutes_to_deploy ASC NULLS LAST,'    || chr(10) ||
    '                                             rk.open_must_do_min ASC NULLS LAST,'     || chr(10) ||
    '                                             rk.vehicle_id) AS seat_rank'             || chr(10) ||
    '               , count(*) OVER () AS seat_qualified'                                  || chr(10) ||
    '          FROM ranked rk'                              || chr(10) ||
    '         ORDER BY rk.eff_rank DESC,'                   || chr(10) ||
    '                  rk.is_resume DESC,'                  || chr(10) ||
    '                  rk.fits_window DESC NULLS LAST,'     || chr(10) ||
    '                  rk.minutes_to_deploy ASC NULLS LAST,'|| chr(10) ||
    '                  rk.open_must_do_min ASC NULLS LAST,' || chr(10) ||
    '                  rk.vehicle_id';
  v_src := replace(v_src, v_before, v_after);

  -- (b) record and skip past the budget. Must be the FIRST statement in the loop
  --     body, before any other CONTINUE guard, or the record is conditional on
  --     guards that have nothing to do with the budget.
  v_before :=
    '      LOOP'                                                                                        || chr(10) ||
    '        IF v_need.stall_type = ''wash_bay''    AND COALESCE(v_wash_open,0) <= 0 THEN CONTINUE; END IF;';
  v_n := (length(v_src) - length(replace(v_src, v_before, ''))) / length(v_before);
  IF v_n <> 1 THEN RAISE EXCEPTION '0169b: seating LOOP head anchor must occur exactly once, found %', v_n; END IF;

  v_after :=
    '      LOOP'                                                                                        || chr(10) ||
    '        -- 0169: the tick budget, recorded rather than silent. A vehicle past the'                 || chr(10) ||
    '        -- budget was never considered; noop_no_candidate would be a lie about it.'                || chr(10) ||
    '        IF v_need.seat_rank > public.ottoq_policy_get(p_sim_run_id, ''decide_seat_batch'', 20) THEN' || chr(10) ||
    '          INSERT INTO ottoq_decisions (sim_run_id,tick_seq,sim_clock,depot_id,snapshot_id,action_context,entity_type,entity_id,context_frame,proposed_action,enacted_action,outcome_status,propose_latency_ms,total_latency_ms)' || chr(10) ||
    '          VALUES (p_sim_run_id,v_tick,v_clock,v_depot,v_snapshot_id,''stall_assignment'',''vehicle'',v_need.vehicle_id,' || chr(10) ||
    '                  jsonb_build_object(''seat_rank'',v_need.seat_rank,''seat_qualified'',v_need.seat_qualified,' || chr(10) ||
    '                                     ''seat_batch'',public.ottoq_policy_get(p_sim_run_id,''decide_seat_batch'',20),' || chr(10) ||
    '                                     ''stall_type'',v_need.stall_type,''lane'',v_need.lane),' || chr(10) ||
    '                  ''{}''::jsonb,''{}''::jsonb,''deferred_tick_budget'',0,0);' || chr(10) ||
    '          CONTINUE;' || chr(10) ||
    '        END IF;' || chr(10) ||
    '        IF v_need.stall_type = ''wash_bay''    AND COALESCE(v_wash_open,0) <= 0 THEN CONTINUE; END IF;';
  v_src := replace(v_src, v_before, v_after);

  EXECUTE v_src;
END $patch$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_engine_can_say_it_found_nothing_but_not_that_it_never_looked', true,
        'ENGINE. The seating loop''s LIMIT 20 becomes the policy param decide_seat_batch at its current value, and candidates past the budget are recorded as ottoq_decisions rows with outcome_status deferred_tick_budget instead of being dropped unnamed. Behaviour-preserving at the default: h_dec must move on every column, h_cmd/h_bkg/h_nrg must not. A moved h_bkg is a defect, not a new canon.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

-- ------------------------------------------------------- How to apply this
--
-- 1. Only when no certification round is in flight and the matrix is 6 of 6
--    green, so there is a clean baseline to diff against.
-- 2. Verify ottoq_policy_param_catalog's real column names before applying -
--    the INSERT above was written from the table's role, not from a read of its
--    definition. If they differ, fix the INSERT; do not drop the catalog row,
--    because an unregistered param is exactly the magic number this replaces.
-- 3. Apply, then run ONE pair on the grid fixture (twin.ottoq_grid_smoke, ~20 s)
--    before spending a flagship pair. It will catch a syntax or NULL error for
--    the price of nothing.
-- 4. Then one flagship pair per column, and diff every canon against
--    db/canons/round8.md under the prediction above.
-- 5. Expect deferred_tick_budget rows to be RARE - 0078 §6 measured the cap
--    slack on nearly every tick. Zero rows across a whole round is a legitimate
--    outcome and means the cap never bound; it does NOT mean the recording is
--    broken. Prove the recording works by temporarily setting decide_seat_batch
--    to 2 on a grid run and confirming rows appear. A check that cannot fail is
--    not a check, and that is the check.
