-- 0347  **G157 ANSWERED, and the answer is not a mystery writer. `public.sync_stall_occupancy` is an
--       `AFTER UPDATE ON vehicles` trigger that clears `stalls.current_vehicle_id` — and its ONE exemption
--       is a robotic tether, which is exactly why HW.006 fails on `l2` and never on `dcfc`.**
--
--       **The defect is therefore NOT the trigger, which does exactly what it says. It is that a charge
--       session outlives its vehicle's stall assignment:** something moves a vehicle off an L2 charger while
--       its OCPP session is still open, and the trigger then correctly releases the stall the session still
--       believes it holds.
--
--       **And the conflict machinery already saw every one of them.** All five sampled stalls carry
--       `standing_claim_contradicted` rows in `space_conflict_ledger` — resolution `recorded_not_acted`.
--
--       Measured 2026-09-22 ~17:1x UTC (12:1x CT), windowed on `0427`'s apply (`20260922163008`).
--
-- ══ §1 THE WRITER, AND WHY EVERY PREVIOUS SEARCH MISSED IT ═══════════════════
--
--     CREATE TRIGGER trg_sync_stall_occupancy
--       AFTER UPDATE ON public.vehicles FOR EACH ROW EXECUTE FUNCTION sync_stall_occupancy()
--
--     IF OLD.current_stall_id IS DISTINCT FROM NEW.current_stall_id
--        AND NOT (NEW.robotic_tether_until IS NOT NULL
--                 AND NEW.robotic_tether_stall_id IS NOT DISTINCT FROM OLD.current_stall_id) THEN
--       UPDATE stalls SET status='available', current_vehicle_id=NULL WHERE id = OLD.current_stall_id;
--     END IF;
--     IF NEW.current_stall_id IS NOT NULL AND OLD.current_stall_id IS DISTINCT FROM NEW.current_stall_id THEN
--       UPDATE stalls SET status='occupied', current_vehicle_id=NEW.id WHERE id = NEW.current_stall_id;
--     END IF;
--
-- **A write to `vehicles` silently rewrites `stalls`.** Twenty functions in this database clear
-- `stalls.current_vehicle_id`; nineteen are called on a stall path and one is a trigger on a *different
-- table*. **That is why walking the stall-writing call paths never found it** — the same shape as `0326`
-- §6(a)'s standing finding that a static caller search can never find a rule's wiring, and as `0321`'s three
-- row-level probe points that every decide-path census missed.
--
-- ══ §2 THE TETHER EXEMPTION *IS* THE L2/DCFC SPLIT ═══════════════════════════
--
-- `0346` measured **16 failures, all `l2`, against `dcfc` passing 96 of 96**, and called the split the
-- discriminator without knowing the mechanism. It is one clause: the clear is skipped when a robotic tether
-- still holds the old stall. **DCFC is the tethered path** — `twin.ottoq_sim_start_charge_session` begins an
-- arm mate cycle on `stall_type='dcfc'`, and `ottoq_sim_stop_charge_session`'s own pointer clear is guarded
-- by `IF NOT v_tether`. **L2 has no tether, so nothing holds the stall when the vehicle's row moves.**
--
-- So the prediction `0427` §3 wrote before applying — *"if HW.006 fails on untethered closes, the stall
-- pointer is being cleared somewhere upstream of this function"* — is confirmed, and the upstream writer is
-- named.
--
-- ══ §3 THE COUNTS HAVE GROWN, WHICH IS THE POINT OF QUOTING THE MOMENT ═══════
--
--     at 0346 (~16:4x)   16 rows /  9 incidents   (12 empty, 6 other-vehicle)
--     at 0347 (~17:1x)   84 rows / 42 incidents   (60 empty, 24 other-vehicle)
--       against 1,594 stall-carrying evaluations = **5.3% of stall-carrying completions**
--
-- **The 2.00 rows-per-incident duplication `0346` §3 recorded still holds exactly (84/42), so the row count
-- is still not the incident count.** And `0334`'s standing rule applies to this file too: these are figures
-- about a moment on a live engine, not a rate.
--
-- ══ §4 THE CONFLICT LEDGER ALREADY HELD THEM — G157(a) ANSWERED ══════════════
--
-- CLAUDE.md rule 6 requires *"assignment plus verification, always"*, and names `space_conflict_ledger` as
-- the record of every calendar claim overruled by physical reality. **It is working.** Every one of the five
-- sampled "stall holds a different vehicle" stalls carries ledger rows in the same window:
--
--     stall 55fe979e…  92 rows   assignment_refused_occupied, standing_claim_contradicted
--     stall 765adddb…  12 rows   assignment_refused_occupied, standing_claim_contradicted
--     stall a643de50…  82 rows   assignment_refused_occupied, standing_claim_contradicted
--     stall c8049eb3…  16 rows   assignment_refused_occupied, standing_claim_contradicted
--     stall f517a13e…  40 rows   assignment_refused_occupied, standing_claim_contradicted
--
-- Ledger-wide in the window: **1,746 `assignment_refused_occupied` (`command_refused_preflight`), 1,174
-- `standing_claim_contradicted` (`recorded_not_acted`), 50 `stale_claim_displaced`
-- (`reality_outranks_plan`).** So reality-outranks-plan is not aspirational here; it is enacted 50 times and
-- *recorded but not acted on* 1,174 times. **The gap G157 names is the `recorded_not_acted` class**, not a
-- blind spot.
--
-- **AND THE SAMPLE CONTAINS A DISPLACEMENT CHAIN, which is worth more than the count:** stall `55fe979e`
-- expected `7ec698b8` and found `0ea2ccfe`; stall `765adddb` **expected `0ea2ccfe`** and found `db9d7b6e`.
-- The same vehicle is the interloper in one stall and the displaced party in another. **A single vehicle
-- moved without closing its session can propagate.**
--
-- ══ §5 AND IT EXPLAINS A SENTENCE FROM `0341` THAT HAD NO MECHANISM ══════════
--
-- `0341` measured that `status` and `current_vehicle_id` appear on exactly 53,720 events each and **never
-- move independently**, and that of 26,860 transitions to `available`, **zero** leave the vehicle pointer
-- set. That was reported as an unexplained regularity. **It is this trigger:** both branches write `status`
-- and `current_vehicle_id` in the *same* `UPDATE`, so they cannot move apart through this path.
--
-- **WHICH SHARPENS G121 RATHER THAN CLOSING IT.** G121 is three `dcfc` stalls reading `status='available'`
-- **together with** a live `current_vehicle_id` — a combination this trigger **cannot produce**, because it
-- only ever writes that pair as (`available`, NULL) or (`occupied`, NEW.id). So G121's three stalls were
-- written by something else, and the census in §1 is now the shortlist: nineteen functions, of which
-- `ottoq_stall_seat_is_exclusive` is the other trigger (on `stalls` itself). **Do not merge G121 into G157 —
-- `0346` §4 already warned that adjacent is not identical, and the mechanism found here is the evidence
-- for that warning rather than against it.**
--
-- ══ §6 WHAT TO FIX, AND WHAT NOT TO ═════════════════════════════════════════
--
--   1. **Do NOT "fix" the trigger.** Removing the clear would leave dead pointers on every vehicle move —
--      which is G121's defect, manufactured deliberately. The trigger is the mechanism that keeps the
--      pointer honest.
--   2. **Do NOT enforce HW.006.** At 5.3% of stall-carrying completions it would refuse real work, and the
--      rule is right: the vehicle genuinely is not there. `0345` §3's order — fix the input, measure to
--      zero, then promote — is unchanged.
--   3. **The fix is upstream and is a product question:** what moves a vehicle off an L2 charger without
--      closing its OCPP session, and should that path close the session or refuse the move? **Not measured
--      here** — it needs a live run, because the census in §4 is of stalls, not of the moving write.
--      The instrument is one query over `ocpp_sessions` joined to `vehicles`, and it returns nothing while
--      no run is active, which is why this file stops short of naming the mover.

