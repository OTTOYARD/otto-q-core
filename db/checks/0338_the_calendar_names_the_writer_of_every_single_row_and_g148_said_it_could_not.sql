-- 0338  **RETRACTION OF MY OWN `0336`/G148, two hours old. Its headline — "the calendar cannot say who
--       made 20,225 of its entries" — is FALSE. `booked_by IS NULL` on ZERO of 36,268 twin-depot
--       bookings. The calendar names a writer for every single row.**
--
--       `ottoq_stall_bookings` carries **FIVE** provenance columns and I measured the only sparse one.
--       Coverage on the twin depot's 36,268 bookings: `booked_by` **0 NULL** (and `NOT NULL` in the
--       schema, so it cannot be otherwise), `why` **0 NULL** with **23,118 distinct** per-booking English
--       explanations, `need_source` **0 NULL**, `leg_source` **0 NULL** — and `source` 63.7% NULL. I read
--       `source`, found it sparse, and wrote that the table was unattributed.
--
--       **And the retraction moves the FIX to a different function**, which is why it matters more than
--       the wording: `0336` §4 prescribed *"give `ottoq_record_enacted_booking` a required `p_source`"*.
--       That function **already has `p_source`, and it already works on 12,868 of 12,868 rows.**
--
--       Measured 2026-09-22 ~15:1x UTC (10:1x CT), twin depot only (rule 8).
--
-- ══ §1 THE TWO COLUMNS, AND WHY EITHER ALONE MISLEADS ════════════════════════
--
--     booked_by          rows     source NULL   distinct sources
--     ---------------   ------   ------------   ----------------
--     otto_q            22,989   22,800 (99.2%)                6
--     otto_q_enacted    12,868        0 (0.0%)               **16**
--     otto_q_reaction      411      321 (78.1%)                1
--     ---------------   ------   ------------   ----------------
--     TOTAL             36,268   23,121 (63.7%)               16     booked_by NULL: **0**
--
-- `booked_by` is **complete and coarse** — `NOT NULL`, three values, so it answers *"which code path"*
-- and nothing finer. `source` is **fine and sparse** — sixteen values naming the decision (`cuopt`,
-- `forward_lex`, `inspect_seam`, `gate_intake_staging`, `reservation_broken`, `bay_reconcile_displace`, …)
-- — and absent on two thirds of rows. **And `why` is both complete AND fine**: 0 NULL, 23,118 distinct
-- values, one per booking, in English, naming the stall, the window, the need, the need's provenance and
-- the leg. It is the column that actually answers "who put this vehicle in this space and why", and
-- `0336` never looked at it.
--
-- **So the honest statement is not that the calendar is unattributed. It is that the calendar's
-- attribution has two resolutions, and the high-resolution one covers a third of it.** `0336`'s
-- by-purpose table was arithmetically correct in every cell and answered a question about `source`
-- while its prose answered a question about the table.
--
-- ══ §2 THE GAP IS EXACTLY ONE FUNCTION, AND IT IS NOT THE ONE `0336` NAMED ════
--
-- The `booked_by` split above is not three subsystems, it is **three code paths**, and it maps onto the
-- writers one-to-one:
--
--   * **`otto_q_enacted` — 12,868 rows, 0 NULL, 16 sources.** This is the path through
--     `ottoq.ottoq_record_enacted_booking`, whose signature already ends
--     `p_purpose text DEFAULT NULL, p_source text DEFAULT 'unknown'`. **It is the exemplar, not the
--     defect.** Every row it writes names its decision path.
--   * **`otto_q` — 22,989 rows, 99.2% NULL.** This is the direct path through
--     `ottoq.ottoq_book_stall`, and the cause is structural rather than sloppy: **that function has no
--     `p_source` parameter at all.** Its signature is
--     `(p_sim_run_id, p_stall_id, p_vehicle_id, p_purpose, p_from, p_to, p_visit_id DEFAULT NULL,
--       p_leg_id DEFAULT NULL, p_booked_by DEFAULT 'otto_q')`,
--     and its INSERT column list is
--     `(sim_run_id, stall_id, vehicle_id, visit_id, leg_id, purpose, during, booked_by)`.
--     **`source` is not in it.** A caller of `ottoq_book_stall` cannot name itself even if it wants to.
--   * **`otto_q_reaction` — 411 rows**, `ottoq.ottoq_react_to_refusals`, same direct path.
--
-- `ottoq.ottoq_book_stall` is **the only direct `INSERT INTO ottoq_stall_bookings` in the database** —
-- checked across all 3 schemas — so every booking is written by it, and `ottoq_record_enacted_booking`
-- is a wrapper that calls it and then stamps `source` in a follow-up UPDATE.
--
-- **THEREFORE THE FIX IS: give `ottoq.ottoq_book_stall` a `p_source`, put `source` in its INSERT column
-- list, and let its four callers name themselves** — `ottoq_find_and_book_stall`,
-- `ottoq_react_to_refusals`, `public.ottoq_decide_tick`, and `ottoq_record_enacted_booking` (which
-- passes through what it already receives, so its follow-up UPDATE can go away).
--
-- `0336` §4's two prohibitions SURVIVE unchanged and are the reason not to take the shortcut:
-- **no `NOT NULL`** on a column with 23,121 existing nulls, and **no backfill** — a guessed `source` is
-- a number without a run ID.
--
-- ══ §3 WHAT G148 GOT RIGHT, KEPT SO THE RETRACTION IS NOT OVER-CORRECTED ═════
--
--   1. **The spread is the finding, not the total.** Still true, and sharper now that it has a cause:
--      `temp_hold` (9,426) and `perimeter_hold` (3,917) are 100% `source`-NULL with ZERO distinct
--      sources ever recorded, because holds are booked exclusively through the direct path. `inspect`
--      (4,275) and `staging` (506) are 0% NULL because they go through the enacted path.
--   2. ~~**`0335` §6 is still not answerable.**~~ **WITHDRAWN inside this same file — see §5.** I wrote
--      this clause before running `why`, on the assumption that `source`'s sparsity bounded what the
--      table could answer. It does not: `why` answers `0335` §6 outright, in English, on 100% of rows.
--      **The same error twice in one file is the point of §4** — the fix is to list the columns, not to
--      reason about the one you happen to have measured.
--   3. **The comparison to `ottoq_model_call_ledger` holds.** It knows provider and source kind on 100%
--      of rows at full resolution, which is why `0334` could partition a three-day outage out of a
--      lifetime average in one query.
--   4. **Not measured, and still not:** whether `source` is CORRECT where present.
--
-- ══ §4 THE LESSON, AND IT IS A NEW SHAPE FOR THIS PAGE ═══════════════════════
--
-- Every previous instance in this family was *a real measurement read as answering a question it was not
-- about* — a duration read as a wait (`0332`), a value read as an outcome (`0337`), a rate over the
-- wrong denominator (`0413`), a sim date read against a real calendar (`0337` §5, my own, today).
--
-- **This one is different: I measured the right thing on the wrong COLUMN, and never asked whether a
-- second column answered the same question.** `0336` ran nine queries about `source` and not one
-- `\d ottoq_stall_bookings`. The table's own column list contained the refutation the whole time.
--
-- **THE STANDING TEST, and it is cheaper than any of the nine queries: before reporting that a table
-- cannot answer a question, list its columns and confirm no other column answers it.** For a
-- provenance claim specifically, a table that has been instrumented twice over its life will have two
-- provenance columns with different coverage, and reading either alone gives a confident wrong answer.
--
-- **And note which direction this one cut.** `0337` §5's error flattered nothing — it invented a defect
-- that did not exist. This one *understated* our own instrumentation: the enacted path has been at 100%
-- provenance the whole time and I reported the calendar as two-thirds blind. Both are failures of the
-- same discipline, and the flattering direction is the one to check hardest — but the unflattering
-- direction still ships a wrong number.

