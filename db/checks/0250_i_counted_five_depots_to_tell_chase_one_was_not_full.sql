-- 0250  I COUNTED FIVE DEPOTS TO TELL CHASE ONE OF THEM WAS NOT FULL.
--       ON THE ONE THAT MATTERS, EVERY REFUSED PROPOSAL ASKED FOR ONE OF THE
--       TWO STALL TYPES THAT ARE 87% AND 80% OCCUPIED.
--
-- ── 0. THE RETRACTION, WHICH IS THE POINT OF THIS FILE ─────────────────────
--
-- I told Chase, in session, diagnosing why cuOpt proposals were reaching the
-- kernel and none were being enacted:
--
--   "Stalls are NOT scarce: 217 staging, 36 L2, 12 DCFC available. The refusal
--    reasons are entity_decided_by_other_proposal and stall_occupied -- i.e.
--    the local path got there first, not a capacity wall."
--
-- The query behind the first sentence had NO DEPOT PREDICATE. It counted every
-- stall in the database: 330 rows across FIVE depots, one of which ("OTTOYARD
-- Benchmark (CRN A/B)", 160 stalls) has never hosted a sim run. On the site
-- actually under test the L2 figure is not 36, it is 4.
--
-- Fourth instance of the class, after 0145 (ottoq_ab_runs read without its
-- policy dimension), 0146 (baselines compared without the shield held
-- constant) and 0229: a number measured over a wider population than the
-- claim it was used to support.
--
-- ══ 1. THE TWIN DEPOT, SCOPED ══════════════════════════════════════════════
--
-- depot 11111111-1111-1111-1111-111111111111, "OTTOYARD Nashville Flagship",
-- 158 stalls -- the ONLY site authorised for test or validation (section 4).
-- Measured 2026-09-19 ~22:10 UTC, live run a51acc84 at tick ~284:
--
--   stall_type    total   not available   available   utilisation
--   service_bay       2               2           0       100%
--   l2               30              26           4        87%
--   dcfc             10               8           2        80%
--   staging         113              18          95        16%
--   wash_bay          3               0           3         0%
--
-- Against the unscoped figures I quoted -- 36 L2 and 12 DCFC "available" --
-- the truth on the site under test is 4 and 2. The unscoped L2 count was nine
-- times too high.
--
-- ══ 2. AND THE REFUSALS LAND ENTIRELY ON THE SATURATED TYPES ═══════════════
--
-- This is what inverts the reading rather than merely correcting a number.
-- Refused proposals on the live run, by the stall type they asked for
-- (tick 305, re-measured):
--
--   stall_occupied   l2     3
--   stall_occupied   dcfc   2
--   stall_reserved   dcfc   1
--   stall_reserved   l2     1
--                    ---------
--                    7 of 7 on l2 or dcfc; 0 on the 95 free staging stalls
--
-- A refusal set landing entirely on the two scarce types, and never once on
-- the abundant one, is the signature of contention -- not of a proposer being
-- beaten to the punch. Q5 asserts this rather than asking the reader to trust
-- the tally.
--
-- The 11 SUPERSEDED proposals (9 entity_decided_by_other_proposal, 2
-- newer_proposal_same_entity) are a different disposition and my original
-- reading of THOSE stands: that is propose/dispose precedence working as
-- designed. I folded refused and superseded together to reach one comfortable
-- sentence, and they do not mean the same thing.
--
-- ══ 3. AND cuOpt IS NOT AT ZERO ENACTMENTS ═════════════════════════════════
--
-- At tick 284 there were no enacted proposals. At tick 305 there is one:
-- source cuopt, status enacted, disposition_reason enacted_by_kernel, on an
-- l2 stall. "Refusing all" was a statement about one tick that I carried
-- forward as though it were a property of the system.
--
-- ══ 4. THE FINDING THAT OUTRANKS THE CORRECTION ════════════════════════════
--
-- Chasing the discrepancy between the two measurements surfaced something
-- larger: THE ENACTMENT RATE IS NOT MEASURABLE FROM ANY DURABLE TABLE.
--
--   (a) ottoq_external_proposals is a per-tick WORKING SET, not a ledger.
--       Two routines -- ottoq_l2_optimize_assignments and
--       ottoq_l2_propose_seat -- each open with
--           DELETE FROM ottoq_external_proposals
--            WHERE sim_run_id = p_sim_run_id AND source = <their own>
--              AND action_context = 'stall_assignment';
--       before writing the tick's proposals. That is why the two
--       greedy_constrained refusals visible at tick 284 were GONE at tick 305:
--       their own proposer deleted them. The table held 41 rows across 2 runs
--       at 22:16 UTC and 45 six minutes later -- it churns, so treat any row
--       count here as a reading of a moment, not a total. It is also class
--       `engine`, so the demo-run purge takes the rest.
--
--   (b) ottoq_proposer_fire_log IS class `evidence` and does survive -- but it
--       records n_submitted, n_abstained, n_deferred. There is no enactment
--       column. And it holds 112 rows over 10 runs with the most recent at
--       2026-09-17 00:29 UTC: it has captured NOTHING from the live run that
--       started 2026-09-19 21:55. Tracked as G72.
--
--   (c) ottoq_model_call_ledger (0340, class `evidence`) durably counts cuOpt's
--       CALLS and PROPOSALS RETURNED. It does not counts what the kernel then
--       did with them.
--
-- So the rule-6 discipline -- "cuOpt claims must be ledger-backed" -- holds for
-- calls and proposals and DOES NOT hold for enactment. Any sentence of the form
-- "cuOpt's proposals are enacted N% of the time" is unsupportable today in
-- either direction, exactly as 0231 found for the call count. Stating that
-- plainly is the deliverable here; building the ledger is not this file's job.
--
-- ══ 5. SO THE HONEST SENTENCE ══════════════════════════════════════════════
--
-- SAY: "On the twin depot at tick 305, cuOpt's proposals are disposed three
-- ways: 11 superseded by precedence, 7 refused for stall contention, 1 enacted.
-- All 7 refusals asked for an l2 or dcfc stall, and those types are 87% and 80%
-- occupied. Charging capacity on this site is the binding constraint. The
-- proposal-to-enactment RATE is not quotable: the proposals table is a per-tick
-- working set that each proposer wipes, and no evidence-class table records
-- enactment."
--
-- DO NOT SAY: "stalls are not scarce" (measured across five depots, four not
-- under test), "the kernel refuses everything" (one enactment at tick 305), or
-- any enactment percentage at all (section 4).
--
-- What this does NOT establish: whether cuOpt's proposals were GOOD. A proposal
-- refused for stall_occupied may have been refused because the stall genuinely
-- filled between propose and dispose (contention) or because the proposer
-- reasoned over a stale snapshot (a proposer defect). Those are distinguishable
-- -- compare the stall's occupancy at created_at against disposed_at -- and are
-- NOT distinguished here. Tracked as G71.
--
-- ══ 6. THE SITE CONSTRAINT, RECORDED SO IT IS NOT RE-LITIGATED ═════════════
--
-- Chase, 2026-09-19, verbatim:
--
--   "The only depot, installs and chargers and staging spaces I ever want you
--    to test against is Otto-twin depot. I don't wanna do multiple depot with
--    200 stalls. I wanna start with that depot and see effectively if OTTO-Q
--    functions first. If it does, then we will see potentially how many
--    vehicles at one time we can comfortably stage and sort an orchestrate
--    through there. That's the ultimate goal. We are nowhere near that yet. We
--    still need to test and validate everything. Just letting you know, do not
--    test or validate across multiple sites. Only use the simulation twin
--    Depot as the test site."
--
-- This lands in CLAUDE.md Part 1 as operating rule 8. It supersedes two things
-- already written there, both named in the rule rather than deleted: Phase C8's
-- "Site Alpha" multi-tenant config, and 2.5's "cuOpt routes recalls BETWEEN
-- sites (at 18-depot scale)". The second is the sharper conflict -- the forced
-- decomposition of 2.5 hands cuOpt the inter-site layer, and on one depot there
-- is no inter-site layer to hand it. Which makes the 7 refusals and 1 enactment
-- above the whole of cuOpt's present contribution, and makes measuring it
-- honestly matter more, not less.
--
-- Nothing in this file changes engine state. It is measurement plus one
-- retraction. Every query below was executed before the file was committed.
--
-- ── THE QUERIES ────────────────────────────────────────────────────────────

-- Q1  the scoped occupancy census. The WHERE clause IS the finding.
SELECT s.stall_type,
       count(*)                                         AS total,
       count(*) FILTER (WHERE s.status <> 'available')  AS not_available,
       count(*) FILTER (WHERE s.status =  'available')  AS available,
       round(100.0 * count(*) FILTER (WHERE s.status <> 'available')
             / count(*))                                AS pct_utilised
  FROM public.stalls s
 WHERE s.depot_id = '11111111-1111-1111-1111-111111111111'
 GROUP BY 1
 ORDER BY 5 DESC;

-- Q2  the same census WITHOUT the predicate, retained deliberately so the size
--     of the error is reproducible rather than asserted. This is the shape of
--     the query I ran; it answers a question nobody asked.
SELECT count(DISTINCT depot_id) AS depots_counted,
       count(*)                 AS stalls_counted
  FROM public.stalls;

-- Q3  which depots those extra stalls belong to, and how many sim runs each has
--     ever hosted. A depot with zero runs contributing "available" capacity to
--     the diagnosis of a live run is the defect in one row.
--
--     NOTE: GROUP BY d.id, NOT `GROUP BY 1` over `d.id::text`. Grouping by the
--     ordinal groups by the CAST EXPRESSION, leaving the correlated subquery's
--     d.id ungrouped -- 42803 at run time. The first draft of this query had
--     exactly that bug and it is left described rather than silently fixed,
--     because it is the same failure mode as the plpgsql lazy-planning traps
--     this directory keeps recording: valid-looking SQL that only fails when run.
SELECT d.id::text AS depot,
       d.name,
       count(DISTINCT s.id) AS stalls,
       (SELECT count(*) FROM public.ottoq_sim_runs r WHERE r.depot_id = d.id) AS sim_runs
  FROM public.depots d
  LEFT JOIN public.stalls s ON s.depot_id = d.id
 GROUP BY d.id, d.name
 ORDER BY sim_runs DESC, stalls DESC;

-- Q4  proposal disposition on the live run, split by disposition rather than
--     lumped. superseded != refused != enacted.
WITH r AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE status = 'running' ORDER BY started_at DESC LIMIT 1
)
SELECT p.source, p.status, p.disposition_reason, s.stall_type, count(*) AS n
  FROM public.ottoq_external_proposals p
  JOIN r ON r.sim_run_id = p.sim_run_id
  LEFT JOIN public.stalls s ON s.id = (p.proposal->>'stall_id')::uuid
 GROUP BY 1,2,3,4
 ORDER BY n DESC;

