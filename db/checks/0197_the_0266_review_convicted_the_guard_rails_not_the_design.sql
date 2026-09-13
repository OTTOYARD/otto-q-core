-- 0197  THE 0266 REVIEW: THE DESIGN SURVIVED, THE GUARD RAILS DID NOT
--
-- Six hostile lenses over migration 0266 (G46 + G48), 2026-09-13, each with
-- read-only database access and instructed to check claims against the live
-- database rather than trust the file's comments. Two returned before this file
-- was written; both verdicts "sound_with_changes", both recommending DO NOT APPLY
-- AS WRITTEN. Nothing was applied. This file records what they established,
-- because a third of it corrects things the migration itself asserted.
--
-- THE HEADLINE, and it is the useful shape of the result: THE DESIGN IS RIGHT AND
-- THE ASSERTIONS WERE THEATRE. Both lenses independently re-ran the two new
-- function bodies read-only and reproduced 0196's predictions exactly -- P1 (all
-- seven flagship columns reach consecutive_passes = pairs_seen, both grid columns
-- stay 3/3/green) and P2 (the residue instrument names `legs` on exactly the
-- seven flagship columns). The correctness lens went further and proved the copy
-- mechanically: excise the two intended regions from the file's body and the
-- single c_endst line from the live prosrc, and both sides are 113 lines /
-- 5,844 chars / md5 fa410d95b18f2197e5fb1178cba6b4a4. No predicate in `marked`
-- was dropped, weakened or reordered.
--
-- So the split is sound. What was not sound was everything written to prove it.

-- ---------------------------------------------------------------------------
-- 1. A9 WAS A TAUTOLOGY -- the file's ONLY defence of its central G25/G28 claim.
--    It asserted  (arm_a.endst = arm_b.endst) <> (own_eq AND fgn_eq).
--    Every post-floor pair has arm_a.endst = arm_b.endst, so the left side is
--    constantly TRUE; whole-object equality trivially implies both digests
--    equal, so the right side is constantly TRUE. The reviewer then replaced the
--    ENTIRE right-hand side with a constant compared to itself -- reading nothing
--    from the pair at all -- and it still returned zero.
-- ---------------------------------------------------------------------------
SELECT count(*) AS post_floor_pairs,
       count(*) FILTER (WHERE (j->'arm_a'->'endst') IS DISTINCT FROM (j->'arm_b'->'endst'))
         AS endst_ever_unequal
  FROM (SELECT DISTINCT ON (r.depot_id, r.started_at) (r.validation_notes::jsonb) j
          FROM public.ottoq_sim_runs r
         WHERE r.run_by='cert_harness' AND r.validation_notes IS NOT NULL
           AND r.validation_status IS NOT NULL
           AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object'
           AND r.started_at >= public.ottoq_cert_recert_floor()
         ORDER BY r.depot_id, r.started_at, r.sim_run_id) q;
-- MEASURED: 30 pairs, endst_ever_unequal = 0. The left side never varies, so the
-- biconditional never fires. A9 could not fail.
--
-- AND IT NEVER CALLED EITHER FUNCTION. A9 retyped both digest expressions inline,
-- so it tested its own copy of the design and not the body being installed -- a
-- typo in the shipped c_endst was invisible to it.
--
-- REPLACED BY: a SHAPE assertion (endst must be exactly the seven keys, with
-- exactly {vis,fgn} under the four sections), which is falsifiable on today's
-- data and fires the day the fingerprint grows a key the split would drop; plus
-- A9b, which takes canon_endst from ottoq_cert_matrix and canon_fgn from
-- ottoq_cert_residue and checks them against an INDEPENDENT recomputation, so the
-- shipped bodies are what is tested.

-- ---------------------------------------------------------------------------
-- 2. A2 WAS NOT THE POSITIVE CONTROL IT ADVERTISED. Its own comment named the
--    defect -- "a misspelled path still produces a valid md5 of an object full of
--    JSON nulls" -- and then guarded ONLY the case where all seven paths are
--    wrong at once. One wrong path yields six real values and one JSON null,
--    whose digest is neither NULL nor the all-null constant.
-- ---------------------------------------------------------------------------
WITH p AS (
  SELECT DISTINCT ON (r.depot_id, r.started_at) (r.validation_notes::jsonb)->'arm_a'->'endst' e
    FROM public.ottoq_sim_runs r
   WHERE r.run_by='cert_harness' AND r.validation_notes IS NOT NULL
     AND r.validation_status IS NOT NULL
     AND jsonb_typeof((r.validation_notes::jsonb)->'arm_a')='object'
     AND r.started_at >= public.ottoq_cert_recert_floor()
   ORDER BY r.depot_id, r.started_at, r.sim_run_id)
