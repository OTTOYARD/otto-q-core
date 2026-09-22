-- 0348  **G121 has a mechanism, derived from source: `twin.ottoq_sim_start_charge_session` writes the stall
--       POINTER and never the stall STATUS, and the trigger that writes the status — `sync_stall_occupancy`
--       — NO-OPS when the vehicle is already recorded at that stall. A vehicle that is already at its stall
--       when a charge begins therefore leaves `status='available'` beside a live `current_vehicle_id`.**
--
--       That is exactly G121's signature, on exactly G121's stall type.
--
--       **AND G121 IS NOT CURRENTLY OBSERVABLE: 0 of the twin depot's 158 stalls are in that state right
--       now.** All 158 read `available` with no pointer — the depot is idle between runs. So this file
--       establishes a MECHANISM and does not re-observe the defect; §4 says what would.
--
--       Measured 2026-09-22 ~17:3x UTC (12:3x CT).
--
-- ══ §1 THE ASYMMETRIC WRITE, WHICH IS WHAT TO LOOK FOR ══════════════════════
--
-- `0347` established that `status` and `current_vehicle_id` never move independently **through
-- `sync_stall_occupancy`**, because both its branches write the pair together as (`available`, NULL) or
-- (`occupied`, NEW.id). So G121 — `available` **with** a live pointer — cannot come from that trigger, and
-- the producer must be a statement that writes **one of the two and not the other**.
--
-- Censusing every `UPDATE stalls` in the database for exactly that asymmetry returns fourteen statements.
-- Most are unambiguous and harmless: `status='blocked'`/`'maintenance'`/`'offline'` on fault paths, and
-- pointer-only clears (`current_vehicle_id = NULL`) on release paths. **One writes a LIVE pointer with no
-- status:**
--
--     twin.ottoq_sim_start_charge_session
--       UPDATE stalls SET current_vehicle_id = p_vehicle_id WHERE id = p_stall_id;
--
-- Measured on the function: **exactly one `UPDATE stalls`, and it never mentions `status`.**
--
-- ══ §2 WHY IT USUALLY DOES NOT MATTER, AND THE CONDITION WHERE IT DOES ══════
--
-- The status is normally supplied a moment later, by the trigger, because the same function then does:
--
--     position of `UPDATE stalls SET current_vehicle_id = p_vehicle_id`  =  7,070
--     position of `UPDATE vehicles SET current_state …, current_stall_id = p_stall_id`  =  7,147
--
-- — pointer first, vehicle second — and the vehicles UPDATE fires `sync_stall_occupancy`, which sets
-- `status='occupied'`. **But that trigger's own guard is a CHANGE of stall:**
--
--     IF NEW.current_stall_id IS NOT NULL AND OLD.current_stall_id IS DISTINCT FROM NEW.current_stall_id
--
-- **So if the vehicle's `current_stall_id` is ALREADY `p_stall_id` when the charge starts, the trigger does
-- nothing, and nothing else in the path ever writes the stall's status.** The pointer is set; the status
-- keeps whatever it had. If that was `available`, the stall is now `available` with a live
-- `current_vehicle_id` — **G121, persistent across ticks, not a race**, which is precisely how `0326` §2
-- described it.
--
-- **And the stall type matches:** this is the charge path, and G121's three stalls were all `dcfc`.
--
-- ══ §3 WHAT THIS IS AND IS NOT ══════════════════════════════════════════════
--
-- **IT IS:** a mechanism that is sufficient, derived from three facts each read from the live catalog — the
-- charge start's single stall UPDATE omits `status`; it precedes the vehicles UPDATE; and the trigger's
-- occupy branch is guarded on a stall *change*.
--
-- **IT IS NOT** an observation of the defect being produced. `0326` §2 observed the state; this file
-- observes the code that can produce it. **The two have not been joined**, and until they are this is a
-- hypothesis with a strong fit rather than a diagnosis. Saying otherwise would be this branch's most
-- repeated error — a real measurement read as answering a question it was not about.
--
-- **AND IT DOES NOT ACCOUNT FOR THE OTHER THIRTEEN asymmetric statements.** Each is individually plausible
-- as a G121 producer if its stall was pointed-at at the time; they are simply less likely, because a
-- fault-path `status='blocked'` does not leave `available` behind. **This names the best candidate, not the
-- only one.**
--
-- ══ §4 THE ONE OBSERVATION THAT WOULD SETTLE IT, AND WHY IT NEEDS A RUN ═════
--
-- On a live run, find a charge start where the vehicle was already at the stall:
--
--     SELECT st.id, st.stall_type, st.status, st.current_vehicle_id, s.vehicle_id, s.started_at
--       FROM ocpp_sessions s
--       JOIN stalls st ON st.id = s.stall_id
--      WHERE s.status='active'
--        AND st.depot_id='11111111-1111-1111-1111-111111111111'
--        AND st.status::text = 'available'          -- the smoking gun: charging, but not marked occupied
--        AND st.current_vehicle_id = s.vehicle_id;
--
-- **A non-empty result is G121 caught in the act.** It returns nothing today because no run is active and
-- there are no sessions at all — which is also why `0347` §5 stopped where it did. The two open questions
-- share one blocker.
--
-- **The fix, when it is confirmed, is one clause and not a new mechanism:** have the charge start write
-- `status='occupied'` in the same UPDATE as the pointer, which is what every other stall writer in this
-- database already does and what `0347` showed the trigger itself does. **Do NOT instead make the trigger
-- fire on unchanged stalls** — that would rewrite the stall on every vehicles UPDATE, which is the cost the
-- trigger's own comment says it was written to avoid (*"fires on every vehicles UPDATE and must stay cheap
-- and unable to raise"*).
--
-- **NOTE the interaction with `0428`, checked rather than assumed:** the refusal path added by `0428`
-- returns **before** the stall pointer write, so a refused charge never sets the pointer and cannot create
-- this state. Promotion did not widen G121.

