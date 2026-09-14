-- db/checks/0229
-- THE DIAL CATALOGUE: 92 -> 0, AND THE FOUR THINGS "ZERO" DOES NOT MEAN
--
-- Task #117 closed 2026-09-14. ottoq_policy_set REFUSES any key absent from
-- ottoq_policy_param_catalog -- {"ok":false,"error":"unknown_param"} -- so an
-- uncatalogued dial was not a knob with an unknown range. It was a knob the
-- agent layer physically could not turn. Every one of the 92 can now be turned.
--
-- ===========================================================================
-- A. THE ARC, measured at each step
--
--   file   dials  gap after   what it derived the bounds from
--   -----  -----  ---------   -------------------------------
--   0282-6   ?       92 -> …  behavioural derivation, per-dial probes
--   0289       5        61     five gates
--   0290       3        56     INVERSION -- a negative reverses the meaning
--   0291      18        35*    inline GREATEST/LEAST clamps, copied verbatim
--   0296       0        37     * the 35 was WRONG; the gap view was blind to
--                              five of its own call sites
--   0297      10        27     the comparison itself + 3 clamps 0291 missed
--   0298       8        19     hour domain, [0,1) draw, percentage scale
--   0299       4        15     a CHECK constraint; a clamp on the RESULT
--   0300       3        12     a floor on the compared quantity; domain
--                              inheritance from a sibling producer
--   0303       1        11     G61 -- exclusive bounds, because a clamp cannot
--                              express "> 0" when the clamped value IS 0
--   0304      11         0     the enclosing expression; the WRITER of the
--                              compared value; inversion of a documented order
--
-- ===========================================================================
-- B. WHAT 0304 CORRECTED IN 0228, AND THE LESSON IT COST
--
-- 0228 -- this file's predecessor -- grouped the last twelve A-E and said they
-- were "not waiting on more reading." It was wrong about five, and the reason
-- generalizes: 0228 read each READ SITE and stopped there.
--
--   staging_hold_default_min / staging_hold_max_min
--     0228 quoted `v_clock + make_interval(mins => get(...))` and concluded a
--     negative was "a hold that has already expired." It quoted the line. It
--     did not quote the GREATEST(..., v_clock + interval '1 minute') that
--     ENCLOSES it, which floors the RESULT -- so no value can produce an
--     expired hold and everything at or below 1 is one behaviour. min 1.
--
--   indepot_defer_max_min / _critical
--     0228 said "the comparison that consumes v_budget has not been read."
--     Reading it was not enough either: the predicate is
--     flagged_at <= p_sim_clock - budget, and the bound depends on whether
--     flagged_at can exceed p_sim_clock. That is answered by the WRITER --
--     the same function stamps 'flagged_at', p_sim_clock -- not by the reader.
--     min 0.
--
--   l2_overflow_penalty
--     0228 said "a min/max pair is the wrong shape for it." Half right: the
--     CEILING is the wrong shape (it depends on mutable depot data), but the
--     FLOOR is a scalar bound by inversion. min 0, no max.
--
-- THE LESSON: a bound is not a property of the read site. It is a property of
-- the SMALLEST EXPRESSION WHOSE BEHAVIOUR THE DIAL CAN CHANGE -- which may be
-- the enclosing expression, the comparand, or the writer of the comparand.
-- Reading one line further changed the answer for five of twelve dials.
--
-- AND ONE PROBE THAT WAS ITSELF THE DEFECT CLASS. Checking the indepot premise,
-- I first measured live rows for flagged_at > now() and found 2 of 23 -- an
-- apparent violation of the premise the floor rests on. It is not one:
-- flagged_at is SIM time and now() is WALL time, and the function's own comment
-- at line 351 says so. A data sample against the wrong clock would have
-- refuted a true premise. This is the same class as 0098 (a stale row count),
-- 0137/0139/0216 (a hash over the wrong bytes), 0145/0146 (an unscoped read),
-- and 0296 (a regex that could not see its own call sites): AN INSTRUMENT THAT
-- ANSWERS A SLIGHTLY DIFFERENT QUESTION THAN THE ONE ASKED. It is the single
-- most expensive recurring defect in this build.
--
-- ===========================================================================
-- C. THE FOUR THINGS "ZERO" DOES NOT MEAN
--
-- 1. NOT "every dial is bounded." SEVEN of the 160 catalog rows are min NULL /
--    max NULL -- six from 0304, one from 0303 -- and they admit ANY numeric
--    value. That is deliberate (the catalog's allow-list job is separate from
--    its clamp job, and refusing to catalogue an unbounded dial makes it
--    invisible to the agent layer rather than safe), but it is not a bound.
--    An unbounded dial's safety lives in its caller.
--
-- 2. NOT "the gap view sees everything." FIVE call sites across THREE
--    functions still cannot be parsed, because their param key is a variable
--    rather than a literal -- public.ottoq_intelligence_status (3),
--    public.ottoq_agentic_arming (1), public.ottoq_cron_tick (1). The census
--    view counts them precisely so the zero cannot quietly mean "zero among
--    the ones I could read." 0296 exists because that undercount already
--    happened once.
--
-- 3. NOT "every bound the engine needs can be expressed." G61 has THREE
--    classes and only the first is closed:
--      (a) EXCLUSIVE bounds -- CLOSED by 0303.
--      (b) INVARIANTS BETWEEN TWO DIALS -- OPEN. The catalog holds one min and
--          one max per key. Nothing stops staging_hold_default_min above
--          staging_hold_max_min, or indepot_defer_max_min_critical above
--          indepot_defer_max_min, or (0300) deploy_gate_patience_min above
--          deploy_gate_hard_cap_min. Each is recorded in its own description
--          and enforced by nothing.
--      (c) UNBOUNDED-BY-DESIGN rows -- the seven above.
--
-- 4. NOT "only catalogued keys get written." The catalog gates
--    ottoq_policy_set. It does NOT gate direct INSERTs into
--    ottoq_policy_params, and eight in-database writers still bypass the
--    setter (G62; 0302 closed the one that mattered -- ottoq_cil_tick, the
--    autonomous tuner). A FOREIGN KEY from ottoq_policy_params.param_key to
--    the catalog would close it for every writer including the edge functions
--    and UIs.
--
--    MEASURED TODAY, THAT FK IS NOW UNBLOCKED. It was blocked by six live rows
--    across four uncatalogued keys (contention_wait_cap_ticks x2 depot,
--    timer_backstop_ticks x2 depot, l2_overflow_penalty global,
--    metres_per_plan_unit global). 0303 catalogued the last of those and 0304
--    the other three, so ZERO of the 2,779 live rows now reference a key the
--    catalog does not hold. Completing the catalogue turned out to unblock the
--    constraint that makes it mandatory -- which was not the reason for doing
--    it, and is the more valuable outcome.
--
--    WHAT THE FK WOULD AND WOULD NOT DISTURB, from the eight in-database
--    writers measured 2026-09-14:
--      * five write LITERAL keys (ottoq_ab_pair, ottoq_cert_arm_start,
--        ottoq_determinism_pair, ottoq_determinism_pair_replay,
--        ottoq_mpc_energy_lookahead) -- statically checkable, all catalogued;
--      * twin.ottoq_grid_fixture_create COPIES rows from an existing depot
--        scope (INSERT ... SELECT p.param_key FROM ottoq_policy_params p), so
--        every key it writes already satisfies the FK by construction;
--      * public.ottoq_policy_set is the gated one;
--      * public.ottoq_mpc_lookahead is THE ONE GENUINE RISK: its key comes
--        from jsonb_each_text over caller-supplied p_plans, so it is not
--        statically checkable. Under the FK a plan naming an uncatalogued key
--        would RAISE instead of silently writing. That is the intended
--        behaviour and it is still a behaviour change, so it belongs in its
--        own reviewed window rather than riding along with a catalog file.
--
-- ===========================================================================
-- D. WHAT THE CATALOGUE IS FOR
--
-- The agent layer proposes; the kernel disposes. A tuning agent that can only
-- write keys the catalog admits, only within bounds the catalog clamps, is an
-- agent whose worst case is bounded BY CONSTRUCTION rather than by review.
-- 0302 proved that end to end: ottoq_cil_tick used to INSERT straight into
-- ottoq_policy_params and now goes through ottoq_policy_set, so its own
-- undocumented floor (GREATEST(0.15, ...) on energy_demand_factor_peak, while
-- the catalog floors it at 0.25) can no longer overrule the catalog.
--
-- That is the whole point of the 92. Not tidiness -- a blast radius.
--
-- ===========================================================================
-- E. RE-MEASURE

