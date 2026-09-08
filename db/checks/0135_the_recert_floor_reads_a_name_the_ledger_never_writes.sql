-- ---------------------------------------------------------------------------
-- 0135 — G28. Every `forces_recert: FALSE` declared since 2026-09-04 15:00 has
--        been INERT. The floor function joins the lineage table on a name the
--        apply path does not write, so classification never reaches it and the
--        conservative default — "an unclassified migration forces recert" —
--        fires for every migration, classified or not.
--
--        Not one certification column is green. Six of seven are stale. One
--        column has 26 consecutive passing pairs and a streak of zero.
--
-- Found 2026-09-08 14:20 UTC while dry-running 0225's P3 precondition. P3 asks
-- "how many distinct values does each newly compared atom have at or above the
-- recert floor". The answer came back as ONE COLUMN with ONE PAIR, where
-- db/checks/0134 had recorded four columns 78 minutes earlier. The floor had
-- moved to 13:41:09 — 0224's timestamp, and 0224 declares forces_recert FALSE.
-- A migration that says it does not force a recertification had forced one.
-- ---------------------------------------------------------------------------

-- Q1. THE FLOOR FUNCTION, AND THE JOIN THAT DOES NOT JOIN. From the live body
--     of public.ottoq_cert_recert_floor:
--
--       SELECT GREATEST(
--         (SELECT max(<version as timestamptz>)
--            FROM supabase_migrations.schema_migrations m
--            LEFT JOIN public.ottoq_cert_lineage l ON l.name = m.name
--           WHERE COALESCE(l.forces_recert, true)          <-- the default
--             AND m.version ~ '^[0-9]{14}$'),
--         (SELECT max(l.classified_at)
--            FROM public.ottoq_cert_lineage l WHERE l.forces_recert));
--
--     `COALESCE(l.forces_recert, true)` is CORRECT and deliberate: a migration
--     nobody classified must be assumed to move the world. The defect is not
--     the default. The defect is that `l.name = m.name` almost never matches,
--     so nearly every migration reaches the default.
SELECT public.ottoq_cert_recert_floor() AS floor_now;
--     -> 2026-09-08 13:41:09+00   (0224's version timestamp, 2026-09-08 14:20)

-- Q2. THE MISMATCH, MEASURED. The lineage table holds two naming conventions
--     and the switch between them is datable to the hour.
SELECT (l.name ~ '^[0-9]{4}') AS name_has_the_NNNN_prefix,
       count(*) AS rows, min(l.classified_at) AS first, max(l.classified_at) AS last,
       count(*) FILTER (WHERE l.forces_recert) AS forcing
FROM public.ottoq_cert_lineage l GROUP BY 1 ORDER BY 1;
--     -> false | 59 | 2026-09-01 00:55:06 | 2026-09-04 14:09:14 | 21
--        true  | 33 | 2026-09-04 15:00:00 | 2026-09-08 13:41:09 | 12
--
--     `supabase_migrations.schema_migrations.name` is the migration name WITHOUT
--     the number — apply_migration takes the name as an argument and the
--     protocol in scripts/APPLYING.md passes the unprefixed form. So all 33
--     rows written since 2026-09-04 15:00 join nothing. Of those 33, TWENTY-ONE
--     declare forces_recert FALSE, and all twenty-one were inert.

-- Q3. HOW MUCH OF THE LEDGER IS REACHABLE, both ways.
WITH norm AS (
  SELECT l.name AS lname, regexp_replace(l.name,'^[0-9]{4}[a-z]?_','') AS lkey,
         l.forces_recert, l.classified_at FROM public.ottoq_cert_lineage l),
j AS (
  SELECT m.version, m.name,
         make_timestamptz(substr(m.version,1,4)::int, substr(m.version,5,2)::int,
                          substr(m.version,7,2)::int, substr(m.version,9,2)::int,
                          substr(m.version,11,2)::int, substr(m.version,13,2)::numeric,'UTC') AS ts,
         w.forces_recert AS fr_written, s.forces_recert AS fr_symmetric
    FROM supabase_migrations.schema_migrations m
    LEFT JOIN norm w ON w.lname = m.name
    LEFT JOIN norm s ON s.lkey  = regexp_replace(m.name,'^[0-9]{4}[a-z]?_','')
   WHERE m.version ~ '^[0-9]{14}$')
SELECT count(*) AS sm_rows,
       count(fr_written)   AS classified_as_the_join_is_written,
       count(fr_symmetric) AS classified_if_both_sides_normalised,
       max(ts) FILTER (WHERE COALESCE(fr_written,true))   AS floor_branch1_today,
       max(ts) FILTER (WHERE COALESCE(fr_symmetric,true)) AS floor_branch1_normalised,
       (SELECT max(classified_at) FROM norm WHERE forces_recert) AS floor_branch2,
       (SELECT count(*) FROM j WHERE fr_symmetric IS NULL AND ts > '2026-09-04 15:00+00')
         AS genuinely_unclassified_since_the_boundary
FROM j;
--     -> 858 | 60 | 70 | 2026-09-08 13:41:09 | 2026-09-07 21:36:53
--            | 2026-09-07 21:36:53 | 0
--
--     Read the last column first: **zero**. Every migration applied since the
--     naming boundary HAS a lineage row. Nothing is genuinely unclassified in
--     that window. The floor is sixteen hours too new purely because of a
--     string format.
--
--     And normalising BOTH SIDES matters, which is a correction to the first
--     version of this analysis. Stripping the prefix from `l.name` alone
--     raises the count to 69, not 70: it breaks the one case where
--     schema_migrations itself carries a prefixed name (0208), turning a
--     match into a miss. A one-sided normalisation of a two-sided mismatch
--     trades one defect for another.

-- Q4. WHAT THE CORRECT FLOOR IS, AND WHY THIS IS NOT A LOOSENING.
--
--     Normalised, branch 1 gives 2026-09-07 21:36:53 and branch 2 gives the
--     same instant. Both are `0208_the_verdict_sees_what_the_shield_read`,
--     whose header reads:
--
--       forces_recert: TRUE. canon_rule moves everywhere, so the streak restarts.
--
--     So the floor the classifications actually specify is 0208's, and it is
--     already reachable through branch 2 — which is why the two branches agree.
--     Fixing branch 1 does not invent a lower floor; it stops branch 1 from
--     inventing a higher one. Nothing is being relaxed on judgement: every
--     migration between 0208 and now argued its FALSE in its own header, and
--     several proved it against the live verdict function (0224's P1 asserts
--     h_evt never reads data_source; 0223 changes no engine behaviour at all).

-- Q5. THE COST, IN THE MATRIX'S OWN WORDS. Flagship depot, 2026-09-08 14:20:
--
--       scenario/seed/ticks  pairs  streak  green  stale  tail of history
--       busy_day/171717/48       5       0  false  true   PfPPP
--       busy_day/171717/24      54       0  false  true   ...fPPPP
--       busy_day/424242/24      48       0  false  true   ...PPPPPPPPPPPPPPPPPPPPPPPPPP
--       busy_day/171717/12      75       0  false  true   ...PPPPPPPPPPPPPPPPPPPPPPPP
--       busy_day/314159/12      55       1  false  false  ...PPPPPPPPPPPPPPPPP
--       busy_day/424242/12      63       0  false  true   ...PPPPPPPPPPPPPPPPPPPPPPPP
--       normal_day/171717/12    61       0  false  true   ...PPPPPPPPPPPPPPPPPPPPPPPPPP
--
--     `busy_day/424242/24t` has TWENTY-SIX consecutive passing pairs and a
--     consecutive_passes of zero. Not one column is green. Six of the seven are
--     stale, meaning their most recent pair predates a floor that a
--     forces_recert FALSE migration moved.
SELECT scenario, seed, ticks, pairs_seen, consecutive_passes, green, stale,
       last_pair_at, recert_floor, right(history, 30) AS tail
FROM public.ottoq_cert_matrix(now() - interval '10 days')
WHERE depot = '11111111-1111-1111-1111-111111111111'
ORDER BY ticks DESC, scenario, seed;

-- Q6. WHAT THIS DOES AND DOES NOT INVALIDATE.
--
--     DOES NOT: any pair verdict. `ottoq_determinism_pair` never reads the
--     floor. Every PASS in Q5's history is a real within-pair result, and every
--     hand-diffed round canon (db/canons/round25.md, round26.md, round27.md)
--     is real across-round evidence. Round 26's six-of-six and round 27's
--     column a stand exactly as recorded.
--
--     DOES: every statement of the form "the column is green" or "the streak is
--     N" made since 2026-09-04 15:00, and — worth saying plainly because it is
--     my own — every `forces_recert: FALSE` footer I have written since then.
--     Those footers were sound about INTENT and several of them proved their
--     claim against the live verdict function. What none of them delivered was
--     the EFFECT, because the row they wrote could not be read by the function
--     that needed it. A classification nobody can reach is a comment.
--
--     It also sharpens 0134's point rather than replacing it. 0134 found that
--     four enforced atoms sit outside the across-round comparison, so the
--     hand-written round canons were the only place they were diffed. G28 says
--     the across-round comparison has not been running at all. The hand-written
--     canons were not a backup; for four days they were the whole instrument.

-- Q7. THE FIX, AND WHY IT IS TWO THINGS.
--
--     (a) Normalise BOTH sides of the join in ottoq_cert_recert_floor, so a
--         lineage row written under either convention is reachable. Data is not
--         rewritten: 92 rows in two formats stay as they are, and the function
--         stops caring. Rewriting the 33 rows instead would fix today and leave
--         the next convention drift to do this again.
--
--     (b) Make an orphan VISIBLE. The reason this survived four days is that a
--         lineage row that joins nothing looks exactly like a lineage row that
--         joins: it is present, it is correct, and nothing ever asks whether it
--         was consulted. A view that lists lineage rows matching no migration,
--         asserted empty, turns a silent miss into a loud one.
--
--     Drafted as 0226. NOT applied while round 27 is in flight, and applied
--     BEFORE 0225 deliberately: lowering the floor puts many more pairs in
--     scope, which makes 0225's P3 precondition a much harder test. If P3 then
--     refuses, that is the check working, and it is better to learn it from the
--     larger evidence set than from a floor that admits one pair.
SELECT 'see Q1-Q7; this file changes nothing' AS status;

-- ---------------------------------------------------------------------------
-- ADDENDUM 2026-09-08 15:58 UTC — 0226's A1 was asserting the wrong thing, and
-- would have aborted the whole apply window on its own first migration.
--
-- Dry-running 0226's preconditions in the state they would actually meet
-- (scripts/APPLYING.md step 3b(ii)) turned up a defect this file's own framing
-- helped create. 0135 counted "33 of 92 classifications join nothing" and
-- 0226 turned that into an assertion: `ottoq_cert_lineage_orphans()` must
-- return zero. **It returns 22 after the fix, and 32 before it.**
--
-- THE 22, and they are not defects:
--
--     0192 … 0215 — a contiguous block, every one classified between
--     2026-09-04 15:00 and 2026-09-08 07:47.
--
-- Those are the migrations applied through the **SQL endpoint**, which writes
-- no `supabase_migrations.schema_migrations` row at all. There is nothing for
-- their classification to be keyed against, so no amount of key normalisation
-- can match them. 0199 already knew this and gave the floor a **second branch**
-- reading `max(classified_at)` straight off `ottoq_cert_lineage` with no join —
-- and measured today, that branch is the one setting the floor:
--
--     branch 1 (schema_migrations join) : 2026-09-07 21:36:53
--     branch 2 (lineage direct)         : 2026-09-07 21:36:53.363037   <- wins
--
-- So the 22 rows' classifications ARE consulted. The function's name and its
-- first COMMENT both said otherwise ("classifications ottoq_cert_recert_floor
-- cannot consult"), and that was wrong for exactly the rows that make up the
-- entire result.
--
-- WHAT G28 ACTUALLY CLAIMS, and it is checkable without this ambiguity, from
-- the migration side: **no `schema_migrations` row since the naming boundary
-- falls through to the conservative default.** Measured 15:57 UTC: **0**. That
-- is the whole of the finding, it holds, and it is what 0226's A1 now asserts.
--
-- Two second-order notes:
--   * The floor lands at **21:36:53.363037**, not the flat 21:36:53 this file
--     quoted. The 363 ms is branch 2 winning. `db/checks/0140` Q5's P3 dry-run
--     pinned the flat value — 363 ms early — and no pair started inside that
--     gap, so that dry-run stands. Recorded because "the floor is 21:36:53" is
--     the kind of rounded quote that is right until it is load-bearing.
--   * 0226's A2 compares the floor to `max(classified_at) WHERE forces_recert`,
--     i.e. to branch 2 itself, so it matches to the microsecond and passes.
--
-- The lesson is the one APPLYING.md 3b(ii) already carries, earning its keep a
-- second time in one hour: an assertion derived from a check's *summary
-- sentence* rather than from the check's data will encode the summary's
-- imprecision. "33 of 92 join nothing" was true and was never a defect count.
-- ---------------------------------------------------------------------------

-- THE REST OF 0226 DRY-RUNS CLEAN — checked 15:59 UTC, because finding one
-- broken assertion is a reason to check the others, not a reason to stop.
--
--   P2  migrations since the boundary with no classification ......... 0   PASS
--   A1  (rewritten) same check, asserted ............................. 0   PASS
--   A1  lineage rows unreachable by the join, must be < 32 ........... 22  PASS
--   A2  floor lands on max(classified_at) WHERE forces_recert ....... exact match
--       (both are 2026-09-07 21:36:53.363037 — A2 compares against branch 2
--        itself, so the sub-second cannot trip it)
--   A3  an unclassified migration must still exist ................... 788 PASS
--   A3  migrations counting as forcing, must be >= 700 ............... 810 PASS
--   A4  non-stale flagship columns, must be >= 2 ..................... 6   PASS
--
-- A4 is worth a caveat rather than a tick: it reads 6 *today*, at the current
-- high floor, only because round 27 finished after that floor was set. It would
-- have read 1 at 14:15 when 0135 was written. So A4 passes for a reason that has
-- nothing to do with 0226 working, and it is a weak assertion — kept because a
-- weak assertion that cannot fail spuriously is still better than none, but not
-- to be cited as evidence the fix worked. The evidence for that is A1 and A2.

