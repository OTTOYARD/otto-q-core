-- 0350  **`0347` §5 and `0348` §4 both wait for a live run, and the live run ended (20:50 UTC, the run
--       governor's 540 sim-minute ceiling) before either was run. So both are answered from the run's own
--       history — which is the stronger reading anyway: every charge start and every session of one whole
--       busy_day, not the one moment a live query would have caught.**
--
--       **0348 §4 — G121's condition did not occur once: 0 of 133 charge starts found the vehicle already at
--       the charger stall** (76 L2, 57 DCFC; 125 arrived from another stall, 8 from no stall). The mechanism
--       `0348` §2 found — `sync_stall_occupancy`'s occupy branch is guarded on a CHANGE of stall, so a charge
--       started for a vehicle already there never writes `status='occupied'` — had no occasion to bite.
--       **G121 stays a mechanism without a reproduction, and the one-clause fix `0348` §4 describes is still
--       not justified by an observation.** Do not apply it on this evidence.
--
--       **0347 §5 — the mover is named: 2 of 76 L2 sessions outlived their vehicle's stall pointer, by 41 and
--       139 sim-seconds. 0 of 57 DCFC did.** In both, the vehicle's own transition out of `charging_l2`
--       cleared `current_stall_id` while the OCPP session was still `active`:
--
--           charging_l2 -> staged_awaiting_service   session closed 41 s later   fault.thermal_emergency
--           charging_l2 -> charge_complete_holding   session closed 139 s later  completed
--
--       **The DCFC zero is `0347` §2 seen from the other side** — the tether exemption *is* the L2/DCFC split,
--       so the pointer on an arm-tethered DCFC stall is not cleared under an open session and the divergence
--       can only ever be L2. And the rate is small (2.6% of L2 sessions, ~1.5 min each), which is consistent
--       with `0347` §6's order: fix the input upstream, do not enforce HW.006 on it.
--
--       Run `0682752c-7082-4ece-97df-152a67f463f0`, `busy_day`, twin depot `11111111-…`, 1,099 ticks,
--       started from the cockpit 19:40:39 UTC, ended 20:50:00 UTC by `run_governor: reached the 540
--       sim-minute ceiling`. Measured 2026-09-22 ~21:45 UTC (4:45 PM CT), before any later run purged it.
--
-- ══ §1 WHY FROM HISTORY, AND THE ONE THING THAT MADE IT POSSIBLE ═════════════
--
-- Both files wrote their instrument against LIVE state (`ocpp_sessions.status='active'`, the stall's
-- current `status`), which is empty between runs. The history is not: `ocpp_sessions` keeps every session of
-- the run with its sim-clock `started_at`/`ended_at` and `stopped_reason`, and `vehicle_state_log` keeps every
-- state transition — written by `public.log_vehicle_state_change`, fired by `trg_vehicle_state_change` on
-- `vehicles`, with `stall_id = NEW.current_stall_id` and `metadata.previous_stall_id = OLD.current_stall_id`.
-- **That trigger is what makes both questions answerable after the fact:** a transition INTO charging records
-- where the vehicle came from, and a transition OUT records whether its pointer left the stall.
--
-- One clock hazard, handled rather than ignored: `ocpp_sessions` is on the SIM clock, `vehicle_state_log`
-- on the WALL clock. A state row written at wall `w` is placed at the sim clock of the newest tick whose
-- `real_started_at <= w + 1s` (`ottoq_tick_clock_log`) — the rows are written a few ms before their tick's
-- `real_started_at`, and between ticks the sim clock does not move.
--
-- (Aside, measured in passing: every one of the run's 1,958 `vehicle_state_log` rows reads
-- `triggered_by = 'otto_q_engine'` — the trigger's literal default, "overridden by application layer when
-- appropriate", and never overridden on this run. The column cannot say who moved a vehicle.)

\echo '=== 0350 §2 — 0348 §4 from history: charge starts where the vehicle was ALREADY at the stall (G121''s condition) ==='
WITH l AS (
  SELECT v.vehicle_id, v.stall_id, v.new_state::text AS nxt, v.previous_state::text AS prev,
         NULLIF(v.metadata->>'previous_stall_id','')::uuid AS prev_stall
    FROM public.vehicle_state_log v
   WHERE v.depot_id = '11111111-1111-1111-1111-111111111111'
     AND v.created_at >= '2026-09-22 19:40:39+00' AND v.created_at < '2026-09-22 21:40:00+00')
SELECT st.stall_type::text AS stall_kind,
       count(*)                                                                 AS charge_starts,
       count(*) FILTER (WHERE l.prev_stall = l.stall_id)                        AS vehicle_already_at_stall,
       count(*) FILTER (WHERE l.prev_stall IS NULL)                             AS from_no_stall,
       count(*) FILTER (WHERE l.prev_stall IS NOT NULL AND l.prev_stall <> l.stall_id) AS from_other_stall
  FROM l JOIN public.stalls st ON st.id = l.stall_id
 WHERE l.nxt IN ('charging_l2','charging_dcfc')
 GROUP BY 1 ORDER BY 2 DESC;
-- l2    76  0  7  69
-- dcfc  57  0  1  56
-- => G121's condition: 0 of 133.

\echo '=== 0350 §3 — 0347 §5 from history: sessions that outlived their vehicle''s stall pointer ==='
WITH ticks AS (
  SELECT real_started_at, sim_clock_after FROM public.ottoq_tick_clock_log
   WHERE sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0'),
sess AS (
  SELECT s.vehicle_id, s.stall_id, st.stall_type::text AS kind, st.stall_code,
         s.started_at, s.ended_at, s.stopped_reason
    FROM public.ocpp_sessions s JOIN public.stalls st ON st.id = s.stall_id
   WHERE s.sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0'
     AND st.depot_id  = '11111111-1111-1111-1111-111111111111'),
vsl AS (
  SELECT v.vehicle_id, v.stall_id, v.new_state::text AS nxt, v.previous_state::text AS prev, v.metadata, v.created_at,
         (SELECT max(t.sim_clock_after) FROM ticks t WHERE t.real_started_at <= v.created_at + interval '1 second') AS sim_at
    FROM public.vehicle_state_log v
   WHERE v.depot_id = '11111111-1111-1111-1111-111111111111'
     AND v.created_at >= '2026-09-22 19:40:39+00' AND v.created_at < '2026-09-22 21:40:00+00'),
firstmove AS (   -- the vehicle's first transition, after its session started, that leaves the session's stall
  SELECT s.*, m.sim_at AS moved_at, m.prev || '->' || m.nxt AS transition,
         (m.stall_id IS NULL) AS pointer_cleared,
         (m.metadata->>'previous_stall_id' = s.stall_id::text) AS left_from_this_stall
    FROM sess s
    LEFT JOIN LATERAL (SELECT * FROM vsl
                        WHERE vsl.vehicle_id = s.vehicle_id AND vsl.sim_at > s.started_at
                          AND vsl.stall_id IS DISTINCT FROM s.stall_id
                        ORDER BY vsl.sim_at, vsl.created_at LIMIT 1) m ON true)
SELECT kind,
       count(*) AS sessions,
       count(*) FILTER (WHERE moved_at < ended_at - interval '40 seconds') AS outlived_the_pointer
  FROM firstmove GROUP BY 1 ORDER BY 1;
-- dcfc  57  0
-- l2    76  2
-- (40 s is more than one tick at this run's cadence, so a same-tick close is not counted as a divergence.)

\echo '=== 0350 §4 — the two, named ==='
WITH ticks AS (
  SELECT real_started_at, sim_clock_after FROM public.ottoq_tick_clock_log
   WHERE sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0'),
sess AS (
  SELECT s.vehicle_id, s.stall_id, st.stall_code, s.started_at, s.ended_at, s.stopped_reason
    FROM public.ocpp_sessions s JOIN public.stalls st ON st.id = s.stall_id
   WHERE s.sim_run_id = '0682752c-7082-4ece-97df-152a67f463f0'
     AND st.depot_id  = '11111111-1111-1111-1111-111111111111'),
vsl AS (
  SELECT v.vehicle_id, v.stall_id, v.new_state::text AS nxt, v.previous_state::text AS prev, v.metadata, v.created_at,
         (SELECT max(t.sim_clock_after) FROM ticks t WHERE t.real_started_at <= v.created_at + interval '1 second') AS sim_at
    FROM public.vehicle_state_log v
   WHERE v.depot_id = '11111111-1111-1111-1111-111111111111'
     AND v.created_at >= '2026-09-22 19:40:39+00' AND v.created_at < '2026-09-22 21:40:00+00')
SELECT left(s.vehicle_id::text, 8) AS vehicle, s.stall_code,
       s.started_at::time AS started, s.ended_at::time AS ended, s.stopped_reason,
       m.sim_at::time AS moved, m.prev || '->' || m.nxt AS transition,
       (m.stall_id IS NULL) AS pointer_cleared,
       (m.metadata->>'previous_stall_id' = s.stall_id::text) AS left_from_this_stall
  FROM sess s
  JOIN LATERAL (SELECT * FROM vsl
                 WHERE vsl.vehicle_id = s.vehicle_id AND vsl.sim_at > s.started_at
                   AND vsl.stall_id IS DISTINCT FROM s.stall_id
                 ORDER BY vsl.sim_at, vsl.created_at LIMIT 1) m ON true
 WHERE m.sim_at < s.ended_at - interval '40 seconds';
--   vehicle   stall             started   ended     stopped_reason           moved     transition                           pointer_cleared  left_from_this_stall
--   73e86c55  NASH-L2-STALL-10  19:02:51  19:35:33  fault.thermal_emergency  19:34:52  charging_l2->staged_awaiting_service  true             true
--   5e93a514  NASH-L2-STALL-20  13:04:43  16:55:23  completed                16:53:04  charging_l2->charge_complete_holding  true             true
-- Both: the state trigger wrote stall_id NULL with previous_stall_id = the session's stall, i.e. the
-- vehicle's pointer left the charger, and the session stayed `active` for 41 s / 139 s of sim time.

-- ══ §5 WHAT THIS CHANGES ═════════════════════════════════════════════════════
--
--   1. **G121: no change of state, one change of evidence.** The mechanism stands (`0348` §1–§2); the
--      condition that triggers it did not arise in a full busy_day. The fix stays unapplied until a run
--      produces the condition, and §2 above is now the query that says when one has.
--   2. **`0347` §6.3's product question now has its two paths.** "What moves a vehicle off an L2 charger
--      without closing its OCPP session" = the thermal-fault handler and the charge-complete transition, both
--      of which move the VEHICLE a tick or more before the SESSION is closed. Whether they should close the
--      session first (the physical order: unplug, then move) or refuse the move is still the product call
--      `0347` left open; this file supplies the frequency (2 of 76) and the duration (41 s, 139 s).
--   3. **HW.006 enforcement: still no.** A 2.6% L2 rate of a real divergence is exactly what the rule
--      exists to see; enforcing it would refuse the charge-complete transition, not the defect.