\echo '=== 0338 §1 — booked_by is NULL on ZERO rows; source is NULL on 63.7% ==='
WITH b AS (
  SELECT sb.purpose, sb.source, sb.booked_by
    FROM public.ottoq_stall_bookings sb
    JOIN public.stalls s ON s.id = sb.stall_id
   WHERE s.depot_id='11111111-1111-1111-1111-111111111111'
)
SELECT purpose, count(*) AS bookings,
       count(*) FILTER (WHERE source IS NULL)    AS source_null,
       count(*) FILTER (WHERE booked_by IS NULL) AS booked_by_null,
       count(DISTINCT source)    AS distinct_sources,
       count(DISTINCT booked_by) AS distinct_booked_by
  FROM b GROUP BY 1
 UNION ALL
SELECT '== TOTAL ==', count(*), count(*) FILTER (WHERE source IS NULL),
       count(*) FILTER (WHERE booked_by IS NULL),
       count(DISTINCT source), count(DISTINCT booked_by) FROM b
 ORDER BY 2 DESC;
-- booked_by_null is 0 in EVERY row of this table, including the total. G148's headline claim that the
-- calendar "cannot say who made 20,225 of its entries" is false: it says so on all 36,268.

\echo '=== 0338 §1b — and THREE more provenance columns, all at 100% coverage ==='
WITH b AS (
  SELECT sb.why, sb.need_source, sb.leg_source
    FROM public.ottoq_stall_bookings sb
    JOIN public.stalls s ON s.id = sb.stall_id
   WHERE s.depot_id='11111111-1111-1111-1111-111111111111'
)
SELECT count(*) AS bookings,
       count(*) FILTER (WHERE why IS NULL)         AS why_null,
       count(DISTINCT why)                         AS distinct_why,
       count(*) FILTER (WHERE need_source IS NULL) AS need_source_null,
       count(*) FILTER (WHERE leg_source IS NULL)  AS leg_source_null
  FROM b;
