-- 0318  **RETRACTION, and the largest one this session. `db/checks/0315` §3 and the ENTIRE
--       PREMISE of `db/checks/0316` rest on "`ottoq_events` holds zero arm or tether rows."
--       It holds 2,678, it has held them all along, and the zero came from a WHERE clause I
--       deleted myself while fixing a syntax error somewhere else in the same query.**
--
--       Everything `0316` then reasoned — the 459 MB, the 39% growth, the "difference between a
--       feature and an outage," the summary-versus-individual design — is retracted. Not
--       adjusted. Retracted. The feature it was sizing already exists.
--
-- ══ §1 THE CAUSE, VERBATIM, BECAUSE IT IS NOT A SEARCH MISTAKE ══════════════
--
-- Two tool calls, ten seconds apart, on 2026-09-21. The first (18:40:07 UTC) asked the right
-- question inside a nine-key `jsonb_build_object` census:
--
--     'arm_events', (SELECT count(*) FROM public.ottoq_events
--                     WHERE event_type ILIKE '%tether%'
--                        OR event_type ILIKE '%arm%'
--                        OR event_type ILIKE '%mate%')
--
-- That predicate matches `arm.mate_latched`. It would have returned ~2,600. **It never ran.**
-- A DIFFERENT key in the same statement — `demate_literals`, which put `regexp_matches` inside
-- `jsonb_object_agg` — failed the whole call:
--
--     ERROR: 0A000: aggregate function calls cannot contain set-returning function calls
--     HINT:  You might be able to move the set-returning function into a LATERAL FROM item.
--
-- The second call (18:40:17 UTC) fixed that correctly, moving `regexp_matches` into a subquery.
-- And while retyping the other eight keys it shipped this:
--
--     'arm_events', (SELECT count(*) FROM public.ottoq_events
--                     WHERE event_type ILIKE '%tether%'
--                        OR event_type ILIKE '%robotic%')
--
-- **`%arm%` and `%mate%` are gone.** No event type in this database contains "tether" or
-- "robotic" — the family is `arm.*`. So the surviving predicate could not have returned
-- anything but 0, and it returned 0, **under a key still named `arm_events`.** I read the key,
-- not the predicate, and wrote two files on it.
--
-- **THE DEFECT CLASS, and it is new in this session's tally.** The previous four (0313, the
-- `model_parameters` claim, 0314, 0317) were one shape: a negative claim from a search over one
-- layer of a three-layer system. This is not that. This is:
--
--     **A monolithic multi-key census statement fails on ONE key, forcing a retype of ALL of
--     them; an unrelated key comes back narrower than it went in; and its ALIAS keeps asserting
--     the old meaning after its predicate stopped supporting it.**
--
-- An alias is a claim about a predicate, and nothing in SQL checks it. The rewrite is where the
-- two came apart, and a rewrite forced by an error elsewhere is the moment of maximum risk
-- precisely because attention is on the part that failed loudly.
--
-- **The habits that would have caught it, in order of cost:**
--   (a) On a forced rewrite, diff the new statement against the old one KEY BY KEY. Ten seconds.
--   (b) Never let a count of zero stand on one predicate — a zero is the one result that is
--       equally consistent with "nothing is there" and "I asked wrong". Confirm it with a
--       DIFFERENT shape: `SELECT DISTINCT event_type ... LIMIT 50` would have printed
--       `arm.mate_latched` in the first screenful.
--   (c) Prefer several small statements to one nine-key `jsonb_build_object`. The convenience is
--       real; the blast radius of one syntax error is every key beside it.
--
-- ══ §2 WHAT IS ACTUALLY THERE ══════════════════════════════════════════════
--
-- Measured 2026-09-21 ~20:20 UTC (3:20 PM CT). `twin.ottoq_arm_advance_cycles` has been calling
-- `public.ottoq_record_event` per closed cycle all along, with `actor_type='ottoq_engine'`,
-- `actor_id='twin_charge_arm'`, and six event types:
--
--     arm.mate_started 739 · arm.mate_latched 709 · arm.demate_started 633
--     arm.demate_cleared 567 · arm.emergency_release 16 · arm.move_refused 14   = 2,678
--
-- Emission is roughly **two events per cycle** (a start plus its terminal outcome), not one:
-- on the runs present in both tables it reads 236 events / 118 cycles and 146 / 74. And it
-- covers **41 of the 43 runs** that survive in `ottoq_events`, including `c23de1b8` — the demo
-- run Chase was watching, 84 arm events spanning 18:00–18:26 UTC.
--
-- **So `0315` §3's conclusion — "the arms can never appear in the audit trail" — is exactly
-- backwards. They have never been absent from it.** And `0315` §3d's open question is closed the
-- same way: `twin.ottoq_arm_advance_cycles` writes `vehicles.robotic_tether_phase` in its own
-- body ('charging' on latch, 'clear' on cleared), so the renderer's binding IS populated while a
-- run ticks. That is read from the function source, not from a live sample, and is stated as
-- source evidence.
--
-- ══ §3 AND `0316`'s SIZING IS WRONG BY ~2,700x, IN BOTH FACTORS ════════════
--
-- `0316` multiplied 53,330 cycles by 8.6 KB an event to get 459 MB per run. **Both numbers are
-- wrong, and they are wrong in the same direction.**
--
-- **The unit cost.** 8.6 KB came from `pg_total_relation_size / count(*)`. Measured directly:
--
--     avg(pg_column_size(e.*)) over arm.* rows          =   743 bytes
--     avg(pg_column_size(e.*)) over all rows            =   937 bytes
--     avg over vehicle.state_changed (95,885 rows)      = 1,197 bytes
--
-- The 1,188 MB is **529 MB heap + 486 MB indexes** on a table with **13,095,089 lifetime inserts
-- against 16,526,607 deletes**. Dividing total relation size by live row count on a table like
-- that measures accumulated bloat and index overhead, not the cost of a row. It is the same
-- mistake in a different currency as the one §1 describes: a number whose NAME says "bytes per
-- event" while its DERIVATION says "bytes of disk per surviving row, including everything ever
-- deleted."
--
-- **The multiplier.** 53,330 was never a per-run figure. `twin.arm_cycles` holds 54,098 rows
-- across **1,414 distinct `sim_run_id`s**, oldest 08-12 — about **38 cycles per run**. A live
-- twin-depot run runs 74–165. `0316` took a cross-run accumulation and called it "for a single
-- run."
--
-- **The honest number: ~150–240 arm events per run at ~743 bytes ≈ 110–180 KB per run.** Against
-- 459 MB. And it is not a projection, because those rows are already being written.
--
-- ══ §4 WHY `arm_cycles` HELD 1,414 RUNS WHILE `ottoq_events` HELD 43 ════════
--
-- This is the part with a real defect behind it, and it is the one thing `0315` got directionally
-- right for the wrong reason. `public.ottoq_events` is `class='engine'` in
-- `ottoq_run_scope_registry`, so the demo purge clears it. **`twin.arm_cycles` is in the registry
-- under no class at all.** Neither is `twin.arm_registrations`. Nothing purges them, so they have
-- accumulated since 08-12:
--
--     twin.arm_cycles         1,608 rows for live runs  ·  52,490 orphaned  (97%)
--     twin.arm_registrations    870 rows for live runs  ·  27,971 orphaned  (97%)
--
-- 1,373 of 1,414 `sim_run_id`s in `arm_cycles` name a run that no longer exists. **So the
-- "53,862 cycles versus zero events" contrast in `0315` §3 was a durable-but-unclassified table
-- measured against a purged one — CLAUDE.md's "cite the run, never the table", both sides at
-- once.** The predicate bug of §1 produced the zero; this produced the 53,862. Neither side of
-- that comparison was a fact about a run.
--
-- ══ §5 THE GATE THAT EXISTS TO CATCH THIS CANNOT SEE THE `twin` SCHEMA ═════
--
-- `public.ottoq_check_run_scope_registry()` check (a) is titled, in its own source, *"a
-- run-scoped column that nobody has classified."* Its predicate:
--
--     AND c.table_schema IN ('public','proof_0015')
--
-- **`twin` is not in the list, and `ottoq` is not either.** The function returns `[]` today —
-- clean — while two unclassified run-scoped tables sit in `twin`. Widened to every non-system
-- schema the same check returns **exactly two rows, both of them the arm tables**, so this is a
-- narrow, closeable hole and not a flood. Fixed by `0408`.
--
-- Check (a)'s severity is `warn`, and `ottoq_purge_prior_runs` raises only on `block`
-- (it counts `severity='block'` and merely collects the warns), so widening the schema list
-- cannot refuse a demo run. That was verified in the purge's own source before touching it.
--
-- **The classification itself is NOT in `0408`, deliberately.** Registering either arm table as
-- `engine` trips check (b2), which demands an FK to `ottoq_sim_runs` — and **neither table has
-- any foreign key at all**, so the FK would have to be added, and it cannot be added over 52,490
-- and 27,971 orphan rows without deleting them first. That is an 80,461-row deletion, and it is
-- Chase's call, not a hygiene migration. `evidence` is the non-destructive alternative and is
-- defensible (0340's doctrine: the ledger answering a product question should outlive its run) —
-- but it would register as durable evidence a table whose run link is gone for 97% of its rows,
-- which is "no number ships without a run ID" failing on its own substrate. **Both options are
-- written up and neither is taken here.** What `0408` does instead is make the gate SAY SO on
-- every purge, so it cannot be forgotten a second time.
--
-- ══ §6 A LIVE DEFECT FOUND WHILE CHECKING THIS, AND IT IS MINE FROM TODAY ══
--
-- `public.ottoq_evidence_join_loss()` **does not run.** Called today:
--
--     ERROR: 42883: operator does not exist: uuid = bigint
--     QUERY: ... WHERE sr.sim_run_id = t.promotion_id ... FROM public.ottoq_dial_promotion_ledger t
--
-- The function loops over every `class='evidence'` row in the registry and joins that row's
-- column to `ottoq_sim_runs.sim_run_id`. `db/migrations/0403` — mine, this afternoon — created
-- `ottoq_dial_promotion_ledger` and registered its **bigint surrogate primary key**
-- `promotion_id` as evidence. A surrogate key is not a run reference, the join is a type error,
-- and the whole check dies on the first such row. So one of this repo's evidence-integrity
-- checks has been dead since `0403` landed, and nothing noticed because nothing calls it on a
-- schedule.
--
-- **The obvious fix is the wrong one, and that is the interesting part.** `0344` fixed the
-- identical per-column/per-table confusion in check (b2) by narrowing it to the four run-key
-- column names (`sim_run_id`, `run_id`, `owning_sim_run_id`, `source_run_id`). Copying that here
-- would break the check in a quieter way, because the evidence rows on non-standard names are:
--
--     public.ottoq_determinism_verdict_ledger.arm_a_run   uuid    <- a genuine run reference
--     public.ottoq_determinism_verdict_ledger.arm_b_run   uuid    <- a genuine run reference
--     public.ottoq_dial_promotion_ledger.promotion_id     bigint  <- not a run reference
--
-- The name list would silently stop watching the determinism ledger's two arm columns — which
-- are precisely the columns whose join loss matters most. **The discriminator is the TYPE, not
-- the name:** `ottoq_sim_runs.sim_run_id` is `uuid`, so a non-uuid column cannot reference it,
-- and a uuid column called `arm_a_run` can. `0408` filters on `uuid` and keeps all three
-- correctly classified.
--
-- **The general lesson, which is why this sits in a retraction file rather than a fix comment:**
-- `0344` fixed a registry consumer that confused per-column classification with per-table
-- meaning, and left its sibling consumer with the same confusion. **When you fix that class of
-- bug in one reader of a shared registry, census the other readers in the same change.** Four
-- functions read `ottoq_run_scope_registry`; `0344` touched one.
--
-- ══ §7 THE ONE THING FROM `0315` §3 THAT SURVIVES AS A REAL GAP ════════════
--
-- **None of the six `arm.*` types is registered in `ottoq_event_types_catalog`** (139 rows).
-- `ottoq_record_event` does not validate against the catalog, so emission works regardless —
-- which is exactly why the omission was invisible for as long as it was. Phase C7 step 2 requires
-- a canonical event vocabulary with additions "registered properly", so this is a genuine, small,
-- in-scope defect. `0408` registers all six.
--
-- And one unexercised branch worth recording before anybody trusts it: across 54,098 cycles,
-- outcome `restaged` = **0** and `failed` = **0**. `twin.ottoq_arm_advance_cycles` has code paths
-- for both (`arm.mate_restage_required`, `arm.mate_failed`) and neither has ever run. Two of the
-- six emitted types are therefore untested in production, and the two event types the function
-- can emit that have NEVER appeared are exactly those. Not a defect; a coverage fact.
--
-- ══ §8 WHAT THIS MEANS FOR THE TASK IT WAS BLOCKING ════════════════════════
--
-- Task "emit arm cycle events into ottoq_events" is **already done, by someone earlier, and the
-- work left is the catalog rows in §7.** There is no summary-versus-individual design decision to
-- make, no 459 MB to avoid, no `forces_recert` change to schedule. `0316` proposed a 65x
-- reduction against a cost that was never 459 MB, for a feature that already shipped. It is
-- retracted in full and its recommendation must not be implemented — building it would ADD the
-- per-tick summary events it was invented to substitute for.
--
-- ══ §9 WHAT THE REVIVED CHECK SAID THE MOMENT IT COULD SPEAK (added after `0409`) ═══
--
-- §6's fix (`0408`) let `ottoq_evidence_join_loss_now` run for the first time since `0403`, and its
-- first reading was 83–98% join loss across every evidence ledger. **My first instinct was that
-- the check was pointed at the wrong parent and should be repointed at `ottoq_run_archives`.
-- `0380`'s own COMMENT refutes that** — the check's documented question is literally *"how many
-- rows a naive JOIN to `ottoq_sim_runs` drops"*, so 98.2% is the correct answer to the question it
-- asks, and repointing it would have deleted the warning. **I came within one migration of
-- "fixing" a working check, which is the mistake `0317` was about, arriving from the opposite
-- direction.**
--
-- What was actually missing is a second column, added by `0409`: of those orphans, how many are
-- still attributable through `ottoq_run_archives` (the durable reproducibility key, 1,567 runs)
-- rather than `ottoq_sim_runs` (engine-class, 49 rows). Measured immediately after:
--
--     table                                total  orphaned  join_loss  recoverable  UNATTRIBUTABLE
--     ottoq_model_call_ledger              8,498     8,345     98.20%        7,928             417
--     ottoq_ab_runs                           91        91    100.00%           20              71
--     ottoq_proposer_fire_log               1,845     1,768     95.83%        1,765               3
--     ottoq_proposal_disposition_ledger    20,397    16,856     82.64%       16,856               0
--     ottoq_site_power_excursion_ledger     1,306     1,259     96.40%        1,259               0
--     ottoq_determinism_verdict_ledger         79        56     70.89%           56               0
--
-- **And the ranking inverts.** On `join_loss_pct` the disposition ledger (82.64%) looks healthier
-- than `ottoq_ab_runs` (100%) by seventeen points. On real loss the disposition ledger is at
-- **zero** and `ottoq_ab_runs` has lost the run identity of **71 of its 91 rows, 78%** — the worst
-- in the database by a wide margin, and the only table where the alarming number was
-- understated. The cuOpt ledger that `SOLVER_STATE.md` §13 quotes reads 98.20% join loss and
-- **4.9% actual loss**; "98% of the cuOpt evidence cannot be tied to a run" would have been a
-- false retraction of a correct document.
--
-- **So quote `rows_unattributable`, never `join_loss_pct`.** The first is evidence loss; the second
-- is a warning about how you write your JOIN. `db/checks/0275` reads this view and was written
-- before the distinction existed.
--
-- `ottoq_ab_runs`'s 71 lost rows are noted and not chased here. It is the well-shaped empty
-- instrument of Phase C5 (`db/checks/0145`: 68 rows, one policy, one seed, no writer), so its
-- provenance loss costs nothing today — but C5 must not build on those 91 rows believing they
-- carry run IDs. Seventy-one of them do not.

\echo '=== 0318 §1 — the arm events that two files said did not exist ==='
SELECT event_type, count(*) AS n,
       count(DISTINCT sim_run_id) AS runs,
       round(avg(pg_column_size(e.*))) AS avg_bytes
  FROM public.ottoq_events e
 WHERE event_type LIKE 'arm.%'
 GROUP BY event_type ORDER BY n DESC;
-- EXPECT six types and a non-zero total. A zero here means the rows were purged with their
-- runs, which is correct behaviour for a class='engine' table and is NOT evidence of §1's
-- claim — re-read the derivation, not this count.

\echo '=== 0318 §2 — the predicate that produced the zero, run side by side ==='
SELECT (SELECT count(*) FROM public.ottoq_events
         WHERE event_type ILIKE '%tether%' OR event_type ILIKE '%arm%'
            OR event_type ILIKE '%mate%')                       AS predicate_as_written,
       (SELECT count(*) FROM public.ottoq_events
         WHERE event_type ILIKE '%tether%'
            OR event_type ILIKE '%robotic%')                    AS predicate_as_shipped;
-- The second column is what `0315` §3 and all of `0316` were built on. It cannot be non-zero:
-- no event type in this database contains 'tether' or 'robotic'.

\echo '=== 0318 §3 — the two factors that made 459 MB, measured properly ==='
SELECT pg_size_pretty(pg_relation_size('public.ottoq_events'))        AS heap,
       pg_size_pretty(pg_indexes_size('public.ottoq_events'))         AS indexes,
       (SELECT round(avg(pg_column_size(e.*))) FROM public.ottoq_events e) AS avg_row_bytes,
       round(pg_total_relation_size('public.ottoq_events')
             / NULLIF((SELECT count(*) FROM public.ottoq_events),0) / 1024.0, 1) AS the_8_6_kb_figure,
       (SELECT n_tup_ins FROM pg_stat_user_tables
         WHERE schemaname='public' AND relname='ottoq_events')        AS lifetime_inserts,
       (SELECT n_tup_del FROM pg_stat_user_tables
         WHERE schemaname='public' AND relname='ottoq_events')        AS lifetime_deletes;
-- `the_8_6_kb_figure` is `0316`'s number reproduced from its own formula, beside the ~937 bytes
-- a row actually occupies. The gap is index size plus the bloat that 13M inserts against 16.5M
-- deletes leaves behind.

\echo '=== 0318 §4 — arm_cycles is a 1,414-run accumulation, not one run ==='
SELECT count(*)                                                AS rows_total,
       count(DISTINCT sim_run_id)                              AS runs_represented,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                                       WHERE r.sim_run_id = c.sim_run_id))  AS rows_for_live_runs,
       count(*) FILTER (WHERE sim_run_id IS NULL
                           OR NOT EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                                           WHERE r.sim_run_id = c.sim_run_id)) AS rows_orphaned,
       to_char(min(started_at),'MM-DD HH24:MI')                AS oldest
  FROM twin.arm_cycles c;
