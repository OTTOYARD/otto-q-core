-- ---------------------------------------------------------------------------
-- 0201 — G23'S OBSERVED PURGE PASS: 7,300,205 ROWS, EXACTLY AS PREDICTED,
-- AND THE NINE LEGS ARE GONE.
--
-- Run 2026-09-13 14:16-14:25 UTC (9:16-9:25 AM CT), immediately after 0267
-- unblocked ottoq_retention_purge_runs. This is the "ONE observed pass"
-- db/checks/0196 makes the precondition for round 42, and the first real test
-- of 0266's split. NOT the nightly cron job -- see db/checks/0200 for why that
-- one could not have served.
-- ---------------------------------------------------------------------------

-- 1. THE RESULT, TABLE BY TABLE. Every figure matches the pre-flight prediction
--    in db/checks/0200 §3 EXACTLY -- not approximately, exactly:
--
--      table                       before      after     deleted   predicted
--      ottoq_rule_evaluations    2,614,022  1,356,053  1,257,969  1,257,969
--      ottoq_bay_binding_witness 1,666,977    172,531  1,494,446  1,494,446
--      ottoq_variability_cards   1,612,929    169,373  1,443,556  1,443,556
--      ottoq_events              1,712,384    617,197  1,095,187  1,095,187
--      ottoq_stall_bookings      1,022,356    106,539    915,817    915,817
--      ottoq_itinerary_legs        678,128     86,257    591,871    591,871
--      ottoq_comms_messages        606,690     89,331    517,359    517,359
--                                                      ---------
--                                                      7,300,205
--
--    939 doomed runs, all stamped purged_at (0251: from that moment their KPIs
--    are not whole and ottoq_kpi_five must say so). ottoq_sim_runs itself went
--    1,070 -> 1,070: the purge deletes a doomed run's CHILD rows and never the
--    run header, so all 892 cert pairs carrying endst remain readable and
--    neither instrument lost a single pair.

-- 2. THE MEASUREMENT THE WHOLE THING WAS FOR.
SELECT count(*) AS flagship_foreign_live_legs
  FROM public.ottoq_itinerary_legs l
  JOIN public.vehicles v ON v.id = l.vehicle_id
 WHERE v.home_depot_id = '11111111-1111-1111-1111-111111111111'::uuid
   AND l.status IN ('planned','active') AND l.sim_run_id IS NOT NULL;
-- BEFORE: 9   (all owned by doomed runs, all from ONE run -- run 9291ec6d's
--              pre-janitor backlog, the same nine db/checks/0193 §2 named)
-- AFTER:  0
--
-- endst.legs.fgn at the flagship depot is therefore now empty where it held nine
-- rows. THE NEXT PAIR WILL SEE A DIFFERENT FOREIGN HALF. That is the prediction
-- round 42 judges, and it is exactly what 0266 built ottoq_cert_residue to
-- report: `sections_moved` should name `legs`, for a reason that is true.

-- 3. WHAT DID NOT MOVE, AND WHY THAT IS NOT YET THE PROOF.
--    Both instruments read validation_notes off ottoq_sim_runs, which the purge
--    never touches, so their canons are stored hashes and CANNOT move. Measured
--    after the pass (and after 0268 restored the floor): nine columns, nine
--    green, every canon and every streak byte-identical to the 13:58 reading.
--
--    THAT IS NOT EVIDENCE THE SPLIT WORKS. It is evidence the record survived.
--    The real question -- does the engine still REPRODUCE those canons from a
--    world 7.3 million rows lighter -- is answered only by running a new pair.
--    Stating this plainly because "the matrix is still green after the purge"
--    is exactly the sentence that would be quoted as a result, and it is a
--    tautology: a stored hash does not change when you delete other runs' rows.

-- 4. TWO OPERATIONAL FINDINGS FROM RUNNING IT.
--
--    (a) THE ACCOUNTING UNDER-REPORTS AN INTERRUPTED CALL.
SELECT pass_deleted FROM public.ottoq_retention_state WHERE table_name = 'engine_rows';
--    MEASURED 5,565,201 against 7,300,205 actually deleted -- short by
--    1,735,004. ottoq_retention_purge_runs updates ottoq_retention_state AFTER
--    its loops, so a call that ends any other way (here: the MCP client timing
--    out at 60 s while the procedure kept running server-side) commits every
--    row deletion and none of the accounting. The deletions are correct; the
--    counter is not a reliable total. Anyone quoting "rows purged" should count
--    the tables, not read this column -- or the update should move inside the
--    per-batch COMMIT, which is the real fix and is not made here.
--
--    (b) THE PROCEDURE OUTLIVES ITS CLIENT. A CALL with a 600 s budget kept
--    deleting after the 60 s client timeout -- confirmed by pg_stat_activity
--    showing it still running and the counts still falling. Useful, and a
--    hazard: an operator who re-issues a "failed" call can end up with two
--    purges racing. The advisory lock (pg_advisory_lock on
--    hashtext('ottoq_retention_purge')) is what makes that safe, and it is the
--    reason the second call in such a pair simply waits rather than interleaving.
--
--    (c) AND THE SPACE IS NOT BACK YET. pg_total_relation_size after the pass:
--        ottoq_events 3429 MB, ottoq_rule_evaluations 5657 MB -- unchanged,
--        because DELETE leaves dead tuples. Database 17 GB. Reclaiming it needs
--        VACUUM (for reuse) and REINDEX (for index bloat); G23's third step.
--        Until then "7.3 million rows deleted" is true and "the database got
--        smaller" is not.

-- ---------------------------------------------------------------------------
-- THE ORDER 0196 SET, AND WHERE IT NOW STANDS
--   0266 applied and green ....................... done 13:56 UTC
--   0267 (the blocker 0196 did not know about) ... done 14:14 UTC
--   0268 (the floor 0267 moved) .................. done 14:29 UTC
--   ONE observed purge pass ...................... done 14:25 UTC, this file
--   round 42 ..................................... next; it judges 0196 P1-P3
-- ---------------------------------------------------------------------------