\echo '=== 0348 §1 — every asymmetric stall write: one of status/pointer but not both ==='
WITH f AS (
  SELECT n.nspname||'.'||p.proname AS fn,
         regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname IN ('public','twin','ottoq') AND p.prosrc ~ 'UPDATE\s+(public\.)?stalls'),
stmts AS (
  SELECT f.fn, (regexp_matches(f.src,'UPDATE\s+(?:public\.)?stalls\s+SET([^;]{0,240})','g'))[1] AS set_clause
    FROM f)
SELECT fn,
       (set_clause ~ 'status')             AS sets_status,
       (set_clause ~ 'current_vehicle_id') AS sets_pointer,
       (set_clause ~ 'current_vehicle_id\s*=\s*[^N]')  AS sets_a_LIVE_pointer,
       left(regexp_replace(set_clause,'\s+',' ','g'), 90) AS set_clause
  FROM stmts
 WHERE (set_clause ~ 'status') <> (set_clause ~ 'current_vehicle_id')
 ORDER BY 4 DESC NULLS LAST, 1;
-- Fourteen asymmetric statements. Exactly ONE sets a LIVE pointer with no status:
-- twin.ottoq_sim_start_charge_session. The rest are fault-path status writes or pointer-only clears.

\echo '=== 0348 §2 — the charge start writes the pointer BEFORE the vehicles row, and never the status ==='
WITH s AS (SELECT regexp_replace(regexp_replace(prosrc,'/\*.*?\*/','','g'),'--[^'||chr(10)||']*','','g') AS src
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='twin' AND p.proname='ottoq_sim_start_charge_session')
SELECT position('UPDATE stalls SET current_vehicle_id = p_vehicle_id' in src) AS stall_pointer_at,
       position('UPDATE vehicles SET current_state' in src)                   AS vehicles_update_at,
       (src ~ 'UPDATE\s+stalls\s+SET[^;]*status')                             AS ever_sets_stall_status,
       (SELECT count(*) FROM regexp_matches(src,'UPDATE\s+stalls','g'))       AS stall_updates
  FROM s;
-- pointer 7070 < vehicles 7147, ever_sets_stall_status FALSE, exactly 1 stall UPDATE. So the status can
-- only arrive via sync_stall_occupancy -- whose occupy branch is guarded on the stall CHANGING.

\echo '=== 0348 §2b — the trigger guard that makes it a no-op for a vehicle already at the stall ==='
SELECT (prosrc ~ 'OLD\.current_stall_id IS DISTINCT FROM NEW\.current_stall_id') AS occupy_guarded_on_change,
       (prosrc ~ 'status = ''occupied''')                                        AS trigger_writes_occupied
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname='sync_stall_occupancy';
-- Both true. Vehicle already at the stall => no change => no occupy write => status keeps 'available'.

\echo '=== 0348 §3 — G121 is NOT currently observable: 0 of 158 twin stalls are in that state ==='
SELECT status::text AS status, count(*) AS stalls,
       count(*) FILTER (WHERE current_vehicle_id IS NOT NULL) AS with_live_pointer
  FROM public.stalls
 WHERE depot_id='11111111-1111-1111-1111-111111111111'
 GROUP BY 1 ORDER BY 2 DESC;
-- 158 available, 0 with a live pointer. The depot is idle between runs, so this file establishes a
-- mechanism and does NOT re-observe the defect. Section 4 has the one query that would, on a live run.