SELECT count(*) AS pairs,
       --: the OLD A2: does a one-path typo ever hit the all-null constant?
       count(*) FILTER (WHERE md5(jsonb_build_object(
           'visit_needs', e->'visit_needs'->'viss',   -- the typo
           'bookings', e->'bookings'->'vis', 'legs', e->'legs'->'vis',
           'dispatches', e->'dispatches'->'vis', 'chargers', e->'chargers',
           'calibration', e->'calibration', 'world', e->'world')::text)
         = md5(jsonb_build_object('visit_needs', NULL::jsonb,'bookings', NULL::jsonb,
             'legs', NULL::jsonb,'dispatches', NULL::jsonb,'chargers', NULL::jsonb,
             'calibration', NULL::jsonb,'world', NULL::jsonb)::text)) AS old_a2_would_catch,
       --: the NEW A2: does any of the seven paths extract nothing?
       count(*) FILTER (WHERE (e->'visit_needs'->'viss') IS NULL) AS new_a2_would_catch
  FROM p;
-- MEASURED: 30 pairs, old_a2_would_catch = 0, new_a2_would_catch = 30.
-- The old test caught nothing; the new one catches every pair. REPLACED BY the
-- per-path non-NULL check, with the all-null digest kept as a second net.

-- ---------------------------------------------------------------------------
-- 3. A3 AND A4 COULD NOT TELL THE SPLIT FROM DELETING endst ALTOGETHER.
--    A3 asserted the grid columns were still 3/3 green -- but they were ALREADY
--    at their ceiling before this migration, so no weakening of any kind could
--    move them upward. A4 asserted greenness, which is the outcome the rewrite
--    was built to produce. The reviewer simulated the maximal weakening (the
--    whole endst conjunct deleted from `marked`, no split at all) and got
--    a3_would_fire = 0, a4_would_fire = 0.
--
--    Worse for A4: 0196 M1 measured that all twelve NON-endst atoms already match
--    on every post-floor pair, so none of them is load-bearing on today's data --
--    meaning a conjunct accidentally deleted during the rewrite would also have
--    left A4 green, and nothing in the file pinned the post-image body.
--
--    REPLACED BY: A3 now computes the OLD digest alongside the new one, runs the
--    same streak logic over both, and asserts the difference set EXACTLY -- seven
--    flagship columns improved, zero non-flagship improved, zero regressed. Under
--    the maximal weakening the grid columns would also improve and it fires.
--    A4 now pins all THIRTEEN canon conjuncts by substring against the POST-IMAGE
--    prosrc, which is the only way a dropped conjunct is visible at all.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 4. THE BLOCKER THE CORRECTNESS LENS FOUND, and the one that would have cost
--    most: THE FILE HAD NO md5 GUARD AND NO SNAPSHOT FOR THE ONE FUNCTION IT
--    REPLACES. scripts/APPLYING.md step 2 makes both mandatory, and 0261, 0265
--    and db/migrations/0001_EXAMPLE_template.sql all carry both. 0266 had a bare
--    SELECT whose result apply_migration discards, with the expected digest
--    living only in a hand-written comment -- and A8 pinned md5 on the two
--    functions the file must NOT touch while leaving the one it DOES touch
--    unpinned, and A8 runs AFTER the replace regardless.
--
--    Concretely: a hotfix to ottoq_cert_matrix between measurement and apply
--    would have been silently deleted with no snapshot row to recover it from.
--    FIXED: section G (count = 1, prosrc md5, functiondef md5, prosrc length,
--    and a refusal if ottoq_cert_residue already exists) and section S2 (the
--    ottoq_schema_snapshots insert).
SELECT p.proname, md5(p.prosrc) AS prosrc_md5,
       md5(pg_get_functiondef(p.oid)) AS def_md5, length(p.prosrc) AS len
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='ottoq_cert_matrix';
-- MEASURED: f5bb81931feae44871c3ecd86d4f86b4 / 4c00ae1ae666230eb286c7fd864a0717
-- / 5934. These are the values section G now refuses to proceed without.

