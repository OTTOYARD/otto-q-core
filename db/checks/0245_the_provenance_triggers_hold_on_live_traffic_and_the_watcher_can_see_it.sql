-- ============================================================================
-- 0245 — THE PROVENANCE TRIGGERS HOLD ON LIVE TRAFFIC, AND THE WATCHER CAN
--        NOW SEE IT.
-- ============================================================================
-- Measured 2026-09-14 20:15 UTC, round 44 in flight (no pair executing at the
-- moment of measurement; every statement below is read-only).
--
-- WHAT 0320-0322 AND 0326 CLAIMED. Four functions wrote return_eta_minutes and
-- exactly one wrote eta_source, so the label described a write that had been
-- superseded. 0320 created ottoq_refresh_return_eta (value + stamp + label in
-- ONE statement, the label branching on the same variable the value COALESCEs
-- from); 0321 gave the other writers their own labels and added a per-tick
-- refresh so an ACTIVE dispatch carries a forecast, not only a returning one;
-- 0322 added BEFORE triggers refusing a write that moves the value without its
-- provenance; 0326 corrected 0322, which had demanded the sim clock ADVANCE
-- between two correct writes in the same tick and was refusing the engine's own
-- writes.
--
-- A MIGRATION THAT APPLIES IS NOT A MIGRATION THAT WORKS. 0322's own A2/A3
-- assertions both passed and neither could catch the defect 0326 fixed, because
-- each tested a SINGLE write against a row whose stamp already differed. The
-- only instrument that settles it is live traffic through the real writers.
--
-- MEASURED, against public.ottoq_vehicle_dispatches:
--
--   rows created since 0322 applied (19:24 UTC) ........................  746
--     ... of those, carrying return_eta_minutes ........................  746
--     ... of those, missing eta_source .................................    0
--     ... of those, missing eta_refreshed_at ...........................    0
--
--   rows with an ETA and no label, whole table ........................ 73,589
--
-- The 73,589 are legacy and must not be read as a live defect: they predate the
-- triggers, which cannot retro-refuse a write that already happened. The number
-- that matters is the second block -- 746 of 746, zero unlabelled, zero
-- unstamped -- and it is the one that proves the trigger pair is live on both
-- INSERT and UPDATE rather than merely installed:
--
--   trg_dispatch_eta_provenance_ins   INSERT
--   trg_dispatch_eta_provenance_upd   UPDATE
--
-- AND NOTE HOW THE COUNT WAS TAKEN, because the first version of it was wrong
-- in this file's own recurring way. The obvious filter is
--   WHERE return_eta_minutes IS NOT NULL AND eta_source IS NULL
--     AND eta_refreshed_at > '<when 0322 applied>'
-- which answers "unlabelled rows carrying a RECENT STAMP" -- and a row written
-- after 0322 with no stamp and no label is exactly the row that filter cannot
-- see. The measurement above keys on created_at instead, so the window is the
-- row's own age and not a column the defect would have suppressed.
--
-- ---------------------------------------------------------------------------
-- THE SECOND HALF: scripts/watch-run.sql can now be pointed at a run and answer
-- the question these migrations were for. Three hops added, and the reason each
-- is annotated the way it is:
--
--   hop 1  the 0323 arming receipt, read from ottoq_sim_runs.payload.
--          '(NO RECEIPT)' on a cert_harness run is CORRECT and says so --
--          arming sets proposer_frame_facts=1, which moves the decision frame
--          every canon was measured against.
--
--   hop 5  forecast coverage over ACTIVE dispatches. The pre-0321 baseline was
--          0 of 68. The trap the note names: a COMPLETED run has no active
--          dispatch, so this hop reads 0/0 on every finished run and says
--          "NOT A FAILURE" in its own note rather than leaving a reader to
--          conclude 0321 did not take.
--
--   hop 6  the eta_source distribution WITH A DISTINCT-VALUE COUNT per label,
--          which is the whole point: 'computed:*' holding 1 distinct value is a
--          constant wearing a computation's name, and 'policy_constant:*'
--          holding many is the reverse. Both are the defect 0320 was written
--          for, and a bare label count would show neither.
--
-- Verified by running the file's query against run e02e92b4 (bench_busy_day,
-- seed 606060, 48 ticks, completed 18:31 UTC -- a PRE-0323 run, so hop 1
-- correctly reads (NO RECEIPT)). Every hop returned; hop 6 read
-- 'computed:distance_over_speed=55(21 distinct min)', which is a genuinely
-- varying forecast under a label that claims computation.
-- ---------------------------------------------------------------------------
-- AND THE WATCHER IMMEDIATELY EARNED ITS KEEP. Reading hop 6's distinct-value
-- count fleet-wide rather than per-run turns up a label that looks like the
-- exact defect 0320 was written for:
--
--   eta_source                          rows   distinct   range (min)
--   (NO LABEL -- legacy)              73,589         42   1.0 .. 45.9
--   policy_constant:return_eta_minutes 44,067         18   1.6 .. 48.8   <--
--   twin_eta_delay_card:congestion      5,289         15   1.1 .. 33.5
--   computed:distance_over_speed        1,935        119   1.0 .. 153.4
--   twin_eta_delay_card:heavy_traffic   1,905          7   1.2 .. 30.0
--   twin_eta_delay_card:accident        1,089          4   1.7 .. 30.0
--   booking_plan:secured                  288         36   1.0 .. 45.9
--   fixture:prime_deployment              204          1   30.0 .. 30.0
--
-- A label asserting "this is the policy constant" across 18 distinct values is
-- the 0320 defect stated in reverse. IT IS NOT ONE, and the reason is the
-- denominator: the dial is PER RUN, so 18 distinct values across 1,102 runs is
-- 1,102 dials, not one constant that moves. Split per run:
--
--   runs carrying the label ........................................  1,102
--   ... holding exactly ONE distinct value .........................  1,101
--   ... holding MORE than one ......................................      1
--   worst single run ...............................................     17
--
-- The one offender is run a5bd449f (bench_normal_day, 17:05 UTC): 21 dispatches
-- labelled "policy constant" carrying 17 different values from 1.6 to 48.8
-- minutes. It is a PRE-0320 run -- 0320 applied at 19:21 -- so it is a specimen
-- of the defect, not a survival of it.
--
-- THE HONEST LIMIT ON THAT, because "not one" is a claim about live code and
-- the ledger cannot support it yet:
--
--   rows carrying policy_constant:return_eta_minutes since 0320 applied .... 0
--
-- Every forecast written since 0320 took the computed branch, so the fallback
-- branch HAS NOT BEEN EXERCISED IN LIVE TRAFFIC. What can be said is structural
-- and was read from the applied function body, not from the migration file:
--
--   v_eta := COALESCE(v_computed, GREATEST(1, COALESCE(ottoq_policy_get(...), 30)));
--   ... eta_source = CASE WHEN v_computed IS NOT NULL THEN 'computed:...'
--                                                     ELSE 'policy_constant:...' END
--
-- value and label branch on the SAME variable, so the pair cannot disagree. Say
-- "correct by construction, unexercised in live traffic" -- never "proven".
--
-- ============================================================================