\echo '=== 0347 §1 — the writer is a trigger on VEHICLES, which is why stall-path searches missed it ==='
SELECT n.nspname||'.'||p.proname AS fn,
       coalesce(string_agg(DISTINCT t.tgrelid::regclass::text, ', '), '(not a trigger)') AS fires_on_table
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  LEFT JOIN pg_trigger t ON t.tgfoid = p.oid AND NOT t.tgisinternal
 WHERE n.nspname IN ('public','twin','ottoq') AND p.prosrc ~ 'current_vehicle_id\s*=\s*NULL'
 GROUP BY 1 ORDER BY 2 DESC, 1;
-- Twenty functions clear the pointer. public.sync_stall_occupancy fires on VEHICLES; only
-- ottoq_stall_seat_is_exclusive fires on stalls. Nineteen are ordinary call-path functions.

\echo '=== 0347 §2 — the tether exemption, read from the trigger itself ==='
SELECT (prosrc ~ 'robotic_tether_until')      AS has_tether_guard,
       (prosrc ~ 'status = ''available''')    AS writes_available,
       (prosrc ~ 'status = ''occupied''')     AS writes_occupied
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='sync_stall_occupancy';
-- The clear is skipped only when a robotic tether still holds the OLD stall. DCFC is the tethered path;
-- L2 is not. That single clause is 0346's l2-only split.

