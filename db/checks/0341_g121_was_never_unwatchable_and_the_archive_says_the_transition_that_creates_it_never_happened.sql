-- 0341  **RETRACTION of `0336` §6 / G121's "unwatchable" claim, on every clause — and the correct
--       instrument then returns something far more interesting than the claim it replaces.**
--
--       `0336` §6 said: *"`stall.state_changed` carries **one payload key** across all 83,456 rows, a
--       `diff` containing **only `status`**. The combination that defines G121 is structurally absent from
--       the archive, so it can be caught live or not at all."* And from that I wrote a blocking
--       prerequisite into FINDINGS and the task list: *"Add the two pointer fields to the stall trigger's
--       diff BEFORE fixing G121, or there is no before to compare an after against."*
--
--       **The pointer fields have been in the diff the whole time. The prerequisite migration is
--       unnecessary and it was blocking a real defect — three of the twin depot's ten fast chargers held
--       by nobody — behind work that did not need doing.**
--
--       Measured 2026-09-22 ~15:5x UTC (10:5x CT).
--
-- ══ §1 WHAT THE DIFF ACTUALLY CARRIES ════════════════════════════════════════
--
-- `ottoq_stalls_state_change` does not hand-pick keys. It computes
-- `v_diff := ottoq_jsonb_diff(to_jsonb(OLD), to_jsonb(NEW))` — a **generic whole-row diff** — so every
-- column that changes is in it. Over 112,572 `stall.state_changed` events, **six** distinct diff keys
-- exist in total:
--
--     diff key                 events
--     ----------------------   ------
--     reservation_expires_at   63,616
--     reserved_by              **63,616**
--     reserved_at              56,159
--     current_vehicle_id       **53,720**
--     status                   **53,720**
--     updated_at                1,906
--
-- and the shape is `{"status": {"from": "occupied", "to": "available"},
--                    "current_vehicle_id": {"from": "f0077a3a-…", "to": null}}` — **both sides of both
-- fields.** The combination that defines G121 — `status` together with `current_vehicle_id` — appears on
-- **49,140 events.**
--
-- **Every clause of the retracted sentence is false.** Not "one payload key" (six). Not "only `status`"
-- (`status` is on 53,720 of 112,572, fewer than half, and is outnumbered by `reserved_by`). Not
-- "structurally absent" (49,140 events carry exactly the pair). The "83,456 rows" was also a count of a
-- different population than the 112,572 that exist now.
--
-- ══ §2 WHY I READ IT AS ABSENT, AND THE MECHANISM IS DELIBERATE ══════════════
--
-- I measured `new_state`, found it NULL on **103,676 of 112,572 (92.1%)**, and concluded the archive did
-- not hold the row. It does — in the `diff`, and in an anchor snapshot.
--
-- `ottoq_events` carries a BEFORE INSERT trigger, **`ottoq_events_slim_new_state_bi`**, driven by
-- `ottoq_write_slimming_policy`. Its CUT 2 claims one anchor per
-- `(run_key, event_type, entity_id, anchor_day)` via `ON CONFLICT DO NOTHING` on
-- `ottoq_event_state_anchor`, keeps the **full snapshot** on the winner, and nulls `new_state` on the rest
-- — with the reason in its own comment: *"an anchor exists; the diff carries the news."* It also refuses to
-- slim anything whose diff is absent or empty (*"no diff to carry the change: keep the snapshot"*).
--
-- **So the archive is reconstructible by construction: anchor snapshot + replay the diffs.** 8,896 anchors
-- for 112,572 events is a 92% saving on a table CLAUDE.md records as ~9 GB of an 11 GB database, and the
-- design is careful — per-row `jsonb` equality test before CUT 1, one exception block around everything,
-- *"We save nothing; we never break anything."*
--
-- **I measured the column the space optimisation empties, and reported the archive as blind.** Both
-- readings that looked like corroboration were artefacts of the same thing: the NULLs are not an era (both
-- groups span the identical window to the microsecond) and not recency (~8–9% carry snapshots in every
-- hour) — they are *one anchor per entity per day*.
--
-- ══ §3 AND THE CORRECT INSTRUMENT SAYS SOMETHING SHARPER THAN THE CLAIM ══════
--
-- Now that the archive can be interrogated, it answers — and the answer is not "here are the G121
-- events":
--
--   * **26,860 events move `status` to `available`. In ZERO of them does `current_vehicle_id.to` remain
--     non-null.** The transition that would create G121 is detectable, and it never occurs.
--   * **Zero events change `current_vehicle_id` without also changing `status`** (`to` non-null, no
--     `status` key). And the census above shows why that is not a coincidence: `status` and
--     `current_vehicle_id` appear on **exactly 53,720 events each**. The two fields never move
--     independently in the entire archive.
--
-- **So the three `dcfc` stalls `0326` §2 found — `status='available'` with a live `current_vehicle_id` and
-- `reserved_by`, persistent across ticks — did not reach that state through this trigger.** Either a writer
-- reaches `stalls` on a path that does not fire it (direct SQL, a `session_replication_role` window, a
-- COPY), or the state is assembled in a way the trigger's own churn filter drops.
--
-- **The churn filter is checked and does NOT explain it:** it returns early only when every changed key is
-- in `('updated_at','reservation_expires_at','reserved_at')`, so a `current_vehicle_id`-only change would
-- still be recorded. That leaves a writer outside the audit trail, which is a more serious finding than
-- G121 itself: **a state the engine's own signed event stream has no record of.**
--
-- **NOT established here, and named rather than guessed:** which writer. The next query is a census of
-- every function that UPDATEs `stalls.current_vehicle_id` or `reserved_by`, cross-checked against whether
-- it runs in a context where the trigger is live. `0326` §2's three stalls were also cleared by a demo-run
-- reset before they could be traced (per the 14:46 check-in), so this needs the pattern to recur — and it
-- can now be watched from the archive rather than only live.
--
-- ══ §4 THE LESSON — THIRD INSTANCE TODAY, AND THE COSTLIEST ══════════════════
--
-- `0338` §4 set the standing test: **before reporting that a table cannot answer a question, list its
-- columns and confirm no other column answers it.** This is the same failure one level deeper: I did look
-- at a second column, and the one I looked at was the one a space optimisation had emptied.
--
-- **So the test needs its sharper form: when a column is unexpectedly NULL at scale, find out WHO NULLS IT
-- before concluding the data was never written.** A trigger named `…_slim_…` on the table being queried is
-- one `pg_trigger` lookup away, and reading it would have turned "structurally absent" into "stored in the
-- diff, by design, with an anchor for replay."
--
-- **And this one had a cost the other two did not.** `0338`'s error produced a wrong sentence.
-- This one produced a **wrong prerequisite**: G121 is a live defect on the depot's scarcest resource —
-- `0250` established that refused proposals are asking for exactly these stall types — and I filed a
-- migration in front of it that never needed to exist. **A fabricated blocker is worse than a wrong
-- number, because it stops work rather than merely misdescribing it.**