-- EXPECT ~97% orphaned. This is the table `0316` divided by nothing and called "a single run".

\echo '=== 0318 §5 — every run-scoped column the registry does not classify ==='
SELECT c.table_schema, c.table_name, c.column_name,
       (c.table_schema IN ('public','proof_0015')) AS visible_to_check_a_today
  FROM information_schema.columns c
  JOIN pg_class rc ON rc.relname = c.table_name
  JOIN pg_namespace nn ON nn.oid = rc.relnamespace AND nn.nspname = c.table_schema
 WHERE rc.relkind = 'r'
   AND c.table_schema IN ('public','ottoq','twin','proof_0015')
   AND c.column_name IN ('sim_run_id','run_id','owning_sim_run_id','source_run_id')
   AND NOT EXISTS (SELECT 1 FROM public.ottoq_run_scope_registry g
                    WHERE g.table_schema = c.table_schema
                      AND g.table_name   = c.table_name
                      AND g.column_name  = c.column_name)
 ORDER BY 1,2;
-- Before 0408: two rows, both twin.arm_*, both with visible_to_check_a_today = false — which is
-- why ottoq_check_run_scope_registry() returns clean while they sit unclassified.
-- After 0408: the same two rows, now reported by the gate itself as warns.

\echo '=== 0318 §6 — the evidence-integrity check that has been dead since 0403 ==='
SELECT g.table_schema||'.'||g.table_name AS tbl, g.column_name,
       c.data_type,
       (c.data_type = 'uuid') AS can_join_to_sim_run_id
  FROM public.ottoq_run_scope_registry g
  JOIN information_schema.columns c
    ON c.table_schema=g.table_schema AND c.table_name=g.table_name AND c.column_name=g.column_name
 WHERE g.class='evidence'
   AND g.column_name NOT IN ('sim_run_id','run_id','owning_sim_run_id','source_run_id')
 ORDER BY 1,2;
