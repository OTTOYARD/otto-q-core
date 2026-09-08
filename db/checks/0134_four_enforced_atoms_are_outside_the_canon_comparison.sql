-- ---------------------------------------------------------------------------
-- 0134 — the pair enforces FOURTEEN equalities. The canon machinery compares
--        NINE of them. Two of the missing four are printed in the matrix's own
--        output, which is worse than omitting them.
--
-- Found 2026-09-08 12:58 UTC while checking whether db/canons/README.md's
-- regeneration query was still current. It is not, and the reason it is not is
-- a gap in ottoq_cert_matrix rather than in the README.
-- ---------------------------------------------------------------------------

-- Q1. TWO DIFFERENT JOBS, AND ONLY ONE OF THEM IS THE PAIR'S.
--
--     ottoq_determinism_pair compares ARM A TO ARM B. That is a
--     within-pair question: did the same seed produce the same run twice.
--
--     ottoq_cert_matrix compares THIS PAIR TO THE CANON. That is the
--     across-round question: did today's migrations move anything. It is the
--     mechanism db/canons/README.md exists to serve — "a canon committed to the
--     repo is the thing an engine change is diffed against".
--
--     A defect that moves an atom IDENTICALLY ON BOTH ARMS passes the first
--     question and is only catchable by the second.

-- Q2. WHAT on_canon ACTUALLY COMPARES. From the live body:
--
--        AND r.c_fp  IS NOT DISTINCT FROM k.c_fp
--        AND r.c_cmd IS NOT DISTINCT FROM k.c_cmd
--        AND r.c_dec IS NOT DISTINCT FROM k.c_dec
--        AND r.c_evt IS NOT DISTINCT FROM k.c_evt
--        AND r.c_bkg IS NOT DISTINCT FROM k.c_bkg
--        AND r.c_nrg IS NOT DISTINCT FROM k.c_nrg
--        AND (r.c_prop IS NULL OR k.c_prop IS NULL OR r.c_prop = k.c_prop)
--        AND (r.c_defr IS NULL OR k.c_defr IS NULL OR r.c_defr = k.c_defr)
--        AND (r.c_cal  IS NULL OR k.c_cal  IS NULL OR r.c_cal  = k.c_cal)
--
--     Nine. Six strict, three NULL-tolerant (0199/0201, correctly: a pair
--     hashed before an instrument existed cannot be judged by it).
--
--     And `bool_and(m.on_canon) OVER (PARTITION BY …)` is what feeds
--     consecutive_passes, and consecutive_passes is what feeds `green`. So the
--     nine atoms above are the ones that can break a streak. The others cannot.
SELECT (SELECT count(*) FROM regexp_matches(p.prosrc,'IS NOT DISTINCT FROM','g')) AS strict_compares,
       (SELECT count(*) FROM regexp_matches(p.prosrc,'h_sdr','g'))  AS mentions_h_sdr,
       (SELECT count(*) FROM regexp_matches(p.prosrc,'endst','g'))  AS mentions_endst,
       (SELECT count(*) FROM regexp_matches(p.prosrc,'c_rule','g')) AS mentions_c_rule,
       (SELECT count(*) FROM regexp_matches(p.prosrc,'c_rcl','g'))  AS mentions_c_rcl
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='ottoq_cert_matrix';
--     -> 6 / 0 / 0 / 3 / 3   (2026-09-08 12:58 UTC)

-- Q3. WHAT THE PAIR ENFORCES, for comparison. From ottoq_determinism_pair's
--     v_equal, fourteen equalities:
--
--       fp  h_cmd  h_dec  h_evt  h_bkg  h_nrg          <- in the canon (strict)
--       h_prop  h_defr  h_cal                          <- in the canon (lenient)
--       h_rule   (enforced 0205)                       <- NOT COMPARED
--       h_rcl    (enforced 0217)                       <- NOT COMPARED
--       h_sdr    (enforced 0219, this morning)         <- NOT CARRIED AT ALL
--       endst    (enforced 0139)                       <- NOT CARRIED AT ALL
--       ticks                                          <- structural, not a canon
--
--     **Four enforced atoms are outside the across-round comparison.**

-- Q4. AND TWO OF THEM ARE PRINTED ANYWAY, WHICH IS THE PART THAT MISLEADS.
--     ottoq_cert_matrix's RETURNS TABLE ends:
--
--       …, canon_prop text, canon_defr text, canon_cal text,
--          canon_rule text, canon_rcl text
--
--     c_rule and c_rcl are extracted from the run, carried into the canon CTE,
--     and RETURNED as columns — three mentions each, and not one of them is a
--     comparison. A reader looking at the matrix sees `canon_rule` beside
--     `canon_cmd` and has no way to know that one of them can break the streak
--     and the other cannot. An omitted column is a gap; a displayed column that
--     is never judged is a false assurance.
SELECT pg_get_function_result(p.oid) AS returns_table
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='ottoq_cert_matrix';

-- Q5. THE CONSEQUENCE, STATED AS THE SCENARIO IT PERMITS.
--
--     A migration changes the settlement path so that every SDR gets one more
--     field. Both arms produce the same new h_sdr. Next round:
--
--       the pair          PASSES     (arm A = arm B)
--       on_canon          TRUE       (h_sdr is not one of the nine)
--       consecutive_passes ADVANCES
--       green             STAYS TRUE
--       the canon for that column has silently changed
--
--     That is precisely the failure db/canons/README.md was written about:
--     "five passing rows made 'today's migrations introduced no carrier' an
--     easy claim to write, and it was not available from the evidence." The
--     README solved it for the repo. It is still true inside the machinery.
--
--     IT IS LIVE RIGHT NOW. 0219 promoted h_sdr to enforced at 11:15 UTC today.
--     Round 26 is recertifying against it — and the matrix cannot see it. The
--     only reason round 26's h_sdr movement would have been caught is that
--     db/canons/round25.md and round26.md were compared BY HAND.

-- Q6. WHAT NOT TO CONCLUDE. This does not mean round 26 proves nothing. Every
--     atom in rounds 25 and 26 was compared column by column in
--     db/canons/round26.md, by hand, against round 25's recorded values —
--     including all four of the atoms the matrix omits. The hand comparison is
--     real evidence. What is missing is the AUTOMATION: the claim currently
--     depends on somebody remembering to diff two markdown files, and that is
--     exactly the kind of dependency this project has been removing everywhere
--     else.
--
--     THE FIX is a migration extending ottoq_cert_matrix: carry c_sdr and
--     c_endst, and move c_rule and c_rcl from carried-and-printed to compared.
--     Two cautions for whoever writes it:
--
--       - use the 0199/0201 NULL-tolerant form for the newly compared atoms.
--         Pairs older than the instrument have NULLs, and a strict compare
--         would retroactively break every historical streak.
--       - it changes `green` for existing columns if any of them are in fact
--         off-canon on rule/rcl today. Check that BEFORE applying, or the
--         migration lands looking like a regression.
--
--     Deliberately not drafted here: round 27 already judges 0223 and 0224, and
--     a third change would make none of the three attributable.
SELECT 'see Q1-Q6; this file changes nothing' AS status;