\echo '=== 0341 §1 — six diff keys, and the pointer fields are on tens of thousands of events ==='
SELECT k AS diff_key, count(*) AS events
  FROM public.ottoq_events e, jsonb_object_keys(e.payload->'diff') AS k
 WHERE e.event_type='stall.state_changed'
 GROUP BY 1 ORDER BY 2 DESC;
-- reserved_by 63,616 · current_vehicle_id 53,720 · status 53,720. NOT "one payload key", NOT "only
-- status". NOTE the LATERAL join fans one row per key -- count events with FILTER, not with this join,
-- which is 0339's own standing test applied to itself.

SELECT count(*) AS events,
       count(*) FILTER (WHERE payload->'diff' ? 'status')             AS diff_has_status,
       count(*) FILTER (WHERE payload->'diff' ? 'current_vehicle_id') AS diff_has_vehicle,
       count(*) FILTER (WHERE payload->'diff' ? 'reserved_by')        AS diff_has_reserved_by,
       count(*) FILTER (WHERE payload->'diff' ? 'current_vehicle_id'
                          AND payload->'diff' ? 'status')             AS g121_pair_present
  FROM public.ottoq_events WHERE event_type='stall.state_changed';
-- 49,140 events carry the exact pair that DEFINES G121. It was never structurally absent.

\echo '=== 0341 §2 — who nulls new_state, and why the archive is still complete ==='
SELECT t.tgname, p.proname, t.tgenabled
  FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_proc p ON p.oid=t.tgfoid
 WHERE c.relname='ottoq_events' AND NOT t.tgisinternal;
-- ottoq_events_slim_new_state_bi. It keeps ONE full snapshot per (run, event_type, entity, day) in
-- ottoq_event_state_anchor and nulls the rest because "the diff carries the news". 8,896 anchors for
-- 112,572 events. The column I measured is the one it empties by design.

SELECT (new_state IS NULL) AS new_state_null, count(*) AS events,
       min(occurred_at) AS oldest, max(occurred_at) AS newest
  FROM public.ottoq_events WHERE event_type='stall.state_changed' GROUP BY 1;
-- Both groups span the IDENTICAL window to the microsecond -- so the NULLs are not an era and not a
-- purge, which is what ruled out every "the data is gone" explanation and forced reading the trigger.

\echo '=== 0341 §3 — the instrument works, and says the G121 transition never happened ==='
SELECT count(*) AS status_to_available,
       count(*) FILTER (WHERE payload->'diff'->'current_vehicle_id'->>'to' IS NOT NULL)
         AS and_vehicle_pointer_still_set
  FROM public.ottoq_events
 WHERE event_type='stall.state_changed'
   AND payload->'diff'->'status'->>'to' = 'available';
-- 26,860 and ZERO. The transition that would create G121 is detectable and does not occur.

SELECT count(*) AS vehicle_set_without_status_moving
  FROM public.ottoq_events
 WHERE event_type='stall.state_changed'
   AND payload->'diff' ? 'current_vehicle_id' AND NOT (payload->'diff' ? 'status')
   AND payload->'diff'->'current_vehicle_id'->>'to' IS NOT NULL;
-- ZERO. The two fields never move independently (53,720 each, exactly). So G121's three stalls were not
-- created by any write this trigger saw -- which points at a writer outside the signed event stream.
-- WHICH writer is NOT established here. Census every UPDATE of stalls.current_vehicle_id / reserved_by
-- next, and check whether each runs where the trigger is live.