-- EXPECT three rows: two uuid columns on ottoq_determinism_verdict_ledger that a name-based fix
-- would wrongly drop, and one bigint on ottoq_dial_promotion_ledger that is what raises 42883.

\echo '=== 0318 §7 — the six emitted arm types against the catalog ==='
SELECT e.event_type,
       (k.event_type IS NOT NULL) AS in_catalog,
       count(*) AS emitted
  FROM public.ottoq_events e
  LEFT JOIN public.ottoq_event_types_catalog k ON k.event_type = e.event_type
 WHERE e.event_type LIKE 'arm.%'
 GROUP BY e.event_type, k.event_type ORDER BY 1;
-- Before 0408: in_catalog false for all six. After 0408: true for all six.

\echo '=== 0318 §8 — the two arm outcomes that have never once happened ==='
SELECT outcome, count(*) AS cycles
  FROM twin.arm_cycles
 GROUP BY outcome
 ORDER BY count(*) DESC;
-- `restaged` and `failed` are absent. twin.ottoq_arm_advance_cycles emits
-- arm.mate_restage_required and arm.mate_failed on those branches, so two of its six event
-- types are unexercised. Coverage fact, not a defect.

\echo '=== 0318 §9 — join loss versus actual evidence loss, and they rank differently ==='
SELECT table_name, rows_total, rows_orphaned, join_loss_pct,
       rows_recoverable_via_archive AS recoverable_via_archive,
       rows_unattributable          AS actually_lost
  FROM public.ottoq_evidence_join_loss_now
 ORDER BY rows_unattributable DESC, rows_orphaned DESC;
-- `join_loss_pct` is how much a naive JOIN to ottoq_sim_runs destroys (the 0380 warning).
-- `actually_lost` is how many rows name a run that neither ottoq_sim_runs NOR ottoq_run_archives
-- remembers. Only the second justifies alarm. At 0409: ottoq_ab_runs is the worst table in the
-- database at 71 of 91 lost, while ottoq_proposal_disposition_ledger reads 82.64% join loss and
-- has lost nothing at all.
