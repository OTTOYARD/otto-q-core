-- 0336  **`ottoq_stall_bookings` is "the calendar" — CLAUDE.md 2.3's word for it, and `db/checks/0127`
--       measured it as 53% of every disk block this database has ever read. It cannot say who made
--       20,225 of its 31,730 twin-depot entries. 63.7% carry `source IS NULL`.**
--
--       Found while trying to answer a one-join question from `0335` §6: which caller books a service
--       bay for a service performed at the vehicle? **The answer is not in the data**, because 94% of
--       `purpose='service'` bookings are unattributed.
--
--       Measured 2026-09-22 ~14:1x UTC (09:1x CT), twin depot only per rule 8.
--
-- ══ §1 THE CALENDAR'S PROVENANCE, BY PURPOSE ═════════════════════════════════
--
--     purpose          bookings   source IS NULL   % unattributed   distinct sources
--     --------------  ---------  ---------------  ---------------  ----------------
--     temp_hold           8,190            8,190        **100.0%**            **0**
--     perimeter_hold      3,527            3,527        **100.0%**            **0**
--     service             2,836            2,666           94.0%                 6
--     detail                917              755           82.3%                 6
--     wash                2,272            1,800           79.2%                 6
--     charge_l2           7,981            2,989           37.5%                 6
--     charge_dcfc         1,714              298           17.4%                 5
--     inspect             3,837                0         **0.0%**                1
--     staging               456                0         **0.0%**                1
--     ---------------------------------------------------------------------------
--     ALL                31,730           20,225        **63.7%**               16
--
-- **The spread is the finding, not the total.** Two purposes are fully attributed, two are attributed
-- zero percent of the time with not one named source ever, and the charge paths sit in between. This is
-- not a table with a nullable column nobody bothered to fill — it is a table where **some writers
-- instrument themselves and others never have**, and the ones that never have are the holds: `temp_hold`
-- and `perimeter_hold`, 11,717 rows between them, 37% of the whole calendar.
--
-- ══ §2 WHY THIS BLOCKS A FIX THAT IS OTHERWISE READY ═════════════════════════
--
-- `0335` §6 narrowed the walkaround's bay bookings to "one of five callers of
-- `ottoq_record_enacted_booking`, none of which reads `lane_stalls`", and named the next step as one
-- join on `source`. Run:
--
--     source                            bookings   first_at     last_at
--     -------------------------------  ---------  -----------  -----------
--     **(null)**                          **2,603**   08-30        today
--     bay_reconcile_displace                    90   today        today
--     bay_reservation_activated                 22   today        today
--     bay_reservation_activated_early           20   today        today
--     service_sequencing                        18   08-30        today
--     needs_card                                10   today        today
--
-- **94% of the rows name nobody**, and the named sources are all small and all recent — four of the six
-- first appear today. So the instrumentation was added to the newer paths and the dominant writer has
-- never had it. **The caller cannot be identified from the data**, which is why `0335` §6's "one join"
-- does not close and this check exists instead of a migration.
--
-- ══ §3 WHAT THIS IS AND IS NOT ═══════════════════════════════════════════════
--
-- **It is not a data-loss bug.** Every booking is present, correct, and enforced by the EXCLUDE
-- constraint; `0145`'s double-booking impossibility is untouched. What is missing is *attribution*.
--
-- **It is the booking-table analogue of the rule this company runs on.** CLAUDE.md's credibility rule is
-- *"no number ships without a run ID."* Every booking already carries `sim_run_id`, so that rule is
-- honoured. **What has no analogue is "no booking ships without a writer"**, and the cost is exactly
-- what `0335` hit: a live, current, 2,754-row behaviour on the depot's scarcest resource, and no way to
-- ask the table which code did it.
--
-- **And the comparison that makes the case.** `ottoq_model_call_ledger` (`0340`) records one row per
-- external model call *with its provider and its source kind*, and that is why `0334` could partition a
-- three-day outage out of a lifetime average in one query this morning. The calendar has no such
-- column filled. The instrument that made this morning's best retraction possible is the one the most
-- load-bearing table lacks.
--
-- ══ §4 WHAT TO DO, AND THE ORDER ═════════════════════════════════════════════
--
--   1. **Make `source` NOT NULL at the writer, not at the column.** A `NOT NULL` constraint on a table
--      with 20,225 existing nulls forces a backfill with a value nobody can verify, which is worse than
--      the gap. The right move is to give `ottoq_record_enacted_booking` a required `p_source` and let
--      its five callers name themselves — the two 100%-unattributed purposes (`temp_hold`,
--      `perimeter_hold`) go through `ottoq.ottoq_book_hold_stall`, which is a separate and equally
--      unattributed path (`0383` quotes its purpose-picking `CASE`).
--   2. **Then re-run `0335` §6's join**, which becomes answerable, and fix the walkaround booking at
--      whichever caller it names.
--   3. **Do not backfill the 20,225.** They are unattributable by construction; a guessed `source` is a
--      number without a run ID, which is the thing this repo exists not to do. Leave them NULL and let
--      the NULL count itself become the migration's own progress metric.
--
-- **`forces_recert`: almost certainly TRUE** for step 1 — `bookings` is one of the fourteen atoms and
-- adding a column value changes what a cert arm writes. That is a reason to sequence it, not to skip it.
--
-- ══ §5 AND THE ONE THING NOT MEASURED HERE ═══════════════════════════════════
--
-- Whether `source` is *correct* where it is present. This check counts NULLs; it does not verify that
-- `bay_reconcile_displace` rows were actually written by `ottoq_reconcile_displace_stale_claim`. Given
-- `0331` (an actor inferred from whether a run is live) and `0333` (a stall resolved for work that
-- occupies none), a populated provenance column is worth exactly as much as its verification, and that
-- verification has not been done.