-- 1. The window that keys on the row's own age, not on a column the defect
--    would have suppressed.
SELECT count(*) FILTER (WHERE created_at > '2026-09-14 19:24:00+00')
         AS rows_created_since_0322,
       count(*) FILTER (WHERE created_at > '2026-09-14 19:24:00+00'
                          AND return_eta_minutes IS NOT NULL)
         AS with_eta,
       count(*) FILTER (WHERE created_at > '2026-09-14 19:24:00+00'
                          AND return_eta_minutes IS NOT NULL
                          AND eta_source IS NULL)
         AS with_eta_no_label,
       count(*) FILTER (WHERE created_at > '2026-09-14 19:24:00+00'
                          AND return_eta_minutes IS NOT NULL
                          AND eta_refreshed_at IS NULL)
         AS with_eta_no_stamp,
       count(*) FILTER (WHERE return_eta_minutes IS NOT NULL
                          AND eta_source IS NULL)
         AS unlabelled_legacy_whole_table
  FROM public.ottoq_vehicle_dispatches;

-- 2. Both triggers, and which statement each fires on. A provenance rule
--    installed on UPDATE alone would let a first write in unlabelled.
SELECT tgname,
       CASE tgtype::int & 28 WHEN 4 THEN 'INSERT' WHEN 16 THEN 'UPDATE'
                             WHEN 20 THEN 'INSERT+UPDATE' ELSE tgtype::text END AS fires_on
  FROM pg_trigger
 WHERE tgrelid = 'public.ottoq_vehicle_dispatches'::regclass
   AND NOT tgisinternal
 ORDER BY tgname;

-- 3. The distribution hop 6 reads, fleet-wide rather than per-run: a label with
--    one distinct value is the thing to look at, whatever the label says.
SELECT COALESCE(eta_source,'(NO LABEL -- legacy)') AS eta_source,
       count(*)                                    AS rows,
       count(DISTINCT return_eta_minutes)          AS distinct_minutes,
       min(return_eta_minutes)                     AS min_min,
       max(return_eta_minutes)                     AS max_min
  FROM public.ottoq_vehicle_dispatches
 WHERE return_eta_minutes IS NOT NULL
 GROUP BY 1
 ORDER BY 2 DESC;