-- 0 / 0 / 0 nulls, and 23,118 distinct `why` values. ottoq_book_stall computes `why` via
-- ottoq.ottoq_booking_why on every successful INSERT -- its own comment calls it "WHY THIS VEHICLE IS IN
-- THIS SPACE". G148 reported the calendar two-thirds blind while this column was complete.

\echo '=== 0338 §2 — the three booked_by values are three code paths, and one is already perfect ==='
WITH b AS (
  SELECT sb.source, sb.booked_by, sb.purpose
    FROM public.ottoq_stall_bookings sb
    JOIN public.stalls s ON s.id = sb.stall_id
   WHERE s.depot_id='11111111-1111-1111-1111-111111111111'
)
SELECT booked_by, count(*) AS n,
       count(*) FILTER (WHERE source IS NULL) AS source_null,
       count(DISTINCT source) AS distinct_sources,
       string_agg(DISTINCT source, ' | ') AS sources
  FROM b GROUP BY 1 ORDER BY n DESC;
-- otto_q_enacted: 12,868 rows, 0 null, 16 sources -- ottoq_record_enacted_booking, which 0336 §4 said
-- to fix. It is the exemplar. otto_q: 22,989 rows, 99.2% null -- ottoq_book_stall, which has no
-- p_source parameter and no `source` in its INSERT column list. THAT is the function to change.

\echo '=== 0338 §2b — ottoq_book_stall is the ONLY direct INSERT, and it cannot name a source ==='
WITH src AS (
  SELECT n.nspname||'.'||p.proname AS fn,
         regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS s
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq')
)
SELECT fn FROM src
 WHERE s ~* 'INSERT[[:space:]]+INTO[[:space:]]+(public\.|ottoq\.|twin\.)?ottoq_stall_bookings';
-- Exactly one row: ottoq.ottoq_book_stall. Every booking in the database is written by it.

SELECT p.proname, pg_get_function_arguments(p.oid) AS args
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='ottoq' AND p.proname IN ('ottoq_book_stall','ottoq_record_enacted_booking')
 ORDER BY p.proname;
-- ottoq_record_enacted_booking ends `p_source text DEFAULT 'unknown'`. ottoq_book_stall has no p_source
-- at all -- so its callers cannot name themselves even if they want to. The defect is structural.

\echo '=== 0338 §4 — the one query 0336 never ran ==='
SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
 WHERE table_schema='public' AND table_name='ottoq_stall_bookings'
   AND (column_name ~ 'source|booked|why|by$' )
 ORDER BY ordinal_position;