\echo '=== 0336 §1 — the calendar cannot say who made two thirds of its own entries ==='
SELECT COALESCE(b.purpose,'(null)') AS purpose,
       count(*) AS bookings,
       count(*) FILTER (WHERE b.source IS NULL) AS source_is_null,
       round(100.0*count(*) FILTER (WHERE b.source IS NULL)/count(*),1) AS pct_unattributed,
       count(DISTINCT b.source) AS distinct_sources
  FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id=b.stall_id
 WHERE s.depot_id='11111111-1111-1111-1111-111111111111'
 GROUP BY 1
UNION ALL
SELECT 'ALL PURPOSES', count(*), count(*) FILTER (WHERE b.source IS NULL),
       round(100.0*count(*) FILTER (WHERE b.source IS NULL)/count(*),1), count(DISTINCT b.source)
  FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id=b.stall_id
 WHERE s.depot_id='11111111-1111-1111-1111-111111111111'
 ORDER BY bookings DESC;
-- 20,225 of 31,730 = 63.7%. temp_hold and perimeter_hold are 100% unattributed with ZERO distinct
-- sources ever; inspect and staging are 100% attributed. The spread is the finding.

\echo '=== 0336 §2 — and that is why 0335 §6s one join does not close ==='
SELECT COALESCE(b.source,'(null)') AS source, count(*) AS bookings,
       count(DISTINCT b.sim_run_id) AS runs,
       min(b.booked_at) AS first_at, max(b.booked_at) AS last_at
  FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id=b.stall_id
 WHERE s.depot_id='11111111-1111-1111-1111-111111111111' AND s.stall_type='service_bay'
   AND b.need_atom='perimeter_walkaround'
 GROUP BY 1 ORDER BY bookings DESC;
-- 2,603 of 2,763 name nobody. The named sources are small and four of the six first appear today, so
-- the newer paths were instrumented and the dominant writer never was.

\echo '=== 0336 §3 — the calendar against the ledger that made this mornings retraction possible ==='
SELECT 'ottoq_stall_bookings (the calendar)' AS table_name,
       (SELECT count(*) FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id=b.stall_id
         WHERE s.depot_id='11111111-1111-1111-1111-111111111111') AS rows_twin_depot,
       (SELECT round(100.0*count(*) FILTER (WHERE b.source IS NULL)/NULLIF(count(*),0),1)
          FROM public.ottoq_stall_bookings b JOIN public.stalls s ON s.id=b.stall_id
         WHERE s.depot_id='11111111-1111-1111-1111-111111111111') AS pct_unattributed
UNION ALL
SELECT 'ottoq_model_call_ledger (0340)',
       (SELECT count(*) FROM public.ottoq_model_call_ledger),
       (SELECT round(100.0*count(*) FILTER (WHERE provider IS NULL OR source_kind IS NULL)
                     /NULLIF(count(*),0),1) FROM public.ottoq_model_call_ledger);
-- The ledger knows its provider and its source kind on every row, which is why 0334 could partition a
-- three-day outage out of a lifetime average in one query. The calendar cannot.