SELECT status, count(*) AS keys
  FROM public.ottoq_policy_catalog_gap
 GROUP BY status ORDER BY status;

-- the seven unbounded-by-design rows, which must stay deliberate and named:
SELECT param_key, default_value, min_exclusive, max_exclusive,
       left(description, 60) AS description_opens_with
  FROM public.ottoq_policy_param_catalog
 WHERE min_value IS NULL AND max_value IS NULL
 ORDER BY param_key;

-- the residual the key scanner cannot parse, which must stay explained
-- rather than merely small:
SELECT * FROM public.ottoq_policy_read_site_census WHERE n_unparsed > 0 ORDER BY fn;

-- no live value may sit outside its catalogued bound, inclusive or exclusive:
SELECT pp.param_key, pp.scope_id, pp.param_value,
       c.min_value, c.max_value, c.min_exclusive, c.max_exclusive
  FROM public.ottoq_policy_params pp
  JOIN public.ottoq_policy_param_catalog c USING (param_key)
 WHERE (c.min_value     IS NOT NULL AND pp.param_value <  c.min_value)
    OR (c.max_value     IS NOT NULL AND pp.param_value >  c.max_value)
    OR (c.min_exclusive IS NOT NULL AND pp.param_value <= c.min_exclusive)
    OR (c.max_exclusive IS NOT NULL AND pp.param_value >= c.max_exclusive);

-- what still blocks the G62 foreign key: live param_key values with no
-- catalog row. Every one of these is a key some writer bypassing
-- ottoq_policy_set has inserted directly.
SELECT pp.param_key, count(*) AS live_rows,
       string_agg(DISTINCT pp.updated_by, ', ') AS written_by
  FROM public.ottoq_policy_params pp
 WHERE NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog c
                    WHERE c.param_key = pp.param_key)
 GROUP BY pp.param_key ORDER BY pp.param_key;