\echo '=== 0347 §3 — the counts, and the 2.00x duplication still holding ==='
SELECT count(*) AS rows,
       count(DISTINCT (result_payload->>'stall_id',
                       result_payload->>'expected_vehicle_id', evaluated_at)) AS incidents,
       count(*) FILTER (WHERE result_payload->>'stall_current_vehicle_id' IS NULL)     AS pointer_empty,
       count(*) FILTER (WHERE result_payload->>'stall_current_vehicle_id' IS NOT NULL) AS pointer_other,
       max(evaluated_at) AS last_seen
  FROM public.ottoq_rule_evaluations
 WHERE rule_code='HW.006.physical_presence_verification' AND action_context='task_completion'
   AND NOT passed AND evaluated_at >= '2026-09-22 16:30:08+00';
-- 84 rows / 42 incidents at this reading, against 1,594 stall-carrying evaluations = 5.3%. Grew from
-- 16/9 half an hour earlier -- quote the moment, never the total (0334).

\echo '=== 0347 §4 — every affected stall is already in the conflict ledger (G157(a): YES) ==='
SELECT conflict_kind, resolution, count(*) AS n, max(recorded_at) AS last_seen
  FROM public.space_conflict_ledger
 WHERE recorded_at >= '2026-09-22 16:30:08+00'
 GROUP BY 1,2 ORDER BY n DESC;
-- 1,746 assignment_refused_occupied / command_refused_preflight
-- 1,174 standing_claim_contradicted / recorded_not_acted   <-- the class G157 is about
--    50 stale_claim_displaced       / reality_outranks_plan
-- "Assignment plus verification" is working. The gap is recorded_not_acted, not a blind spot.

\echo '=== 0347 §5 — the instrument that names the MOVER, which needs a live run ==='
SELECT st.stall_type::text AS stall_kind,
       count(*) AS active_sessions,
       count(*) FILTER (WHERE v.current_stall_id IS DISTINCT FROM s.stall_id) AS vehicle_moved_away,
       count(*) FILTER (WHERE st.current_vehicle_id IS NULL)                  AS stall_pointer_empty,
       count(*) FILTER (WHERE st.current_vehicle_id IS NOT NULL
                          AND st.current_vehicle_id <> s.vehicle_id)          AS stall_holds_other
  FROM public.ocpp_sessions s
  JOIN public.stalls st ON st.id = s.stall_id
  JOIN public.vehicles v ON v.id = s.vehicle_id
 WHERE s.status='active' AND st.depot_id='11111111-1111-1111-1111-111111111111'
 GROUP BY 1 ORDER BY 2 DESC;
-- Returns NOTHING while no run is active, which is why this file does not name the mover. Run it during a
-- live run: a non-zero `vehicle_moved_away` on l2 is the divergence, caught while it is still open rather
-- than after the session closes.