-- Q5  the assertion carrying section 2: every refusal targets a charging stall.
WITH r AS (
  SELECT sim_run_id FROM public.ottoq_sim_runs
   WHERE status = 'running' ORDER BY started_at DESC LIMIT 1
),
refused AS (
  SELECT s.stall_type, count(*) AS n
    FROM public.ottoq_external_proposals p
    JOIN r ON r.sim_run_id = p.sim_run_id
    LEFT JOIN public.stalls s ON s.id = (p.proposal->>'stall_id')::uuid
   WHERE p.status = 'refused'
   GROUP BY 1
)
SELECT coalesce((SELECT sum(n) FROM refused), 0)                              AS refusals_total,
       coalesce((SELECT sum(n) FROM refused WHERE stall_type IN ('l2','dcfc')), 0)
                                                                              AS refusals_on_charging,
       coalesce((SELECT sum(n) FROM refused
                  WHERE stall_type NOT IN ('l2','dcfc') OR stall_type IS NULL), 0)
                                                                              AS refusals_elsewhere,
       coalesce((SELECT sum(n) FROM refused WHERE stall_type IN ('l2','dcfc')), 0)
         = coalesce((SELECT sum(n) FROM refused), 0)  AS every_refusal_is_a_charging_stall;

-- Q6  section 4(a): the proposals table is a working set. Two routines delete
--     their own prior rows each tick. 41 rows over 2 runs for the engine's life.
SELECT (SELECT count(*) FROM public.ottoq_external_proposals)                  AS rows_total,
       (SELECT count(DISTINCT sim_run_id) FROM public.ottoq_external_proposals) AS runs_present,
       (SELECT min(created_at) FROM public.ottoq_external_proposals)           AS earliest_row,
       (SELECT string_agg(n.nspname||'.'||p.proname, ', ' ORDER BY p.proname)
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','gs'),
                              '--[^\n]*','','g')
                 ~* 'delete\s+from\s+(public\.)?ottoq_external_proposals')     AS deleters;

-- Q7  section 4(b): the evidence-class proposer log survives its run, has no
--     enactment column, and has captured nothing since 2026-09-17. G72.
SELECT count(*)                       AS rows,
       count(DISTINCT sim_run_id)     AS runs,
       max(fired_at)                  AS latest_fire,
       (SELECT count(*) FROM information_schema.columns
         WHERE table_schema='public' AND table_name='ottoq_proposer_fire_log'
           AND column_name ILIKE '%enact%')                AS enactment_columns,
       (SELECT count(*) FROM public.ottoq_proposer_fire_log f
         JOIN public.ottoq_sim_runs r ON r.sim_run_id = f.sim_run_id
        WHERE r.status = 'running')                        AS rows_for_live_run
  FROM public.ottoq_proposer_fire_log;