-- ---------------------------------------------------------------------------
-- 5. THE COMMENT THAT WAS EXACTLY BACKWARDS, and is the finding worth keeping
--    longest. The c_endst comment claimed the explicit key list was written out
--    "so the key set is visible here and cannot drift with the fingerprint's
--    shape." The opposite is true: the OLD opaque md5 over the whole object
--    covered every key BY CONSTRUCTION and could not drift; an ENUMERATED list is
--    precisely what drifts. If ottoq_boot_state_fingerprint gains an eighth key,
--    that atom is streaked by neither instrument and leaves the canon silently --
--    while the pair goes on enforcing it. The comparison becoming narrower than
--    the enforcement is the G25/G28 defect, reintroduced by the fix for G46.
--
--    And the pair verdict cannot cover for it: the arms agree on every section in
--    446 of 446 pairs (0196 M2), so a key equal WITHIN a pair and moving BETWEEN
--    rounds -- G46's own failure class -- is invisible to any arm-vs-arm check.
--
--    FIXED IN TWO PLACES, because apply-time alone is the wrong place for a risk
--    that lives afterwards: 0266's A9 refuses the migration unless the shape is
--    exactly what the split enumerates, and db/checks/0198 registers the same
--    assertion as a STANDING check so a later fingerprint change is forced to
--    revisit both key lists rather than quietly outrunning them.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 6. THE INSTRUMENT THAT LIED IN ITS OWN OUTPUT. ottoq_cert_residue's `history`
--    glyph was computed from `same`, which is floor-scoped -- so every pair below
--    the recert floor rendered '.', meaning MOVED. At the function's own default
--    p_since of 30 days, the reviewer measured grid column 424242/6t rendering
--    '.................SSS' where the truth is twenty S's: seventeen false claims
--    of movement, on a column whose foreign half has never moved, in the
--    instrument whose entire job is to say when it does.
--    FIXED: three states -- 'S' equal, '.' moved, '-' below the floor and not
--    judged -- with the glyph computed from fgn equality alone and the floor
--    confined to the streak, where it belongs.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 7. THE SMALLER ONES, all fixed, listed so the record is complete:
--      * A5 was floor-scoped, so it examined ZERO replay pairs (all nine predate
--        the floor) and was blind to exactly the divergence the new G48 predicate
--        could introduce. The file makes this argument for A10 and failed to
--        apply it here. Now runs over the wide window.
--      * A8 used `count(*) WHERE proname=X AND md5 <> pin` and refused on > 0 --
--        which PASSES when the function does not exist at all. That is the
--        NOT-EXISTS-skips-the-row shape db/checks/0193 (iii) already convicted;
--        reintroducing it inside the fix for it would have been the same defect
--        twice. Inverted to a positive count = 1, which also refuses an overload.
--      * A7b checked only that the ACL was non-empty and mentioned service_role,
--        so deleting the REVOKE line would have left PUBLIC holding EXECUTE and
--        A7b green. Now pins the exact ACL string. And the comment claiming the
--        residue was "granted to match ottoq_cert_matrix exactly" was refuted by
--        A7's own pinned string thirty lines below it -- the matrix's ACL carries
--        a leading `=X/postgres`, which IS the PUBLIC grant. The comment was
--        corrected rather than the grant loosened.
--      * The residue's `same` was NULL-tolerant while `sections_moved` used
--        IS DISTINCT FROM -- one instrument disagreeing with itself about how to
--        treat `unknown`. Both halves now guard NULL the same way.
--      * A6 matched sections_moved = 'legs' exactly, so a second section moving
--        before apply would have refused the migration for an unrelated reason.
--        Now membership.
--      * A10b filtered AFTER DISTINCT ON while the body filters inside the WHERE;
--        A10b exists to prove the clause is in the body, so it now uses the same
--        predicate in the same position.
--      * A10's population omitted `validation_status IS NOT NULL`, validating the
--        predicate over 500 pairs while protecting 493.
--      * The P block matched `jobname ~ '^r[0-9]+_'`, which does not match
--        `ottoq-cert-battery` (cron jobid 13, currently inactive). Now matches on
--        the COMMAND, so a certification path added later is covered without
--        anyone remembering to widen a regex.
--      * Section 1's header claimed the pair CTE was copied verbatim AFTER G48
--        added three predicates to it -- the 0228 defect class (a header
--        asserting what the body does not do) in the comment a reviewer uses to
--        decide how hard to diff. And line 60 credited A6 with the proacl check
--        that A7 performs.
--      * A0 added: three of the assertions pass on an EMPTY matrix. A suite whose
--        subject can be the empty set is not a suite.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 8. A PROCESS FINDING WORTH MORE THAN ANY OF THE ABOVE. The assertions lens
--    reported that the Read tool handed it an ABRIDGED 602-line copy of a file
--    that is 685 lines on disk, silently omitting G48 entirely; the correctness
--    lens reported the file growing from 602 to 701 lines mid-review. Both
--    worked around it by reading with sed and said so.
--
--    THE RULE THAT FOLLOWS: a review of a file that is still being edited is a
--    review of a file that no longer exists. Freeze the artefact before the
--    reviewers start -- and when a reviewer says its copy disagrees with the
--    disk, believe it and re-run rather than reconciling the findings by hand.
--
--    APPLIED IMMEDIATELY, AND IMMEDIATELY STRAINED. The follow-up review of the
--    rebuilt guards reads a frozen copy under scratchpad, pinned by md5 in its
--    own prompt. Then two further fail-open defects were found by hand while it
--    ran (A4 and A7 used a bare SELECT ... INTO, so a missing function left the
--    variable NULL and `position(x in NULL) = 0` is NULL, which `IF` does not
--    fire on -- the same class as the A8 conviction, in the rebuild FOR it) and
--    fixing them moved HEAD away from the frozen copy.
--    THE HONEST PRACTICE, then, is not "never edit" -- it is: the reviewers keep
--    their stable artefact, edits QUEUE against it, and every returning finding
--    is re-checked against HEAD before it is called stale. Silently updating the
--    copy under a running reviewer would be worse than either.
--    Both lenses here caught real defects anyway, but only because each one
--    checked the live database instead of trusting the text in front of it.
-- ---------------------------------------------------------------------------