-- Listing the columns is what refutes the finding. Before reporting that a table cannot answer a
-- question, confirm no other column answers it.

-- ══ §5 AND THE RETRACTION UNBLOCKS THE THING G148 WAS BLOCKING ═══════════════
--
-- G148 was recorded as *"blocks the walkaround fix (#23)"* — on the grounds that the calendar could not
-- say which code booked a bay for a service that needs none. **It could. `why` answers it in English on
-- 100% of rows, and it names the mechanism outright:**
--
--     "NASH-SVC-01 service 11:08-11:23 to satisfy need 'perimeter_walkaround' (visit_atom);
--      leg 8cb99275 (service, matched caller)"
--     need_source = 'visit_atom' · leg_source = 'caller' · need_atom = 'perimeter_walkaround'
--
-- So the bay is booked **to satisfy the walkaround visit atom, through a service leg**. Not a prefix
-- collision (`0335` §6 settled that), not a mystery writer — the service-leg path books a bay per atom.
--
-- ══ §6 THE CAUSE: NOTHING IN THE DATABASE READS `lane_stalls` ════════════════
--
-- `service_cadence_policy.lane_stalls` is the per-lane stall capacity: `anchor` 45, `wash_bay` 3,
-- `service_bay` 2, `detail` 0, and **NULL for the five lanes that are not stall-based** — `cabin`,
-- `digital`, `exterior`, `gate`. Measured across all three schemas: **zero functions mention
-- `lane_stalls`.** The column that says whether a service occupies a stall is read by nothing.
--
-- **And the anomaly isolates to a single pair, with lane, lane_stalls and concurrency all held
-- constant** — which is why this is a defect and not a modelling opinion:
--
--     svc                    concurrency   lane        lane_stalls   stall bookings   on
--     --------------------   -----------   ---------   -----------   --------------   ----------
--     sensor_clean           exterior      exterior    NULL                     **0**   --
--     perimeter_walkaround   exterior      exterior    NULL                 **3,257**   service bay
--
-- `0383` re-derived the walkaround as `concurrency='exterior'` *explicitly modelled on `sensor_clean`*
-- — event-raised, performed at the vehicle, `lane_stalls=NULL`. Its twin books **no stalls at all.** The
-- walkaround books 3,257, on the depot's **two** service bays. Everything else in the catalogue behaves:
-- all four `cabin` services and `digital` book zero, and every `bay`/`anchor` service with a stall count
-- books its own kind or nothing.
--
-- **So the fix for #23 is: the service-leg path must not book a lane stall for an atom whose service has
-- `lane_stalls IS NULL`.** One predicate, in the leg/bay booking path, on a column that already carries
-- the answer.
--
-- ══ §7 WHAT IS *NOT* ESTABLISHED, AND ONE SECOND CASE TO MEASURE SEPARATELY ═══
--
--   1. **Displacement is STILL not demonstrated**, and `0335`'s rule stands: *a booking is not contention
--      until something is refused because of it.* 3,257 bookings on two bays is a large number on a
--      scarce resource and that is all it is so far. **The one consequence that IS measured** is
--      `0337` §2: HW.006 fails **234 of 808** walkaround `task_completion` evaluations because the probe
--      resolves a stall via `need_atom = svc`, gets a bay the work was never performed at, and the rule
--      correctly reports the vehicle is not in it. Those 234 critical failures are this booking's only
--      demonstrated cost.
--   2. **`readiness_check` is the same shape and must NOT be folded into the same fix without its own
--      measurement.** `lane='gate'`, `lane_stalls=NULL`, and **4,467 bookings on `inspection` stalls** —
--      larger than the walkaround. But unlike the walkaround it has **no same-lane twin** to compare
--      against, and a gate readiness check plausibly does occupy an inspection stall. `lane_stalls=NULL`
--      may mean "no dedicated lane stalls" rather than "occupies nothing" — note `interior_deep_clean`
--      carries `lane_stalls=0` and legitimately books `wash` stalls, so the column is a capacity, not a
--      boolean. **Open, and to be measured on its own evidence.**
--   3. **Whether `source` is correct where present** — still not measured, as `0336` §5 said.