-- ══════════════════════════════════════════════════════════════════════════════
-- §6  THE SAME SHAPE ON A SECOND TABLE: G121 IS UNOBSERVABLE AFTER THE FACT
--     (appended same session, while the recert sweep finished its last column)
-- ══════════════════════════════════════════════════════════════════════════════
--
-- **G121 is defined by a DISAGREEMENT between three fields** (`0326` §2): a stall carrying
-- `status='available'` **together with** a live `current_vehicle_id` and `reserved_by`. Three DCFC
-- stalls — the depot's scarcest resource — held by nobody.
--
-- **Two observations, and the second is the point.**
--
-- **(a) It is not present right now, and that fact is worth nothing.** All 158 twin-depot stalls read
-- `available` with both pointers NULL. That is the clean between-runs state: a determinism pair had just
-- reset the fleet. **Checking a live-run defect on an idle depot is not a test**, it is the inverse of
-- the error `0334` caught this morning — there I quoted a fixed outage as current, here I could quote an
-- idle depot as fixed. Same failure, opposite sign: not checking what state the measurement was taken in.
--
-- **(b) And it cannot be checked historically either, because the event stream does not carry the
-- fields that define it.** `stall.state_changed` has **83,456 rows**, and every one has exactly one
-- payload key:
--
--     payload_keys        ["diff"]
--     diff contents       {"status": {"from": "occupied", "to": "available"}}
--     new_has_vehicle_ptr  (no `new` block at all)
--     new_has_reserved_by  (no `new` block at all)
--
-- **The stall trigger records the status transition and neither pointer.** So the one combination that
-- defines G121 is structurally invisible in the archive. Contrast `vehicle.state_changed`, whose diff
-- carries SoC, `target_soc`, `config` and `last_state_change` — `0329` reconstructed a whole
-- contamination from it. The vehicle trigger diffs broadly; the stall trigger diffs one column.
--
-- **That is why G121 has stayed open.** Every look either lands on a live run and catches it (as `0326`
-- did) or lands between runs and sees nothing — and there is no ledger to consult in between. It is not
-- a hard defect to fix; it is a defect nobody can *watch*.
--
-- ══ WHAT THIS ADDS TO §4's FIX ORDER ═════════════════════════════════════════
--
-- Same family as this check's headline, one table over: **`ottoq_stall_bookings` cannot say WHO, and
-- `stall.state_changed` cannot say WHAT ELSE WAS TRUE.** Both are questions the table was never asked to
-- answer and both block a live defect.
--
--   * **Add `current_vehicle_id` and `reserved_by` to the stall trigger's diff.** Cheap, and it turns
--     G121 from "catch it live or not at all" into a countable rate — the same move `0340` made for
--     model calls, which is what let `0334` partition an outage this morning.
--   * **Then G121's fix can be verified**, which today it cannot: there is no before to compare an after
--     against.
--
-- **`forces_recert` TRUE** — `events` is one of the fourteen atoms and this changes what a cert arm
-- writes. Sequence it with the `p_source` change in §4; they are one theme and one sweep.

\echo '=== 0336 §6a — G121 absent right now, on an IDLE depot. This is not a test ==='
SELECT s.stall_type, s.status,
       (s.current_vehicle_id IS NOT NULL) AS has_vehicle_ptr,
       (s.reserved_by IS NOT NULL)        AS has_reserved_by,
       count(*) AS stalls
  FROM public.stalls s
 WHERE s.depot_id='11111111-1111-1111-1111-111111111111'
 GROUP BY 1,2,3,4
 ORDER BY (s.status='available' AND s.current_vehicle_id IS NOT NULL) DESC, stalls DESC;
-- All 158 available, both pointers NULL: the between-runs state after a pair's fleet reset. An idle
-- depot cannot falsify a live-run defect, and reading it as "fixed" is 0334's error with the sign
-- reversed.

\echo '=== 0336 §6b — and the archive cannot answer either: the diff carries only status ==='
SELECT (SELECT jsonb_agg(DISTINCT k) FROM jsonb_object_keys(e.payload) k) AS payload_keys,
       (e.payload->'diff' ? 'status')             AS diff_has_status,
       (e.payload->'diff' ? 'current_vehicle_id') AS diff_has_vehicle_ptr,
       (e.payload->'diff' ? 'reserved_by')        AS diff_has_reserved_by,
       count(*) AS n
  FROM public.ottoq_events e
 WHERE e.event_type='stall.state_changed'
 GROUP BY 1,2,3,4 ORDER BY n DESC;
-- 83,456 rows, one payload key, status only. The combination that DEFINES G121 is structurally absent
-- from the archive, so the defect can be caught live or not at all -- which is why it has stayed open.
